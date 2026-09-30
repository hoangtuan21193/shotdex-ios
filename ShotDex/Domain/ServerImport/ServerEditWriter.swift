import Foundation

/// Where an export lands beside its original on the server (FS-17.06 §6).
enum ServerEditPlacement: Equatable, Sendable {
    /// `<name>_edited.<ext>`, then ` (2)`, ` (3)`… — the original untouched.
    case newFile
    /// Under the original's own name. The original is deleted only once the
    /// new file has been read back and matched.
    case replaceOriginal
}

enum ServerEditWriteError: Error, Equatable, LocalizedError {
    case checksumMismatch

    var errorDescription: String? {
        String(localized: "The copy on the server didn't match the original.", comment: "Upload to Server: checksum read back from the server differs")
    }
}

/// Writes one rendered file from this device to a server folder, with the
/// upload's guarantees (FS-15.02 §4): no real name on the server ever points
/// at a file that was not read back and matched.
enum ServerEditWriter {
    /// The server path the file landed on.
    static func write(
        _ local: URL,
        originalName: String,
        into folder: String,
        placement: ServerEditPlacement,
        client: any RemoteFileClient,
        progress: @escaping @Sendable (Int64) -> Void = { _ in }
    ) async throws -> String {
        if !folder.isEmpty { try await client.createDirectory(folder) }
        let destination: String
        switch placement {
        case .newFile:
            let existing = try await client.fileNames(in: folder)
            let edited = ServerUploadPath.editedFilename(original: originalName, rendered: local.lastPathComponent)
            destination = ServerUploadPath.join(folder, ServerUploadPath.nextFreeName(for: edited, existing: existing))
        case .replaceOriginal:
            destination = ServerUploadPath.join(folder, originalName)
        }
        let localHash = try FileChecksum.sha256(of: local)
        let part = ServerUploadPath.partPath(for: destination)
        do {
            try await client.upload(local, to: part, progress: progress)
            let remoteHash = try await client.sha256(of: part) { _ in }
            try Task.checkCancellation()
            guard remoteHash == localHash else { throw ServerEditWriteError.checksumMismatch }
            if placement == .replaceOriginal {
                try await client.remove(destination)
            }
            try await client.move(part, to: destination)
        } catch {
            // Detached: a cancelled task's own awaits may throw at once, and
            // the part must still go.
            await Task.detached { try? await client.remove(part) }.value
            throw error
        }
        return destination
    }
}
