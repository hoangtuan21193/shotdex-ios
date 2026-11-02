import Foundation

/// The one way a file gets onto a server (FS-15.02 §4): streamed up under a
/// `.shotdex-part` name, read back and hashed, and only then given its real
/// name — so nothing under a real name is ever unverified. Upload and Backup
/// (FS-22.02 §2) both go through it; each keeps its own events and records
/// between the steps.
struct VerifiedRemoteWrite: Sendable {
    let client: any RemoteFileClient

    /// Creates the folder and streams `local` up as `<destination>.shotdex-part`.
    func uploadPart(_ local: URL, for destination: String, progress: @escaping @Sendable (Int64) -> Void) async throws {
        try await client.createDirectory(ServerUploadPath.parent(of: destination))
        try await client.upload(local, to: ServerUploadPath.partPath(for: destination), progress: progress)
    }

    /// Reads the part back from the server and returns its SHA-256.
    func readBackSHA256(for destination: String, progress: @escaping @Sendable (Int64) -> Void) async throws -> String {
        try await client.sha256(of: ServerUploadPath.partPath(for: destination), progress: progress)
    }

    /// Gives the checked part its real name, removing what was there first
    /// when the caller chose Replace.
    func moveIntoPlace(_ destination: String, replacing: Bool) async throws {
        if replacing {
            try await client.remove(destination)
        }
        try await client.move(ServerUploadPath.partPath(for: destination), to: destination)
    }

    /// Removes the part. Runs even when the caller was cancelled: a cancelled
    /// task's own awaits may throw at once, and the part must still go.
    /// False when the server refused, so a caller that records the part can
    /// keep pointing at it.
    @discardableResult
    func discardPart(for destination: String) async -> Bool {
        let client = client
        let part = ServerUploadPath.partPath(for: destination)
        return await Task.detached { (try? await client.remove(part)) != nil }.value
    }
}
