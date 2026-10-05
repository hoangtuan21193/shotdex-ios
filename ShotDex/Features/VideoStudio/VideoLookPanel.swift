import SwiftUI
import ShotDexKit

/// The Look panel's body (FS-12.06c §3): Filter · Adjust · Color, and under
/// Filter the photo editor's three shelves — Presets · My Looks · LUTs — as
/// tiles of the clip under the playhead, then Amount, Apply To, the line
/// that says what video skips, and Import Look….
///
/// One view for every window; `VideoLookPanelStyle` (from the environment)
/// carries what the boards draw differently: a scrolling row of 70pt tiles
/// on the phone, 60 on the Duo's cover, a 3-column grid of 66 in the Duo's
/// 264 column and of 103×50 in the iPad's 360 inspector.
struct VideoLookPanel: View {
    /// The whole video's Look tool, or a selected clip's Look block
    /// (LOOK FOR THIS CLIP, §3), reached from the clip's command row.
    enum Mode {
        case wholeVideo, clip
        /// A multi-select group's Look row (FS-12.11 §5): the shelf's tiles
        /// alone, one scrolling row, writing every clip of the group.
        case groupRow
    }

    @Bindable var model: VideoStudioModel
    var mode: Mode = .wholeVideo
    /// The Color tab's scopes draw taller in a column.
    var usesTallScopes = false

    @Environment(\.videoLookPanelStyle) private var style
    @Environment(AppDependencies.self) private var dependencies
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @State private var thumbnails = VideoLookThumbnails()
    /// Save as Look… (§6b): the naming prompt, and the name in it.
    @State private var isNamingLook = false
    @State private var lookName = ""

    var body: some View {
        Group {
            if mode == .groupRow {
                tiles
            } else if style.dockColumns {
                dockBody
            } else {
                stackBody
            }
        }
        .task(id: model.clipIndexUnderPlayhead) {
            thumbnails.refresh(for: model, photoLibrary: photoLibrary, cell: style.tile.width)
        }
        .onDisappear { thumbnails.cancel() }
        // Import Look… is the photo editor's own import (FS-03.14a): the
        // same picker, the same report, the same shelves.
        .fileImporter(
            isPresented: Binding(
                get: { dependencies.lookExchange.isPickingFiles },
                set: { dependencies.lookExchange.isPickingFiles = $0 }
            ),
            allowedContentTypes: LookExchangeModel.importTypes,
            allowsMultipleSelection: true
        ) { result in
            // Cancelling the picker changes nothing (§7).
            if case let .success(urls) = result { dependencies.lookExchange.startImport(urls, completion: imported) }
        }
        .sheet(isPresented: Binding(
            get: { dependencies.lookExchange.isSheetPresented },
            set: { if !$0 { dependencies.lookExchange.dismissReport() } }
        )) {
            LookImportReportSheet(model: dependencies.lookExchange)
        }
        // The photo editor's Save Look prompt (FS-03.02 §9): a blank name
        // cannot be saved, Cancel saves nothing, a name already in My Looks
        // is saved over. The message names what stays in the video.
        .alert(VideoStudioCopy.saveLookTitle, isPresented: $isNamingLook) {
            TextField(VideoStudioCopy.lookNameField, text: $lookName)
            Button(VideoStudioCopy.cancel, role: .cancel) {}
            Button(VideoStudioCopy.saveLook) {
                model.saveVideoLook(named: lookName, into: dependencies.lookPresets)
            }
            .disabled(lookName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text(VideoStudioCopy.saveLookMessage(notSaved: model.photoLookCut.notSaved))
        }
    }

    /// Every window but the iPad's portrait dock: one column, top to bottom.
    private var stackBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The iPad's clip header sits right under the command row's
            // rule (F5_IL_Looks).
            Color.clear.frame(height: mode == .clip && style.segmented ? 0 : style.topGap)
            if mode == .clip {
                clipHeader
                if !style.segmented {
                    // The phone's order (board F5_P_ClipLook): where the
                    // look goes comes first, under the header.
                    clipApplyRow
                    Color.clear.frame(height: 8)
                }
            }
            // The iPad's clip block is the shelves alone (F5_IL_Looks):
            // Adjust and Color are the whole video's, in its idle Look.
            if !(mode == .clip && style.segmented) {
                chipRow(VideoLookTab.allCases, selected: model.lookTab, height: style.tabHeight, title: { Text($0.title) }) {
                    model.lookTab = $0
                }
            }
            switch mode == .clip && style.segmented ? .filter : model.lookTab {
            case .filter: filterBody
            case .adjust: adjustBody
            case .color: VideoColorPanel(model: model, usesTallScopes: usesTallScopes)
            }
        }
    }

    // MARK: Portrait dock (FS-12.03 §3, boards IP1_Main, F5_IP_Looks)

    /// The iPad portrait dock has width and no height: the panel stands in
    /// three columns of 312, 32 apart, all seen at once. First column: the
    /// tabs (a clip: its header) and the shelves over the first row of
    /// tiles; second: the tiles that follow, Amount and the line under it;
    /// third: where the look goes, Import Look… and what it means. Adjust
    /// and Color keep the tabs in the first column and take the other two.
    private var dockBody: some View {
        let isClip = mode == .clip
        let tab: VideoLookTab = isClip ? .filter : model.lookTab
        return DockColumns(gap: VideoStudioDeskGeometry.dockColumnGap) {
            // First column.
            VStack(alignment: .leading, spacing: 0) {
                if isClip {
                    clipHeader
                } else {
                    chipRow(VideoLookTab.allCases, selected: model.lookTab, height: style.tabHeight, title: { Text($0.title) }) {
                        model.lookTab = $0
                    }
                }
                if tab == .filter {
                    Color.clear.frame(height: gapAfterHead)
                    shelfRow
                    Color.clear.frame(height: style.afterShelf)
                    dockTiles(Array(tileItems.prefix(style.columns ?? 3)))
                } else if tab == .adjust {
                    adjustSliders(Array(Self.adjustKinds.prefix(3)))
                }
                Spacer(minLength: 0)
            }
        } second: {
            VStack(alignment: .leading, spacing: 0) {
                switch tab {
                case .filter:
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            dockTiles(Array(tileItems.dropFirst(style.columns ?? 3)))
                            Color.clear.frame(height: style.afterTiles)
                            if VideoLookEditing.showsAmount(model.lookSlot), let look = model.lookSlot {
                                amountRow(look)
                            }
                            caption
                        }
                        .padding(.bottom, 8)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                case .adjust:
                    adjustSliders(Array(Self.adjustKinds.dropFirst(3)))
                case .color:
                    EmptyView()
                }
                Spacer(minLength: 0)
            }
        } third: {
            VStack(alignment: .leading, spacing: 0) {
                if tab == .filter {
                    Text(VideoStudioCopy.applyToTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, style.inset)
                        .frame(height: 24, alignment: .leading)
                    Color.clear.frame(height: 2)
                    applyTo
                    Color.clear.frame(height: 4)
                    importRow
                    if !isClip { saveRow }
                    Text(isClip ? VideoStudioCopy.clipLookExplainer : VideoStudioCopy.wholeVideoLookExplainer)
                        .font(.system(size: style.captionSize))
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, style.inset)
                } else if tab == .color {
                    VideoColorPanel(model: model, usesTallScopes: false)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Under the tabs, the tab row's gap; under the iPad's clip header —
    /// no tabs there, the shelves follow the 44pt header — 4 (F5_IL_Looks,
    /// F5_IP_Looks).
    private var gapAfterHead: CGFloat {
        mode == .clip && style.segmented ? 4 : style.afterTabs
    }

    private static let adjustKinds: [PhotoAdjustmentKind] = [.exposure, .contrast, .saturation, .warmth, .brightness, .vignette]

    private func adjustSliders(_ kinds: [PhotoAdjustmentKind]) -> some View {
        VStack(spacing: 0) {
            ForEach(kinds, id: \.self) { kind in
                let value = model.activeNode.adjustments[kind]
                InspectorSlider(
                    label: kind.displayName, value: value, range: -1...1,
                    valueText: String(format: "%+.0f", value * 100), anchor: 0, notch: true, detent: 0, model: model,
                    set: { model.setAdjustment(kind, value: $0) },
                    reset: { model.pushUndo(); model.setAdjustment(kind, value: 0) }
                )
            }
        }
        .padding(.top, style.afterTabs)
    }

    /// One run of the dock's tiles: three across the column, 10 apart.
    private func dockTiles(_ items: [VideoLookTile]) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: style.tileGap), count: style.columns ?? 3),
            alignment: .leading,
            spacing: style.tileRowGap
        ) {
            ForEach(items) { tile($0) }
        }
        .padding(.horizontal, style.inset)
        .onAppear { thumbnails.request(tileItems.map { ($0.id, $0.look) }) }
    }

    // MARK: Filter

    private var filterBody: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: gapAfterHead)
                shelfRow
                Color.clear.frame(height: style.afterShelf)
                tiles
                Color.clear.frame(height: style.afterTiles)
                if VideoLookEditing.showsAmount(model.lookSlot), let look = model.lookSlot {
                    amountRow(look)
                }
                if mode == .wholeVideo, !style.segmented, model.compare != nil { compareSection }
                if mode == .wholeVideo || style.segmented { applyTo }
                caption
                Color.clear.frame(height: 4)
                if !style.importsBesideShelf { importRow }
                if mode == .wholeVideo { saveRow }
            }
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// COMPARE under Amount while Before and After is on (FS-12.15 §4):
    /// Split · Hold to Compare on the phone and the cover (181×30), Side by
    /// Side · Split in the Duo's inner column (112×28), and the line that
    /// says what Before is — or that there is nothing to tell apart.
    @ViewBuilder
    private var compareSection: some View {
        if let compare = model.compare {
            let sideBySide = style == .duoInner
            VStack(alignment: .leading, spacing: 6) {
                if !sideBySide {
                    Text(VideoStudioCopy.compareHeader)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(EditorTheme.dimText)
                        .accessibilityAddTraits(.isHeader)
                }
                CaptionChipRow(
                    items: VideoBeforeAfter.modes(sideBySide: sideBySide).map { ($0, VideoStudioCopy.compareMode($0)) },
                    selection: compare.mode,
                    fills: true,
                    height: sideBySide ? 28 : 30
                ) { model.setCompareMode($0) }
                if !sideBySide {
                    Text(model.hasNothingToCompare
                         ? VideoStudioCopy.noEditsToCompare
                         : (compare.mode == .hold ? VideoStudioCopy.holdHint : VideoStudioCopy.splitHint))
                        .font(.system(size: style.captionSize))
                        .foregroundStyle(.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("compareCaption")
                }
            }
            .padding(.horizontal, style.inset)
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
    }

    private var shelfRow: some View {
        HStack(spacing: 8) {
            chipRow(EditorPresetSource.allCases, selected: model.lookShelf, height: style.shelfHeight, title: { Text(LocalizedStringKey($0.title)) }) {
                model.lookShelf = $0
            }
            // Beside Import, the shelves run up to its 8pt gap.
            .padding(.trailing, style.importsBesideShelf ? -style.inset : 0)
            if style.importsBesideShelf {
                Button { dependencies.lookExchange.isPickingFiles = true } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(VideoStudioCopy.importLook)
                .padding(.trailing, style.inset)
            }
        }
    }

    /// The shelf's tiles, built from the photo editor's own stores — the
    /// same looks, the same names, the same order.
    private var tileItems: [VideoLookTile] {
        VideoLookTile.tiles(
            shelf: model.lookShelf,
            includesOriginal: style.showsOriginalTile || model.lookShelf == .presets,
            looks: dependencies.lookPresets,
            luts: dependencies.importedLUTs
        )
    }

    @ViewBuilder
    private var tiles: some View {
        let items = tileItems
        Group {
            if let columns = style.columns {
                LazyVGrid(
                    columns: Array(
                        repeating: style.fillsColumns
                            ? GridItem(.flexible(), spacing: style.tileGap)
                            : GridItem(.fixed(style.tile.width), spacing: style.tileGap),
                        count: columns
                    ),
                    alignment: .leading,
                    spacing: style.tileRowGap
                ) {
                    ForEach(items) { tile($0) }
                }
                .padding(.horizontal, style.inset)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: style.tileGap) {
                        ForEach(items) { tile($0) }
                    }
                    .padding(.horizontal, style.inset)
                }
                .frame(height: style.tile.height + 5 + style.tileLabelSize + 4)
            }
        }
        .onAppear { thumbnails.request(items.map { ($0.id, $0.look) }) }
        .onChange(of: items.map(\.id)) { _, _ in thumbnails.request(tileItems.map { ($0.id, $0.look) }) }
        .onChange(of: thumbnails.baseAssetID) { _, _ in thumbnails.request(tileItems.map { ($0.id, $0.look) }) }
    }

    private func tile(_ item: VideoLookTile) -> some View {
        let isSelected = item.isChosen(in: model.lookSlot, slotIsClip: model.lookTarget != .allClips)
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return Button {
            model.chooseLook(item.look.source)
        } label: {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let image = thumbnails.images[item.id] {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            LinearGradient(
                                colors: item.swatch.map { Color(red: $0.red, green: $0.green, blue: $0.blue) },
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        }
                    }
                    .frame(width: style.fillsColumns ? nil : style.tile.width, height: style.tile.height)
                    .frame(maxWidth: style.fillsColumns ? .infinity : nil)
                    .clipShape(shape)
                    if item.isImported {
                        Text(verbatim: "XMP")
                            .font(.system(size: style.badgeSize, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.65)))
                            .padding(3)
                    }
                }
                .overlay { if isSelected { shape.strokeBorder(Color.white, lineWidth: 2).padding(-2) } }
                Text(verbatim: item.name(model.presetName))
                    .font(.system(size: style.tileLabelSize, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.55))
                    .lineLimit(1)
                    .frame(width: style.fillsColumns ? nil : style.tile.width + 8)
                    .frame(maxWidth: style.fillsColumns ? .infinity : nil)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VideoStudioCopy.lookTileLabel(name: item.name(model.presetName), isImported: item.isImported))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func amountRow(_ look: VideoLook) -> some View {
        InspectorSlider(
            label: VideoStudioCopy.amount, value: look.amount, range: 0...1,
            valueText: "\(Int((look.amount * 100).rounded()))", detent: 1, model: model,
            set: { model.setLookAmount($0) },
            reset: { model.pushUndo(); model.setLookAmount(1) }
        )
        .frame(height: style.amountHeight)
    }

    @ViewBuilder
    private var applyTo: some View {
        if style.showsApplyHeader {
            Text(VideoStudioCopy.applyTo)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, style.inset)
                .frame(height: 26, alignment: .top)
                .padding(.top, 6)
        }
        chipRow(
            mode == .clip ? VideoLookTarget.allCases : VideoLookTarget.wholeVideoTargets,
            selected: model.lookTarget, height: style.applyHeight, title: { Text($0.title) },
            isEnabled: { $0 != .selected || model.canTargetSelectedClips }
        ) {
            model.lookTarget = $0
        }
    }

    /// LOOK FOR THIS CLIP, and Use Video Look at its right while the clip
    /// has a look of its own — white, not accent: accent is Export's (§3).
    private var clipHeader: some View {
        HStack(spacing: 8) {
            Text(style.segmented ? VideoStudioCopy.lookForThisClip : VideoStudioCopy.lookForThisClip.uppercased())
                .font(.system(size: style.segmented ? 15 : 11, weight: style.segmented ? .semibold : .bold))
                .foregroundStyle(.white.opacity(style.segmented ? 1 : 0.7))
                .lineLimit(1)
            Spacer(minLength: 0)
            if model.lookSlot != nil {
                Button { model.useVideoLook() } label: {
                    Text(VideoStudioCopy.useVideoLook)
                        .font(.system(size: style.segmented ? 17 : 12.5, weight: style.segmented ? .regular : .semibold))
                        .foregroundStyle(.white)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(VideoStudioCopy.useVideoLookForThisClip)
            }
        }
        .padding(.horizontal, style.inset)
        .frame(height: style.segmented ? 44 : 28)
    }

    /// "Apply to" and This Clip · Selected · All Clips, on one row.
    private var clipApplyRow: some View {
        HStack(spacing: 8) {
            Text(VideoStudioCopy.applyToRow)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.leading, style.inset)
            chipRow(
                VideoLookTarget.allCases, selected: model.lookTarget, height: style.tabHeight,
                title: { Text($0.title) }, isEnabled: { $0 != .selected || model.canTargetSelectedClips }
            ) { model.lookTarget = $0 }
                .padding(.leading, -style.inset)
        }
    }

    private var caption: some View {
        let skipped = model.lookSlot.map { VideoLookEditing.skippedOnVideo($0.recipe) } ?? []
        let line: String = if let look = model.lookSlot, VideoLookEditing.isMissingLUT(look, lutExists: model.lutExists) {
            VideoStudioCopy.lookMissingLUT(VideoLookEditing.name(of: look, presetName: model.presetName))
        } else {
            VideoStudioCopy.lookSkippedLine(skipped)
        }
        return Text(line)
            .font(.system(size: style.captionSize))
            .foregroundStyle(.white.opacity(0.35))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, style.inset)
            .padding(.top, 6)
    }

    private var importRow: some View {
        listRow(VideoStudioCopy.importLook, systemImage: "square.and.arrow.down") {
            dependencies.lookExchange.isPickingFiles = true
        }
        #if DEBUG
        .onAppear { dependencies.lookExchange.importFixturesIfAsked(completion: imported) }
        #endif
    }

    /// Save as Look… (§6b), the whole video's only: dimmed while the video
    /// has nothing a photo would show — no look, no grade.
    private var saveRow: some View {
        listRow(VideoStudioCopy.saveAsLook, systemImage: "plus", isEnabled: !model.photoLookCut.isEmpty) {
            lookName = dependencies.lookPresets.suggestedName()
            isNamingLook = true
        }
    }

    /// A row of the panel's foot: icon, title, chevron — the phone's 42pt
    /// row, the iPad's 44 at 17pt (boards F5_P_Looks, IP1_Main).
    private func listRow(_ title: String, systemImage: String, isEnabled: Bool = true, action: @escaping () -> Void) -> some View {
        let isWide = style.segmented
        return Button(action: action) {
            HStack(spacing: isWide ? 12 : 10) {
                Image(systemName: systemImage)
                    .font(.system(size: isWide ? 17 : 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: isWide ? 20 : nil)
                Text(title)
                    .font(.system(size: isWide ? 17 : 12.5))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: isWide ? 14 : 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .opacity(isEnabled ? 1 : 0.35)
            .padding(.horizontal, style.inset)
            .frame(height: isWide ? 44 : 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func imported(_ report: PresetImportReport) {
        model.lookImported(report, looks: dependencies.lookPresets, luts: dependencies.importedLUTs)
    }

    // MARK: Adjust

    private var adjustBody: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(Self.adjustKinds, id: \.self) { kind in
                    let value = model.activeNode.adjustments[kind]
                    InspectorSlider(
                        label: kind.displayName, value: value, range: -1...1,
                        valueText: String(format: "%+.0f", value * 100), anchor: 0, notch: true, detent: 0, model: model,
                        set: { model.setAdjustment(kind, value: $0) },
                        reset: { model.pushUndo(); model.setAdjustment(kind, value: 0) }
                    )
                }
            }
            .padding(.top, style.afterTabs)
        }
    }

    // MARK: Chips

    /// A row of equal chips — the phone's 8pt-rounded ones, or the iPad's
    /// segmented control.
    private func chipRow<Item: Identifiable & Equatable>(
        _ items: [Item],
        selected: Item,
        height: CGFloat,
        title: @escaping (Item) -> Text,
        isEnabled: @escaping (Item) -> Bool = { _ in true },
        pick: @escaping (Item) -> Void
    ) -> some View {
        HStack(spacing: style.segmented ? 2 : 8) {
            ForEach(items) { item in
                let isOn = item == selected
                Button { pick(item) } label: {
                    title(item)
                        .font(.system(size: style.chipFontSize, weight: isOn ? .semibold : .medium))
                        .foregroundStyle(.white.opacity(isEnabled(item) ? 1 : 0.3))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: style.segmented ? height - 4 : height)
                        .background(
                            RoundedRectangle(cornerRadius: style.segmented ? 10 : 8, style: .continuous)
                                .fill(isOn ? Color.white.opacity(0.20) : (style.segmented ? Color.clear : Color.white.opacity(0.06)))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled(item))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(style.segmented ? 2 : 0)
        .background {
            if style.segmented {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08))
            }
        }
        .padding(.horizontal, style.inset)
    }
}

/// One tile of the Look panel: what it is, what a tap puts in the slot, and
/// what it draws before its thumbnail has rendered.
struct VideoLookTile: Identifiable {
    let id: String
    let look: VideoLook
    let isImported: Bool
    let swatch: [LookSwatch.RGB]

    func name(_ presetName: (PhotoFilter) -> String) -> String {
        VideoLookEditing.name(of: look, presetName: presetName)
    }

    /// Whether the slot holds this tile's look. Original is lit when the
    /// whole video's slot holds nothing; a clip with no look of its own
    /// follows the video and lights no tile.
    func isChosen(in slot: VideoLook?, slotIsClip: Bool = false) -> Bool {
        guard let slot else { return look.isOriginal && !slotIsClip }
        return VideoLookEditing.isSameChoice(slot.source, look.source)
    }

    @MainActor
    static func tiles(
        shelf: EditorPresetSource,
        includesOriginal: Bool,
        looks: LookPresetStore,
        luts: ImportedLUTStore
    ) -> [VideoLookTile] {
        let original = VideoLookTile(id: "preset.original", look: .original, isImported: false, swatch: LookSwatch.colors(for: .original))
        switch shelf {
        case .presets:
            return PhotoFilter.allCases.map { filter in
                VideoLookTile(id: "preset.\(filter.rawValue)", look: VideoLook(.preset(filter)), isImported: false, swatch: LookSwatch.colors(for: filter))
            }
        case .myLooks:
            let mine = looks.presets.map { preset in
                // The look as the editor applies it: an imported look
                // changes only the settings its preset named (E6).
                let recipe = preset.applied(onto: .identity)
                return VideoLookTile(
                    id: "look.\(preset.id.uuidString)",
                    look: VideoLook(.myLook(sourceID: preset.id, name: preset.name, isImported: preset.source == .imported, recipe: recipe)),
                    isImported: preset.source == .imported,
                    swatch: LookSwatch.colors(for: recipe)
                )
            }
            return (includesOriginal ? [original] : []) + mine
        case .luts:
            let tables = luts.luts.map { lut in
                VideoLookTile(
                    id: "lut.\(lut.id)", look: VideoLook(.lut(id: lut.id, name: lut.displayName)),
                    isImported: false, swatch: [LookSwatch.highlight, LookSwatch.shadow]
                )
            }
            return (includesOriginal ? [original] : []) + tables
        }
    }
}

/// What a window draws the Look panel at (FS-12.06c §3, boards F5_*).
struct VideoLookPanelStyle: Equatable {
    var tile = CGSize(width: 70, height: 70)
    /// Nil: one scrolling row. Otherwise a grid this many tiles across.
    var columns: Int?
    var tileGap: CGFloat = 10
    var tileRowGap: CGFloat = 10
    var tileLabelSize: CGFloat = 10.5
    var badgeSize: CGFloat = 8.5
    var tabHeight: CGFloat = 28
    var shelfHeight: CGFloat = 30
    var amountHeight: CGFloat = 40
    var applyHeight: CGFloat = 30
    var chipFontSize: CGFloat = 12.5
    var captionSize: CGFloat = 11.5
    var showsApplyHeader = true
    var showsOriginalTile = true
    var importsBesideShelf = false
    var segmented = false
    /// Grid tiles share the column's width rather than keeping theirs: the
    /// iPad inspector is 316–360 wide depending on the window.
    var fillsColumns = false
    var inset: CGFloat = 16
    var topGap: CGFloat = 6
    /// The iPad portrait dock's three columns (FS-12.03 §3).
    var dockColumns = false
    var afterTabs: CGFloat = 10
    var afterShelf: CGFloat = 12
    var afterTiles: CGFloat = 6

    /// iPhone, `F5_P_Looks`: panel 340 at y 450.
    static let phone = VideoLookPanelStyle()

    /// Duo cover, `F5_DC_Looks`: 382×344 beside the 84 rail.
    static let duoCover = VideoLookPanelStyle(
        tile: CGSize(width: 60, height: 60), tileGap: 8, shelfHeight: 28, amountHeight: 36,
        applyHeight: 28, showsApplyHeader: false, inset: 14, topGap: 6, afterTabs: 8, afterShelf: 10, afterTiles: 4
    )

    /// Duo inner, `F5_DI_Looks`: the 264 column, a 3 × 2 grid of 66.
    static let duoInner = VideoLookPanelStyle(
        tile: CGSize(width: 66, height: 66), columns: 3, shelfHeight: 28, amountHeight: 34,
        applyHeight: 26, showsApplyHeader: false, showsOriginalTile: false, inset: 14, topGap: 0,
        afterTabs: 8, afterShelf: 10, afterTiles: 8
    )

    /// iPad, `F5_IL_Looks` (Mac-style): segmented controls 36 tall, a grid
    /// of 103×50 tiles, Amount 44, in the 360 inspector.
    static let iPad = VideoLookPanelStyle(
        tile: CGSize(width: 102.67, height: 50), columns: 3, tileGap: 10, tileRowGap: 6, tileLabelSize: 13,
        badgeSize: 11, tabHeight: 36, shelfHeight: 36, amountHeight: 44, applyHeight: 36, chipFontSize: 15,
        captionSize: 13, showsApplyHeader: false, showsOriginalTile: false, importsBesideShelf: true,
        segmented: true, fillsColumns: true, inset: 16, topGap: 4, afterTabs: 10, afterShelf: 10, afterTiles: 6
    )

    /// iPad portrait, `F5_IP_Looks` / `IP1_Main`: the dock's three columns
    /// of 312, tiles 3 across, 72 tall with their names.
    static let iPadDock = VideoLookPanelStyle(
        tile: CGSize(width: 97.33, height: 50), columns: 3, tileGap: 10, tileRowGap: 6, tileLabelSize: 13,
        badgeSize: 11, tabHeight: 36, shelfHeight: 36, amountHeight: 44, applyHeight: 36, chipFontSize: 15,
        captionSize: 13, showsApplyHeader: false, showsOriginalTile: false, importsBesideShelf: false,
        segmented: true, fillsColumns: true, inset: 0, topGap: 0, dockColumns: true, afterTabs: 10,
        afterShelf: 10, afterTiles: 6
    )
}

extension VideoLookPanelStyle {
    static func `for`(_ windowClass: VideoStudioWindowClass) -> VideoLookPanelStyle {
        switch windowClass {
        case .phone: .phone
        case .duoCover: .duoCover
        case .duoInner: .duoInner
        case .iPadLandscape: .iPad
        case .iPadPortrait: .iPadDock
        }
    }
}

private struct VideoLookPanelStyleKey: EnvironmentKey {
    static let defaultValue = VideoLookPanelStyle.phone
}

extension EnvironmentValues {
    var videoLookPanelStyle: VideoLookPanelStyle {
        get { self[VideoLookPanelStyleKey.self] }
        set { self[VideoLookPanelStyleKey.self] = newValue }
    }
}

extension VideoLookTarget {
    /// The whole video's panel offers two; a clip's block three (§4).
    static let wholeVideoTargets: [VideoLookTarget] = [.allClips, .thisClip]
}

/// "1 look is missing its LUT and exports without it." (FS-12.06c §6), as
/// the boards ES_* draw it: a 10-rounded band of white 6 % with the
/// warning glyph. Export is never blocked by it.
struct VideoMissingLUTBanner: View {
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            Text(VideoStudioCopy.looksMissingLUT(count))
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("missingLUTLine")
    }
}
