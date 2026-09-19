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

    /// Wide-screen sidebar: which side it is parked on, how wide, and whether it
    /// is collapsed. All three are the user's, so all three persist.
    @AppStorage(SettingsKeys.editorSidebarEdge)
    private var sidebarEdgeRaw = EditorSidebarEdge.trailing.rawValue
    @AppStorage(SettingsKeys.editorSidebarWidth)
    private var storedSidebarWidth = Double(EditorLayoutMetrics.sidebarDefaultWidth)
    @AppStorage(SettingsKeys.editorSidebarHidden)
    private var isSidebarHidden = false
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
    /// Pick / reject / rating for every photo in the run, read once when the
    /// strip appears and after each change rather than per thumbnail.
    @State private var cullStates: [String: PhotoCullState] = [:]
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
            controller?.close()
        }
        .interactiveDismissDisabled(controller?.hasSessionChanges == true)
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
            Text("Photos doesn't support HEIC as the edited rendition for this asset, so ShotDex saved a maximum-quality JPEG instead.")
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
            Button("Hide or Show Tools") { isSidebarHidden.toggle() }
                .keyboardShortcut("\\", modifiers: .command)
            Button("Back") {
                if controller.hasSessionChanges {
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
    private func openCurrentPhoto() async {
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
        await newController.load()
        // After load: `load()` reads the asset's own saved edit, and the draft
        // from this session is the newer of the two.
        if let draft = session.draft(for: target) {
            newController.apply(draft)
        }
    }

    /// Switches the canvas to another photo in the run, parking the current
    /// edit in the session first so coming back restores it.
    private func selectPhoto(at index: Int) {
        guard let session, index != session.index, session.assets.indices.contains(index) else {
            return
        }
        if let controller, let current = session.current {
            controller.commitCropSession()
            session.store(controller.recipe, for: current)
            controller.close()
        }
        session.moveToPhoto(at: index)
        controller = nil
        Task { await openCurrentPhoto() }
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
            // Width *and* height: the sidebar's own chrome — title, histogram,
            // command row, tool strip, Save — is about 280pt before a single tool
            // row, so a 700×400 window would be all panel and no tools.
            let isWide = proxy.size.width >= EditorLayoutMetrics.sidebarMinCanvasWidth
                && proxy.size.height >= EditorLayoutMetrics.sidebarMinCanvasHeight
            Group {
                if isWide {
                    wideBody(
                        controller,
                        // The editor claims the safe areas, so the band has to
                        // carry the status bar itself — `max` would tuck the
                        // Back/Save row under an iPad Split View's clock.
                        bandHeight: 56 + proxy.safeAreaInsets.top,
                        safeArea: proxy.safeAreaInsets,
                        canvasWidth: proxy.size.width,
                        canvasHeight: proxy.size.height
                    )
                } else {
                    narrowBody(
                        controller,
                        bandHeight: bandHeight,
                        panelHeight: panelHeight
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
            }
            .onChange(of: isWide, initial: true) { _, wide in
                chrome.isWideLayout = wide
                // Full bleed is a phone answer to a phone problem — no room. It
                // has no exit in the wide layout (the sidebar and the band both
                // hide for it), so a window dragged past the threshold while
                // full-bleed would strand the session with no Back and no Save.
                if wide { chrome.isFullBleed = false }
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
                    .padding(.bottom, chrome.isFullBleed ? 40 : 24)
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
            EditorNewMaskSheet { kind in
                controller.addMask(kind: kind)
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
        panelHeight: CGFloat
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

            filmstrip(controller)

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
        let showsSidebar = !isSidebarHidden && !controller.isEditingDrawing
        return HStack(spacing: 0) {
            if sidebarEdge == .leading, showsSidebar {
                sidebarColumn(controller, safeArea: safeArea, canvasWidth: canvasWidth)
                    .transition(.move(edge: .leading))
                resizeHandle(canvasWidth: canvasWidth)
            }

            VStack(spacing: 0) {
                if controller.isEditingDrawing {
                    drawTopBar(controller)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else if !chrome.isFullBleed, !showsSidebar {
                    // Only when the tools are away. With the sidebar up the band
                    // would be a second strip of chrome stealing 56pt from the
                    // photo for controls the sidebar already carries — and on a
                    // desktop-shaped editor the picture is what the space is for.
                    commandBand(
                        controller,
                        height: bandHeight,
                        showsDocumentControls: true
                    )
                    .transition(.opacity)
                }

                if let reference = session?.referenceAsset, !chrome.isFullBleed,
                   !controller.isEditingDrawing {
                    referenceSplit(
                        controller,
                        reference: reference,
                        canvas: CGSize(
                            width: canvasWidth - (showsSidebar ? sidebarWidth(in: canvasWidth) : 0),
                            height: canvasHeight
                        )
                    )
                    .transition(.opacity)
                } else {
                    imageStage(controller)
                }

                filmstrip(controller)
            }
            if sidebarEdge == .trailing, showsSidebar {
                resizeHandle(canvasWidth: canvasWidth)
                sidebarColumn(controller, safeArea: safeArea, canvasWidth: canvasWidth)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(EditorTheme.animation, value: showsSidebar)
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
    private func filmstrip(_ controller: PhotoEditorController) -> some View {
        if let session, session.isMultiPhoto, !chrome.isFullBleed, !controller.isEditingDrawing {
            EditorFilmstrip(
                session: session,
                photoLibrary: dependencies.photoLibrary,
                currentHasEdits: !controller.recipe.isIdentity,
                cullStates: cullStates,
                setFlag: { flag, asset in
                    try? dependencies.cullStore.setFlag(flag, ids: [asset.localIdentifier])
                    reloadCullStates()
                },
                toggleReference: chrome.isWideLayout
                    ? { index in
                        withAnimation(EditorTheme.animation) {
                            session.toggleReference(at: index)
                        }
                    }
                    : nil
            ) { index in
                selectPhoto(at: index)
            }
            .task(id: session.assets.count) { reloadCullStates() }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func reloadCullStates() {
        guard let session, session.isMultiPhoto else { return }
        cullStates = (try? dependencies.cullStore.states(
            assetIds: session.assets.map(\.localIdentifier)
        )) ?? [:]
    }

    /// The photo itself, with the floating histogram card over it. Shared by both
    /// layouts — only the chrome around it differs.
    private func imageStage(_ controller: PhotoEditorController) -> some View {
        stageContent(controller)
            // A secondary click on the photo reaches the same commands as the ⋯
            // button. Pointer users expect the canvas itself to answer; without
            // it a trackpad right-click on an iPad does nothing anywhere in the
            // editor.
            .contextMenu {
                Button {
                    controller.applyAutoTone()
                } label: {
                    Label("Auto Enhance", systemImage: "wand.and.sparkles")
                }
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
                    chrome.isHistorySheetPresented = true
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

    /// Whether the photo is currently filling the canvas rather than fitted into
    /// it. Read from the zoom the fill sets, with a margin for float error — a
    /// hand-pinched zoom reads as filled too, which is what the fit button should
    /// undo anyway.
    private var isFillingCanvas: Bool { chrome.zoomScale > 1.02 }

    /// Whether this device has a Dynamic Island / notch worth routing the band
    /// around. iPads have a 24pt status inset and no cutout.
    private var hasTopCutout: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
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
            }
            sidebarDragWidth = nil
            sidebarDragStartWidth = nil
        }
    }

    private func sidebarColumn(
        _ controller: PhotoEditorController,
        safeArea: EdgeInsets,
        canvasWidth: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            // The editor ignores the container's safe areas so the photo can use
            // them; the sidebar is chrome and has to put them back, or its header
            // sits under an iPad Split View's status bar and Save sits in the
            // home-indicator swipe strip.
            Color.clear.frame(height: safeArea.top)

            HStack(spacing: 0) {
                backButton(controller)
                Spacer(minLength: 8)
                Text("Edit")
                    .font(EditorTheme.sidebarTitle)
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Button {
                    isSidebarHidden = true
                } label: {
                    Image(systemName: sidebarEdge.collapseIcon)
                        .font(EditorTheme.commandGlyph)
                        .foregroundStyle(EditorTheme.secondaryText)
                        .frame(width: AppTheme.Size.minTouch, height: AppTheme.Size.minTouch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide Tools")
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(height: EditorLayoutMetrics.sidebarHeaderHeight)

            // The histogram is the first thing in the panel and it never leaves,
            // the way every desktop raw editor has it: it is read continuously
            // while the sliders move, so parking it behind a tap (the phone's
            // band mini) would be one tap per glance.
            EditorHistogramSparkline(histogram: controller.histogram)
                .padding(AppTheme.Spacing.sm)
                .frame(height: EditorLayoutMetrics.sidebarHistogramHeight)
                .background(
                    EditorTheme.control,
                    in: RoundedRectangle.app(AppTheme.Radius.lg)
                )
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.bottom, AppTheme.Spacing.sm)
                .accessibilityElement()
                .accessibilityLabel("RGB histogram")
                .accessibilityValue(histogramClippingSummary(controller))

            HStack(spacing: AppTheme.Spacing.sm) {
                circleCommand("arrow.uturn.backward", isEnabled: controller.canUndo) {
                    controller.undo()
                }
                .accessibilityLabel("Undo")
                circleCommand("arrow.uturn.forward", isEnabled: controller.canRedo) {
                    controller.redo()
                }
                .accessibilityLabel("Redo")
                beforeAfterButton(controller)
                // Fit ⇄ fill, the double tap's visible twin. A gesture nobody
                // can see is not a feature on a screen this size.
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
                Spacer(minLength: 8)
                overflowMenu(controller, showsSidebarControls: true)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.sm)

            Rectangle().fill(EditorTheme.panelDivider).frame(height: 1)

            sidebarToolStrip(controller)

            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    // Whichever stage tool is up gets its panel first, above the
                    // parameter stack — it is the thing the user just picked.
                    if let tool = activeStageTool {
                        sidebarSectionBody(tool, controller: controller)
                            .padding(.bottom, AppTheme.Spacing.sm)
                        Rectangle().fill(EditorTheme.panelDivider).frame(height: 1)
                    }

                    ForEach(Self.sidebarParameterGroups) { group in
                        EditorSidebarSection(
                            group: group,
                            isExpanded: chrome.expandedSidebarGroups.contains(group),
                            isActive: chrome.selectedGroup == group
                                || (group == .color && Self.colorSegments.contains(chrome.selectedGroup)),
                            hasEdits: groupHasEdits(group, controller: controller),
                            toggle: { toggleSidebarSection(group, in: controller) }
                        ) {
                            sidebarSectionBody(group, controller: controller)
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

            Rectangle().fill(EditorTheme.panelDivider).frame(height: 1)

            Button {
                controller.commitCropSession()
                isSaveSheetPresented = true
            } label: {
                Group {
                    if controller.isSaving {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            ProgressView().tint(.black)
                            Text("Saving\u{2026}")
                        }
                    } else if controller.isLoading {
                        Text("Opening\u{2026}")
                    } else {
                        Text("Save\u{2026}")
                    }
                }
                    .font(EditorTheme.sidebarActionLabel)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppTheme.Size.primaryActionHeight)
                    .background(
                        EditorTheme.accent,
                        in: RoundedRectangle.app(AppTheme.Radius.md)
                    )
            }
            .buttonStyle(.plain)
            .disabled(controller.isLoading || controller.isSaving)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.top, AppTheme.Spacing.md)
            .padding(.bottom, max(safeArea.bottom, AppTheme.Spacing.md))
        }
        .frame(width: sidebarWidth(in: canvasWidth))
        .background(EditorTheme.panelSolid)
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
    /// not fit even with everything closed.
    private static let sidebarParameterGroups: [EditorGroup] = [
        .light, .curve, .color, .grade, .detail, .effects
    ]

    /// Tools that take the photo over. Exactly one can be up at a time, so they
    /// are a radio strip rather than four more disclosures.
    private static let sidebarToolGroups: [EditorGroup] = [.crop, .mask, .markup, .presets]

    /// The three ways to work on colour, shown as segments inside one section
    /// the way Lightroom nests HSL under Color.
    private static let colorSegments: [EditorGroup] = [.color, .colorMix, .pointColor]

    private var activeStageTool: EditorGroup? {
        Self.sidebarToolGroups.contains(chrome.selectedGroup) ? chrome.selectedGroup : nil
    }

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

    /// The radio strip of stage tools. Tapping the one that is already up puts
    /// the photo back to plain adjusting, which is the only way out of Crop that
    /// does not involve committing it.
    private func sidebarToolStrip(_ controller: PhotoEditorController) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            ForEach(Self.sidebarToolGroups) { tool in
                let isActive = chrome.selectedGroup == tool
                Button {
                    withAnimation(EditorTheme.animation) {
                        selectGroup(isActive ? .light : tool, in: controller)
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tool.icon)
                            .font(.system(size: 15, weight: .medium))
                        Text(tool.title)
                            .font(EditorTheme.sidebarToolLabel)
                    }
                    .foregroundStyle(isActive ? Color.black : Color.white.opacity(0.9))
                    .frame(maxWidth: .infinity)
                    .frame(height: AppTheme.Size.minTouch)
                    .background {
                        if isActive {
                            RoundedRectangle.app(AppTheme.Radius.sm)
                                .fill(EditorTheme.accent)
                        }
                    }
                    .contentShape(RoundedRectangle.app(AppTheme.Radius.sm))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tool.title)
                .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.bottom, AppTheme.Spacing.sm)
    }

    /// Whether this group holds anything on this photo, for the header's dot.
    /// Compared against an untouched recipe rather than tracked separately, so
    /// undo and Reset All put the dots back on their own.
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
        case .crop:
            return recipe.crop != identity.crop
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
            // Grade acts on one tonal region at a time, so the region picker has
            // to come with it — without it the section quietly edits only
            // shadows.
            if group == .grade {
                targetStrip(for: group, controller: controller)
                    .frame(height: EditorLayoutMetrics.editorTargetStripHeight)
            }

            if group == .color {
                Picker("Colour controls", selection: colorSegmentBinding(controller)) {
                    Text("Basic").tag(EditorGroup.color)
                    Text("Mix").tag(EditorGroup.colorMix)
                    Text("Point").tag(EditorGroup.pointColor)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.bottom, AppTheme.Spacing.sm)

                toolPanelContent(for: colorSegment, controller: controller)
            } else {
                toolPanelContent(for: group, controller: controller)
            }

            // The graph goes in the panel, not on the photo: the sidebar is wide
            // enough for a usable plot, and a picture with a grid drawn across it
            // is not what a big screen is for.
            if group == .curve {
                sidebarCurveGraph(controller)
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
                stageRect: rect
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
                // Opening Light while Crop is up must not close the crop frame:
                // the strip above owns the stage, the stack below only owns
                // parameters. Colour keeps whichever segment was last showing.
                if activeStageTool == nil {
                    selectGroup(group == .color ? colorSegment : group, in: controller)
                }
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
        showsDocumentControls: Bool = false
    ) -> some View {
        let sideInset = EditorLayoutMetrics.editorFloatingCommandSideInset
        let buttonSize = EditorLayoutMetrics.editorFloatingCommandButtonSize
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
            HStack(spacing: 5) {
                if showsDocumentControls {
                    backButton(controller)
                    if isSidebarHidden, sidebarEdge == .leading {
                        showSidebarCommand
                    }
                }

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

                // Fixed reserve for the island; keeps the pill clear of the cutout.
                Color.clear.frame(width: reserve)

                // The pill (or, while the card floats, a clear stand-in so the ⋯
                // does not shift) stretches from the island out to the ⋯, at the
                // buttons' full height.
                Group {
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

                overflowMenu(controller, showsSidebarControls: showsDocumentControls)

                if showsDocumentControls {
                    if isSidebarHidden, sidebarEdge == .trailing {
                        showSidebarCommand
                    }
                    saveButton(controller)
                }
            }
            .frame(height: showsDocumentControls ? 42 : buttonSize)
            .padding(.horizontal, sideInset)
            .padding(.top, EditorLayoutMetrics.editorFloatingCommandRowTopInset)
            .frame(height: bandHeight, alignment: .top)
        }
        .frame(height: bandHeight)
        .background(EditorTheme.background)
    }

    /// Brings a collapsed sidebar back. It lives in the band rather than floating
    /// over the photo: the stage owns every touch inside its own bounds (zoom,
    /// pan, mask painting, crop handles), and a button laid over it there never
    /// sees the tap — measured on iPad. The band is the one strip of chrome that
    /// always answers.
    private var showSidebarCommand: some View {
        circleCommand(sidebarEdge.collapseIcon, isEnabled: true) {
            isSidebarHidden = false
        }
        .accessibilityLabel("Show Tools")
    }

    /// Hold-to-see-original, mirroring the photo's own press-and-hold. Down shows
    /// the original, up restores the edit; the circle turns accent while it is held.
    private func beforeAfterButton(_ controller: PhotoEditorController) -> some View {
        let size = EditorLayoutMetrics.editorFloatingCommandButtonSize
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
        let size = EditorLayoutMetrics.editorFloatingCommandButtonSize
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
        let size = EditorLayoutMetrics.editorFloatingCommandButtonSize
        return Menu {
            if showsSidebarControls {
                Picker("Tools Panel", selection: $sidebarEdgeRaw) {
                    ForEach(EditorSidebarEdge.allCases) { edge in
                        Text(edge.title).tag(edge.rawValue)
                    }
                }
                .pickerStyle(.menu)

                Button {
                    isSidebarHidden.toggle()
                } label: {
                    Label(
                        isSidebarHidden ? "Show Tools" : "Hide Tools",
                        systemImage: sidebarEdge.collapseIcon
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

            Button {
                controller.applyAutoTone()
            } label: {
                Label("Auto Enhance", systemImage: "wand.and.stars")
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
                chrome.isHistorySheetPresented = true
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
        .accessibilityLabel("More editor actions")
    }

    // MARK: Panel

    /// The Turn 31 panel: one opaque slab of fixed height. Top to bottom — the
    /// parameter zone (its first row is the Grade target strip when shown, so the
    /// zone, and the panel, stay one height on every tab), then the group strip (a
    /// snap wheel flanked by Back and Save), then a bare home-indicator inset. No
    /// command row: it moved to the band. No blur, no glass; the image never shows
    /// through it.
    private func panel(_ controller: PhotoEditorController, height: CGFloat) -> some View {
        let hasTarget = panelHasTargetStrip(controller)
        let rowsHeight = EditorLayoutMetrics.editorParamAreaHeight(
            hasTargetStrip: hasTarget
        )
        return VStack(spacing: 0) {
            // Parameter zone: fixed total height, the target strip eating into it
            // rather than adding to the panel.
            VStack(spacing: 0) {
                if hasTarget {
                    targetStrip(controller)
                        .frame(height: EditorLayoutMetrics.editorTargetStripHeight)
                }
                toolPanel(controller)
                    .frame(height: rowsHeight)
            }
            .frame(height: EditorLayoutMetrics.editorParamZoneHeight)

            groupStripRow(controller)
                .frame(height: EditorLayoutMetrics.editorGroupStripHeight)
            // Bare home-indicator zone: the wheel above takes only horizontal
            // swipes, so the system's vertical bottom-edge gesture never fights it.
            Color.clear.frame(height: EditorLayoutMetrics.editorPanelSafeAreaInset)
        }
        .frame(height: height)
        .background(EditorTheme.panelSolid)
        .overlay(alignment: .top) {
            Rectangle().fill(EditorTheme.panelTopHairline).frame(height: 1)
        }
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
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                }
        default:
            EmptyView()
        }
    }

    // MARK: Back / Save (group-strip ends)

    /// Back: a 38pt chevron on the leading end of the group strip, discard-guarded
    /// when the session has changes.
    private func backButton(_ controller: PhotoEditorController) -> some View {
        Button {
            if controller.hasSessionChanges {
                isDiscardConfirmationPresented = true
            } else {
                dismiss()
            }
        } label: {
            Image(systemName: "chevron.backward")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.6))
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }

    /// Save (✓): the one accent control on the screen, a 42pt filled circle on the
    /// trailing end of the group strip. Commits a draft crop first, then opens the
    /// save sheet.
    private func saveButton(_ controller: PhotoEditorController) -> some View {
        Button {
            controller.commitCropSession()
            isSaveSheetPresented = true
        } label: {
            Image(systemName: "checkmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 42, height: 42)
                .background(EditorTheme.accent, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(controller.isLoading || controller.isSaving)
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
                saveLook: {
                    lookName = dependencies.lookPresets.suggestedName()
                    isSaveLookPresented = true
                }
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
        case .crop:
            EditorCropPanel(controller: controller)
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
    private func selectGroup(_ group: EditorGroup, in controller: PhotoEditorController) {
        chrome.resetZoom()
        chrome.isEyedropperActive = false
        // 30c has no crop Done: the crop stays live and is committed when its tab is
        // left (or when the edit is saved). Switching to any other group is that
        // moment. Leaving via Save commits too, so a double commit is harmless.
        if chrome.selectedGroup == .crop, group != .crop {
            controller.commitCropSession()
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
        case .pointColor, .grade, .crop, .presets:
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
                            "Photos doesn't support an HEIC edited rendition for this asset. ShotDex will save a maximum-quality JPEG.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    }
                } footer: {
                    Text("Save Copy is full resolution at maximum quality. Turning off metadata strips EXIF and clears the Photos date/location on Save Changes. If Photos doesn't support HEIC for this asset, ShotDex falls back to JPEG and tells you.")
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
                    Text("Save Changes is non-destructive: Photos keeps the original and ShotDex reopens this asset with the saved crop, sliders and masks. A Live Photo keeps its motion. Save Copy creates a still image.")
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
                guard let new, new != chrome.selectedGroup else { return }
                onSelect(new)
            }
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

