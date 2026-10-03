import Foundation

/// Writes the Video Studio project as a draft while it is being edited
/// (FS-12.18 §2): about a second after the last change, and at once when
/// asked — Back, the app going to the background, the scene changing.
///
/// Changes in a burst make one write, not one each: every new change cancels
/// the write it would have followed. Writes leave the main actor and go
/// through one serial writer that numbers them, so a slow earlier write can
/// never land on top of a later one — the newest project always wins.
@MainActor @Observable
final class VideoDraftAutosave {
    typealias Write = @Sendable (Creation) throws -> Void
    typealias Sleep = @Sendable (Duration) async throws -> Void

    /// How long the project has to sit still before it is written.
    static let delay: Duration = .seconds(1)

    /// True from a failed write until the next one succeeds — what the
    /// "Couldn't save your video draft" banner shows (FS-12.18 §6).
    private(set) var hasFailedSave = false

    /// A write is waiting for the project to sit still.
    var isSavePending: Bool { pending != nil }

    private let writer: VideoDraftWriter
    private let sleep: Sleep
    private var pending: Task<Void, Never>?
    private var generation = 0

    init(
        write: @escaping Write,
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.writer = VideoDraftWriter(write: write)
        self.sleep = sleep
    }

    /// Writes `snapshot()` once the project has been still for `delay`.
    /// The snapshot is taken when the write happens, not now, so it is the
    /// project as it stands after the burst.
    /// A snapshot that throws — the recipe would not encode — is a failed
    /// save, not "nothing to write": the banner has to come up.
    func schedule(_ snapshot: @escaping @MainActor () throws -> Creation?) {
        pending?.cancel()
        let sleep = self.sleep
        pending = Task { [weak self] in
            do { try await sleep(Self.delay) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.pending = nil
            _ = await self.write(snapshot)
        }
    }

    /// Writes now, dropping any write that was waiting. Returns whether the
    /// project is on disk.
    @discardableResult
    func saveNow(_ snapshot: @MainActor () throws -> Creation?) async -> Bool {
        pending?.cancel()
        pending = nil
        return await write(snapshot)
    }

    /// Drops a waiting write without making it.
    func cancel() {
        pending?.cancel()
        pending = nil
    }

    private func write(_ snapshot: @MainActor () throws -> Creation?) async -> Bool {
        generation += 1
        let mine = generation
        let creation: Creation
        do {
            guard let made = try snapshot() else { return true }
            creation = made
        } catch {
            settle(failed: true, generation: mine)
            return false
        }
        do {
            try await writer.write(creation, generation: mine)
            settle(failed: false, generation: mine)
            return true
        } catch {
            settle(failed: true, generation: mine)
            return false
        }
    }

    /// The newest write to finish decides the banner: an older write that
    /// lands late cannot clear a failure the newer one reported.
    private var settledGeneration = 0

    private func settle(failed: Bool, generation: Int) {
        guard generation >= settledGeneration else { return }
        settledGeneration = generation
        hasFailedSave = failed
    }
}

/// The one place drafts are written from, off the main actor. A write that
/// arrives after a newer one has landed is dropped rather than made.
actor VideoDraftWriter {
    private let write: VideoDraftAutosave.Write
    private var lastWritten = 0

    init(write: @escaping VideoDraftAutosave.Write) {
        self.write = write
    }

    func write(_ creation: Creation, generation: Int) throws {
        guard generation > lastWritten else { return }
        try write(creation)
        lastWritten = generation
    }
}
