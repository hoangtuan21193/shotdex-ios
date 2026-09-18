import Foundation
import SwiftUI

/// Remembers which photos were opened and which were shared, so the app can
/// offer the "Recently Viewed" and "Recently Shared" collections Photos has.
///
/// PhotoKit records neither: it knows when an asset was created and modified,
/// not when someone looked at it. So the app keeps its own list — newest first,
/// capped, and holding nothing but asset ids, which are already the app's to
/// know.
@MainActor
@Observable
final class RecentActivityStore {
    /// How far back each list reaches. Long enough to answer "what was I just
    /// looking at", short enough that the list stays a shortcut rather than a
    /// second library.
    static let limit = 100

    private enum Key {
        static let viewed = "recents.viewed"
        static let shared = "recents.shared"
    }

    private let defaults: UserDefaults
    private(set) var viewed: [String]
    private(set) var shared: [String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        viewed = defaults.stringArray(forKey: Key.viewed) ?? []
        shared = defaults.stringArray(forKey: Key.shared) ?? []
    }

    /// Records a photo the user opened in the viewer.
    func recordViewed(_ assetId: String) {
        viewed = Self.promoting(assetId, in: viewed)
        defaults.set(viewed, forKey: Key.viewed)
    }

    /// Records photos handed to the share sheet. Recorded when the sheet is
    /// raised, not when it completes: iOS does not report what the user did
    /// with it, and "I shared this a moment ago" is the question the list
    /// answers either way.
    func recordShared(_ assetIds: [String]) {
        for assetId in assetIds.reversed() {
            shared = Self.promoting(assetId, in: shared)
        }
        defaults.set(shared, forKey: Key.shared)
    }

    func clear() {
        viewed = []
        shared = []
        defaults.removeObject(forKey: Key.viewed)
        defaults.removeObject(forKey: Key.shared)
    }

    /// Moves an id to the front, removing any earlier appearance, then trims.
    /// Re-opening a photo should move it up the list, not add a duplicate.
    private static func promoting(_ assetId: String, in list: [String]) -> [String] {
        var updated = list
        updated.removeAll { $0 == assetId }
        updated.insert(assetId, at: 0)
        return Array(updated.prefix(limit))
    }
}
