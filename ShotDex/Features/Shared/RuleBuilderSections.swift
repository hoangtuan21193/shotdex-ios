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
    var places: [String] = []
    /// Live count of matching photos; nil hides the footer.
    var matchCount: Int?

    /// Photo-vs-video as a scope control instead of a condition row. Backed by a
    /// single `.mediaType` rule so it compiles through the same SQL builder as
    /// everything else; "All" simply removes it.
    private var mediaKind: Binding<MediaKind?> {
        Binding(
            get: {
                query.rules
                    .first { $0.field == .mediaType && $0.op == .isExactly }
                    .flatMap { MediaKind(rawValue: $0.text) }
            },
            set: { kind in
                query.rules.removeAll { $0.field == .mediaType && $0.op == .isExactly }
                guard let kind else { return }
                query.rules.insert(
                    SmartAlbumRule(field: .mediaType, op: .isExactly, text: kind.rawValue),
                    at: 0
                )
            }
        )
    }

    /// Editable bindings for the conditions shown as rows.
    private var visibleRuleBindings: [Binding<SmartAlbumRule>] {
        Array($query.rules).filter { $0.wrappedValue.field != .mediaType }
    }

    var body: some View {
        Section {
            Picker("Media Type", selection: mediaKind) {
                Text("All").tag(MediaKind?.none)
                ForEach(MediaKind.allCases) { kind in
                    Text(kind.displayName).tag(MediaKind?.some(kind))
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Media Type")
        } footer: {
            if query.matchMode == .any, mediaKind.wrappedValue != nil {
                Text("Counts as one of the conditions, so it widens the match rather than narrowing it.")
            }
        }

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
            // The media-type rule has its own control above, so it is filtered
            // out of the rows rather than skipped inside the `ForEach` — swipe
            // offsets have to line up with what is actually on screen.
            ForEach(visibleRuleBindings, id: \.wrappedValue.id) { $rule in
                SmartAlbumRuleRow(
                    rule: $rule,
                    brands: brands,
                    bodies: bodies,
                    lenses: lenses,
                    places: places,
                    onDelete: { query.rules.removeAll { $0.id == rule.id } }
                )
            }
            .onDelete { offsets in
                let deleted = Set(offsets.map { visibleRuleBindings[$0].wrappedValue.id })
                query.rules.removeAll { deleted.contains($0.id) }
            }

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
