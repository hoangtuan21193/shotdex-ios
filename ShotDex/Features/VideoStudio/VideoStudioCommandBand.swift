import SwiftUI

// MARK: - Floating top command band (spec §2)

/// The band over the Dynamic Island, mirroring the photo editor's: Undo · Redo
/// on the leading edge; a running playback timecode on the trailing edge.
/// Every control is a 34pt dark-glass circle.
struct VideoStudioTopBand: View {
    @Bindable var model: VideoStudioModel

    private let size = EditorLayoutMetrics.editorFloatingCommandButtonSize
    private let inset = EditorLayoutMetrics.editorFloatingCommandSideInset

    var body: some View {
        HStack(spacing: 5) {
            circle("arrow.uturn.backward", isEnabled: model.canUndo) { model.undo() }
                .accessibilityLabel("Undo")
            circle("arrow.uturn.forward", isEnabled: model.canRedo) { model.redo() }
                .accessibilityLabel("Redo")

            Spacer(minLength: 8)

            timecodePill
        }
        .frame(height: size)
        .padding(.horizontal, inset)
        // Inset the row from the band's top so it sits level with the Dynamic
        // Island, exactly like the photo editor's floating command row.
        .padding(.top, EditorLayoutMetrics.editorFloatingCommandRowTopInset)
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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(commands) { VideoCommandCell(command: $0) }
            }
            .padding(.horizontal, 14)
        }
        .frame(height: VideoStudioMetrics.panelCommandHeight)
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
                Image(systemName: command.systemImage).font(.system(size: 21, weight: .regular))
                Text(command.title).font(.system(size: 9.5, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(color)
            .frame(width: VideoStudioMetrics.commandCellWidth, height: VideoStudioMetrics.commandCellHeight)
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
