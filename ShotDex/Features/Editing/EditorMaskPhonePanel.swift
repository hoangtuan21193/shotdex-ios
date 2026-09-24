import SwiftUI
import ShotDexKit

/// The Mask tab on the phone panel (FS-03.05 §2–3). Two states, both inside the
/// panel: choosing a kind (no mask yet, or after `+`), and adjusting the selected
/// mask under the thumbnail strip. No sheet — a sheet covered the photo the user
/// was about to outline.
struct EditorMaskPhonePanel: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel
    let rename: () -> Void

    /// The chooser shows when there is nothing to adjust, or when `+` asked for it.
    static func showsChooser(controller: PhotoEditorController, chrome: EditorChromeModel) -> Bool {
        controller.recipe.masks.isEmpty || chrome.isChoosingMaskKind
    }

    var body: some View {
        Group {
            if Self.showsChooser(controller: controller, chrome: chrome) {
                EditorMaskChooser(controller: controller, chrome: chrome)
            } else {
                EditorMaskDetailPanel(controller: controller, chrome: chrome, rename: rename)
            }
        }
        .onAppear(perform: keepAMaskOpen)
        // Leaving the Mask tab ends a half-made "+": coming back shows the masks.
        .onDisappear { chrome.isChoosingMaskKind = false }
        .onChange(of: controller.recipe.masks.map(\.id)) { keepAMaskOpen() }
        .onChange(of: controller.editingMaskAdjustments) { keepAMaskOpen() }
    }

    /// On the phone there is no list level to fall back to: with masks present, one
    /// of them is always the one being adjusted (the last, after an undo or delete
    /// cleared the selection).
    private func keepAMaskOpen() {
        guard !controller.recipe.masks.isEmpty, !chrome.isChoosingMaskKind else { return }
        if controller.selectedMaskID == nil, let last = controller.recipe.masks.last {
            controller.selectMask(last.id)
        }
        if !controller.editingMaskAdjustments {
            controller.editSelectedMaskAdjustments()
        }
    }
}

/// "Choose an area to adjust": three rows of kind chips, each scrolling, one tap
/// makes the mask. A kind that cannot work on this photo is dimmed; tapping it
/// puts the reason where the title was for 3s instead of making an empty mask.
/// Long-press a chip for what the kind does (the old sheet's explainer line).
struct EditorMaskChooser: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel
    @State private var noticeTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ForEach(Array(EditorNewMaskOption.Row.allCases.enumerated()), id: \.offset) { _, row in
                ScrollView(.horizontal) {
                    HStack(spacing: EditorStripLayout.chipSpacing) {
                        ForEach(EditorNewMaskOption.options(in: row)) { option in
                            chip(option)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .frame(maxHeight: .infinity)
                }
                .scrollIndicators(.hidden)
                .frame(height: EditorLayoutMetrics.editorPanelRowHeight)
            }
            Spacer(minLength: 0)
        }
        .onDisappear { noticeTask?.cancel() }
    }

    private var header: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            if !controller.recipe.masks.isEmpty {
                Button {
                    chrome.isChoosingMaskKind = false
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to masks")
            }
            Text(chrome.maskChooserNotice ?? "Choose an area to adjust")
                .font(.system(size: 13))
                .foregroundStyle(EditorTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(EditorLayoutMetrics.editorPanelRowMinimumScale)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(height: EditorLayoutMetrics.editorPanelRowHeight)
        .animation(EditorTheme.animation, value: chrome.maskChooserNotice)
    }

    private func chip(_ option: EditorNewMaskOption) -> some View {
        let reason = option.unavailableReason(
            hasDepth: controller.hasDepthSource,
            hasFaces: controller.hasFaces
        )
        return Button {
            if let reason {
                showNotice(reason)
            } else {
                chrome.isChoosingMaskKind = false
                chrome.maskChooserNotice = nil
                controller.addMask(option: option)
                controller.editSelectedMaskAdjustments()
            }
        } label: {
            EditorPanelChipLabel(title: option.shortTitle, systemImage: option.systemImage)
        }
        .buttonStyle(EditorChipButtonStyle(isSelected: false))
        .opacity(reason == nil ? 1 : EditorTheme.rowDisabled)
        .contextMenu {
            Text(reason ?? option.description)
        }
        .accessibilityLabel(option.title)
        .accessibilityHint(reason ?? option.description)
    }

    private func showNotice(_ text: String) {
        noticeTask?.cancel()
        chrome.maskChooserNotice = text
        noticeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            chrome.maskChooserNotice = nil
        }
    }
}

/// The phone panel's Mask target strip: every mask as a 40×30 matte thumbnail
/// (white ring on the selected one, 35% when its effect is off), `+` for another
/// mask, the selected mask's name, and its `⋯` menu. The strip follows the
/// selection when it changes without a tap here (a new mask, Duplicate, Undo).
struct EditorMaskStrip: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel
    let rename: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(controller.recipe.masks) { mask in
                            thumbnail(mask).id(mask.id)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .onChange(of: controller.selectedMaskID) { _, id in
                    guard let id else { return }
                    withAnimation(EditorTheme.animation) { proxy.scrollTo(id, anchor: .center) }
                }
                .onAppear {
                    if let id = controller.selectedMaskID { proxy.scrollTo(id, anchor: .center) }
                }
            }
            .frame(maxWidth: CGFloat(controller.recipe.masks.count) * 48)
            .layoutPriority(1)

            Button {
                chrome.isChoosingMaskKind = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(EditorTheme.chipIdle, in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                    .frame(width: 44, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New mask")

            Text(controller.selectedMask?.name ?? "")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, AppTheme.Spacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)

            EditorMaskActionsMenu(controller: controller, rename: rename) {
                controller.deleteSelectedMask()
                chrome.resetZoom()
            }
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func thumbnail(_ mask: PhotoMask) -> some View {
        let isSelected = controller.selectedMaskID == mask.id
        let shape = RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
        return Button {
            controller.selectMask(mask.id)
            controller.editSelectedMaskAdjustments()
        } label: {
            shape
                .fill(EditorTheme.chipIdle)
                .frame(width: 40, height: 30)
                .overlay {
                    if let image = controller.maskThumbnails[mask.id] {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 40, height: 30)
                            .clipShape(shape)
                    } else {
                        Image(systemName: mask.components.first?.kind.systemImage ?? "circle.dashed")
                            .font(.system(size: 13))
                            .foregroundStyle(EditorTheme.dimText)
                    }
                }
                .opacity(mask.isVisible ? 1 : EditorTheme.rowDisabled)
                .overlay {
                    if controller.isDetecting(mask: mask) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                }
                .padding(3.5)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm + 3.5, style: .continuous)
                            .strokeBorder(.white, lineWidth: 1.5)
                    }
                }
                .frame(width: 48, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mask.name)
        .accessibilityValue(mask.isVisible ? "" : "Hidden")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
