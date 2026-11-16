import AppKit
import GRDB
import ImageIO
import Photos
import ShotDexKit
import SwiftUI
import UniformTypeIdentifiers

/// Image › Resize… ⌥⌘R (board `MAC_Compress`, FS-18.04 §4a, behaviour of
/// FS-03.07): the selected photos at a smaller size, from wherever they are.
/// Library photos go back to Photos as new pictures; folder, drive and NAS
/// photos go to Pictures › ShotDex Resized (or a folder chosen), never into
/// the folder they came from. Originals stay unless Remove originals is on.
@MainActor
@Observable
final class MacResizeModel: Identifiable {
    /// Where a photo lives, for the table's Source column and the way out.
    enum Kind: Equatable, Sendable {
        case photos
        case file
        case drive
        case server
    }

    struct Row: Identifiable, Equatable, Sendable {
        let id: String
        var name: String
        var sourceName: String
        var kind: Kind
        var width: Int
        var height: Int
        var bytes: Int64
        var isRAW: Bool
        /// Only on a server: there is no file here to resize.
        var isUnreachable: Bool { kind == .server }
    }

    enum Stage: Equatable {
        case editing
        case running(done: Int, total: Int)
        /// The copies are written; the originals are going (Photos asks first).
        case removing
        case finished(Summary)
    }

    struct Summary: Equatable {
        var saved = 0
        var failed = 0
        var skipped = 0
        var stopped = false
        var savedBytes: Int64 = 0
        var originalBytes: Int64 = 0
        var removedOriginals = 0
        var removeFailed = false
        /// Originals on a drive with no Trash: kept, never deleted for good from here.
        var keptNoTrash = 0
        /// The folder the files went to, for Show in Finder.
        var folder: URL?
        var wroteToPhotos = 0
        /// Photos that were not resized, by name, and why.
        var failures: [(name: String, reason: String)] = []
        /// Remove originals was on but the run was stopped: nothing removed.
        var keptBecauseStopped = false
        /// Photos' own dialog said Don't Allow: the user's choice, not a failure.
        var keptInPhotos = false

        static func == (a: Summary, b: Summary) -> Bool {
            a.saved == b.saved && a.failed == b.failed && a.skipped == b.skipped && a.stopped == b.stopped
                && a.removedOriginals == b.removedOriginals && a.removeFailed == b.removeFailed && a.folder == b.folder
                && a.failures.map(\.name) == b.failures.map(\.name)
        }
    }

    let id = UUID()
    let ids: [String]
    private(set) var rows: [Row] = []
    private(set) var isLoading = true
    /// The photo the preview shows.
    var previewId: String? {
        didSet {
            guard previewId != oldValue else { return }
            // The new photo's pictures, or the spinner — never the last photo under the new name.
            before = nil
            after = nil
            previewProblem = nil
            changed()
        }
    }

    var presetId: UUID = ResizePreset.twoK.id { didSet { changed() } }
    var quality: Double = FileExportQuality.defaultValue { didSet { changed() } }
    var format: PhotoOutputFormat = .preserve { didSet { changed() } }
    var metadata: MetadataLevel = .all
    var removesOriginals = false
    /// Pictures › ShotDex Resized, or a folder the user chose (bookmarked).
    private(set) var folder: MacResizeFolder
    var showsInspector = true
    var zoom = MacResizeZoom.actual { didSet { changed() } }

    private(set) var stage = Stage.editing
    private(set) var before: CGImage?
    private(set) var after: CGImage?
    /// Bytes per output pixel, measured by encoding the preview photo at the
    /// target size: the table's estimates scale it to each photo.
    private(set) var bytesPerPixel: Double?
    private(set) var previewProblem: String?
    /// Photos whose file is on a drive with no Trash: Remove originals leaves them.
    private(set) var noTrashIds: Set<String> = []

    let sizes = CompressionPresetStore()
    private let dependencies: MacDependencies
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private let renderer = PhotoRenderService()

    init(ids: [String], dependencies: MacDependencies) {
        self.ids = ids
        self.dependencies = dependencies
        folder = MacResizeFolder.remembered()
    }

    var preset: ResizePreset { sizes.allPresets.first { $0.id == presetId } ?? .twoK }

    // MARK: Loading

    /// A row's small picture (the grid's thumbnail).
    func thumbnail(_ id: String) async -> CGImage? {
        #if DEBUG
        if MacDemoLibrary.isOn { return MacDemoLibrary.picture(for: id) }
        #endif
        return await MacViewerThumbnail.load(id, side: 48, dependencies: dependencies)
    }

    /// Called from the page's `.task`: leaving the page cancels it.
    func load() async {
        let database = dependencies.database
        let ids = ids
        do {
            let read = await Task.detached(priority: .userInitiated) { Self.readRows(ids, database: database) }.value
            guard !Task.isCancelled else { return }
            rows = read
            isLoading = false
            previewId = read.first { !$0.isUnreachable }?.id ?? read.first?.id
            let queries = dependencies.sourceDeletion.makeQueries()
            let fileIds = read.filter { $0.kind == .file || $0.kind == .drive }.map(\.id)
            noTrashIds = await Task.detached(priority: .utility) { () -> Set<String> in
                let copies = (try? queries.copies(photoIds: fileIds)) ?? [:]
                return Set(copies.compactMap { id, targets in
                    targets.first { $0.kind == "file" }.flatMap { if case .permanent = $0.destination { id } else { nil } }
                })
            }.value
        }
    }

    /// Name, size, pixels and where each photo lives, in one read.
    nonisolated static func readRows(_ ids: [String], database: AppDatabase) -> [Row] {
        (try? database.reader.read { db -> [Row] in
            var rows: [Row] = []
            for chunk in stride(from: 0, to: ids.count, by: 500).map({ Array(ids[$0..<min($0 + 500, ids.count)]) }) {
                let marks = chunk.map { _ in "?" }.joined(separator: ",")
                let metadata = try GRDB.Row.fetchAll(db, sql: """
                    SELECT assetId, originalFilename, width, height, fileSize FROM photo_metadata
                    WHERE assetId IN (\(marks)) AND mediaType = 1
                    """, arguments: StatementArguments(chunk))
                let copies = try GRDB.Row.fetchAll(db, sql: """
                    SELECT c.photoId, c.kind, s.name AS sourceName, s.kind AS sourceKind FROM photo_copies c
                    LEFT JOIN sources s ON s.id = c.sourceId
                    WHERE c.photoId IN (\(marks)) AND c.missingSince IS NULL
                    ORDER BY c.kind = 'file' DESC, c.kind = 'photos' DESC
                    """, arguments: StatementArguments(chunk))
                var firstCopy: [String: GRDB.Row] = [:]
                for copy in copies where firstCopy[copy["photoId"]] == nil { firstCopy[copy["photoId"]] = copy }
                var byId: [String: GRDB.Row] = [:]
                for row in metadata { byId[row["assetId"]] = row }
                for id in chunk {
                    guard let meta = byId[id] else { continue }
                    let name: String = meta["originalFilename"] ?? id
                    let copy = firstCopy[id]
                    let kind: Kind
                    switch copy?["kind"] as String? {
                    case "file": kind = (copy?["sourceKind"] as String?) == "drive" ? .drive : .file
                    case "server": kind = .server
                    default: kind = .photos
                    }
                    let source = copy?["sourceName"] as String?
                        ?? String(localized: "Photos Library", comment: "Mac Resize: the Photos library as a source")
                    rows.append(Row(id: id, name: name, sourceName: source, kind: kind,
                                    width: meta["width"] ?? 0, height: meta["height"] ?? 0,
                                    bytes: meta["fileSize"] ?? 0,
                                    isRAW: PairingRule.isRaw(name)))
                }
            }
            return rows
        }) ?? []
    }

    // MARK: Numbers

    /// The pixel size a photo comes out at.
    func target(_ row: Row) -> CGSize {
        guard row.width > 0, row.height > 0 else { return .zero }
        return preset.targetPixelSize(sourceWidth: row.width, sourceHeight: row.height)
    }

    /// About how many bytes the resized file takes.
    func estimate(_ row: Row) -> Int64? {
        guard let bytesPerPixel, !row.isUnreachable else { return nil }
        let size = target(row)
        return Int64((Double(size.width * size.height) * bytesPerPixel).rounded())
    }

    var reachable: [Row] { rows.filter { !$0.isUnreachable } }
    var totalBytes: Int64 { reachable.reduce(0) { $0 + $1.bytes } }
    var totalEstimate: Int64? {
        guard bytesPerPixel != nil else { return nil }
        return reachable.reduce(Int64(0)) { $0 + (estimate($1) ?? 0) }
    }

    var sourceCount: Int { Set(rows.map(\.sourceName)).count }

    /// "3 from Photos Library go to Recently Deleted. 4 folder and drive files
    /// go to the Trash." — and what is left alone: a drive with no Trash
    /// (never deleted for good from here), a photo only on a server.
    var removalWords: String {
        let photos = reachable.filter { $0.kind == .photos }.count
        let files = reachable.filter { ($0.kind == .file || $0.kind == .drive) && !noTrashIds.contains($0.id) }.count
        let kept = reachable.filter { noTrashIds.contains($0.id) }.count
        let servers = rows.filter { $0.kind == .server }
        var parts: [String] = []
        if photos > 0 {
            parts.append(String(localized: "\(photos) from Photos Library go to Recently Deleted — Photos asks you first.",
                                comment: "Mac Resize: where removed Photos originals go"))
        }
        if files > 0 {
            parts.append(String(localized: "\(files) folder and drive files go to the Trash.",
                                comment: "Mac Resize: where removed folder originals go"))
        }
        if kept > 0 {
            parts.append(String(localized: "\(kept) on a drive with no Trash are kept.",
                                comment: "Mac Resize: originals on a drive without a Trash are never deleted from Resize"))
        }
        if let server = servers.first {
            parts.append(String(localized: "\(servers.count) only on \(server.sourceName) is skipped — it isn’t on this Mac.",
                                comment: "Mac Resize: server-only photos are not resized or removed"))
        }
        return parts.joined(separator: " ")
    }

    var commandTitle: String {
        let count = reachable.count
        if removesOriginals {
            return count == 1
                ? String(localized: "Resize and Remove Original", comment: "Mac Resize: the commit button, one photo, removing it")
                : String(localized: "Resize \(count) Photos and Remove Originals", comment: "Mac Resize: the commit button, removing originals")
        }
        return count == 1
            ? String(localized: "Resize 1 Photo", comment: "Mac Resize: the commit button, one photo")
            : String(localized: "Resize \(count) Photos", comment: "Mac Resize: the commit button")
    }

    /// The format a photo is written in: JPEG or HEIC as asked; Same as
    /// Original keeps HEIC as HEIC and makes everything else — RAW, PNG,
    /// TIFF — JPEG (FS-03.07 §2).
    func outputFormat(_ row: Row) -> PhotoOutputFormat {
        KitExportRenderer.format(for: FileExportItem(id: row.id, filename: row.name, captureDate: Date(), kind: .photo, files: []),
                                 requested: format)
    }

    // MARK: Preview

    private func changed() {
        guard stage == .editing else { return }
        refreshPreview()
    }

    /// The preview photo before and after, and the bytes per pixel the
    /// estimates scale from — off the main actor, the latest change wins.
    func refreshPreview() {
        previewTask?.cancel()
        guard let row = rows.first(where: { $0.id == previewId }) else { return }
        guard !row.isUnreachable else {
            before = nil
            after = nil
            previewProblem = String(localized: "This photo is only on \(row.sourceName). Its original isn’t on this Mac.",
                                    comment: "Mac Resize: a server-only photo has no preview")
            return
        }
        let preset = preset, quality = quality, format = outputFormat(row), zoom = zoom
        let dependencies = dependencies
        let renderer = renderer
        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            guard let url = await MacResizeSource.file(for: row, dependencies: dependencies) else {
                guard !Task.isCancelled, previewId == row.id else { return }
                previewProblem = String(localized: "ShotDex can’t read this photo’s original right now.", comment: "Mac Resize: preview failed")
                return
            }
            // A Photos original is a temporary copy: gone once the preview is made.
            defer { if row.kind == .photos { MacResizeSource.discard(url) } }
            let database = dependencies.database
            let id = row.id
            let work = Task.detached(priority: .userInitiated) { () -> MacResizePreview.Made? in
                let recipe = (try? PhotoRecipeStore(database: database).recipe(photoId: id)) ?? .identity
                return await MacResizePreview.make(url, renderer: renderer, recipe: recipe, preset: preset, quality: quality,
                                                   format: format, zoom: zoom)
            }
            let made = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard !Task.isCancelled, previewId == row.id else { return }
            if let made {
                before = made.before
                after = made.after
                bytesPerPixel = made.bytesPerPixel
                previewProblem = nil
            } else {
                previewProblem = String(localized: "ShotDex can’t read this photo’s original right now.", comment: "Mac Resize: preview failed")
            }
        }
    }

    // MARK: Folder

    /// A folder from the system picker; its bookmark is made off the main actor.
    func choose(_ url: URL) {
        Task {
            guard let chosen = await Task.detached(priority: .userInitiated, operation: { MacResizeFolder(picked: url) }).value else { return }
            folder = chosen
            chosen.remember()
        }
    }

    func useDefaultFolder() {
        folder = .shotDexResized
        folder.remember()
    }

    // MARK: Running

    /// Every reachable photo, one at a time off the main actor (memory stays
    /// at one photo); a failure moves on to the next. Not modal: the page
    /// shows "Resizing 3 of 8" with Stop, and Activity has a row.
    func run() {
        guard stage == .editing else { return }
        let todo = reachable
        guard !todo.isEmpty else { return }
        // The run has the machine: no preview renders beside it.
        previewTask?.cancel()
        let preset = preset, quality = quality, metadata = metadata, removes = removesOriginals
        let formats = Dictionary(uniqueKeysWithValues: todo.map { ($0.id, outputFormat($0)) })
        let dependencies = dependencies
        let folder = folder
        let activity = dependencies.exports
        let runId = activity.begin(title: String(localized: "Resizing \(todo.count) photos", comment: "Mac Activity › Background: a Resize run"),
                                   detail: String(localized: "0 of \(todo.count)", comment: "Mac Activity › Background: progress"),
                                   name: String(localized: "\(todo.count) photos", comment: "Mac Activity: what a resize run is of"),
                                   isResize: true)
        stage = .running(done: 0, total: todo.count)
        runTask = Task {
            var summary = Summary(skipped: rows.count - todo.count)
            let writer = MacResizeWriter(folder: folder, dependencies: dependencies)
            var done: [String] = []
            for (index, row) in todo.enumerated() {
                if Task.isCancelled { summary.stopped = true; break }
                stage = .running(done: index, total: todo.count)
                activity.update(runId, detail: String(localized: "\(index + 1) of \(todo.count)", comment: "Mac Activity › Background: progress"))
                do {
                    let result = try await writer.write(row, preset: preset, quality: quality, format: formats[row.id] ?? .jpeg, metadata: metadata)
                    summary.saved += 1
                    summary.savedBytes += result.bytes
                    summary.originalBytes += row.bytes
                    if result.toPhotos { summary.wroteToPhotos += 1 } else { summary.folder = result.folder }
                    done.append(row.id)
                } catch {
                    if error is CancellationError || Task.isCancelled {
                        summary.stopped = true
                        break
                    }
                    summary.failed += 1
                    summary.failures.append((row.name, MacResizeWords.reason(error)))
                }
            }
            if Task.isCancelled { summary.stopped = true }
            if removes, summary.stopped, !done.isEmpty { summary.keptBecauseStopped = true }
            // Only photos whose copy was written lose their original — and none after Stop.
            if removes, !done.isEmpty, !summary.stopped {
                stage = .removing
                activity.update(runId, detail: String(localized: "Removing originals…", comment: "Mac Activity › Background: a Resize run removes originals"))
                let removable = todo.filter { done.contains($0.id) && !noTrashIds.contains($0.id) }
                summary.keptNoTrash = todo.filter { done.contains($0.id) && noTrashIds.contains($0.id) }.count
                do {
                    let removal = try await Self.removeOriginals(removable, dependencies: dependencies)
                    summary.removedOriginals = removal.recentlyDeleted + removal.trashedFiles
                    summary.keptInPhotos = removal.photosCancelled
                    summary.removeFailed = removal.failedFiles > 0 || removal.failure != nil
                } catch {
                    summary.removeFailed = true
                }
            }
            // Said in Activity too: the page may be gone by now.
            let problems = summary.failed > 0 || summary.removeFailed
            activity.finish(runId,
                            title: problems ? String(localized: "Resize finished with problems", comment: "Mac Activity › Background: a Resize run ended with failures")
                                            : String(localized: "Resized \(summary.saved) photos", comment: "Mac Activity › Background: a Resize run ended"),
                            detail: MacResizeWords.activityLine(summary),
                            failed: problems)
            stage = .finished(summary)
            // The outcome is said in the inspector: it is shown.
            showsInspector = true
        }
    }

    /// Stop: the photo being written finishes or is dropped; what is saved stays.
    func stop() { runTask?.cancel() }

    /// The page went: its preview work stops. A run keeps going (Activity says how it ends).
    func close() { previewTask?.cancel() }

    /// The copy each photo was resized from — its Photos asset (Photos asks,
    /// then Recently Deleted) or its folder or drive file (the Trash) — by
    /// the Move to Trash path. Other copies of the photo stay (FS-19.04 §1).
    nonisolated private static func removeOriginals(_ rows: [Row], dependencies: MacDependencies) async throws -> DeletionService.Summary {
        let context = await dependencies.sourceDeletion
        let queries = context.makeQueries()
        let copies = try queries.copies(photoIds: rows.map(\.id))
        var targets: [[DeletionTarget]] = []
        var alsoPhotos: [String] = []
        for row in rows {
            let wanted = row.kind == .photos ? "photos" : "file"
            if let target = copies[row.id]?.first(where: { $0.kind == wanted }) {
                // Never for good from here: a drive with no Trash keeps its file.
                if case .permanent = target.destination { continue }
                targets.append([target])
            } else if row.kind == .photos {
                alsoPhotos.append(row.id)
            }
        }
        return try await context.makeService().run(targets, alsoPhotos: alsoPhotos)
    }
}

/// 100% shows pixels as they are; Fit shows the whole photo.
enum MacResizeZoom: String, CaseIterable, Identifiable {
    case actual
    case fit
    var id: String { rawValue }

    var title: String {
        switch self {
        case .actual: "100%"
        case .fit: String(localized: "Whole Photo", comment: "Mac Resize: the preview shows the whole photo")
        }
    }
}

// MARK: - Where the files go

/// Pictures › ShotDex Resized, or a folder the user picked.
struct MacResizeFolder: Equatable, Sendable {
    var name: String
    /// Nil: Pictures › ShotDex Resized.
    var bookmark: Data?

    static let shotDexResized = MacResizeFolder(
        name: String(localized: "ShotDex Resized", comment: "Mac Resize: the default folder in Pictures"), bookmark: nil)

    private static let key = "mac.resize.folder"

    init(name: String, bookmark: Data?) {
        self.name = name
        self.bookmark = bookmark
    }

    init?(picked url: URL) {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
        guard let bookmark = try? url.bookmarkData(options: .withSecurityScope) else { return nil }
        self.init(name: url.lastPathComponent, bookmark: bookmark)
    }

    static func remembered() -> MacResizeFolder {
        guard let bookmark = UserDefaults.standard.data(forKey: key),
              let name = UserDefaults.standard.string(forKey: key + ".name") else { return .shotDexResized }
        return MacResizeFolder(name: name, bookmark: bookmark)
    }

    func remember() {
        UserDefaults.standard.set(bookmark, forKey: Self.key)
        UserDefaults.standard.set(bookmark == nil ? nil : name, forKey: Self.key + ".name")
    }

    /// The folder on disk: the bookmark's, or Pictures › ShotDex Resized in
    /// the user's own home (not the sandbox container's).
    nonisolated func resolved() -> URL? {
        if let bookmark {
            var stale = false
            return try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale)
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ShotDexResizeTest") {
            return FileManager.default.temporaryDirectory.appendingPathComponent("ShotDexResizeTest", isDirectory: true)
        }
        #endif
        guard let home = getpwuid(getuid())?.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: home)).appendingPathComponent("Pictures/ShotDex Resized", isDirectory: true)
    }
}

// MARK: - Reading originals

enum MacResizeSource {
    /// A Photos original written for this run or preview: removed after use.
    nonisolated static func discard(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// The original's file: a folder or drive copy on this Mac, the demo's
    /// picture, or a Photos picture written to a temporary file.
    @MainActor
    static func file(for row: MacResizeModel.Row, dependencies: MacDependencies) async -> URL? {
        #if DEBUG
        if MacDemoLibrary.isOn {
            return await Task.detached(operation: { MacDemoLibrary.pictureFiles(for: [row.id]).first }).value
        }
        #endif
        switch row.kind {
        case .file, .drive:
            guard let file = await MacPhotoFiles.resolve(row.id, dependencies: dependencies), !file.isPlaceholder else { return nil }
            return file.url
        case .photos:
            return await MacPhotosExport.write(assetIds: [row.id]).first
        case .server:
            return nil
        }
    }
}

// MARK: - Preview pictures

enum MacResizePreview {
    /// `@unchecked`: CGImage is immutable; a Made is never changed after make().
    struct Made: @unchecked Sendable {
        let before: CGImage
        let after: CGImage
        let bytesPerPixel: Double
    }

    /// The photo before and after: at 100% the middle of it at its own pixels
    /// beside the same part of the resized file blown up to match; at Fit the
    /// whole of both. The resized one is the real file — encoded at the
    /// quality, read back — so the artefacts are the ones that will be saved.
    /// One context for every preview: making one per change is costly.
    private static let context = CIContext()

    static func make(_ url: URL, renderer: PhotoRenderService, recipe: PhotoEditRecipe, preset: ResizePreset, quality: Double,
                     format: PhotoOutputFormat, zoom: MacResizeZoom) async -> Made? {
        guard let source = try? await renderer.inspectSource(at: url),
              let full = try? await renderer.render(source: source, recipe: recipe), !Task.isCancelled else { return nil }
        let resized = preset.kind == .original ? full : await renderer.resize(full, preset: preset, cropAnchor: .center)
        guard !Task.isCancelled else { return nil }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("resize-preview-\(UUID().uuidString).\(format.fileExtension)")
        defer { try? FileManager.default.removeItem(at: file) }
        guard (try? await renderer.write(resized, to: file, format: format, quality: quality, metadata: .noMetadata)) != nil,
              let bytes = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize),
              let imageSource = CGImageSourceCreateWithURL(file as CFURL, nil),
              let encoded = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else { return nil }
        let context = Self.context
        guard !Task.isCancelled else { return nil }
        let original = full.image
        let pixels = Double(encoded.width * encoded.height)
        let bytesPerPixel = pixels > 0 ? Double(bytes) / pixels : 0
        let window = CGSize(width: 2200, height: 760)
        switch zoom {
        case .fit:
            let scale = min(1, min(window.width / original.extent.width, window.height / original.extent.height))
            let small = original.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            guard let before = context.createCGImage(small, from: small.extent.integral, format: .RGBA8, colorSpace: full.colorSpace) else { return nil }
            let afterImage = CIImage(cgImage: encoded)
            let afterScale = min(window.width / afterImage.extent.width, window.height / afterImage.extent.height)
            let fitted = afterImage.transformed(by: CGAffineTransform(scaleX: afterScale, y: afterScale))
            guard let after = context.createCGImage(fitted, from: fitted.extent.integral) else { return nil }
            return Made(before: before, after: after, bytesPerPixel: bytesPerPixel)
        case .actual:
            let crop = CGRect(x: original.extent.midX - window.width / 2, y: original.extent.midY - window.height / 2,
                              width: window.width, height: window.height).intersection(original.extent).integral
            guard let before = context.createCGImage(original, from: crop, format: .RGBA8, colorSpace: full.colorSpace) else { return nil }
            // The same part of the photo in the resized file, scaled back up to the crop's size.
            let ratio = CGFloat(encoded.width) / original.extent.width
            let afterImage = CIImage(cgImage: encoded)
            let part = CGRect(x: (crop.minX - original.extent.minX) * ratio, y: (crop.minY - original.extent.minY) * ratio,
                              width: crop.width * ratio, height: crop.height * ratio).intersection(afterImage.extent)
            let up = afterImage.cropped(to: part)
                .transformed(by: CGAffineTransform(translationX: -part.minX, y: -part.minY))
                .transformed(by: CGAffineTransform(scaleX: crop.width / max(1, part.width), y: crop.height / max(1, part.height)))
            guard let after = context.createCGImage(up, from: CGRect(origin: .zero, size: crop.size)) else { return nil }
            return Made(before: before, after: after, bytesPerPixel: bytesPerPixel)
        }
    }
}

// MARK: - Writing

/// One resized photo: rendered with its ShotDex edit, at the preset, and
/// written — back into Photos for a Photos picture, into the folder for the
/// rest. A name already in the folder gets " (2)", " (3)"….
struct MacResizeWriter {
    struct Written {
        let bytes: Int64
        let toPhotos: Bool
        let folder: URL?
    }

    let folder: MacResizeFolder
    let dependencies: MacDependencies
    private let renderer = PhotoRenderService()

    init(folder: MacResizeFolder, dependencies: MacDependencies) {
        self.folder = folder
        self.dependencies = dependencies
    }

    struct SameFolder: Error {}

    @MainActor
    func write(_ row: MacResizeModel.Row, preset: ResizePreset, quality: Double, format: PhotoOutputFormat,
               metadata: MetadataLevel) async throws -> Written {
        guard let source = await MacResizeSource.file(for: row, dependencies: dependencies) else {
            // Stop during an iCloud download reads as Stop, not as an unreadable photo.
            try Task.checkCancellation()
            throw PhotoEditingError.missingSource
        }
        // A Photos original is a temporary copy: removed once used, off the main actor.
        defer { if row.kind == .photos { Task.detached { MacResizeSource.discard(source) } } }
        let database = dependencies.database
        let id = row.id
        let stem = (row.name as NSString).deletingPathExtension
        let fileName = "\(stem).\(format.fileExtension)"
        let renderer = renderer
        // A Photos picture goes back to Photos (the demo writes it to a folder of its own).
        var toPhotos = row.kind == .photos
        #if DEBUG
        if MacDemoLibrary.isOn { toPhotos = false }
        #endif
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("ShotDexResize", isDirectory: true)
        let rendered = staging.appendingPathComponent("\(UUID().uuidString).\(format.fileExtension)")
        // Stop reaches the render: the detached work is cancelled with the run.
        let work = Task.detached(priority: .userInitiated) {
            try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let recipe = (try? PhotoRecipeStore(database: database).recipe(photoId: id)) ?? .identity
            let info = try await renderer.inspectSource(at: source)
            var result = try await renderer.render(source: info, recipe: recipe)
            if preset.kind != .original { result = await renderer.resize(result, preset: preset, cropAnchor: .center) }
            try Task.checkCancellation()
            try await renderer.write(result, to: rendered, format: format, quality: quality, metadata: metadata)
            try Task.checkCancellation()
            return (try? rendered.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        }
        let bytes: Int64
        do {
            bytes = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
            // Stop that landed after the render: nothing more is saved.
            try Task.checkCancellation()
        } catch {
            Task.detached { try? FileManager.default.removeItem(at: rendered) }
            throw error
        }
        if toPhotos {
            do {
                _ = try await dependencies.photoLibrary.saveImageFile(at: rendered, filename: fileName)
            } catch {
                try? FileManager.default.removeItem(at: rendered)
                throw error
            }
            return Written(bytes: bytes, toPhotos: true, folder: nil)
        }
        let folder = folder
        let placed = try await Task.detached(priority: .userInitiated) { () -> URL in
            let manager = FileManager.default
            // The bookmark is resolved here, off the main actor: a sleeping share can take seconds.
            guard let target = folder.resolved() else {
                try? manager.removeItem(at: rendered)
                throw CocoaError(.fileNoSuchFile)
            }
            let isAccessing = target.startAccessingSecurityScopedResource()
            defer { if isAccessing { target.stopAccessingSecurityScopedResource() } }
            // Never into the folder the photo came from (FS-18.04 §4a).
            if target.standardizedFileURL.resolvingSymlinksInPath().path
                == source.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path {
                try? manager.removeItem(at: rendered)
                throw SameFolder()
            }
            try manager.createDirectory(at: target, withIntermediateDirectories: true)
            let existing = Set(((try? manager.contentsOfDirectory(atPath: target.path)) ?? []).map { $0.lowercased() })
            var name = fileName
            if existing.contains(name.lowercased()) {
                let number = FileExportPlan.firstFreeNumber { existing.contains("\(stem) (\($0)).\(format.fileExtension)".lowercased()) }
                name = "\(stem) (\(number)).\(format.fileExtension)"
            }
            let destination = target.appendingPathComponent(name)
            do {
                try manager.moveItem(at: rendered, to: destination)
            } catch {
                try? manager.removeItem(at: rendered)
                throw error
            }
            return destination
        }.value
        return Written(bytes: bytes, toPhotos: false, folder: placed.deletingLastPathComponent())
    }
}
