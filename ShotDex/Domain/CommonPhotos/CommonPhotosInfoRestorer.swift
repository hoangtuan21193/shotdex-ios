import Foundation

/// Restore File Info… (FS-19.08 §6e): the copies a Copy run left in the
/// shared folder without their sources' dates — every run before §6e, or a
/// server that refused at the time — get them now. No byte is copied or
/// hashed: a copy still at its path with the photo's size takes the first
/// folder's dates and flags; one changed in the shared folder, or whose
/// first-folder copy is gone, is said and left alone. Each row is written
/// as it is done, so a Stop keeps what is done and running it again does
/// the rest. It holds the run's claim, as a run does: never beside the
/// helper's runner or an undo of the same run.
struct CommonPhotosInfoRestorer: Sendable {
    let client: any RemoteFileClient
    let store: CommonPhotosStore

    struct Progress: Equatable, Sendable {
        var done = 0, total = 0
        var restored = 0
        /// Left as they were: changed in the shared folder, or no first-folder copy.
        var leftAlone = 0
        /// The server took the request and kept another date.
        var refused = 0
    }

    /// Why a run cannot be restored now.
    enum Refusal: Error, Equatable {
        case busy
    }

    /// The reasons a restore writes, and the only ones it clears: a Copied
    /// row's own warning (`sidecarNotCopied`) is never overwritten.
    static let ownReasons: Set<CommonPhotosItem.Reason> = [.changedInShared, .noSource]

    /// The rows it works on: a Copy run's Copied rows whose copy did not
    /// keep its info, within `positions` when given (the selection). A row a
    /// restore already left alone stays out: its reason says why.
    static func candidates(_ items: [CommonPhotosItem], run: CommonPhotosRun, positions: Set<Int>? = nil) -> [CommonPhotosItem] {
        guard run.action == .copy, !run.isUndo else { return [] }
        return items.filter {
            $0.status == .copied && $0.fileInfo != .kept && $0.fileInfo != .tagsNotKept && $0.destinationPath != nil
                && !(($0.failure?.reason).map(ownReasons.contains) ?? false)
                && (positions?.contains($0.position) ?? true)
        }
    }

    @discardableResult
    func run(_ runId: String, positions: Set<Int>? = nil,
             progress: @escaping @Sendable (Progress) -> Void = { _ in }) async throws -> Progress {
        guard let run = try store.run(id: runId) else { throw CommonPhotosStore.RunMissing(runId: runId) }
        guard try store.undoRuns(of: runId).allSatisfy(\.isOver),
              CommonPhotosRunner.claim(runId: runId, in: store.database) else { throw Refusal.busy }
        defer { CommonPhotosRunner.release(runId: runId, in: store.database) }
        let rows = Self.candidates(try store.items(runId: runId), run: run, positions: positions)
        var state = Progress(total: rows.count)
        progress(state)
        let write = VerifiedRemoteWrite(client: client)
        var outcomes: [FileInfoOutcome] = []
        // What the server did, even when stopped part way (§6e).
        defer {
            if let keeps = ServerFileInfoSupport.keepsDates(from: outcomes) {
                try? ServerFileInfoSupport.record(connectionId: run.connectionId, keepsDates: keeps, in: store.database)
            }
        }
        for item in rows {
            try Task.checkCancellation()
            guard let copy = item.destinationPath else { continue }
            // Another reason the row had (a sidecar not copied) stays.
            let kept = (item.failure?.reason).map { Self.ownReasons.contains($0) } == false ? item.reason : nil
            var fileInfo = item.fileInfo
            var reason = kept
            if try await client.fileSize(at: copy) != item.size {
                reason = kept ?? CommonPhotosItem.reason(.changedInShared)
                state.leftAlone += 1
            } else if let source = item.sources.first?.path, let info = try await client.sourceInfo(at: source) {
                guard let outcome = await write.applyInfo(info, to: copy) else { throw CancellationError() }
                fileInfo = outcome
                outcomes.append(outcome)
                if outcome == .kept { state.restored += 1 } else { state.refused += 1 }
            } else {
                reason = kept ?? CommonPhotosItem.reason(.noSource)
                state.leftAlone += 1
            }
            try store.setRestoredInfo(runId: runId, position: item.position, fileInfo: fileInfo, reason: reason)
            state.done += 1
            progress(state)
        }
        return state
    }
}
