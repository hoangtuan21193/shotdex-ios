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

/// "Choose an area to adjust": a 4-column grid of every kind, one tap makes
/// the mask. A kind that cannot work on this photo is dimmed; tapping it
/// puts the reason where the title was for 3s instead of making an empty mask.
/// Long-press a chip for what the kind does (the old sheet's explainer line).
struct EditorMaskChooser: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel
    @State private var noticeTask: Task<Void, Never>?

    var body: some View {
        // Every kind on screen at once, 4 × 4 (FS-03.15d AC-52): three
        // scrolling rows hid half of them past the right edge. Four 44pt rows
        // fill the panel, so the title and the way back sit in the two slots
        // the fourteen kinds leave free at the end.
        let rows = stride(from: 0, to: EditorNewMaskOption.gridOrder.count, by: EditorNewMaskOption.gridColumns).map {
            Array(EditorNewMaskOption.gridOrder[$0..<min($0 + EditorNewMaskOption.gridColumns, EditorNewMaskOption.gridOrder.count)])
        }
        VStack(spacing: 0) {
            // No vertical spacing: each tile carries half the gap above and
            // below as touch area, so a 40pt tile answers a 44pt target.
            Grid(horizontalSpacing: Self.tileSpacing, verticalSpacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(row) { option in
                            chip(option)
                        }
                        if row.count < EditorNewMaskOption.gridColumns {
                            header
                                .gridCellColumns(EditorNewMaskOption.gridColumns - row.count)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .onDisappear { noticeTask?.cancel() }
    }

    static let tileSpacing: CGFloat = 4
    /// Drawn height; the touch area adds `tileSpacing` for 44pt.
    static let tileHeight: CGFloat = 40

    /// The grid's last, wide cell: the title — or for 3s the reason a kind
    /// cannot work here — and, once there are masks, the way back to them.
    private var header: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Text(chrome.maskChooserNotice ?? "Choose an area to adjust")
                .font(.system(size: 12))
                .foregroundStyle(EditorTheme.secondaryText)
                .lineLimit(2)
                .minimumScaleFactor(EditorLayoutMetrics.editorPanelRowMinimumScale)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !controller.recipe.masks.isEmpty {
                Button {
                    chrome.isChoosingMaskKind = false
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: Self.tileHeight)
                        .background(EditorTheme.chipIdle, in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to masks")
            }
        }
        .frame(height: Self.tileHeight)
        .padding(.vertical, Self.tileSpacing / 2)
        .animation(EditorTheme.animation, value: chrome.maskChooserNotice)
    }

    /// People opens its list instead of making a mask: All People and
    /// Person 1…4, each with its parts (FS-03.15d §3). A part the photo
    /// cannot make says why in the header and makes nothing.
    private var peopleChip: some View {
        let available = controller.availableSemanticParts
        return Menu {
            ForEach(PhotoEditorController.peopleRows(count: controller.peopleCount ?? 0), id: \.title) { row in
                Menu(row.title) {
                    ForEach(PhotoPersonPart.allCases) { part in
                        Button {
                            if let reason = controller.addPeopleMask(person: row.person, part: part) {
                                showNotice(reason)
                            } else {
                                chrome.isChoosingMaskKind = false
                                chrome.maskChooserNotice = nil
                                controller.editSelectedMaskAdjustments()
                            }
                        } label: {
                            if part.needsSemanticMatte, !available.contains(part) {
                                Text(part.displayName)
                                Text("Needs a Portrait photo taken on iPhone")
                            } else {
                                Text(part.displayName)
                            }
                        }
                    }
                }
            }
        } label: {
            EditorMaskKindTileLabel(option: .people)
        }
        .buttonStyle(EditorMaskKindTileStyle())
        .accessibilityLabel(EditorNewMaskOption.people.title)
        .onAppear { controller.countPeopleIfNeeded() }
    }

    @ViewBuilder
    private func chip(_ option: EditorNewMaskOption) -> some View {
        if option == .people {
            peopleChip
        } else {
            plainChip(option)
        }
    }

    private func plainChip(_ option: EditorNewMaskOption) -> some View {
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
            EditorMaskKindTileLabel(option: option)
        }
        .buttonStyle(EditorMaskKindTileStyle())
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

/// One tile of the mask-kind grid: the kind's glyph over its short name.
private struct EditorMaskKindTileLabel: View {
    let option: EditorNewMaskOption

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: option.systemImage)
                .font(.system(size: 17))
            Text(option.shortTitle)
                .font(.system(size: 11))
                .lineLimit(1)
                .minimumScaleFactor(EditorLayoutMetrics.editorPanelRowMinimumScale)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: EditorMaskChooser.tileHeight)
    }
}

/// The chip's idle fill and pressed dim, on a grid tile, with half the
/// grid's gap above and below as touch area.
private struct EditorMaskKindTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
        configuration.label
            .background(EditorTheme.chipIdle, in: shape)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .padding(.vertical, EditorMaskChooser.tileSpacing / 2)
            .contentShape(Rectangle())
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
                .frame(
                    minWidth: EditorLayoutMetrics.editorThumbnailStripNameMinWidth,
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .padding(.leading, AppTheme.Spacing.xs)

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
