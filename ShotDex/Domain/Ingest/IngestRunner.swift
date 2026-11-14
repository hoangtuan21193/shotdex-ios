import CryptoKit
import Foundation
import os

/// Where a card import goes: the destination source's folder and, when
/// asked, a backup drive (FS-20 §6).
struct IngestTarget: Sendable {
    let destination: any IngestDestination
    /// What the user calls it: `T7 RAW Archive`.
    let name: String
}

/// What a run reports as it goes, in order, on the runner's actor.
enum IngestEvent: Sendable, Equatable {
    /// One file of a photo is in the destination under its real name and
    /// reads back as the card's bytes.
    case fileVerified(itemId: String, file: CardFile, path: String, sha256: String)
    /// Every file of the photo is in: it can join the source (FS-20 §7.5).
    case imported(itemId: String)
    case failed(itemId: String, IngestFailure)
    case backedUp(itemId: String, paths: [String])
    case progress(IngestProgress)
    /// What happens to a photo now, for Activity's file list (FS-20 §7,
    /// board `MAC_IngestProgress`): sent as each file of it starts copying,
    /// once its bytes are in and the part file is being read back, and as
    /// its backup copy starts.
    case stage(itemId: String, IngestFileStage)
    /// Pause took hold — the photo in hand is done and the run waits — or
    /// Resume let it go: the time-left clock stops and starts here.
    case parked(Bool)
}

/// A photo's step in a run, for the file list.
enum IngestFileStage: Sendable, Equatable {
    case copying
    case verifying
    case backingUp
}

struct IngestProgress: Sendable, Equatable {
    var done = 0
    var total = 0
    var bytesDone: Int64 = 0
    var bytesTotal: Int64 = 0
    var currentFile: String?

    var fraction: Double { bytesTotal > 0 ? Double(bytesDone) / Double(bytesTotal) : (total > 0 ? Double(done) / Double(total) : 0) }
}

/// How a run ended (FS-20 §7–8).
struct IngestSummary: Sendable, Equatable {
    enum Ending: Sendable, Equatable {
        case finished
        /// Stop Import…, or a pause that ended the run.
        case stopped
        case cardDisconnected
        case destinationFailed(FileExportFailure)
    }

    var ending: Ending = .finished
    var total = 0
    /// Photos whose every file is in the destination and verified.
    var imported: [String] = []
    var failed: [String: IngestFailure] = [:]
    /// Photos whose backup copy is verified too.
    var backedUp: [String] = []
    /// The backup drive went away mid-run; the primary copy went on.
    var backupIncomplete = false
    /// Photos never started: what Import Remaining copies.
    var remaining: [String] = []

    /// The card is let go only when every copy is verified (FS-20 §8): no
    /// failure, not stopped, every backup done.
    func canEject(backupEnabled: Bool) -> Bool {
        ending == .finished && failed.isEmpty && remaining.isEmpty
            && (!backupEnabled || (!backupIncomplete && Set(backedUp) == Set(imported)))
    }
}

/// Copies a card into a folder source (FS-20 §7): one file at a time, in
/// chunks of at most 1 MB, hashed as it goes; the part file is read back and
/// must match before it gets its name; a mismatch is copied once more. A
/// photo is in whole or not at all. The backup copy of a photo follows its
/// primary copy. A problem with one file leaves the batch running; the card
/// or the destination going away stops it.
actor IngestRunner {
    static let chunkSize = 1 << 20

    let card: any CardReader
    let plan: FileExportPlan
    let primary: IngestTarget
    let backup: IngestTarget?
    private let onEvent: @Sendable (IngestEvent) async -> Void
    /// Bytes of the photo in hand copied so far (primary copy only), at most
    /// every 100 ms: called from inside the chunk loop, which cannot wait.
    private let onCopied: @Sendable (_ itemId: String, _ bytes: Int64) -> Void
    private var isPaused = false

    init(card: any CardReader, plan: FileExportPlan, primary: IngestTarget, backup: IngestTarget? = nil,
         onEvent: @escaping @Sendable (IngestEvent) async -> Void = { _ in },
         onCopied: @escaping @Sendable (_ itemId: String, _ bytes: Int64) -> Void = { _, _ in }) {
        self.card = card
        self.plan = plan
        self.primary = primary
        self.backup = backup
        self.onEvent = onEvent
        self.onCopied = onCopied
    }

    /// Pause (FS-20 AC-28): the file being copied finishes — copy, verify,
    /// rename — and the run waits before the next one.
    func pause() { isPaused = true }
    func resume() { isPaused = false }
    func setPaused(_ paused: Bool) { isPaused = paused }
    var paused: Bool { isPaused }

    /// Runs the plan, or only `ids` of it (Import Remaining, Retry Failed).
    /// `copiesPrimary` false backs up photos already in the destination
    /// (Back Up Remaining). Cancelling the task is Stop Import….
    func run(only ids: Set<String>? = nil, copiesPrimary: Bool = true, backsUp: Bool = true) async -> IngestSummary {
        let entries = plan.writtenEntries.filter { ids?.contains($0.id) ?? true }
        var summary = IngestSummary(total: entries.count)
        var progress = IngestProgress(total: entries.count,
                                      bytesTotal: entries.reduce(0) { $0 + $1.item.originalBytes })
        let backup = backsUp ? self.backup : nil
        var backupGone = false
        for (index, entry) in entries.enumerated() {
            if isPaused, !Task.isCancelled {
                await onEvent(.parked(true))
                while isPaused, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(50)) }
                await onEvent(.parked(false))
            }
            if Task.isCancelled {
                summary.ending = .stopped
                summary.remaining = entries[index...].map(\.id)
                break
            }
            do {
                if copiesPrimary {
                    try await copy(entry, to: primary, progress: &progress)
                    summary.imported.append(entry.id)
                    await onEvent(.imported(itemId: entry.id))
                }
                if let backup, !backupGone {
                    do {
                        await onEvent(.stage(itemId: entry.id, .backingUp))
                        let paths = try await copy(entry, to: backup, report: false)
                        // Back Up Remaining: the backup is the only copy, so it is what moves the bytes.
                        if !copiesPrimary { progress.bytesDone += entry.item.originalBytes }
                        summary.backedUp.append(entry.id)
                        await onEvent(.backedUp(itemId: entry.id, paths: paths))
                    } catch let failure as IngestFailure where failure.isDestinationGone {
                        // The backup drive alone went away: the primary copy goes on.
                        backupGone = true
                        summary.backupIncomplete = true
                    }
                }
            } catch is CancellationError {
                summary.ending = .stopped
                summary.remaining = entries[index...].map(\.id)
                break
            } catch let failure as IngestFailure {
                if failure.stopsBatch {
                    summary.ending = failure == .cardDisconnected ? .cardDisconnected : .destinationFailed(failure.destinationFailure ?? .disconnected)
                    summary.remaining = entries[index...].map(\.id)
                    break
                }
                summary.failed[entry.id] = failure
                await onEvent(.failed(itemId: entry.id, failure))
            } catch {
                summary.failed[entry.id] = .unreadable
                await onEvent(.failed(itemId: entry.id, .unreadable))
            }
            progress.done = index + 1
            progress.currentFile = nil
            await onEvent(.progress(progress))
        }
        if summary.ending != .finished {
            for folder in Set(entries.map(\.folder)) {
                await primary.destination.sweepLeftoverParts(in: folder)
                await self.backup?.destination.sweepLeftoverParts(in: folder)
            }
        }
        if backup != nil, summary.backupIncomplete == false, Set(summary.backedUp) != Set(summary.imported), summary.ending == .finished {
            summary.backupIncomplete = true
        }
        return summary
    }

    /// The primary copy of one photo, counted in the progress.
    @discardableResult
    private func copy(_ entry: FileExportPlan.Entry, to target: IngestTarget, progress: inout IngestProgress) async throws -> [String] {
        let paths = try await copy(entry, to: target, report: true)
        progress.bytesDone += entry.item.originalBytes
        return paths
    }

    /// Every file of one photo to `target`; on a file that fails, the ones
    /// already written for this photo are taken back.
    private func copy(_ entry: FileExportPlan.Entry, to target: IngestTarget, report: Bool) async throws -> [String] {
        var written: [String] = []
        var base: Int64 = 0
        let onEvent = self.onEvent
        do {
            for output in entry.outputs {
                guard let source = output.source else { continue }
                let file = CardFile(path: source.key, size: source.byteCount, modified: entry.item.captureDate)
                let meter = report ? ChunkMeter(itemId: entry.id, base: base, send: onCopied) : nil
                let (result, sha) = try await copyFile(file, name: output.name, folder: entry.folder, to: target, meter: meter,
                                                       starting: { if report { await onEvent(.stage(itemId: entry.id, .copying)) } },
                                                       copied: { if report { await onEvent(.stage(itemId: entry.id, .verifying)) } })
                base += source.byteCount
                written.append(result.path)
                if report {
                    await onEvent(.fileVerified(itemId: entry.id, file: file, path: result.path, sha256: sha))
                }
            }
        } catch {
            for path in written { await target.destination.remove(path) }
            throw Self.normalized(error)
        }
        return written
    }

    /// One file, copied and proven; a mismatch is copied once more from the
    /// card before it counts as failed (FS-20 §8).
    private func copyFile(_ file: CardFile, name: String, folder: String, to target: IngestTarget,
                          meter: ChunkMeter? = nil,
                          starting: @Sendable () async -> Void = {},
                          copied: @escaping @Sendable () async -> Void = {}) async throws -> (ExportWrittenFile, String) {
        var attempt = 0
        while true {
            attempt += 1
            let card = self.card
            let box = DigestBox()
            // Each attempt — a mismatch is copied once more — starts the file over.
            meter?.restart()
            await starting()
            do {
                let result = try await target.destination.writeVerified(name: name, in: folder) { part in
                    let handle = try FileHandle(forWritingTo: part)
                    defer { try? handle.close() }
                    var hasher = SHA256()
                    try await card.read(file.path, chunkSize: Self.chunkSize) { data in
                        try Task.checkCancellation()
                        hasher.update(data: data)
                        try handle.write(contentsOf: data)
                        meter?.add(Int64(data.count))
                    }
                    let digest = FileChecksum.hex(hasher.finalize())
                    box.value = digest
                    // The bytes are in; the destination reads the part file back now.
                    meter?.flush()
                    await copied()
                    return digest
                }
                return (result, box.value ?? "")
            } catch IngestFailure.checksumMismatch where attempt < 2 {
                continue
            }
        }
    }

    static func normalized(_ error: Error) -> Error {
        if error is CancellationError || error is IngestFailure { return error }
        if let failure = FileExportFailure.classify(error) {
            return failure.stopsBatch ? IngestFailure.destination(failure) : IngestFailure.unreadable
        }
        return IngestFailure.unreadable
    }
}

private final class DigestBox: @unchecked Sendable {
    var value: String?
}

/// Counts one file's bytes as its chunks land and passes the photo's total
/// on at most every 100 ms — a 1 MB chunk is a few milliseconds, and the
/// file list does not need a main-actor hop for each.
private final class ChunkMeter: Sendable {
    private struct State {
        var bytes: Int64 = 0
        var lastSent: ContinuousClock.Instant?
    }

    let itemId: String
    let base: Int64
    let send: @Sendable (String, Int64) -> Void
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(itemId: String, base: Int64, send: @escaping @Sendable (String, Int64) -> Void) {
        self.itemId = itemId
        self.base = base
        self.send = send
    }

    /// A second attempt after a mismatch starts the file over.
    func restart() { state.withLock { $0 = State() } }

    /// The last bytes of the file, whatever the 100 ms gate held back.
    func flush() { send(itemId, base + state.withLock { $0.bytes }) }

    func add(_ count: Int64) {
        let now = ContinuousClock.now
        let due: Int64? = state.withLock { state in
            state.bytes += count
            if let last = state.lastSent, now - last < .milliseconds(100) { return nil }
            state.lastSent = now
            return state.bytes
        }
        if let due { send(itemId, base + due) }
    }
}

extension IngestFailure {
    var isDestinationGone: Bool { stopsBatch && self != .cardDisconnected }
    var destinationFailure: FileExportFailure? {
        if case .destination(let failure) = self { return failure }
        return nil
    }
}
