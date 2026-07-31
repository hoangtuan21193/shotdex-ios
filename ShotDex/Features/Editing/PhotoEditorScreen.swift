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
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .task {
            guard controller == nil else { return }
            let newController = PhotoEditorController(
                asset: asset,
                sourceAlbum: sourceAlbum,
                service: dependencies.photoEditing
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
    }

    private func editor(_ controller: PhotoEditorController) -> some View {
        @Bindable var chrome = chrome
        return GeometryReader { proxy in
            let panelHeight = EditorLayoutMetrics.panelHeight(forHeight: proxy.size.height)
            // The editor claims the top safe area itself: the chrome starts level
            // with the Dynamic Island rather than under it.
            VStack(spacing: 0) {
                if !chrome.isFullBleed {
                    topBar(controller)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                EditorImageStage(
                    controller: controller,
                    chrome: chrome,
                    histogramNamespace: histogramNamespace
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // The Size/Feather/Flow dialog floats at the bottom of the
                    // photo, directly above the action-row button that opened it.
                    // Anchored to the stage, not the row, so it covers letterbox
                    // and image edge rather than pushing the panel around.
                    .overlay(alignment: .bottom) {
                        if let control = chrome.activeMaskControl,
                           actionRowMode(controller) == .mask {
                            EditorMaskControlPopup(
                                controller: controller,
                                control: control
                            )
                            .padding(.horizontal, 12)
                            .padding(.bottom, 10)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(EditorTheme.animation, value: chrome.activeMaskControl)

                if !chrome.isFullBleed {
                    panel(controller, height: panelHeight)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .ignoresSafeArea(.container, edges: [.top, .bottom])
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
                // A gradient greets you with its guides; a fresh brush had
                // nothing until the first stroke. Opening the Size dialog (and
                // with it the centred footprint preview) is the brush's version
                // of "here is the shape, set it up before you commit".
                if kind == .brush {
                    chrome.activeMaskControl = .brushSize
                }
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

    /// Fixed row at the top of the panel. Two fixed slots: the parked histogram
    /// always at the leading edge, and a trailing group that swaps with the tool.
    /// The row's height never changes and the histogram never moves, so the pill
    /// stays the same target in every mode; only the buttons on the right slide.
    ///
    /// - Adjust / Filters: the whole session — undo, redo, compare, history, reset, `⋯`.
    /// - Crop: `Reset Crop` and `Done`, instead of a second row of buttons under
    ///   the ratio chips.
    /// - Single-mask editor: the shape controls — Size/Feather popup buttons, the
    ///   add/subtract toggle, the red-overlay eye and the `⋯` overflow. They used
    ///   to float over the photo; here they cover nothing. Navigating masks stays
    ///   in the panel's own nav row.
    private func actionRow(_ controller: PhotoEditorController) -> some View {
        HStack(spacing: 4) {
            histogramSlot(controller)

            Spacer(minLength: 0)

            ZStack(alignment: .trailing) {
                switch actionRowMode(controller) {
                case .crop:
                    cropActions(controller)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                case .mask:
                    EditorMaskShapeControls(controller: controller, chrome: chrome)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                case .session:
                    sessionActions(controller)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: EditorLayoutMetrics.actionRowHeight)
        // The groups slide past each other inside the row's own bounds — the row
        // itself keeps its height through every swap.
        .clipped()
        .animation(EditorTheme.animation, value: actionRowMode(controller))
        .overlay(alignment: .bottom) {
            Rectangle().fill(EditorTheme.hairline).frame(height: 0.5)
        }
    }

    private enum ActionRowMode: Equatable {
        case session
        case crop
        case mask
    }

    private func actionRowMode(_ controller: PhotoEditorController) -> ActionRowMode {
        if controller.selectedTool == .crop { return .crop }
        if controller.editingMaskAdjustments { return .mask }
        return .session
    }

    /// Reserved width at the leading edge, whether or not the pill is currently in
    /// it: when the histogram is expanded over the photo the trailing buttons must
    /// not shift sideways to fill the gap.
    private func histogramSlot(_ controller: PhotoEditorController) -> some View {
        ZStack(alignment: .leading) {
            if chrome.isHistogramCollapsed {
                EditorHistogramPill(
                    histogram: controller.histogram,
                    namespace: histogramNamespace
                ) {
                    withAnimation(EditorHistogramTransition.animation) {
                        chrome.isHistogramCollapsed = false
                    }
                }
            }
        }
        .frame(
            width: EditorLayoutMetrics.histogramCollapsedWidth,
            alignment: .leading
        )
    }

    /// Reset the frame, or leave Crop. Framing is written into the recipe on every
    /// drag, so `Done` commits nothing — it is there because a crop tool with no way
    /// out reads as unfinished.
    private func cropActions(_ controller: PhotoEditorController) -> some View {
        HStack(spacing: 6) {
            Button("Reset Crop") {
                controller.resetCrop()
            }
            .buttonStyle(EditorTextButtonStyle())
            .disabled(controller.recipe.crop == .identity)

            Button {
                select(.adjust, in: controller)
            } label: {
                Text("Done")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 30)
                    .background(EditorTheme.accent, in: Capsule())
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func sessionActions(_ controller: PhotoEditorController) -> some View {
        HStack(spacing: 4) {
            circleButton("arrow.uturn.backward", isEnabled: controller.canUndo) {
                controller.undo()
            }
            .accessibilityLabel("Undo")

            circleButton("arrow.uturn.forward", isEnabled: controller.canRedo) {
                controller.redo()
            }
            .accessibilityLabel("Redo")

            circleButton(
                "rectangle.split.2x1",
                isEnabled: controller.originalPreviewImage != nil,
                isSelected: chrome.showsSplitCompare
            ) {
                withAnimation(EditorTheme.animation) {
                    chrome.showsSplitCompare.toggle()
                }
            }
            .accessibilityLabel("Split compare")
            .accessibilityValue(chrome.showsSplitCompare ? "On" : "Off")

            circleButton("clock.arrow.circlepath", isEnabled: true) {
                chrome.isHistorySheetPresented = true
            }
            .accessibilityLabel("History")

            circleButton(
                "arrow.counterclockwise",
                isEnabled: !controller.recipe.isIdentity
            ) {
                controller.reset()
            }
            .accessibilityLabel("Reset all")

            overflowMenu(controller)
        }
    }

    private func circleButton(
        _ systemName: String,
        isEnabled: Bool,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    isSelected
                        ? EditorTheme.accent
                        : (isEnabled ? .white : Color.white.opacity(0.28))
                )
                .frame(width: 30, height: 30)
                .background(
                    isSelected ? EditorTheme.accent.opacity(0.18) : EditorTheme.control,
                    in: Circle()
                )
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    /// What is left over once undo/redo/compare/history/reset have their own
    /// buttons: recalling the recipe stored in Photos, and picking the RAW or JPEG
    /// source of a RAW+JPEG pair.
    private func overflowMenu(_ controller: PhotoEditorController) -> some View {
        Menu {
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

            Button {
                chrome.isNewMaskSheetPresented = true
            } label: {
                Label("New Mask", systemImage: "circle.dashed")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(EditorTheme.control, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More editor actions")
    }

    // MARK: Panel

    /// The panel keeps the same height for the whole session — including while a
    /// slider is being dragged. Only full-bleed takes it away.
    private func panel(_ controller: PhotoEditorController, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            actionRow(controller)
            toolPanel(controller)
                .frame(height: height - EditorLayoutMetrics.tabBarHeight)
            tabBar(controller)
                .padding(.bottom, EditorLayoutMetrics.panelBottomInset)
        }
        .background(EditorTheme.panel)
    }

    @ViewBuilder
    private func toolPanel(_ controller: PhotoEditorController) -> some View {
        switch controller.selectedTool {
        case .adjust:
            EditorAdjustmentGroupsView(
                controller: controller,
                chrome: chrome,
                groups: EditorAdjustmentCatalog.groups(
                    isRAWSource: controller.isRAWSource,
                    scope: .global
                )
            )
        case .color:
            EditorColorPanel(controller: controller, chrome: chrome)
        case .filters:
            EditorFiltersPanel(controller: controller, chrome: chrome)
        case .crop:
            EditorCropPanel(controller: controller)
        case .masks:
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
        case .cleanUp:
            EditorCleanUpPanel(controller: controller, chrome: chrome)
        }
    }

    private func tabBar(_ controller: PhotoEditorController) -> some View {
        HStack(spacing: 4) {
            ForEach(PhotoEditorTool.allCases) { tool in
                let isSelected = controller.selectedTool == tool
                Button {
                    select(tool, in: controller)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tool.systemImage)
                            .font(.system(size: 17, weight: .medium))
                        Text(tool.title)
                            .font(EditorTheme.tabLabel)
                            .fontWeight(isSelected ? .semibold : .regular)
                            // Six tabs leave about 56pt each on a 375pt screen,
                            // and "Clean Up" does not fit. Shrinking beats a
                            // silent truncation to "Clean U…".
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(isSelected ? EditorTheme.accent : EditorTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        isSelected ? EditorTheme.control : .clear,
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 10)
        // The selected pill has to clear the bottom edge: the panel now runs into
        // the home-indicator area, and a rounded highlight flush with the screen
        // reads as a rendering glitch.
        .padding(.bottom, 8)
        .frame(height: EditorLayoutMetrics.tabBarHeight)
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

    private func select(_ tool: PhotoEditorTool, in controller: PhotoEditorController) {
        chrome.resetZoom()
        chrome.isEyedropperActive = false
        switch tool {
        case .adjust:
            controller.editGlobalAdjustments()
        case .masks:
            controller.selectedTool = .masks
            controller.scheduleRender()
        case .color, .filters, .crop, .cleanUp:
            controller.selectedTool = tool
            controller.closeSelectedMaskAdjustments()
        }
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
