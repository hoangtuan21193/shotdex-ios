import SwiftUI

/// A selected item's command row (FS-12.04b §2): the first row of its panel,
/// 64×56 cells — glyph over a 10pt label — scrolling sideways with a 32pt
/// fade into the panel at the trailing edge. A lit section command sits on
/// white 14 %; Delete, always last, is drawn in the timeline's red.
struct VideoItemCommandRow: View {
    let commands: [VideoItemCommand]
    let isOn: (VideoItemCommand) -> Bool
    let isEnabled: (VideoItemCommand) -> Bool
    let perform: (VideoItemCommand) -> Void
    /// 10 on the phone and the Duo; 13 in the iPad's inspector.
    var inset: CGFloat = VideoStudioMetrics.itemCommandRowInset

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: VideoStudioMetrics.itemCommandGap) {
                ForEach(commands) { command in
                    cell(command)
                }
            }
            .padding(.horizontal, inset)
        }
        .frame(height: VideoStudioMetrics.itemCommandCell.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Commands", tableName: VideoStudioCopy.table, comment: "Video Studio: VoiceOver name of the selected item's row of commands"))
        .overlay(alignment: .trailing) {
            LinearGradient(
                colors: [EditorTheme.panelSolid.opacity(0), EditorTheme.panelSolid],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: VideoStudioMetrics.itemCommandFade)
            .allowsHitTesting(false)
        }
    }

    private func cell(_ command: VideoItemCommand) -> some View {
        let enabled = isEnabled(command)
        let lit = isOn(command)
        return Button {
            perform(command)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: command.systemImage)
                    .font(.system(size: 19, weight: .regular))
                    .frame(height: 22)
                Text(command.title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(tint(command, enabled: enabled))
            .frame(width: VideoStudioMetrics.itemCommandCell.width, height: VideoStudioMetrics.itemCommandCell.height)
            .background(
                RoundedRectangle(cornerRadius: VideoStudioMetrics.commandCellRadius, style: .continuous)
                    .fill(lit ? VideoStudioMetrics.openCellFill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier("itemCommand.\(command.id)")
        .accessibilityAddTraits(lit ? .isSelected : [])
    }

    private func tint(_ command: VideoItemCommand, enabled: Bool) -> Color {
        guard enabled else { return .white.opacity(0.28) }
        return command.isDestructive ? EditorTheme.timelineDestructive : .white
    }
}
