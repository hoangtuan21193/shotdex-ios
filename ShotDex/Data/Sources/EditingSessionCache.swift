import Foundation

/// The bookkeeping behind `PhotoEditingService`'s recent sessions: which
/// session a revisit reuses, which one eviction may throw away, and which a
/// Save Changes retires. Generic so it can be tested without PhotoKit; the
/// service owns the actual file deletion for every session this hands back.
struct EditingSessionCache<Session: AnyObject> {
    let limit: Int
    /// Newest last.
    private(set) var recent: [(id: String, session: Session)] = []
    /// Sessions of photos saved with Save Changes (FS-03.09b AC-5). Out of
    /// `recent`, so the next open reads PhotoKit again and gets the saved
    /// recipe; still owned, because the canvas may be drawing from the
    /// retired session's source file until the editor closes.
    private(set) var retired: [Session] = []
    /// The photo the editor has open, never the one evicted.
    var activeID: String?

    init(limit: Int) {
        self.limit = limit
    }

    func cached(_ id: String) -> Session? {
        recent.first { $0.id == id }?.session
    }

    /// Whether `session` is still the cache's to delete — `endSession` must
    /// leave it alone.
    func owns(_ session: Session) -> Bool {
        recent.contains { $0.session === session } || retired.contains { $0 === session }
    }

    /// Adds `session` as `id`'s newest entry. Returns what has to be deleted
    /// now: a different session it replaced, and the oldest entries past the
    /// limit, skipping the canvas's.
    mutating func remember(_ session: Session, id: String) -> [Session] {
        var dropped: [Session] = []
        if let index = recent.firstIndex(where: { $0.id == id }) {
            let old = recent.remove(at: index).session
            if old !== session, !retired.contains(where: { $0 === old }) { dropped.append(old) }
        }
        recent.append((id, session))
        while recent.count > limit, let oldest = recent.firstIndex(where: { $0.id != activeID }) {
            dropped.append(recent.remove(at: oldest).session)
        }
        return dropped
    }

    /// After Save Changes: `id` is no longer served from the cache.
    mutating func retire(_ id: String) {
        guard let index = recent.firstIndex(where: { $0.id == id }) else { return }
        let session = recent.remove(at: index).session
        if !retired.contains(where: { $0 === session }) { retired.append(session) }
    }

    /// Everything owned, for the editor closing.
    mutating func releaseAll() -> [Session] {
        let all = recent.map(\.session) + retired
        recent.removeAll()
        retired.removeAll()
        activeID = nil
        return all
    }
}
