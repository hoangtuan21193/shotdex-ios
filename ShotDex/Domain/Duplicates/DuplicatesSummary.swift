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

/// The numbers of the summary screen (§7.2): what Quick clean would free,
/// what needs a choice, and the source frames, which free nothing.
struct DuplicatesSummary: Equatable, Sendable {
    struct Row: Equatable, Sendable, Identifiable {
        var kind: DuplicateKind
        var groups: Int
        var bytes: Int
        var id: DuplicateKind { kind }
    }

    var groupCount = 0
    var freeBytes = 0
    var quickClean: [Row] = []
    var chooseYourself: [Row] = []
    var brackets = 0
    var focusStacks = 0

    var quickCleanGroups: Int { quickClean.reduce(0) { $0 + $1.groups } }
    var quickCleanBytes: Int { quickClean.reduce(0) { $0 + $1.bytes } }
    var chooseGroups: Int { chooseYourself.reduce(0) { $0 + $1.groups } }
    var chooseBytes: Int { chooseYourself.reduce(0) { $0 + $1.bytes } }
    var hasSourceFrames: Bool { brackets + focusStacks > 0 }

    init(groups: [DuplicateGroup], freeBytes: (DuplicateGroup) -> Int) {
        var rows: [DuplicateKind: Row] = [:]
        for group in groups {
            if let set = group.sourceSet {
                if set.kind == .bracket { brackets += 1 } else { focusStacks += 1 }
                continue
            }
            groupCount += 1
            let bytes = freeBytes(group)
            self.freeBytes += bytes
            rows[group.kind, default: Row(kind: group.kind, groups: 0, bytes: 0)].groups += 1
            rows[group.kind]?.bytes += bytes
        }
        for kind in DuplicateKind.allCases {
            guard let row = rows[kind] else { continue }
            if kind.isCopy { quickClean.append(row) } else { chooseYourself.append(row) }
        }
    }

    /// "6 brackets · 2 focus stacks".
    var sourceFramesText: String {
        var parts: [String] = []
        if brackets > 0 {
            parts.append(brackets == 1
                ? String(localized: "1 bracket", comment: "Duplicates summary: source frames count")
                : String(localized: "\(brackets) brackets", comment: "Duplicates summary: source frames count"))
        }
        if focusStacks > 0 {
            parts.append(focusStacks == 1
                ? String(localized: "1 focus stack", comment: "Duplicates summary: source frames count")
                : String(localized: "\(focusStacks) focus stacks", comment: "Duplicates summary: source frames count"))
        }
        return parts.joined(separator: " · ")
    }
}
