import Foundation

/// When a photo's user data goes (FS-19.05 §5, FS-01.12 AC-9).
///
/// Stars, flags, keywords, recipes and album places are typed by the user
/// and exist nowhere else, so a photo that leaves the library does not take
/// them at once: the photo becomes an orphan, and only an orphan older than
/// 30 days is purged. A file that comes back, or an asset shared again,
/// finds its data where it left it.
///
/// What counts as gone:
/// - deleted from inside ShotDex — PhotoKit confirmed the deletion, whatever
///   the access level;
/// - reported gone by an index run — only with full access. Under `.limited`
///   a photo the user stopped sharing disappears from every fetch exactly as
///   a deleted one does, and it is not an orphan at all.
enum OrphanRetention {
    static let days = 30

    enum Evidence: Equatable, Sendable {
        case deletedInApp
        case indexRun(accessIsFull: Bool)
    }

    static func makesOrphans(on evidence: Evidence) -> Bool {
        switch evidence {
        case .deletedInApp: true
        case .indexRun(let accessIsFull): accessIsFull
        }
    }

    /// The ids an index run reports gone that become orphans.
    static func orphanIds(after changes: IndexRunChanges) -> Set<String> {
        makesOrphans(on: .indexRun(accessIsFull: changes.accessIsFull)) ? changes.deleted : []
    }

    /// Orphans marked before this instant are purged.
    static func purgeCutoff(now: Date) -> Date {
        now.addingTimeInterval(-Double(days) * 24 * 60 * 60)
    }
}
