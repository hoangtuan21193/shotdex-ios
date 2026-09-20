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

    @Environment(\.usesRegularToolChrome) private var usesRegularToolChrome
    private var size: CGFloat {
        EditorLayoutMetrics.editorFloatingCommandButtonSize(
            isRegularWidth: usesRegularToolChrome
        )
    }
    private let inset = EditorLayoutMetrics.editorFloatingCommandSideInset

    var body: some View {
        HStack(spacing: 5) {
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
            // Hold to see the clips as they came out of the library. The
            // model has done this since the studio shipped (spec §7.9); the
            // control went missing in a layout turn, which left the whole
            // before/after capability unreachable.
            beforeAfterCircle(isEnabled: model.hasEdits)

            Spacer(minLength: 8)

            timecodePill

            if let projectActions {
                readout
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
        // Inset the row from the band's top so it sits level with the Dynamic
        // Island, exactly like the photo editor's floating command row.
        .padding(.top, EditorLayoutMetrics.editorFloatingCommandRowTopInset)
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
        .font(.system(size: 11).monospacedDigit())
        .foregroundStyle(EditorTheme.dimText)
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
                .fill(Color.white.opacity(0.08))
        )
        .accessibilityLabel("\(timecode(model.currentTime)) of \(timecode(model.totalDuration))")
    }

    private func timecode(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let whole = Int(clamped)
        let tenths = Int((clamped - Double(whole)) * 10)
        return String(format: "%d:%02d.%d", whole / 60, whole % 60, tenths)
    }

    /// Press and hold, like the photo editor's before/after: the preview
    /// drops every filter, adjustment and overlay while the finger is down.
    private func beforeAfterCircle(isEnabled: Bool) -> some View {
        Image(systemName: "rectangle.on.rectangle")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(
                model.showsOriginal
                    ? EditorTheme.accent
                    : (isEnabled ? Color.white.opacity(0.9) : Color.white.opacity(0.28))
            )
            .frame(width: size, height: size)
            .background { Color.clear.editorGlass(Circle()) }
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
            .accessibilityLabel(Text("Show original", comment: "Video Studio: press-and-hold control that previews the clips without edits"))
            .accessibilityHint(Text("Press and hold to see the clips without edits", comment: "Hint for the Video Studio before/after control"))
            .accessibilityAddTraits(model.showsOriginal ? .isSelected : [])
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
    let action: () -> Void
}

/// The horizontal, scrolling icon command band: 52×54 cells, a right-edge fade.
struct VideoCommandBand: View {
    let commands: [VideoCommand]
    /// In a narrow inspector column the row becomes a grid: a horizontal
    /// scroller inside a 320pt column hides half its commands behind a
    /// gesture nobody expects there.
    var wraps = false

    var body: some View {
        if wraps { grid } else { row }
    }

    private var grid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: VideoStudioMetrics.commandCellWidth), spacing: 8)],
            spacing: 8
        ) {
            ForEach(commands) { VideoCommandCell(command: $0) }
        }
        .padding(.horizontal, 14)
    }

    private var row: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(commands) { VideoCommandCell(command: $0) }
            }
            .padding(.horizontal, 14)
        }
        .frame(height: VideoStudioMetrics.sheetCommandHeight)
        .overlay(alignment: .trailing) {
            LinearGradient(
                colors: [EditorTheme.panelSolid.opacity(0), EditorTheme.panelSolid],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 26)
            .allowsHitTesting(false)
        }
    }
}

private struct VideoCommandCell: View {
    let command: VideoCommand

    /// The band beside it and the rail below it both grew on a big screen;
    /// this row sat in the same feature at phone size, which is how one
    /// screen ends up with two ideas of how big a tool cell is.
    @Environment(\.usesRegularToolChrome) private var isRegularWidth

    private var color: Color {
        switch command.tint {
        case .normal: command.isEnabled ? .white : .white.opacity(0.28)
        case .accent: EditorTheme.accent
        case .destructive: EditorTheme.timelineDestructive
        }
    }

    var body: some View {
        Button(action: command.action) {
            VStack(spacing: 6) {
                Image(systemName: command.systemImage)
                    .font(.system(size: isRegularWidth ? 24 : 21, weight: .regular))
                Text(command.title)
                    .font(.system(size: isRegularWidth ? 11 : 9.5, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(color)
            .frame(
                width: isRegularWidth ? VideoStudioMetrics.commandCellWidth + 12 : VideoStudioMetrics.commandCellWidth,
                height: isRegularWidth ? VideoStudioMetrics.commandCellHeight + 8 : VideoStudioMetrics.commandCellHeight
            )
            .background(
                RoundedRectangle(cornerRadius: VideoStudioMetrics.commandCellRadius, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
        .disabled(!command.isEnabled)
        .accessibilityLabel(command.title)
    }
}
