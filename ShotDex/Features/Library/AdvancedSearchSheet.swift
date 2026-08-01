import SwiftUI

/// Advanced search for the Library: the same rule builder used to create a
/// smart album (`RuleBuilderSections`), but applied as a transient query over
/// the grid instead of a saved album. Applying sets
/// `LibraryModel.advancedQuery` (mutually exclusive with the normal
/// search/filter); "Save as Smart Album" hands the same rules to the editor.
struct AdvancedSearchSheet: View {
    let model: LibraryModel
    let dependencies: AppDependencies
    /// Called after applying so the caller can switch to the Library tab.
    var onApply: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var query: SmartAlbumQuery
    @State private var matchCount: Int?
    @State private var isSaveAsAlbumPresented = false

    init(model: LibraryModel, dependencies: AppDependencies, onApply: @escaping () -> Void) {
        self.model = model
        self.dependencies = dependencies
        self.onApply = onApply
        // Resume the active advanced query if there is one, else open on a
        // single blank condition to fill (matching the album editor).
        var initial = model.advancedQuery ?? .empty
        if initial.rules.isEmpty {
            initial.rules = [SmartAlbumRule()]
        }
        _query = State(initialValue: initial)
    }

    /// Rules complete enough to compile — the query actually applied/saved.
    private var cleaned: SmartAlbumQuery {
        SmartAlbumQuery(matchMode: query.matchMode, rules: query.validRules)
    }

    private var canApply: Bool { !query.isEmpty }

    var body: some View {
        NavigationStack {
            List {
                RuleBuilderSections(
                    query: $query,
                    brands: model.availableBrands,
                    bodies: model.availableBodies,
                    lenses: model.availableLenses,
                    places: model.availablePlaces,
                    matchCount: matchCount
                )

                Section {
                    Button {
                        isSaveAsAlbumPresented = true
                    } label: {
                        Label("Save as Smart Album", systemImage: "rectangle.stack.badge.plus")
                    }
                    .disabled(!canApply)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Advanced Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Search", action: apply)
                        .fontWeight(.semibold)
                        .disabled(!canApply)
                }
            }
            .sheet(isPresented: $isSaveAsAlbumPresented) {
                SmartAlbumEditorSheet(
                    existing: nil,
                    dependencies: dependencies,
                    initialQuery: cleaned,
                    onSaved: { isSaveAsAlbumPresented = false }
                )
            }
        }
        .onAppear {
            model.refreshFilterOptions()
        }
        .task(id: query) { await recomputeCount(for: query) }
    }

    private func apply() {
        guard canApply else { return }
        model.advancedQuery = cleaned
        onApply()
        dismiss()
    }

    /// Live match count off the main thread; skipped when no rule compiles.
    @MainActor
    private func recomputeCount(for snapshot: SmartAlbumQuery) async {
        let cleanedSnapshot = SmartAlbumQuery(
            matchMode: snapshot.matchMode,
            rules: snapshot.validRules
        )
        guard !cleanedSnapshot.isEmpty else {
            matchCount = nil
            return
        }
        let queries = dependencies.libraryQueries
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        let count = (try? await queries.count(matching: cleanedSnapshot)) ?? 0
        guard !Task.isCancelled, query == snapshot else { return }
        matchCount = count
    }
}

/// Active-advanced-query header for the Library grid: the match count and each
/// condition as a token, with Edit (reopen the builder) and Clear actions. The
/// advanced-search counterpart to `FilterTokenBar`.
struct AdvancedSearchBar: View {
    let query: SmartAlbumQuery
    var onEdit: () -> Void
    var onRemoveRule: (UUID) -> Void
    var onClear: () -> Void

    private var rules: [SmartAlbumRule] { query.validRules }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if rules.count > 1 {
                        Text("Match \(query.matchMode.word)")
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                            .foregroundStyle(.secondary)
                            .frame(minHeight: 44)
                    }

                    ForEach(rules) { rule in
                        ActiveConditionChip(
                            label: rule.compactDisplaySummary,
                            removalAccessibilityLabel: "Remove condition: \(rule.displaySummary)",
                            onRemove: { onRemoveRule(rule.id) }
                        )
                    }
                }
                .padding(.leading)
                .padding(.trailing, 8)
                .padding(.vertical, 6)
            }

            HStack(spacing: 12) {
                Divider()
                    .frame(height: 24)
                Button("Edit", action: onEdit)
                    .font(.footnote.weight(.medium))
                    .frame(minHeight: 44)
                Button("Clear", action: onClear)
                    .font(.footnote.weight(.medium))
                    .frame(minHeight: 44)
            }
            .padding(.trailing, 12)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
            .background(Color(.systemBackground))
        }
        .background(Color(.systemBackground))
    }
}
