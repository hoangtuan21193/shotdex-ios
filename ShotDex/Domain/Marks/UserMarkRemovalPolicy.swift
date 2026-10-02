import Foundation

/// When a photo's star and flag rows go (FS-01.12 §4, AC-9).
///
/// They are user data with no copy anywhere else, so they only go when the
/// photo is really gone:
/// - deleted from inside ShotDex — PhotoKit confirmed the deletion, whatever
///   the access level;
/// - reported gone by an index run — only with full access. Under `.limited`
///   a photo the user stopped sharing disappears from every fetch exactly as
///   a deleted one does, and the marks must survive to come back with it.
enum UserMarkRemovalPolicy {
    enum Evidence: Equatable, Sendable {
        case deletedInApp
        case indexRun(accessIsFull: Bool)
    }

    static func removesMarks(on evidence: Evidence) -> Bool {
        switch evidence {
        case .deletedInApp: true
        case .indexRun(let accessIsFull): accessIsFull
        }
    }

    /// The ids whose marks an index run may remove.
    static func idsToRemove(after changes: IndexRunChanges) -> Set<String> {
        removesMarks(on: .indexRun(accessIsFull: changes.accessIsFull)) ? changes.deleted : []
    }
}
