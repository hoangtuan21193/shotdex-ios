import PencilKit
import Photos
import SwiftUI

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
    @State private var isCurveEditorPresented = false
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

                // The only thing allowed over the image is the histogram card, and
                // only when the user taps the band mini open — every other control
                // lives in the panel's command row. It parks back to the mini on
                // tap / close.
                EditorImageStage(
                    controller: controller,
                    chrome: chrome,
                    drawSession: drawSession
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        GeometryReader { proxy in
                            if !chrome.isHistogramCollapsed {
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

    // MARK: Floating command band

    /// The band over the Dynamic Island, carrying the floating command row. The
    /// island splits it: undo / redo / hold-for-original on the leading edge, the
    /// histogram mini and the ⋯ menu on the trailing edge. Both clusters are inset
    /// `editorFloatingCommandSideInset` from their screen edge so the outermost disc
    /// clears the device's rounded corner; they can still butt right up against the
    /// island in the middle. Every control is a 34pt circle — this is where the
    /// panel's old command row went. The histogram mini taps to expand the card.
    private func commandBand(
        _ controller: PhotoEditorController,
        height bandHeight: CGFloat
    ) -> some View {
        let sideInset = EditorLayoutMetrics.editorFloatingCommandSideInset
        let buttonSize = EditorLayoutMetrics.editorFloatingCommandButtonSize
        return GeometryReader { geo in
            // The three left discs plus their two 5pt gaps. The pill starts just
            // right of the Dynamic Island, so the fixed reserve is the run from the
            // end of that cluster to there; the pill then flexes out to the ⋯.
            let leftClusterWidth = buttonSize * 3 + 5 * 2
            let reserve = max(
                0,
                EditorLayoutMetrics.editorHistogramPillLeading(bandWidth: geo.size.width)
                    - sideInset - leftClusterWidth
            )
            HStack(spacing: 5) {
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

                overflowMenu(controller)
            }
            .frame(height: buttonSize)
            .padding(.horizontal, sideInset)
            .padding(.top, EditorLayoutMetrics.editorFloatingCommandRowTopInset)
            .frame(height: bandHeight, alignment: .top)
        }
        .frame(height: bandHeight)
        .background(EditorTheme.background)
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
    private func overflowMenu(_ controller: PhotoEditorController) -> some View {
        let size = EditorLayoutMetrics.editorFloatingCommandButtonSize
        return Menu {
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

    @ViewBuilder
    private func targetStrip(_ controller: PhotoEditorController) -> some View {
        switch chrome.selectedGroup {
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

    @ViewBuilder
    private func toolPanel(_ controller: PhotoEditorController) -> some View {
        switch chrome.selectedGroup {
        case .light:
            lightContent(controller)
        case .effects, .detail, .optics, .geo:
            adjustmentContent(chrome.selectedGroup, controller: controller)
        case .color:
            colorContent(controller)
        case .colorMix:
            EditorColorMixerSection(controller: controller, chrome: chrome)
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
            HStack(spacing: 8) {
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

    /// The Color group: the base Temp / Tint / Vibrance / Saturation rows. The HSL
    /// mixer is now its own nav chip (`.colorMix`), not a sub-view reached from a
    /// row here.
    private func colorContent(_ controller: PhotoEditorController) -> some View {
        EditorAdjustmentGroupsView(
            controller: controller,
            chrome: chrome,
            groups: catalogGroups(for: .color, controller: controller)
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
        case .light, .color, .colorMix, .effects, .detail, .optics, .geo:
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
/// panel colour. The centred chip is accent-tinted; the rest are dim. Every change
/// gives a selection haptic.
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
            .overlay { notchRail }
        }
    }

    /// The selection indicator: a rail across the top of the wheel that dips into a
    /// rounded pocket around the chip at the centre — the open group nests in the
    /// notch, the rest sit under the rail. Fixed at the centre; chips scroll through
    /// the pocket. Solid accent, drawn *over* the edge fades so it stays fully
    /// coloured out to both ends of the wheel.
    private var notchRail: some View {
        WheelNotchRail(
            pocketWidth: EditorLayoutMetrics.editorGroupChipWidth + 10,
            pocketHeight: EditorLayoutMetrics.editorGroupChipHeight + 8,
            corner: 10
        )
        .stroke(EditorTheme.accent, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        .allowsHitTesting(false)
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

/// The wheel's selection indicator, drawn as one stroked path: a horizontal rail
/// near the top that detours down into a rounded-bottom pocket cradling the
/// centred chip, then returns to the rail. The pocket is centred in `rect`; the
/// selected chip is always there.
private struct WheelNotchRail: Shape {
    /// Width of the pocket's flat bottom span — chip width plus a little breathing
    /// room each side.
    let pocketWidth: CGFloat
    /// Height of the pocket — the chip height plus a little room, so the whole chip
    /// (icon *and* label) nests inside the notch.
    let pocketHeight: CGFloat
    /// Corner radius of the four pocket bends.
    let corner: CGFloat

    func path(in rect: CGRect) -> Path {
        // Pocket is centred on the chip row; the rail runs level with the pocket's
        // top edge and the pocket dips one chip-height-plus below it.
        let cy = rect.midY
        let railY = cy - pocketHeight / 2
        let pocketBottom = cy + pocketHeight / 2
        let cx = rect.midX
        let half = pocketWidth / 2
        let r = min(corner, (pocketBottom - railY) / 2, half)

        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: railY))
        p.addLine(to: CGPoint(x: cx - half - r, y: railY))
        // Rail dips into the left wall.
        p.addQuadCurve(
            to: CGPoint(x: cx - half, y: railY + r),
            control: CGPoint(x: cx - half, y: railY)
        )
        p.addLine(to: CGPoint(x: cx - half, y: pocketBottom - r))
        // Bottom-left bend.
        p.addQuadCurve(
            to: CGPoint(x: cx - half + r, y: pocketBottom),
            control: CGPoint(x: cx - half, y: pocketBottom)
        )
        p.addLine(to: CGPoint(x: cx + half - r, y: pocketBottom))
        // Bottom-right bend.
        p.addQuadCurve(
            to: CGPoint(x: cx + half, y: pocketBottom - r),
            control: CGPoint(x: cx + half, y: pocketBottom)
        )
        p.addLine(to: CGPoint(x: cx + half, y: railY + r))
        // Right wall climbs back to the rail.
        p.addQuadCurve(
            to: CGPoint(x: cx + half + r, y: railY),
            control: CGPoint(x: cx + half, y: railY)
        )
        p.addLine(to: CGPoint(x: rect.maxX, y: railY))
        return p
    }
}
