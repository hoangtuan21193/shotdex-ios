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
        controller.recipe.masks.isEmpty || chrome.isChoosingMaskKind || chrome.maskAreaOperation != nil
    }

    var body: some View {
        Group {
            if Self.showsChooser(controller: controller, chrome: chrome) {
                EditorMaskChooser(controller: controller, chrome: chrome)
            } else if chrome.isMaskListOpen {
                EditorMaskList(controller: controller, chrome: chrome)
            } else {
                EditorMaskDetailPanel(controller: controller, chrome: chrome, rename: rename)
            }
        }
        .onAppear(perform: keepAMaskOpen)
        // Leaving the Mask tab ends a half-made "+" and closes the list:
        // coming back shows the selected mask.
        .onDisappear {
            chrome.isChoosingMaskKind = false
            chrome.isMaskListOpen = false
            chrome.maskAreaOperation = nil
        }
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

/// "Choose an area to adjust": a 4-column grid of every kind (FS-03.13c §1),
/// 60pt tiles under a one-line title, scrolling vertically when the panel
/// shows fewer rows than there are. One tap makes the mask. A kind that
/// cannot work on this photo is dimmed; tapping it puts the reason where the
/// title was for 3s instead of making an empty mask. Long-press a tile for
/// what the kind does.
struct EditorMaskChooser: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel
    @State private var noticeTask: Task<Void, Never>?

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                header
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: Self.tileSpacing),
                        count: EditorNewMaskOption.gridColumns
                    ),
                    spacing: Self.tileSpacing
                ) {
                    ForEach(EditorNewMaskOption.gridOrder) { option in
                        chip(option)
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.lg)
        }
        .scrollIndicators(.hidden)
        .onDisappear { noticeTask?.cancel() }
    }

    /// FS-03.13c §1: 60pt tiles, 8 apart.
    static let tileSpacing: CGFloat = 8
    static let tileHeight = EditorKindTileLabel.height
    static let headerHeight: CGFloat = 32

    /// Whole rows a zone of `height` shows under the title; the rest scroll.
    static func visibleRows(in height: CGFloat) -> Int {
        Int((height - headerHeight + tileSpacing) / (tileHeight + tileSpacing))
    }

    /// "Choose an area to adjust" — or, from `+` with masks already there,
    /// `‹` and "New Mask". For 3s after a refused tap, the reason instead.
    /// The title: an area for the selected mask, a new mask, or the first.
    private var title: String {
        if let operation = chrome.maskAreaOperation {
            return EditorMaskListRow.chooserTitle(for: operation, maskName: controller.selectedMask?.name ?? "")
        }
        return controller.recipe.masks.isEmpty ? "Choose an area to adjust" : "New Mask"
    }

    /// Back from an area grid is the list it came from; from `+` the mask.
    private func goBack() {
        if chrome.maskAreaOperation != nil {
            chrome.maskAreaOperation = nil
        } else {
            chrome.isChoosingMaskKind = false
        }
    }

    /// One tap made the mask or the area: back to the selected mask, list shut.
    private func finish() {
        chrome.isChoosingMaskKind = false
        chrome.maskAreaOperation = nil
        chrome.isMaskListOpen = false
        chrome.maskChooserNotice = nil
        controller.editSelectedMaskAdjustments()
    }

    private var header: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            if !controller.recipe.masks.isEmpty {
                Button {
                    goBack()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(EditorTheme.chipIdle, in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                        .frame(width: 44, height: Self.headerHeight, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(chrome.maskAreaOperation == nil ? "Back to masks" : "Back to the list")
            }
            Text(chrome.maskChooserNotice ?? title)
                .font(.system(size: 13, weight: controller.recipe.masks.isEmpty ? .regular : .semibold))
                .foregroundStyle(controller.recipe.masks.isEmpty || chrome.maskChooserNotice != nil ? Color.white.opacity(0.6) : .white)
                .lineLimit(2)
                .minimumScaleFactor(EditorLayoutMetrics.editorPanelRowMinimumScale)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(height: Self.headerHeight)
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
                            if part.needsSemanticMatte, !available.contains(part) {
                                showNotice("Needs a Portrait photo taken on iPhone")
                            } else if let operation = chrome.maskAreaOperation {
                                controller.addMaskArea(option: .people, operation: operation, person: row.person, part: part)
                                finish()
                            } else if let reason = controller.addPeopleMask(person: row.person, part: part) {
                                showNotice(reason)
                            } else {
                                finish()
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
            EditorKindTileLabel(title: EditorNewMaskOption.people.shortTitle, systemImage: EditorNewMaskOption.people.systemImage)
        }
        .buttonStyle(EditorKindTileStyle())
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
            } else if let operation = chrome.maskAreaOperation {
                controller.addMaskArea(option: option, operation: operation)
                finish()
            } else {
                controller.addMask(option: option)
                finish()
            }
        } label: {
            EditorKindTileLabel(title: option.shortTitle, systemImage: option.systemImage)
        }
        .buttonStyle(EditorKindTileStyle())
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

/// Every mask, opened from the name in the top row (FS-03.13c §2): a 40pt
/// row each; under the selected one its areas and Add / Subtract / Intersect
/// area; New Mask last. A tap picks and closes; 👁 hides or shows that mask.
struct EditorMaskList: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel

    var body: some View {
        let masks = controller.recipe.masks
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                Text("Masks · \(masks.count) \(masks.count == 1 ? "mask" : "masks")")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 32)
                    .accessibilityAddTraits(.isHeader)
                ForEach(EditorMaskListRow.rows(masks: masks, selected: controller.selectedMaskID), id: \.self) { row in
                    rowView(row)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.lg)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func rowView(_ row: EditorMaskListRow) -> some View {
        switch row {
        case let .mask(id):
            if let mask = controller.recipe.masks.first(where: { $0.id == id }) {
                maskRow(mask)
            }
        case let .area(maskID, componentID):
            if let component = controller.recipe.masks.first(where: { $0.id == maskID })?
                .components.first(where: { $0.id == componentID }) {
                action(
                    title: MaskAreaSummary.name(of: component),
                    systemImage: component.operation.symbolName,
                    isSelected: controller.selectedComponentID == componentID,
                    isIndented: true
                ) {
                    controller.selectComponent(componentID)
                    close()
                }
            }
        case let .addArea(operation):
            action(
                title: EditorMaskListRow.title(of: operation),
                systemImage: operation.symbolName,
                isSelected: false,
                isIndented: true,
                isDim: true
            ) {
                chrome.maskAreaOperation = operation
            }
        case .newMask:
            action(title: "New Mask", systemImage: "plus", isSelected: false, isIndented: false) {
                chrome.isMaskListOpen = false
                chrome.isChoosingMaskKind = true
            }
        }
    }

    private func maskRow(_ mask: PhotoMask) -> some View {
        let isSelected = controller.selectedMaskID == mask.id
        return HStack(spacing: AppTheme.Spacing.sm) {
            Button {
                controller.selectMask(mask.id)
                close()
            } label: {
                HStack(spacing: AppTheme.Spacing.sm) {
                    EditorMaskThumbnail(controller: controller, mask: mask, side: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(mask.name)
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(MaskAreaSummary.subtitle(for: mask))
                            .font(.system(size: 11.5))
                            .foregroundStyle(EditorTheme.secondaryText)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(mask.name), \(MaskAreaSummary.subtitle(for: mask))")
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Button {
                controller.toggleMaskVisibility(mask.id)
            } label: {
                Image(systemName: mask.isVisible ? "eye" : "eye.slash")
                    .font(.system(size: 15))
                    .foregroundStyle(mask.isVisible ? Color.white : EditorTheme.dimText)
                    .frame(width: 44, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(mask.isVisible ? "Hide \(mask.name)" : "Show \(mask.name)")
        }
        .padding(.leading, AppTheme.Spacing.sm)
        .frame(height: 40)
        .background(isSelected ? Color.white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
    }

    private func action(
        title: String,
        systemImage: String,
        isSelected: Bool,
        isIndented: Bool,
        isDim: Bool = false,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                    .frame(width: 30)
                Text(title)
                    .font(.system(size: 14))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isDim ? Color.white.opacity(0.6) : .white)
            .padding(.leading, isIndented ? 30 : AppTheme.Spacing.sm)
            .frame(height: 40)
            .background(isSelected ? Color.white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func close() {
        withAnimation(EditorTheme.animation) { chrome.isMaskListOpen = false }
        controller.editSelectedMaskAdjustments()
    }
}

/// The Mask tool's top row (FS-03.13c §2): the selected mask's thumbnail,
/// its name ▼ over the areas it holds, Mask Overlay, `+` (the one way to a new
/// mask) and `⋯`. The name opens the list of masks (`chrome.isMaskListOpen`).
struct EditorMaskTopRow: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel
    let rename: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            if let mask = controller.selectedMask {
                Button {
                    withAnimation(EditorTheme.animation) { chrome.isMaskListOpen.toggle() }
                } label: {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        EditorMaskThumbnail(controller: controller, mask: mask, side: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(mask.name)
                                    .font(.system(size: 14.5, weight: .semibold))
                                    .lineLimit(1)
                                Image(systemName: chrome.isMaskListOpen ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            Text(subtitle(of: mask))
                                .font(.system(size: 11.5))
                                .foregroundStyle(EditorTheme.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(mask.name), \(subtitle(of: mask))")
                .accessibilityHint("Shows every mask")
                .layoutPriority(1)
            }

            Button {
                controller.setMaskOverlay(!controller.isMaskOverlayPinned)
            } label: {
                Text("Mask Overlay")
                    .fixedSize()
            }
            .buttonStyle(EditorChipButtonStyle(isSelected: controller.isMaskOverlayPinned))
            .accessibilityAddTraits(controller.isMaskOverlayPinned ? .isSelected : [])

            Button {
                chrome.isMaskListOpen = false
                chrome.isChoosingMaskKind = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(EditorTheme.chipIdle, in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                    .frame(width: 38, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New mask")

            EditorMaskActionsMenu(controller: controller, rename: rename, deleteMask: {
                controller.deleteSelectedMask()
                chrome.resetZoom()
            }, isChip: true)
        }
        .padding(.leading, AppTheme.Spacing.lg)
        .padding(.trailing, AppTheme.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The areas, or "Subtracting" while a subtracted area is the one being
    /// worked on.
    private func subtitle(of mask: PhotoMask) -> String {
        MaskAreaSummary.topRowSubtitle(for: mask, selectedComponent: controller.selectedComponentID)
    }
}

/// A mask's matte as a thumbnail (its kind's glyph until the matte exists),
/// dimmed while its effect is off, a spinner while detection runs.
struct EditorMaskThumbnail: View {
    @Bindable var controller: PhotoEditorController
    let mask: PhotoMask
    let side: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
        shape
            .fill(EditorTheme.chipIdle)
            .frame(width: side, height: side)
            .overlay {
                if let image = controller.maskThumbnails[mask.id] {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: side, height: side)
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
    }
}
