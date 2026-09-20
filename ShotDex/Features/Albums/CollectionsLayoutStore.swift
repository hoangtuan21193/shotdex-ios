import Foundation
import SwiftUI

/// One section of the Collections tab, in the order it appears by default.
enum CollectionsSection: String, CaseIterable, Identifiable, Codable, Sendable {
    case pinned
    case memories
    case subjects
    case smartAlbums
    case myAlbums
    case sharedAlbums
    // Media Types sits directly above Utilities, the way iOS 26 Photos
    // arranges the same two lists: both are pick-from-a-list destinations
    // rather than covers to browse, so they read as one block at the foot of
    // the tab.
    case mediaTypes
    case utilities

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pinned: "Pinned"
        case .memories: "Memories"
        case .subjects: "People and Pets"
        case .smartAlbums: "Smart Albums"
        case .mediaTypes: "Media Types"
        case .myAlbums: "My Albums"
        case .sharedAlbums: "Shared Albums"
        case .utilities: "Utilities"
        }
    }

    var systemImage: String {
        switch self {
        case .pinned: "pin"
        case .memories: "sparkles"
        case .subjects: "person.crop.square"
        case .smartAlbums: "line.3.horizontal.decrease.circle"
        case .mediaTypes: "square.stack.3d.down.right"
        case .myAlbums: "rectangle.stack"
        case .sharedAlbums: "person.2"
        case .utilities: "wrench.and.screwdriver"
        }
    }

    /// Sections a user cannot turn off. Pinned is the user's own arrangement,
    /// so hiding it would bury what they explicitly asked to keep in reach;
    /// Utilities holds the tools, and an app that can hide its own tools has a
    /// support problem.
    var isAlwaysShown: Bool {
        switch self {
        case .pinned, .utilities: true
        default: false
        }
    }
}

/// The order and visibility of the Collections tab's sections.
///
/// The tab's default order is an opinion about what most people reach for.
/// Somebody who lives in their own albums and never opens Memories should be
/// able to say so once, which is what this stores — Photos calls the same idea
/// "Customize & Reorder".
///
/// Unknown ids in the stored order are dropped and missing ones are appended,
/// so a build that adds a section shows it rather than losing it.
@MainActor
@Observable
final class CollectionsLayoutStore {
    private enum Key {
        static let order = "collections.sectionOrder"
        static let hidden = "collections.hiddenSections"
    }

    private let defaults: UserDefaults
    private(set) var order: [CollectionsSection]
    private(set) var hidden: Set<CollectionsSection>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.stringArray(forKey: Key.order) ?? []
        self.order = Self.merged(stored: stored)
        let storedHidden = defaults.stringArray(forKey: Key.hidden) ?? []
        self.hidden = Set(
            storedHidden.compactMap(CollectionsSection.init(rawValue:))
                .filter { !$0.isAlwaysShown }
        )
    }

    /// The sections to draw, in order.
    var visibleOrder: [CollectionsSection] {
        order.filter { !hidden.contains($0) }
    }

    func isHidden(_ section: CollectionsSection) -> Bool {
        hidden.contains(section)
    }

    func setHidden(_ isHidden: Bool, for section: CollectionsSection) {
        guard !section.isAlwaysShown else { return }
        if isHidden {
            hidden.insert(section)
        } else {
            hidden.remove(section)
        }
        defaults.set(hidden.map(\.rawValue), forKey: Key.hidden)
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        order.move(fromOffsets: source, toOffset: destination)
        defaults.set(order.map(\.rawValue), forKey: Key.order)
    }

    /// Back to the app's own order, with everything shown.
    func reset() {
        order = CollectionsSection.allCases
        hidden = []
        defaults.removeObject(forKey: Key.order)
        defaults.removeObject(forKey: Key.hidden)
    }

    var isCustomized: Bool {
        order != CollectionsSection.allCases || !hidden.isEmpty
    }

    /// Stored ids first, in their stored order, then anything this build knows
    /// about that the stored list does not.
    static func merged(stored: [String]) -> [CollectionsSection] {
        var result = stored.compactMap(CollectionsSection.init(rawValue:))
        var seen = Set(result)
        for section in CollectionsSection.allCases where !seen.contains(section) {
            result.append(section)
            seen.insert(section)
        }
        return result
    }
}
