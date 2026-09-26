import Foundation
import ImageIO

/// One photo to bring down (FS-17.02 §2).
struct ServerDownloadItem: Sendable {
    let photo: ServerPhoto
    /// The folder on the server the photo's files are in.
    let folder: String
    /// SHA-256 a history row already knows, by file name — the check the
    /// download must pass when present.
    var knownChecksums: [String: String] = [:]

    func path(of file: RemoteEntry) -> String { ServerUploadPath.join(folder, file.name) }
}

/// What PhotoKit is asked to create: one asset from one or two files.
struct AssetCreationRequest: Sendable, Equatable {
    enum Role: Sendable, Equatable {
        /// The image Photos shows (a single file, or the JPEG/HEIC of a pair).
        case photo
        /// The RAW of a RAW + JPEG pair.
        case alternatePhoto
    }

    struct Resource: Sendable, Equatable {
        let url: URL
        let role: Role
        let originalFilename: String
    }

    let resources: [Resource]
    let creationDate: Date?
    /// A user album to add the new asset to; nil = the library only.
    let albumId: String?
}

enum AssetCreationError: Error, Equatable, LocalizedError {
    /// Photos refused the file's format (WEBP, AVIF…).
    case unsupportedFormat(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            String(localized: "Photos can't store this format (\(format)).", comment: "Download from server: Photos rejected the file type")
        case .failed(let message):
            message
        }
    }
}

/// Writes assets into the library — PhotoKit in the app, a recorder in tests.
protocol AssetCreating: Sendable {
    /// The new asset's local identifier.
    func createAsset(_ request: AssetCreationRequest) async throws -> String
}

enum ServerDownloadPhase: Equatable, Sendable {
    case downloading
    case checking
    case saving
}

enum ServerDownloadEvent: Sendable {
    case itemStarted(index: Int, phase: ServerDownloadPhase)
    case phase(index: Int, ServerDownloadPhase)
    case bytes(done: Int64, total: Int64)
}

enum ServerDownloadOutcome: Equatable, Sendable {
    case saved(assetId: String)
    case failed(String)
    case notAttempted
}

struct ServerDownloadResult: Sendable {
    var outcomes: [ServerDownloadOutcome]
    var stopReason: ServerUploadResult.StopReason?
}

/// Brings photos down one at a time (FS-17.02 §2): download each file to a
/// work folder hashing on the way, check it, save the photo as one asset,
/// record it, delete the work files. A failure of one photo is recorded and
/// the batch goes on; a failure that will hit every later photo (connection,
/// disk) stops it, the way uploads do.
actor ServerDownloadSession {
    private let client: any RemoteFileClient
    private let creator: any AssetCreating
    private let serverId: String
    private let serverName: String
    private let workDirectory: URL
    private let albumId: String?
    private let onEvent: @Sendable (ServerDownloadEvent) -> Void
    private let record: @Sendable (ServerDownloadRecord) throws -> Void

    init(
        client: any RemoteFileClient,
        creator: any AssetCreating,
        serverId: String,
        serverName: String,
        workDirectory: URL,
        albumId: String?,
        onEvent: @escaping @Sendable (ServerDownloadEvent) -> Void = { _ in },
        record: @escaping @Sendable (ServerDownloadRecord) throws -> Void
    ) {
        self.client = client
        self.creator = creator
        self.serverId = serverId
        self.serverName = serverName
        self.workDirectory = workDirectory
        self.albumId = albumId
        self.onEvent = onEvent
        self.record = record
    }

    func run(_ items: [ServerDownloadItem]) async -> ServerDownloadResult {
        var outcomes = [ServerDownloadOutcome](repeating: .notAttempted, count: items.count)
        let total = items.reduce(Int64(0)) { $0 + $1.photo.totalBytes }
        var done: Int64 = 0
        try? FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        do {
            try await client.connect()
        } catch {
            return ServerDownloadResult(outcomes: outcomes, stopReason: .error(Self.remoteError(error)))
        }
        defer { Task { [client] in await client.disconnect() } }

        for (index, item) in items.enumerated() {
            if Task.isCancelled {
                return ServerDownloadResult(outcomes: outcomes, stopReason: .cancelled)
            }
            onEvent(.itemStarted(index: index, phase: .downloading))
            let startedAt = done
            do {
                outcomes[index] = try await bringDown(item, index: index) { bytes in
                    self.onEvent(.bytes(done: startedAt + bytes, total: total))
                }
            } catch is CancellationError {
                return ServerDownloadResult(outcomes: outcomes, stopReason: .cancelled)
            } catch let error as RemoteFileError where error.stopsBatch {
                return ServerDownloadResult(outcomes: outcomes, stopReason: .error(error))
            } catch {
                outcomes[index] = .failed(error.localizedDescription)
            }
            done = startedAt + item.photo.totalBytes
            onEvent(.bytes(done: done, total: total))
        }
        return ServerDownloadResult(outcomes: outcomes, stopReason: nil)
    }

    private func bringDown(
        _ item: ServerDownloadItem,
        index: Int,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws -> ServerDownloadOutcome {
        let folder = workDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        var local: [(file: RemoteEntry, url: URL, sha256: String)] = []
        var before: Int64 = 0
        for file in item.photo.files {
            let url = folder.appendingPathComponent(file.name)
            let offset = before
            let sha = try await client.download(item.path(of: file), to: url) { bytes in progress(offset + bytes) }
            local.append((file, url, sha))
            before += file.size
        }

        onEvent(.phase(index: index, .checking))
        for (file, url, sha) in local {
            if let reason = Self.checkFailure(file: file, at: url, sha256: sha, known: item.knownChecksums[file.name]) {
                return .failed(reason)
            }
        }

        onEvent(.phase(index: index, .saving))
        let resources = local.map { entry in
            AssetCreationRequest.Resource(
                url: entry.url,
                role: item.photo.isPair && entry.file == item.photo.raw ? .alternatePhoto : .photo,
                originalFilename: entry.file.name
            )
        }
        let request = AssetCreationRequest(
            resources: resources,
            creationDate: Self.captureDate(of: local[0].url) ?? item.photo.primary.modified,
            albumId: albumId
        )
        let assetId = try await creator.createAsset(request)
        for (file, _, sha) in local {
            try? record(ServerDownloadRecord(
                assetId: assetId, serverId: serverId, serverName: serverName,
                remotePath: item.path(of: file), byteCount: file.size, sha256: sha
            ))
        }
        return .saved(assetId: assetId)
    }

    /// Nil when the file passed (FS-17.02 §2): the byte count the server
    /// reported, an image ImageIO can open, and the known SHA-256 if any.
    static func checkFailure(file: RemoteEntry, at url: URL, sha256: String, known: String?) -> String? {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? -1
        if size != file.size {
            return String(localized: "\(file.name) arrived incomplete.", comment: "Download from server: size check failed")
        }
        if let known, known != sha256 {
            return String(localized: "\(file.name) doesn't match the copy uploaded from this device.", comment: "Download from server: checksum differs from history")
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetType(source) != nil,
              CGImageSourceGetCount(source) > 0
        else {
            return String(localized: "\(file.name) isn't an image ShotDex can read.", comment: "Download from server: ImageIO could not open the file")
        }
        return nil
    }

    /// `DateTimeOriginal` (+ `OffsetTimeOriginal`) of the downloaded file,
    /// else the first EXIF date string in its head.
    static func captureDate(of url: URL) -> Date? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 256 * 1024) else { return nil }
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let date = EmbeddedPreview.captureDate(fromEXIF: exif) {
            return date
        }
        return EmbeddedPreview.captureDate(from: head)
    }

    private static func remoteError(_ error: Error) -> RemoteFileError {
        (error as? RemoteFileError) ?? .other(error.localizedDescription)
    }
}
