import Foundation

/// A folder inside or around an existing source is refused (FS-19.01 §1):
/// overlapping sources would see every file twice and fight over its
/// sidecar.
enum SourceOverlap: Equatable, Sendable {
    case none
    /// The chosen folder sits inside this source.
    case inside(sourceName: String)
    /// The chosen folder contains this source.
    case contains(sourceName: String)

    struct Existing: Sendable {
        let name: String
        let path: String
    }

    static func check(_ path: String, against sources: [Existing]) -> SourceOverlap {
        let chosen = components(path)
        for source in sources {
            let existing = components(source.path)
            if chosen.starts(with: existing) { return .inside(sourceName: source.name) }
            if existing.starts(with: chosen) { return .contains(sourceName: source.name) }
        }
        return .none
    }

    /// The refusal the user reads; nil when the folder can be added.
    var message: String? {
        switch self {
        case .none:
            nil
        case .inside(let name):
            String(localized: "Already part of “\(name)”.", comment: "Add source refused: the folder is inside an existing source")
        case .contains(let name):
            String(localized: "Contains “\(name)”. Remove that source first to add this folder.",
                   comment: "Add source refused: the folder contains an existing source")
        }
    }

    /// Path components, normalized the way the file systems compare them:
    /// NFC, case folded (APFS, exFAT and SMB shares are case-insensitive).
    private static func components(_ path: String) -> [String] {
        URL(fileURLWithPath: path).standardizedFileURL.pathComponents
            .map { $0.precomposedStringWithCanonicalMapping.lowercased() }
            .filter { $0 != "/" }
    }
}
