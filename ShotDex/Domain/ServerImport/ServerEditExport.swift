import Foundation
import ShotDexKit

/// One place an export goes (FS-17.06 §6). Chosen together, run one after
/// the other; Share always last, because it hands the user a sheet.
enum ServerExportDestination: Hashable, Sendable, Identifiable {
    /// The folder the photo came from, on its own connection.
    case originalFolder
    /// A new asset in Photos, the render only.
    case photosLibrary
    /// A folder on any saved connection.
    case otherFolder(serverId: String, serverName: String, path: String)
    /// A folder in Files — On My iPhone, iCloud Drive, a drive — by its
    /// bookmark in Export…'s recents (FS-03.07b §8).
    case filesFolder(id: UUID, title: String)
    case share

    var id: String {
        switch self {
        case .originalFolder: "original"
        case .photosLibrary: "photos"
        case .otherFolder(let serverId, _, let path): "other|\(serverId)|\(path)"
        case .filesFolder(let id, _): "files|\(id.uuidString)"
        case .share: "share"
        }
    }

    /// Run order: the writes that can fail on their own first, the share
    /// sheet last.
    var order: Int {
        switch self {
        case .originalFolder: 0
        case .otherFolder, .filesFolder: 1
        case .photosLibrary: 2
        case .share: 3
        }
    }
}

/// Rules of the export sheet that need no server (FS-17.06 §6).
enum ServerExportRules {
    /// Replace Original only where the render can take the original's own
    /// name and kind: a lone JPEG or HEIC. A RAW, or a RAW+JPEG pair, keeps
    /// its original — ShotDex never writes RAW.
    static func canReplaceOriginal(_ photo: ServerPhoto) -> Bool {
        guard !photo.isPair, photo.raw == nil else { return false }
        return replacementFormat(for: photo) != nil
    }

    /// A video goes into Photos as a video, not a photo.
    static func isMovie(_ url: URL) -> Bool {
        ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
    }

    /// The format a replacement is rendered in: the original's own.
    static func replacementFormat(for photo: ServerPhoto) -> ServerExportFormat? {
        switch (photo.primary.name as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg": .jpeg
        case "heic", "heif": .heic
        default: nil
        }
    }
}

/// The two formats ShotDex renders an export in.
enum ServerExportFormat: String, Sendable, CaseIterable {
    case jpeg
    case heic

    var fileExtension: String { self == .jpeg ? "jpg" : "heic" }
}

/// What happened to one photo at one destination.
enum ServerExportOutcome: Equatable, Sendable {
    /// The server path, or the new asset's id.
    case done(String)
    case failed(String)
    /// The server refused the write — the user picks another folder.
    case permissionDenied
}

/// The result of a run, by destination and photo id. What is missing was
/// not reached.
struct ServerExportReport: Sendable, Equatable {
    var outcomes: [ServerExportDestination: [String: ServerExportOutcome]] = [:]
    /// Rendered files for Share, in photo order.
    var shareFiles: [URL] = []

    func outcome(_ destination: ServerExportDestination, _ photoId: String) -> ServerExportOutcome? {
        outcomes[destination]?[photoId]
    }

    /// Every photo reached every destination. Only then do the copies go.
    func isComplete(photos: [FetchedServerPhoto], destinations: Set<ServerExportDestination>) -> Bool {
        isComplete(ids: photos.map(\.id), destinations: destinations)
    }

    func isComplete(ids: [String], destinations: Set<ServerExportDestination>) -> Bool {
        destinations.allSatisfy { destination in
            destination == .share || ids.allSatisfy {
                if case .done = outcome(destination, $0) { true } else { false }
            }
        }
    }

    var failedDestinations: Set<ServerExportDestination> {
        Set(outcomes.compactMap { destination, byPhoto in
            byPhoto.values.contains { if case .done = $0 { false } else { true } } ? destination : nil
        })
    }
}

/// What the export needs from the rest of the app — the renderer, the two
/// servers, Photos — so the run is tested against fakes.
struct ServerExportServices: Sendable {
    /// Renders one photo's edit to a file in `directory`, resized when a
    /// preset is given (Resize, FS-17.06 §3).
    var render: @Sendable (FetchedServerPhoto, ServerExportFormat, ResizePreset?, URL) async throws -> URL
    /// The photo's own connection.
    var originAccess: any RemoteFileAccess
    /// Another saved connection, by id.
    var access: @Sendable (String) async throws -> any RemoteFileAccess
    /// A new asset from a rendered file; returns its id.
    var saveToPhotos: @Sendable (URL, String) async throws -> String
    /// A file into a folder in Files, by its bookmark's id, under a name;
    /// returns where it landed.
    var writeToFiles: @Sendable (URL, String, UUID) async throws -> String = { _, _, _ in
        throw RemoteFileError.other(String(localized: "That folder is gone.", table: "Export", comment: "Server export: the Files folder is not available"))
    }
}

/// One file a tool made from several photos — a collage, a combined photo,
/// a video — already on disk, and the name it goes out under (FS-17.06 §6b).
struct ComposedOutput: Sendable, Equatable {
    /// The key the report files it under.
    static let id = "composed"

    let file: URL
    /// With the extension, already cleaned (`ServerComposedName.filename`).
    let filename: String
    /// The first server photo's folder: where Original Folder writes.
    let folder: String
}

/// Renders every photo once, then sends it to each destination (FS-17.06 §6).
/// A destination that fails leaves the others alone; a retry runs only what
/// is not done, reusing the renders already on disk.
actor ServerEditExporter {
    struct Job: Sendable {
        let photos: [FetchedServerPhoto]
        let destinations: Set<ServerExportDestination>
        let placement: ServerEditPlacement
        let format: ServerExportFormat
        var resize: ResizePreset?
        /// A file made from all the photos: sent as it is, once per
        /// destination, instead of one render per photo.
        var composed: ComposedOutput?

        /// What the report is keyed by.
        var itemIds: [String] { composed == nil ? photos.map(\.id) : [ComposedOutput.id] }
    }

    enum Event: Sendable {
        case rendering(index: Int)
        case sending(destination: ServerExportDestination, index: Int)
    }

    private let services: ServerExportServices
    private let renderDirectory: URL
    private let onEvent: @Sendable (Event) -> Void
    private var rendered: [String: URL] = [:]
    private var namedFiles: [String: URL] = [:]
    private(set) var report = ServerExportReport()

    init(
        services: ServerExportServices,
        renderDirectory: URL,
        onEvent: @escaping @Sendable (Event) -> Void = { _ in }
    ) {
        self.services = services
        self.renderDirectory = renderDirectory
        self.onEvent = onEvent
    }

    func run(_ job: Job) async -> ServerExportReport {
        if let composed = job.composed { return await run(composed, to: job.destinations) }
        try? FileManager.default.createDirectory(at: renderDirectory, withIntermediateDirectories: true)
        for destination in job.destinations.sorted(by: { $0.order < $1.order }) {
            for (index, photo) in job.photos.enumerated() {
                if Task.isCancelled { return report }
                if case .done = report.outcome(destination, photo.id) { continue }
                let outcome: ServerExportOutcome
                do {
                    let file = try await renderedFile(photo, index: index, job: job)
                    onEvent(.sending(destination: destination, index: index))
                    outcome = try await send(file, of: photo, to: destination, placement: job.placement)
                } catch let error as RemoteFileError {
                    if case .permissionDenied = error {
                        outcome = .permissionDenied
                    } else {
                        outcome = .failed(error.localizedDescription)
                    }
                } catch is CancellationError {
                    return report
                } catch {
                    outcome = .failed(error.localizedDescription)
                }
                report.outcomes[destination, default: [:]][photo.id] = outcome
                // A connection that is gone will fail every later photo too.
                if case .failed = outcome, destination != .photosLibrary, destination != .share,
                   job.photos.count > index + 1 {
                    for later in job.photos[(index + 1)...] where report.outcome(destination, later.id) == nil {
                        report.outcomes[destination, default: [:]][later.id] = outcome
                    }
                    break
                }
            }
        }
        return report
    }

    private func run(_ composed: ComposedOutput, to destinations: Set<ServerExportDestination>) async -> ServerExportReport {
        let file: URL
        do {
            file = try named(composed)
        } catch {
            for destination in destinations {
                report.outcomes[destination, default: [:]][ComposedOutput.id] = .failed(error.localizedDescription)
            }
            return report
        }
        for destination in destinations.sorted(by: { $0.order < $1.order }) {
            if Task.isCancelled { return report }
            if case .done = report.outcome(destination, ComposedOutput.id) { continue }
            let outcome: ServerExportOutcome
            do {
                onEvent(.sending(destination: destination, index: 0))
                outcome = try await send(file, named: composed.filename, folder: composed.folder, to: destination)
            } catch let error as RemoteFileError {
                if case .permissionDenied = error {
                    outcome = .permissionDenied
                } else {
                    outcome = .failed(error.localizedDescription)
                }
            } catch is CancellationError {
                return report
            } catch {
                outcome = .failed(error.localizedDescription)
            }
            report.outcomes[destination, default: [:]][ComposedOutput.id] = outcome
        }
        return report
    }

    /// The file under the name the user gave it, so Share and Photos see
    /// that name too. A hard link where the volume allows, a copy otherwise.
    private func named(_ composed: ComposedOutput) throws -> URL {
        if composed.file.lastPathComponent == composed.filename { return composed.file }
        if let url = namedFiles[composed.filename], FileManager.default.fileExists(atPath: url.path) { return url }
        let folder = renderDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(composed.filename)
        do {
            try FileManager.default.linkItem(at: composed.file, to: url)
        } catch {
            try FileManager.default.copyItem(at: composed.file, to: url)
        }
        namedFiles[composed.filename] = url
        return url
    }

    private func send(
        _ file: URL, named filename: String, folder: String, to destination: ServerExportDestination
    ) async throws -> ServerExportOutcome {
        switch destination {
        case .originalFolder:
            let path = try await services.originAccess.perform { client in
                try await ServerEditWriter.write(file, originalName: filename, into: folder,
                                                 placement: .asNamed, client: client)
            }
            return .done(path)
        case .otherFolder(let serverId, _, let folder):
            let access = try await services.access(serverId)
            let path = try await access.perform { client in
                try await ServerEditWriter.write(file, originalName: filename, into: folder,
                                                 placement: .asNamed, client: client)
            }
            return .done(path)
        case .filesFolder(let id, _):
            return .done(try await services.writeToFiles(file, filename, id))
        case .photosLibrary:
            return .done(try await services.saveToPhotos(file, filename))
        case .share:
            if !report.shareFiles.contains(file) { report.shareFiles.append(file) }
            return .done(file.path)
        }
    }

    private func renderedFile(_ photo: FetchedServerPhoto, index: Int, job: Job) async throws -> URL {
        if let url = rendered[photo.id], FileManager.default.fileExists(atPath: url.path) { return url }
        onEvent(.rendering(index: index))
        let format = job.placement == .replaceOriginal
            ? (ServerExportRules.replacementFormat(for: photo.photo) ?? job.format)
            : job.format
        let folder = renderDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = try await services.render(photo, format, job.resize, folder)
        rendered[photo.id] = url
        return url
    }

    private func send(
        _ file: URL,
        of photo: FetchedServerPhoto,
        to destination: ServerExportDestination,
        placement: ServerEditPlacement
    ) async throws -> ServerExportOutcome {
        switch destination {
        case .originalFolder:
            let path = try await services.originAccess.perform { client in
                try await ServerEditWriter.write(file, originalName: photo.photo.primary.name, into: photo.folder,
                                                 placement: placement, client: client)
            }
            return .done(path)
        case .otherFolder(let serverId, _, let folder):
            let access = try await services.access(serverId)
            let path = try await access.perform { client in
                try await ServerEditWriter.write(file, originalName: photo.photo.primary.name, into: folder,
                                                 placement: .newFile, client: client)
            }
            return .done(path)
        case .filesFolder(let id, _):
            // `<name>_edited.jpg`, as beside the original (FS-17.06 §6).
            let name = ServerUploadPath.editedFilename(original: photo.photo.primary.name, rendered: file.lastPathComponent)
            return .done(try await services.writeToFiles(file, name, id))
        case .photosLibrary:
            let name = ServerUploadPath.editedFilename(original: photo.photo.primary.name, rendered: file.lastPathComponent)
            return .done(try await services.saveToPhotos(file, name))
        case .share:
            if !report.shareFiles.contains(file) { report.shareFiles.append(file) }
            return .done(file.path)
        }
    }
}
