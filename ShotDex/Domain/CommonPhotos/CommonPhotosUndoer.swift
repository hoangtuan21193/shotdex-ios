import CryptoKit
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
/// Undo Move: each copy the run removed is written back from the bytes in
/// the destination — uploaded as a part, read back, then given its name —
/// unless its old path now holds other bytes, which are never written over.
/// The copy the run renamed into the destination is renamed back when its
/// old path is free. The destination copy goes last, and only once every
/// removed copy is back; at every step the photo has at least one checked
/// copy on the server.
///
/// Every row done here is written back to the run's own row as `undone`,
/// so a second undo never takes the same photo back twice.
struct CommonPhotosUndoer: Sendable {
    let client: any RemoteFileClient
    let store: CommonPhotosStore
    /// Where a photo sits on this Mac between download and upload (Undo
    /// Move) — one at a time.
    let workDirectory: URL
    /// Free bytes on this Mac; nil = unknown.
    var freeBytes: @Sendable () -> Int64? = { nil }
    /// After the last row and the CSV: put back the upload, download and
    /// Backup history, rescan. `restored` is every source path the undo's
    /// rows hold as not removed; only those a Move recorded moving history
    /// from are acted on (`CommonPhotosStore.restoreHistory`). Thrown errors leave the undo `finishing`, so Resume does it
    /// again.
    var afterUndo: @Sendable (CommonPhotosRun, Set<String>) async throws -> Void = { _, _ in }
    /// Now, and the zone it is told in, for the CSV's name.
    var now: @Sendable () -> Date = { Date() }
    var timeZone: TimeZone = .current

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
                    try await undoMove(&items[index], originalId: originalId, originals: originals, state: state, progress: progress)
                }
                if items[index].status == .undone { originals[items[index].position]?.status = .undone }
                state.doneCount += 1
                state.doneBytes += items[index].size
                state.currentName = nil
                state.currentStep = nil
                progress(state)
            }
            try await removeEmptyFolders(madeBy: originalId, destination: run.destination)
            try store.markState(.finishing, runId: runId)
            let csvPath = try await writeLog(items, run: run, originalId: originalId)
            let restored = Set(items.flatMap { $0.sources.filter { !$0.isRemoved }.map(\.path) })
            try await afterUndo(run, restored)
            try store.markState(.finished, runId: runId, csvPath: csvPath)
        } catch {
            if let state = try? store.run(id: runId)?.state, state != .finishing { try? store.markState(.paused, runId: runId) }
            throw error
        }
    }

    /// The folders the run made for Organize (§6e) that its photos leaving
    /// left empty — deepest first, so `2025/03/15` goes before `2025/03`.
    /// A folder anything else is in (a photo not undone, a file the user put
    /// there) stays; one already gone, or that the server will not remove,
    /// is left as it is.
    private func removeEmptyFolders(madeBy originalId: String, destination: String) async throws {
        guard let made = try store.run(id: originalId)?.createdFolders, !made.isEmpty else { return }
        for folder in made.sorted(by: { $0.split(separator: "/").count > $1.split(separator: "/").count }) {
            try Task.checkCancellation()
            let path = ServerUploadPath.join(destination, folder)
            do {
                guard try await client.entries(in: path).isEmpty else { continue }
                try await client.removeEmptyDirectory(path)
            } catch let error as RemoteFileError where !error.stopsBatch {
                continue
            }
        }
    }

    // MARK: CSV

    /// Every photo of the run taken back: the run's CSV goes, with the CSVs
    /// of earlier undos of it. Otherwise this undo's rows go in
    /// `… Undo.csv` beside the photos, through the same verified write;
    /// written once — a Resume finds the one it recorded.
    private func writeLog(_ items: [CommonPhotosItem], run: CommonPhotosRun, originalId: String) async throws -> String? {
        if !(try store.items(runId: originalId)).contains(where: \.isUndoable) {
            let runs = ([try store.run(id: originalId)] + (try store.undoRuns(of: originalId)).filter { $0.id != run.id })
                .compactMap { $0 }.filter { $0.csvPath != nil }
            for log in runs {
                guard let path = log.csvPath, try await isOurLog(path, destination: run.destination) else { continue }
                try await client.remove(path)
            }
            try store.forgetCSVs(runIds: runs.map(\.id))
            return nil
        }
        let recorded = try store.run(id: run.id)?.csvPath
        if let recorded, try await isOurLog(recorded, destination: run.destination) { return recorded }
        // The folder may be gone (the user deleted it): the log still goes
        // where the photos went.
        try await client.createDirectory(run.destination)
        let names = Set(try await client.entries(in: run.destination).map(\.name))
        let target = recorded ?? ServerUploadPath.join(run.destination, ServerUploadPath.nextFreeName(
            for: CommonPhotosLog.undoCSVName(at: now(), timeZone: timeZone), existing: names))
        try store.markState(.finishing, runId: run.id, csvPath: target)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        let local = workDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        defer { try? FileManager.default.removeItem(at: local) }
        let data = Data(CommonPhotosLog.csv(items, isUndo: true).utf8)
        try data.write(to: local)
        let write = VerifiedRemoteWrite(client: client)
        do {
            try await write.uploadPart(local, for: target, progress: { _ in })
            guard try await write.readBackSHA256(for: target, progress: { _ in }) == FileChecksum.hex(SHA256.hash(data: data)) else {
                throw RemoteFileError.other("checksum mismatch")
            }
            try await write.moveIntoPlace(target, replacing: false)
        } catch {
            await write.discardPart(for: target)
            throw error
        }
        return target
    }

    /// Whether `path` is still a log a run wrote: in the destination, named
    /// as ShotDex names its logs, starting with their header. A file the
    /// user put under that name is left alone.
    private func isOurLog(_ path: String, destination: String) async throws -> Bool {
        let name = ServerUploadPath.lastComponent(of: path)
        guard CommonPhotosServerChecks.comparable(ServerUploadPath.parent(of: path)) == CommonPhotosServerChecks.comparable(destination),
              name.hasPrefix("ShotDex Common Photos "), name.lowercased().hasSuffix(".csv"),
              try await client.fileSize(at: path) != nil else { return false }
        let header = Data(CommonPhotosLog.csv([]).utf8)
        return try await client.readRange(path, offset: 0, length: header.count) == header
    }

    // MARK: Undo Move

    /// What an old path holds now.
    private enum PathState { case free, same, other }

    private func state(of path: String, size: Int64, sha256: String) async throws -> PathState {
        guard let found = try await client.fileSize(at: path) else { return .free }
        guard found == size, try await client.sha256(of: path, progress: { _ in }) == sha256 else { return .other }
        return .same
    }

    /// One photo, Move. Progress lives in the row's sources (`isRemoved`
    /// cleared as each copy is back) and on the server, so a stop anywhere
    /// resumes by looking again.
    private func undoMove(_ item: inout CommonPhotosItem, originalId: String, originals: [Int: CommonPhotosItem],
                          state progressState: Progress, progress: @escaping @Sendable (Progress) -> Void) async throws {
        guard let placed = item.destinationPath, let original = originals[item.position] else {
            try finish(&item, .failed, reason: .unreadableRecord)
            return
        }
        // The same bytes were in the destination before the run: that file
        // is not the run's and stays.
        let wasThere = original.destinationWasThere || item.destinationWasThere || original.failure?.reason == .alreadyThere
        let name = ServerUploadPath.lastComponent(of: placed)
        let itemSize = item.size
        let report = { @Sendable (step: Progress.Step, fraction: Double) in
            var moving = progressState
            moving.currentName = name
            moving.currentStep = step
            moving.doneBytes += Int64(Double(itemSize) * min(1, max(0, fraction)))
            progress(moving)
        }
        let local = workDirectory.appendingPathComponent(UUID().uuidString + "-" + name)
        defer { try? FileManager.default.removeItem(at: local) }
        var hasLocal = false
        var skipped: [String] = []
        var writing: String?
        let write = VerifiedRemoteWrite(client: client)
        // What became of each put-back copy's dates (FS-19.08 §6e); the
        // row says the worst of them.
        var outcomes: [FileInfoOutcome] = []
        do {
            report(.checking, 0)
            try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
            let renamedFrom = item.movedFrom.flatMap { from in item.sources.firstIndex { $0.path == from && $0.isRemoved } }
            let uploads = item.sources.indices.filter { item.sources[$0].isRemoved && $0 != renamedFrom }
                + (renamedFrom.map { [$0] } ?? [])
            var placedIsGone = false
            for (step, index) in uploads.enumerated() {
                try Task.checkCancellation()
                let path = item.sources[index].path
                // This copy's share of the photo's bar.
                let share = { (fraction: Double) in (Double(step) + fraction) / Double(uploads.count) }
                report(.checking, share(0))
                switch try await state(of: path, size: item.size, sha256: item.sha256) {
                case .same:
                    // Back already — an earlier session put it there and may
                    // have stopped before its dates were set: set them now.
                    if let info = item.sources[index].info, let outcome = await write.applyInfo(info, to: path) {
                        outcomes.append(outcome)
                    }
                case .other:
                    skipped.append(path)
                    continue
                case .free:
                    var renamedBack = false
                    if index == renamedFrom, !wasThere,
                       try await checks.holds(placed, size: item.size, sha256: item.sha256) {
                        // Renamed back: no bytes travel. Refused (the
                        // share's rules changed), it is written back instead.
                        report(.moving, share(0))
                        do {
                            try await client.move(placed, to: path)
                        } catch let error as RemoteFileError where !error.stopsBatch {
                            guard try await client.fileSize(at: path) == nil else { throw error }
                        }
                        if try await client.fileSize(at: path) == item.size {
                            renamedBack = true
                            placedIsGone = true
                            // A rename keeps whatever dates the shared copy
                            // has, and the run's rename may not have kept the
                            // source's (WebDAV across mounts): set them.
                            if let info = item.sources[index].info, let outcome = await write.applyInfo(info, to: path) {
                                outcomes.append(outcome)
                            }
                        }
                    }
                    if !renamedBack {
                        if let free = freeBytes(), free - item.size < BackupRunner.minimumFreeBytes {
                            throw Stop.noRoom(needed: item.size + BackupRunner.minimumFreeBytes - free)
                        }
                        if !hasLocal {
                            report(.downloading, share(0))
                            guard try await fetch(item, placed: placed, to: local) else {
                                try finish(&item, .failed, reason: .changedInShared)
                                return
                            }
                            hasLocal = true
                        }
                        writing = path
                        let size = Double(max(1, item.size))
                        try await write.uploadPart(local, for: path, progress: { report(.uploading, share(Double($0) / size / 2)) })
                        guard try await write.readBackSHA256(for: path, progress: { report(.readingBack, share(0.5 + Double($0) / size / 2)) })
                                == item.sha256 else {
                            throw RemoteFileError.other("checksum mismatch")
                        }
                        // Back as it was (FS-19.08 §6e): the dates and flags
                        // recorded before the Move removed this copy.
                        if let outcome = try await write.moveIntoPlace(path, replacing: false, info: item.sources[index].info) {
                            outcomes.append(outcome)
                        }
                        writing = nil
                    }
                }
                if let outcome = try await putBackSidecar(of: item.sources[index], item: item) { outcomes.append(outcome) }
                item.sources[index].isRemoved = false
                item.fileInfo = Self.worst(outcomes)
                try store.finishUndo(item, originalRunId: originalId)
            }
            // The destination copy goes last: the run's, every removed copy
            // back, and each of them checked again now — a copy put back in
            // an earlier session may have been edited since.
            if !wasThere, !placedIsGone, skipped.isEmpty {
                let aside = placed + CommonPhotosRunner.removingSuffix
                let atPlaced = try await client.fileSize(at: placed) != nil
                var atAside = false
                if !atPlaced { atAside = try await client.fileSize(at: aside) != nil }
                if atPlaced || atAside {
                    let others = try await presentSources(of: item)
                    guard others.count == item.sources.count(where: { !$0.isRemoved }) else {
                        if atAside { await putBackIfAside(aside, placed: placed) }
                        try finish(&item, .failed, reason: .changedOnServer)
                        try store.finishUndo(item, originalRunId: originalId)
                        return
                    }
                    guard try await checks.holds(atPlaced ? placed : aside, size: item.size, sha256: item.sha256) else {
                        if atAside { await putBackIfAside(aside, placed: placed) }
                        try finish(&item, .failed, reason: .changedInShared)
                        try store.finishUndo(item, originalRunId: originalId)
                        return
                    }
                    report(.removing, 1)
                    do {
                        // Set aside by a stop before it was deleted, or now.
                        if atPlaced { try await client.move(placed, to: aside) }
                        try await removeAside(aside, restoring: placed, others: others)
                    } catch {
                        await putBackIfAside(aside, placed: placed)
                        throw error
                    }
                }
            }
            if skipped.isEmpty {
                try await finishPhoto(&item, originalId: originalId, originals: originals)
            } else {
                // The copies that are back stay back; the photo is still
                // whole in the destination or where it was renamed to.
                item.status = .failed
                item.reason = CommonPhotosItem.reason(.nameTaken, skipped.joined(separator: "; "))
                try store.finishUndo(item, originalRunId: originalId)
            }
        } catch {
            if let writing { await write.discardPart(for: writing) }
            guard let remote = error as? RemoteFileError, !remote.stopsBatch else { throw error }
            // A copy that landed before the error (a rename back whose
            // check failed) is recorded as back, so the run's row says so.
            for index in item.sources.indices where item.sources[index].isRemoved {
                if (try? await state(of: item.sources[index].path, size: item.size, sha256: item.sha256)) == .same {
                    item.sources[index].isRemoved = false
                }
            }
            try finish(&item, .failed, reason: .serverError, detail: remote.localizedDescription)
            try store.finishUndo(item, originalRunId: originalId)
        }
    }

    /// The photo's bytes into `local`, from the destination or a copy
    /// already put back — whichever still hashes to the photo's SHA-256.
    private func fetch(_ item: CommonPhotosItem, placed: String, to local: URL) async throws -> Bool {
        let candidates = [placed] + item.sources.filter { !$0.isRemoved }.map(\.path)
        for path in candidates {
            guard try await client.fileSize(at: path) == item.size else { continue }
            if try await client.download(path, to: local, progress: { _ in }) == item.sha256 { return true }
        }
        return false
    }

    /// The row's File info after an undo: lost when any copy put back lost
    /// its dates, kept when every one that could be dated was; nil when
    /// none was (an undo of a run from before §6e).
    static func worst(_ outcomes: [FileInfoOutcome]) -> FileInfoOutcome? {
        if outcomes.contains(.datesNotKept) { return .datesNotKept }
        if outcomes.contains(.tagsNotKept) { return .tagsNotKept }
        return outcomes.isEmpty ? nil : .kept
    }

    /// A source's `.xmp`, removed by the Move, written back from the one in
    /// the destination when its old name is free, with its own recorded
    /// dates; returns what became of them. Best effort: a sidecar that will
    /// not go back never holds the photo up.
    @discardableResult
    private func putBackSidecar(of source: CommonPhotosItem.Source, item: CommonPhotosItem) async throws -> FileInfoOutcome? {
        guard let sidecar = source.sidecar, let there = Self.sidecarInDestination(of: item) else { return nil }
        let write = VerifiedRemoteWrite(client: client)
        let local = workDirectory.appendingPathComponent(UUID().uuidString + ".xmp")
        defer { try? FileManager.default.removeItem(at: local) }
        do {
            guard try await client.fileSize(at: sidecar) == nil, try await client.fileSize(at: there) != nil else { return nil }
            let sha256 = try await client.download(there, to: local, progress: { _ in })
            // Written by the run and edited since: not what was removed.
            if item.sidecarPlaced == there, let recorded = item.sidecarSHA256, recorded != sha256 { return nil }
            try await write.uploadPart(local, for: sidecar, progress: { _ in })
            guard try await write.readBackSHA256(for: sidecar, progress: { _ in }) == sha256 else {
                await write.discardPart(for: sidecar)
                return nil
            }
            return try await write.moveIntoPlace(sidecar, replacing: false, info: source.sidecarInfo)
        } catch {
            await write.discardPart(for: sidecar)
            if let remote = error as? RemoteFileError, !remote.stopsBatch { return nil }
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
