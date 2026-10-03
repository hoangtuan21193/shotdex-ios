import Foundation
import OSLog

/// Keeps the caption/keyword mirror (`PhotoKeywordStore`) in step with
/// Photos on iOS 27 (FS-02.07 §8). The one writer of the mirror, so a page of
/// the full read can never land on top of a write the user just made:
///
/// - **full read** — first launch on iOS 27, after Clear local metadata index,
///   and after an index run had to walk the whole library (Photos' change
///   history expired): every indexed id, in pages of 1,000, each page **one**
///   prefetched fetch and **one** transaction, with no `await` between the
///   two. Resumes from its cursor; yields while someone is looking at a photo.
/// - **refresh** — a set of ids read again now: what an index run reported
///   changed (Photos' "updated" set, even when the modification date did not
///   move — AC-10), what Info found out of step, what the app just wrote.
///
/// Reads no file, ever: only `PHAsset.extendedMetadata`.
actor ExtendedMetadataMirrorPass {
    struct Summary: Equatable, Sendable {
        var pages = 0
        var assets = 0
        var completed = false
        var wasCancelled = false
        /// The largest memory footprint seen after a page, in bytes — the
        /// AC-15 budget's second number (FS-02.07 §10 q6).
        var peakFootprint: UInt64 = 0
    }

    static let pageSize = 1_000

    private static let logger = Logger(subsystem: "com.hoangtuan.shotdex", category: "keywords")

    private let store: PhotoKeywordStore
    private let reader: any ExtendedMetadataReading
    private let shouldPause: @Sendable () -> Bool
    private let sleep: @Sendable (Duration) async -> Void
    private var isRunning = false
    private var isCancelled = false

    init(
        store: PhotoKeywordStore,
        reader: any ExtendedMetadataReading,
        shouldPause: @escaping @Sendable () -> Bool = { false },
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.store = store
        self.reader = reader
        self.shouldPause = shouldPause
        self.sleep = sleep
    }

    /// Whether the mirror still needs (the rest of) a full read.
    func needsFullRead() -> Bool {
        ((try? store.passState()) ?? .initial).completedAt == nil
    }

    /// Reads every indexed id into the mirror, from where the last run
    /// stopped. Does nothing once a full read has completed — `restart`
    /// asks for another.
    @discardableResult
    func runFullRead(now: @Sendable () -> Date = { Date() }) async -> Summary {
        guard !isRunning else { return Summary() }
        isRunning = true
        isCancelled = false
        defer { isRunning = false }

        var summary = Summary()
        var state = (try? store.passState()) ?? .initial
        guard state.completedAt == nil else { return summary }
        let started = ContinuousClock.now

        while true {
            if isCancelled || Task.isCancelled {
                summary.wasCancelled = true
                return summary
            }
            // Yield to a person looking at a photo (NF-01 rule 5) — between
            // pages only, never inside one.
            while shouldPause(), !isCancelled, !Task.isCancelled {
                await sleep(.seconds(1))
            }
            guard let ids = try? store.indexedAssetIds(after: state.cursorAssetId, limit: Self.pageSize) else {
                return summary
            }
            if ids.isEmpty {
                try? store.deleteOrphans()
                state = .init(cursorAssetId: nil, completedAt: Int(now().timeIntervalSince1970))
                try? store.savePassState(state)
                summary.completed = true
                break
            }
            // Fetch and commit in one actor turn: nothing else writes the
            // mirror in between, so no page can undo a newer write.
            let values = reader.read(ids: ids)
            state.cursorAssetId = ids.last
            do {
                try store.replace(ids: ids, with: values, state: state)
            } catch {
                Self.logger.error("mirror page failed: \(error.localizedDescription, privacy: .public)")
                return summary
            }
            summary.pages += 1
            summary.assets += ids.count
            summary.peakFootprint = max(summary.peakFootprint, Self.footprint())
            await Task.yield()
        }
        let elapsed = ContinuousClock.now - started
        Self.logger.log("""
            mirror full read: \(summary.assets) assets, \(summary.pages) pages, \
            \(elapsed, privacy: .public), peak \(summary.peakFootprint / 1_048_576) MB
            """)
        return summary
    }

    /// The process's physical footprint, as Xcode's memory gauge shows it.
    private static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    /// Reads the given ids again and replaces their mirror — an id Photos no
    /// longer returns loses its rows. In pages, like the full read.
    func refresh(ids: some Collection<String>) {
        let all = Array(Set(ids))
        guard !all.isEmpty else { return }
        for start in stride(from: 0, to: all.count, by: Self.pageSize) {
            let page = Array(all[start..<min(start + Self.pageSize, all.count)])
            let values = reader.read(ids: page)
            try? store.replace(ids: page, with: values, state: nil)
        }
    }

    /// Writes values already in hand (Info's live read) — through the same
    /// actor, so it queues behind a page in flight.
    func record(_ values: [String: CaptionKeywords]) {
        try? store.replace(values)
    }

    /// Asks for a new full read from the start: the index had to walk the
    /// whole library, so Photos' history no longer covers every change.
    func restart() {
        try? store.savePassState(.initial)
    }

    /// What one finished index run means for the mirror (FS-02.07 AC-10):
    /// the changed ids are read again; deleted ids already went with their
    /// `photo_metadata` rows; a full walk asks for a full read.
    func handle(_ changes: IndexRunChanges) {
        if changes.isFullWalk {
            // The full read covers every id; reading the walk's ids first
            // would only read them twice.
            restart()
            return
        }
        refresh(ids: changes.changed.subtracting(changes.deleted))
    }

    func cancel() {
        isCancelled = true
    }
}
