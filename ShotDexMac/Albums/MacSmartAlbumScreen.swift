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
    /// When an `Original is …` album last read again for the check.
    @State private var lastOriginalReload = Date.distantPast

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
        // An album on the Original rule asks for fresh answers (FS-06.10 §4)
        // for as long as it is open — keyed by album, because the sidebar
        // swaps albums in this same view without a disappear.
        .task(id: album) {
            guard album.query.usesOriginal else { return }
            let check = dependencies.originalPresenceCheck
            check.screenOpened()
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(3600)) }
            check.screenClosed()
        }
        // Each batch of the original check can move photos in or out (§3).
        // At most one reload every 3 s: a pass runs ~275 batches, and a grid
        // reloading on each one flickers. Other albums never read it.
        .task(id: "\(album.query.usesOriginal ? dependencies.originalPresenceCheck.generation : 0)-\(model != nil)") {
            guard album.query.usesOriginal, let model else { return }
            let wait = 3 - Date().timeIntervalSince(lastOriginalReload)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            lastOriginalReload = Date()
            // Not tied to this task: the next batch re-keys it, and a load
            // cut off half-way would drop the rows it had not read yet.
            Task { await model.load() }
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
            // A nested group: one chip, its conditions joined by its and/or.
            ForEach(album.query.validGroups) { group in
                Text(group.displaySummary(naming: model.sourceNames))
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
            if !model.onServerLines.isEmpty || originalCheck != nil {
                VStack(alignment: .trailing, spacing: 2) {
                    // The counts keep to one line; the sentences after them
                    // (a hash mismatch names a device, FS-19.07 §12.4) wrap.
                    if let first = model.onServerLines.first {
                        Text(first).lineLimit(1)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                    // The originals check, under the On Server counts
                    // (FS-06.10 §3): its own element, the two tick apart.
                    if let originalCheck {
                        HStack(spacing: 6) {
                            originalGlyph(originalCheck)
                            Text(originalCheck.line).lineLimit(1)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(originalCheck.line.replacingOccurrences(of: " · ", with: ", "))
                        .accessibilityAddTraits(.updatesFrequently)
                    }
                    ForEach(Array(model.onServerLines.dropFirst().enumerated()), id: \.offset) { _, line in
                        Text(line).multilineTextAlignment(.trailing)
                    }
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .contain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// The original check's line and how far it is, for an album on the
    /// Original rule (FS-06.10 §3).
    private var originalCheck: (line: String, fraction: Double?)? {
        guard album.query.usesOriginal else { return nil }
        let check = dependencies.originalPresenceCheck
        let finishedAt = check.pass?.finishedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let line = OriginalPresenceProgressLine.text(checked: check.progress.checked, total: check.progress.total,
                                                     finishedAt: finishedAt)
        let isDone = finishedAt != nil && check.progress.checked >= check.progress.total
        let fraction = check.progress.total > 0 ? min(1, Double(check.progress.checked) / Double(check.progress.total)) : 0
        return (line, isDone ? nil : fraction)
    }

    /// A ring while the check runs, a check mark once it is through (board
    /// `MAC_SmartAlbum`, `original` tweak).
    @ViewBuilder
    private func originalGlyph(_ check: (line: String, fraction: Double?)) -> some View {
        if let fraction = check.fraction {
            ZStack {
                Circle().stroke(MacTheme.fill2, lineWidth: 1.5)
                Circle().trim(from: 0, to: fraction)
                    .stroke(MacTheme.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 12, height: 12)
            .accessibilityHidden(true)
        } else {
            // The ring's 12 pt box, so the text does not move when it turns.
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
        }
    }

    /// Delete through the gate (FS-19.07 §9): photos that rely on a server
    /// are checked there first; Can't Reach asks Delete Anyway or Cancel.
    private func delete() {
        guard let model, !selection.isEmpty else { return }
        let ids = Array(selection)
        // Folder and server photos have no PHAsset: PhotoKit alone would
        // drop them and report success (FS-19.04 §2).
        let roots = dependencies.folderRoots
        if var request = try? DeletionTargetQueries(database: dependencies.database, hasTrash: { roots.hasTrash($0) })
            .request(photoIds: ids, selection: .photos) {
            request.plan.trashName = MixedDeletionPlan.macTrashName
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
