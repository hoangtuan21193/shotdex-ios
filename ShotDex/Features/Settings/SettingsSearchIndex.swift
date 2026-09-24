import Foundation

/// One row, as search offers it.
struct SettingsSearchEntry: Identifiable, Hashable, Sendable {
    let label: SettingsRowLabel
    /// The row's own words, resolved for the current language.
    let text: String
    /// Which sidebar item holds the row — the subtitle under every result, so
    /// the reader learns where the row lives rather than only being teleported
    /// to it.
    let section: SettingsSection
    let sectionTitle: String
    /// Set when the row is not always on screen; see
    /// `SettingsRowLabel.Availability`.
    let explanation: String?

    var id: SettingsRowLabel { label }
}

/// Search over the rows of Settings.
///
/// Derived from `SettingsRowLabel.allCases`, never written out a second time:
/// a row that exists is a row that is findable, and there is no way to add one
/// without indexing it.
///
/// Matching is on **row** labels, not section names. Nine sidebar items filtered
/// by their own titles would be useless — people type "ISO", "cellular", "hdr",
/// which are rows buried inside a group.
enum SettingsSearchIndex {

    /// Every row, in sidebar order, then in the order the section draws them.
    static let entries: [SettingsSearchEntry] = {
        let order = Dictionary(
            uniqueKeysWithValues: SettingsGroup.allCases.enumerated().map { ($1, $0) }
        )
        return SettingsRowLabel.allCases
            .sorted { lhs, rhs in
                let left = sectionIndex(of: lhs)
                let right = sectionIndex(of: rhs)
                if left != right { return left < right }
                let leftGroup = order[lhs.group] ?? 0
                let rightGroup = order[rhs.group] ?? 0
                if leftGroup != rightGroup { return leftGroup < rightGroup }
                return declarationIndex(of: lhs) < declarationIndex(of: rhs)
            }
            .map(entry(for:))
    }()

    /// The rows a query finds, in the same order as `entries`.
    ///
    /// Substring, not prefix: "cellular" has to reach "Use **Cellular** Data
    /// for Indexing", which is the case the whole feature is for. An empty or
    /// blank query finds nothing, so the caller keeps showing the settings
    /// themselves instead of dumping all 38 rows as "results".
    static func results(for query: String) -> [SettingsSearchEntry] {
        let needle = WidgetAlbumCatalog.normalized(query)
        guard !needle.isEmpty else { return [] }
        return table.filter { $0.normalized.contains(needle) }.map(\.entry)
    }

    /// Every row a sidebar item holds.
    static func entries(in section: SettingsSection) -> [SettingsSearchEntry] {
        entries.filter { $0.section == section }
    }

    /// The sidebar item that shows a row.
    static func section(for label: SettingsRowLabel) -> SettingsSection {
        SettingsSection.allCases.first { $0.groups.contains(label.group) } ?? .photoLibrary
    }

    // MARK: Private

    /// Resolved once: 38 rows through `String(localized:)` on every keystroke
    /// would be work for nothing, and the answer only changes with the app's
    /// language.
    private static let table: [(normalized: String, entry: SettingsSearchEntry)] =
        entries.map { entry in
            let words = ([entry.text] + entry.label.searchAliases).joined(separator: " ")
            return (WidgetAlbumCatalog.normalized(words), entry)
        }

    private static func entry(for label: SettingsRowLabel) -> SettingsSearchEntry {
        let section = section(for: label)
        return SettingsSearchEntry(
            label: label,
            text: String(localized: label.text),
            section: section,
            sectionTitle: String(localized: section.title),
            explanation: label.availability.explanation.map { String(localized: $0) }
        )
    }

    private static func sectionIndex(of label: SettingsRowLabel) -> Int {
        SettingsSection.allCases.firstIndex(of: section(for: label)) ?? 0
    }

    private static func declarationIndex(of label: SettingsRowLabel) -> Int {
        SettingsRowLabel.allCases.firstIndex(of: label) ?? 0
    }
}
