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
    @Bindable var model: VideoStudioModel
    /// The Color tab's scopes draw taller in a column.
    var usesTallScopes = false

    @Environment(\.videoLookPanelStyle) private var style
    @Environment(AppDependencies.self) private var dependencies
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @State private var thumbnails = VideoLookThumbnails()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: style.topGap)
            chipRow(VideoLookTab.allCases, selected: model.lookTab, height: style.tabHeight, title: { Text($0.title) }) {
                model.lookTab = $0
            }
            switch model.lookTab {
            case .filter: filterBody
            case .adjust: adjustBody
            case .color: VideoColorPanel(model: model, usesTallScopes: usesTallScopes)
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
    }

    // MARK: Filter

    private var filterBody: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: style.afterTabs)
                shelfRow
                Color.clear.frame(height: style.afterShelf)
                tiles
                Color.clear.frame(height: style.afterTiles)
                if VideoLookEditing.showsAmount(model.lookSlot), let look = model.lookSlot {
                    amountRow(look)
                }
                applyTo
                caption
                Color.clear.frame(height: 4)
                if !style.importsBesideShelf { importRow }
            }
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var shelfRow: some View {
        HStack(spacing: 8) {
            chipRow(EditorPresetSource.allCases, selected: model.lookShelf, height: style.shelfHeight, title: { Text(LocalizedStringKey($0.title)) }) {
                model.lookShelf = $0
            }
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
        chipRow(VideoLookTarget.wholeVideoTargets, selected: model.lookTarget, height: style.applyHeight, title: { Text($0.title) }) {
            model.lookTarget = $0
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
        Button { dependencies.lookExchange.isPickingFiles = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                Text(VideoStudioCopy.importLook)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.horizontal, style.inset)
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if DEBUG
        .onAppear { dependencies.lookExchange.importFixturesIfAsked(completion: imported) }
        #endif
    }

    private func imported(_ report: PresetImportReport) {
        model.lookImported(report, looks: dependencies.lookPresets, luts: dependencies.importedLUTs)
    }

    // MARK: Adjust

    private var adjustBody: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach([PhotoAdjustmentKind.exposure, .contrast, .saturation, .warmth, .brightness, .vignette], id: \.self) { kind in
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
}

extension VideoLookPanelStyle {
    static func `for`(_ windowClass: VideoStudioWindowClass) -> VideoLookPanelStyle {
        switch windowClass {
        case .phone: .phone
        case .duoCover: .duoCover
        case .duoInner: .duoInner
        case .iPadLandscape, .iPadPortrait: .iPad
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
