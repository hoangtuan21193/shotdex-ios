import Photos
import SwiftUI

/// Immutable payload for presenting the collage editor. Assets live inside the
/// item (see `CompressionPresentation`) so the cover never opens against an
/// older, empty snapshot.
struct CollagePresentation: Identifiable {
    let id = UUID()
    /// Images only, pick order, 2–9 of them.
    let assets: [PHAsset]
}

/// Full-screen collage editor (DESIGN.md tier D, Turn 5). Top to bottom: a
/// floating command band across the Dynamic Island, the Unplaced tray (hidden
/// when empty), the centred collage stage, and a fixed 216pt panel whose content
/// zone switches between Layout / Style / Text while the bottom bar (tabs +
/// Export) stays put. The screen is a thin shell — state lives in
/// `CollageEditorModel`, panel content in `CollagePanelViews`.
struct CollageScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppDependencies.self) private var dependencies

    let assets: [PHAsset]
    /// Called with the new asset id after a successful export, so the presenter
    /// can open the new photo's detail (§12).
    var onSaved: (String) -> Void = { _ in }

    @State private var model: CollageEditorModel?
    @State private var isExportPresented = false
    @State private var isDiscardConfirmationPresented = false
    @State private var fillingCellIndex: Int?
    @State private var editingOverlay: PhotoOverlay?
    @State private var isAddingText = false
    @State private var isFontPickerPresented = false
    @State private var isSavingPreset = false
    @State private var presetNameDraft = ""
    @State private var renamingPreset: CollagePreset?
    @State private var renameDraft = ""

    var body: some View {
        modals(rootContent)
    }

    // Split from `body` so the type-checker infers the root chain and the
    // sheet/alert chain separately — one long modifier chain otherwise trips
    // "unable to type-check in reasonable time".
    private var rootContent: some View {
        ZStack {
            EditorTheme.background.ignoresSafeArea()
            if let model {
                editor(model)
            } else {
                ProgressView()
            }
        }
        .preferredColorScheme(.dark)
        // Hide the system clock/battery and let the command band ride up level
        // with the Dynamic Island, like the photo editor.
        .statusBarHidden(true)
        .task {
            guard model == nil else { return }
            let newModel = CollageEditorModel(
                assets: assets,
                photoLibrary: dependencies.photoLibrary,
                indexPipeline: dependencies.indexPipeline,
                overlayFontRecents: dependencies.overlayFontRecents,
                presetStore: dependencies.collagePresets
            )
            model = newModel
            newModel.loadPreviews()
        }
        .interactiveDismissDisabled(model?.hasEdits == true || model?.isExporting == true)
        .fullScreenCover(isPresented: $isExportPresented) {
            if let model {
                CollageExportScreen(model: model, onClose: { isExportPresented = false })
            }
        }
        .onChange(of: model?.didSaveAssetID) { _, assetID in
            if let assetID {
                onSaved(assetID)
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func modals<Content: View>(_ content: Content) -> some View {
        content
        .confirmationDialog(
            "Discard this collage?",
            isPresented: $isDiscardConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
        .alert(
            "Collage Error",
            isPresented: Binding(
                get: { model?.errorMessage != nil },
                set: { if !$0 { model?.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model?.errorMessage ?? "")
        }
        .sheet(item: fillSheetBinding) { target in
            if let model {
                CollageMediaPicker(
                    model: model,
                    photoLibrary: dependencies.photoLibrary,
                    slotCapacity: max(1, model.emptySlotCount)
                ) { assetIDs in
                    model.fillSlots(startingAt: target.index, with: assetIDs)
                }
                .presentationDetents([.large])
                .presentationCornerRadius(AppTheme.Radius.xxl)
                .presentationBackground(EditorTheme.panelSolid)
            }
        }
        .alert("Save Preset", isPresented: $isSavingPreset) {
            TextField("Name", text: $presetNameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") { model?.saveCurrentAsPreset(named: presetNameDraft) }
        } message: {
            Text("Saves the frame and style — not the photos or text.")
        }
        .alert("Rename Preset", isPresented: renameAlertBinding) {
            TextField("Name", text: $renameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let preset = renamingPreset { model?.renamePreset(preset.id, to: renameDraft) }
            }
        }
        .sheet(isPresented: $isFontPickerPresented) {
            if let model {
                EditorFontPickerSheet(
                    recents: dependencies.overlayFontRecents.recents,
                    current: model.lastFont
                ) { choice in
                    model.rememberFont(choice)
                    model.updateSelectedOverlay { overlay in
                        overlay.fontPostScriptName = choice.postScriptName
                        overlay.fontFamilyName = choice.familyName
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $isAddingText) {
            EditorInlineTextEditor(
                initialText: "",
                tokens: .empty,
                alignment: .center,
                onCommit: { text in
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { model?.addTextOverlay(trimmed) }
                    isAddingText = false
                },
                onCancel: { isAddingText = false }
            )
        }
        .fullScreenCover(item: $editingOverlay) { overlay in
            EditorInlineTextEditor(
                initialText: overlay.text,
                tokens: .empty,
                alignment: overlay.alignment,
                onCommit: { text in
                    model?.updateSelectedOverlay { $0.text = text }
                    editingOverlay = nil
                },
                onCancel: { editingOverlay = nil }
            )
        }
    }

    // MARK: - Layout

    private func editor(_ model: CollageEditorModel) -> some View {
        ZStack(alignment: .bottom) {
            // The canvas layout stays structurally constant while a photo is
            // lifted — the tray only appears for genuinely unplaced photos, never
            // as a side effect of the hold. The lift's drop target and HUD are
            // overlays, so `beginLift` never rebuilds the canvas out from under
            // the live gesture (which was cancelling it, leaving photos stuck).
            VStack(spacing: 0) {
                CollageCommandBand(model: model)

                if !model.unplaced.isEmpty {
                    CollageUnplacedTray(model: model, photoLibrary: dependencies.photoLibrary)
                        .frame(height: CollageMetrics.trayHeight)
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.top, AppTheme.Spacing.xs)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                CollageCanvasView(
                    model: model,
                    onFillRequest: { index in fillingCellIndex = index },
                    onEditText: { overlay in
                        model.selectedOverlayID = overlay.id
                        editingOverlay = overlay
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                panel(model)
            }
            // Reclaim the top safe area so the command band sits beside the
            // Dynamic Island rather than below the status bar.
            .ignoresSafeArea(.container, edges: .top)

            if model.isLiftingCell {
                CollageSwapHUD()
                    .padding(.bottom, CollageMetrics.panelHeight + AppTheme.Spacing.md)
            } else if let message = model.undoToastMessage {
                CollageUndoToast(message: message) {
                    withAnimation(EditorTheme.animation) { model.undo(); model.undoToastMessage = nil }
                }
                .padding(.bottom, CollageMetrics.panelHeight + AppTheme.Spacing.md)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: message) {
                    try? await Task.sleep(for: .seconds(4))
                    model.undoToastMessage = nil
                }
            }
        }
        // The set-aside drop banner is an overlay — it must not sit in the VStack
        // flow, or showing it would resize/rebuild the canvas mid-gesture.
        .overlay(alignment: .top) {
            if model.isLiftingCell {
                CollageDropBanner()
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.top, CollageMetrics.commandBandHeight + AppTheme.Spacing.xs)
            }
        }
        .animation(EditorTheme.panelSpring, value: model.unplaced.isEmpty)
        .animation(EditorTheme.animation, value: model.isLiftingCell)
        .animation(EditorTheme.animation, value: model.undoToastMessage)
    }

    /// Leaves the editor — straight out if untouched, via a discard prompt if not.
    private func close(_ model: CollageEditorModel) {
        if model.hasEdits {
            isDiscardConfirmationPresented = true
        } else {
            dismiss()
        }
    }

    private func panel(_ model: CollageEditorModel) -> some View {
        VStack(spacing: 0) {
            panelContent(model)
                .frame(height: CollageMetrics.panelContentHeight)
            CollageBottomBar(
                model: model,
                onBack: { close(model) },
                onExport: { isExportPresented = true }
            )
            .frame(height: CollageMetrics.panelBottomBarHeight)
            Color.clear.frame(height: CollageMetrics.panelSafeAreaInset)
        }
        .frame(height: CollageMetrics.panelHeight)
        .background(EditorTheme.panelSolid)
        .overlay(alignment: .top) {
            Rectangle().fill(EditorTheme.panelTopHairline).frame(height: 1)
        }
    }

    @ViewBuilder
    private func panelContent(_ model: CollageEditorModel) -> some View {
        switch model.panelGroup {
        case .layout:
            CollageLayoutPanel(
                model: model,
                onSavePreset: {
                    presetNameDraft = ""
                    isSavingPreset = true
                },
                onRenamePreset: { preset in
                    renameDraft = preset.name
                    renamingPreset = preset
                }
            )
        case .style:
            CollageStylePanel(model: model)
        case .text:
            CollageTextPanel(
                model: model,
                onAddText: { isAddingText = true },
                onEditText: { overlay in
                    model.selectedOverlayID = overlay.id
                    editingOverlay = overlay
                },
                onPickFont: { isFontPickerPresented = true }
            )
        }
    }

    // MARK: - Fill sheet plumbing

    private struct FillTarget: Identifiable {
        let index: Int
        var id: Int { index }
    }

    private var fillSheetBinding: Binding<FillTarget?> {
        Binding(
            get: { fillingCellIndex.map(FillTarget.init(index:)) },
            set: { fillingCellIndex = $0?.index }
        )
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renamingPreset != nil },
            set: { if !$0 { renamingPreset = nil } }
        )
    }
}

// MARK: - Command band

/// The floating command row flanking the Dynamic Island, like the photo editor:
/// Undo · Redo on the leading edge, the `N of M · ratio` status readout on the
/// trailing edge. No eye or ⋯ here — leaving the editor is the bottom-bar back
/// button; Export commits.
private struct CollageCommandBand: View {
    @Bindable var model: CollageEditorModel

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            CollageCircleButton(systemImage: "arrow.uturn.backward", isEnabled: model.canUndo) {
                withAnimation(EditorTheme.animation) { model.undo() }
            }
            .accessibilityLabel(String(localized: "Undo"))

            CollageCircleButton(systemImage: "arrow.uturn.forward", isEnabled: model.canRedo) {
                withAnimation(EditorTheme.animation) { model.redo() }
            }
            .accessibilityLabel(String(localized: "Redo"))

            Spacer(minLength: 0)

            EditorPillLabel(text: model.statusText)
        }
        .padding(.horizontal, AppTheme.Size.floatingChromeMargin)
        .padding(.top, EditorLayoutMetrics.editorFloatingCommandRowTopInset)
        .frame(height: EditorLayoutMetrics.editorFloatingCommandRowHeight
            + EditorLayoutMetrics.editorFloatingCommandRowTopInset)
    }
}

/// A round tier-D glass button; dimmed and inert when disabled (DESIGN.md §9).
struct CollageCircleButton: View {
    let systemImage: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CollageCircleGlyph(systemImage: systemImage, isEnabled: isEnabled)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

/// The glass disc + glyph shared by the round buttons and the ⋯ menu label.
struct CollageCircleGlyph: View {
    let systemImage: String
    var isActive: Bool = false
    var isEnabled: Bool = true

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(glyphColor)
            .frame(width: CollageMetrics.commandButtonSize, height: CollageMetrics.commandButtonSize)
            .background(isActive ? EditorTheme.accent : Color.clear, in: Circle())
            .editorGlass(Circle())
    }

    private var glyphColor: Color {
        if isActive { return .black }
        return isEnabled ? .white : .white.opacity(0.28)
    }
}

// MARK: - Bottom bar

/// The panel's bottom bar: the Layout/Style/Text group tabs and the Export pill
/// (§12) — Export is a labelled pill, not a round confirm, because it opens its
/// own screen rather than dismissing.
private struct CollageBottomBar: View {
    @Bindable var model: CollageEditorModel
    let onBack: () -> Void
    let onExport: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            backButton
            Spacer(minLength: AppTheme.Spacing.sm)
            HStack(spacing: AppTheme.Spacing.lg) {
                ForEach(CollageEditorModel.PanelGroup.allCases) { group in
                    groupTab(group)
                }
            }
            Spacer(minLength: AppTheme.Spacing.sm)
            exportButton
        }
        .padding(.horizontal, AppTheme.Size.screenMargin)
    }

    private var backButton: some View {
        Button(action: onBack) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: AppTheme.Size.minTouch, height: AppTheme.Size.minTouch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Close"))
    }

    private func groupTab(_ group: CollageEditorModel.PanelGroup) -> some View {
        Button {
            withAnimation(EditorTheme.animation) { model.panelGroup = group }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: group.systemImage)
                    .font(.system(size: 15, weight: .medium))
                Text(group.title)
                    .font(EditorTheme.tabLabel)
            }
            .foregroundStyle(model.panelGroup == group ? EditorTheme.accent : EditorTheme.dimText)
            .frame(minWidth: 52)
            .frame(maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(model.panelGroup == group ? .isSelected : [])
    }

    private var exportButton: some View {
        Button(action: onExport) {
            Group {
                if model.isExporting {
                    ProgressView().tint(.black)
                } else {
                    Text("Export")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black)
                }
            }
            .frame(height: CollageMetrics.exportPillHeight)
            .padding(.horizontal, AppTheme.Spacing.xl)
            .background(EditorTheme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.isExporting || model.template == nil || model.placedCount == 0)
        .opacity(model.template == nil || model.placedCount == 0 ? 0.4 : 1)
    }
}

// MARK: - Unplaced tray

/// Thumbnails of photos set aside from the collage (§3). Normally a plain strip;
/// while a photo is lifted it becomes the "set aside" drop target — dashed
/// yellow on a faint accent wash, its own photos dimmed, its label swapped for a
/// centred prompt (§7). It pulses once whenever a photo lands.
private struct CollageUnplacedTray: View {
    @Bindable var model: CollageEditorModel
    let photoLibrary: PhotoLibraryService

    @State private var flashActive = false

    var body: some View {
        strip
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .onChange(of: model.trayFlashToken) { _, _ in pulse() }
    }

    private var strip: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 0) {
                Text("UNPLACED")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                Text("\(model.unplaced.count)")
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
            }
            .foregroundStyle(EditorTheme.secondaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CollageMetrics.trayThumbnailSpacing) {
                    ForEach(model.unplaced, id: \.self) { id in
                        CollageTrayThumbnail(assetID: id, model: model, photoLibrary: photoLibrary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle.app(AppTheme.Radius.md)
        shape.fill(Color.white.opacity(0.05))
        shape.strokeBorder(EditorTheme.accent, lineWidth: flashActive ? 2 : 0)
    }

    private func pulse() {
        withAnimation(EditorTheme.animation) { flashActive = true }
        Task {
            try? await Task.sleep(for: .seconds(0.35))
            withAnimation(EditorTheme.animation) { flashActive = false }
        }
    }
}

/// The set-aside drop target shown at the top while a photo is lifted (§7). An
/// overlay, not part of the layout flow, so appearing it never disturbs the live
/// canvas gesture underneath.
private struct CollageDropBanner: View {
    var body: some View {
        Text("Drop here to set aside")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(EditorTheme.accent)
            .frame(maxWidth: .infinity)
            .frame(height: CollageMetrics.trayExpandedHeight)
            .background(
                RoundedRectangle.app(AppTheme.Radius.md).fill(EditorTheme.accent.opacity(0.1))
            )
            .overlay(
                RoundedRectangle.app(AppTheme.Radius.md)
                    .strokeBorder(EditorTheme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5]))
            )
            .allowsHitTesting(false)
    }
}

/// Bottom hint shown while a cell is lifted, naming the other branch of the
/// gesture so the tray's "set aside" prompt is not read as the only option (§7).
private struct CollageSwapHUD: View {
    var body: some View {
        Text("Or drop on another photo to swap")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .frame(height: AppTheme.Size.pillHeightDark)
            .editorGlass(Capsule())
            .allowsHitTesting(false)
    }
}

/// Toast confirming a set-aside, with a one-tap Undo (§4). Auto-dismissed by the
/// screen after a few seconds.
private struct CollageUndoToast: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
            Button(action: onUndo) {
                Text("Undo")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(EditorTheme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(height: AppTheme.Size.pillHeightLight)
        .editorGlass(Capsule())
    }
}

private struct CollageTrayThumbnail: View {
    let assetID: String
    @Bindable var model: CollageEditorModel
    let photoLibrary: PhotoLibraryService

    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle.app(AppTheme.Radius.sm)
            .fill(EditorTheme.control)
            .overlay {
                if let image = image ?? model.image(forAsset: assetID) {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .frame(width: CollageMetrics.trayThumbnailSize, height: CollageMetrics.trayThumbnailSize)
            .clipShape(RoundedRectangle.app(AppTheme.Radius.sm))
            .frame(width: AppTheme.Size.minTouch, height: AppTheme.Size.minTouch)
            .contentShape(Rectangle())
            .accessibilityLabel(String(localized: "Unplaced photo, drag to place"))
            // Drag a tray photo down onto a cell to place it there (§7).
            .draggable(assetID)
            .onAppear {
                guard model.image(forAsset: assetID) == nil, let asset = model.asset(id: assetID) else { return }
                _ = photoLibrary.requestThumbnail(
                    for: asset,
                    targetSize: CGSize(width: 120, height: 120),
                    allowNetwork: false
                ) { result in
                    if let result { image = result }
                }
            }
    }
}

