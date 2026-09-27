import CoreGraphics
import Foundation
import QuickLookThumbnailing

/// `RemoteFileClient` over a folder picked in the Files app — Dropbox,
/// Google Drive, OneDrive, iCloud Drive, On My iPhone (FS-17.05). Paths are
/// relative to that folder and never leave it. Every read and write goes
/// through `NSFileCoordinator`, which is how the service's app downloads a
/// cloud-only file or picks up a new one to sync.
///
/// `@unchecked Sendable`: the browse session and the upload session call
/// one method at a time, as with the other clients.
final class FilesFolderClient: RemoteFileClient, @unchecked Sendable {
    private let server: FileServer
    private var root: URL?
    private var isAccessing = false

    init(server: FileServer) {
        self.server = server
    }

    static let folderGone = String(localized: "ShotDex can't open this folder anymore. Add it again.", comment: "Cloud folder error: the saved bookmark no longer resolves")

    func connect() async throws {
        guard let bookmark = server.bookmark else { throw RemoteFileError.other(Self.folderGone) }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale) else {
            throw RemoteFileError.other(Self.folderGone)
        }
        if isAccessing { root?.stopAccessingSecurityScopedResource() }
        isAccessing = url.startAccessingSecurityScopedResource()
        root = url
        guard (try? url.checkResourceIsReachable()) == true else {
            await disconnect()
            throw RemoteFileError.other(Self.folderGone)
        }
    }

    func disconnect() async {
        if isAccessing { root?.stopAccessingSecurityScopedResource() }
        isAccessing = false
        root = nil
    }

    // MARK: Paths

    /// `path` inside the picked folder. `..`, `.` and absolute paths are
    /// refused: this client only ever touches what the user chose.
    func url(_ path: String) throws -> URL {
        guard let root else { throw RemoteFileError.connectionLost }
        guard !path.hasPrefix("/") else { throw RemoteFileError.permissionDenied(path) }
        let parts = path.split(separator: "/").map(String.init)
        guard !parts.contains(".."), !parts.contains(".") else { throw RemoteFileError.permissionDenied(path) }
        return parts.reduce(root) { $0.appendingPathComponent($1) }
    }

    // MARK: Coordination

    /// Coordinated work off the cooperative pool: a read may wait for the
    /// service to download the file.
    private func coordinated<T>(_ body: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try body() })
            }
        }
    }

    private static func read<T>(_ url: URL, options: NSFileCoordinator.ReadingOptions = [], _ body: (URL) throws -> T) throws -> T {
        var coordinatorError: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: options, error: &coordinatorError) { url in
            result = Result { try body(url) }
        }
        if let coordinatorError { throw map(coordinatorError, path: url.lastPathComponent) }
        guard let result else { throw RemoteFileError.connectionLost }
        return try result.get()
    }

    private static func write<T>(_ url: URL, options: NSFileCoordinator.WritingOptions, _ body: (URL) throws -> T) throws -> T {
        var coordinatorError: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: options, error: &coordinatorError) { url in
            result = Result { try body(url) }
        }
        if let coordinatorError { throw map(coordinatorError, path: url.lastPathComponent) }
        guard let result else { throw RemoteFileError.connectionLost }
        return try result.get()
    }

    static func map(_ error: Error, path: String) -> Error {
        if error is RemoteFileError || error is CancellationError { return error }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError: return RemoteFileError.folderMissing(path)
            case NSFileWriteNoPermissionError, NSFileReadNoPermissionError: return RemoteFileError.permissionDenied(path)
            case NSFileWriteOutOfSpaceError: return RemoteFileError.serverFull
            default: break
            }
        }
        return RemoteFileError.other(nsError.localizedDescription)
    }

    private static let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]

    // MARK: RemoteFileClient

    var peeksWithSystemThumbnails: Bool { true }

    func fileSize(at path: String) async throws -> Int64? {
        let url = try url(path)
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        guard let values, values.isDirectory != true, let size = values.fileSize else { return nil }
        return Int64(size)
    }

    func directoryExists(_ path: String) async throws -> Bool {
        let url = try url(path)
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    func fileNames(in directory: String) async throws -> Set<String> {
        Set(try await entries(in: directory).filter { !$0.isDirectory }.map(\.name))
    }

    func folderNames(in directory: String) async throws -> Set<String> {
        Set(try await entries(in: directory).filter(\.isDirectory).map(\.name))
    }

    func entries(in directory: String) async throws -> [RemoteEntry] {
        let url = try url(directory)
        return try await coordinated {
            try Self.read(url, options: .immediatelyAvailableMetadataOnly) { url in
                guard FileManager.default.fileExists(atPath: url.path) else { return [] }
                let items = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Self.keys)
                return items.map { item in
                    let values = try? item.resourceValues(forKeys: Set(Self.keys))
                    return RemoteEntry(
                        name: item.lastPathComponent,
                        isDirectory: values?.isDirectory ?? false,
                        size: Int64(values?.fileSize ?? 0),
                        modified: values?.contentModificationDate
                    )
                }
            }
        }
    }

    func createDirectory(_ path: String) async throws {
        let url = try url(path)
        try await coordinated {
            try Self.write(url, options: .forMerging) { url in
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
    }

    func upload(_ localURL: URL, to path: String, progress: @escaping @Sendable (Int64) -> Void) async throws {
        let url = try url(path)
        let size = (try? localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0 ?? 0) } ?? 0
        try await coordinated {
            try Self.write(url, options: .forReplacing) { url in
                guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path) else {
                    throw RemoteFileError.folderMissing(path)
                }
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                try FileManager.default.copyItem(at: localURL, to: url)
            }
        }
        try Task.checkCancellation()
        progress(size)
    }

    func sha256(of path: String, progress: @escaping @Sendable (Int64) -> Void) async throws -> String {
        let url = try url(path)
        let hash = try await coordinated {
            try Self.read(url) { url in try FileChecksum.sha256(of: url) }
        }
        progress(try await fileSize(at: path) ?? 0)
        return hash
    }

    func readRange(_ path: String, offset: Int64, length: Int) async throws -> Data {
        let url = try url(path)
        return try await coordinated {
            try Self.read(url) { url in
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                try handle.seek(toOffset: UInt64(max(0, offset)))
                return try handle.read(upToCount: length) ?? Data()
            }
        }
    }

    func download(_ path: String, to localURL: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> String {
        let url = try url(path)
        let hash = try await coordinated {
            try Self.read(url) { url in
                if FileManager.default.fileExists(atPath: localURL.path) { try FileManager.default.removeItem(at: localURL) }
                try FileManager.default.copyItem(at: url, to: localURL)
                return try FileChecksum.sha256(of: localURL)
            }
        }
        progress((try? localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0 ?? 0) } ?? 0)
        return hash
    }

    func move(_ source: String, to destination: String) async throws {
        let from = try url(source)
        let to = try url(destination)
        try await coordinated {
            var coordinatorError: NSError?
            var failure: Error?
            NSFileCoordinator().coordinate(writingItemAt: from, options: .forMoving, writingItemAt: to, options: .forReplacing, error: &coordinatorError) { from, to in
                do {
                    guard !FileManager.default.fileExists(atPath: to.path) else {
                        throw RemoteFileError.other(String(localized: "An item with that name already exists.", comment: "Cloud folder: rename onto an existing name"))
                    }
                    try FileManager.default.moveItem(at: from, to: to)
                } catch {
                    failure = error
                }
            }
            if let coordinatorError { throw Self.map(coordinatorError, path: destination) }
            if let failure { throw Self.map(failure, path: destination) }
        }
    }

    func remove(_ path: String) async throws {
        let url = try url(path)
        try await coordinated {
            try Self.write(url, options: .forDeleting) { url in
                guard FileManager.default.fileExists(atPath: url.path) else { return }
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    func removeEmptyDirectory(_ path: String) async throws {
        try await remove(path)
    }

    /// One coordinated delete takes the folder and what is in it.
    func removeFolderTree(_ path: String) async throws {
        guard !ServerUploadPath.normalizedFolder(path).isEmpty else { throw RemoteFileError.permissionDenied(path) }
        try await remove(path)
    }

    func systemThumbnail(at path: String, maxPixelSize: Int) async -> CGImage? {
        guard let url = try? url(path) else { return nil }
        let side = CGFloat(maxPixelSize)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side), scale: 1, representationTypes: .thumbnail)
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).cgImage
    }
}

extension FilesFolderClient {
    /// How a picked folder is described on its row (FS-17.05 §2): the
    /// service, from where the Files app keeps its folders, and the folder.
    static func describe(_ url: URL) -> (service: String, folder: String) {
        let parts = url.standardizedFileURL.pathComponents
        let service: String
        if let index = parts.firstIndex(of: "CloudStorage"), index + 1 < parts.count {
            // `GoogleDrive-name@example.com`, `Dropbox`, `OneDrive-Personal`.
            service = parts[index + 1].split(separator: "-").first.map(String.init) ?? parts[index + 1]
        } else if parts.contains("com~apple~CloudDocs") || parts.contains(where: { $0.hasPrefix("iCloud~") }) {
            service = String(localized: "iCloud Drive", comment: "Cloud folder row: the service")
        } else if parts.contains("File Provider Storage") || parts.contains("Documents") {
            service = String(localized: "On My iPhone", comment: "Cloud folder row: a folder on this device in Files")
        } else {
            service = String(localized: "Files", comment: "Cloud folder row: a folder from the Files app, service unknown")
        }
        let spaced = service.replacingOccurrences(of: "GoogleDrive", with: "Google Drive")
        return (spaced, url.lastPathComponent)
    }
}
