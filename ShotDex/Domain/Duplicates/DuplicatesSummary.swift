import Foundation

/// What the Duplicates list shows (FS-06.06 §7.3): every group, one kind,
/// or the brackets and focus stacks. A source set shows under All and
/// Source frames only — never as a kind's junk.
enum DuplicatesFilter: Hashable, Sendable {
    case all
    case kind(DuplicateKind)
    case sourceFrames

    init(stored: String?) {
        switch stored {
        case "sourceFrames": self = .sourceFrames
        case let raw?: self = DuplicateKind(rawValue: raw).map(DuplicatesFilter.kind) ?? .all
        case nil: self = .all
        }
    }

    var storedValue: String {
        switch self {
        case .all: ""
        case .kind(let kind): kind.rawValue
        case .sourceFrames: "sourceFrames"
        }
    }

    func includes(_ group: DuplicateGroup) -> Bool {
        switch self {
        case .all: true
        case .kind(let kind): group.sourceSet == nil && group.kind == kind
        case .sourceFrames: group.sourceSet != nil
        }
    }

    var title: String {
        switch self {
        case .all: String(localized: "All", comment: "Duplicates filter: every kind of group")
        case .kind(let kind): kind.title
        case .sourceFrames: String(localized: "Source frames", comment: "Duplicates filter: brackets and focus stacks")
        }
    }
}
