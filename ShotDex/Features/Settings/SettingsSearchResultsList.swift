import SwiftUI

/// What Settings shows while something is typed in its search field.
///
/// Rows, not sections: people search for "ISO" and "cellular", which are rows
/// buried inside a group. Each result names the item that holds it, so the
/// reader also learns where the setting lives instead of only being sent there.
struct SettingsSearchResultsList: View {
    let query: String
    let onSelect: (SettingsSearchEntry) -> Void

    private var results: [SettingsSearchEntry] {
        SettingsSearchIndex.results(for: query)
    }

    var body: some View {
        if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List(results) { entry in
                SettingsSearchResultRow(entry: entry) { onSelect(entry) }
            }
            .listStyle(.insetGrouped)
            .accessibilityIdentifier("settings.search.results")
        }
    }
}

/// One result, as a row of whichever list is showing it — the phone's settings
/// list or the iPad's sidebar. Shared so a result reads the same in both.
struct SettingsSearchResultRow: View {
    let entry: SettingsSearchEntry
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(entry.text)
                Text(entry.sectionTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // The index knows every row the screen can draw, including the
                // ones that appear only under a condition. Saying so here is
                // what keeps a result from being a tap that visibly does
                // nothing.
                if let explanation = entry.explanation {
                    Text(explanation)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.searchResult.\(entry.label.rawValue)")
    }
}
