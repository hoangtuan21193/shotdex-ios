import Foundation

/// Keeps the search index (FS-01.03c §1) in step with the library: rebuilds it
/// once at launch and again a few seconds after the tables it reads stop
/// changing, off the main actor.
///
/// A burst of writes — an index run saves a batch of 200 every moment — is one
/// rebuild, not one per batch; and a long run still gets a rebuild every
/// `longestWait`, so search does not stay a run behind until it ends.
actor SearchIndexer {
    /// The tables a group is computed from. Not `search_group` itself, or every
    /// rebuild would schedule the next.
    static let watchedTables = ["photo_metadata", "photo_keyword", "photo_user_keyword", "photo_copies", "sources"]

    private let database: AppDatabase
    private let quietPeriod: Duration
    private let longestWait: Duration
    private var observer: Task<Void, Never>?
    private var pending: Task<Void, Never>?
    private var pendingSince: ContinuousClock.Instant?
    private var isRebuilding = false
    private var needsAnotherRebuild = false

    /// Rebuilds finished since launch — for tests and the indexing banner.
    private(set) var rebuildCount = 0

    init(database: AppDatabase, quietPeriod: Duration = .seconds(3), longestWait: Duration = .seconds(30)) {
        self.database = database
        self.quietPeriod = quietPeriod
        self.longestWait = longestWait
    }

    /// Starts watching. Safe to call more than once.
    nonisolated func start() {
        Task { await self.begin() }
    }

    private func begin() {
        guard observer == nil else { return }
        schedule(after: .zero)
        let database = self.database
        observer = Task { [weak self] in
            for await _ in DatabaseChangeSignal.changes(in: database, tables: Self.watchedTables) {
                await self?.changed()
            }
        }
    }

    private func changed() {
        let now = ContinuousClock.now
        if pendingSince == nil { pendingSince = now }
        // Past the longest wait, let the scheduled rebuild run instead of
        // pushing it back again.
        if let since = pendingSince, now - since >= longestWait, pending != nil { return }
        schedule(after: quietPeriod)
    }

    private func schedule(after delay: Duration) {
        pending?.cancel()
        pending = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            await self?.rebuild()
        }
    }

    /// Rebuilds now; a change during the rebuild queues exactly one more.
    func rebuild() async {
        guard !isRebuilding else {
            needsAnotherRebuild = true
            return
        }
        isRebuilding = true
        pending = nil
        pendingSince = nil
        let store = SearchIndexStore(database: database)
        await Task.detached(priority: .utility) {
            try? store.rebuild()
        }.value
        rebuildCount += 1
        isRebuilding = false
        if needsAnotherRebuild {
            needsAnotherRebuild = false
            schedule(after: quietPeriod)
        }
    }
}
