import Foundation

/// A folder on a saved connection as Export…'s destination (FS-03.07b §7):
/// each file is made in a scratch file on this device — one at a time, as
/// FS-15 §5 — then sent with the upload's guarantees through
/// `ServerEditWriter`: part name, SHA-256 read back, real name. No upload
/// history is written: a 2048 px copy on the NAS must never make the
/// original look backed up (FS-15.02 §7).
struct RemoteFolderWriter: ExportDestinationWriter {
    let access: any RemoteFileAccess
    /// The chosen folder on the server.
    let folder: String
    /// Where a file waits between its render and its upload.
    let scratch: URL

    func path(_ sub: String) -> String { ServerUploadPath.join(folder, sub) }

    func existingNames(in sub: String) async throws -> Set<String> {
        do {
            return try await access.perform { client in try await client.fileNames(in: path(sub)) }
        } catch {
            throw Self.failure(error)
        }
    }

    func freeBytes() async -> Int64? {
        try? await access.perform { client in try await client.storageSpace(at: folder)?.free }
    }

    func sweepLeftoverParts(in sub: String) async {
        let directory = path(sub)
        _ = try? await access.perform { client in
            for name in try await client.fileNames(in: directory) where name.hasSuffix(ServerUploadPath.partSuffix) {
                try? await client.remove(ServerUploadPath.join(directory, name))
            }
        }
    }

    func write(
        name: String,
        in sub: String,
        replacing: Bool,
        produce: @Sendable (URL) async throws -> Void
    ) async throws -> ExportWrittenFile {
        let directory = scratch.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let local = directory.appendingPathComponent(name)
        FileManager.default.createFile(atPath: local.path, contents: nil)
        try await produce(local)
        try Task.checkCancellation()
        try LocalFolderWriter.checkComplete(local)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: local.path)[.size] as? Int64) ?? 0
        let target = path(sub)
        do {
            let landed = try await access.perform { client in
                try await ServerEditWriter.write(local, originalName: name, into: target,
                                                 placement: replacing ? .replaceOriginal : .asNamed, client: client)
            }
            return ExportWrittenFile(path: landed, bytes: bytes)
        } catch {
            throw Self.failure(error)
        }
    }

    /// The server's words in the export's: a connection that is gone stops
    /// the batch like a pulled drive.
    static func failure(_ error: Error) -> Error {
        guard let remote = error as? RemoteFileError else { return error }
        switch remote {
        case .permissionDenied: return FileExportFailure.permissionDenied
        case .serverFull: return FileExportFailure.full
        case .unreachable, .connectionLost, .authenticationFailed, .localNetworkDenied, .hostKeyChanged, .hostKeyUntrusted, .folderMissing:
            return FileExportFailure.disconnected
        case .fileMissing, .other: return error
        }
    }
}
