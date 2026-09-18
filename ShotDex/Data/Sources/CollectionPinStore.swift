import Foundation
import SwiftUI

/// The collections the user pinned to the top of the Collections tab.
///
/// Stored as opaque tokens rather than typed ids so one list can hold albums,
/// smart albums and the utilities side by side, in the order the user put them
/// in. An id that no longer resolves is simply skipped when the row is built —
/// an album can be deleted from Photos, and a stale pin must not be an error.
@MainActor
@Observable
final class CollectionPinStore {
    /// What a pin can point at.
    enum Target: Hashable {
        case album(String)
        case smartAlbum(String)
        case places
        case trips
        case duplicates

        var token: String {
            switch self {
            case .album(let id): "album:\(id)"
            case .smartAlbum(let id): "smart:\(id)"
            case .places: "utility:places"
            case .trips: "utility:trips"
            case .duplicates: "utility:duplicates"
            }
        }

        init?(token: String) {
            guard let separator = token.firstIndex(of: ":") else { return nil }
            let kind = String(token[token.startIndex..<separator])
            let value = String(token[token.index(after: separator)...])
            switch (kind, value) {
            case ("album", let id): self = .album(id)
            case ("smart", let id): self = .smartAlbum(id)
            case ("utility", "places"): self = .places
            case ("utility", "trips"): self = .trips
            case ("utility", "duplicates"): self = .duplicates
            default: return nil
            }
        }
    }

    private static let storageKey = "collections.pinned"

    private let defaults: UserDefaults
    private(set) var pinned: [Target]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pinned = (defaults.array(forKey: Self.storageKey) as? [String] ?? [])
            .compactMap(Target.init(token:))
    }

    func isPinned(_ target: Target) -> Bool {
        pinned.contains(target)
    }

    func toggle(_ target: Target) {
        if let index = pinned.firstIndex(of: target) {
            pinned.remove(at: index)
        } else {
            pinned.append(target)
        }
        persist()
    }

    private func persist() {
        defaults.set(pinned.map(\.token), forKey: Self.storageKey)
    }
}
