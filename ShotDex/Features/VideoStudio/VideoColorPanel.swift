import SwiftUI
import UniformTypeIdentifiers
import ShotDexKit

/// The grading stage, as one scrolling panel rather than a second page.
///
/// Resolve puts this behind a whole Color page. What is here is that page's
/// working order, top to bottom: read the frame on a scope, undo the log,
/// set the three primaries, bend the curve, fix one colour on the mixer,
/// lay a look pack over the top, then window off whatever is still wrong.
/// The render maths behind most of it is the photo editor's —
/// `PhotoRenderService.applyColor`, `.applyCurve`, `.applyFilter`, already
/// shipping and already unit-tested.
///
/// What is deliberately absent: the node graph and the tracker. A node
/// graph only earns its screen once a grade has branches, and this chain is
/// a fixed one; the tracker needs Vision and a per-frame mask transform,
/// which is a feature, not a panel.
struct VideoColorPanel: View {
    @Bindable var model: VideoStudioModel
    /// The inspector column gets a taller scope. The phone's band gets the
    /// same four, drawn shorter — a 140pt scope there is most of the panel,
    /// but leaving them out put the measurement that a grade is dialled
    /// against on one device only.
    var usesTallScopes = false

    @Environment(PhotoLibraryService.self) private var photoLibrary

    @State private var scopes = VideoScopeModel()
    @State private var luts = ImportedLUTStore()
    @State private var isLUTImporterPresented = false
    @State private var region: ColorGradingRegion = .midtones
    @State private var curveChannel: ToneCurveChannel = .rgb
    @State private var band: ColorMixerBand = .red

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                scopesSection
                Divider().overlay(EditorTheme.panelDivider)
                inputTransformSection
                Divider().overlay(EditorTheme.panelDivider)
                primariesSection
                Divider().overlay(EditorTheme.panelDivider)
                curvesSection
                Divider().overlay(EditorTheme.panelDivider)
                mixerSection
                Divider().overlay(EditorTheme.panelDivider)
                lutSection
                Divider().overlay(EditorTheme.panelDivider)
                windowsSection
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.lg)
        }
        // Named so the UI driver has one big element to swipe: the section
        // headers are the only other labelled things in here, and swiping a
        // 14pt label scrolls by 14pt.
        .accessibilityIdentifier("colorPanel")
        .task(id: model.clipIndexUnderPlayhead) {
            scopes.refresh(for: model, photoLibrary: photoLibrary)
        }
        // The grade itself is the other thing that makes the picture stale,
        // and it changes on every drag of a wheel. The model compares the
        // whole colour chain and only recounts when something in it moved,
        // so this can fire as often as SwiftUI likes.
        .onChange(of: model.recipe) {
            scopes.refresh(for: model, photoLibrary: photoLibrary)
        }
        .onDisappear { scopes.cancel() }
        .fileImporter(
            isPresented: $isLUTImporterPresented,
            allowedContentTypes: [Self.cubeType]
        ) { result in
            guard case .success(let url) = result else { return }
            do {
                let imported = try luts.add(from: url)
                model.setLUT(VideoLUTReference(id: imported.id, name: imported.displayName))
            } catch {
                model.errorMessage = String(
                    localized: "Couldn't read that LUT. ShotDex reads .cube files.",
                    comment: "Video Studio colour: the imported LUT did not parse"
                )
            }
        }
    }

    /// `.cube` has no registered system type, so it is matched by extension
    /// and falls back to plain data rather than to "any file" — which would
    /// let the user pick a JPEG and be told nothing.
    private static let cubeType = UTType(filenameExtension: "cube") ?? .data

    // MARK: Imported LUT

    /// A creative LUT from a look pack, at a strength.
    ///
    /// Resolve makes this a node in the tree; here it is the last stage of
    /// the chain, which is the same place — a look pack is authored to be
    /// the final word over a corrected picture. Bringing one in is a Files
    /// import for the same reason the music is: the user owns the pack.
    private var lutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LUT", comment: "Video Studio colour: an imported .cube lookup table")
                    .font(EditorTheme.groupLabel)
                    .foregroundStyle(EditorTheme.secondaryText)
                Spacer(minLength: 0)
                if model.recipe.lut != nil {
                    Button { model.setLUT(nil) } label: {
                        Text("None", comment: "Video Studio colour: grades without a LUT")
                            .font(EditorTheme.pillLabel)
                            .foregroundStyle(EditorTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            if luts.luts.isEmpty {
                Text(
                    "No LUTs yet. Import a .cube file from a look pack you own.",
                    comment: "Video Studio colour: the LUT list is empty"
                )
                .font(.system(size: 10.5))
                .foregroundStyle(EditorTheme.dimText)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(luts.luts) { lut in
                            lutChip(lut)
                        }
                    }
                }
            }

            Button { isLUTImporterPresented = true } label: {
                Label {
                    Text("Import LUT…", comment: "Video Studio colour: brings a .cube in from Files")
                } icon: {
                    Image(systemName: "square.and.arrow.down")
                }
                .font(EditorTheme.rowLabel)
                .foregroundStyle(EditorTheme.accent)
            }
            .buttonStyle(.plain)

            if let reference = model.recipe.lut {
                InspectorSlider(
                    label: String(localized: "Strength", comment: "Video Studio colour: how much of the LUT to mix in"),
                    value: reference.intensity,
                    range: 0...1,
                    valueText: "\(Int((reference.intensity * 100).rounded()))%",
                    model: model,
                    set: { model.setLUTIntensity($0) },
                    reset: { model.pushUndo(); model.setLUTIntensity(1) }
                )
            }
        }
    }

    private func lutChip(_ lut: ImportedLUT) -> some View {
        let isSelected = model.recipe.lut?.id == lut.id
        return Button {
            model.setLUT(
                isSelected ? nil : VideoLUTReference(id: lut.id, name: lut.displayName)
            )
        } label: {
            Text(lut.displayName)
                .lineLimit(1)
        }
        .buttonStyle(EditorChipButtonStyle(isSelected: isSelected))
        .contextMenu {
            Button(role: .destructive) {
                if isSelected { model.setLUT(nil) }
                luts.delete(lut)
            } label: {
                Label {
                    Text("Delete LUT", comment: "Video Studio colour: removes an imported .cube")
                } icon: {
                    Image(systemName: "trash")
                }
            }
        }
    }

    // MARK: Scopes

    /// The four readings, one at a time.
    ///
    /// Resolve floats these over the viewer and lets a colourist show all
    /// four at once. On a 300pt column that would be four postage stamps, so
    /// this shows the one being looked at, full width — the reading stays
    /// legible, and switching is one tap.
    private var scopesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Scopes", comment: "Video Studio colour: the measurement displays")
                .font(EditorTheme.groupLabel)
                .foregroundStyle(EditorTheme.secondaryText)

            Picker("", selection: $scopes.kind) {
                ForEach(VideoScopeKind.allCases) { kind in
                    Text(kind.pickerName).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                    .fill(Color.black)
                if let picture = scopes.image {
                    scopePicture(picture)
                } else {
                    Text("Move the playhead over a clip", comment: "Video Studio scopes: nothing to measure yet")
                        .font(EditorTheme.maskSubtitle)
                        .foregroundStyle(EditorTheme.secondaryText)
                }
            }
            .frame(
                height: usesTallScopes
                    ? VideoStudioMetrics.scopeHeight
                    : VideoStudioMetrics.scopeCompactHeight
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))

            Text(scopeCaption)
                .font(EditorTheme.maskSubtitle)
                .foregroundStyle(EditorTheme.secondaryText)
        }
    }

    /// `.none` interpolation on purpose: a waveform cell is one measurement,
    /// and smoothing it invents trace where none was counted.
    @ViewBuilder
    private func scopePicture(_ picture: CGImage) -> some View {
        let image = Image(decorative: picture, scale: 1)
            .resizable()
            .interpolation(.none)
        if scopes.kind == .vectorscope {
            image.aspectRatio(1, contentMode: .fit)
        } else {
            image
        }
    }

    private var scopeCaption: String {
        switch scopes.kind {
        case .waveform:
            String(localized: "Brightness against position across frame.", comment: "Video Studio scopes: waveform")
        case .parade:
            String(localized: "Red, green and blue side by side — uneven feet mean a cast.", comment: "Video Studio scopes: parade")
        case .vectorscope:
            String(localized: "Vectorscope: hue and saturation. The diagonal line is where skin sits.", comment: "Video Studio scopes: vectorscope")
        case .histogram:
            String(localized: "How many pixels at each tone.", comment: "Video Studio scopes: histogram")
        }
    }

    // MARK: Input transform

    private var inputTransformSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Input Transform", comment: "Video Studio colour: undoing the camera's encoding")
                .font(EditorTheme.groupLabel)
                .foregroundStyle(EditorTheme.secondaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(VideoInputTransform.allCases) { transform in
                        transformChip(transform)
                    }
                }
            }

            Text(model.recipe.inputTransform.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(EditorTheme.dimText)

            if !model.recipe.inputTransform.isIdentity {
                Text(
                    "Transfer function only — a wide-gamut capture keeps its primaries.",
                    comment: "Video Studio colour: what the input transform does not do"
                )
                .font(.system(size: 10.5))
                .foregroundStyle(EditorTheme.dimText)
            }
        }
        .padding(.top, AppTheme.Spacing.md)
    }

    private func transformChip(_ transform: VideoInputTransform) -> some View {
        let isOn = model.recipe.inputTransform == transform
        return Button { model.setInputTransform(transform) } label: {
            Text(transform.title)
                .font(EditorTheme.pillLabel)
                .foregroundStyle(isOn ? Color.black : Color.white)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    Capsule().fill(isOn ? EditorTheme.accent : EditorTheme.trackChip)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: Primaries

    private var primariesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Primaries", comment: "Video Studio colour: the three grading wheels")
                    .font(EditorTheme.groupLabel)
                    .foregroundStyle(EditorTheme.secondaryText)
                Spacer(minLength: 0)
                Button {
                    model.resetColor()
                } label: {
                    Text("Reset", comment: "Video Studio colour: puts the whole grade back to neutral")
                        .font(EditorTheme.pillLabel)
                        .foregroundStyle(EditorTheme.accent)
                }
                .buttonStyle(.plain)
                .disabled(model.recipe.color.isIdentity)
            }

            Picker("Region", selection: $region) {
                ForEach(ColorGradingRegion.allCases) { region in
                    Text(region.displayName).tag(region)
                }
            }
            .pickerStyle(.segmented)

            EditorColorWheel(
                hue: wheel.hue,
                saturation: wheel.saturation,
                diameter: 150,
                onBegin: { model.pushUndo() },
                onChange: { hue, saturation in
                    model.setGradingWheel(region, hue: hue, saturation: saturation)
                },
                onEnd: {},
                onReset: { model.resetGrading(region) }
            )
            .frame(maxWidth: .infinity)

            InspectorSlider(
                label: "Luminance",
                value: wheel.luminance,
                range: -1...1,
                valueText: String(format: "%+.2f", wheel.luminance),
                model: model,
                set: { model.setGradingLuminance(region, $0) },
                reset: { model.pushUndo(); model.setGradingLuminance(region, 0) }
            )
        }
    }

    private var wheel: ColorGradingAdjustments.Wheel {
        model.recipe.color.grading[region]
    }

    // MARK: Curves

    private var curvesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Curves", comment: "Video Studio colour: the point tone curve")
                    .font(EditorTheme.groupLabel)
                    .foregroundStyle(EditorTheme.secondaryText)
                Spacer(minLength: 0)
                Button { model.resetCurve(curveChannel) } label: {
                    Text("Reset", comment: "Video Studio colour: straightens the shown channel's curve")
                        .font(EditorTheme.pillLabel)
                        .foregroundStyle(EditorTheme.accent)
                }
                .buttonStyle(.plain)
                .disabled(model.recipe.curve[curveChannel] == ToneCurveAdjustments.linear)
            }

            Picker("Channel", selection: $curveChannel) {
                ForEach(ToneCurveChannel.allCases) { channel in
                    Text(channel.displayName).tag(channel)
                }
            }
            .pickerStyle(.segmented)

            VideoCurvePlot(model: model, channel: curveChannel)

            Text(
                "Tap to add a point, drag it off the plot to remove it.",
                comment: "Video Studio colour: how the curve plot is edited"
            )
            .font(.system(size: 10.5))
            .foregroundStyle(EditorTheme.dimText)
        }
    }

    // MARK: Colour mixer

    /// Per-band hue, saturation and luminance — the HSL wheel a colourist
    /// reaches for when one colour in the frame is the problem and the rest
    /// of the picture is fine.
    private var mixerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Color Mixer", comment: "Video Studio colour: per-band HSL")
                    .font(EditorTheme.groupLabel)
                    .foregroundStyle(EditorTheme.secondaryText)
                Spacer(minLength: 0)
                Button { model.resetMixerBand(band) } label: {
                    Text("Reset", comment: "Video Studio colour: clears the shown band")
                        .font(EditorTheme.pillLabel)
                        .foregroundStyle(EditorTheme.accent)
                }
                .buttonStyle(.plain)
                .disabled(model.recipe.color.mixer[band].isIdentity)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ColorMixerBand.allCases) { candidate in
                        bandChip(candidate)
                    }
                }
            }

            ForEach(ColorMixerProperty.allCases) { property in
                InspectorSlider(
                    label: property.displayName,
                    value: model.recipe.color.mixer[band][property],
                    range: -1...1,
                    valueText: String(format: "%+.0f", model.recipe.color.mixer[band][property] * 100),
                    model: model,
                    set: { model.setMixer(band, property, $0) },
                    reset: { model.pushUndo(); model.setMixer(band, property, 0) }
                )
            }
        }
    }

    private func bandChip(_ candidate: ColorMixerBand) -> some View {
        let isOn = candidate == band
        let touched = !model.recipe.color.mixer[candidate].isIdentity
        return Button { band = candidate } label: {
            Text(candidate.displayName)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(isOn ? Color.black : Color.white)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(Capsule().fill(isOn ? EditorTheme.accent : EditorTheme.trackChip))
                .overlay(alignment: .topTrailing) {
                    // A dot on a band that has been dialled: without it the
                    // only way to find your own edits is to tap all eight.
                    if touched, !isOn {
                        Circle()
                            .fill(EditorTheme.accent)
                            .frame(width: 5, height: 5)
                            .offset(x: -3, y: 3)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: Windows and qualifiers

    /// Resolve calls these power windows and the HSL qualifier; the model
    /// behind them is the photo editor's own `PhotoMask`, so a window means
    /// the same thing in both editors.
    private var windowsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Windows & Qualifiers", comment: "Video Studio colour: masked, local grades")
                .font(EditorTheme.groupLabel)
                .foregroundStyle(EditorTheme.secondaryText)

            HStack(spacing: 6) {
                ForEach(VideoMaskRenderer.supportedKinds) { kind in
                    Button { model.addMask(kind) } label: {
                        VStack(spacing: 3) {
                            Image(systemName: kind.videoSystemImage)
                                .font(.system(size: 14, weight: .medium))
                            Text(kind.displayName)
                                .font(.system(size: 9.5, weight: .medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: VideoStudioMetrics.commandCellRadius, style: .continuous)
                                .fill(EditorTheme.trackChip)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Add \(kind.displayName) window", comment: "Video Studio colour: adds one local grade"))
                }
            }

            if model.recipe.masks.isEmpty {
                Text(
                    "A window grades part of the frame. Brush, subject and sky are photo-only — they need a pass per frame.",
                    comment: "Video Studio colour: empty state for windows, and which kinds are absent"
                )
                .font(.system(size: 11))
                .foregroundStyle(EditorTheme.dimText)
            }

            ForEach(model.recipe.masks) { mask in
                maskRow(mask)
            }

            if let mask = model.selectedMask {
                maskControls(mask)
            }
        }
    }

    private func maskRow(_ mask: PhotoMask) -> some View {
        let isOn = mask.id == model.selectedMaskID
        return HStack(spacing: 8) {
            Button { model.selectedMaskID = isOn ? nil : mask.id } label: {
                Text(mask.name)
                    .font(.system(size: 12, weight: isOn ? .semibold : .regular))
                    .foregroundStyle(isOn ? EditorTheme.accent : .white)
                Spacer(minLength: 0)
            }
            .buttonStyle(.plain)

            Button { model.toggleMaskInverted(mask.id) } label: {
                Image(systemName: mask.isInverted ? "circle.righthalf.filled" : "circle.lefthalf.filled")
                    .foregroundStyle(mask.isInverted ? EditorTheme.accent : EditorTheme.dimText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Invert window", comment: "Video Studio colour: grades outside the window instead of inside"))

            Button { model.toggleMaskVisible(mask.id) } label: {
                Image(systemName: mask.isVisible ? "eye" : "eye.slash")
                    .foregroundStyle(mask.isVisible ? EditorTheme.dimText : EditorTheme.timelineDestructive)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Show window", comment: "Video Studio colour: turns one window off without deleting it"))

            Button { model.removeMask(mask.id) } label: {
                Image(systemName: "trash")
                    .foregroundStyle(EditorTheme.timelineDestructive)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Delete window", comment: "Video Studio colour"))
        }
        .font(.system(size: 13))
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func maskControls(_ mask: PhotoMask) -> some View {
        if let component = mask.components.first {
            VStack(spacing: 0) {
                switch component.kind {
                case .radialGradient:
                    slider("Size", component.radiusX, 0.05...1) { value in
                        model.updateSelectedMaskComponent { $0.radiusX = value; $0.radiusY = value }
                    }
                    slider("Feather", component.feather, 0...1) { value in
                        model.updateSelectedMaskComponent { $0.feather = value }
                    }
                case .luminanceRange:
                    slider("From", component.luminanceMinimum, 0...1) { value in
                        model.updateSelectedMaskComponent { $0.luminanceMinimum = value }
                    }
                    slider("To", component.luminanceMaximum, 0...1) { value in
                        model.updateSelectedMaskComponent { $0.luminanceMaximum = value }
                    }
                case .colorRange:
                    slider("Tolerance", component.colorTolerance, 0.02...1) { value in
                        model.updateSelectedMaskComponent { $0.colorTolerance = value }
                    }
                default:
                    EmptyView()
                }
                // What the window actually does to the picture it covers.
                slider("Exposure", mask.adjustments[.exposure], -1...1) { value in
                    model.updateSelectedMaskAdjustment(.exposure, value: value)
                }
                slider("Saturation", mask.adjustments[.saturation], -1...1) { value in
                    model.updateSelectedMaskAdjustment(.saturation, value: value)
                }
            }
        }
    }

    private func slider(
        _ label: String,
        _ value: Double,
        _ range: ClosedRange<Double>,
        set: @escaping (Double) -> Void
    ) -> some View {
        InspectorSlider(
            label: label,
            value: value,
            range: range,
            valueText: String(format: "%.2f", value),
            model: model,
            set: set,
            reset: { model.pushUndo(); set(range.lowerBound <= 0 ? 0 : range.lowerBound) }
        )
    }
}

extension PhotoMaskComponentKind {
    /// The glyph the Video Studio uses for each window it supports.
    var videoSystemImage: String {
        switch self {
        case .radialGradient: "circle.dashed"
        case .linearGradient: "line.diagonal"
        case .luminanceRange: "circle.lefthalf.filled"
        case .colorRange: "eyedropper"
        default: "square.dashed"
        }
    }
}
