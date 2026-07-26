import SwiftUI

/// Creates or edits a smart album with a macOS-Photos-style rule builder: a
/// name, a match mode (all / any), and a list of conditions grown one at a
/// time. Each condition picks a field, an operator (contains / is / greater
/// than / …), and a value. Saving persists a `SmartAlbum` (JSON-encoded
/// `SmartAlbumQuery`) via `SmartAlbumStore`.
struct SmartAlbumEditorSheet: View {
    /// Non-nil when editing an existing album (reuses its id + createdAt).
    var existing: SmartAlbum?
    let dependencies: AppDependencies
    /// Called after a successful save so the caller can reload.
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var query: SmartAlbumQuery
    @State private var availableBrands: [String] = []
    @State private var availableBodies: [String] = []
    @State private var availableLenses: [String] = []
    /// Live count of photos the current rules match (nil until first compute).
    @State private var matchCount: Int?
    /// Lowercased names of the *other* smart albums, for the uniqueness check.
    @State private var takenNames: Set<String> = []

    init(
        existing: SmartAlbum?,
        dependencies: AppDependencies,
        initialQuery: SmartAlbumQuery? = nil,
        onSaved: @escaping () -> Void
    ) {
        self.existing = existing
        self.dependencies = dependencies
        self.onSaved = onSaved
        _name = State(initialValue: existing?.name ?? "")
        // New albums open with one blank condition so there is a row to fill;
        // existing albums load their saved rules. `initialQuery` seeds a new
        // album from elsewhere (e.g. "Save as Smart Album" in advanced search).
        var initial = existing?.query ?? initialQuery ?? .empty
        if initial.rules.isEmpty {
            initial.rules = [SmartAlbumRule()]
        }
        _query = State(initialValue: initial)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A non-empty name already used by another smart album (case-insensitive).
    private var isDuplicateName: Bool {
        !trimmedName.isEmpty && takenNames.contains(trimmedName.lowercased())
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !query.isEmpty && !isDuplicateName
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Smart Album Name", text: $name)
                } header: {
                    Text("Name")
                } footer: {
                    if isDuplicateName {
                        Text("A smart album named “\(trimmedName)” already exists.")
                            .foregroundStyle(.red)
                    }
                }

                RuleBuilderSections(
                    query: $query,
                    brands: availableBrands,
                    bodies: availableBodies,
                    lenses: availableLenses,
                    matchCount: matchCount
                )
            }
            .listStyle(.insetGrouped)
            .navigationTitle(existing == nil ? "New Smart Album" : "Edit Smart Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
        .task { await prepare() }
        .task(id: query) { await recomputeCount(for: query) }
    }

    /// Loads autocomplete suggestion sources and the initial match count.
    @MainActor
    private func prepare() async {
        let suggestionCache = dependencies.filterSuggestions
        let smartAlbumStore = dependencies.smartAlbumStore
        async let suggestionLoad = suggestionCache.load()
        let all = await Task.detached(priority: .utility) {
            (try? smartAlbumStore.fetchAllOrdered()) ?? []
        }.value
        let catalog = await suggestionLoad
        guard !Task.isCancelled else { return }
        availableBrands = catalog.brands
        availableBodies = catalog.bodies
        availableLenses = catalog.lenses
        // Names of every *other* album, so renaming to an existing name is
        // blocked while keeping this album's own name valid when editing.
        takenNames = Set(
            all.filter { $0.id != existing?.id }
                .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )
    }

    /// Recomputes the live match count off the main thread; a `COUNT(*)` over
    /// the compiled rules. Skips work when there is no valid condition yet.
    @MainActor
    private func recomputeCount(for snapshot: SmartAlbumQuery) async {
        guard !snapshot.isEmpty else {
            matchCount = nil
            return
        }
        let queries = dependencies.libraryQueries
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        let count = (try? await queries.count(matching: snapshot)) ?? 0
        guard !Task.isCancelled, query == snapshot else { return }
        matchCount = count
    }

    private func save() {
        guard canSave else { return }
        // Persist only the compilable rules — blank rows are dropped.
        let cleaned = SmartAlbumQuery(matchMode: query.matchMode, rules: query.validRules)
        let album = SmartAlbum(
            id: existing?.id ?? UUID().uuidString,
            name: trimmedName,
            query: cleaned,
            createdAt: existing?.createdAt ?? Int(Date().timeIntervalSince1970)
        )
        try? dependencies.smartAlbumStore.upsert(album)
        onSaved()
        dismiss()
    }
}
