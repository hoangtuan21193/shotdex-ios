import Foundation

/// The copy checklist of a deletion from All Photos, an album or an
/// unfiltered Cull (FS-19.04 §1): one row per copy for one photo, one row
/// per source for several. On by default: the copy each photo opens from;
/// the others are backups, off. Absent when no photo has two copies.
struct CopyChecklist: Equatable, Sendable {
    struct Row: Equatable, Sendable, Identifiable {
        let sourceId: String
        let title: String
        /// Photos with a copy in this source, for the several-photos form.
        let count: Int
        var isOn: Bool
        var id: String { sourceId }
    }

    var rows: [Row]

    /// The copies `[photo][copy]` in copy order; nil when every photo has one.
    init?(copies: [[DeletionTarget]]) {
        guard copies.contains(where: { $0.count > 1 }) else { return nil }
        let single = copies.count == 1
        var order: [String] = []
        var titles: [String: String] = [:]
        var counts: [String: Int] = [:]
        var on: Set<String> = []
        for photo in copies {
            if let first = photo.first { on.insert(first.sourceId) }
            for copy in photo {
                if titles[copy.sourceId] == nil {
                    order.append(copy.sourceId)
                    titles[copy.sourceId] = Self.title(copy, withPath: single)
                }
                counts[copy.sourceId, default: 0] += 1
            }
        }
        rows = order.map { Row(sourceId: $0, title: titles[$0]!, count: counts[$0]!, isOn: on.contains($0)) }
    }

    /// "T7 RAW Archive › RAW/2026-09-27", "Photos Library", "NAS Home (hide)".
    static func title(_ copy: DeletionTarget, withPath: Bool) -> String {
        if case .hide = copy.destination {
            return String(localized: "\(copy.sourceName) (hide)", comment: "Deletion checklist: a server copy, which is hidden rather than deleted")
        }
        if withPath, copy.kind == "file", let path = copy.relativePath {
            let folder = (path as NSString).deletingLastPathComponent
            if !folder.isEmpty { return "\(copy.sourceName) › \(folder)" }
        }
        return copy.sourceName
    }

    var enabledSources: Set<String> { Set(rows.filter(\.isOn).map(\.sourceId)) }

    /// The copies the deletion removes with the checklist as it stands.
    func selected(_ copies: [[DeletionTarget]]) -> [[DeletionTarget]] {
        let on = enabledSources
        return copies.map { $0.filter { on.contains($0.sourceId) } }.filter { !$0.isEmpty }
    }
}
