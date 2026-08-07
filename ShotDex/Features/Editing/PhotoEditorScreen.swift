import PencilKit
import Photos
import SwiftUI

/// Photo editor: top bar, photo, fixed panel (action row + tool content + tab bar).
///
/// The panel height is fixed for the whole session — it does not change when the
/// list scrolls, when the tab changes, when a mask is opened, or while a slider is
/// being dragged. Only full-bleed takes it away. The chrome claims both safe
/// areas so the photo gets that height: the first row sits level with the Dynamic
/// Island and the tab bar sits close to the bottom edge. The histogram floats over
/// the photo when expanded and parks in the top bar when collapsed. Every session
/// opens on the Adjust tab. The top bar carries only Cancel and Done; everything
/// that acts on the session lives in the panel's fixed action row, in reach of a
/// thumb.
struct PhotoEditorScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppDependencies.self) private var dependencies

    let asset: PHAsset
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
    @State private var chrome = EditorChromeModel()
    @State private var isSaveSheetPresented = false
    @State private var isDiscardConfirmationPresented = false
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
    /// Whether the group nav's paging arrow has jumped to the end (chevron flips to
    /// page back to the start).
    @State private var groupNavAtEnd = false
    @State private var isCurveEditorPresented = false

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
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .fullScreenCover(isPresented: $isCurveEditorPresented) {
            if let controller {
                EditorCurveEditor(controller: controller) {
                    isCurveEditorPresented = false
                }
            }
        }
        .task {
            guard controller == nil else { return }
            let newController = PhotoEditorController(
                asset: asset,
                sourceAlbum: sourceAlbum,
                service: dependencies.photoEditing,
                metadata: metadata
            )
            // Every session opens on Adjust: the tab the user left last time is
            // rarely the one they want on a different photo.
            newController.selectedTool = .adjust
            controller = newController
            await newController.load()
        }
        .onDisappear {
            controller?.close()
        }
        .interactiveDismissDisabled(controller?.hasSessionChanges == true)
        .confirmationDialog(
            "Discard this editing session?",
            isPresented: $isDiscardConfirmationPresented,
            titleVisibility: .visible
        ) {
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
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
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
        return GeometryReader { _ in
            // 28c: the panel is one fixed 246pt slab glued to the bottom. The image
            // takes everything above it and is never overlapped by it.
            let panelHeight = EditorLayoutMetrics.editorPanelFixedHeight
            // The editor claims the top safe area itself: the chrome starts level
            // with the Dynamic Island rather than under it.
            VStack(spacing: 0) {
                // Drawing is a full takeover, like Crop: Cancel / Save step aside and
                // a Clear / Done bar takes the top, clear of the tool picker below.
                if controller.isEditingDrawing {
                    drawTopBar(controller)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else if !chrome.isFullBleed {
                    topBar(controller)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // 28c: the image is never overlapped — no floating pods. Every
                // control (session, crop, mask) lives in the panel's action bar.
                EditorImageStage(
                    controller: controller,
                    chrome: chrome,
                    drawSession: drawSession
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // No bottom panel while drawing: the tool picker owns that space and
                // Clear / Done live in the top bar.
                if !chrome.isFullBleed, !controller.isEditingDrawing {
                    panel(controller, height: panelHeight)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
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
        .sheet(isPresented: $isSaveSheetPresented) {
            PhotoEditorSaveSheet(controller: controller) {
                isSaveSheetPresented = false
                // Announced here, once, not in the fallback alert's OK button:
                // the JPEG fallback still saved an asset worth revealing.
                if let savedAssetID = controller.savedAssetID {
                    onSaved?(savedAssetID)
                }
                if controller.didFallbackToJPEG {
                    isFallbackNoticePresented = true
                } else {
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

    // MARK: Top bar

    /// Only `Cancel` and `Done`, level with the Dynamic Island and on either side
    /// of it, inside what would otherwise be dead safe-area space. Every other
    /// action lives in the panel's action row, within thumb reach.
    private func topBar(_ controller: PhotoEditorController) -> some View {
        HStack(spacing: 6) {
            Button("Cancel") {
                if controller.hasSessionChanges {
                    isDiscardConfirmationPresented = true
                } else {
                    dismiss()
                }
            }
            .font(.system(size: 16))
            .foregroundStyle(EditorTheme.secondaryText)
            .frame(minWidth: 56, minHeight: 44, alignment: .leading)

            Spacer(minLength: 0)

            Button("Save") {
                // Saving is a confirmation of what is on screen, so a crop still in
                // draft is kept rather than dropped by the tab switch behind us.
                controller.commitCropSession()
                isSaveSheetPresented = true
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(EditorTheme.accent)
            .frame(minWidth: 52, minHeight: 44, alignment: .trailing)
            .disabled(controller.isLoading || controller.isSaving)
        }
        // Wider than the rest of the chrome: these two sit at the very top of a
        // rounded display, where flush-to-the-edge reads as cramped.
        .padding(.horizontal, 26)
        .padding(.top, EditorLayoutMetrics.dynamicIslandRowTopInset)
        .background(EditorTheme.background)
    }

    /// The drawing sub-mode's own top bar: Clear and Done sit up here, level with
    /// the Dynamic Island, because the `PKToolPicker` owns the bottom of the screen
    /// and would otherwise cover a bottom action row.
    private func drawTopBar(_ controller: PhotoEditorController) -> some View {
        HStack(spacing: 6) {
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


    /// The `⋯` menu at the right of the action bar. History lives here now (rather
    /// than as its own bar button, per 28c's five-slot right group), alongside the
    /// conditional Recall and RAW/JPEG source actions.
    private func overflowMenu(_ controller: PhotoEditorController) -> some View {
        Menu {
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
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.78))
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More editor actions")
    }

    // MARK: Panel

    /// The 28c panel: one opaque slab of fixed height, four stacked tiers that never
    /// reorder — action bar, the tool content, and the group nav (a target strip
    /// joins in later modes). No blur, no glass; the image never shows through it.
    private func panel(_ controller: PhotoEditorController, height: CGFloat) -> some View {
        let navHeight = EditorLayoutMetrics.editorGroupNavHeight
            + EditorLayoutMetrics.panelBottomInset
        let contentHeight = max(
            0,
            height - EditorLayoutMetrics.editorActionBarHeight - navHeight
        )
        return VStack(spacing: 0) {
            actionBar(controller)
            toolPanel(controller)
                .frame(height: contentHeight)
            groupNav(controller)
                .padding(.bottom, EditorLayoutMetrics.panelBottomInset)
        }
        .frame(height: height)
        .background(EditorTheme.panelSolid)
        .overlay(alignment: .top) {
            Rectangle().fill(EditorTheme.panelTopHairline).frame(height: 1)
        }
    }

    // MARK: Action bar

    /// The panel's top row (28c): a mini histogram parked at the left, and a
    /// trailing control group that swaps with the mode. Solid, not glass, always in
    /// the same place — tool-specific actions join this row rather than floating a
    /// second bar over the photo. Crop shows its rotate / flip / reset / done here;
    /// every other group shows the session controls.
    private func actionBar(_ controller: PhotoEditorController) -> some View {
        HStack(spacing: 0) {
            EditorHistogramSparkline(histogram: controller.histogram)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .frame(
                    width: EditorLayoutMetrics.editorMiniHistogramSize.width,
                    height: EditorLayoutMetrics.editorMiniHistogramSize.height
                )
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel("RGB histogram")

            Spacer(minLength: 0)

            if controller.selectedTool == .crop {
                cropBarControls(controller)
            } else if controller.editingMaskAdjustments {
                maskBarControls(controller)
            } else {
                sessionBarControls(controller)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: EditorLayoutMetrics.editorActionBarHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(EditorTheme.panelDivider).frame(height: 1)
        }
    }

    /// A single mask's controls, in the action bar instead of a glass pod: delete
    /// (leftmost, a full row from Done), add / subtract, invert, the red-overlay
    /// toggle, and Done. Size / Feather / Flow are rows in the panel below now, so
    /// they are not repeated here.
    private func maskBarControls(_ controller: PhotoEditorController) -> some View {
        let isSubtracting = controller.maskOperation == .subtract
        return HStack(spacing: 2) {
            barButton("trash", isEnabled: true) {
                controller.deleteSelectedMask()
                chrome.resetZoom()
                controller.closeSelectedMaskAdjustments()
            }
            .accessibilityLabel("Delete mask")

            barButton(
                isSubtracting ? "minus.circle" : "plus.circle",
                isEnabled: true,
                isActive: isSubtracting
            ) {
                controller.maskOperation = isSubtracting ? .add : .subtract
            }
            .accessibilityLabel(isSubtracting ? "Subtracting from mask" : "Adding to mask")

            barButton(
                "circle.lefthalf.filled",
                isEnabled: true,
                isActive: controller.selectedMask?.isInverted == true
            ) {
                controller.invertSelectedMask()
            }
            .accessibilityLabel("Invert mask")

            Button {
                controller.setMaskOverlay(!controller.showsMaskOverlay)
            } label: {
                Image(systemName: controller.showsMaskOverlay ? "circle.fill" : "circle.slash")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(
                        controller.showsMaskOverlay
                            ? Color(red: 1, green: 0.08, blue: 0.13)
                            : Color.white.opacity(0.78)
                    )
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show mask area")
            .accessibilityValue(controller.showsMaskOverlay ? "Shown" : "Hidden")

            Button {
                chrome.resetZoom()
                controller.closeSelectedMaskAdjustments()
            } label: {
                Text("Done")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 32)
                    .background(EditorTheme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Done with this mask")
        }
    }

    private func sessionBarControls(_ controller: PhotoEditorController) -> some View {
        HStack(spacing: 2) {
            barButton("arrow.uturn.backward", isEnabled: controller.canUndo) {
                controller.undo()
            }
            .accessibilityLabel("Undo")

            barButton("arrow.uturn.forward", isEnabled: controller.canRedo) {
                controller.redo()
            }
            .accessibilityLabel("Redo")

            barButton(
                "rectangle.split.2x1",
                isEnabled: controller.originalPreviewImage != nil,
                isActive: chrome.showsSplitCompare
            ) {
                withAnimation(EditorTheme.animation) {
                    chrome.showsSplitCompare.toggle()
                }
            }
            .accessibilityLabel("Compare")
            .accessibilityValue(chrome.showsSplitCompare ? "On" : "Off")

            barButton(
                "arrow.counterclockwise",
                isEnabled: !controller.recipe.isIdentity
            ) {
                controller.reset()
            }
            .accessibilityLabel("Reset all")

            overflowMenu(controller)
        }
    }

    /// Crop's controls, now in the action bar instead of a glass pod over the
    /// photo: rotate 90°, flip, Reset Crop, and Done. Done is the crop's only
    /// commit — leaving the group any other way still reverts the framing.
    private func cropBarControls(_ controller: PhotoEditorController) -> some View {
        let canReset = controller.recipe.crop != .identity
        return HStack(spacing: 2) {
            barButton("rotate.right", isEnabled: true) {
                controller.rotate()
            }
            .accessibilityLabel("Rotate 90 degrees")

            barButton(
                "arrow.left.and.right.righttriangle.left.righttriangle.right",
                isEnabled: true
            ) {
                controller.flip()
            }
            .accessibilityLabel("Flip horizontally")

            Button {
                controller.resetCrop()
            } label: {
                Text("Reset")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(canReset ? .white : Color.white.opacity(0.3))
                    .padding(.horizontal, 10)
                    .frame(height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canReset)
            .accessibilityLabel("Reset crop")

            Button {
                controller.commitCropSession()
                selectGroup(.light, in: controller)
            } label: {
                Text("Done")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 32)
                    .background(EditorTheme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Done cropping")
        }
    }

    private func barButton(
        _ systemName: String,
        isEnabled: Bool,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(
                    isEnabled ? Color.white.opacity(0.78) : Color.white.opacity(0.24)
                )
                .frame(width: 40, height: 40)
                .background(
                    isActive ? Color.white.opacity(0.09) : .clear,
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    @ViewBuilder
    private func toolPanel(_ controller: PhotoEditorController) -> some View {
        switch chrome.selectedGroup {
        case .light:
            lightContent(controller)
        case .effects, .detail, .optics, .geo:
            adjustmentContent(chrome.selectedGroup, controller: controller)
        case .color:
            colorContent(controller)
        case .pointColor:
            EditorPointColorSection(controller: controller, chrome: chrome)
        case .grade:
            EditorColorGradingSection(controller: controller, chrome: chrome)
        case .presets:
            EditorFiltersPanel(controller: controller, chrome: chrome)
        case .markup:
            // The detail panel shows only when explicitly opened. A merely selected
            // layer keeps the list up and is moved / resized / rotated on the photo.
            if !controller.showsOverlayDetail || controller.selectedOverlay == nil {
                EditorTextPanel(
                    controller: controller,
                    chrome: chrome,
                    addText: { startTextEntry(controller, isNew: true) },
                    addImage: { isImagePickerPresented = true },
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
        controller: PhotoEditorController
    ) -> some View {
        let groups = catalogGroups(for: group, controller: controller)
        if groups.isEmpty {
            placeholderContent(group)
        } else {
            EditorAdjustmentGroupsView(
                controller: controller,
                chrome: chrome,
                groups: groups
            )
        }
    }

    private func catalogGroups(
        for group: EditorGroup,
        controller: PhotoEditorController
    ) -> [EditorAdjustmentGroup] {
        let all = EditorAdjustmentCatalog.groups(
            isRAWSource: controller.isRAWSource,
            scope: .global
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
        VStack(spacing: 6) {
            Image(systemName: group == .optics ? "camera.aperture" : "grid")
                .font(.system(size: 24))
                .foregroundStyle(EditorTheme.dimText)
            Text("\(group.title) — coming soon")
                .font(EditorTheme.rowLabel)
                .foregroundStyle(EditorTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The Light group: the tone rows with a Curve entry beneath them that opens
    /// the full-screen point-curve editor.
    private func lightContent(_ controller: PhotoEditorController) -> some View {
        EditorAdjustmentGroupsView(
            controller: controller,
            chrome: chrome,
            groups: catalogGroups(for: .light, controller: controller)
        ) {
            curveEntry(controller)
        }
    }

    private func curveEntry(_ controller: PhotoEditorController) -> some View {
        Button {
            isCurveEditorPresented = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(EditorTheme.secondaryText)
                Text("Curve")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                if !controller.recipe.curve.isIdentity {
                    Circle()
                        .fill(EditorTheme.accent)
                        .frame(width: 6, height: 6)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EditorTheme.secondaryText)
            }
            .padding(.horizontal, 14)
            .frame(height: EditorLayoutMetrics.editorRowHeight + 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The Color group: the base Temp / Tint / Vibrance / Saturation rows with a
    /// Color Mix entry beneath them, or the HSL mixer itself once that entry is
    /// tapped. (The §6 target-strip mixer form and the B&W toggle land with the
    /// parity work; this keeps the existing mixer reachable in the new layout.)
    @ViewBuilder
    private func colorContent(_ controller: PhotoEditorController) -> some View {
        if chrome.showsColorMix {
            VStack(spacing: 0) {
                colorMixBackBar
                EditorColorMixerSection(controller: controller, chrome: chrome)
            }
        } else {
            EditorAdjustmentGroupsView(
                controller: controller,
                chrome: chrome,
                groups: catalogGroups(for: .color, controller: controller)
            ) {
                colorMixEntry
            }
        }
    }

    private var colorMixEntry: some View {
        Button {
            withAnimation(EditorTheme.animation) { chrome.showsColorMix = true }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "circle.hexagongrid")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(EditorTheme.secondaryText)
                Text("Color Mix")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EditorTheme.secondaryText)
            }
            .padding(.horizontal, 14)
            .frame(height: EditorLayoutMetrics.editorRowHeight + 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var colorMixBackBar: some View {
        Button {
            withAnimation(EditorTheme.animation) { chrome.showsColorMix = false }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                Text("Color Mix")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(EditorTheme.accent)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The 28c bottom nav: 12 group chips in a horizontal scroll, with a paging
    /// arrow pinned to the right edge. Plain-text chips (accent-tinted when
    /// selected), no icons. The selected group is scrolled into view whenever it
    /// changes — including programmatic returns like Crop's Done.
    private func groupNav(_ controller: PhotoEditorController) -> some View {
        ScrollViewReader { scroller in
            ZStack(alignment: .trailing) {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(EditorGroup.allCases) { group in
                            groupChip(group, in: controller).id(group)
                        }
                    }
                    .padding(.horizontal, 12)
                    // Clear the paging arrow so the last chip is never under it.
                    .padding(.trailing, 36)
                    .frame(height: EditorLayoutMetrics.editorGroupNavHeight)
                }
                .scrollIndicators(.hidden)
                .onChange(of: chrome.selectedGroup) { _, group in
                    withAnimation(EditorTheme.animation) {
                        scroller.scrollTo(group, anchor: .center)
                    }
                }
                .onAppear {
                    scroller.scrollTo(chrome.selectedGroup, anchor: .center)
                }

                navArrow(scroller: scroller)
            }
        }
        .frame(height: EditorLayoutMetrics.editorGroupNavHeight)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1)
        }
    }

    private func groupChip(
        _ group: EditorGroup,
        in controller: PhotoEditorController
    ) -> some View {
        let isSelected = chrome.selectedGroup == group
        return Button {
            selectGroup(group, in: controller)
        } label: {
            Text(group.title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? EditorTheme.accent : EditorTheme.secondaryText)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(
                    isSelected ? EditorTheme.accent.opacity(0.16) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 9)
                )
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Pages the nav a screenful at a time. First tap jumps to the end (chevron
    /// flips); the next returns to the start. A rough stand-in for true per-page
    /// paging that reads the same to a thumb.
    private func navArrow(scroller: ScrollViewProxy) -> some View {
        Button {
            withAnimation(EditorTheme.animation) {
                if groupNavAtEnd {
                    scroller.scrollTo(EditorGroup.allCases.first, anchor: .leading)
                } else {
                    scroller.scrollTo(EditorGroup.allCases.last, anchor: .trailing)
                }
            }
            groupNavAtEnd.toggle()
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.62))
                .rotationEffect(.degrees(groupNavAtEnd ? 180 : 0))
                .frame(width: 36)
                .frame(maxHeight: .infinity)
                .background(
                    LinearGradient(
                        colors: [EditorTheme.panelSolid.opacity(0), EditorTheme.panelSolid],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More groups")
    }

    private func undoToastView(
        _ controller: PhotoEditorController,
        toast: EditorChromeModel.UndoToast
    ) -> some View {
        HStack(spacing: 10) {
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
        chrome.showsColorMix = false
        chrome.mixerChannel = nil
        withAnimation(EditorTheme.animation) {
            chrome.selectedGroup = group
        }
        switch group {
        case .light, .color, .effects, .detail, .optics, .geo:
            controller.editGlobalAdjustments()
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
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
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
