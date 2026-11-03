import Photos
import SwiftUI

/// A smart album in the Library window (board `MAC_SmartAlbum`, FS-19.07 §11):
/// the read-only conditions and the On Server line under the toolbar, the
/// grid with the "on server" glyph, and Delete (⌘⌫) through the gate that
/// asks the server first (§9). A selection with a folder or server copy goes
/// through the sources instead (FS-19.04 §2), as on iOS: a server copy is
/// hidden in ShotDex, never deleted on the server.
struct MacSmartAlbumScreen: View {
    let album: SmartAlbum
    var edit: () -> Void
    @Environment(MacDependencies.self) private var dependencies
    @State private var model: SmartAlbumDetailModel?
    @State private var selection: Set<String> = []
    @State private var onServer: Set<String> = []
    @State private var deletion = PhotoDeletionFlow()
    @State private var sourceDeletion: DeletionTargetQueries.Request?
    @State private var deleteError: String?
    /// The first load has finished; until then an empty list means "not yet".
    @State private var hasLoaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let model {
                conditionsBar(model)
                Divider()
                if hasLoaded, model.items.isEmpty, !model.isLoading {
                    emptyState
                } else {
                    MacPhotoGrid(items: model.items, photoLibrary: dependencies.photoLibrary,
                                 asset: { model.asset(for: $0) }, picture: MacRootWindow.demoPicture,
                                 isNewestFirst: true, showsDays: false, onServer: onServer, onSelection: { selection = $0 })
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(album.name)
        .navigationSubtitle(String(localized: "Smart Album", comment: "Mac toolbar subtitle of a smart album"))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: edit) {
                    Label(String(localized: "Edit Smart Album…", comment: "Mac: edit the open smart album"), systemImage: "slider.horizontal.3")
                }
                Button(role: .destructive, action: delete) {
                    Label(selection.count == 1
                          ? String(localized: "Delete 1 Photo…", comment: "Mac: delete the selected photo")
                          : String(localized: "Delete \(selection.count) Photos…", comment: "Mac: delete the selected photos"),
                          systemImage: "trash")
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(selection.isEmpty || deletion.isChecking)
            }
        }
        .photoDeletionPrompts(deletion)
        .sourceDeletion($sourceDeletion, context: dependencies.sourceDeletion) { removed, _ in
            model?.removeDeleted(ids: removed)
            selection.subtract(removed)
        }
        .alert(String(localized: "Couldn't Delete", comment: "Mac: a delete failed"),
               isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button(String(localized: "OK", comment: "Delete: dismiss"), role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
        .task(id: album) {
            let model = SmartAlbumDetailModel(album: album, libraryQueries: dependencies.libraryQueries,
                                              metadataStore: dependencies.metadataStore, photoLibrary: dependencies.photoLibrary,
                                              pipeline: dependencies.indexPipeline, database: dependencies.database)
            self.model = model
            selection = []
            hasLoaded = false
            await model.load()
            hasLoaded = true
        }
        .task(id: "\(dependencies.onServerCheck.generation)-\(model != nil)") {
            guard let model else { return }
            await model.refreshOnServer(dependencies.onServerCheck,
                                        isLimited: dependencies.photoLibrary.authorizationState == .limited)
            let queries = OnServerProgressQueries(database: dependencies.database)
            onServer = (try? await Task.detached { try queries.presentAnywhere() }.value) ?? []
            if dependencies.onServerCheck.generation > 0 { await model.load() }
        }
    }

    /// No photo matches (board `MAC_SmartAlbum`, `empty` tweak): say so in
    /// the album's words and offer the one way out, editing the conditions.
    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "No Photos Match", comment: "Mac smart album: nothing matches the conditions"),
                  systemImage: "gearshape.2")
        } description: {
            Text("Photos that match these conditions appear here as they're added.",
                 comment: "Mac smart album: empty state explanation")
        } actions: {
            Button(String(localized: "Edit Smart Album…", comment: "Mac: edit the open smart album"), action: edit)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Under the toolbar (board `MAC_SmartAlbum`): the conditions as
    /// read-only chips and the count on the left, the On Server line on the
    /// right.
    private func conditionsBar(_ model: SmartAlbumDetailModel) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(album.query.validRules) { rule in
                Text(rule.displaySummary(naming: model.sourceNames))
                    .font(.callout)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }
            Text(model.matchCount == 1
                 ? String(localized: "1 photo", comment: "Mac toolbar subtitle")
                 : String(localized: "\(model.matchCount.formatted()) photos", comment: "Mac toolbar subtitle"))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .padding(.vertical, 4)
            Spacer(minLength: 12)
            if !model.onServerLines.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    // The counts keep to one line; the sentences after them
                    // (a hash mismatch names a device, FS-19.07 §12.4) wrap.
                    ForEach(Array(model.onServerLines.enumerated()), id: \.offset) { index, line in
                        Text(line).lineLimit(index == 0 ? 1 : nil).multilineTextAlignment(.trailing)
                    }
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Delete through the gate (FS-19.07 §9): photos that rely on a server
    /// are checked there first; Can't Reach asks Delete Anyway or Cancel.
    private func delete() {
        guard let model, !selection.isEmpty else { return }
        let ids = Array(selection)
        // Folder and server photos have no PHAsset: PhotoKit alone would
        // drop them and report success (FS-19.04 §2).
        let roots = dependencies.folderRoots
        if let request = try? DeletionTargetQueries(database: dependencies.database, hasTrash: { roots.hasTrash($0) })
            .request(photoIds: ids, selection: .photos) {
            sourceDeletion = request
            return
        }
        deletion.delete(ids, gate: dependencies.photoDeletionGate, perform: { targets in
            try await model.deleteAssets(ids: Set(targets), checkingServer: false)
        }, finished: { result in
            switch result {
            case .success: selection = []
            case .failure(let error) where error is CancellationError: break
            case .failure(let error):
                if (error as? PHPhotosError)?.code != .userCancelled { deleteError = error.localizedDescription }
            }
        })
    }
}
