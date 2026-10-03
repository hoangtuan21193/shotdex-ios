import SwiftUI

// MARK: - Floating top command band (spec §2)

/// The band over the Dynamic Island, mirroring the photo editor's: Undo · Redo
/// on the leading edge; a running playback timecode on the trailing edge.
/// Every control is a 34pt dark-glass circle. Back and Export live on the
/// bottom bar, where they have always been.
struct VideoStudioTopBand: View {
    @Bindable var model: VideoStudioModel
    /// On a regular-width window the band also carries the project's own
    /// controls — Back, the read-out and Export — because the bottom band
    /// they used to live in is not drawn there. Every tablet editor
    /// surveyed keeps the primary output action in the top bar; having it at
    /// the bottom is what let the contextual panel cover it.
    var projectActions: VideoInspectorActions?
    /// Points the stage column actually has. The band shares that column with
    /// the frame, so on a window carrying a rail, a media pool, a meter and
    /// an inspector it can be half the window wide — measured 489pt on the
    /// iPhone Duo's inner display, where the full row wrapped its timecode
    /// onto two lines.
    var stageWidth: CGFloat = .greatestFiniteMagnitude
    /// Extra room on the trailing edge when this band runs to the screen's
    /// own rounded corner — see `VideoStudioMetrics.displayCornerClearance`.
    var trailingCornerClearance: CGFloat = 0
    /// `true` where the tool rail is gone and the project-wide tools need a
    /// home in this band — Resolve keeps format and its like behind a
    /// settings control in the chrome, not on a tool column.
    var carriesProjectTools = false
    /// On a phone the band carries the whole chrome (FS-12.07 §2): Back,
    /// Undo, Redo · Video Settings, Export. There is no bottom band.
    var phoneActions: VideoInspectorActions?

    @Environment(\.usesRegularToolChrome) private var usesRegularToolChrome

    /// What the row drops first when the column is too narrow for all of it.
    ///
    /// The timecode goes first: the viewer header prints the project's length
    /// and the transport prints the playhead, both in full `hh:mm:ss:ff`, so
    /// the pill is the one read-out on screen that is said twice. The export
    /// estimate goes second. Back and Export never go — they are the way out
    /// of the screen and the point of it.
    ///
    /// The project-tools menu is a sixth control in a row that was already
    /// budgeted, so when it is there both thresholds move up by more than its
    /// own width: the row has to stay comfortable, not merely fit.
    private var toolsBudget: CGFloat { carriesProjectTools ? 80 : 0 }
    private var showsTimecode: Bool { projectActions == nil || stageWidth >= 540 + toolsBudget }
    private var showsReadout: Bool { projectActions == nil || stageWidth >= 430 + toolsBudget }
    private var size: CGFloat {
        EditorLayoutMetrics.editorFloatingCommandButtonSize(
            isRegularWidth: usesRegularToolChrome
        )
    }
    private let inset = EditorLayoutMetrics.editorFloatingCommandSideInset

    var body: some View {
        if let phoneActions {
            phoneRow(phoneActions)
        } else {
            deskRow
        }
    }

    /// Back · Undo · Redo on the leading edge, Video Settings · Export on the
    /// trailing one, 36pt discs at the island's height and nothing over the
    /// island itself (FS-12.07 §2, board Main).
    private func phoneRow(_ actions: VideoInspectorActions) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: VideoStudioMetrics.phoneBandLeadingGap) {
                disc(systemName: "chevron.left", isEnabled: true, action: actions.onBack)
                    .accessibilityLabel(Text("Back", comment: "Video Studio: leaves the editor"))
                disc(systemName: "arrow.uturn.backward", isEnabled: model.canUndo) { model.undo() }
                    .accessibilityLabel("Undo")
                disc(systemName: "arrow.uturn.forward", isEnabled: model.canRedo) { model.redo() }
                    .accessibilityLabel("Redo")
            }
            Spacer(minLength: 0)
            HStack(spacing: VideoStudioMetrics.phoneBandTrailingGap) {
                videoSettingsDisc
                Button(action: actions.onExport) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: VideoStudioMetrics.phoneBandButton, height: VideoStudioMetrics.phoneBandButton)
                        .background(Circle().fill(EditorTheme.accent))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Export", comment: "Video Studio: renders the video and saves it"))
            }
        }
        .padding(.horizontal, VideoStudioMetrics.phoneBandInset)
        .padding(.top, VideoStudioMetrics.phoneBandTop)
        .frame(height: VideoStudioMetrics.phoneBandTop + VideoStudioMetrics.phoneBandButton, alignment: .top)
    }

    /// A 36pt disc on white 10 %, glyph white — dim when it cannot act.
    private func disc(systemName: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isEnabled ? Color.white : Color.white.opacity(0.28))
                .frame(width: VideoStudioMetrics.phoneBandButton, height: VideoStudioMetrics.phoneBandButton)
                .background(Circle().fill(Color.white.opacity(0.10)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    /// Video Settings, drawn as the project's own shape: the glyph is a frame
    /// in the project's ratio, so the button says what it changes.
    private var videoSettingsDisc: some View {
        let ratio = model.recipe.aspect.ratio
        let side: CGFloat = 18
        let glyph = CGSize(
            width: ratio >= 1 ? side : side * ratio,
            height: ratio >= 1 ? side / ratio : side
        )
        let isOpen = model.activeToolPanel == .videoSettings
        return Button {
            model.toggleToolPanel(.videoSettings)
        } label: {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(isOpen ? Color.black : Color.white, lineWidth: 1.8)
                .frame(width: glyph.width, height: glyph.height)
                .frame(width: VideoStudioMetrics.phoneBandButton, height: VideoStudioMetrics.phoneBandButton)
                .background(Circle().fill(isOpen ? Color.white : Color.white.opacity(0.10)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(VideoStudioCopy.videoSettings)
        .accessibilityValue(model.recipe.aspect.displayName)
        .accessibilityAddTraits(isOpen ? .isSelected : [])
    }

    private var deskRow: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            if let projectActions {
                Button(action: projectActions.onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: size, height: size)
                        .background { Color.clear.editorGlass(Circle()) }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Spacer(minLength: 8)
            }
            circle("arrow.uturn.backward", isEnabled: model.canUndo) { model.undo() }
                .accessibilityLabel("Undo")
            circle("arrow.uturn.forward", isEnabled: model.canRedo) { model.redo() }
                .accessibilityLabel("Redo")
            // Hold-to-compare moved to the Look panel's title (FS-12.04 §4):
            // it compares the look, so it lives where the look is changed.
            if !carriesProjectTools { videoSettingsCircle }

            Spacer(minLength: 8)

            if showsTimecode { timecodePill }

            if carriesProjectTools { projectToolsMenu }

            if let projectActions {
                if showsReadout { readout }
                Button(action: projectActions.onExport) {
                    Text("Export")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 20)
                        .frame(height: size)
                        .background(Capsule().fill(EditorTheme.accent))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: size)
        .padding(.horizontal, inset)
        .padding(.trailing, trailingCornerClearance)
        // Inset the row from the band's top so it sits level with the Dynamic
        // Island, exactly like the photo editor's floating command row.
        .padding(.top, EditorLayoutMetrics.editorFloatingCommandRowTopInset)
    }

    /// The project-wide tools, where Resolve keeps the equivalent: behind a
    /// settings control in the chrome rather than on a column of their own.
    /// Each one opens the inspector on that tool, which is where its controls
    /// have always lived — this menu replaces the rail cell that used to open
    /// the same panel, not the panel.
    private var projectToolsMenu: some View {
        Menu {
            ForEach([VideoToolPanel.look, .videoSettings]) { panel in
                Button {
                    model.toggleToolPanel(panel)
                } label: {
                    Label(panel.title, systemImage: panel.systemImage)
                }
                // A stable handle for the UI driver.
                .accessibilityIdentifier("projectTool.\(panel.id)")
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background {
                    if model.activeToolPanel == nil {
                        Color.clear.editorGlass(Circle())
                    } else {
                        Circle().fill(VideoStudioMetrics.openCellFill)
                    }
                }
                .contentShape(Circle())
        }
        .accessibilityLabel(Text("Project Tools", comment: "Video Studio: opens ratio, look, adjustments, volume and background"))
    }

    /// Video Settings: the project's shape and what is behind it. Lit while
    /// its panel is open, white not accent.
    private var videoSettingsCircle: some View {
        Button {
            model.toggleToolPanel(.videoSettings)
        } label: {
            Image(systemName: VideoToolPanel.videoSettings.systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background {
                    if model.activeToolPanel == .videoSettings {
                        Circle().fill(VideoStudioMetrics.openCellFill)
                    } else {
                        Color.clear.editorGlass(Circle())
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(VideoStudioCopy.videoSettings)
        .accessibilityAddTraits(model.activeToolPanel == .videoSettings ? .isSelected : [])
    }

    /// Duration, preset and the size estimate — the same two lines the bottom
    /// band showed, beside Export rather than away from it.
    private var readout: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(VideoStudioMetrics.exportReadout(
                duration: model.totalDuration,
                presetName: model.recipe.renderPreset.displayName
            ))
            Text("~\(ByteCountFormatter.string(fromByteCount: model.estimatedExportBytes, countStyle: .file))")
        }
        .font(EditorTheme.rowValue)
        .foregroundStyle(EditorTheme.dimText)
        // Never wrap: a read-out broken across three lines in a 48pt band is
        // worse than no read-out, and the thresholds above are what decide
        // whether it is shown at all.
        .lineLimit(1)
        .fixedSize()
        .padding(.leading, 8)
        .accessibilityElement(children: .combine)
    }

    private var timecodePill: some View {
        HStack(spacing: 0) {
            Text(timecode(model.currentTime))
            Text(" / \(timecode(model.totalDuration))").foregroundStyle(.white.opacity(0.4))
        }
        .font(.system(size: 12, weight: .semibold).monospacedDigit())
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 29)
        .background(
            RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous)
                .fill(EditorTheme.trackChip)
        )
        .accessibilityLabel("\(timecode(model.currentTime)) of \(timecode(model.totalDuration))")
    }

    private func timecode(_ seconds: Double) -> String {
        VideoStudioMetrics.compactTimecode(seconds)
    }

    private func circle(_ systemName: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isEnabled ? Color.white.opacity(0.9) : Color.white.opacity(0.28))
                .frame(width: size, height: size)
                .background { Color.clear.editorGlass(Circle()) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

// MARK: - Inspector icon command band (spec §5.3)

/// One command in the inspector's icon band. `tint` distinguishes the accent
/// Add and the destructive Delete from the neutral commands.
struct VideoCommand: Identifiable {
    enum Tint { case normal, accent, destructive }
    let id = UUID()
    let title: LocalizedStringKey
    let systemImage: String
    var tint: Tint = .normal
    var isEnabled = true
    /// The cell whose panel is open: drawn on white 14 %, never accent —
    /// accent is Export's alone (FS-12.04 §3, DESIGN §3.1).
    var isOpen = false
    let action: () -> Void
}

// MARK: - iPad top band (FS-12.03 §2–3)

/// The iPad's top band, 0–64: Back · Undo · Redo · Show original from x 20 on
/// the leading edge; "5 clips · 16:9 · 0:24" in the middle — the project has
/// no name, so this is what the band says about it; the size read-out, the
/// Video Settings button and Export on the trailing edge. Export and the
/// settings button stay while an item is selected: the inspector's footer
/// carries ✕ · ✓, so the band never has to make way.
struct VideoStudioDeskBand: View {
    @Bindable var model: VideoStudioModel
    let actions: VideoInspectorActions
    /// Portrait folds the settings button onto two lines — ratio and
    /// resolution over frame rate and size — and drops the separate read-out.
    var isPortrait = false

    private typealias Geometry = VideoStudioDeskGeometry

    var body: some View {
        ZStack {
            Text(projectSummary)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(EditorTheme.dimText)
                .lineLimit(1)
            HStack(spacing: Geometry.bandDiscGap) {
                disc("chevron.left", isEnabled: true, action: actions.onBack)
                    .accessibilityLabel(Text("Back", comment: "Video Studio: leaves the editor"))
                disc("arrow.uturn.backward", isEnabled: model.canUndo) { model.undo() }
                    .accessibilityLabel("Undo")
                disc("arrow.uturn.forward", isEnabled: model.canRedo) { model.redo() }
                    .accessibilityLabel("Redo")
                VideoShowOriginalButton(model: model, diameter: Geometry.bandDisc)
                Spacer(minLength: 0)
                if !isPortrait { readout.padding(.trailing, 6) }
                VideoSettingsButton(model: model, isTwoLine: isPortrait)
                exportPill
            }
            .padding(.horizontal, Geometry.bandInset)
        }
        .frame(height: Geometry.bandDisc)
        .padding(.top, Geometry.bandRowTop)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// "5 clips · 16:9 · 0:24".
    private var projectSummary: String {
        VideoStudioCopy.projectSummary(
            clips: model.recipe.clips.count,
            ratio: model.recipe.aspect.displayName,
            length: VideoStudioMetrics.shortDuration(model.totalDuration)
        )
    }

    /// "0:24 · ~30 MB".
    private var readout: some View {
        Text(VideoStudioMetrics.lengthAndSize(duration: model.totalDuration, bytes: model.estimatedExportBytes))
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(EditorTheme.dimText)
            .lineLimit(1)
            .fixedSize()
            .padding(.trailing, 4)
    }

    private var exportPill: some View {
        Button(action: actions.onExport) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 14, weight: .semibold))
                Text("Export", comment: "Video Studio: renders the video and saves it")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 18)
            .frame(height: Geometry.exportHeight)
            .background(Capsule().fill(EditorTheme.accent))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.leading, 4)
    }

    /// A 40pt disc on white 10 %, glyph white — dim when it cannot act.
    private func disc(_ systemName: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isEnabled ? Color.white : Color.white.opacity(0.28))
                .frame(width: Geometry.bandDisc, height: Geometry.bandDisc)
                .background(Circle().fill(Color.white.opacity(0.10)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

/// Show original: press and hold to see the clips without the look — the
/// filter, the adjustments, the grade — and without overlays. One control,
/// wherever it is drawn: the iPad's top band, the Duo's floating discs, the
/// Look panel's title.
struct VideoShowOriginalButton: View {
    @Bindable var model: VideoStudioModel
    var diameter: CGFloat
    var glyphSize: CGFloat = 15
    /// The resting fill — the band's white 10 %, or the Duo's dark disc.
    var restingFill: Color = Color.white.opacity(0.10)

    var body: some View {
        let isEnabled = model.hasEdits
        Image(systemName: "rectangle.on.rectangle")
            .font(.system(size: glyphSize, weight: .medium))
            .foregroundStyle(
                model.showsOriginal ? Color.black : (isEnabled ? Color.white : Color.white.opacity(0.28))
            )
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(model.showsOriginal ? Color.white : restingFill))
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard isEnabled, !model.showsOriginal else { return }
                        model.setShowsOriginal(true)
                    }
                    .onEnded { _ in model.setShowsOriginal(false) }
            )
            .allowsHitTesting(isEnabled)
            .accessibilityElement()
            .accessibilityLabel(Text("Show original", comment: "Video Studio: press-and-hold control that previews the clips without edits"))
            .accessibilityHint(Text("Press and hold to see the clips without edits", comment: "Hint for the Video Studio before/after control"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(model.showsOriginal ? .isSelected : [])
    }
}

/// The Video Settings button of a wide window: the project's shape as a
/// glyph, then what it exports — "16:9 · 1080p · 30 fps" on one line, or on
/// two ("16:9 · 1080p" over "30 fps · ~30 MB") where the band is narrow.
struct VideoSettingsButton: View {
    @Bindable var model: VideoStudioModel
    var isTwoLine = false

    var body: some View {
        let isOpen = model.activeToolPanel == .videoSettings
        let ratio = model.recipe.aspect.displayName
        let preset = model.recipe.renderPreset.displayName
        let fps = VideoStudioCopy.framesPerSecond(30)
        Button {
            model.toggleToolPanel(.videoSettings)
        } label: {
            HStack(spacing: 7) {
                ratioGlyph
                if isTwoLine {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: "\(ratio) · \(preset)")
                            .font(.system(size: 13, weight: .semibold))
                        Text(verbatim: "\(fps) · ~\(ByteCountFormatter.string(fromByteCount: model.estimatedExportBytes, countStyle: .file))")
                            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.5))
                    }
                } else {
                    Text(verbatim: "\(ratio) · \(preset) · \(fps)")
                        .font(.system(size: 13, weight: .semibold))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: isTwoLine ? 40 : VideoStudioDeskGeometry.settingsButtonHeight)
            .background(
                RoundedRectangle(
                    cornerRadius: isTwoLine ? 10 : VideoStudioDeskGeometry.settingsButtonRadius,
                    style: .continuous
                )
                .fill(isOpen ? VideoStudioMetrics.openCellFill : Color.white.opacity(0.08))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(Text(verbatim: "\(VideoStudioCopy.videoSettings): \(ratio), \(preset), \(fps)"))
        .accessibilityAddTraits(isOpen ? .isSelected : [])
    }

    /// A frame in the project's ratio, so the button says what it changes.
    private var ratioGlyph: some View {
        let ratio = model.recipe.aspect.ratio
        let side: CGFloat = 14
        return RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .strokeBorder(Color.white, lineWidth: 1.5)
            .frame(width: ratio >= 1 ? side : side * ratio, height: ratio >= 1 ? side / ratio : side)
            .frame(width: side, height: side)
    }
}
