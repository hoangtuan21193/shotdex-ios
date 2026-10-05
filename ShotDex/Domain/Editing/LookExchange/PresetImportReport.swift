import Foundation

/// The sheet after an import (FS-03.14a §3): a header, then one row per preset
/// with its status and the lines behind it. Not kept after it closes.
struct PresetImportReport: Equatable {
    enum Status: Equatable {
        case added, addedWithChanges, skipped

        var title: String {
            switch self {
            case .added: "Added"
            case .addedWithChanges: "Added with changes"
            case .skipped: "Skipped"
            }
        }

        var symbol: String {
            switch self {
            case .added: "✓"
            case .addedWithChanges: "≈"
            case .skipped: "✕"
            }
        }
    }

    struct Entry: Equatable, Identifiable {
        let id = UUID()
        var name: String
        var status: Status
        var lines: [PresetReportLine]

        static func == (lhs: Entry, rhs: Entry) -> Bool {
            lhs.name == rhs.name && lhs.status == rhs.status && lhs.lines == rhs.lines
        }
    }

    var entries: [Entry] = []
    /// What the import put on the shelves, in file order: the new My Looks
    /// and the new LUTs. The Video Studio selects the first of them for the
    /// slot being edited (FS-12.06c §7).
    var addedLookIDs: [UUID] = []
    var addedLUTIDs: [String] = []

    var addedCount: Int { entries.filter { $0.status != .skipped }.count }
    var skippedCount: Int { entries.filter { $0.status == .skipped }.count }

    /// "12 looks added · 2 skipped"; "1 look added" when nothing was skipped.
    var header: String {
        let added = switch addedCount {
        case 0: "No looks added"
        case 1: "1 look added"
        default: "\(addedCount) looks added"
        }
        return skippedCount == 0 ? added : "\(added) · \(skippedCount) skipped"
    }

    /// A preset's status from what its mapping did: every setting applied is
    /// ✓, some changed or skipped with at least one applied is ≈, none
    /// applied is ✕.
    static func status(applied: Int, lines: [PresetReportLine]) -> Status {
        guard applied > 0 else { return .skipped }
        return lines.contains { $0.kind != .applied } ? .addedWithChanges : .added
    }
}
