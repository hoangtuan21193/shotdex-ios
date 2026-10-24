import Foundation

/// What the Duplicates list shows (FS-06.06 §7.3): one kind. No All and no
/// Source frames (2026-10-21) — a bracket or focus stack is a Burst group.
enum DuplicatesFilter: Hashable, Sendable {
    case kind(DuplicateKind)

    init(stored: String?) {
        self = .kind(stored.flatMap(DuplicateKind.init(rawValue:)) ?? .exact)
    }

    var storedValue: String {
        switch self {
        case .kind(let kind): kind.rawValue
        }
    }

    func includes(_ group: DuplicateGroup) -> Bool {
        switch self {
        case .kind(let kind): group.kind == kind
        }
    }

    var title: String {
        switch self {
        case .kind(let kind): kind.title
        }
    }
}
