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
    @State private var renamingNodeID: UUID?
    @State private var draftNodeName = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                scopesSection
                Divider().overlay(EditorTheme.panelDivider)
                nodesSection
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
        .alert(
            Text("Rename Node", comment: "Video Studio colour: title of the node rename prompt"),
            isPresented: Binding(
                get: { renamingNodeID != nil },
                set: { if !$0 { renamingNodeID = nil } }
            )
        ) {
            TextField(
                String(localized: "Name", comment: "Video Studio colour: the node name field"),
                text: $draftNodeName
            )
            Button {
                if let id = renamingNodeID { model.renameNode(id, to: draftNodeName) }
                renamingNodeID = nil
            } label: {
                Text("Rename", comment: "Video Studio colour: confirms the new node name")
            }
            Button(role: .cancel) {
                renamingNodeID = nil
            } label: {
                Text("Cancel", comment: "Video Studio colour: dismisses the node rename prompt")
            }
        } message: {
            Text(
                "Leave it empty to go back to its number.",
                comment: "Video Studio colour: what an empty node name does"
            )
        }
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

    // MARK: The grading chain

    /// The node chain, as a row read left to right — which is the order the
    /// corrections run in.
    ///
    /// Resolve draws this as a graph on a canvas because its nodes branch.
    /// These do not: a serial chain is a list, and a list on a 320pt column
    /// is a row of chips with the selected one lit. Everything under this
    /// section edits the selected node.
    private var nodesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Nodes", comment: "Video Studio colour: the chain of corrections")
                    .font(EditorTheme.groupLabel)
                    .foregroundStyle(EditorTheme.secondaryText)
                Spacer(minLength: 0)
                Button { model.addNode() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(EditorTheme.accent)
                        .frame(width: 28, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Add Node", comment: "Video Studio colour: adds a correction after the selected one"))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(model.recipe.nodes.enumerated()), id: \.element.id) { index, node in
                        nodeChip(node, at: index)
                    }
                }
            }

            Text(nodeHint)
                .font(.system(size: 10.5))
                .foregroundStyle(EditorTheme.dimText)
        }
    }

    private var nodeHint: String {
        model.recipe.nodes.count > 1
            ? String(
                localized: "Corrections run left to right. Long-press a node to reorder, rename or bypass it.",
                comment: "Video Studio colour: how the node chain works"
            )
            : String(
                localized: "One correction. Add another to keep a look apart from the balance under it.",
                comment: "Video Studio colour: why a second node is useful"
            )
    }

    private func nodeChip(_ node: ColorNode, at index: Int) -> some View {
        let isSelected = model.activeNode.id == node.id
        return Button {
            model.selectedNodeID = node.id
            // A window belongs to its node; keeping the old selection would
            // point the mask controls at something that is not in this node.
            model.selectedMaskID = node.masks.first?.id
        } label: {
            HStack(spacing: 4) {
                if !node.isEnabled {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 9, weight: .semibold))
                }
                Text(node.displayName(at: index))
                    .lineLimit(1)
                // A dot for "this node does something", so a chain of four
                // says at a glance which of them is carrying the grade.
                if !node.isIdentity {
                    Circle()
                        .fill(isSelected ? Color.black.opacity(0.55) : EditorTheme.accent)
                        .frame(width: 5, height: 5)
                }
            }
            .opacity(node.isEnabled ? 1 : 0.5)
        }
        .buttonStyle(EditorChipButtonStyle(isSelected: isSelected))
        .contextMenu {
            Button {
                model.toggleNodeEnabled(node.id)
            } label: {
                Label {
                    node.isEnabled
                        ? Text("Bypass", comment: "Video Studio colour: switches a node off without deleting it")
                        : Text("Enable", comment: "Video Studio colour: switches a bypassed node back on")
                } icon: {
                    Image(systemName: node.isEnabled ? "eye.slash" : "eye")
                }
            }
            Button {
                model.duplicateNode(node.id)
            } label: {
                Label {
                    Text("Duplicate", comment: "Video Studio colour: copies a node after itself")
                } icon: {
                    Image(systemName: "plus.square.on.square")
                }
            }
            Button {
                renamingNodeID = node.id
                draftNodeName = node.name
            } label: {
                Label {
                    Text("Rename…", comment: "Video Studio colour: names a node")
                } icon: {
                    Image(systemName: "pencil")
                }
            }

            Section {
                Button {
                    model.moveNode(node.id, by: -1)
                } label: {
                    Label {
                        Text("Move Earlier", comment: "Video Studio colour: runs this correction before the one on its left")
                    } icon: {
                        Image(systemName: "arrow.left")
                    }
                }
                .disabled(index == 0)
                Button {
                    model.moveNode(node.id, by: 1)
                } label: {
                    Label {
                        Text("Move Later", comment: "Video Studio colour: runs this correction after the one on its right")
                    } icon: {
                        Image(systemName: "arrow.right")
                    }
                }
                .disabled(index == model.recipe.nodes.count - 1)
            }

            Section {
                Button {
                    model.resetNode(node.id)
                } label: {
                    Label {
                        Text("Reset Node", comment: "Video Studio colour: clears this correction and keeps it in the chain")
                    } icon: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                }
                .disabled(node.isIdentity)
                Button(role: .destructive) {
                    model.deleteNode(node.id)
                } label: {
                    Label {
                        Text("Delete Node", comment: "Video Studio colour")
                    } icon: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .accessibilityLabel(Text(node.displayName(at: index)))
        .accessibilityValue(
            node.isEnabled
                ? Text("Active", comment: "Video Studio colour: VoiceOver value for a node that is running")
                : Text("Bypassed", comment: "Video Studio colour: VoiceOver value for a node that is switched off")
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                .disabled(model.activeNode.color.isIdentity)
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
        model.activeNode.color.grading[region]
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
                .disabled(model.activeNode.curve[curveChannel] == ToneCurveAdjustments.linear)
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
                .disabled(model.activeNode.color.mixer[band].isIdentity)
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
                    value: model.activeNode.color.mixer[band][property],
                    range: -1...1,
                    valueText: String(format: "%+.0f", model.activeNode.color.mixer[band][property] * 100),
                    model: model,
                    set: { model.setMixer(band, property, $0) },
                    reset: { model.pushUndo(); model.setMixer(band, property, 0) }
                )
            }
        }
    }

    private func bandChip(_ candidate: ColorMixerBand) -> some View {
        let isOn = candidate == band
        let touched = !model.activeNode.color.mixer[candidate].isIdentity
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

            if model.activeNode.masks.isEmpty {
                Text(
                    "A window grades part of the frame. Brush, subject and sky are photo-only — they need a pass per frame.",
                    comment: "Video Studio colour: empty state for windows, and which kinds are absent"
                )
                .font(.system(size: 11))
                .foregroundStyle(EditorTheme.dimText)
            }

            ForEach(model.activeNode.masks) { mask in
                maskRow(mask)
            }

            if let mask = model.selectedMask {
                trackerRow(mask)
                maskControls(mask)
            }
        }
    }

    /// Following a window across a shot.
    ///
    /// Resolve puts this on the window itself and so does this: the control
    /// is next to the thing it moves. What it recovers is where the subject
    /// is and how big — position and size — because that is what Vision's
    /// tracker returns. A window that needs to roll with the camera is one
    /// this cannot follow, and the note says so rather than leaving the user
    /// to discover it on a shot.
    @ViewBuilder
    private func trackerRow(_ mask: PhotoMask) -> some View {
        let isTracking = model.trackingMaskID == mask.id
        let track = model.activeNode.track(for: mask.id)

        VStack(alignment: .leading, spacing: 6) {
            if isTracking {
                HStack(spacing: 8) {
                    ProgressView(value: model.trackingProgress)
                        .tint(EditorTheme.accent)
                    Button { model.cancelTracking() } label: {
                        Text("Stop", comment: "Video Studio colour: abandons a window track in progress")
                            .font(EditorTheme.pillLabel)
                            .foregroundStyle(EditorTheme.timelineDestructive)
                    }
                    .buttonStyle(.plain)
                }
            } else if model.canTrack(mask) {
                HStack(spacing: 8) {
                    Button { model.trackWindow(mask.id) } label: {
                        Label {
                            track == nil
                                ? Text("Track Forward", comment: "Video Studio colour: follows the window through the rest of the clip")
                                : Text("Track Again", comment: "Video Studio colour: replaces an existing window track")
                        } icon: {
                            Image(systemName: "dot.viewfinder")
                        }
                        .font(EditorTheme.rowLabel)
                        .foregroundStyle(EditorTheme.accent)
                    }
                    .buttonStyle(.plain)

                    if track != nil {
                        Spacer(minLength: 0)
                        Button { model.clearTrack(mask.id) } label: {
                            Text("Clear Track", comment: "Video Studio colour: puts the window back where it was drawn")
                                .font(EditorTheme.pillLabel)
                                .foregroundStyle(EditorTheme.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text(trackerNote(mask, track: track))
                .font(.system(size: 10.5))
                .foregroundStyle(EditorTheme.dimText)
        }
        .padding(.vertical, 2)
    }

    private func trackerNote(_ mask: PhotoMask, track: MaskTrack?) -> String {
        guard let component = mask.components.first else { return "" }
        guard MaskTrackMath.isTrackable(component.kind) else {
            return String(
                localized: "A qualifier picks by colour or brightness, not by place, so there is nothing to follow.",
                comment: "Video Studio colour: why a qualifier cannot be tracked"
            )
        }
        if model.trackingMaskID == mask.id {
            return String(
                localized: "Following the subject from the playhead.",
                comment: "Video Studio colour: the tracker is running"
            )
        }
        if let range = track?.timeRange {
            return String(
                localized: "Tracked \(VideoStudioMetrics.timecode(range.lowerBound)) to \(VideoStudioMetrics.timecode(range.upperBound)). Position and size only — a window cannot roll with the camera.",
                comment: "Video Studio colour: what the existing window track covers and what it does not"
            )
        }
        if !model.canTrack(mask) {
            return String(
                localized: "Park the playhead on a video clip to follow this window.",
                comment: "Video Studio colour: tracking needs moving footage under the playhead"
            )
        }
        return String(
            localized: "Put the window on the subject, then track forward. Position and size only.",
            comment: "Video Studio colour: how to start a window track"
        )
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
