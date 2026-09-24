import SwiftUI
import UIKit
import ShotDexKit

/// Presets tab (30c): an Amount row while a look is active, then every look at
/// once in one horizontal scroll of thumbnail cards — each a small preview of the
/// photo through that look plus its name. No category picker (Basic / Film / B&W);
/// the strips are flattened into the single scroll.
struct EditorFiltersPanel: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel
    /// The user's own saved looks. Nil where the panel is shown without them
    /// (previews).
    var lookPresets: LookPresetStore?
    /// `.cube` files imported from Files. Nil in previews.
    var luts: ImportedLUTStore?
    /// Asks the screen to name and save the current edit as a look.
    var saveLook: (() -> Void)?
    /// Scrolls itself when the host gives it a fixed height — the phone's
    /// 167pt parameter zone, where My Looks and My LUTs above the film strip
    /// no longer fit. The wide sidebar already scrolls, and a scroll view
    /// nested in it would claim no height, so there it stays a plain stack.
    var scrolls = false

    /// Space above each group header: tighter in the phone's fixed zone,
    /// where 12pt is the difference between the film strip's names showing
    /// and being cut at the baseline.
    private var headerTopPadding: CGFloat { scrolls ? 4 : 10 }

    @State private var isLUTImporterPresented = false
    @State private var lutImportError: String?
    @Environment(\.editorUsesPanelStyle) private var usesPanelStyle
    @Environment(\.editorSliderStacked) private var isStacked

    /// Phone (FS-03.12): the source strip picks one shelf, the zone is that
    /// shelf's thumbnail row with Amount under it.
    private var isPhonePanel: Bool { usesPanelStyle && !isStacked }

    /// The recipe names a LUT whose file is gone: the photo renders without
    /// it and the panel says so, instead of quietly showing no look selected.
    private var usesDeletedLUT: Bool {
        guard let id = controller.recipe.lutID, let luts else { return false }
        return luts.url(for: id) == nil
    }

    private var hasActiveLook: Bool {
        controller.recipe.lutID != nil ? !usesDeletedLUT : controller.recipe.filter != .original
    }

    var body: some View {
        if isPhonePanel {
            phoneContent
                .lutImporter(isPresented: $isLUTImporterPresented, error: $lutImportError, luts: luts, controller: controller)
        } else if scrolls {
            ScrollView(.vertical) {
                content
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        } else {
            content
        }
    }

    private var phoneContent: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scroller in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: EditorStripLayout.chipSpacing) {
                        shelf
                    }
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.top, 2)
                    .padding(.bottom, AppTheme.Spacing.sm)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    if chrome.presetSource == .presets {
                        scroller.scrollTo(controller.recipe.filter, anchor: .center)
                    }
                }
            }
            if chrome.presetSource == .luts, usesDeletedLUT {
                Label("LUT deleted · this photo renders without it", systemImage: "exclamationmark.triangle")
                    .font(EditorTheme.rowLabel)
                    .foregroundStyle(EditorTheme.secondaryText)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .frame(height: EditorLayoutMetrics.editorPanelRowHeight)
            } else if hasActiveLook {
                amountRow
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .task { controller.refreshFilterThumbnails() }
    }

    @ViewBuilder
    private var shelf: some View {
        switch chrome.presetSource {
        case .presets:
            ForEach(PhotoFilter.allCases) { filter in
                filterCard(filter).id(filter)
            }
        case .myLooks:
            if let saveLook {
                actionTile("Save Current", systemImage: "plus", isEnabled: !controller.recipe.isIdentity, action: saveLook)
            }
            if let lookPresets {
                ForEach(lookPresets.presets) { preset in
                    lookTile(preset, store: lookPresets)
                }
            }
        case .luts:
            if luts != nil {
                actionTile("Import .cube", systemImage: "square.and.arrow.down", isEnabled: true) {
                    isLUTImporterPresented = true
                }
            }
            if let luts {
                ForEach(luts.luts) { lut in
                    lutCard(lut, store: luts)
                }
                .task(id: luts.luts.map(\.id)) {
                    controller.refreshLUTThumbnails(ids: luts.luts.map(\.id))
                }
            }
        }
    }

    /// First tile of a shelf that makes something rather than picks it.
    private func actionTile(
        _ title: String,
        systemImage: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(EditorTheme.chipIdle, in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                Text(title)
                    .font(EditorTheme.tabLabel)
                    .foregroundStyle(EditorTheme.secondaryText)
                    .lineLimit(1)
                    .frame(width: 66)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : EditorTheme.rowDisabled)
        .accessibilityLabel(title)
    }

    /// A saved look as a tile: the look's name over a plain square (looks carry
    /// no thumbnail of their own). Long-press still deletes it.
    private func lookTile(_ preset: LookPreset, store: LookPresetStore) -> some View {
        Button {
            controller.apply(EditorSyncScope.look.apply(preset.recipe, onto: controller.recipe))
        } label: {
            VStack(spacing: 5) {
                Image(systemName: "camera.filters")
                    .font(.system(size: 18))
                    .foregroundStyle(EditorTheme.secondaryText)
                    .frame(width: 62, height: 62)
                    .background(EditorTheme.control, in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                Text(preset.name)
                    .font(EditorTheme.tabLabel)
                    .foregroundStyle(EditorTheme.secondaryText)
                    .lineLimit(1)
                    .frame(width: 66)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                store.delete(preset)
            } label: {
                Label("Delete Look", systemImage: "trash")
            }
        }
        .accessibilityLabel("Apply look \(preset.name)")
    }

    private var content: some View {
        VStack(spacing: 0) {
            myLooks

            myLUTs

            if hasActiveLook {
                amountRow
                    .padding(.top, 8)
                Rectangle()
                    .fill(EditorTheme.hairline)
                    .frame(height: 0.5)
                    .padding(.horizontal, 14)
            }

            presetStrip
        }
        .frame(maxWidth: .infinity)
        .task { controller.refreshFilterThumbnails() }
    }

    /// The user's looks, above the fixed film looks: their own work comes
    /// first, and the row is where they will look for it.
    @ViewBuilder
    private var myLooks: some View {
        if let lookPresets {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("My Looks")
                        .font(EditorTheme.groupLabel)
                        .tracking(1.1)
                        .foregroundStyle(EditorTheme.secondaryText)
                    Spacer(minLength: 8)
                    if let saveLook {
                        Button(action: saveLook) {
                            Label("Save Current", systemImage: "plus")
                                .font(EditorTheme.maskSubtitle)
                                .foregroundStyle(
                                    controller.recipe.isIdentity
                                        ? EditorTheme.dimText
                                        : EditorTheme.accent
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(controller.recipe.isIdentity)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, headerTopPadding)

                if lookPresets.presets.isEmpty {
                    // The phone's 167pt zone has no line to spare: the
                    // sentence there pushed the film strip off the bottom,
                    // and the header's own button already says what to do.
                    if !scrolls {
                        Text("Save an edit here and it can be put on any other photo.")
                            .font(EditorTheme.maskSubtitle)
                            .foregroundStyle(EditorTheme.dimText)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                    } else {
                        Color.clear.frame(height: 2)
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(lookPresets.presets) { preset in
                                lookChip(preset, store: lookPresets)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                    }
                    .scrollIndicators(.hidden)
                }

                Rectangle()
                    .fill(EditorTheme.hairline)
                    .frame(height: 0.5)
                    .padding(.horizontal, 14)
            }
        }
    }

    /// Imported `.cube` LUTs, in the same list as the film looks but their
    /// own group — a look pack the user bought is theirs, like My Looks.
    @ViewBuilder
    private var myLUTs: some View {
        if let luts {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("My LUTs")
                        .font(EditorTheme.groupLabel)
                        .tracking(1.1)
                        .foregroundStyle(EditorTheme.secondaryText)
                    Spacer(minLength: 8)
                    Button {
                        isLUTImporterPresented = true
                    } label: {
                        Label("Import .cube", systemImage: "square.and.arrow.down")
                            .font(EditorTheme.maskSubtitle)
                            .foregroundStyle(EditorTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.top, headerTopPadding)

                if usesDeletedLUT {
                    Label(
                        "LUT deleted · this photo renders without it",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(EditorTheme.maskSubtitle)
                    .foregroundStyle(EditorTheme.secondaryText)
                    .padding(.horizontal, 14)
                }

                if luts.luts.isEmpty {
                    // The phone's 167pt zone has no line to spare: the
                    // sentence there pushed the film strip off the bottom,
                    // and the header's own button already says what to do.
                    if !scrolls {
                        Text("Import a .cube file from Files to use it as a look.")
                            .font(EditorTheme.maskSubtitle)
                            .foregroundStyle(EditorTheme.dimText)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                    } else {
                        Color.clear.frame(height: 2)
                    }
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 8) {
                            ForEach(luts.luts) { lut in
                                lutCard(lut, store: luts)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                    }
                    .scrollIndicators(.hidden)
                    .task(id: luts.luts.map(\.id)) {
                        controller.refreshLUTThumbnails(ids: luts.luts.map(\.id))
                    }
                }

                Rectangle()
                    .fill(EditorTheme.hairline)
                    .frame(height: 0.5)
                    .padding(.horizontal, 14)
            }
            .fileImporter(
                isPresented: $isLUTImporterPresented,
                allowedContentTypes: [LUTImportMessage.cubeType]
            ) { result in
                guard case .success(let url) = result else { return }
                do {
                    let imported = try luts.add(from: url)
                    controller.chooseLUT(imported.id)
                } catch {
                    lutImportError = LUTImportMessage.text(for: error)
                }
            }
            .alert(
                "Couldn't Import LUT",
                isPresented: Binding(
                    get: { lutImportError != nil },
                    set: { if !$0 { lutImportError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { lutImportError = nil }
            } message: {
                Text(lutImportError ?? "")
            }
        }
    }

    private func lutCard(_ lut: ImportedLUT, store: ImportedLUTStore) -> some View {
        let isSelected = controller.recipe.lutID == lut.id
        return Button {
            controller.chooseLUT(lut.id)
        } label: {
            VStack(spacing: 5) {
                Group {
                    if let image = controller.lutThumbnails[lut.id] {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            EditorTheme.control
                            Image(systemName: "cube")
                                .font(.system(size: 18))
                                .foregroundStyle(EditorTheme.dimText)
                        }
                    }
                }
                .frame(width: 62, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .modifier(EditorTileSelection(isSelected: isSelected, usesRing: isPhonePanel))

                Text(lut.displayName)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? (isPhonePanel ? .white : EditorTheme.accent) : EditorTheme.secondaryText)
                    .lineLimit(1)
                    .frame(width: 66)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                store.delete(lut)
                controller.scheduleRender()
            } label: {
                Label("Delete LUT", systemImage: "trash")
            }
        }
        .accessibilityLabel(lut.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func lookChip(_ preset: LookPreset, store: LookPresetStore) -> some View {
        Button {
            controller.apply(EditorSyncScope.look.apply(preset.recipe, onto: controller.recipe))
        } label: {
            Text(preset.name)
                .font(EditorTheme.pillLabel)
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: AppTheme.Size.pillHeightDark)
                .background(EditorTheme.control, in: Capsule())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .contextMenu {
            Button(role: .destructive) {
                store.delete(preset)
            } label: {
                Label("Delete Look", systemImage: "trash")
            }
        }
        .accessibilityLabel("Apply look \(preset.name)")
    }

    private var amountRow: some View {
        EditorPlainSliderRow(
            title: "Amount",
            value: controller.recipe.filterIntensity,
            range: 0...1,
            isBipolar: false,
            valueText: "\(Int((controller.recipe.filterIntensity * 100).rounded()))%",
            isActive: false,
            detent: 1,
            onBeginDrag: { controller.beginContinuousChange() },
            onDrag: { controller.setFilterIntensity($0) },
            onEndDrag: { controller.endContinuousChange() },
            onReset: { controller.setFilterIntensity(1) }
        )
    }

    /// Every look at once — no category picker — in one horizontal scroll of
    /// thumbnail cards. Opens scrolled to the active look. Swatches stream in as the
    /// controller renders each category batch; until one arrives the card draws the
    /// look's two-tone gradient stand-in.
    private var presetStrip: some View {
        ScrollViewReader { scroller in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(PhotoFilter.allCases) { filter in
                        filterCard(filter).id(filter)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                scroller.scrollTo(controller.recipe.filter, anchor: .center)
            }
        }
    }

    private func filterCard(_ filter: PhotoFilter) -> some View {
        let isSelected = controller.recipe.lutID == nil && controller.recipe.filter == filter
        return Button {
            controller.chooseFilter(filter)
        } label: {
            VStack(spacing: 5) {
                thumbnail(filter)
                    .frame(width: 62, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .modifier(EditorTileSelection(isSelected: isSelected, usesRing: isPhonePanel))

                Text(filter.displayName)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? (isPhonePanel ? .white : EditorTheme.accent) : EditorTheme.secondaryText)
                    .lineLimit(1)
                    .frame(width: 66)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filter.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func thumbnail(_ filter: PhotoFilter) -> some View {
        if let image = controller.filterThumbnails[filter] {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            LinearGradient(
                colors: swatchColors(for: filter),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    /// Stand-in until the photo's own swatch has rendered: the look applied to a lit
    /// warm tone and a shadowed cool one. Made of the same maths as the real thing,
    /// so the placeholder already leans the way the look does.
    private func swatchColors(for filter: PhotoFilter) -> [Color] {
        guard let look = FilmLookLibrary.look(for: filter) else {
            return legacyColors(for: filter)
        }
        let highlight = look.apply(to: SIMD3(0.82, 0.76, 0.66))
        let shadow = look.apply(to: SIMD3(0.22, 0.25, 0.32))
        return [
            Color(red: highlight.x, green: highlight.y, blue: highlight.z),
            Color(red: shadow.x, green: shadow.y, blue: shadow.z),
        ]
    }

    /// The ten original presets are Core Image chains rather than `FilmLook`s, so
    /// their placeholders stay hand-picked.
    private func legacyColors(for filter: PhotoFilter) -> [Color] {
        switch filter {
        case .vivid: [.pink, .blue]
        case .vividWarm: [.orange, .pink]
        case .vividCool: [.cyan, .indigo]
        case .dramatic: [.black, .orange]
        case .dramaticWarm: [.brown, .orange]
        case .dramaticCool: [.black, .blue]
        case .mono: [.white, .gray]
        case .silvertone: [.gray.opacity(0.5), .white]
        case .noir: [.black, .white]
        default: [.gray, .white.opacity(0.6)]
        }
    }
}

/// Crop tab: rotate / flip / reset, straighten, ratio chips. Mask overlays stay
/// hidden while framing, which the render path already handles.
///
/// Turn 31: there is no in-panel command row, so the framing actions that lived
/// there — rotate, flip, reset crop — are a button row at the top of this panel
/// (rotate and flip are also in the band's ⋯ menu). There is no Done: the crop
/// commits when the tab is left or the edit is saved.
struct EditorCropPanel: View {
    @Bindable var controller: PhotoEditorController
    @Environment(\.editorUsesPanelStyle) private var usesPanelStyle
    @Environment(\.editorSliderStacked) private var isStacked

    var body: some View {
        if usesPanelStyle && !isStacked {
            phoneRows
        } else {
            stackedBody
        }
    }

    /// Phone (FS-03.12): the ratios are the target strip (`EditorCropAspectStrip`);
    /// under it Straighten, the Rotate · Flip · Reset chips, and the footnote as a
    /// hint row — every one a 40pt grid row.
    private var phoneRows: some View {
        VStack(spacing: 0) {
            straightenRow
            HStack(spacing: EditorStripLayout.chipSpacing) {
                phoneAction("Rotate", icon: "rotate.right", isEnabled: true) { controller.rotate() }
                phoneAction(
                    "Flip",
                    icon: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                    isEnabled: true
                ) { controller.flip() }
                phoneAction("Reset", icon: "arrow.counterclockwise", isEnabled: controller.recipe.crop != .identity) {
                    controller.resetCrop()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, EditorStripLayout.horizontalInset)
            .frame(height: EditorLayoutMetrics.editorPanelRowHeight)
            Text("The crop applies when you leave this tab or save.")
                .font(EditorTheme.rowLabel)
                .foregroundStyle(EditorTheme.panelHint)
                .lineLimit(1)
                .minimumScaleFactor(EditorLayoutMetrics.editorPanelRowMinimumScale)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: EditorLayoutMetrics.editorPanelRowHeight)
            Spacer(minLength: 0)
        }
    }

    private func phoneAction(
        _ title: String,
        icon: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            EditorPanelChipLabel(title: title, systemImage: icon)
        }
        .buttonStyle(EditorChipButtonStyle(isSelected: false))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : EditorTheme.rowDisabled)
        .accessibilityLabel(title)
    }

    private var straightenRow: some View {
        EditorPlainSliderRow(
            title: "Straighten",
            value: controller.recipe.crop.straightenDegrees,
            range: -45...45,
            isBipolar: true,
            valueText: String(
                format: "%.1f°",
                controller.recipe.crop.straightenDegrees
            ),
            isActive: false,
            detent: 0,
            onBeginDrag: { controller.beginContinuousChange() },
            onDrag: { controller.setStraighten($0) },
            onEndDrag: { controller.endContinuousChange() },
            onReset: { controller.setStraighten(0) }
        )
    }

    private var stackedBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            actionRow

            straightenRow

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(CropAspect.allCases) { aspect in
                        Button(aspect.displayName) {
                            controller.chooseCropAspect(aspect, imageAspect: nil)
                        }
                        .buttonStyle(
                            EditorChipButtonStyle(
                                isSelected: controller.recipe.crop.aspect == aspect
                            )
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)

            Spacer(minLength: 0)

            Text("The crop applies when you leave this tab or save.")
                .font(.system(size: 11))
                .foregroundStyle(EditorTheme.secondaryText)
                .padding(.horizontal, 18)
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Rotate 90° / Flip / Reset Crop — the framing actions that used to sit in the
    /// panel's command row. Reset is disabled until there is a crop to reset.
    private var actionRow: some View {
        HStack(spacing: 8) {
            cropAction("Rotate", icon: "rotate.right", isEnabled: true) {
                controller.rotate()
            }
            cropAction(
                "Flip",
                icon: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                isEnabled: true
            ) {
                controller.flip()
            }
            cropAction(
                "Reset",
                icon: "crop",
                isEnabled: controller.recipe.crop != .identity
            ) {
                controller.resetCrop()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    private func cropAction(
        _ title: String,
        icon: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isEnabled ? .white : EditorTheme.dimText)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(EditorTheme.control, in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }
}

/// The phone panel's Crop target strip: every ratio, each with a frame glyph,
/// scrolling (eight chips). The selected ratio is the white-20% chip, not accent.
struct EditorCropAspectStrip: View {
    @Bindable var controller: PhotoEditorController

    var body: some View {
        EditorPanelChipStrip(
            items: CropAspect.allCases,
            isSelected: { controller.recipe.crop.aspect == $0 },
            label: { EditorPanelChipLabel(title: $0.displayName, systemImage: $0.stripSymbol) },
            accessibilityName: \.displayName,
            onSelect: { controller.chooseCropAspect($0, imageAspect: nil) }
        )
    }
}

extension CropAspect {
    var stripSymbol: String {
        switch self {
        case .free: "crop"
        case .original: "photo"
        case .square: "square"
        case .fourThree: "rectangle.ratio.4.to.3"
        case .threeTwo: "rectangle"
        case .sixteenNine: "rectangle.ratio.16.to.9"
        case .fourFive: "rectangle.portrait"
        case .nineSixteen: "rectangle.ratio.9.to.16"
        }
    }
}

/// Slider row for values that are not `PhotoAdjustmentKind` (filter intensity,
/// straighten, mask shape parameters). Uses the same pan arbitration as the
/// adjustment rows.
struct EditorPlainSliderRow: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let isBipolar: Bool
    let valueText: String
    let isActive: Bool
    /// Value the knob snaps onto while passing it, if this slider has a natural
    /// resting point (0° straighten, 100% filter intensity).
    var detent: Double?
    /// Full-width trough gradient (color mixer / grading rows). When set, the
    /// gradient carries the meaning and the accent progress fill is suppressed —
    /// the knob alone shows the value, mirroring `EditorSliderRow`'s trough
    /// gradients for warmth/tint.
    var trackGradient: LinearGradient?
    let onBeginDrag: () -> Void
    let onDrag: (Double) -> Void
    let onEndDrag: () -> Void
    let onReset: () -> Void

    var body: some View {
        EditorValueSlider(
            label: title,
            value: value,
            range: range,
            valueText: valueText,
            isActive: isActive,
            anchor: isBipolar ? (range.lowerBound + range.upperBound) / 2 : range.lowerBound,
            showsAnchorNotch: isBipolar,
            detent: detent,
            trackGradient: trackGradient,
            onBeginDrag: onBeginDrag,
            onDrag: onDrag,
            onEndDrag: { _, _, _ in onEndDrag() },
            onReset: onReset,
            onEditValue: nil
        )
    }
}

/// Upright — the row above the Geo sliders. Lightroom's Level / Vertical /
/// Full plus an Off, as chips rather than sliders: none of them is a value the
/// user dials, each is a question asked of the photo ("what would level look
/// like?") and answered in one press.
struct EditorUprightRow: View {
    @Bindable var controller: PhotoEditorController

    /// Said in the row rather than in the editor's toast: that toast carries an
    /// Undo button, and there is nothing to undo when a pass found no lines —
    /// pressing it would undo whatever the user did before instead.
    @State private var note: String?
    @State private var noteTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("UPRIGHT")
                .font(EditorTheme.groupLabel)
                .tracking(1.1)
                .foregroundStyle(EditorTheme.secondaryText)
            HStack(spacing: AppTheme.Spacing.sm) {
                ForEach(UprightMode.allCases) { mode in
                    Button(mode.title) {
                        apply(mode)
                    }
                    .buttonStyle(EditorChipButtonStyle(isSelected: false))
                }
                Button("Off") {
                    show(nil)
                    controller.resetUpright()
                }
                .buttonStyle(EditorChipButtonStyle(isSelected: false))
                .disabled(!controller.hasUpright)
                Spacer(minLength: 0)
            }
            if let note {
                Text(note)
                    .font(EditorTheme.rowLabel)
                    .foregroundStyle(EditorTheme.dimText)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.sm)
        .animation(EditorTheme.animation, value: note)
        .onDisappear { noteTask?.cancel() }
    }

    private func apply(_ mode: UprightMode) {
        show(controller.applyUpright(mode) ? nil : "No straight lines to work from")
    }

    private func show(_ message: String?) {
        noteTask?.cancel()
        note = message
        guard message != nil else { return }
        noteTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            note = nil
        }
    }
}

/// The editor's one chip. Inside the photo editor (`editorUsesPanelStyle`,
/// FS-03.12 §4) it is 30pt, white text, white 20% when selected and 6% otherwise —
/// no accent, no border. Everywhere else (Collage, Video Studio, the other tools)
/// it keeps the 28pt accent chip those screens were built with.
struct EditorChipButtonStyle: ButtonStyle {
    let isSelected: Bool
    /// Equal-width chips in a strip give the title the room instead: at 88pt a
    /// four-chip strip cannot also spend 16pt on padding ("Highlights" clipped).
    var horizontalPadding = EditorStripLayout.chipHorizontalPadding

    func makeBody(configuration: Configuration) -> some View {
        EditorChipBody(configuration: configuration, isSelected: isSelected, horizontalPadding: horizontalPadding)
    }
}

private struct EditorChipBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    let horizontalPadding: CGFloat
    @Environment(\.editorUsesPanelStyle) private var usesPanelStyle

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
        if usesPanelStyle {
            configuration.label
                .font(isSelected ? EditorTheme.chipLabelSelected : EditorTheme.chipLabel)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(EditorLayoutMetrics.editorPanelRowMinimumScale)
                .padding(.horizontal, horizontalPadding)
                .frame(height: EditorStripLayout.chipHeight)
                .background(isSelected ? EditorTheme.chipSelected : EditorTheme.chipIdle, in: shape)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .contentShape(shape)
        } else {
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? .white : EditorTheme.secondaryText)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    isSelected
                        ? EditorTheme.accent
                        : EditorTheme.control.opacity(configuration.isPressed ? 0.6 : 1),
                    in: shape
                )
                .contentShape(shape)
        }
    }
}

/// A chip's content: an SF Symbol at 15pt (or an 8pt colour dot) and the title,
/// 4pt apart.
struct EditorPanelChipLabel: View {
    let title: String
    var systemImage: String?
    var dot: Color?
    /// Cleared by the strip for all its chips at once (`EditorStripLayout.showsIcons`).
    var showsIcon = true

    var body: some View {
        HStack(spacing: EditorStripLayout.chipIconSpacing) {
            if showsIcon, let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .regular))
            } else if showsIcon, let dot {
                Circle().fill(dot).frame(width: 8, height: 8)
            }
            Text(title).lineLimit(1)
        }
    }

    /// The title's width at the selected (widest) weight.
    var titleWidth: CGFloat {
        let font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        return ceil((title as NSString).size(withAttributes: [.font: font]).width)
    }
}

/// A row of chips on the panel's grid: equal widths up to five, a horizontal
/// scroll past that (`EditorStripLayout`). One implementation for every target
/// strip — Curve channels, Grade regions, Presets sources, Crop ratios.
struct EditorPanelChipStrip<Item: Identifiable>: View {
    let items: [Item]
    let isSelected: (Item) -> Bool
    let label: (Item) -> EditorPanelChipLabel
    let accessibilityName: (Item) -> String
    let onSelect: (Item) -> Void
    @State private var width: CGFloat = 0

    var body: some View {
        if EditorStripLayout.sharesWidth(itemCount: items.count, kind: .text) {
            HStack(spacing: EditorStripLayout.chipSpacing) {
                ForEach(items) { item in chip(item).frame(maxWidth: .infinity) }
            }
            .padding(.horizontal, EditorStripLayout.horizontalInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: EditorStripLayout.chipSpacing) {
                        ForEach(items) { item in chip(item).id(item.id) }
                    }
                    .padding(.horizontal, EditorStripLayout.horizontalInset)
                    .frame(maxHeight: .infinity)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    if let selected = items.first(where: isSelected) {
                        proxy.scrollTo(selected.id, anchor: .center)
                    }
                }
            }
        }
    }

    private func chip(_ item: Item) -> some View {
        let selected = isSelected(item)
        let sharesWidth = EditorStripLayout.sharesWidth(itemCount: items.count, kind: .text)
        var chipLabel = label(item)
        chipLabel.showsIcon = !sharesWidth || width == 0 || EditorStripLayout.showsIcons(
            titleWidths: items.map { label($0).titleWidth },
            in: width
        )
        return Button {
            onSelect(item)
        } label: {
            chipLabel
                .frame(maxWidth: sharesWidth ? .infinity : nil)
        }
        .buttonStyle(EditorChipButtonStyle(
            isSelected: selected,
            horizontalPadding: sharesWidth ? EditorStripLayout.equalChipHorizontalPadding : EditorStripLayout.chipHorizontalPadding
        ))
        .accessibilityLabel(accessibilityName(item))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// How a look / LUT tile shows it is chosen. On the phone panel: a white ring 2pt
/// clear of the tile (FS-03.12 swatch rule). Elsewhere: the accent outline and tick.
struct EditorTileSelection: ViewModifier {
    let isSelected: Bool
    let usesRing: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
        if usesRing {
            content
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm + 3, style: .continuous)
                            .strokeBorder(.white, lineWidth: 1.5)
                            .padding(-3.5)
                    } else {
                        shape.stroke(.white.opacity(0.10), lineWidth: 0.5)
                    }
                }
        } else {
            content
                .overlay {
                    shape.stroke(
                        isSelected ? EditorTheme.accent : .white.opacity(0.10),
                        lineWidth: isSelected ? 2 : 0.5
                    )
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(EditorTheme.accent)
                            .background(Circle().fill(.black.opacity(0.5)))
                            .padding(4)
                    }
                }
        }
    }
}

/// The phone Presets panel's Files importer for `.cube`, with the same error alert
/// the stacked panel shows.
private extension View {
    func lutImporter(
        isPresented: Binding<Bool>,
        error message: Binding<String?>,
        luts: ImportedLUTStore?,
        controller: PhotoEditorController
    ) -> some View {
        fileImporter(
            isPresented: isPresented,
            allowedContentTypes: [LUTImportMessage.cubeType]
        ) { result in
            guard let luts, case .success(let url) = result else { return }
            do {
                let imported = try luts.add(from: url)
                controller.chooseLUT(imported.id)
            } catch {
                message.wrappedValue = LUTImportMessage.text(for: error)
            }
        }
        .alert(
            "Couldn't Import LUT",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

/// The phone panel's Presets target strip: Presets · My Looks · LUTs.
struct EditorPresetSourceStrip: View {
    @Bindable var chrome: EditorChromeModel

    var body: some View {
        EditorPanelChipStrip(
            items: EditorPresetSource.allCases,
            isSelected: { chrome.presetSource == $0 },
            label: { EditorPanelChipLabel(title: $0.title, systemImage: $0.systemImage) },
            accessibilityName: \.title,
            onSelect: { chrome.presetSource = $0 }
        )
    }
}

