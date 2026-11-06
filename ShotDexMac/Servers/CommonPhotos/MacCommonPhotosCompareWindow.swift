import GRDB
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// What the index shows of one copy on a server source: its preview and the
/// capture date it read (FS-19.08 §6d). Nil when no source holds the copy,
/// or the index has not reached it.
enum MacCommonPhotosPreview {
    struct Indexed: Sendable {
        let image: CGImage?
        let captured: Date?
    }

    static func load(serverPath: String, sources: [(source: SourceStore.Source, connection: FileServer)],
                     database: AppDatabase, maxPixelSize: Int) async -> Indexed? {
        #if DEBUG
        // `-ShotDexCommonPhotosCompareSkipIndex`: as if nothing were indexed, so Compare downloads (screenshots).
        if ProcessInfo.processInfo.arguments.contains("-ShotDexCommonPhotosCompareSkipIndex"), maxPixelSize > 96 { return nil }
        #endif
        guard let holder = sources.first(where: { CommonPhotosSelection.contains($0.connection.folder, serverPath) }) else { return nil }
        let root = ServerUploadPath.normalizedFolder(holder.connection.folder)
        let relative = root.isEmpty ? serverPath : String(serverPath.dropFirst(root.count + 1))
        let key = FolderSourceIndexer.pathKey(relative)
        let sourceId = holder.source.id
        let found = try? await database.reader.read { db -> (copyId: String, captured: Int?)? in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT c.id, m.creationDate FROM photo_copies c LEFT JOIN photo_metadata m ON m.assetId = c.photoId
                WHERE c.sourceId = ? AND c.relativePathKey = ? AND c.missingSince IS NULL
                """, arguments: [sourceId, key]) else { return nil }
            return (row["id"], row["creationDate"])
        }
        guard let found = found ?? nil else { return nil }
        let url = FolderThumbnails.standard.url(copyId: found.copyId)
        let image = await Task.detached {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil as CGImage? }
            return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                                                                   kCGImageSourceCreateThumbnailFromImageAlways: true] as CFDictionary)
        }.value
        return Indexed(image: image, captured: found.captured.map { Date(timeIntervalSince1970: TimeInterval($0)) })
    }
}


/// The Compare window's state (FS-19.08 §6d): the sheet's scan, the row
/// shown, and what each side has loaded. One for the app; the sheet that
/// opens the window sets it, and closes it when the sheet goes.
@MainActor
@Observable
final class MacCommonPhotosCompareModel {
    let scan: CommonPhotosScanModel
    let database: AppDatabase
    let sources: [(source: SourceStore.Source, connection: FileServer)]
    /// Its own session, behind every other call on the connection
    /// (`ConnectionLock.Priority.compare`); nil in tests and previews.
    @ObservationIgnored private let client: (any RemoteFileClient)?
    /// The server's name, for "Downloading from NAS Home…".
    let serverName: String
    @ObservationIgnored let cache: CompareFileCache
    private(set) var compare: CommonPhotosCompare
    /// What the two sides of the row shown show, by copy path; only those
    /// two are kept.
    private(set) var previews: [String: MacCommonPhotosPreview.Indexed] = [:]
    /// Sides downloading: bytes read so far.
    private(set) var downloading: [String: Int64] = [:]
    /// Sides whose download failed, with the sentence to show.
    private(set) var failures: [String: String] = [:]
    /// Sides read whole that this Mac cannot draw (a RAW it does not know).
    private(set) var noPreview: Set<String> = []
    /// Sides drawn from the whole file, not the index's 400-pixel preview.
    private(set) var fullSize: Set<String> = []
    /// Video sides, played from the server where they lie, by copy path.
    @ObservationIgnored private var videoStreams: [String: RemoteVideoStream] = [:]
    /// Both sides' videos read: played as one (AC-185).
    private(set) var videoPair: MacCommonPhotosVideoPair?
    /// Bumped by Try Again: the sides load again.
    private(set) var attempt = 0
    /// The one login of this session, shared by every load.
    @ObservationIgnored private var connecting: Task<Void, Error>?
    /// Closed with the sheet: no load starts or writes after.
    @ObservationIgnored private var isClosed = false
    /// Which load owns each side's progress: a cancelled one never clears
    /// or moves the next one's.
    @ObservationIgnored private var loadTokens: [String: UUID] = [:]
    var zoom = Zoom.fit

    enum Zoom: String, CaseIterable, Identifiable {
        case fit, actual
        var id: Self { self }
    }

    /// The index's preview, 400 pixels on its long edge.
    static let previewPixels = FolderThumbnails.longEdge
    /// A downloaded copy is drawn at most this big: enough for 100% on a
    /// 1180-point window side, without decoding a 60-megapixel RAW whole.
    nonisolated static let downloadedPixels = 4_096

    init(scan: CommonPhotosScanModel, database: AppDatabase,
         sources: [(source: SourceStore.Source, connection: FileServer)], client: (any RemoteFileClient)? = nil,
         serverName: String = "", cache: CompareFileCache = CompareFileCache(), showing rowId: String) {
        self.scan = scan
        self.database = database
        self.sources = sources
        self.client = client
        self.serverName = serverName
        self.cache = cache
        compare = CommonPhotosCompare(rowIds: scan.rows.map(\.id), showing: rowId)
    }

    var row: CommonPhotosScanModel.Row? { compare.currentId.flatMap { id in scan.rows.first { $0.id == id } } }

    var copies: [CommonPhotosCompare.Copy] {
        guard let id = compare.currentId, let photo = scan.photo(forRow: id) else { return [] }
        return CommonPhotosCompare.copies(of: photo, folders: scan.folders)
    }

    /// The two sides: the first folder's copy, and the one the popup picks.
    var sides: [CommonPhotosCompare.Copy] {
        let all = copies
        guard all.count > 1 else { return all }
        return [all[0], all[min(compare.rightCopy, all.count - 1)]]
    }

    /// What `loadSides` runs for: the row, the right side picked, Try Again.
    var sidesKey: String { "\(compare.currentId ?? "")|\(compare.rightCopy)|\(attempt)" }

    /// The row can be checked or unchecked: a Copy skips what is already
    /// in the destination, so that row is no choice (as in the sheet).
    var canChoose: Bool {
        guard let row else { return false }
        if case .alreadyThere? = row.landing, scan.action == .copy { return false }
        return true
    }

    func show(_ rowId: String) {
        compare = CommonPhotosCompare(rowIds: scan.rows.map(\.id), showing: rowId)
    }

    func next() { compare.next() }
    func previous() { compare.previous() }

    func pickRight(_ index: Int) { compare.rightCopy = index }

    /// The list under the window changed: follow it.
    func listChanged() { compare.update(rowIds: scan.rows.map(\.id)) }

    func setIncluded(_ included: Bool) {
        guard canChoose, let id = compare.currentId else { return }
        scan.setIncluded(included, rows: [id])
    }

    func tryAgain() {
        failures = [:]
        attempt += 1
    }

    /// Loads the two sides of the row shown and lets go of every other: the
    /// index's preview first when it has one, then the whole file, downloaded
    /// behind every other call on the connection, in its place (AC-182…184). A cancelled
    /// load (the row changed) writes nothing and leaves no part file.
    func loadSides() async {
        // Before the guard: a list emptied by a rescan stops the sound too.
        videoPair?.stop()
        videoPair = nil
        let sides = sides
        let paths = Set(sides.map(\.path))
        // Before the guard too: a list emptied by a rescan stops the reads.
        for (path, stream) in videoStreams where !paths.contains(path) { stream.cancel() }
        videoStreams = videoStreams.filter { paths.contains($0.key) }
        guard !isClosed, let sha256 = row?.sha256 else { return }
        previews = previews.filter { paths.contains($0.key) }
        downloading = downloading.filter { paths.contains($0.key) }
        // A failure belongs to its row: another row's never shows or blocks.
        failures = failures.filter { paths.contains($0.key) }
        noPreview = noPreview.intersection(paths)
        fullSize = fullSize.intersection(paths)
        cache.pin(paths: sides.map { ($0.path, sha256) })
        let pictures = sides.filter { side in
            !fullSize.contains(side.path) && videoStreams[side.path] == nil
                && !noPreview.contains(side.path) && failures[side.path] == nil
        }
        // A video is played from the server, never from the index's still
        // and never downloaded: any size plays (§6d).
        for side in pictures where Self.isVideo(side.path) { await stream(side) }
        // Both sides' index previews first, so neither waits on the other's
        // download; then each whole file replaces its preview.
        for side in pictures where !Self.isVideo(side.path) && previews[side.path] == nil {
            if let indexed = await MacCommonPhotosPreview.load(serverPath: side.path, sources: sources, database: database,
                                                               maxPixelSize: Self.previewPixels), indexed.image != nil {
                guard !Task.isCancelled else { return }
                previews[side.path] = indexed
            }
        }
        for side in pictures where !Self.isVideo(side.path) {
            guard !Task.isCancelled else { return }
            await download(side, sha256: sha256)
        }
        // Two videos: one transport for both.
        guard !Task.isCancelled, !isClosed else { return }
        if sides.count == 2, let left = videoStreams[sides[0].path], let right = videoStreams[sides[1].path] {
            videoPair = MacCommonPhotosVideoPair(left: left.asset, right: right.asset)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ShotDexCommonPhotosComparePlay") { videoPair?.playFromSixTenths() }
            #endif
        } else {
            // One video with nothing to play against: said, not a spinner.
            for side in sides where videoStreams[side.path] != nil { noPreview.insert(side.path) }
        }
    }

    /// A video side: the session's login, then a stream AVFoundation reads
    /// from as it plays.
    private func stream(_ side: CommonPhotosCompare.Copy) async {
        guard let client else {
            failures[side.path] = String(localized: "The connection for this copy is gone.",
                                         comment: "Common photos compare: no client to read the copy")
            return
        }
        do {
            if connecting == nil { connecting = Task { try await client.connect() } }
            do {
                try await connecting?.value
            } catch {
                connecting = nil
                throw error
            }
        } catch {
            guard !Task.isCancelled, !isClosed, !(error is CancellationError) else { return }
            failures[side.path] = (error as? RemoteFileError)?.errorDescription ?? error.localizedDescription
            return
        }
        guard !Task.isCancelled, !isClosed else { return }
        videoStreams[side.path] = RemoteVideoStream(client: client, path: side.path, size: side.size)
    }

    private func download(_ side: CommonPhotosCompare.Copy, sha256: String) async {
        guard let client else {
            failures[side.path] = String(localized: "The connection for this copy is gone.",
                                         comment: "Common photos compare: no client to read the copy")
            return
        }
        // Both copies of the row stay pinned, so together they fit the cap
        // or neither side is read (§6d, at most 2 GB).
        guard sides.reduce(0, { $0 + $1.size }) <= cache.capacity else {
            failures[side.path] = String(localized: "This copy is too large to show here.",
                                         comment: "Common photos compare: the copy is bigger than the cache")
            return
        }
        let directory = cache.directory
        let loader = CommonPhotosCompareLoader(client: client, cache: cache, freeBytes: {
            let url = FileManager.default.fileExists(atPath: directory.path) ? directory : directory.deletingLastPathComponent()
            return (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
                .volumeAvailableCapacityForImportantUsage ?? .max
        })
        let path = side.path
        let file: URL
        let token = UUID()
        loadTokens[path] = token
        downloading[path] = 0
        defer {
            if loadTokens[path] == token {
                loadTokens[path] = nil
                downloading[path] = nil
            }
        }
        do {
            if cache.cached(path: path, sha256: sha256) == nil {
                if connecting == nil { connecting = Task { try await client.connect() } }
                do {
                    try await connecting?.value
                } catch {
                    connecting = nil
                    throw error
                }
            }
            guard !isClosed else { return }
            let outcome = try await loader.load(path: path, sha256: sha256, size: side.size, progress: { [weak self] bytes in
                Task { @MainActor in
                    // Hops arrive in any order: the bar never goes back.
                    guard let self, self.loadTokens[path] == token else { return }
                    self.downloading[path] = max(self.downloading[path] ?? 0, bytes)
                }
            })
            guard !Task.isCancelled, !isClosed else { return }
            switch outcome {
            case .file(let url): file = url
            case .changed:
                failures[path] = String(localized: "This copy changed on the server since the scan.",
                                        comment: "Common photos compare: the downloaded copy does not match")
                return
            case .noRoom:
                failures[path] = String(localized: "Not enough space on this Mac to show this copy.",
                                        comment: "Common photos compare: no room to download a copy")
                return
            }
        } catch {
            guard !Task.isCancelled, !isClosed, !(error is CancellationError) else { return }
            // The session went: the next load logs in again.
            if (error as? RemoteFileError)?.stopsBatch == true { connecting = nil }
            failures[path] = (error as? RemoteFileError)?.errorDescription ?? error.localizedDescription
            return
        }
        let drawn = await Task.detached { Self.draw(file) }.value
        guard !Task.isCancelled else { return }
        if let drawn {
            // The index read the capture date when the file did not say.
            previews[side.path] = MacCommonPhotosPreview.Indexed(image: drawn.image,
                                                                 captured: drawn.captured ?? previews[side.path]?.captured)
            fullSize.insert(side.path)
        } else if previews[side.path] == nil {
            noPreview.insert(side.path)
        }
    }

    /// The picture and capture date of a whole file; nil when ImageIO
    /// cannot draw it.
    nonisolated private static func draw(_ file: URL) -> MacCommonPhotosPreview.Indexed? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let wanted = min(downloadedPixels, max(width, height))
        func thumbnail(always: Bool) -> CGImage? {
            CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceThumbnailMaxPixelSize: downloadedPixels,
                always ? kCGImageSourceCreateThumbnailFromImageAlways : kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
        }
        // A RAW's own preview when it is big enough: no 60-megapixel decode.
        // A HEIC's or JPEG's embedded thumbnail is often 320 pixels: then the
        // image itself is drawn.
        var image = thumbnail(always: false)
        if let small = image, max(small.width, small.height) < wanted { image = thumbnail(always: true) ?? small }
        guard let image else { return nil }
        let exif = properties?[kCGImagePropertyExifDictionary] as? [CFString: Any]
        // With its offset when the camera wrote one, as the index reads it.
        let captured = exif.flatMap { EmbeddedPreview.captureDate(fromEXIF: $0) }
        return MacCommonPhotosPreview.Indexed(image: image, captured: captured)
    }

    nonisolated static func isVideo(_ path: String) -> Bool {
        UTType(filenameExtension: (path as NSString).pathExtension)?.conforms(to: .movie) == true
    }

    /// The sheet or the window went: no more loads, the session ends, the
    /// files go.
    func close() async {
        isClosed = true
        videoPair?.stop()
        videoPair = nil
        videoStreams.values.forEach { $0.cancel() }
        videoStreams = [:]
        // The files go first: the logoff may wait behind the scan's calls.
        cache.removeAll()
        guard let connecting, let client else { return }
        self.connecting = nil
        if (try? await connecting.value) != nil { await client.disconnect() }
    }
}

/// FS-19.08 §6d, board `MAC_CommonPhotosCompare`: two copies of a Same photo
/// side by side. Tier D: always dark. ↑↓ step through the rows (←→ too when
/// the picture fits), Esc closes; the bar below says the SHA-256 they share.
struct MacCommonPhotosCompareWindow: View {
    static let id = "commonPhotosCompare"
    static let size = CGSize(width: 1180, height: 760)

    @Environment(MacDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let model = dependencies.commonPhotosCompare, let row = model.row {
                MacCommonPhotosCompareContent(model: model, row: row, close: { dismiss() })
            } else {
                ContentUnavailableView(String(localized: "Nothing to Compare", comment: "Common photos compare window: no row"),
                                       systemImage: "rectangle.split.2x1",
                                       description: Text("Choose a photo in Find Common Photos and press Space.",
                                                         comment: "Common photos compare window: how to open it"))
            }
        }
        .frame(minWidth: 860, idealWidth: Self.size.width, minHeight: 560, idealHeight: Self.size.height)
        .background(MacTheme.Editor.background)
        .preferredColorScheme(.dark)
        .tint(MacTheme.Editor.accent)
        // Out here, so it runs when the rows empty too.
        .onChange(of: dependencies.commonPhotosCompare?.scan.rows.map(\.id)) { dependencies.commonPhotosCompare?.listChanged() }
        .onExitCommand { dismiss() }
        // Closing Compare empties its folder (AC-182); it opens fresh next time.
        .onDisappear {
            guard let model = dependencies.commonPhotosCompare else { return }
            dependencies.commonPhotosCompare = nil
            Task { await model.close() }
        }
    }
}

private struct MacCommonPhotosCompareContent: View {
    @Bindable var model: MacCommonPhotosCompareModel
    let row: CommonPhotosScanModel.Row
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 1) {
                ForEach(Array(model.sides.enumerated()), id: \.offset) { index, side in
                    pane(side, isRight: index == 1)
                }
            }
            .background(MacTheme.Editor.hairline)
            if let pair = model.videoPair, !pair.cannotPlay { MacCommonPhotosTransport(pair: pair) }
            proofBar
        }
        .navigationTitle(String(localized: "Compare — \(row.name)", comment: "Common photos compare window title"))
        .navigationSubtitle(String(localized: "\(model.compare.position.index.formatted()) of \(model.compare.position.count.formatted())",
                                   comment: "Common photos compare window subtitle: which row"))
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { model.previous() } label: { Image(systemName: "chevron.up") }
                    .keyboardShortcut(.upArrow, modifiers: [])
                    .help(String(localized: "Previous Row (↑)", comment: "Common photos compare: toolbar"))
                    .accessibilityLabel(String(localized: "Previous Row", comment: "Common photos compare: toolbar"))
                Button { model.next() } label: { Image(systemName: "chevron.down") }
                    .keyboardShortcut(.downArrow, modifiers: [])
                    .help(String(localized: "Next Row (↓)", comment: "Common photos compare: toolbar"))
                    .accessibilityLabel(String(localized: "Next Row", comment: "Common photos compare: toolbar"))
            }
            ToolbarItemGroup {
                Picker(String(localized: "Zoom", comment: "Common photos compare: zoom"), selection: $model.zoom) {
                    Text("Fit", comment: "Common photos compare: zoom to fit").tag(MacCommonPhotosCompareModel.Zoom.fit)
                        .help(String(localized: "Fit in each side", comment: "Common photos compare: zoom tooltip"))
                    Text("100%", comment: "Common photos compare: actual size").tag(MacCommonPhotosCompareModel.Zoom.actual)
                        .help(String(localized: "Actual size", comment: "Common photos compare: zoom tooltip"))
                }
                .pickerStyle(.segmented)
                Toggle(isOn: Binding(get: { row.isIncluded }, set: { model.setIncluded($0) })) {
                    Text(model.scan.action == .move
                         ? String(localized: "Include in Move", comment: "Common photos compare: the row's checkbox, Move")
                         : String(localized: "Include in Copy", comment: "Common photos compare: the row's checkbox, Copy"))
                }
                .toggleStyle(.checkbox)
                .disabled(!model.canChoose)
                .help(String(localized: "Unchecked: left out of this set from now on.", comment: "Common photos compare: checkbox tooltip"))
            }
        }
        .focusable()
        .focusEffectDisabled()
        // ←→ step too while the picture fits; at 100% they scroll it.
        .onKeyPress(.rightArrow) { guard model.zoom == .fit else { return .ignored }; model.next(); return .handled }
        .onKeyPress(.leftArrow) { guard model.zoom == .fit else { return .ignored }; model.previous(); return .handled }
        // Space plays a video pair; a focused checkbox or picker gets it first.
        .onKeyPress(.space) {
            guard let pair = model.videoPair, !pair.cannotPlay else { return .ignored }
            pair.togglePlay()
            return .handled
        }
        .task(id: model.sidesKey) { await model.loadSides() }
    }

    private func pane(_ side: CommonPhotosCompare.Copy, isRight: Bool) -> some View {
        VStack(spacing: 0) {
            ZStack {
                MacTheme.Editor.background
                if let pair = model.videoPair, !pair.cannotPlay {
                    MacCommonPhotosPlayerView(player: isRight ? pair.follower : pair.leader).padding(16)
                } else if let image = model.previews[side.path]?.image {
                    let picture = Image(decorative: image, scale: 1)
                    Group {
                        if model.zoom == .fit {
                            picture.resizable().scaledToFit().padding(16)
                        } else {
                            ScrollView([.horizontal, .vertical]) { picture }
                        }
                    }
                    // The index's preview stands in while the whole file comes.
                    .overlay(alignment: .bottom) {
                        if let read = model.downloading[side.path], !model.fullSize.contains(side.path) {
                            fullSizeBadge(side, read: read)
                        }
                    }
                } else if let failure = model.failures[side.path] {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(MacTheme.Editor.secondaryText)
                        Text(failure).multilineTextAlignment(.center)
                        Text("Your scan results are kept.", comment: "Common photos compare: a copy could not load")
                            .font(.caption).foregroundStyle(MacTheme.Editor.secondaryText)
                        Button(String(localized: "Try Again", comment: "Common photos compare: load the copy again")) { model.tryAgain() }
                    }
                    .frame(maxWidth: 300)
                } else if model.noPreview.contains(side.path) || model.videoPair?.cannotPlay == true {
                    VStack(spacing: 8) {
                        Image(systemName: "doc").font(.title).foregroundStyle(MacTheme.Editor.secondaryText)
                        Text(MacCommonPhotosCompareModel.isVideo(side.path)
                             ? String(localized: "No preview for this video", comment: "Common photos compare: a video copy")
                             : String(localized: "No preview for this RAW", comment: "Common photos compare: this Mac cannot draw the copy"))
                        Text("Its bytes still match: SHA-256 below.", comment: "Common photos compare: no preview, still Same")
                            .font(.caption).foregroundStyle(MacTheme.Editor.secondaryText)
                    }
                } else if let read = model.downloading[side.path] {
                    downloadingView(side, read: read)
                } else if MacCommonPhotosCompareModel.isVideo(side.path), model.scan.isScanning {
                    // Its reads wait behind the scan's (AC-184).
                    downloadingView(side, read: 0)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(side.place), \(side.name)")
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    if isRight, model.copies.count > 2 {
                        Picker(selection: Binding(get: { model.compare.rightCopy }, set: { model.pickRight($0) })) {
                            ForEach(Array(model.copies.enumerated().dropFirst()), id: \.offset) { index, copy in
                                Text(copy.place).tag(index)
                            }
                        } label: { EmptyView() }
                            .labelsHidden()
                            .fixedSize()
                            .accessibilityLabel(String(localized: "Copy to Compare", comment: "Common photos compare: which copy the right side shows"))
                    } else {
                        Text(side.place).fontWeight(.semibold).lineLimit(1)
                    }
                    Text(side.name).foregroundStyle(MacTheme.Editor.secondaryText).lineLimit(1).truncationMode(.middle)
                }
                .font(.body)
                Text(meta(side)).font(.caption).foregroundStyle(MacTheme.Editor.secondaryText).monospacedDigit().lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .padding(.horizontal, 20)
            .background(MacTheme.Editor.panel)
        }
        .background(MacTheme.Editor.background)
    }

    /// The whole file coming from the server — or waiting while the scan
    /// still reads (its calls go first, AC-184).
    /// Over the index's preview: the whole file is on its way.
    private func fullSizeBadge(_ side: CommonPhotosCompare.Copy, read: Int64) -> some View {
        HStack(spacing: 8) {
            ProgressView(value: Double(read), total: Double(max(side.size, 1))).frame(width: 80)
            Text("Loading full size…", comment: "Common photos compare: the index preview shows while the whole file downloads")
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private func downloadingView(_ side: CommonPhotosCompare.Copy, read: Int64) -> some View {
        if read == 0, model.scan.isScanning {
            VStack(spacing: 8) {
                Image(systemName: "clock").font(.title2).foregroundStyle(MacTheme.Editor.secondaryText)
                Text("Waiting for the scan…", comment: "Common photos compare: the download waits for the scan")
                Text("This copy loads when the scan has nothing else to read.", comment: "Common photos compare: why it waits")
                    .font(.caption).foregroundStyle(MacTheme.Editor.secondaryText)
            }
        } else {
            VStack(spacing: 10) {
                Text("Downloading from \(model.serverName)…", comment: "Common photos compare: the copy is not in the index")
                ProgressView(value: Double(read), total: Double(max(side.size, 1))).frame(width: 200)
                Text("\(read.formatted(.byteCount(style: .file))) of \(side.size.formatted(.byteCount(style: .file)))",
                     comment: "Common photos compare: download progress")
                    .font(.caption).monospacedDigit().foregroundStyle(MacTheme.Editor.secondaryText)
            }
        }
    }

    /// "2.9 MB · Jun 1, 2025 at 4:12 PM · SHA-256 1c3e8a02".
    private func meta(_ side: CommonPhotosCompare.Copy) -> String {
        var parts = [side.size.formatted(.byteCount(style: .file))]
        if let date = model.previews[side.path]?.captured { parts.append(date.formatted(date: .abbreviated, time: .shortened)) }
        if MacCommonPhotosCompareModel.isVideo(side.path) {
            parts.append(String(localized: "played from \(model.serverName)", comment: "Common photos compare: a video side streams from the server"))
        }
        if !row.isQuick { parts.append("SHA-256 " + String(row.sha256.prefix(8))) }
        return parts.joined(separator: " · ")
    }

    /// Status only (MAC_STYLE: nothing actionable in the bottom 60pt).
    private var proofBar: some View {
        HStack(spacing: 12) {
            // A Quick Check row was never read whole: it claims no SHA-256 (§6e).
            Label(row.isQuick
                  ? String(localized: "Quick check — same path and size, three samples match", comment: "Common photos compare: the proof of a Quick Check row")
                  : String(localized: "Same bytes — SHA-256 matches", comment: "Common photos compare: the proof"),
                  systemImage: "checkmark")
                .foregroundStyle(.green)
                .fontWeight(.semibold)
            Text(row.isQuick ? String(localized: "Not read in full", comment: "Common photos Compare: a Quick Check row has no SHA-256") : row.sha256)
                .font(.caption.monospaced()).foregroundStyle(MacTheme.Editor.secondaryText)
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            Spacer(minLength: 0)
            Text("↑↓ next row · Esc close", comment: "Common photos compare: keys").font(.caption)
                .foregroundStyle(MacTheme.Editor.secondaryText)
        }
        .padding(.horizontal, 20)
        .frame(height: 40)
        .background(MacTheme.Editor.panel)
    }
}
