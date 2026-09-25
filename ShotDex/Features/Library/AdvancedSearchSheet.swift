import SwiftUI

/// Advanced search: the same rule builder used to create a smart album
/// (`RuleBuilderSections`), applied as a transient query over a grid instead
/// of a saved album.
///
/// Library applies it to the whole library (mutually exclusive with its quick
/// filters) and offers "Save as Smart Album". An album applies it inside the
/// album only (FS-06.09): the confirm button says Apply, the live count is the
/// album's, and there is no Save — a smart album saved from here would match
/// the whole library, not the album.
struct AdvancedSearchSheet: View {
    let dependencies: AppDependencies
    var confirmTitle: LocalizedStringKey = "Search"
    var allowsSaveAsSmartAlbum = true
    /// How many photos a query would show where it is being applied.
    var countMatches: @MainActor (SmartAlbumQuery) async -> Int
    var onApply: (SmartAlbumQuery) -> Void
    /// Library refreshes its own suggestion lists when the sheet opens.
    var onPresent: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var query: SmartAlbumQuery
    @State private var matchCount: Int?
    @State private var isSaveAsAlbumPresented = false
    @State private var suggestions = FilterSuggestionCatalog(brands: [], bodies: [], lenses: [], places: [])

    init(
        initialQuery: SmartAlbumQuery?,
        dependencies: AppDependencies,
        confirmTitle: LocalizedStringKey = "Search",
        allowsSaveAsSmartAlbum: Bool = true,
        countMatches: @escaping @MainActor (SmartAlbumQuery) async -> Int,
        onApply: @escaping (SmartAlbumQuery) -> Void,
        onPresent: (() -> Void)? = nil
    ) {
        self.dependencies = dependencies
        self.onPresent = onPresent
        self.confirmTitle = confirmTitle
        self.allowsSaveAsSmartAlbum = allowsSaveAsSmartAlbum
        self.countMatches = countMatches
        self.onApply = onApply
        // Resume the active query if there is one, else open on a single
        // blank condition to fill (matching the album editor).
        var initial = initialQuery ?? .empty
        if initial.rules.isEmpty {
            initial.rules = [SmartAlbumRule()]
        }
        _query = State(initialValue: initial)
    }

    /// Library's sheet: applies to `LibraryModel.advancedQuery`, then calls
    /// `onApplied` so the caller can switch to the Library tab.
    init(model: LibraryModel, dependencies: AppDependencies, onApplied: @escaping () -> Void) {
        let queries = dependencies.libraryQueries
        self.init(
            initialQuery: model.advancedQuery,
            dependencies: dependencies,
            countMatches: { query in (try? await queries.count(matching: query)) ?? 0 },
            onApply: { query in
                model.advancedQuery = query
                onApplied()
            },
            onPresent: { model.refreshFilterOptions() }
        )
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
                    brands: suggestions.brands,
                    bodies: suggestions.bodies,
                    lenses: suggestions.lenses,
                    places: suggestions.places,
                    matchCount: matchCount
                )

                if allowsSaveAsSmartAlbum {
                    Section {
                        Button {
                            isSaveAsAlbumPresented = true
                        } label: {
                            Label("Save as Smart Album", systemImage: "plus.rectangle.on.rectangle")
                        }
                        .disabled(!canApply)
                    }
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
                    Button(confirmTitle, action: apply)
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
        .task {
            onPresent?()
            // Shared actor cache: the DISTINCT scans never block the sheet,
            // and every presentation after the first reuses the catalog.
            suggestions = await dependencies.filterSuggestions.load()
        }
        .task(id: query) { await recomputeCount(for: query) }
    }

    private func apply() {
        guard canApply else { return }
        onApply(cleaned)
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
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        let count = await countMatches(cleanedSnapshot)
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
    /// Flips the query between "match all" and "match any" and re-runs it.
    var onToggleMatchMode: () -> Void

    private var rules: [SmartAlbumRule] { query.validRules }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if rules.count > 1 {
                        // A control, not a caption. It used to be dead text that
                        // said "Match all" and did nothing, while being the one
                        // thing on the bar that changes what every condition
                        // below it means — tapping it now switches all/any.
                        ActiveConditionChip(
                            label: "Match \(query.matchMode.word)",
                            onTap: onToggleMatchMode,
                            isEmphasised: false
                        )
                        .accessibilityLabel("Match \(query.matchMode.word) of the conditions")
                        .accessibilityHint("Switches between matching all and any")
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
                .padding(.trailing, ActiveConditionChip.scrollFadeWidth)
                .padding(.vertical, 6)
            }
            .fadingTrailingEdge()

            HStack(spacing: 16) {
                Button("Edit", action: onEdit)
                    .font(.footnote.weight(.medium))
                Button("Clear", action: onClear)
                    .font(.footnote.weight(.medium))
            }
            .tint(.primary)
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .glassBackground(Capsule())
            .padding(.trailing, AppTheme.Size.floatingChromeMargin)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
        }
        // Floating chrome, no band — same reasoning as `FilterTokenBar`.
    }
}
