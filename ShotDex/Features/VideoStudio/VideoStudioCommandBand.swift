import SwiftUI

// MARK: - Floating top command band (spec §2)

/// The phone's top band over the Dynamic Island (FS-12.07 §2): Back · Undo
/// · Redo on the leading edge, Video Settings · Export on the trailing one,
/// 36pt discs, nothing over the island. Wide windows have their own bands
/// (`VideoStudioDeskBand`, the Duo's discs and rail).
struct VideoStudioTopBand: View {
    @Bindable var model: VideoStudioModel
    let phoneActions: VideoInspectorActions

    var body: some View {
        phoneRow(phoneActions)
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
        let preset = model.recipe.resolution.displayName
        let fps = VideoStudioCopy.framesPerSecond(model.recipe.frameRate.rawValue)
        Button {
            model.toggleToolPanel(.videoSettings)
        } label: {
            HStack(spacing: 6) {
                ratioGlyph
                if isTwoLine {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: "\(ratio) · \(preset)")
                            .font(.system(size: 13, weight: .semibold))
                        Text(verbatim: "\(fps) · \(VideoExportEstimate.label(model.estimatedExportBytes))")
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
            .padding(.horizontal, 9)
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
