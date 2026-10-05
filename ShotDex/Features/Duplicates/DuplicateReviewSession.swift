import Foundation
import Observation

/// The user's work on the Duplicates screen, kept for the life of the app
/// process (FS-06.06b §1, D2): marks survive switching strictness, Back and
/// coming back, other tabs and the background — and are gone when the app is
/// killed. Nothing here is written to disk.
///
/// Owned by `AppDependencies`, not by the screen's model, because the model
/// is rebuilt every time the screen is pushed.
@MainActor
@Observable
final class DuplicateReviewSession {
    /// Asset ids marked for deletion — one set for every strictness, so a
    /// photo marked under Similar is marked under Exact too.
    var marks: Set<String> = []
    /// Groups the user said to keep whole ("Keep all"), by `key(_:_:)`.
    var keptAll: Set<String> = []
    /// Groups folded to their one-line summary, by `key(_:_:)`.
    var collapsed: Set<String> = []
    /// The member the user picked to keep with Keep Only This, by group key.
    /// Overrides the suggestion.
    var keeperOverride: [String: String] = [:]

    /// Groups are only unique within a strictness: the same lead photo can
    /// head an Exact group and a Similar one.
    nonisolated static func key(_ strictness: DuplicateStrictness, _ groupId: String) -> String {
        "\(strictness.rawValue):\(groupId)"
    }
}
