import Foundation

/// Carries out an undo run (FS-19.08 §6b): takes back what a common-photos
/// run put in the destination, from the log alone, one server command at a
/// time. An undo run is a run of its own (`undoOf`), so it pauses, stops
/// and resumes like one; its rows are copies of the rows it undoes, keeping
/// their position.
///
/// Undo Copy: the copy in the destination goes only when it still holds the
/// bytes the run put there and some source still holds them too — the last
/// copy is never removed. It goes the way a Move removes a source: set
/// aside, the other copy checked still there (two paths to one file would
/// make it vanish), then deleted. The `.xmp` the run wrote goes with it,
/// unless another photo of the run still needs it.
///
/// Every row done here is written back to the run's own row as `undone`,
/// so a second undo never takes the same photo back twice.
struct CommonPhotosUndoer: Sendable {
    let client: any RemoteFileClient
    let store: CommonPhotosStore
    /// Where a photo sits on this Mac between download and upload (Undo
    /// Move) — one at a time.
    let workDirectory: URL

    typealias Progress = CommonPhotosRunner.Progress
    typealias Stop = CommonPhotosRunner.Stop

    private var checks: CommonPhotosServerChecks { CommonPhotosServerChecks(client: client) }

    /// Undoes every row not done yet. Returns when all are done; throws when
    /// the server went away or the task was cancelled — the run is then
    /// paused, and done rows stay done.
    func run(_ runId: String, progress: @escaping @Sendable (Progress) -> Void = { _ in }) async throws {
        guard CommonPhotosRunner.claim(runId: runId, in: store.database) else { throw Stop.alreadyRunning }
        defer { CommonPhotosRunner.release(runId: runId, in: store.database) }
        guard let run = try store.run(id: runId) else { throw CommonPhotosStore.RunMissing(runId: runId) }
        guard run.canResume, let originalId = run.undoOf else { throw Stop.notResumable }
        // Undo Move lands with U3 of the plan; until then it is refused
        // before anything is touched.
        guard run.action == .copy else { throw Stop.notResumable }
        try store.markState(.running, runId: runId)
        // Rows a quit left undone here but not yet on the run's own row.
        try store.markUndone(runId: originalId, positions: try store.items(runId: runId).filter { $0.status == .undone }.map(\.position))
        var items = try store.items(runId: runId)
        var originals = Dictionary(uniqueKeysWithValues: try store.items(runId: originalId).map { ($0.position, $0) })
        var state = Progress(doneCount: items.filter(\.isDone).count, totalCount: items.count,
                             doneBytes: items.filter(\.isDone).reduce(0) { $0 + $1.size },
                             totalBytes: items.reduce(0) { $0 + $1.size })
        progress(state)
        do {
            for index in items.indices where !items[index].isDone {
                try Task.checkCancellation()
                switch run.action {
                case .copy:
                    try await undoCopy(&items[index], originalId: originalId, originals: originals, state: state, progress: progress)
                case .move:
                    throw Stop.notResumable
                }
                if items[index].status == .undone { originals[items[index].position]?.status = .undone }
                state.doneCount += 1
                state.doneBytes += items[index].size
                state.currentName = nil
                state.currentStep = nil
                progress(state)
            }
            try store.markState(.finishing, runId: runId)
            try store.markState(.finished, runId: runId)
        } catch {
            if let state = try? store.run(id: runId)?.state, state != .finishing { try? store.markState(.paused, runId: runId) }
            throw error
        }
    }

    // MARK: Undo Copy

    /// One photo, Copy. Done in steps any of which a stop may cut short;
    /// each is looked at on the server again on resume, so a photo set
    /// aside and not yet deleted is finished, not left behind.
    private func undoCopy(_ item: inout CommonPhotosItem, originalId: String, originals: [Int: CommonPhotosItem],
                          state: Progress, progress: @escaping @Sendable (Progress) -> Void) async throws {
        guard let placed = item.destinationPath else {
            try finish(&item, .failed, reason: .unreadableRecord)
            return
        }
        let name = ServerUploadPath.lastComponent(of: placed)
        let report = { @Sendable (step: Progress.Step) in
            var moving = state
            moving.currentName = name
            moving.currentStep = step
            progress(moving)
        }
        report(.checking)
        // Every source still holding the bytes: the last copy stays, and
        // each is checked again after the set-aside (any could be the same
        // file as the destination under another path).
        let others = try await presentSources(of: item)
        guard !others.isEmpty else {
            try finish(&item, .failed, reason: .noOtherCopy)
            return
        }
        let aside = placed + CommonPhotosRunner.removingSuffix
        do {
            if try await client.fileSize(at: placed) != nil {
                guard try await checks.holds(placed, size: item.size, sha256: item.sha256) else {
                    try finish(&item, .failed, reason: .changedInShared)
                    return
                }
                report(.removing)
                try await client.move(placed, to: aside)
            } else if try await client.fileSize(at: aside) != nil {
                // Set aside by a stop before it was deleted: still ours?
                guard try await checks.holds(aside, size: item.size, sha256: item.sha256) else {
                    try await putBack(aside, to: placed)
                    try finish(&item, .failed, reason: .changedInShared)
                    return
                }
                report(.removing)
            } else {
                // Gone already (deleted before it was recorded).
                try await finishPhoto(&item, originalId: originalId, originals: originals)
                return
            }
        } catch {
            // The rename's reply can be an error after the server did it:
            // never left hidden under the aside name.
            await putBackIfAside(aside, placed: placed)
            guard let remote = error as? RemoteFileError, !remote.stopsBatch else { throw error }
            try finish(&item, .failed, reason: .serverError, detail: remote.localizedDescription)
            return
        }
        do {
            try await removeAside(aside, restoring: placed, others: others)
        } catch {
            // Pause, Stop or a server error: back under its name, so a
            // Discard of this undo leaves nothing hidden.
            await putBackIfAside(aside, placed: placed)
            guard let remote = error as? RemoteFileError, !remote.stopsBatch else { throw error }
            try finish(&item, .failed, reason: .serverError, detail: remote.localizedDescription)
            return
        }
        try await finishPhoto(&item, originalId: originalId, originals: originals)
    }

    /// The photo is out of the destination: its `.xmp`, then the row — the
    /// undo row and the run's own row in one write. A sidecar that will not
    /// go is noted on a row that is still Undone, since the photo is.
    private func finishPhoto(_ item: inout CommonPhotosItem, originalId: String, originals: [Int: CommonPhotosItem]) async throws {
        try Task.checkCancellation()
        var detail: String?
        do {
            try await removeSidecar(of: item, originals: originals)
        } catch let error as RemoteFileError where !error.stopsBatch {
            detail = error.localizedDescription
        } catch let stop as Stop {
            // The sidecar went back; the photo is still gone.
            detail = stop.localizedDescription
        }
        item.status = .undone
        item.partPath = nil
        item.reason = detail.map { CommonPhotosItem.reason(.serverError, $0) }
        try store.finishUndo(item, originalRunId: originalId)
    }

    /// Sources not removed that still hold the bytes: the size and write
    /// time of the scan, or — the write time moved — the SHA-256. A folder
    /// gone or unreadable counts as no copy there.
    private func presentSources(of item: CommonPhotosItem) async throws -> [CommonPhotosItem.Source] {
        var present: [CommonPhotosItem.Source] = []
        for source in item.sources where !source.isRemoved {
            do {
                if try await checks.isUnchanged(source, sha256: item.sha256) {
                    present.append(source)
                } else if try await checks.holds(source.path, size: item.size, sha256: item.sha256) {
                    present.append(source)
                }
            } catch let error as RemoteFileError where !error.stopsBatch {
                continue
            }
        }
        return present
    }

    /// The `.xmp` the run wrote for this photo, while it holds the bytes
    /// written, some source sidecar still holds them too, and no other
    /// photo of the run still in place uses the same file in the
    /// destination. Two photos can share one (`IMG_1.JPG` and `IMG_1.MOV`
    /// both get `IMG_1.xmp`) and only the first records it, so the last of
    /// them to be undone takes it. A sidecar that was there before the run
    /// is never recorded, so never touched.
    private func removeSidecar(of item: CommonPhotosItem, originals: [Int: CommonPhotosItem]) async throws {
        guard let target = Self.sidecarInDestination(of: item) else { return }
        let sharing = originals.values.filter { $0.position != item.position && Self.sidecarInDestination(of: $0) == target }
        guard !sharing.contains(where: { $0.status != .undone && $0.status != .failed }) else { return }
        guard let claim = ([item] + sharing).first(where: { $0.sidecarPlaced == target }),
              let sha256 = claim.sidecarSHA256 else { return }
        // Some source sidecar must still hold the same bytes.
        var others: [CommonPhotosItem.Source] = []
        for row in [item] + sharing {
            for source in row.sources where !source.isRemoved {
                guard let sidecar = source.sidecar, !others.contains(where: { $0.path == sidecar }),
                      let size = try await client.fileSize(at: sidecar),
                      try await client.sha256(of: sidecar, progress: { _ in }) == sha256 else { continue }
                others.append(CommonPhotosItem.Source(path: sidecar, size: size, modifiedAt: nil))
            }
        }
        guard !others.isEmpty else { return }
        let aside = target + CommonPhotosRunner.removingSuffix
        if try await client.fileSize(at: target) != nil {
            guard try await client.sha256(of: target, progress: { _ in }) == sha256 else { return }
            try await client.move(target, to: aside)
        } else if try await client.fileSize(at: aside) != nil {
            guard try await client.sha256(of: aside, progress: { _ in }) == sha256 else { return }
        } else {
            return
        }
        do {
            try await removeAside(aside, restoring: target, others: others)
        } catch {
            await putBackIfAside(aside, placed: target)
            throw error
        }
    }

    /// Where the photo's `.xmp` sits in the destination: beside its final
    /// name, in the form its source named it.
    private static func sidecarInDestination(of item: CommonPhotosItem) -> String? {
        guard let placed = item.destinationPath,
              let source = item.sources.first(where: { $0.sidecar != nil }), let sidecar = source.sidecar else { return nil }
        return CommonPhotosServerChecks.sidecarTarget(sidecar, photoPath: source.path,
                                                     photoName: ServerUploadPath.lastComponent(of: placed),
                                                     folder: ServerUploadPath.parent(of: placed))
    }

    /// Deletes a copy set aside — after checking every other copy still has
    /// its size. One that vanished with the rename was the same file: the
    /// copy goes back where it was and the run stops.
    private func removeAside(_ aside: String, restoring original: String, others: [CommonPhotosItem.Source]) async throws {
        for other in others {
            guard try await client.fileSize(at: other.path) == other.size else {
                try await putBack(aside, to: original)
                throw Stop.destinationIsASource
            }
        }
        try await client.remove(aside)
    }

    /// Puts `aside` back as `placed` when that is where things stand — the
    /// name free and the aside there. Best effort: a server gone leaves it
    /// for Resume, which finishes from the aside.
    private func putBackIfAside(_ aside: String, placed: String) async {
        let client = client
        await Task.detached {
            guard case .some(nil) = await Self.size(of: placed, client: client),
                  case .some(.some) = await Self.size(of: aside, client: client) else { return }
            try? await client.move(aside, to: placed)
        }.value
    }

    /// The size at `path`: nil when the server could not say, `.some(nil)`
    /// when nothing is there.
    private static func size(of path: String, client: any RemoteFileClient) async -> Int64?? {
        do { return .some(try await client.fileSize(at: path)) } catch { return nil }
    }

    /// A copy set aside goes back to its name — even while the task is
    /// being cancelled: left aside, it would be missing from where the user
    /// looks.
    private func putBack(_ aside: String, to original: String) async throws {
        let client = client
        try await Task.detached { try await client.move(aside, to: original) }.value
    }

    private func finish(_ item: inout CommonPhotosItem, _ status: CommonPhotosItem.Status,
                        reason: CommonPhotosItem.Reason? = nil, detail: String? = nil) throws {
        item.status = status
        item.partPath = nil
        item.reason = reason.map { CommonPhotosItem.reason($0, detail) }
        try store.update(item)
    }
}
