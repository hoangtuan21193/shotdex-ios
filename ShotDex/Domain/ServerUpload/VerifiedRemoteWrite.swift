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
    /// when the caller chose Replace. With `info`, the file also gets its
    /// source's dates and flags (FS-19.08 §6e): set on the part before the
    /// rename (a rename keeps them), read-only only after it (a read-only
    /// part could not be renamed or cleaned up everywhere), then read back.
    /// Returns what became of them — nil without `info`, and nil when the
    /// task was cancelled after the rename, so a resumed run sets them again
    /// instead of recording a verdict it never reached. The info never fails
    /// the write: the bytes are already checked.
    @discardableResult
    func moveIntoPlace(_ destination: String, replacing: Bool, info: RemoteFileInfo? = nil) async throws -> FileInfoOutcome? {
        let part = ServerUploadPath.partPath(for: destination)
        var answer: FileInfoSupport?
        if let info {
            answer = try? await client.setFileInfo(info.writable, at: part)
        }
        if replacing {
            try await client.remove(destination)
        }
        try await client.move(part, to: destination)
        guard let info, !Task.isCancelled else { return nil }
        return await verdict(answer, info: info, at: destination)
    }

    /// After the first request (streams, dates and flags but read-only):
    /// read-only now — the streams went with the first — then read back.
    private func verdict(_ answer: FileInfoSupport?, info: RemoteFileInfo, at destination: String) async -> FileInfoOutcome? {
        guard answer == .applied || answer == .appliedWithoutStreams else { return .datesNotKept }
        if info.isReadOnly {
            _ = try? await client.setFileInfo(info.withoutStreams, at: destination)
        }
        guard !Task.isCancelled else { return nil }
        guard let landed = try? await client.fileInfo(at: destination), landed.hasSameModified(as: info) else {
            return Task.isCancelled ? nil : .datesNotKept
        }
        // Dates held; tags only when every stream went across.
        return answer == .appliedWithoutStreams || info.hasUnreadStreams ? .tagsNotKept : .kept
    }

    /// Dates and flags for a file already in place — Restore File Info…
    /// (FS-19.08 §6e) and a server-side copy. Same order as above minus the
    /// rename: read-only last, then read back. Nil when cancelled.
    func applyInfo(_ info: RemoteFileInfo, to destination: String) async -> FileInfoOutcome? {
        let answer = try? await client.setFileInfo(info.writable, at: destination)
        guard !Task.isCancelled else { return nil }
        return await verdict(answer, info: info, at: destination)
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
