import Foundation

/// Keeps the search index (FS-01.03c §1) in step with the library — lazily.
///
/// A rebuild reads every photo row, so it must never compete with scrolling
/// or with an index run: a change only marks the index stale. It is rebuilt
/// when the search screen asks (`refresh()`, on opening it), or once the
/// library has been quiet for `quietPeriod` — never in the middle of a burst
/// of writes. Until then search answers from the previous build, which differs
/// only by the photos of the last few minutes.
actor SearchIndexer {
    /// The tables a group is computed from. Not `search_group` itself, or every
    /// rebuild would mark the index stale again.
    static let watchedTables = ["photo_metadata", "photo_keyword", "photo_user_keyword", "photo_copies", "sources"]

    private let database: AppDatabase
    private let quietPeriod: Duration
    private var observer: Task<Void, Never>?
    private var idleRebuild: Task<Void, Never>?
    private var building: Task<Void, Never>?
    private var isStale = true

    /// Rebuilds finished since launch — for tests.
    private(set) var rebuildCount = 0

    init(database: AppDatabase, quietPeriod: Duration = .seconds(60)) {
        self.database = database
        self.quietPeriod = quietPeriod
    }

    /// Starts watching. Safe to call more than once. Builds nothing by itself
    /// until the library has been quiet for `quietPeriod`.
    nonisolated func start() {
        Task { await self.begin() }
    }

    /// The search screen opened: rebuild now if anything changed since the
    /// last build. Returns at once; `refreshed()` waits for it.
    nonisolated func refresh() {
        Task { await self.refreshed() }
    }

    /// Rebuilds if stale and waits for the build (or the one already running).
    func refreshed() async {
        if let building {
            await building.value
            return
        }
        guard isStale else { return }
        await rebuild()
    }

    private func begin() {
        guard observer == nil else { return }
        scheduleIdleRebuild()
        let database = self.database
        observer = Task { [weak self] in
            for await _ in DatabaseChangeSignal.changes(in: database, tables: Self.watchedTables) {
                await self?.changed()
            }
        }
    }

    private func changed() {
        isStale = true
        scheduleIdleRebuild()
    }

    /// Every change pushes the idle rebuild back: an index run that saves a
    /// batch every few seconds never triggers one.
    private func scheduleIdleRebuild() {
        idleRebuild?.cancel()
        let quietPeriod = self.quietPeriod
        idleRebuild = Task { [weak self] in
            try? await Task.sleep(for: quietPeriod)
            guard !Task.isCancelled else { return }
            await self?.rebuildIfStale()
        }
    }

    private func rebuildIfStale() async {
        guard isStale, building == nil else { return }
        await rebuild()
    }

    private func rebuild() async {
        isStale = false
        let store = SearchIndexStore(database: database)
        let task = Task<Void, Never>.detached(priority: .background) {
            _ = try? store.rebuild()
        }
        building = task
        await task.value
        building = nil
        rebuildCount += 1
    }
}
