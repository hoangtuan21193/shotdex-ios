import SwiftUI

/// The shared rule-builder body: a match-mode picker plus a grow-as-you-go
/// list of conditions (each a `SmartAlbumRuleRow`), with a live match-count
/// footer. Rendered as `Section`s, so the parent embeds it inside its own
/// `List`. Used by both the smart-album editor (`SmartAlbumEditorSheet`) and
/// the Library advanced search (`AdvancedSearchSheet`) so the two stay in sync.
struct RuleBuilderSections: View {
    @Binding var query: SmartAlbumQuery
    let brands: [String]
    let bodies: [String]
    let lenses: [String]
    /// Live count of matching photos; nil hides the footer.
    var matchCount: Int?

    var body: some View {
        Section {
            Picker("Match", selection: $query.matchMode) {
                Text("All").tag(RuleMatchMode.all)
                Text("Any").tag(RuleMatchMode.any)
            }
            .pickerStyle(.segmented)
            Text(query.matchMode == .all
                ? "Photos must match every condition below."
                : "Photos must match at least one condition below.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Section {
            ForEach($query.rules) { $rule in
                SmartAlbumRuleRow(
                    rule: $rule,
                    brands: brands,
                    bodies: bodies,
                    lenses: lenses,
                    onDelete: { query.rules.removeAll { $0.id == rule.id } }
                )
            }
            .onDelete { query.rules.remove(atOffsets: $0) }

            Button {
                query.rules.append(SmartAlbumRule())
            } label: {
                Label("Add Condition", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Conditions")
        } footer: {
            if let matchCount {
                Text("Matches ^[\(matchCount) photo](inflect: true).")
            }
        }
    }
}
