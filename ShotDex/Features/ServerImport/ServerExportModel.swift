import Foundation
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
    /// Set for Resize (FS-17.06 §3): the sizes offered, and the one picked.
    let resizePresets: [ResizePreset]?
    var resizePreset: ResizePreset?
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
        resizePresets: [ResizePreset]? = nil,
        composed: ComposedSource? = nil
    ) {
        self.photos = photos
        self.composed = composed
        self.name = composed.map { ServerComposedName.defaultBase(firstFilename: $0.firstFilename, tool: $0.tool) } ?? ""
        self.resizePresets = resizePresets
        self.resizePreset = resizePresets?.first
        self.originServer = originServer
        self.originFolder = photos.first?.folder ?? ""
        self.renderDirectory = renderDirectory
        self.services = services
    }

    /// Replace Original is offered only when every photo can take it — a
    /// lone JPEG or HEIC (FS-17.06 §6).
    var canReplaceOriginals: Bool {
        composed == nil && photos.allSatisfy { ServerExportRules.canReplaceOriginal($0.photo) }
    }

    var isComposed: Bool { composed != nil }

    /// The file name the composed file goes out under, or nil while the
    /// typed name leaves nothing (FS-17.06 §6b).
    var composedFilename: String? {
        composed.flatMap { ServerComposedName.filename(typed: name, fileExtension: $0.fileExtension) }
    }

    var hasRAWOriginal: Bool { photos.contains { $0.photo.raw != nil } }

    var resolvedDestinations: Set<ServerExportDestination> {
        Set(destinations.compactMap { choice in
            switch choice {
            case .originalFolder: .originalFolder
            case .photosLibrary: .photosLibrary
            case .share: .share
            case .otherFolder: otherFolder.map { .otherFolder(serverId: $0.server.id, serverName: $0.server.name, path: $0.path) }
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
            resize: resizePreset,
            composed: composed.map { source in
                ComposedOutput(file: source.file, filename: composedFilename ?? source.file.lastPathComponent, folder: originFolder)
            }
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
        destinations.insert(.otherFolder)
        let refused = report.failedDestinations
        var next = job.destinations.subtracting(refused.filter { destination in
            report.outcomes[destination]?.values.contains(.permissionDenied) == true
        })
        next.insert(.otherFolder(serverId: folder.server.id, serverName: folder.server.name, path: folder.path))
        start(ServerEditExporter.Job(photos: job.photos, destinations: next, placement: job.placement,
                                     format: job.format, resize: job.resize, composed: job.composed),
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
        resizePresets: [ResizePreset]? = nil
    ) -> ServerExportModel {
        let service = dependencies.photoEditing
        return ServerExportModel(
            photos: photos,
            originServer: context.server,
            renderDirectory: context.workDirectory.appendingPathComponent("Exports", isDirectory: true),
            services: services(context: context, dependencies: dependencies) { photo, format, resize, folder in
                try await EditorBatchSaver.renderToFile(
                    photo,
                    recipe: recipes[photo.id] ?? .identity,
                    service: service,
                    format: format == .heic ? .heic : .jpeg,
                    includeMetadata: true,
                    resize: resize,
                    into: folder
                )
            },
            resizePresets: resizePresets
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
            services: services(context: context, dependencies: dependencies) { _, _, _, _ in
                // The tool rendered it already; nothing renders per photo.
                source.file
            },
            composed: source
        )
    }

    private static func services(
        context: ServerExportContext,
        dependencies: AppDependencies,
        render: @escaping @Sendable (FetchedServerPhoto, ServerExportFormat, ResizePreset?, URL) async throws -> URL
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
            }
        )
    }
}
