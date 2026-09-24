import PencilKit
import Photos
import SwiftUI
import ShotDexKit

/// Photo editor (Turn 31): a Dynamic Island band, the photo, and a fixed panel.
///
/// There is no top bar and no in-panel command row. A floating command row rides
/// the band over the Dynamic Island: undo / redo / hold-for-original on the leading
/// edge, the histogram mini (taps to expand the floating card) and the ⋯ menu on
/// the trailing edge. The panel height is fixed for the whole session and never
/// resizes — its tiers, top to bottom, are the scrolling parameter zone (an
/// optional Grade target strip is its first row, so the panel is the same height on
/// every tab), the group strip — a snap wheel flanked by Back and Save — and a bare
/// home-indicator inset. The wheel is the one horizontally-scrolling tier and sits
/// above only the 10pt inset, which the system's vertical edge swipe leaves alone.
/// Only full-bleed takes the panel away. Every session opens on the Adjust tab.
struct PhotoEditorScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let asset: PHAsset
    /// Every photo opened together, when the editor was entered from a multi-photo
    /// selection. `asset` is whichever of them is on the canvas first. Empty (the
    /// single-photo case) means no filmstrip and no sync.
    var siblings: [PHAsset] = []
    let sourceAlbum: PHAssetCollection?
    /// The indexed row for this photo, when the presenter already has it. Only used
    /// to expand `{camera}`-style tokens in text overlays; everything else in the
    /// editor reads the original file.
    var metadata: PhotoMetadata?
    /// Called with the saved asset's local identifier as the editor closes after
    /// a successful save — Save Changes hands back this asset's own id, Save
    /// Copy the new copy's. The presenter uses it to put that photo on screen.
    var onSaved: ((String) -> Void)?

    @State private var controller: PhotoEditorController?
    @State private var session: EditorSession?

    /// Whether leaving now would throw work away — the photo on the canvas
    /// **or** any other photo in the run.
    ///
    /// `hasSessionChanges` only knows about the controller currently on
    /// screen, and Sync, Auto Sync, Paste Edits and Apply Previous all park
    /// drafts on photos that are not. A run where the live photo happened to
    /// net back to its baseline therefore dismissed without a word and took
    /// every parked draft with it.
    private var hasUnsavedWork: Bool {
        controller?.hasSessionChanges == true || (session?.draftCount ?? 0) > 0
    }
    @State private var chrome = EditorChromeModel()
    @State private var isSaveSheetPresented = false
    @State private var isDiscardConfirmationPresented = false
    @State private var isRevertConfirmationPresented = false
    @State private var isFallbackNoticePresented = false
    @State private var isRenamePresented = false
    @State private var renameText = ""
    /// Set while the text field opened on a layer that was created for it, so
    /// cancelling out of a caption that was never typed drops the empty layer rather
    /// than leaving an "Empty text" row behind.
    @State private var textEntryIsNew = false
    @State private var isFontPickerPresented = false
    @State private var isImagePickerPresented = false
    /// Up from the moment a photo is chosen for an image layer until it has been
    /// decoded, stored and placed — the decode/store is a visible beat and would
    /// otherwise read as the editor freezing.
    @State private var isImportingImage = false
    @State private var isSignatureLibraryPresented = false
    @State private var isSignatureNamePresented = false
    @State private var signatureName = ""
    @State private var drawSession = EditorDrawSession()
    /// Warming the neighbouring photos' sessions. Held so dismissing the
    /// editor stops it: `prewarmSession` allows network access, so it can
    /// still be waiting on iCloud when the screen goes, and finishing after
    /// `releaseCachedSessions()` would put a session back into a cache that
    /// no longer has an owner to release it.
    @State private var prewarmTask: Task<Void, Never>?

    /// Wide-screen sidebar: which side it is parked on, how wide, and whether
    /// it is collapsed. All three are the user's, so all three persist — but
    /// as scene-local state read from and written back to defaults, not as a
    /// live `@AppStorage` binding. A binding pushes every change to every
    /// observer, so on an iPad with two editor windows open, dragging one
    /// window's sidebar resized the other window's canvas mid-edit.
    @State private var sidebarEdgeRaw = UserDefaults.standard.string(
        forKey: SettingsKeys.editorSidebarEdge
    ) ?? EditorSidebarEdge.trailing.rawValue
    @State private var storedSidebarWidth = UserDefaults.standard.object(
        forKey: SettingsKeys.editorSidebarWidth
    ) as? Double ?? Double(EditorLayoutMetrics.sidebarDefaultWidth)
    @State private var isSidebarHidden = UserDefaults.standard.bool(
        forKey: SettingsKeys.editorSidebarHidden
    )
    /// Live width while the edge is being dragged; written back on release so a
    /// drag is one `UserDefaults` write rather than one per frame.
    @State private var sidebarDragWidth: CGFloat?
    /// Width the drag started from. `DragGesture` reports translation from the
    /// gesture's start, not from the last frame, so adding it to the live width
    /// every frame integrates the drag and the sidebar slams into its clamp
    /// after a few tens of points.
    @State private var sidebarDragStartWidth: CGFloat?
    @State private var batchSaver = EditorBatchSaver()
    /// Mirrors the saver's failure flag into view state. A `Binding` closure that
    /// reads an `@Observable` does not register a dependency, so an alert bound
    /// straight to the saver never appeared.
    @State private var showsBatchFailures = false
    @State private var isSaveLookPresented = false
    @State private var lookName = ""
    /// Ties the band's histogram pill to the floating card so expanding /
    /// collapsing animates as one object moving between the two.
    @Namespace private var histogramNamespace

    var body: some View {
        ZStack {
            EditorTheme.background.ignoresSafeArea()
            if let controller {
                editor(controller)
            } else {
                ProgressView("Opening original…")
                    .tint(.white)
                    .foregroundStyle(.white)
            }
            importingImageOverlay
            if let controller, controller.isEditingText {
                inlineTextEditor(controller)
            }
        }
        .background {
            if let controller {
                editorKeyboardShortcuts(controller)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .task {
            guard controller == nil else { return }
            if session == nil {
                let run = siblings.isEmpty ? [asset] : siblings
                let start = run.firstIndex { $0.localIdentifier == asset.localIdentifier } ?? 0
                session = EditorSession(assets: run, startIndex: start)
            }
            await openCurrentPhoto()
        }
        .onDisappear {
            prewarmTask?.cancel()
            controller?.close()
            // The cached sessions belong to this editor run: their temporary
            // directories have to go with it, or a long browse leaves three
            // photos' worth of files behind every time.
            dependencies.photoEditing.releaseCachedSessions()
        }
        .interactiveDismissDisabled(hasUnsavedWork)
        // An alert, not a confirmation dialog: on iOS 26 the dialog floats over the
        // photo with its cancel-role button hidden, so only the red Discard shows.
        .alert(
            "Revert to Original?",
            isPresented: $isRevertConfirmationPresented
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Revert", role: .destructive) {
                controller?.revertToOriginal { dismiss() }
            }
        } message: {
            Text("This throws away every edit saved to this photo, including edits made in Photos.")
        }
        .alert("Discard this editing session?", isPresented: $isDiscardConfirmationPresented) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
        .alert("Rename Mask", isPresented: $isRenamePresented) {
            TextField("Mask name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                controller?.renameSelectedMask(renameText)
            }
        }
        .alert(
            "Editor Error",
            isPresented: Binding(
                get: { controller?.errorMessage != nil },
                set: { if !$0 { controller?.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(controller?.errorMessage ?? "")
        }
        .alert("Saved as JPEG", isPresented: $isFallbackNoticePresented) {
            Button("OK") { dismiss() }
        } message: {
            Text("Photos doesn't support HEIC as the edited version of this photo, so ShotDex saved a maximum-quality JPEG instead.")
        }
        .sheet(isPresented: $isFontPickerPresented) {
            if let controller {
                EditorFontPickerSheet(
                    recents: dependencies.overlayFontRecents.recents,
                    current: currentFontChoice(controller)
                ) { choice in
                    controller.updateSelectedOverlay {
                        $0.fontPostScriptName = choice.postScriptName
                        $0.fontFamilyName = choice.familyName
                    }
                    // Remembered on the controller for the next layer, and in the
                    // store for the next photo.
                    controller.lastFont = choice
                    dependencies.overlayFontRecents.remember(choice)
                }
            }
        }
        .sheet(isPresented: $isImagePickerPresented) {
            if let controller {
                EditorSignatureImagePicker(
                    onPick: { data, assetIdentifier in
                        applyPickedImage(
                            data: data,
                            assetIdentifier: assetIdentifier,
                            controller: controller
                        )
                    },
                    onFailure: { isImportingImage = false },
                    onBegin: { isImportingImage = true }
                )
            }
        }
        .sheet(isPresented: $isSignatureLibraryPresented) {
            if let controller {
                EditorSignatureSheet(
                    presets: dependencies.signaturePresets.presets,
                    onApply: { controller.applySignature($0) },
                    onRename: { id, name in
                        dependencies.signaturePresets.rename(id: id, to: name)
                    },
                    onDelete: { dependencies.signaturePresets.delete(id: $0) }
                )
            }
        }
        .alert("Save Preset", isPresented: $isSignatureNamePresented) {
            TextField("Name", text: $signatureName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let controller { saveSignature(controller) }
            }
        } message: {
            Text("Saves every layer on this photo as a preset, so it can be stamped onto another one.")
        }
    }

    /// The on-photo text field. Selecting a text layer and typing happen here rather
    /// than in a sheet; Cancel on a layer that was just created and never typed drops
    /// it so the list is not left with an empty row.
    /// Keyboard for a desktop-shaped editor: a Magic Keyboard iPad running a
    /// Lightroom-style layout has to answer ⌘Z, ⌘S and Esc.
    ///
    /// Zero-size buttons in a background rather than modifiers on the visible
    /// controls, because two of these (Copy/Paste Edits) live inside a `Menu`,
    /// and a shortcut attached to a menu item only fires while that menu is open.
    private func editorKeyboardShortcuts(_ controller: PhotoEditorController) -> some View {
        ZStack {
            Button("Undo") { controller.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!controller.canUndo)
            Button("Redo") { controller.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!controller.canRedo)
            Button("Save") {
                controller.commitCropSession()
                isSaveSheetPresented = true
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(controller.isLoading || controller.isSaving)
            Button("Copy Edits") { dependencies.editClipboard.copy(from: controller.recipe) }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(controller.recipe.isIdentity)
            Button("Paste Edits") { controller.pasteEdits(from: dependencies.editClipboard) }
                .keyboardShortcut("v", modifiers: .command)
                .disabled(!dependencies.editClipboard.hasContent)
            Button("Fit or Fill") { chrome.requestFillZoomToggle() }
                .keyboardShortcut("0", modifiers: .command)
            Button("Hide or Show Tools") { setSidebarHidden(!isSidebarHidden) }
                .keyboardShortcut("\\", modifiers: .command)
            // Esc unwinds one level, it does not leave. With a mode up — Crop,
            // Mask, Markup, Presets — it backs out of the mode (and out of Crop
            // *without* applying the frame, like the rail's repeat tap); only
            // from plain Edit does it leave the editor. It was wired straight to
            // Back, so on a Magic Keyboard iPad the key that means "cancel this"
            // threw the whole session away from inside a crop.
            Button("Cancel") {
                if railMode != .edit {
                    withAnimation(EditorTheme.animation) {
                        selectGroup(
                            .light,
                            in: controller,
                            discardingCrop: railMode == .crop
                        )
                    }
                } else if hasUnsavedWork {
                    isDiscardConfirmationPresented = true
                } else {
                    dismiss()
                }
            }
            .keyboardShortcut(.cancelAction)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    // MARK: Multi-photo session

    /// Opens whichever photo the session points at, restoring the edit it was
    /// left with.
    private func openCurrentPhoto(replacing outgoing: PhotoEditorController? = nil) async {
        guard let session, let target = session.current else { return }
        let newController = PhotoEditorController(
            asset: target,
            sourceAlbum: sourceAlbum,
            // The metadata is this screen's *entry* photo only — it expands
            // `{camera}` tokens in text overlays, so handing it to a sibling
            // would stamp the wrong camera on it.
            service: dependencies.photoEditing,
            metadata: target.localIdentifier == asset.localIdentifier ? metadata : nil
        )
        // Every session opens on Adjust: the tab the user left last time is
        // rarely the one they want on a different photo.
        newController.selectedTool = .adjust
        controller = newController
        // Swapped out, so its original can go. After the assignment, not before:
        // closing first is what left the screen with no controller to render.
        outgoing?.close()
        await newController.load()
        // After load: `load()` reads the asset's own saved edit, and the draft
        // from this session is the newer of the two.
        if let draft = session.draft(for: target) {
            newController.apply(draft)
        }
        prewarmNeighbours(of: session)
    }

    /// Opens the sessions either side of the current photo in the background.
    /// A filmstrip walk goes next, next, back — and the back step used to pay
    /// a full `beginSession` (an iCloud round trip for anything not local)
    /// for a photo the editor had open a second earlier.
    private func prewarmNeighbours(of session: EditorSession) {
        let neighbours = [session.index - 1, session.index + 1]
            .filter { session.assets.indices.contains($0) }
            .map { session.assets[$0] }
        guard !neighbours.isEmpty else { return }
        prewarmTask?.cancel()
        prewarmTask = Task { @MainActor in
            for asset in neighbours {
                guard !Task.isCancelled else { return }
                await dependencies.photoEditing.prewarmSession(for: asset)
            }
        }
    }

    /// Switches the canvas to another photo in the run, parking the current
    /// edit in the session first so coming back restores it.
    private func selectPhoto(at index: Int) {
        guard let session, index != session.index, session.assets.indices.contains(index) else {
            return
        }
        let outgoing = controller
        if let outgoing, let current = session.current {
            outgoing.commitCropSession()
            session.store(outgoing.recipe, for: current)
        }
        session.moveToPhoto(at: index)
        // The outgoing controller is *not* dropped here. The body renders
        // `editor(controller)` only when the controller is non-nil, so nilling
        // it unmounted the band, the filmstrip the user had just tapped and the
        // panel — five frames of a walk were five full teardowns, for a wait
        // the prewarm had already made short. `openCurrentPhoto` swaps the new
        // controller in with one assignment and closes the old one after.
        Task { await openCurrentPhoto(replacing: outgoing) }
    }

    /// How many photos a Save All would write: every parked draft, plus the photo
    /// on the canvas when it has been touched.
    private var pendingSaveCount: Int {
        guard let session, session.isMultiPhoto else { return 0 }
        var count = session.draftCount
        if let controller, !controller.recipe.isIdentity, !session.hasDraft(session.assets[session.index]) {
            count += 1
        }
        return count
    }

    /// Writes every edited photo in the run. The photo on the canvas is parked
    /// into the session first so it goes through the same path as its siblings.
    private func saveWholeRun(
        _ controller: PhotoEditorController,
        format: PhotoOutputFormat,
        includeMetadata: Bool,
        savesCopy: Bool
    ) {
        guard let session, let current = session.current else { return }
        controller.commitCropSession()
        session.store(controller.recipe, for: current)

        let items: [(asset: PHAsset, recipe: PhotoEditRecipe)] = session.assets.compactMap { asset in
            guard let recipe = session.draft(for: asset) else { return nil }
            return (asset, recipe)
        }
        guard !items.isEmpty else { return }

        batchSaver.run(
            items: items,
            service: dependencies.photoEditing,
            libraryQueries: dependencies.libraryQueries,
            format: format,
            includeMetadata: includeMetadata,
            savesCopy: savesCopy,
            album: sourceAlbum,
            onSaved: { assetID in
                session.markSaved(assetID)
                onSaved?(assetID)
            },
            onFinished: {
                // Everything that could be written has been; what is left is the
                // failures, which keep their drafts so they can be retried.
                if session.draftCount == 0 { dismiss() }
            }
        )
    }

    private var batchSaveFailureMessage: String {
        let names = batchSaver.failures.prefix(3).map(\.filename).joined(separator: ", ")
        let extra = batchSaver.failures.count - min(batchSaver.failures.count, 3)
        let tail = extra > 0 ? " and \(extra) more" : ""
        let reason = batchSaver.failures.first?.message ?? ""
        return "\(names)\(tail). Their edits are still here — try saving them again.\n\n\(reason)"
    }

    /// After a save in a multi-photo run, move to the next photo that still has
    /// an edit waiting instead of closing the editor. Returns false when there is
    /// nothing left to go to — the single-photo case, and the end of a run — and
    /// the caller dismisses.
    ///
    /// Closing on the first save is what made the run pointless: sync a look to
    /// twenty frames, save one, and the other nineteen drafts went with the
    /// screen.
    private func advanceAfterSave() -> Bool {
        guard let session, session.isMultiPhoto else { return false }
        let order = session.assets.indices
        // Look forward from here first, then wrap: the run reads left to right.
        let forward = order.filter { $0 > session.index }
        let behind = order.filter { $0 < session.index }
        let next = (forward + behind).first { session.hasDraft(session.assets[$0]) }
        guard let next else { return false }
        selectPhoto(at: next)
        return true
    }

    /// Lightroom's Sync Settings: this photo's edit onto every other photo in
    /// the run. They are applied as drafts, so nothing is written until each
    /// photo is saved.
    private func syncEditsToAll(_ scope: EditorSyncScope) {
        guard let session, let controller, let current = session.current else { return }
        controller.commitCropSession()
        session.autoSyncScope = scope
        session.syncToAll(controller.recipe, from: current, scope: scope)
    }

    /// Applies the previous photo's edit to this one — Lightroom's `Previous`,
    /// the rhythm of a filmstrip: next frame, same treatment, tweak.
    private func applyPreviousEdit(_ controller: PhotoEditorController) {
        guard let recipe = session?.previousRecipe else { return }
        controller.apply(session?.autoSyncScope.apply(recipe, onto: controller.recipe) ?? recipe)
    }

    /// While Auto Sync is on, every committed change lands on the rest of the run.
    private func propagateIfAutoSyncing(_ controller: PhotoEditorController) {
        guard let session, session.isAutoSyncing, session.isMultiPhoto,
              let current = session.current
        else { return }
        session.syncToAll(controller.recipe, from: current, scope: session.autoSyncScope)
    }

    private func inlineTextEditor(_ controller: PhotoEditorController) -> some View {
        EditorInlineTextEditor(
            initialText: controller.selectedOverlay?.text ?? "",
            tokens: controller.overlayTokens,
            alignment: controller.selectedOverlay?.alignment ?? .center,
            onCommit: { text in
                controller.commitText(text)
                textEntryIsNew = false
            },
            onCancel: {
                let wasEmpty = (controller.selectedOverlay?.text ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                controller.endTextEntry()
                if textEntryIsNew, wasEmpty {
                    controller.deleteSelectedOverlay()
                }
                textEntryIsNew = false
            }
        )
        .transition(.opacity)
    }

    /// Opens the on-photo field. A brand-new caption first gets an empty text layer
    /// to type into; editing an existing one just opens the field on it.
    private func startTextEntry(_ controller: PhotoEditorController, isNew: Bool) {
        if isNew {
            controller.addTextOverlay()
        }
        textEntryIsNew = isNew
        controller.beginTextEntry()
    }

    @ViewBuilder
    private var importingImageOverlay: some View {
        if isImportingImage {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea()
                ProgressView("Adding image…")
                    .tint(.white)
                    .foregroundStyle(.white)
                    .padding(20)
                    .editorGlass(cornerRadius: AppTheme.Radius.lg)
            }
            .transition(.opacity)
        }
    }

    /// The face the font picker should show as current: the selected layer's, or the
    /// one a new layer would inherit when nothing is selected.
    private func currentFontChoice(_ controller: PhotoEditorController) -> OverlayFontChoice {
        guard let overlay = controller.selectedOverlay, overlay.kind == .text else {
            return controller.lastFont
        }
        guard !overlay.fontPostScriptName.isEmpty else { return .system }
        return OverlayFontChoice(
            postScriptName: overlay.fontPostScriptName,
            familyName: overlay.fontFamilyName,
            displayName: overlay.fontFamilyName.isEmpty
                ? overlay.fontPostScriptName
                : overlay.fontFamilyName
        )
    }

    /// A picked image becomes a file first: the recipe carries an identifier, never
    /// bytes, because it has to fit inside a photo's adjustment data.
    private func applyPickedImage(
        data: Data,
        assetIdentifier: String?,
        controller: PhotoEditorController
    ) {
        defer { isImportingImage = false }
        guard let id = try? dependencies.overlayImages.store(pngData: data) else {
            return
        }
        if controller.selectedOverlay?.kind == .image {
            controller.updateSelectedOverlay {
                $0.imageID = id
                $0.imageAssetIdentifier = assetIdentifier
            }
        } else {
            controller.addImageOverlay(imageID: id, assetIdentifier: assetIdentifier)
        }
    }

    private func saveSignature(_ controller: PhotoEditorController) {
        let name = signatureName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !controller.recipe.overlays.isEmpty else { return }
        dependencies.signaturePresets.upsert(
            SignaturePreset(
                name: name,
                createdAt: Date(),
                layers: controller.recipe.overlays
            )
        )
    }

    private func editor(_ controller: PhotoEditorController) -> some View {
        @Bindable var chrome = chrome
        return GeometryReader { proxy in
            // 30c: the panel is one fixed slab glued to the bottom, the photo above
            // it, and a band over the Dynamic Island carrying the histogram and the
            // clipping readout. The editor claims both safe areas so the photo gets
            // that height.
            let panelHeight = EditorLayoutMetrics.editorPanelHeight
            // The band must reach past the bottom of the Dynamic Island so a tall,
            // aspect-fit photo starts *below* it — the 48pt design height is short of
            // the ~59pt top safe area on Face-ID iPhones, which is what was slicing
            // the top of tall images. Grow it to the real inset when that is larger.
            let bandHeight = max(
                EditorLayoutMetrics.editorTopBandHeight,
                proxy.safeAreaInsets.top
            )
            // Width, height *and* orientation — see `usesSidebar`. A sidebar is
            // paid for in width, so it is only worth it on a window that has
            // width spare; a portrait iPad pays for it out of the photo.
            let isWide = EditorLayoutMetrics.usesSidebar(
                width: proxy.size.width,
                height: proxy.size.height
            )
            Group {
                if isWide {
                    wideBody(
                        controller,
                        // The editor claims the safe areas, so the bar has to
                        // carry the top one itself — `max` would tuck the
                        // Back/Save row under an iPad Split View's clock. 52 is
                        // the 44pt row with 4pt of air above and below it.
                        bandHeight: 52 + proxy.safeAreaInsets.top,
                        safeArea: proxy.safeAreaInsets,
                        canvasWidth: proxy.size.width,
                        canvasHeight: proxy.size.height
                    )
                } else {
                    narrowBody(
                        controller,
                        bandHeight: bandHeight,
                        panelHeight: panelHeight,
                        canvasHeight: proxy.size.height
                    )
                }
            }
            // Follows the window, not the device: a Split View that narrows past
            // the threshold puts the graph back on the photo, where the phone
            // layout needs it. `onChange`, not `task`: a task body runs a hop
            // later, so a live Stage Manager drag would spend a frame with the
            // stage on the other layout's rules.
            // Auto Sync rides the recipe itself rather than each mutator: every
            // change lands here once it has settled, whatever made it.
            .onChange(of: controller.recipe) { _, _ in
                propagateIfAutoSyncing(controller)
                // Belt to the context-menu braces: whatever cancelled a
                // hold-to-compare, a recipe write means the user is editing
                // again and the canvas has to show what they are editing. A
                // latched `showsOriginal` is otherwise invisible except as
                // "the sliders do nothing".
                if controller.showsOriginal { controller.showsOriginal = false }
            }
            .onChange(of: isWide, initial: true) { _, wide in
                chrome.isWideLayout = wide
                // Full bleed is a phone answer to a phone problem — no room. It
                // has no exit in the wide layout (the sidebar and the band both
                // hide for it), so a window dragged past the threshold while
                // full-bleed would strand the session with no Back and no Save.
                if wide { chrome.isFullBleed = false }
                // And a pinned reference goes with the pane that showed it. The
                // narrow layout never renders `referenceSplit`, and the only
                // control that clears the badge is inside `if let
                // toggleReference`, which is nil there — so a Duo folded with a
                // reference pinned kept a badge on one filmstrip frame that
                // nothing on screen could explain or remove.
                if !wide { session?.referenceIndex = nil }
            }
            .onChange(of: proxy.safeAreaInsets.top, initial: true) { _, top in
                windowTopInset = top
            }
            .ignoresSafeArea(.container, edges: [.top, .bottom])
            // The editor and its fixed panel never move for the keyboard: when the
            // on-photo text field opens, only that overlay reacts (its token bar
            // rides the keyboard). Without this the whole panel is shoved upward.
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .overlay(alignment: .bottom) {
            if let toast = chrome.undoToast {
                undoToastView(controller, toast: toast)
                    // Above the panel, not on it. Bottom-aligned with 24pt it
                    // sat at y 806–850 on a 402×874 phone and the group wheel
                    // sits at 795–849 — a complete overlap, and the toast has
                    // its own Undo button so it swallowed the taps rather than
                    // passing them through. It is raised on drags under 250ms,
                    // i.e. exactly the accidental flick, where the next move is
                    // usually "get out of this group". The letterbox above the
                    // panel is empty and hit-tests to nothing.
                    .padding(.bottom, undoToastBottomInset)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(EditorTheme.animation, value: chrome.isFullBleed)
        .animation(EditorTheme.animation, value: chrome.undoToast?.id)
        .overlay {
            if batchSaver.isRunning {
                EditorBatchSaveOverlay(saver: batchSaver)
            }
        }
        .onChange(of: batchSaver.hasFinishedWithFailures) { _, hasFailures in
            showsBatchFailures = hasFailures
        }
        .alert("Save Look", isPresented: $isSaveLookPresented) {
            TextField("Name", text: $lookName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                dependencies.lookPresets.save(controller.recipe, name: lookName)
            }
            // A blank name is refused by the store, and the alert used to
            // close as though it had saved — no chip, no reason.
            .disabled(lookName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Saves the tone, colour, curve and film look on this photo. The crop, masks and markup stay with the photo.")
        }
        .alert("Some Photos Didn't Save", isPresented: $showsBatchFailures) {
            Button("OK") { batchSaver.clearFailures() }
        } message: {
            Text(batchSaveFailureMessage)
        }
        .sheet(isPresented: $isSaveSheetPresented) {
            PhotoEditorSaveSheet(
                controller: controller,
                pendingCount: pendingSaveCount,
                saveAll: { format, includeMetadata, savesCopy in
                    isSaveSheetPresented = false
                    saveWholeRun(
                        controller,
                        format: format,
                        includeMetadata: includeMetadata,
                        savesCopy: savesCopy
                    )
                }
            ) {
                isSaveSheetPresented = false
                // Announced here, once, not in the fallback alert's OK button:
                // the JPEG fallback still saved an asset worth revealing.
                if let savedAssetID = controller.savedAssetID {
                    session?.markSaved(savedAssetID)
                    onSaved?(savedAssetID)
                }
                if controller.didFallbackToJPEG {
                    isFallbackNoticePresented = true
                } else if !advanceAfterSave() {
                    dismiss()
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $chrome.isNewMaskSheetPresented) {
            EditorNewMaskSheet(
                previewImage: controller.previewImage,
                hasDepth: controller.hasDepthSource,
                hasFaces: controller.hasFaces
            ) { option in
                controller.addMask(option: option)
                controller.editSelectedMaskAdjustments()
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $chrome.isMaskPickerPresented) {
            EditorMaskPickerSheet(
                masks: controller.recipe.masks,
                selectedID: controller.selectedMaskID,
                thumbnails: controller.maskThumbnails
            ) { id in
                controller.selectMask(id)
                controller.editSelectedMaskAdjustments()
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $chrome.isHistorySheetPresented) {
            EditorHistorySheet(controller: controller)
                .presentationDetents([.medium, .large])
        }
        .alert(
            "Enter value",
            isPresented: Binding(
                get: { chrome.numericEntryKind != nil },
                set: { if !$0 { chrome.numericEntryKind = nil } }
            )
        ) {
            TextField("Value", text: $chrome.numericEntryText)
                .keyboardType(.numbersAndPunctuation)
            Button("Cancel", role: .cancel) { chrome.numericEntryKind = nil }
            Button("Set") {
                guard let kind = chrome.numericEntryKind,
                      let value = EditorAdjustmentCatalog.value(
                          fromDisplayText: chrome.numericEntryText,
                          of: kind
                      )
                else { return }
                controller.setAdjustment(kind, value: value)
                chrome.numericEntryKind = nil
            }
        } message: {
            if let kind = chrome.numericEntryKind {
                Text(kind.displayName)
            }
        }
    }

    // MARK: Layouts

    /// Phone layout: band on top, photo, one fixed slab of tools glued to the
    /// bottom.
    private func narrowBody(
        _ controller: PhotoEditorController,
        bandHeight: CGFloat,
        panelHeight: CGFloat,
        canvasHeight: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            // Drawing is a full takeover, like Crop: the band steps aside and a
            // Clear / Done bar takes the top, clear of the tool picker below.
            if controller.isEditingDrawing {
                drawTopBar(controller)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if !chrome.isFullBleed {
                commandBand(controller, height: bandHeight)
                    .transition(.opacity)
            }

            imageStage(controller)

            filmstrip(controller, canvasHeight: canvasHeight)

            // No bottom panel while drawing: the tool picker owns that space and
            // Clear / Done live in the top bar.
            if !chrome.isFullBleed, !controller.isEditingDrawing {
                panel(controller, height: panelHeight)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    /// Wide layout (iPad, the Duo's inner display, a wide window): Lightroom on a
    /// desktop. The tools stand beside the photo as a sidebar of collapsible
    /// groups instead of a slab under it, which is the only way a landscape photo
    /// gets height — a 246pt panel takes a third of an iPad's short side. Back
    /// and Save move up into the band so they stay reachable with the sidebar
    /// collapsed.
    private func wideBody(
        _ controller: PhotoEditorController,
        bandHeight: CGFloat,
        safeArea: EdgeInsets,
        canvasWidth: CGFloat,
        canvasHeight: CGFloat
    ) -> some View {
        // Drawing keeps the panel and the rail on a wide window: there is room
        // beside the photo for Clear and Done, and a bar floating over the
        // picture while a stroke is being drawn covers the one thing being
        // worked on. The phone, with no panel to put them in, still floats them.
        let showsPanel = !isSidebarHidden
        let showsRail = true
        // A window too short to hold a parameter group in the panel. The panel
        // gives up its histogram and its Look row there; the band takes the
        // histogram back as its pill.
        let isShortColumn = canvasHeight < EditorLayoutMetrics.sidebarShortColumnHeight
        // How much of the window the chrome on the tool side takes, for the
        // reference split's arithmetic.
        let toolsWidth = (showsPanel ? sidebarWidth(in: canvasWidth) : 0)
            + (showsRail ? EditorLayoutMetrics.sidebarRailWidth : 0)
        return VStack(spacing: 0) {
            // One toolbar across the whole window, the way every tablet editor
            // draws it: Back on the leading edge, the document commands on the
            // trailing one. It used to appear only when the tools were away, on
            // the grounds that a second strip of chrome costs the photo 56pt —
            // but the panel was then paying for the same controls twice over,
            // in a title row and a command row it could not scroll, which is
            // 88pt of the dimension the parameter list is actually short of.
            commandBand(
                    controller,
                    height: bandHeight,
                    showsDocumentControls: true,
                    // The panel carries the histogram whenever it is up — on a
                    // short column too, at 56pt. The pill only comes back when
                    // there is no panel to hold it.
                    showsHistogram: !showsPanel,
                    // Save lives in the band on a wide window whether the panel
                    // is up or not: the panel's foot is gone, and a document
                    // command belongs with the document commands.
                    showsSave: true,
                    // The commands belong over the tools they act on. With the
                    // panel on the leading edge that is the leading edge: an
                    // undo disc 800pt away from the slider the hand is holding
                    // is the measured cost of not mirroring this.
                    mirrored: sidebarEdge == .leading,
                    topInset: safeArea.top + AppTheme.Spacing.xs
                )
                .transition(.opacity)

            HStack(spacing: 0) {
                if sidebarEdge == .leading {
                    if showsRail { toolRail(controller, safeArea: safeArea) }
                    if showsPanel {
                        sidebarColumn(
                            controller,
                            safeArea: safeArea,
                            canvasWidth: canvasWidth,
                            canvasHeight: canvasHeight,
                            isShortColumn: isShortColumn
                        )
                        .transition(.move(edge: .leading))
                        resizeHandle(canvasWidth: canvasWidth)
                    }
                }

                VStack(spacing: 0) {
                    if let reference = session?.referenceAsset, !chrome.isFullBleed,
                       !controller.isEditingDrawing {
                        referenceSplit(
                            controller,
                            reference: reference,
                            canvas: CGSize(
                                width: canvasWidth - toolsWidth,
                                height: canvasHeight
                            )
                        )
                        .transition(.opacity)
                    } else {
                        imageStage(controller)
                    }

                    filmstrip(controller, canvasHeight: canvasHeight)
                }

                if sidebarEdge == .trailing {
                    if showsPanel {
                        resizeHandle(canvasWidth: canvasWidth)
                        sidebarColumn(
                            controller,
                            safeArea: safeArea,
                            canvasWidth: canvasWidth,
                            canvasHeight: canvasHeight,
                            isShortColumn: isShortColumn
                        )
                        .transition(.move(edge: .trailing))
                    }
                    if showsRail { toolRail(controller, safeArea: safeArea) }
                }
            }
        }
        .animation(EditorTheme.animation, value: showsPanel)
        .animation(EditorTheme.animation, value: sidebarEdge)
    }

    /// The canvas cut in two, the way round that leaves both frames biggest.
    @ViewBuilder
    private func referenceSplit(
        _ controller: PhotoEditorController,
        reference: PHAsset,
        canvas: CGSize
    ) -> some View {
        let axis = EditorLayoutMetrics.referenceSplit(
            canvas: canvas,
            aspectRatio: controller.previewAspectRatio
        )
        let pane = EditorReferencePane(
            asset: reference,
            photoLibrary: dependencies.photoLibrary,
            zoomScale: chrome.zoomScale,
            zoomOffset: chrome.zoomOffset,
            isLocked: session?.isReferenceLocked ?? true,
            toggleLock: { session?.isReferenceLocked.toggle() }
        ) {
            withAnimation(EditorTheme.animation) {
                session?.referenceIndex = nil
            }
        }
        let divider = Rectangle().fill(EditorTheme.panelTopHairline)

        if axis == .horizontal {
            HStack(spacing: 0) {
                pane
                divider.frame(width: 1)
                imageStage(controller)
            }
        } else {
            VStack(spacing: 0) {
                pane
                divider.frame(height: 1)
                imageStage(controller)
            }
        }
    }

    /// The run of photos under the canvas. Nothing at all for a single photo, and
    /// nothing while a tool has taken the screen over (drawing, full bleed) —
    /// switching photos mid-stroke is not something anyone means to do.
    @ViewBuilder
    private func filmstrip(
        _ controller: PhotoEditorController,
        canvasHeight: CGFloat
    ) -> some View {
        if let session, session.isMultiPhoto, !chrome.isFullBleed, !controller.isEditingDrawing {
            EditorFilmstrip(
                session: session,
                photoLibrary: dependencies.photoLibrary,
                currentHasEdits: !controller.recipe.isIdentity,
                toggleReference: chrome.isWideLayout
                    ? { index in
                        withAnimation(EditorTheme.animation) {
                            session.toggleReference(at: index)
                        }
                    }
                    : nil,
                // Height, not layout. Tying this to `isWideLayout` gave the
                // Duo's 644pt cover the phone's 124pt strip — a constant sized
                // for an iPhone 17's 874 — which left the stage 226pt, 35% of
                // the screen. The compact pair returns 52 of those.
                isCompact: canvasHeight < EditorLayoutMetrics.sidebarShortColumnHeight
            ) { index in
                selectPhoto(at: index)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// The photo itself, with the floating histogram card over it. Shared by both
    /// layouts — only the chrome around it differs.
    private func imageStage(_ controller: PhotoEditorController) -> some View {
        stageContent(controller)
            // A secondary click on the photo reaches the same commands as the ⋯
            // button. Pointer users expect the canvas itself to answer; without
            // it a trackpad right-click on an iPad does nothing anywhere in the
            // editor.
            //
            // Regular width only. On a touch phone `UIContextMenuInteraction`
            // claims the same press at ~0.5s that `holdBeforeGesture` claimed at
            // 0.3s, so the sequenced drag's `onEnded` never runs and
            // `showsOriginal` latches on for the rest of the session — measured:
            // one 1.2s press leaves the before/after disc accent-filled two
            // screens later, and every slider after that moves nothing visible.
            // The ⋯ menu carries all five commands anyway.
            .contextMenu { stageContextMenu(controller) }
            // Undo, within reach of the hand that is on the sliders. Compact
            // width only: the wide layout's undo disc is already over the
            // tools, and a two-finger tap there would fight the trackpad.
            .background {
                if horizontalSizeClass == .compact {
                    EditorTwoFingerTapCatcher {
                        guard controller.canUndo else { return }
                        controller.undo()
                    }
                }
            }
    }

    /// The stage's secondary-click menu — the same commands as ⋯, where a
    /// pointer user expects to find them.
    ///
    /// **Regular width only, and that is the fix for a measured bug.** On a
    /// touch phone `UIContextMenuInteraction` claims the same press at ~0.5s
    /// that `holdBeforeGesture` claimed at 0.3s, so the sequenced drag's
    /// `onEnded` never runs and `controller.showsOriginal` latches on for the
    /// rest of the session: one 1.2s press leaves the before/after disc
    /// accent-filled two screens later and every slider after it moves nothing
    /// visible. Emitting no items leaves the long press to the compare gesture,
    /// which is what the phone wants anyway — the ⋯ menu already carries all
    /// five commands, and `holdBeforeGesture` is the only thing on a phone that
    /// wants a long press on the photo.
    @ViewBuilder
    private func stageContextMenu(_ controller: PhotoEditorController) -> some View {
        if horizontalSizeClass == .regular {
            Button {
                dependencies.editClipboard.copy(from: controller.recipe)
            } label: {
                Label("Copy Edits", systemImage: "doc.on.doc")
            }
            .disabled(controller.recipe.isIdentity)
            Button {
                controller.pasteEdits(from: dependencies.editClipboard)
            } label: {
                Label("Paste Edits", systemImage: "doc.on.clipboard")
            }
            .disabled(!dependencies.editClipboard.hasContent)
            Divider()
            Button {
                controller.reset()
            } label: {
                Label("Reset All", systemImage: "arrow.counterclockwise")
            }
            .disabled(controller.recipe.isIdentity)
            Button {
                showHistory()
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
        }
    }

    private func stageContent(_ controller: PhotoEditorController) -> some View {
        // The only thing allowed over the image is the histogram card, and only
        // when the user taps the band mini open — every other control lives in
        // the tools. It parks back to the mini on tap / close. (The curve graph
        // is the one exception, and it is drawn by the stage itself; the card
        // stays parked while it is up.)
        EditorImageStage(
            controller: controller,
            chrome: chrome,
            drawSession: drawSession
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            GeometryReader { proxy in
                if !chrome.isHistogramCollapsed, chrome.selectedGroup != .curve {
                    EditorHistogramCard(
                        histogram: controller.histogram,
                        chrome: chrome,
                        bounds: CGRect(origin: .zero, size: proxy.size),
                        namespace: histogramNamespace
                    )
                    .transition(.identity)
                }
            }
        }
    }

    // MARK: Wide-screen sidebar

    /// Where the undo toast parks: clear of whatever chrome owns the bottom.
    private var undoToastBottomInset: CGFloat {
        if chrome.isFullBleed { return 40 }
        if chrome.isWideLayout { return AppTheme.Spacing.xxl }
        return EditorLayoutMetrics.editorPanelHeight + AppTheme.Spacing.md
    }

    /// Whether the photo is currently filling the canvas rather than fitted into
    /// it. Read from the zoom the fill sets, with a margin for float error — a
    /// hand-pinched zoom reads as filled too, which is what the fit button should
    /// undo anyway.
    private var isFillingCanvas: Bool { chrome.zoomScale > 1.02 }

    /// Whether the *window* has a Dynamic Island / notch worth routing the band
    /// around, read from the safe area rather than from the idiom.
    ///
    /// A cutout is what pushes the top inset past a plain status bar's 24pt, so
    /// that is the test. The idiom is not: the iPhone Duo reports `.phone` on
    /// both displays and its cover has a 24pt inset and no cutout there, so the
    /// band reserved `editorHistogramPillLeading(bandWidth: 382)` − 20 − 112 =
    /// **125pt of `Color.clear`** — a third of a 382pt band — for a cutout that
    /// is not at that x, leaving the histogram pill about 37pt wide.
    @State private var windowTopInset: CGFloat = 0

    private var hasTopCutout: Bool { windowTopInset > 24 }

    /// Collapsed or not, persisted for the next window rather than pushed
    /// into the one already open.
    private func setSidebarHidden(_ hidden: Bool) {
        isSidebarHidden = hidden
        UserDefaults.standard.set(hidden, forKey: SettingsKeys.editorSidebarHidden)
    }

    private var sidebarEdge: EditorSidebarEdge {
        EditorSidebarEdge.resolved(sidebarEdgeRaw)
    }

    private func sidebarWidth(in canvasWidth: CGFloat) -> CGFloat {
        clampedSidebarWidth(sidebarDragWidth ?? CGFloat(storedSidebarWidth), in: canvasWidth)
    }

    /// Inside the scale, and never more than a cramped window can spare: a stored
    /// 420 in a 700pt Stage Manager window would leave the photo 270pt, narrower
    /// than the tools beside it.
    private func clampedSidebarWidth(_ width: CGFloat, in canvasWidth: CGFloat) -> CGFloat {
        let range = EditorLayoutMetrics.sidebarWidthRange
        let ceiling = max(range.lowerBound, min(range.upperBound, canvasWidth * 0.45))
        return min(max(width, range.lowerBound), ceiling)
    }

    private func resizeHandle(canvasWidth: CGFloat) -> some View {
        EditorSidebarResizeHandle(edge: sidebarEdge) { delta in
            let base = sidebarDragStartWidth ?? sidebarWidth(in: canvasWidth)
            sidebarDragStartWidth = base
            sidebarDragWidth = clampedSidebarWidth(base + delta, in: canvasWidth)
        } onEnd: {
            if let width = sidebarDragWidth {
                storedSidebarWidth = Double(width)
                UserDefaults.standard.set(storedSidebarWidth, forKey: SettingsKeys.editorSidebarWidth)
            }
            sidebarDragWidth = nil
            sidebarDragStartWidth = nil
        }
    }

    private func sidebarColumn(
        _ controller: PhotoEditorController,
        safeArea: EdgeInsets,
        canvasWidth: CGFloat,
        canvasHeight: CGFloat,
        isShortColumn: Bool
    ) -> some View {
        VStack(spacing: 0) {
            // The histogram is the first thing in the panel and it never leaves,
            // the way every desktop raw editor has it: it is read continuously
            // while the sliders move, so parking it behind a tap (the phone's
            // band mini) would be one tap per glance. Lightroom floats it over
            // the photo instead; this stays put, because a graph that moves is
            // a graph that has to be found again.
            //
            // A short column keeps it too and pays by shrinking it to the graph
            // band alone: 56pt instead of 92. Handing it back to the command
            // band — which is what this used to do — cost a tap per glance on
            // the one device where the glance matters most.
            EditorHistogramSparkline(histogram: controller.histogram)
                .padding(isShortColumn ? AppTheme.Spacing.xs : AppTheme.Spacing.sm)
                .frame(
                    height: EditorLayoutMetrics.sidebarHistogramHeight(
                        forColumnHeight: canvasHeight
                    )
                )
                .background(
                    EditorTheme.control,
                    in: RoundedRectangle.app(AppTheme.Radius.lg)
                )
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.top, AppTheme.Spacing.md)
                .padding(.bottom, AppTheme.Spacing.sm)
                .accessibilityElement()
                .accessibilityLabel("RGB histogram")
                .accessibilityValue(histogramClippingSummary(controller))

            sidebarModeHeader(controller)

            ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    if chrome.showsHistoryPanel {
                        EditorHistoryPanel(controller: controller)
                    } else if railMode == .edit {
                        ForEach(Self.sidebarParameterGroups) { group in
                            EditorSidebarSection(
                                group: group,
                                isExpanded: chrome.expandedSidebarGroups.contains(group),
                                isActive: chrome.expandedSidebarGroups.contains(group),
                                hasEdits: groupHasEdits(group, controller: controller),
                                spacing: EditorLayoutMetrics.sidebarCardSpacing(
                                    forColumnHeight: canvasHeight
                                ),
                                toggle: { toggleSidebarSection(group, in: controller) },
                                reset: { resetSection(group, in: controller) }
                            ) {
                                sidebarSectionBody(group, controller: controller)
                            }
                            .id(group)
                        }
                    } else {
                        // A stage tool takes the panel over rather than sitting
                        // on top of the adjustment stack: the rail already says
                        // which mode the editor is in, and the eight headers
                        // underneath were a list of things this tool is not.
                        if controller.isEditingDrawing {
                            sidebarDrawControls(controller)
                        } else {
                            sidebarSectionBody(railMode.group, controller: controller)
                                .padding(.top, AppTheme.Spacing.sm)
                        }

                        // Mask with nothing masked yet shows the five sections
                        // greyed under the empty state. It answers the question
                        // the empty panel raises — *adjust what, exactly?* —
                        // without a sentence, and it is why the `+` above is the
                        // only live control on the panel.
                        if railMode == .mask, controller.recipe.masks.isEmpty {
                            ForEach(Self.sidebarParameterGroups) { group in
                                EditorSidebarSection(
                                    group: group,
                                    isExpanded: false,
                                    isActive: false,
                                    spacing: EditorLayoutMetrics.sidebarCardSpacing(
                                        forColumnHeight: canvasHeight
                                    ),
                                    toggle: {}
                                ) {
                                    EmptyView()
                                }
                            }
                            .opacity(EditorTheme.rowDisabled)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                        }
                    }
                    Color.clear.frame(height: AppTheme.Spacing.xxl)
                }
            }
            // One switch for the whole stack: no panel inside the sidebar owns a
            // vertical scroll, so every section is exactly as tall as its content
            // and this scroll takes the overflow.
            .environment(\.editorPanelScrolls, false)
            // Same rule as the phone panel: a finger that owns a slider must not
            // also be scrolling the list under it.
            .scrollDisabled(chrome.activeSlider != nil)
            .onChange(of: chrome.sectionToScrollTo) { _, group in
                guard let group else { return }
                withAnimation(EditorTheme.animation) {
                    proxy.scrollTo(group, anchor: .top)
                }
                chrome.sectionToScrollTo = nil
            }
            }

            // Only the three stage modes have a foot. Edit and Presets end with
            // the list, and Save lives in the command band with the rest of the
            // document commands.
            if Self.stageModes.contains(railMode), !chrome.showsHistoryPanel {
                Rectangle().fill(EditorTheme.panelDivider).frame(height: 1)
                sidebarCommitBar(controller, safeArea: safeArea)
            } else {
                Color.clear.frame(height: safeArea.bottom)
            }
        }
        // Every slider in the panel puts its track on its own line. The switch
        // is here rather than at each call site so the mask, grade, curve and
        // markup panels get it without knowing they are in a sidebar.
        .environment(\.editorSliderStacked, true)
        .environment(\.editorUsesPanelStyle, true)
        // And no panel draws its own title: the mode header two rows up already
        // says "MASK", and the panel repeating it in a larger font 40pt below
        // was the same name twice.
        .environment(\.editorPanelShowsTitle, false)
        .frame(width: sidebarWidth(in: canvasWidth))
        .background(EditorTheme.panelSolid)
    }

    /// History goes to the panel on a window that has one and to a sheet on one
    /// that does not — the stage menu, the ⋯ menu and the rail all come here so
    /// there is one answer to that question.
    private func showHistory() {
        guard chrome.isWideLayout else {
            chrome.isHistorySheetPresented = true
            return
        }
        withAnimation(EditorTheme.animation) {
            chrome.showsHistoryPanel = true
            if isSidebarHidden { setSidebarHidden(false) }
        }
    }

    /// Which rail stop the panel is showing, derived from the selected group so
    /// there is one source of truth — a mask opened from the photo's own context
    /// menu moves the rail too.
    private var railMode: EditorRailMode {
        EditorRailMode.containing(chrome.selectedGroup)
    }

    private func toolRail(
        _ controller: PhotoEditorController,
        safeArea: EdgeInsets
    ) -> some View {
        EditorToolRail(
            selected: railMode,
            editedModes: Set(
                EditorRailMode.allCases.filter {
                    $0 != .edit && groupHasEdits($0.group, controller: controller)
                }
            ),
            isPanelHidden: isSidebarHidden,
            isHistoryActive: chrome.showsHistoryPanel,
            edge: sidebarEdge,
            select: { mode in
                withAnimation(EditorTheme.animation) {
                    // Tapping the open mode folds the panel away and leaves the
                    // rail — Lightroom's own toggle, and the only way to get the
                    // photo the whole window now that there is no Hide Tools
                    // button. Tapping it again brings the same mode back.
                    let isRepeat = mode == railMode && !chrome.showsHistoryPanel
                    if isRepeat, !isSidebarHidden {
                        setSidebarHidden(true)
                        return
                    }
                    chrome.showsHistoryPanel = false
                    if isSidebarHidden { setSidebarHidden(false) }
                    guard mode != railMode else { return }
                    selectGroup(mode.group, in: controller)
                }
            },
            showHistory: {
                // The rail stop toggles, the way the five mode stops above it do.
                if chrome.showsHistoryPanel {
                    withAnimation(EditorTheme.animation) { chrome.showsHistoryPanel = false }
                } else {
                    showHistory()
                }
            }
        )
        .padding(.bottom, safeArea.bottom)
    }

    /// The panel's own title line: what it is showing, and Auto — Lightroom's
    /// one-press tone pass, which lived in the ⋯ menu and so was never found.
    private func sidebarModeHeader(_ controller: PhotoEditorController) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text((chrome.showsHistoryPanel ? "History" : railMode.title).uppercased())
                .font(EditorTheme.groupLabel)
                .tracking(1.1)
                .foregroundStyle(EditorTheme.secondaryText)
            Spacer(minLength: 8)
            if chrome.showsHistoryPanel {
                Button {
                    withAnimation(EditorTheme.animation) { chrome.showsHistoryPanel = false }
                } label: {
                    Text("Done")
                        .font(EditorTheme.pillLabel)
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .frame(height: AppTheme.Size.pillHeightDark)
                        .background(EditorTheme.control, in: Capsule())
                        .overlay { Capsule().strokeBorder(EditorTheme.hairline, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
        }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(height: EditorLayoutMetrics.sidebarModeHeaderHeight)
    }

    /// The film look the photo is on, and the way to another one — Lightroom's
    /// Profile / Browse row. It is the first decision of an edit and the one
    /// thing the adjustment stack cannot show, because a look is not a slider.
    private func sidebarLookRow(_ controller: PhotoEditorController) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Look")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                Text(controller.recipe.filter.displayName)
                    .font(.system(size: 11))
                    .foregroundStyle(EditorTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                withAnimation(EditorTheme.animation) {
                    selectGroup(.presets, in: controller)
                }
            } label: {
                Text("Browse")
                    .font(EditorTheme.pillLabel)
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .frame(height: AppTheme.Size.pillHeightDark)
                    .background(EditorTheme.control, in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(EditorTheme.hairline, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .accessibilityLabel("Browse Looks")
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(height: EditorLayoutMetrics.sidebarLookRowHeight)
    }

    /// The panel's foot: Reset on the leading edge, Save filling the rest.
    /// Lightroom parks its reset in exactly this corner; Save has no Lightroom
    /// counterpart because Lightroom has nothing to save to.
    /// The foot of a stage mode: undo this mode's work, drop it, or keep it.
    /// Only Crop & Geometry, Mask and Markup have one — they are the modes that
    /// build something on the photo, and a thing being built needs a way out
    /// that is not "undo enough times". Edit and Presets have no foot at all,
    /// which is 74pt the parameter list keeps.
    ///
    /// Told apart by colour, not by size: Apply is an accent pill only as wide
    /// as its word, Cancel is bare text, ↺ is a 32pt disc at the far end.
    private func sidebarCommitBar(
        _ controller: PhotoEditorController,
        safeArea: EdgeInsets
    ) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Button {
                resetStageMode(controller)
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(EditorTheme.commandGlyph)
                    .foregroundStyle(stageModeHasWork(controller) ? .white : EditorTheme.dimText)
                    .frame(
                        width: EditorLayoutMetrics.editorPrimaryButtonHeight,
                        height: EditorLayoutMetrics.editorPrimaryButtonHeight
                    )
                    .background(EditorTheme.control, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!stageModeHasWork(controller))
            .hoverEffect(.highlight)
            .accessibilityLabel("Reset \(railMode.title)")

            Spacer(minLength: 8)

            Button {
                cancelStageMode(controller)
            } label: {
                Text("Cancel")
                    .font(EditorTheme.pillLabel)
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(height: EditorLayoutMetrics.editorPrimaryButtonHeight)
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)

            Button {
                applyStageMode(controller)
            } label: {
                Text("Apply")
                    .font(EditorTheme.pillLabel)
                    .foregroundStyle(.black)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .frame(height: EditorLayoutMetrics.editorPrimaryButtonHeight)
                    .frame(maxWidth: EditorLayoutMetrics.editorPrimaryButtonMaxWidth)
                    .background(EditorTheme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .frame(height: EditorLayoutMetrics.sidebarCommitBarHeight)
        .padding(.bottom, safeArea.bottom)
        .background(EditorTheme.panelSolid)
    }

    /// Whether the mode on screen has anything to put back.
    private func stageModeHasWork(_ controller: PhotoEditorController) -> Bool {
        groupHasEdits(railMode.group, controller: controller)
    }

    /// ↺ in the commit bar: this mode's own reset, one history step.
    private func resetStageMode(_ controller: PhotoEditorController) {
        switch railMode {
        case .crop: controller.resetCrop()
        case .heal: controller.removeAllHealingSpots()
        case .mask: controller.removeAllMasks()
        case .markup: controller.removeAllOverlays()
        default: break
        }
    }

    /// Cancel: leave the mode having kept nothing it built.
    private func cancelStageMode(_ controller: PhotoEditorController) {
        withAnimation(EditorTheme.animation) {
            switch railMode {
            case .crop:
                controller.cancelCropSession()
            case .heal, .mask, .markup:
                controller.restoreStageEntry()
            default:
                break
            }
            selectGroup(EditorRailMode.edit.group, in: controller)
        }
    }

    /// Apply: keep it and go back to adjusting.
    private func applyStageMode(_ controller: PhotoEditorController) {
        withAnimation(EditorTheme.animation) {
            if railMode == .crop { controller.commitCropSession() }
            controller.clearStageEntry()
            selectGroup(EditorRailMode.edit.group, in: controller)
        }
    }

    /// The parameter panels, in pipeline order — the order Lightroom's develop
    /// panels run in, which is also the order an edit is actually made in.
    ///
    /// Six, not fourteen. The four stage-owning tools moved to the strip above
    /// (they are mutually exclusive, so a disclosure triangle promising "open as
    /// many as you like" was lying about them), Mix and Point became segments
    /// inside Color, and Optics and Geo have no parameters to show yet — a
    /// permanent "coming soon" row is unshipped UI, not an empty state. Fourteen
    /// headers plus dividers came to more than the sidebar is tall: the list did
    /// not fit even with everything closed. Optics and Geo came back once they
    /// had controls to show — Geo now carries Upright, which is the reason to
    /// open it.
    /// The four modes that build something on the photo, and so have a commit
    /// bar: a frame, a set of healing spots, a set of masks, a stack of markup
    /// layers.
    private static let stageModes: [EditorRailMode] = [.crop, .heal, .mask, .markup]

    /// The five sections the panel lists, in the catalog's order. Curve rides
    /// inside Light, Mix / Point / Grade are tabs inside Color, and Geometry
    /// went to Crop with the frame it shapes.
    private static let sidebarParameterGroups: [EditorGroup] = [
        .light, .color, .effects, .detail, .optics
    ]

    /// The three ways to work on colour, shown as segments inside one section
    /// the way Lightroom nests HSL under Color.
    private static let colorSegments: [EditorGroup] = [.color, .colorMix, .pointColor, .grade]

    /// What the histogram says out loud. The shape is not describable; what a
    /// photographer reads it for is whether the ends are against the wall.
    private func histogramClippingSummary(_ controller: PhotoEditorController) -> String {
        let histogram = controller.histogram
        switch (histogram.hasClippedShadows, histogram.hasClippedHighlights) {
        case (true, true): return "Shadows and highlights clipped"
        case (true, false): return "Shadows clipped"
        case (false, true): return "Highlights clipped"
        case (false, false): return "No clipping"
        }
    }

    /// Whether this group holds anything on this photo, for the header's dot.
    /// Compared against an untouched recipe rather than tracked separately, so
    /// undo and Reset All put the dots back on their own.
    /// Puts one section back to its defaults, in one history step — the ↺ on a
    /// card's header. It is deliberately narrower than the old Reset All at the
    /// foot of the panel: that button sat under whatever the person was working
    /// on and undid all of it, and its name did not say so.
    private func resetSection(_ group: EditorGroup, in controller: PhotoEditorController) {
        switch group {
        case .light, .effects, .detail, .optics:
            let kinds = catalogGroups(for: group, controller: controller).flatMap(\.kinds)
            controller.resetAdjustments(kinds)
        case .geo:
            let kinds = catalogGroups(for: .geo, controller: controller).flatMap(\.kinds)
            controller.resetAdjustments(kinds)
            controller.resetUpright()
        case .curve:
            controller.resetAllCurves()
        case .color, .colorMix, .pointColor:
            // Colour is one recipe: basic, mixer and point colour all live in
            // it, and the section shows all three.
            controller.resetColor()
        case .grade:
            for region in ColorGradingRegion.allCases {
                controller.resetColorGrading(region: region)
            }
        case .cropGeometry:
            controller.resetCrop()
        case .heal, .mask, .markup, .presets:
            // These are stage modes with their own commit bar; their reset lives
            // there, next to Cancel and Apply.
            break
        }
    }

    private func groupHasEdits(_ group: EditorGroup, controller: PhotoEditorController) -> Bool {
        let recipe = controller.recipe
        let identity = PhotoEditRecipe.identity
        switch group {
        case .light, .detail, .effects, .optics, .geo:
            return catalogGroups(for: group, controller: controller).contains { catalogGroup in
                catalogGroup.kinds.contains { recipe.adjustments[$0] != identity.adjustments[$0] }
            }
        case .curve:
            return recipe.curve != identity.curve
        case .color:
            let basic = catalogGroups(for: .color, controller: controller).contains { catalogGroup in
                catalogGroup.kinds.contains { recipe.adjustments[$0] != identity.adjustments[$0] }
            }
            return basic
                || recipe.color.mixer != identity.color.mixer
                || !recipe.color.points.isEmpty
        case .grade:
            return recipe.color.grading != identity.color.grading
        case .presets:
            return recipe.filter != identity.filter
        case .cropGeometry:
            return recipe.crop != identity.crop
        case .heal:
            return !recipe.healing.isEmpty
        case .mask:
            return !recipe.masks.isEmpty
        case .markup:
            return !recipe.overlays.isEmpty || recipe.drawing != identity.drawing
        case .colorMix:
            return recipe.color.mixer != identity.color.mixer
        case .pointColor:
            return !recipe.color.points.isEmpty
        }
    }

    /// One section's controls, at their natural height.
    @ViewBuilder
    private func sidebarSectionBody(
        _ group: EditorGroup,
        controller: PhotoEditorController
    ) -> some View {
        VStack(spacing: 0) {
            if group == .color {
                // Four ways to work on colour, one section — Lightroom's own
                // arrangement. Grade used to be a ninth header of its own, which
                // put "colour" in two places in the same list.
                Picker("Colour controls", selection: colorSegmentBinding(controller)) {
                    Text("Basic").tag(EditorGroup.color)
                    Text("Mix").tag(EditorGroup.colorMix)
                    Text("Point").tag(EditorGroup.pointColor)
                    Text("Grade").tag(EditorGroup.grade)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.bottom, AppTheme.Spacing.sm)

                // Grade acts on one tonal region at a time, so the region picker
                // has to come with it — without it the tab quietly edits only
                // shadows.
                if colorSegment == .grade {
                    targetStrip(for: .grade, controller: controller)
                        .frame(height: EditorLayoutMetrics.sidebarTargetStripHeight)
                }

                toolPanelContent(for: colorSegment, controller: controller)
            } else if group == .cropGeometry {
                // Crop & Geometry: the frame first, then the six geometry
                // sliders and Upright under a hairline. Both shape the same
                // rectangle, and keeping them two rail stops apart meant
                // straightening a building was a tool change.
                toolPanelContent(for: .cropGeometry, controller: controller)
                Rectangle()
                    .fill(EditorTheme.panelDivider)
                    .frame(height: 1)
                    .padding(.vertical, AppTheme.Spacing.sm)
                toolPanelContent(for: .geo, controller: controller)
            } else {
                toolPanelContent(for: group, controller: controller)

                // Light carries the tone curve at its foot: the same tonal
                // decision by another instrument, and Lightroom keeps them in
                // one place too. The graph goes in the panel, not on the photo —
                // a picture with a grid drawn across it is not what a big screen
                // is for.
                if group == .light {
                    Rectangle()
                        .fill(EditorTheme.panelDivider)
                        .frame(height: 1)
                        .padding(.vertical, AppTheme.Spacing.sm)
                    toolPanelContent(for: .curve, controller: controller)
                    sidebarCurveGraph(controller)
                }
            }
        }
    }

    /// Which colour segment is showing. Kept on the selected group so the stage
    /// keeps behaving — Point arms the eyedropper on the photo.
    private var colorSegment: EditorGroup {
        Self.colorSegments.contains(chrome.selectedGroup) ? chrome.selectedGroup : .color
    }

    private func colorSegmentBinding(_ controller: PhotoEditorController) -> Binding<EditorGroup> {
        Binding(
            get: { colorSegment },
            set: { selectGroup($0, in: controller) }
        )
    }

    /// The tone-curve plot, square, inside its sidebar section.
    private func sidebarCurveGraph(_ controller: PhotoEditorController) -> some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            EditorCurveOverlay(
                controller: controller,
                chrome: chrome,
                imageRect: rect,
                stageRect: rect,
                scrollsWithPanel: true
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.bottom, AppTheme.Spacing.sm)
    }

    /// Opening a section also makes it the active group: several panels can be
    /// open at once, but only one of them can own the photo (crop handles, the
    /// mask overlay, the curve graph). Closing one leaves the active group alone.
    private func toggleSidebarSection(_ group: EditorGroup, in controller: PhotoEditorController) {
        withAnimation(EditorTheme.animation) {
            if chrome.expandedSidebarGroups.contains(group) {
                chrome.expandedSidebarGroups.remove(group)
            } else {
                chrome.expandedSidebarGroups.insert(group)
                // Only the adjustment stack is on screen when a section can be
                // opened at all — the rail's other four modes replace the stack
                // rather than sitting above it — so this never has to worry
                // about closing a live crop frame. Colour keeps whichever
                // segment was last showing.
                selectGroup(group == .color ? colorSegment : group, in: controller)
                // And bring it to the top of the scroll: a section opened from
                // the bottom of the list otherwise unfolds off-screen, and the
                // user scrolls to find the rows their own tap just produced.
                chrome.sectionToScrollTo = group
            }
        }
    }

    // MARK: Floating command band

    /// The band over the Dynamic Island, carrying the floating command row. The
    /// island splits it: undo / redo / hold-for-original on the leading edge, the
    /// histogram mini and the ⋯ menu on the trailing edge. Both clusters are inset
    /// `editorFloatingCommandSideInset` from their screen edge so the outermost disc
    /// clears the device's rounded corner; they can still butt right up against the
    /// island in the middle. Every control is a 34pt circle — this is where the
    /// panel's old command row went. The histogram mini taps to expand the card.
    /// `showsDocumentControls` is the wide layout: Back and Save ride the band's
    /// two ends there, because the sidebar that used to carry them can be
    /// collapsed and Save must never go with it.
    private func commandBand(
        _ controller: PhotoEditorController,
        height bandHeight: CGFloat,
        showsDocumentControls: Bool = false,
        /// False when the panel beside the photo already draws the graph.
        showsHistogram: Bool = true,
        /// False when the panel's own full-width Save is on screen — two Saves
        /// 300pt apart is one too many, and the panel's is the one that says
        /// what it will do.
        showsSave: Bool = true,
        /// Swaps the two clusters: Back on the trailing edge, the commands on the
        /// leading one. Follows `sidebarEdge`, so the commands always sit over the
        /// tools they act on and Back always sits on the far side from them.
        mirrored: Bool = false,
        /// Where the row of discs starts inside the band. 11 on the phone, which
        /// is what puts them level with the Dynamic Island. A wide window has no
        /// island but does have a top safe area the editor took for the photo,
        /// so the bar has to carry it or the row sits in it.
        topInset: CGFloat = EditorLayoutMetrics.editorFloatingCommandRowTopInset
    ) -> some View {
        let sideInset = EditorLayoutMetrics.editorFloatingCommandSideInset
        let buttonSize = EditorLayoutMetrics.editorFloatingCommandButtonSize(isRegularWidth: horizontalSizeClass == .regular)
        return GeometryReader { geo in
            // The three left discs plus their two 5pt gaps. The pill starts just
            // right of the Dynamic Island, so the fixed reserve is the run from the
            // end of that cluster to there; the pill then flexes out to the ⋯.
            let leftClusterWidth = buttonSize * 3 + 5 * 2
            // The reserve keeps the histogram pill clear of the Dynamic Island.
            // Gate it on a device that actually has one: an iPad in a narrow
            // Split View takes the phone layout and was leaving 219pt of empty
            // band in the middle of an unbroken strip.
            let reserve = showsDocumentControls || !hasTopCutout
                ? 0
                : max(
                    0,
                    EditorLayoutMetrics.editorHistogramPillLeading(bandWidth: geo.size.width)
                        - sideInset - leftClusterWidth
                )
            let undoRedo = HStack(spacing: 5) {
                circleCommand(
                    "arrow.uturn.backward",
                    isEnabled: controller.canUndo
                ) { controller.undo() }
                    .accessibilityLabel("Undo")

                circleCommand(
                    "arrow.uturn.forward",
                    isEnabled: controller.canRedo
                ) { controller.redo() }
                    .accessibilityLabel("Redo")

                beforeAfterButton(controller)

                if showsDocumentControls {
                    // Fit ⇄ fill, the double tap's visible twin. A gesture
                    // nobody can see is not a feature on a screen this size.
                    // It rode in the sidebar's command row until that row's job
                    // moved up here.
                    circleCommand(
                        isFillingCanvas
                            ? "arrow.down.forward.and.arrow.up.backward"
                            : "arrow.up.backward.and.arrow.down.forward",
                        isEnabled: true,
                        isActive: isFillingCanvas
                    ) {
                        chrome.requestFillZoomToggle()
                    }
                    .accessibilityLabel(isFillingCanvas ? "Fit Photo" : "Fill Screen")
                }
            }

            let trailingCommands = HStack(spacing: 5) {
                overflowMenu(controller, showsSidebarControls: showsDocumentControls)
                if showsDocumentControls, showsSave {
                    saveButton(controller, side: buttonSize)
                }
            }

            // The pill, or a clear stand-in while the card floats so the ⋯ does
            // not shift. It is the band's one flexible child — wherever a second
            // flexible child exists, an `HStack` splits the slack between them
            // and the commands end up stranded near the middle of a 1376pt bar.
            let pill = Group {
                if chrome.isHistogramCollapsed {
                    EditorHistogramPill(
                        histogram: controller.histogram,
                        namespace: histogramNamespace
                    ) {
                        withAnimation(EditorHistogramTransition.animation) {
                            chrome.isHistogramCollapsed = false
                        }
                    }
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 5) {
                if showsDocumentControls, mirrored {
                    // Every command in one cluster over the tools it acts on,
                    // ⋯ and Save included.
                    undoRedo
                    trailingCommands
                    if showsHistogram { pill } else { Spacer(minLength: AppTheme.Spacing.md) }
                    // Back stands alone on the edge away from the tools: it is
                    // the one control that *leaves*, and grouping it with the
                    // ones that change the photo is how a session gets thrown
                    // away by a mis-tap.
                    Color.clear.frame(width: AppTheme.Spacing.md)
                    backButton(controller, side: buttonSize)
                } else if showsDocumentControls {
                    // Same rule the other way round: Back alone on the far edge,
                    // everything that changes the photo gathered over the panel.
                    // Split across a 1210pt bar, the undo disc sat 869pt from the
                    // slider the hand was holding.
                    backButton(controller, side: buttonSize)
                    Color.clear.frame(width: AppTheme.Spacing.md)
                    if showsHistogram { pill } else { Spacer(minLength: AppTheme.Spacing.md) }
                    undoRedo
                    trailingCommands
                } else {
                    undoRedo
                    // Fixed reserve for the island; keeps the pill clear of the cutout.
                    Color.clear.frame(width: reserve)
                    if showsHistogram { pill }
                    trailingCommands
                }
            }
            .frame(height: buttonSize)
            .padding(.horizontal, sideInset)
            .padding(.top, topInset)
            .frame(height: bandHeight, alignment: .top)
        }
        .frame(height: bandHeight)
        .background(EditorTheme.background)
    }

    /// Hold-to-see-original, mirroring the photo's own press-and-hold. Down shows
    /// the original, up restores the edit; the circle turns accent while it is held.
    private func beforeAfterButton(_ controller: PhotoEditorController) -> some View {
        let size = EditorLayoutMetrics.editorFloatingCommandButtonSize(isRegularWidth: horizontalSizeClass == .regular)
        return Image(systemName: "rectangle.split.2x1")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(controller.showsOriginal ? .black : Color.white.opacity(0.9))
            .frame(width: size, height: size)
            .background {
                if controller.showsOriginal {
                    Circle().fill(EditorTheme.accent)
                } else {
                    floatingCircleFill
                }
            }
            .contentShape(Circle())
            .hoverEffect(.lift)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in controller.showsOriginal = true }
                    .onEnded { _ in controller.showsOriginal = false }
            )
            .accessibilityLabel("Hold to see original")
            // The drag is the whole control, so without these there is no way to
            // see the original with VoiceOver, Switch Control or a keyboard.
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                controller.showsOriginal.toggle()
            }
    }

    /// A 34pt circular band button: a blurred near-black disc, white glyph. Dims
    /// when disabled; goes accent when `isActive`.
    private func circleCommand(
        _ systemName: String,
        isEnabled: Bool,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let size = EditorLayoutMetrics.editorFloatingCommandButtonSize(isRegularWidth: horizontalSizeClass == .regular)
        return Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(
                    isActive
                        ? Color.black
                        : (isEnabled ? Color.white.opacity(0.9) : Color.white.opacity(0.28))
                )
                .frame(width: size, height: size)
                .background {
                    if isActive {
                        Circle().fill(EditorTheme.accent)
                    } else {
                        floatingCircleFill
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        // `.buttonStyle(.plain)` gets no pointer effect of its own, so without
        // this the whole top bar stayed dead under a trackpad while the panel
        // 40pt away lit up — which reads as the bar being broken rather than as
        // a missing nicety.
        .hoverEffect(.lift)
    }

    /// The blurred near-black disc under every band button. The near-black tint
    /// sits over the shared glass so the disc keeps its dark editor look while the
    /// blur (Liquid Glass on iOS 26) comes through the single glass entrypoint.
    private var floatingCircleFill: some View {
        Color.clear.editorGlass(Circle())
    }

    /// The drawing sub-mode's own top bar: Clear and Done sit up here, level with
    /// the Dynamic Island, because the `PKToolPicker` owns the bottom of the screen
    /// and would otherwise cover a bottom action row.
    /// Clear and Done for a drawing session, in the panel rather than floating
    /// over the photo. PencilKit's own palette still floats — it is the system's
    /// and cannot be re-parented — but the two decisions that end the session
    /// now sit beside the picture instead of on top of it.
    private func sidebarDrawControls(_ controller: PhotoEditorController) -> some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Text("Draw on the photo. The pencil palette is the system's; it can be dragged out of the way.")
                .font(EditorTheme.maskSubtitle)
                .foregroundStyle(EditorTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: AppTheme.Spacing.md) {
                Button("Clear") { drawSession.clear() }
                    .font(EditorTheme.pillLabel)
                    .foregroundStyle(
                        drawSession.isEmpty ? EditorTheme.dimText : Color.white.opacity(0.9)
                    )
                    .disabled(drawSession.isEmpty)
                    .frame(height: EditorLayoutMetrics.editorPrimaryButtonHeight)

                Spacer(minLength: 0)

                Button {
                    controller.commitDrawing(
                        data: drawSession.drawing.dataRepresentation(),
                        canvasSize: drawSession.canvasSize
                    )
                } label: {
                    Text("Done")
                        .font(EditorTheme.pillLabel)
                        .foregroundStyle(.black)
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .frame(height: EditorLayoutMetrics.editorPrimaryButtonHeight)
                        .background(EditorTheme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.top, AppTheme.Spacing.md)
    }

    private func drawTopBar(_ controller: PhotoEditorController) -> some View {
        HStack(spacing: 8) {
            Button("Clear") {
                drawSession.clear()
            }
            .font(.system(size: 16))
            .foregroundStyle(
                drawSession.isEmpty ? EditorTheme.dimText : EditorTheme.secondaryText
            )
            .disabled(drawSession.isEmpty)
            .frame(minWidth: 56, minHeight: 44, alignment: .leading)

            Spacer(minLength: 0)

            Button("Done") {
                controller.commitDrawing(
                    data: drawSession.drawing.dataRepresentation(),
                    canvasSize: drawSession.canvasSize
                )
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(EditorTheme.accent)
            .frame(minWidth: 52, minHeight: 44, alignment: .trailing)
        }
        .padding(.horizontal, 26)
        .padding(.top, EditorLayoutMetrics.dynamicIslandRowTopInset)
        .background(EditorTheme.background)
    }


    /// The band's ⋯ menu: every command that has no room beside the Dynamic Island.
    /// A fixed part (Reset All, History, the conditional Recall / Source) plus a
    /// per-tab part — Crop gets Rotate 90° / Flip Horizontal, an open mask gets Show
    /// Overlay / Invert Selection — following the rule that the most-used action of
    /// the tab is promoted only if there is room, and the rest fall in here.
    private func overflowMenu(
        _ controller: PhotoEditorController,
        showsSidebarControls: Bool = false
    ) -> some View {
        let size = EditorLayoutMetrics.editorFloatingCommandButtonSize(isRegularWidth: horizontalSizeClass == .regular)
        return Menu {
            // Undo and Redo are *also* here, not only as the two discs in the
            // band's corner. On a phone that corner is the one place a thumb
            // cannot reach without regripping, 800pt from the slider the hand
            // is on, and the only other route was ⌘Z. A named row costs no
            // screen space; `EditorTwoFingerTapCatcher` on the stage covers the
            // reach, the way Lightroom and Procreate both do it.
            Button {
                controller.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!controller.canUndo)

            Button {
                controller.redo()
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .disabled(!controller.canRedo)

            Divider()

            // Pinning a reference had exactly one route: a context menu on a
            // 56pt filmstrip thumbnail. HIG *Gestures* — a custom gesture must
            // not be the only way to perform an important action — and
            // `spec.md` calls the reference pane the reason the big screen
            // exists.
            if showsSidebarControls, let session, session.isMultiPhoto {
                Button {
                    withAnimation(EditorTheme.animation) {
                        if session.referenceIndex == nil {
                            session.toggleReference(at: session.index)
                        } else {
                            session.referenceIndex = nil
                        }
                    }
                } label: {
                    Label(
                        session.referenceIndex == nil ? "Use as Reference" : "Clear Reference",
                        systemImage: "rectangle.on.rectangle"
                    )
                }
            }

            // On the phone the double tap means full bleed and there is no
            // named fit ⇄ fill anywhere; in the wide layout it means fit ⇄ fill
            // and full bleed has the rail's Hide Tools. On the Duo one user
            // meets both meanings in one sitting, so each needs a control with
            // a name on it — this is the phone's missing half. (The wide layout
            // already has the fit/fill disc in the band.)
            if !showsSidebarControls {
                Button {
                    chrome.requestFillZoomToggle()
                } label: {
                    Label(
                        isFillingCanvas ? "Fit Photo" : "Fill Screen",
                        systemImage: isFillingCanvas
                            ? "arrow.down.forward.and.arrow.up.backward"
                            : "arrow.up.backward.and.arrow.down.forward"
                    )
                }
            }

            if showsSidebarControls {
                Divider()

                Picker("Tools Panel", selection: $sidebarEdgeRaw) {
                    ForEach(EditorSidebarEdge.allCases) { edge in
                        Text(edge.title).tag(edge.rawValue)
                    }
                }
                .pickerStyle(.menu)

                Button {
                    // Through `setSidebarHidden`, like the rail button and ⌘\ —
                    // it is the only thing that writes the preference, so a
                    // plain `toggle()` here hid the panel and then brought it
                    // back on the next launch.
                    withAnimation(EditorTheme.animation) {
                        setSidebarHidden(!isSidebarHidden)
                    }
                } label: {
                    Label(
                        isSidebarHidden ? "Show Tools" : "Hide Tools",
                        systemImage: isSidebarHidden
                            ? sidebarEdge.expandIcon
                            : sidebarEdge.collapseIcon
                    )
                }

                Divider()
            }

            if controller.selectedTool == .crop {
                Button {
                    controller.rotate()
                } label: {
                    Label("Rotate 90°", systemImage: "rotate.right")
                }
                Button {
                    controller.flip()
                } label: {
                    Label("Flip Horizontal", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                }
                Divider()
            } else if chrome.selectedGroup == .curve {
                Button {
                    withAnimation(EditorTheme.animation) {
                        chrome.isCurveGraphHidden.toggle()
                    }
                } label: {
                    Label(
                        chrome.isCurveGraphHidden ? "Show Graph" : "Hide Graph",
                        systemImage: "chart.xyaxis.line"
                    )
                }
                Button {
                    controller.resetAllCurves()
                } label: {
                    Label("Reset Curve", systemImage: "arrow.counterclockwise")
                }
                .disabled(controller.recipe.curve.isIdentity)
                Divider()
            } else if controller.editingMaskAdjustments {
                Button {
                    controller.setMaskOverlay(!controller.showsMaskOverlay)
                } label: {
                    Label(
                        controller.showsMaskOverlay ? "Hide Mask Overlay" : "Show Mask Overlay",
                        systemImage: "circle.righthalf.filled"
                    )
                }
                Button {
                    controller.invertSelectedMask()
                } label: {
                    Label("Invert Selection", systemImage: "circle.lefthalf.filled")
                }
                Divider()
            }


            // Tone, colour, curve and filter only — see `EditClipboard`.
            Button {
                dependencies.editClipboard.copy(from: controller.recipe)
            } label: {
                Label("Copy Edits", systemImage: "doc.on.doc")
            }
            .disabled(EditClipboard.look(of: controller.recipe).isIdentity)

            if dependencies.editClipboard.hasContent {
                Button {
                    controller.pasteEdits(from: dependencies.editClipboard)
                } label: {
                    Label("Paste Edits", systemImage: "doc.on.clipboard")
                }
            }

            if let session, session.isMultiPhoto {
                Toggle(isOn: Binding(
                    get: { session.isAutoSyncing },
                    set: { session.isAutoSyncing = $0 }
                )) {
                    Label("Auto Sync", systemImage: "arrow.triangle.2.circlepath")
                }

                if session.previousRecipe != nil {
                    Button {
                        applyPreviousEdit(controller)
                    } label: {
                        Label("Apply Previous", systemImage: "arrow.uturn.left.square")
                    }
                }

                Menu(
                    session.assets.count == 2
                        ? "Sync to 1 Photo"
                        : "Sync to \(session.assets.count - 1) Photos"
                ) {
                    Button {
                        syncEditsToAll(.look)
                    } label: {
                        Label("Sync Look", systemImage: "paintpalette")
                    }
                    Button {
                        syncEditsToAll(.everything)
                    } label: {
                        Label("Sync Everything", systemImage: "square.on.square.dashed")
                    }
                }
                .disabled(controller.recipe.isIdentity)
            }

            Button {
                controller.reset()
            } label: {
                Label("Reset All", systemImage: "arrow.counterclockwise")
            }
            .disabled(controller.recipe.isIdentity)

            // Reset All only undoes this session. Revert throws away every edit
            // ever saved to the asset, including edits made in Photos, and is
            // the only way back to the camera's own frame.
            if controller.canRevertToOriginal {
                Button(role: .destructive) {
                    isRevertConfirmationPresented = true
                } label: {
                    Label("Revert to Original", systemImage: "arrow.uturn.backward")
                }
            }

            Button {
                showHistory()
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }

            if controller.recalledRecipe != nil {
                Button {
                    controller.recallLastEdit()
                } label: {
                    Label("Recall Last ShotDex Edit", systemImage: "arrow.trianglehead.clockwise")
                }
                .disabled(!controller.canRecall)
            }

            if controller.sourceOptions.count > 1 {
                Menu("Source") {
                    ForEach(controller.sourceOptions) { option in
                        Button {
                            Task {
                                try? await controller.selectSource(option)
                            }
                        } label: {
                            if option.id == controller.selectedSourceOption?.id {
                                Label(option.displayName, systemImage: "checkmark")
                            } else {
                                Text(option.displayName)
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.9))
                .frame(width: size, height: size)
                .background { floatingCircleFill }
                .contentShape(Circle())
        }
        .hoverEffect(.lift)
        .accessibilityLabel("More editor actions")
    }

    // MARK: Panel

    /// The phone panel (FS-03.12): one opaque slab of fixed height, top corners
    /// rounded, no hairline. Top to bottom — the parameter zone on a 40pt row grid
    /// (its first row is the target strip when the group has one, so the zone, and
    /// the panel, stay one height on every tab), then the group strip (a snap wheel
    /// flanked by Back and Save), then a bare home-indicator inset. No blur, no
    /// glass; the image never shows through it.
    private func panel(_ controller: PhotoEditorController, height: CGFloat) -> some View {
        let hasTarget = panelHasTargetStrip(controller)
        let rowsHeight = EditorLayoutMetrics.editorParamAreaHeight(
            hasTargetStrip: hasTarget
        )
        let slab = UnevenRoundedRectangle(
            topLeadingRadius: EditorLayoutMetrics.editorPanelCornerRadius,
            topTrailingRadius: EditorLayoutMetrics.editorPanelCornerRadius,
            style: .continuous
        )
        return VStack(spacing: 0) {
            // Parameter zone: fixed total height — an 8pt inset, the target strip
            // (one grid row) when the group has one, then the rows. Row n of every
            // group therefore sits at the same y.
            VStack(spacing: 0) {
                Color.clear.frame(height: EditorLayoutMetrics.editorParamZoneTopInset)
                if hasTarget {
                    targetStrip(controller)
                        .frame(height: EditorLayoutMetrics.editorTargetStripHeight)
                }
                toolPanel(controller)
                    .frame(height: rowsHeight)
            }
            .frame(height: EditorLayoutMetrics.editorParamZoneHeight)
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [EditorTheme.panelSolid.opacity(0), EditorTheme.panelSolid],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: EditorLayoutMetrics.editorParamZoneFadeHeight)
                .allowsHitTesting(false)
            }
            .clipShape(slab)

            groupStripRow(controller)
                .frame(height: EditorLayoutMetrics.editorGroupStripHeight)
            // Bare home-indicator zone: the wheel above takes only horizontal
            // swipes, so the system's vertical bottom-edge gesture never fights it.
            Color.clear.frame(height: EditorLayoutMetrics.editorPanelSafeAreaInset)
        }
        .frame(height: height)
        .background(EditorTheme.panelSolid, in: slab)
        .environment(\.editorUsesPanelStyle, true)
    }

    /// The target strip — which area of the photo the controls act on — shows only
    /// where there is one to pick: Grade's tonal region. (Mask keeps its own list /
    /// detail panels for now.)
    private func panelHasTargetStrip(_ controller: PhotoEditorController) -> Bool {
        chrome.selectedGroup == .grade
    }

    private func targetStrip(_ controller: PhotoEditorController) -> some View {
        targetStrip(for: chrome.selectedGroup, controller: controller)
    }

    @ViewBuilder
    private func targetStrip(
        for group: EditorGroup,
        controller: PhotoEditorController
    ) -> some View {
        switch group {
        case .grade:
            EditorGradeRegionStrip(controller: controller, chrome: chrome)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            EmptyView()
        }
    }

    // MARK: Back / Save (group-strip ends)

    /// Back: a chevron on the leading end of the group strip, discard-guarded
    /// when the session has changes.
    ///
    /// 38 is the phone's strip size. On a wide screen Back and Save move up into
    /// the command band, where the circles beside them are 44 — so the caller
    /// passes the band's own size rather than leaving two neighbours six points
    /// apart, both of them under the 44pt minimum.
    private func backButton(_ controller: PhotoEditorController, side: CGFloat = 38) -> some View {
        Button {
            if hasUnsavedWork {
                isDiscardConfirmationPresented = true
            } else {
                dismiss()
            }
        } label: {
            Image(systemName: "chevron.backward")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.6))
                .frame(width: side, height: side)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .accessibilityLabel("Back")
    }

    /// Save (✓): the one accent control on the screen, a filled circle on the
    /// trailing end of the group strip (42) or of the command band (the band's
    /// own size). Commits a draft crop first, then opens the save sheet.
    private func saveButton(_ controller: PhotoEditorController, side: CGFloat = 42) -> some View {
        Button {
            controller.commitCropSession()
            isSaveSheetPresented = true
        } label: {
            if chrome.isWideLayout {
                // A word, not a slab. The panel's old Save was 240×50 of accent
                // sitting beside a photograph whose colour the user is judging;
                // the pill says the same thing in 32pt and lets the picture be
                // the brightest thing on screen.
                Text("Save")
                    .font(EditorTheme.pillLabel)
                    .foregroundStyle(.black)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .frame(height: EditorLayoutMetrics.editorPrimaryButtonHeight)
                    .frame(maxWidth: EditorLayoutMetrics.editorPrimaryButtonMaxWidth)
                    .background(EditorTheme.accent, in: Capsule())
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: side, height: side)
                    .background(EditorTheme.accent, in: Circle())
                    .contentShape(Circle())
            }
        }
        .buttonStyle(.plain)
        .disabled(controller.isLoading || controller.isSaving)
        .hoverEffect(.lift)
        .accessibilityLabel("Save")
    }

    /// The panel for whichever group the phone layout has open.
    private func toolPanel(_ controller: PhotoEditorController) -> some View {
        toolPanelContent(for: chrome.selectedGroup, controller: controller)
    }

    /// One group's controls. Takes the group explicitly rather than reading
    /// `chrome.selectedGroup`, because the wide-screen sidebar draws several
    /// groups at once and only one of them is the selected one.
    @ViewBuilder
    private func toolPanelContent(
        for group: EditorGroup,
        controller: PhotoEditorController,
        isScrollable: Bool? = nil
    ) -> some View {
        switch group {
        case .light, .effects, .detail, .optics, .geo:
            adjustmentContent(group, controller: controller, isScrollable: isScrollable)
        case .curve:
            EditorCurvePanel(controller: controller, chrome: chrome)
        case .color:
            colorContent(controller, isScrollable: isScrollable)
        case .colorMix:
            EditorColorMixerSection(controller: controller, chrome: chrome)
        case .pointColor:
            EditorPointColorSection(controller: controller, chrome: chrome)
        case .grade:
            EditorColorGradingSection(controller: controller, chrome: chrome)
        case .presets:
            EditorFiltersPanel(
                controller: controller,
                chrome: chrome,
                lookPresets: dependencies.lookPresets,
                luts: dependencies.importedLUTs,
                saveLook: {
                    lookName = dependencies.lookPresets.suggestedName()
                    isSaveLookPresented = true
                },
                scrolls: isScrollable ?? !chrome.isWideLayout
            )
        case .markup:
            // The detail panel shows only when explicitly opened. A merely selected
            // layer keeps the list up and is moved / resized / rotated on the photo.
            if !controller.showsOverlayDetail || controller.selectedOverlay == nil {
                EditorTextPanel(
                    controller: controller,
                    chrome: chrome,
                    addText: { startTextEntry(controller, isNew: true) },
                    addImage: { isImagePickerPresented = true },
                    addShape: { controller.addShapeOverlay($0) },
                    addMagnifier: { controller.addMagnifierOverlay() },
                    startDrawing: { startDrawing(controller) },
                    openPresets: { isSignatureLibraryPresented = true }
                )
            } else {
                EditorTextDetailPanel(
                    controller: controller,
                    chrome: chrome,
                    editText: { startTextEntry(controller, isNew: false) },
                    pickFont: { isFontPickerPresented = true },
                    replaceImage: { isImagePickerPresented = true },
                    saveSignature: {
                        signatureName = defaultSignatureName(controller)
                        isSignatureNamePresented = true
                    }
                )
            }
        case .cropGeometry:
            EditorCropPanel(controller: controller)
        case .heal:
            EditorHealPanel(controller: controller)
        case .mask:
            if controller.editingMaskAdjustments {
                EditorMaskDetailPanel(
                    controller: controller,
                    chrome: chrome,
                    rename: { presentRename(controller) }
                )
            } else {
                EditorMaskListPanel(
                    controller: controller,
                    chrome: chrome,
                    rename: { presentRename(controller) }
                )
            }
        }
    }

    /// The rows for one adjustment-style group. Light / Color / Effects / Detail
    /// map onto the existing catalog groups; Optics and Geo have no parameters yet
    /// (parity work lands later) so they show a placeholder rather than an empty
    /// list.
    @ViewBuilder
    private func adjustmentContent(
        _ group: EditorGroup,
        controller: PhotoEditorController,
        isScrollable: Bool? = nil
    ) -> some View {
        let groups = catalogGroups(for: group, controller: controller)
        if groups.isEmpty {
            placeholderContent(group)
        } else if group == .optics {
            // The profile first: it is the correction the other two sliders
            // clean up after, and Lightroom lists it first for that reason.
            VStack(spacing: 0) {
                EditorLensProfileSection(controller: controller)
                EditorAdjustmentGroupsView(
                    controller: controller,
                    chrome: chrome,
                    groups: groups,
                    isScrollable: isScrollable
                )
            }
        } else if group == .geo {
            // Upright sits above the sliders, the way Lightroom orders them:
            // it is the thing that sets those sliders, so reading it after
            // them is reading the answer before the question.
            VStack(spacing: 0) {
                EditorUprightRow(controller: controller)
                EditorAdjustmentGroupsView(
                    controller: controller,
                    chrome: chrome,
                    groups: groups,
                    isScrollable: isScrollable
                )
            }
        } else {
            EditorAdjustmentGroupsView(
                controller: controller,
                chrome: chrome,
                groups: groups,
                isScrollable: isScrollable
            )
        }
    }

    private func catalogGroups(
        for group: EditorGroup,
        controller: PhotoEditorController
    ) -> [EditorAdjustmentGroup] {
        let all = EditorAdjustmentCatalog.groups(
            isRAWSource: controller.isRAWSource,
            scope: .global,
            hasDepth: controller.hasDepthSource
        )
        let ids: [EditorAdjustmentGroup.Identity]
        switch group {
        case .light: ids = [.light]
        case .color: ids = [.color]
        case .effects: ids = [.effects]
        case .detail: ids = controller.isRAWSource ? [.detail, .raw] : [.detail]
        case .optics: ids = [.optics]
        case .geo: ids = [.geo]
        default: ids = []
        }
        return ids.compactMap { id in all.first { $0.id == id } }
    }

    private func placeholderContent(_ group: EditorGroup) -> some View {
        VStack(spacing: 8) {
            Image(systemName: group == .optics ? "camera.aperture" : "grid")
                .font(.system(size: 24))
                .foregroundStyle(EditorTheme.dimText)
            Text("\(group.title) — coming soon")
                .font(EditorTheme.rowLabel)
                .foregroundStyle(EditorTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The Color group: the base Temp / Tint / Vibrance / Saturation rows. The HSL
    /// mixer is now its own nav chip (`.colorMix`), not a sub-view reached from a
    /// row here.
    private func colorContent(
        _ controller: PhotoEditorController,
        isScrollable: Bool? = nil
    ) -> some View {
        EditorAdjustmentGroupsView(
            controller: controller,
            chrome: chrome,
            groups: catalogGroups(for: .color, controller: controller),
            isScrollable: isScrollable
        )
    }

    /// The group-strip tier: `[Back] [wheel] [Save]`. The wheel is a snap picker
    /// whose centred chip is the open group; Back and Save flank it. Padding 10,
    /// gap 8, per Turn 31 §4.
    private func groupStripRow(_ controller: PhotoEditorController) -> some View {
        HStack(spacing: 8) {
            backButton(controller)
            EditorGroupWheel(controller: controller, chrome: chrome) { group in
                selectGroup(group, in: controller)
            }
            .frame(maxWidth: .infinity)
            saveButton(controller)
        }
        .padding(.horizontal, 10)
        .frame(height: EditorLayoutMetrics.editorGroupStripHeight)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
        }
    }

    private func undoToastView(
        _ controller: PhotoEditorController,
        toast: EditorChromeModel.UndoToast
    ) -> some View {
        HStack(spacing: 8) {
            Text(toast.message)
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(.white)
            Divider()
                .frame(height: 18)
            Button("Undo") {
                controller.undo()
                chrome.dismissUndoToast()
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(EditorTheme.accent)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .editorGlass(cornerRadius: 22)
    }

    /// Switch the panel to a nav group and put the controller in the matching tool.
    /// The six adjustment groups all sit on the global `.adjust` tool and differ
    /// only in which rows `toolPanel` shows.
    private func selectGroup(
        _ group: EditorGroup,
        in controller: PhotoEditorController,
        discardingCrop: Bool = false
    ) {
        chrome.isEyedropperActive = false
        // A cancelled hold-to-compare must not follow the user into the next
        // tool. See `stageContextMenu`.
        controller.showsOriginal = false
        // 30c has no crop Done: the crop stays live and is committed when its tab is
        // left (or when the edit is saved). Switching to any other group is that
        // moment. Leaving via Save commits too, so a double commit is harmless.
        if chrome.selectedGroup == .cropGeometry, group != .cropGeometry {
            // `discardingCrop` is the repeat-tap on the rail's Crop stop, which
            // the rail advertises as the way out that does not apply the frame.
            // It used to advertise it and then commit anyway — the claim was in
            // the comment and in `spec.md`, and nothing implemented it.
            if discardingCrop {
                controller.cancelCropSession()
            } else {
                controller.commitCropSession()
            }
        }
        // Zoom is state the user built up by hand, and only Crop needs it gone —
        // the crop frame is laid out against the fitted photo. It used to reset
        // on *every* group change, which in the wide layout is on the path of
        // every rail tap, every accordion header and every Color segment: pinch
        // to 400% to judge sharpening, reach for Detail, lose the eyelash.
        if group == .cropGeometry || chrome.selectedGroup == .cropGeometry {
            chrome.resetZoom()
        }
        // A stage mode is a session with a way out: snapshot on the way in so
        // Cancel has somewhere to return to, and drop the snapshot on the way
        // out so Apply's work is not still pending a rewind.
        if [EditorGroup.cropGeometry, .heal, .mask, .markup].contains(group) {
            controller.beginStageSession()
        } else {
            controller.clearStageEntry()
        }
        withAnimation(EditorTheme.animation) {
            chrome.selectedGroup = group
        }
        switch group {
        case .light, .curve, .color, .colorMix, .effects, .detail, .optics, .geo:
            controller.editGlobalAdjustments()
            // The graph takes the photo; a card floating over both would be noise.
            if group == .curve {
                chrome.collapseHistogram()
            }
        case .mask:
            controller.selectedTool = .masks
            controller.scheduleRender()
        case .markup:
            // Always at the list level on arrival: a layer left selected from a
            // previous visit would hand the photo's gestures to it before the user
            // has said which layer they mean.
            controller.selectOverlay(nil)
            controller.selectedTool = .markup
            controller.closeSelectedMaskAdjustments()
        case .heal:
            controller.selectOverlay(nil)
            controller.closeSelectedMaskAdjustments()
            controller.selectedTool = .heal
        case .pointColor, .grade, .cropGeometry, .presets:
            controller.selectedTool = group.tool
            controller.selectOverlay(nil)
            controller.closeSelectedMaskAdjustments()
        }
    }

    /// Loads the current drawing into the canvas and enters the draw sub-mode. Zoom
    /// is reset so canvas points map straight to the fitted photo rect.
    private func startDrawing(_ controller: PhotoEditorController) {
        chrome.resetZoom()
        drawSession.load(data: controller.drawingData)
        controller.beginDrawing()
    }

    /// Names a new signature after what it says, so the library is browsable
    /// without applying every entry.
    private func defaultSignatureName(_ controller: PhotoEditorController) -> String {
        let firstText = controller.recipe.overlays
            .first { $0.kind == .text && !$0.text.isEmpty }
            .map { controller.resolvedText(for: $0) }
            .map { $0.replacingOccurrences(of: "\n", with: " ") }
        guard let firstText, !firstText.isEmpty else { return "Signature" }
        return String(firstText.prefix(40))
    }

    private func presentRename(_ controller: PhotoEditorController) {
        renameText = controller.selectedMask?.name ?? ""
        isRenamePresented = true
    }
}

private struct PhotoEditorSaveSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var controller: PhotoEditorController
    /// Photos in this run carrying edits. Zero for a single-photo session, which
    /// hides the batch row entirely.
    var pendingCount: Int = 0
    /// Starts a batch write: format, metadata, and whether it copies rather than
    /// overwrites.
    var saveAll: ((PhotoOutputFormat, Bool, Bool) -> Void)?
    let onFinished: () -> Void

    /// Defaults to JPEG: it is the format that always works, and making every save
    /// start with a format decision was friction for no benefit.
    @State private var format: PhotoOutputFormat? = .jpeg
    @State private var includeMetadata = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Format", selection: $format) {
                        Text("JPEG").tag(PhotoOutputFormat.jpeg as PhotoOutputFormat?)
                        Text("HEIC").tag(PhotoOutputFormat.heic as PhotoOutputFormat?)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Include Metadata", isOn: $includeMetadata)
                    if format == .heic, !controller.supportsHEICEditOutput {
                        Label(
                            "Photos doesn't support an HEIC edited version of this photo. ShotDex will save a maximum-quality JPEG.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    }
                } footer: {
                    Text("Save Copy is full resolution at maximum quality. Turning off metadata strips EXIF and clears the Photos date/location on Save Changes. If Photos doesn't support HEIC for this photo, ShotDex falls back to JPEG and tells you.")
                }

                if pendingCount > 1, let saveAll {
                    Section {
                        Button {
                            guard let format else { return }
                            saveAll(format, includeMetadata, false)
                        } label: {
                            Label(
                                "Save Changes to \(pendingCount) Photos",
                                systemImage: "square.and.arrow.down.on.square"
                            )
                        }
                        .disabled(format == nil)

                        Button {
                            guard let format else { return }
                            saveAll(format, includeMetadata, true)
                        } label: {
                            Label(
                                "Save \(pendingCount) Copies",
                                systemImage: "plus.square.on.square"
                            )
                        }
                        .disabled(format == nil)
                    } footer: {
                        Text("Writes every photo in this run that has edits. One that fails keeps its edits so you can try it again.")
                    }
                }

                Section {
                    Button {
                        guard let format else { return }
                        Task {
                            await controller.saveCopy(
                                format: format,
                                includeMetadata: includeMetadata
                            )
                            if controller.savedAssetID != nil { onFinished() }
                        }
                    } label: {
                        Label("Save Copy", systemImage: "plus.square.on.square")
                    }
                    .disabled(format == nil)

                    Button {
                        guard let format else { return }
                        Task {
                            await controller.saveChanges(
                                format: format,
                                includeMetadata: includeMetadata
                            )
                            if controller.savedAssetID != nil { onFinished() }
                        }
                    } label: {
                        Label("Save Changes", systemImage: "square.and.arrow.down")
                    }
                    .disabled(
                        format == nil || !controller.asset.canPerform(.content)
                    )
                } footer: {
                    Text("Save Changes is non-destructive: Photos keeps the original and ShotDex reopens this photo with the saved crop, sliders and masks. A Live Photo keeps its motion. Save Copy creates a still image.")
                }
            }
            .navigationTitle("Save Edit")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(controller.isSaving)
            .overlay {
                if controller.isSaving {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea()
                        ProgressView("Rendering full resolution…")
                            .padding(20)
                            .glassBackground(RoundedRectangle.app(AppTheme.Radius.lg))
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// The group wheel (Turn 31 §4): a horizontal snap picker where the chip nearest the
/// centre *is* the open group. Swiping and letting go snaps the nearest chip to the
/// centre and switches to it — one gesture, no second tap; tapping an off-centre chip
/// scrolls it to the centre and switches too. Half-viewport margins on both ends let
/// the first and last groups reach the centre; a fade dissolves each edge into the
/// panel colour. The centred chip is accent-tinted; the rest are dim — that tint is
/// the whole selection indicator (the accent notch rail that used to frame the
/// centred chip was dropped as visual noise). Every change gives a selection haptic.
private struct EditorGroupWheel: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel
    /// Called with the group that reached the centre, to drive `selectGroup`.
    let onSelect: (EditorGroup) -> Void

    /// The chip the scroll view has snapped to the centre. Bound to
    /// `scrollPosition`, so it follows both drags and programmatic scrolls.
    @State private var centered: EditorGroup?
    /// Waits for the wheel to stop moving before the panel changes.
    ///
    /// `centered` reports *every* chip that passes the middle, so acting on it
    /// directly ran the full `selectGroup` — a crop commit, a tool change, a
    /// `scheduleRender` — once per chip a flick went past, with a haptic
    /// apiece. `spec.md` writes the intent as "vuốt → nhả → snap → đổi nhóm":
    /// one switch, on release. A debounce rather than `onScrollPhaseChange`
    /// because the deployment target is iOS 17, and it covers the tap route
    /// too, which animates `centered` with no scroll phase at all. The tint
    /// still follows the wheel chip by chip.
    @State private var settleTask: Task<Void, Never>?
    private static let settleDelay = Duration.milliseconds(140)

    var body: some View {
        GeometryReader { geo in
            // Half-viewport-minus-half-chip padding at each end, so the first and
            // last chips can sit dead centre.
            let sideInset = max(
                0,
                (geo.size.width - EditorLayoutMetrics.editorGroupChipWidth) / 2
            )
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(EditorGroup.allCases) { group in
                        chip(group).id(group)
                    }
                }
                .frame(maxHeight: .infinity)
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, sideInset, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centered, anchor: .center)
            .sensoryFeedback(.selection, trigger: centered)
            .onAppear { centered = chrome.selectedGroup }
            .onChange(of: centered) { _, new in
                settleTask?.cancel()
                guard let new else { return }
                settleTask = Task {
                    try? await Task.sleep(for: Self.settleDelay)
                    guard !Task.isCancelled, centered == new,
                          new != chrome.selectedGroup
                    else { return }
                    onSelect(new)
                }
            }
            .onDisappear { settleTask?.cancel() }
            .onChange(of: chrome.selectedGroup) { _, group in
                // A group changed from outside the wheel (rare — Save's crop commit,
                // a deep-link): keep the centred chip in step.
                guard centered != group else { return }
                withAnimation(EditorTheme.animation) { centered = group }
            }
            .overlay { edgeFades }
        }
    }

    private func chip(_ group: EditorGroup) -> some View {
        let isCenter = centered == group
        return Button {
            withAnimation(EditorTheme.animation) { centered = group }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: group.icon)
                    .font(.system(size: 19, weight: isCenter ? .semibold : .regular))
                Text(group.title)
                    .font(.system(size: 9.5, weight: isCenter ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(isCenter ? EditorTheme.accent : Color.white.opacity(0.5))
            .frame(
                width: EditorLayoutMetrics.editorGroupChipWidth,
                height: EditorLayoutMetrics.editorGroupChipHeight
            )
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(group.title)
        .accessibilityAddTraits(isCenter ? .isSelected : [])
    }

    /// The two 26pt fades dissolving the wheel's ends into the panel colour.
    private var edgeFades: some View {
        let fade = EditorLayoutMetrics.editorGroupWheelEdgeFade
        return HStack(spacing: 0) {
            LinearGradient(
                colors: [EditorTheme.panelSolid, EditorTheme.panelSolid.opacity(0)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: fade)
            Spacer(minLength: 0)
            LinearGradient(
                colors: [EditorTheme.panelSolid.opacity(0), EditorTheme.panelSolid],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: fade)
        }
        .allowsHitTesting(false)
    }
}

