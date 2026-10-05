import Foundation
import ImageIO
import Observation
import ShotDexKit

/// The export sheet of a server run (FS-17.06 §6): where to, how the
/// original is treated, the run, and what came of it per destination.
@MainActor
@Observable
final class ServerExportModel {
    enum Stage: Equatable {
        case choosing
        case exporting
        /// Something did not arrive; the sheet shows each destination.
        case finishedWithFailures
        /// Every destination has every photo. Share, if chosen, is up next.
        case done
    }

    /// One file a tool made from all the photos (FS-17.06 §6b): it goes out
    /// as it is, under a name the user can change.
    struct ComposedSource {
        let file: URL
        let tool: ServerComposedName.Tool
        /// The name of the photo the default name is built from.
        let firstFilename: String

        var fileExtension: String { file.pathExtension.lowercased() }

        /// The format as the sheet names it elsewhere: JPEG, HEIC, MP4.
        var formatName: String {
            switch fileExtension {
            case "jpg", "jpeg": "JPEG"
            case "heic", "heif": "HEIC"
            default: fileExtension.uppercased()
            }
        }
    }

    /// The other folder picked for Other Folder….
    struct OtherFolder: Equatable {
        let server: FileServer
        let path: String
    }

    let photos: [FetchedServerPhoto]
    let originServer: FileServer
    let originFolder: String
    private(set) var stage: Stage = .choosing
    var destinations: Set<Choice> = []
    var placement: ServerEditPlacement = .newFile
    var format: ServerExportFormat = .jpeg
    var otherFolder: OtherFolder?
    /// Other Folder → Folder in Files…: a folder from the system picker, in
    /// Export…'s recents (FS-03.07b §8). Wins over `otherFolder` once set.
    var filesFolder: ExportFolder?
    /// The sizes every per-photo export offers — the Resize presets, the
    /// user's own included, Original first (FS-03.07b §8). Empty for one
    /// file a tool made, which goes out as it is.
    let sizePresets: [ResizePreset]
    /// The size picked. Original, except Resize, which starts at 2048 px.
    private(set) var sizePreset: ResizePreset
    /// Set when a tool made one file from all the photos.
    let composed: ComposedSource?
    /// The name typed in the sheet, without the extension.
    var name: String
    private(set) var report = ServerExportReport()
    private(set) var progressLine = ""

    /// The rows of the sheet, before Other Folder has a folder.
    enum Choice: Hashable {
        case originalFolder
        case photosLibrary
        case otherFolder
        case share
    }

    /// The forms' remembered watermark (FS-05.04 §5); nil in a test that
    /// does not stamp, and never for one file a tool made.
    let watermarkSettings: WatermarkSettingsStore?
    let signaturePresets: SignaturePresetStore?
    @ObservationIgnored let imageExists: (UUID) -> Bool

    private let services: ServerExportServices
    private let renderDirectory: URL
    private var exporter: ServerEditExporter?
    private var lastJob: ServerEditExporter.Job?
    private var task: Task<Void, Never>?

    init(
        photos: [FetchedServerPhoto],
        originServer: FileServer,
        renderDirectory: URL,
        services: ServerExportServices,
        sizePresets: [ResizePreset] = ResizePreset.builtIns,
        startingSize: ResizePreset = .original,
        composed: ComposedSource? = nil,
        watermarkSettings: WatermarkSettingsStore? = nil,
        signaturePresets: SignaturePresetStore? = nil,
        imageExists: @escaping (UUID) -> Bool = { OverlayImageStore().imageExists(id: $0) }
    ) {
        self.watermarkSettings = composed == nil ? watermarkSettings : nil
        self.signaturePresets = signaturePresets
        self.imageExists = imageExists
        self.photos = photos
        self.composed = composed
        self.name = composed.map { ServerComposedName.defaultBase(firstFilename: $0.firstFilename, tool: $0.tool) } ?? ""
        self.sizePresets = composed == nil ? ServerExportSizes.offered(sizePresets) : []
        self.sizePreset = ServerExportSizes.offered(sizePresets).first { $0.id == startingSize.id } ?? .original
        self.originServer = originServer
        self.originFolder = photos.first?.folder ?? ""
        self.renderDirectory = renderDirectory
        self.services = services
    }

    /// Replace Original is offered only when every photo can take it — a
    /// lone JPEG or HEIC (FS-17.06 §6) — and never with a watermark: a
    /// stamped copy must not take the place of the only clean one
    /// (FS-05.04 §5).
    var canReplaceOriginals: Bool {
        composed == nil && photos.allSatisfy { ServerExportRules.canReplaceOriginal($0.photo) } && watermarkTemplate == nil
    }

    // MARK: Watermark (FS-05.04)

    /// The watermark the sheet stamps, before tokens: nil when it is off,
    /// its preset is gone, or this is one file a tool made.
    var watermarkTemplate: WatermarkStamp? {
        guard let watermarkSettings, let signaturePresets else { return nil }
        let imageExists = imageExists
        return watermarkSettings.formStamp(in: signaturePresets.presets) {
            WatermarkAvailability.of($0, imageExists: imageExists).isSelectable
        }
    }

    /// Whether the sheet shows the Watermark row: every per-photo export.
    var offersWatermark: Bool { composed == nil && watermarkSettings != nil && signaturePresets != nil }

    /// The Watermark screen for this sheet: one page per photo, its picture
    /// from the fetched file, its size as the sheet will write it.
    func makeWatermarkModel() -> WatermarkModel? {
        guard let watermarkSettings, let signaturePresets else { return nil }
        let preset = sizePreset
        let pages = photos.map { photo in
            let url = photo.primaryURL
            let pixels = ServerExportModel.pixelSize(of: url)
            return WatermarkPreviewPage(
                id: photo.id,
                filename: photo.photo.primary.name,
                exportSize: preset.id == ResizePreset.original.id ? pixels : preset.outputPixelSize(source: pixels),
                tokens: .empty,
                load: { await Task.detached { ServerExportModel.preview(of: url) }.value }
            )
        }
        return WatermarkModel(
            settings: watermarkSettings, presets: signaturePresets, pages: pages,
            formTitle: String(localized: "Export", comment: "Server export sheet title"), imageExists: imageExists
        )
    }

    /// The picture's upright size.
    nonisolated static func pixelSize(of url: URL) -> CGSize {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return CGSize(width: 1000, height: 1000) }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    /// A 1,200px upright preview read from the fetched file.
    nonisolated static func preview(of url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_200,
        ] as CFDictionary)
    }

    /// The row's value: the preset's name, Off, or None.
    var watermarkRowValue: String {
        guard let signaturePresets, !signaturePresets.presets.isEmpty else { return WatermarkCopy.none() }
        return watermarkTemplate?.name ?? WatermarkCopy.off()
    }

    var isComposed: Bool { composed != nil }

    /// The file name the composed file goes out under, or nil while the
    /// typed name leaves nothing (FS-17.06 §6b).
    var composedFilename: String? {
        composed.flatMap { ServerComposedName.filename(typed: name, fileExtension: $0.fileExtension) }
    }

    /// Folder in Files…: the picked folder joins Export…'s recents and is
    /// where Other Folder writes.
    func chooseFilesFolder(_ url: URL, in store: ExportFolderStore) {
        guard let folder = try? store.remember(url) else { return }
        filesFolder = folder
        otherFolder = nil
        destinations.insert(.otherFolder)
    }

    /// Picks a size. A preset that names its own format sets Format to it;
    /// Same as Original leaves Format as it is.
    func chooseSize(_ preset: ResizePreset) {
        sizePreset = preset
        switch preset.format {
        case .jpeg: format = .jpeg
        case .heic: format = .heic
        case .preserve: break
        }
    }

    /// What the render resizes to: nothing for the built-in Original, so an
    /// edit at full size keeps the full quality it always had.
    var resize: ResizePreset? {
        sizePreset.id == ResizePreset.original.id ? nil : sizePreset
    }

    var hasRAWOriginal: Bool { photos.contains { $0.photo.raw != nil } }

    var resolvedDestinations: Set<ServerExportDestination> {
        Set(destinations.compactMap { choice in
            switch choice {
            case .originalFolder: .originalFolder
            case .photosLibrary: .photosLibrary
            case .share: .share
            case .otherFolder:
                filesFolder.map { .filesFolder(id: $0.id, title: $0.title) }
                    ?? otherFolder.map { .otherFolder(serverId: $0.server.id, serverName: $0.server.name, path: $0.path) }
            }
        })
    }

    var canExport: Bool {
        stage == .choosing && !destinations.isEmpty && resolvedDestinations.count == destinations.count
            && (composed == nil || composedFilename != nil)
    }

    /// Replace Original goes through a second, red confirmation first.
    var needsReplaceConfirmation: Bool {
        destinations.contains(.originalFolder) && placement == .replaceOriginal
    }

    func toggle(_ choice: Choice) {
        if destinations.contains(choice) { destinations.remove(choice) } else { destinations.insert(choice) }
        if !destinations.contains(.originalFolder) { placement = .newFile }
    }

    func export() {
        guard canExport else { return }
        let effectivePlacement: ServerEditPlacement = destinations.contains(.originalFolder) && canReplaceOriginals ? placement : .newFile
        let job = ServerEditExporter.Job(
            photos: photos, destinations: resolvedDestinations, placement: effectivePlacement, format: format,
            resize: composed == nil ? resize : nil,
            composed: composed.map { source in
                ComposedOutput(file: source.file, filename: composedFilename ?? source.file.lastPathComponent, folder: originFolder)
            },
            // A server photo has no index: its tokens are the editor's —
            // none (FS-05.04 §3).
            watermark: composed == nil ? watermarkTemplate?.resolved(with: .empty) : nil
        )
        start(job, exporter: ServerEditExporter(services: services, renderDirectory: renderDirectory) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        })
    }

    /// Runs again what did not arrive, with the renders already made.
    func retryFailed() {
        guard stage == .finishedWithFailures, let job = lastJob, let exporter else { return }
        start(job, exporter: exporter)
    }

    /// A server that refused the write: pick another folder for the photos
    /// that did not arrive (FS-17.06 §6).
    func chooseAnotherFolder(_ folder: OtherFolder) {
        guard let job = lastJob, let exporter else { return }
        otherFolder = folder
        filesFolder = nil
        destinations.insert(.otherFolder)
        let refused = report.failedDestinations
        var next = job.destinations.subtracting(refused.filter { destination in
            report.outcomes[destination]?.values.contains(.permissionDenied) == true
        })
        next.insert(.otherFolder(serverId: folder.server.id, serverName: folder.server.name, path: folder.path))
        start(ServerEditExporter.Job(photos: job.photos, destinations: next, placement: job.placement,
                                     format: job.format, resize: job.resize, composed: job.composed,
                                     watermark: job.watermark),
              exporter: exporter)
    }

    /// What went wrong at one destination, for its row in the result:
    /// the first thing that did not arrive there, or nil when everything
    /// did. A composed export is filed under its own key, not a photo's.
    func failure(at destination: ServerExportDestination) -> ServerExportOutcome? {
        let ids = composed == nil ? photos.map(\.id) : [ComposedOutput.id]
        return ids.compactMap { report.outcome(destination, $0) }
            .first { if case .done = $0 { false } else { true } }
    }

    var hasPermissionDenied: Bool {
        report.outcomes.values.contains { $0.values.contains(.permissionDenied) }
    }

    func cancel() { task?.cancel() }

    private func start(_ job: ServerEditExporter.Job, exporter: ServerEditExporter) {
        guard task == nil else { return }
        self.exporter = exporter
        lastJob = job
        stage = .exporting
        progressLine = ""
        task = Task { [weak self] in
            let report = await exporter.run(job)
            guard let self else { return }
            self.task = nil
            self.report = report
            self.stage = report.isComplete(ids: job.itemIds, destinations: job.destinations) ? .done : .finishedWithFailures
        }
    }

    private func handle(_ event: ServerEditExporter.Event) {
        let count = composed == nil ? photos.count : 1
        switch event {
        case .rendering(let index):
            progressLine = String(localized: "Rendering \(index + 1) of \(count)", comment: "Server export: rendering the edit of one photo")
        case .sending(let destination, let index):
            progressLine = String(localized: "\(title(of: destination)): \(index + 1) of \(count)", comment: "Server export: sending one photo to a destination")
        }
    }

    func title(of destination: ServerExportDestination) -> String {
        switch destination {
        case .originalFolder: String(localized: "Original Folder", comment: "Server export destination")
        case .photosLibrary: String(localized: "Photos Library", comment: "Server export destination")
        case .otherFolder(_, let name, let path): path.isEmpty ? name : "\(name) · \(path)"
        case .filesFolder(_, let title): title
        case .share: String(localized: "Share", comment: "Server export destination")
        }
    }
}

/// A sheet item: one export, one sheet.
extension ServerExportModel: Identifiable {}

/// Logins to the other connections an export writes to, opened on first use
/// and shared by every photo of the run.
actor RemoteAccessPool {
    private let make: @Sendable (String) throws -> ServerBrowseSession
    private var sessions: [String: ServerBrowseSession] = [:]

    init(make: @escaping @Sendable (String) throws -> ServerBrowseSession) {
        self.make = make
    }

    func access(for serverId: String) throws -> any RemoteFileAccess {
        if let session = sessions[serverId] { return session }
        let session = try make(serverId)
        sessions[serverId] = session
        return session
    }

    func closeAll() async {
        for session in sessions.values { await session.close() }
        sessions = [:]
    }
}

extension ServerExportModel {
    /// An export wired to the app: the editor's renderer, the run's login
    /// for the original folder, a login per other connection opened on first
    /// use, and Photos for the library.
    static func make(
        photos: [FetchedServerPhoto],
        recipes: [String: PhotoEditRecipe],
        context: ServerExportContext,
        dependencies: AppDependencies,
        isResize: Bool = false
    ) -> ServerExportModel {
        let service = dependencies.photoEditing
        return ServerExportModel(
            photos: photos,
            originServer: context.server,
            renderDirectory: context.workDirectory.appendingPathComponent("Exports", isDirectory: true),
            services: services(context: context, dependencies: dependencies) { photo, format, resize, watermark, folder in
                let recipe = recipes[photo.id] ?? .identity
                // An edit that already has a layer from the preset is not
                // stamped twice (FS-05.04 §5).
                let stamp = watermark.flatMap {
                    WatermarkPlan.alreadyStamped(savedLayers: recipe.overlays, presetID: $0.presetID) ? nil : $0
                }
                return try await EditorBatchSaver.renderToFile(
                    photo,
                    recipe: recipe,
                    service: service,
                    format: format == .heic ? .heic : .jpeg,
                    // The render goes back to the server and to Photos with
                    // everything; its Share destination filters it (AC-22).
                    metadata: .all,
                    resize: resize,
                    watermark: stamp,
                    into: folder
                )
            },
            sizePresets: dependencies.compressionPresets.allPresets,
            startingSize: isResize ? .twoK : .original,
            watermarkSettings: dependencies.watermarkSettings,
            signaturePresets: dependencies.signaturePresets,
            imageExists: { [images = dependencies.overlayImages] in images.imageExists(id: $0) }
        )
    }

    /// The export of one file a tool made from `photos` — a collage, a
    /// combined photo, a video (FS-17.06 §6b).
    static func makeComposed(
        _ source: ComposedSource,
        photos: [FetchedServerPhoto],
        context: ServerExportContext,
        dependencies: AppDependencies
    ) -> ServerExportModel {
        ServerExportModel(
            photos: photos,
            originServer: context.server,
            renderDirectory: context.workDirectory.appendingPathComponent("Exports", isDirectory: true),
            services: services(context: context, dependencies: dependencies) { _, _, _, _, _ in
                // The tool rendered it already; nothing renders per photo.
                source.file
            },
            composed: source
        )
    }

    private static func services(
        context: ServerExportContext,
        dependencies: AppDependencies,
        render: @escaping @Sendable (FetchedServerPhoto, ServerExportFormat, ResizePreset?, WatermarkStamp?, URL) async throws -> URL
    ) -> ServerExportServices {
        let library = dependencies.photoLibrary
        dependencies.fileServerCatalog.reload()
        let servers = Dictionary(uniqueKeysWithValues: dependencies.fileServerCatalog.servers.map { ($0.id, $0) })
        let store = dependencies.fileServers
        let passwords = servers.mapValues { store.password(for: $0.id) ?? "" }
        let pool = RemoteAccessPool { id in
            guard let server = servers[id] else {
                throw RemoteFileError.other(String(localized: "That connection is gone.", comment: "Server export: the picked connection was deleted"))
            }
            return ServerBrowseSession(server: server, client: RemoteFileClientFactory.make(for: server, password: passwords[id] ?? ""))
        }
        return ServerExportServices(
            render: render,
            originAccess: context.access,
            access: { id in try await pool.access(for: id) },
            saveToPhotos: { url, name in
                // A video goes in as a video, read in place.
                if ServerExportRules.isMovie(url) {
                    return try await library.importFile(at: url, isVideo: true)
                }
                // Photos takes the file; the render stays for the other
                // destinations.
                let copy = url.deletingLastPathComponent()
                    .appendingPathComponent("photos-\(UUID().uuidString)-\(url.lastPathComponent)")
                try FileManager.default.copyItem(at: url, to: copy)
                return try await library.saveImageFile(at: copy, filename: name)
            },
            writeToFiles: { file, name, id in
                try await writeToFiles(file, name: name, folderId: id, store: await MainActor.run { ExportFolderStore() })
            }
        )
    }
}

/// The Size row of the server export sheet (FS-03.07b §8).
enum ServerExportSizes {
    /// The presets as Resize lists them, Original first, each once.
    static func offered(_ presets: [ResizePreset]) -> [ResizePreset] {
        var seen: Set<UUID> = [ResizePreset.original.id]
        return [.original] + presets.filter { seen.insert($0.id).inserted }
    }
}

extension ServerExportModel {
    /// A render into a folder in Files the way Export… writes (FS-03.07b §6):
    /// under its part name, checked, renamed through file coordination, the
    /// next free name if one is taken. No upload history: the copy on disk
    /// is not a backup of the server's original (§7).
    nonisolated static func writeToFiles(_ file: URL, name: String, folderId: UUID, store: ExportFolderStore) async throws -> String {
        let url: URL? = await MainActor.run {
            guard let folder = store.recents.first(where: { $0.id == folderId }),
                  case .available(let url) = store.resolve(folder) else { return nil }
            return url
        }
        guard let url else { throw RemoteFileError.other(ExportCopy.folderGone) }
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
        let writer = LocalFolderWriter(root: url)
        let target = ServerUploadPath.nextFreeName(for: name, existing: try await writer.existingNames(in: ""))
        return try await writer.write(name: target, in: "", replacing: false) { part in
            try RollingOriginalPrefetcher.copyInBlocks(from: file, to: part)
        }.path
    }
}
