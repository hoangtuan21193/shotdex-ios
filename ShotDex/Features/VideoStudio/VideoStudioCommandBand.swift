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
        .accessibilityLabel(VideoStudioCopy.videoSettingsAccessibility(model.recipe))
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

// MARK: - iPad toolbar (FS-12.03 §2–3, the Mac-style canvas)

/// The iPad's toolbar row, y 24–68: glass capsules 44 tall, 12 apart, the
/// way the Mac and the redrawn iPad canvas draw a window's toolbar. Leading:
/// Media Pool (while the pool is shut) · Back · the project's summary
/// ("5 clips · 16:9 · 0:24") over its length and size — the project has no
/// name. Trailing: Undo · Redo · Show original · Video Settings · Quick
/// Adjust · Inspector · Export. Export and Video Settings stay while an item
/// is selected: the inspector's foot carries ✕ · ✓.
///
/// Tier D, so the capsules are the editor's dark glass (`editorGlass`) on
/// both sides of iOS 26 — no fourth way into glass (DESIGN §9).
struct VideoStudioDeskToolbar: View {
    @Bindable var model: VideoStudioModel
    let actions: VideoInspectorActions
    /// Nil where the pool cannot open at all; false shows the Media Pool
    /// capsule that opens it.
    var isPoolOpen: Bool?
    var isInspectorOpen: Bool
    var isQuickAdjustOpen: Bool
    /// The Export Video sheet is up: the pill goes quiet (FS-12.16 §5).
    var isExportOpen = false
    let onTogglePool: () -> Void
    let onToggleInspector: () -> Void
    let onToggleQuickAdjust: () -> Void

    private typealias Geometry = VideoStudioDeskGeometry

    var body: some View {
        HStack(spacing: Geometry.capsuleGap) {
            if isPoolOpen == false {
                capsule(width: Geometry.toolbarHeight) {
                    toolbarButton("sidebar.leading", isOn: false, action: onTogglePool)
                        .accessibilityLabel(Text("Media Pool", comment: "Video Studio: shows or hides the library column"))
                }
            }
            capsule(width: Geometry.toolbarHeight) {
                toolbarButton("chevron.left", isOn: false, action: actions.onBack)
                    .accessibilityLabel(Text("Back", comment: "Video Studio: leaves the editor"))
            }
            title
            Spacer(minLength: 0)
            capsule(width: Geometry.historyCapsuleWidth, spacing: 6) {
                toolbarButton("arrow.uturn.backward", isEnabled: model.canUndo, isOn: false) { model.undo() }
                    .accessibilityLabel("Undo")
                toolbarButton("arrow.uturn.forward", isEnabled: model.canRedo, isOn: false) { model.redo() }
                    .accessibilityLabel("Redo")
                VideoShowOriginalButton(
                    model: model,
                    diameter: Geometry.capsuleButton,
                    glyphSize: 18,
                    restingFill: .clear
                )
            }
            capsule(width: Geometry.settingsCapsuleWidth) {
                VideoSettingsButton(model: model, style: .capsule, presentsPopover: true)
            }
            capsule(width: Geometry.viewToggleCapsuleWidth, spacing: 4) {
                toolbarButton("slider.horizontal.3", isOn: isQuickAdjustOpen, action: onToggleQuickAdjust)
                    .accessibilityLabel(Text("Quick Adjust", comment: "Video Studio: shows or hides the quick slider strip under the frame"))
                toolbarButton("sidebar.trailing", isOn: isInspectorOpen, action: onToggleInspector)
                    .accessibilityLabel(Text("Inspector", comment: "Video Studio: shows or hides the controls column"))
            }
            exportPill
        }
        .padding(.leading, Geometry.toolbarLeading(isPoolOpen: isPoolOpen == true))
        .padding(.trailing, Geometry.toolbarInset)
        .frame(height: Geometry.toolbarHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// "5 clips · 16:9 · 0:24" in 20 semibold over "0:24 · ~30 MB" in 13.
    private var title: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: VideoStudioCopy.projectSummary(
                clips: model.recipe.clips.count,
                ratio: model.recipe.aspect.displayName,
                length: VideoStudioMetrics.shortDuration(model.totalDuration)
            ))
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            Text(verbatim: VideoStudioMetrics.lengthAndSize(duration: model.totalDuration, bytes: model.estimatedExportBytes))
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(EditorTheme.secondaryText)
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    private var exportPill: some View {
        Button(action: actions.onExport) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 17, weight: .semibold))
                Text("Export", comment: "Video Studio: renders the video and saves it")
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(isExportOpen ? Color.white : Color.black)
            .frame(width: Geometry.exportSize.width, height: Geometry.exportSize.height)
            .background(
                RoundedRectangle(cornerRadius: Geometry.exportRadius, style: .continuous)
                    .fill(isExportOpen ? Color.white.opacity(0.08) : EditorTheme.accent)
            )
            .contentShape(RoundedRectangle(cornerRadius: Geometry.exportRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// A glass capsule `width`×44, its buttons from 3pt inside its leading
    /// edge (the 1pt stroke and 2 of padding).
    private func capsule<Content: View>(width: CGFloat, spacing: CGFloat = 0, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: spacing) { content() }
            .padding(.leading, 3)
            .frame(width: width, height: Geometry.toolbarHeight, alignment: .leading)
            .editorGlass(Capsule())
    }

    /// A 40pt button inside a capsule: glyph 20, white; on white 14 % while
    /// what it shows is open; dim when it cannot act.
    private func toolbarButton(
        _ systemName: String,
        isEnabled: Bool = true,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isEnabled ? Color.white : Color.white.opacity(0.28))
                .frame(width: Geometry.capsuleButton, height: Geometry.capsuleButton)
                .background(Circle().fill(isOn ? VideoStudioMetrics.openCellFill : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Show original: press and hold to see the clips without the look — the
/// filter, the adjustments, the grade — and without overlays. One control,
/// wherever it is drawn: the iPad's toolbar capsule and the Duo's floating
/// discs. The phone and the Duo's cover have none until FS-12.15's Before and
/// After lands in the Look panel's title.
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
/// glyph, then what it exports — "16:9 · 1080p · 30 fps" on one line in the
/// iPad toolbar's capsule, or on two ("16:9 · 1080p" over "30 fps · ~30 MB")
/// in the Duo's bottom row.
struct VideoSettingsButton: View {
    enum Style {
        /// 222×40 inside the iPad toolbar's 226 capsule.
        case capsule
        /// Two lines, 40 tall, radius 10 — the Duo inner display's row.
        case twoLine
    }

    @Bindable var model: VideoStudioModel
    var style: Style = .twoLine
    /// The iPad opens Video Settings as a popover under the button
    /// (FS-12.10 §3) rather than in the inspector column.
    var presentsPopover = false
    @State private var isPopoverOpen = false

    var body: some View {
        let isOpen = presentsPopover ? isPopoverOpen : model.activeToolPanel == .videoSettings
        let ratio = model.recipe.aspect.displayName
        let preset = model.recipe.resolution.displayName
        let fps = VideoStudioCopy.framesPerSecond(model.recipe.frameRate.rawValue)
        Button {
            if presentsPopover {
                isPopoverOpen.toggle()
            } else {
                model.toggleToolPanel(.videoSettings)
            }
        } label: {
            switch style {
            case .twoLine:
                HStack(spacing: 6) {
                    ratioGlyph(side: 14)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: "\(ratio) · \(preset)")
                            .font(.system(size: 13, weight: .semibold))
                        Text(verbatim: "\(fps) · \(VideoExportEstimate.label(model.estimatedExportBytes))")
                            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    chevron(isOpen: isOpen)
                }
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isOpen ? VideoStudioMetrics.openCellFill : Color.white.opacity(0.08))
                )
                .contentShape(Rectangle())
            case .capsule:
                HStack(spacing: 8) {
                    ratioGlyph(side: 19)
                    Text(verbatim: "\(ratio) · \(preset) · \(fps)")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // ⌃⌄: a pop-up of settings (FS-12.10 §3).
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.leading, 14)
                .padding(.trailing, 12)
                .frame(
                    width: VideoStudioDeskGeometry.settingsCapsuleWidth - 4,
                    height: VideoStudioDeskGeometry.capsuleButton
                )
                .background(Capsule().fill(isOpen ? VideoStudioMetrics.openCellFill : .clear))
                .contentShape(Capsule())
            }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .popover(isPresented: $isPopoverOpen, arrowEdge: .top) {
            VideoSettingsPanel(model: model, onDone: { isPopoverOpen = false }, isForm: style == .capsule)
                .frame(width: VideoStudioMetrics.videoSettingsPopoverSize.width,
                       height: VideoStudioMetrics.videoSettingsPopoverSize.height)
                .presentationCompactAdaptation(.popover)
                .preferredColorScheme(.dark)
        }
        .accessibilityLabel(Text(verbatim: VideoStudioCopy.videoSettingsAccessibility(model.recipe)))
        .accessibilityAddTraits(isOpen ? .isSelected : [])
    }

    /// ⌃ while open, ⌄ while shut (FS-12.10 §3).
    private func chevron(isOpen: Bool) -> some View {
        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.6))
    }

    /// A frame in the project's ratio, so the button says what it changes.
    private func ratioGlyph(side: CGFloat) -> some View {
        let ratio = model.recipe.aspect.ratio
        return RoundedRectangle(cornerRadius: side * 0.18, style: .continuous)
            .strokeBorder(Color.white, lineWidth: 1.5)
            .frame(width: ratio >= 1 ? side : side * ratio, height: ratio >= 1 ? side / ratio : side)
            .frame(width: side, height: side)
    }
}
