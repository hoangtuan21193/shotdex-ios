import Foundation
import Observation

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
        services: ServerExportServices
    ) {
        self.photos = photos
        self.originServer = originServer
        self.originFolder = photos.first?.folder ?? ""
        self.renderDirectory = renderDirectory
        self.services = services
    }

    /// Replace Original is offered only when every photo can take it — a
    /// lone JPEG or HEIC (FS-17.06 §6).
    var canReplaceOriginals: Bool { photos.allSatisfy { ServerExportRules.canReplaceOriginal($0.photo) } }

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
            photos: photos, destinations: resolvedDestinations, placement: effectivePlacement, format: format
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
        start(ServerEditExporter.Job(photos: job.photos, destinations: next, placement: job.placement, format: job.format),
              exporter: exporter)
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
            self.stage = report.isComplete(photos: job.photos, destinations: job.destinations) ? .done : .finishedWithFailures
        }
    }

    private func handle(_ event: ServerEditExporter.Event) {
        let count = photos.count
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
