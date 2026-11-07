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
    @State private var folderPicker = SourceFolderPicker()
    @State private var availableBrands: [String] = []
    @State private var availableBodies: [String] = []
    @State private var availableLenses: [String] = []
    /// Live count of photos the current rules match (nil until first compute).
    @State private var matchCount: Int?
    /// Lowercased names of the *other* smart albums, for the uniqueness check.
    @State private var takenNames: Set<String> = []
    /// Keep in Photos (FS-06.12): the switch as loaded, and as set now.
    @State private var keepsInPhotos = false
    @State private var keptInPhotos = false

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
            // Wide: name and scope on a 320pt leading column, the conditions
            // beside them (board `DI_SmartAlbumEditor`).
            AdaptiveFormColumns(leadingWidth: 320) {
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

                rules(.scope)
            } trailing: {
                rules(.conditions)
            } closing: {
                keepInPhotosSection
            }
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
        .sourceFolderPicker(folderPicker, query: $query)
        .task { await prepare() }
        .task(id: query) { await recomputeCount(for: query) }
    }

    /// Keep in Photos — last in one column, under Match in two (FS-06.12 §6).
    /// Needs Full Access: an album of photos ShotDex cannot all see would
    /// not be "exactly these photos".
    private var keepInPhotosSection: some View {
        let isFullAccess = dependencies.photoLibrary.authorizationState == .authorized
        return Section {
            // On without Full Access can still be turned off (UX review).
            Toggle("Keep in Photos", isOn: $keepsInPhotos)
                .disabled(!isFullAccess && !keepsInPhotos)
        } footer: {
            if isFullAccess {
                Text("ShotDex keeps an album in Photos with exactly these photos.")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(keepsInPhotos ? "Needs Full Photos Access. The album in Photos isn’t updating." : "Needs Full Photos Access.")
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .font(.footnote)
                }
            }
        }
    }

    private func rules(_ parts: RuleBuilderSections.Parts) -> some View {
        RuleBuilderSections(
            query: $query,
            brands: availableBrands,
            bodies: availableBodies,
            lenses: availableLenses,
            matchCount: matchCount,
            parts: parts
        )
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
        let links = SmartAlbumPhotosAlbumStore(database: dependencies.database)
        let albumId = existing?.id
        let kept = await Task.detached(priority: .utility) {
            albumId.flatMap { try? links.link($0) }?.isEnabled ?? false
        }.value
        let catalog = await suggestionLoad
        guard !Task.isCancelled else { return }
        // The switch as the person left it if they touched it while this loaded.
        if keepsInPhotos == keptInPhotos { keepsInPhotos = kept }
        keptInPhotos = kept
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
        let cleaned = query.cleaned
        let album = SmartAlbum(
            id: existing?.id ?? UUID().uuidString,
            name: trimmedName,
            query: cleaned,
            createdAt: existing?.createdAt ?? Int(Date().timeIntervalSince1970)
        )
        do {
            try dependencies.smartAlbumStore.upsert(album)
        } catch {
            return
        }
        // Only after the album row exists: a link to no album is never cleaned up.
        if keepsInPhotos != keptInPhotos {
            try? SmartAlbumPhotosAlbumStore(database: dependencies.database).setEnabled(keepsInPhotos, smartAlbumId: album.id)
            // The album's line shows the change now, not after the next pass.
            dependencies.photosAlbumSync.linksChanged()
        }
        // A rename or new conditions change the album in Photos too.
        dependencies.photosAlbumSync.setNeedsSync()
        onSaved()
        dismiss()
    }
}
