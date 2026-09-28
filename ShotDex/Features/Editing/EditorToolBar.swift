import SwiftUI

/// The phone editor's six tools (FS-03.13a §4), fixed, never scrolling.
/// Presets and Edit switch in place; the other four are tools you enter and
/// leave with ✕ or ✓.
enum EditorTool: String, CaseIterable, Identifiable, Sendable {
    case presets, edit, transform, mask, heal, markup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .presets: "Presets"
        case .edit: "Edit"
        case .transform: "Transform"
        case .mask: "Mask"
        case .heal: "Heal"
        case .markup: "Markup"
        }
    }

    var systemImage: String {
        switch self {
        case .presets: "camera.filters"
        case .edit: "slider.horizontal.3"
        case .transform: "crop.rotate"
        case .mask: "circle.dashed"
        case .heal: "bandage"
        case .markup: "pencil.tip.crop.circle"
        }
    }

    /// Entered with ✕ · name · ✓ rather than switched to.
    var isSession: Bool {
        switch self {
        case .presets, .edit: false
        case .transform, .mask, .heal, .markup: true
        }
    }

    /// The tool a group belongs to — which cell is lit.
    static func tool(for group: EditorGroup) -> EditorTool {
        switch group {
        case .presets: .presets
        case .cropGeometry, .geo: .transform
        case .mask: .mask
        case .heal: .heal
        case .markup: .markup
        default: .edit
        }
    }

    /// The group a tool opens; Edit goes back to where its list was.
    func group(editListGroup: EditorGroup?) -> EditorGroup {
        switch self {
        case .presets: .presets
        case .edit: editListGroup ?? .light
        case .transform: .cropGeometry
        case .mask: .mask
        case .heal: .heal
        case .markup: .markup
        }
    }
}

/// The 54pt bar under the panel: six equal cells, or — inside a tool —
/// ✕ · the tool's name · ✓ (FS-03.13a §5).
struct EditorToolBar: View {
    let current: EditorTool
    /// A tool inside a tool — Curve, opened from Edit or a mask — shows its
    /// own ✕ · name · ✓.
    var sessionTitle: String?
    let select: (EditorTool) -> Void
    let cancel: () -> Void
    let apply: () -> Void

    var body: some View {
        if current.isSession || sessionTitle != nil {
            sessionBar
        } else {
            tools
        }
    }

    private var tools: some View {
        HStack(spacing: 0) {
            ForEach(EditorTool.allCases) { tool in
                let isSelected = tool == current
                Button {
                    select(tool)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tool.systemImage)
                            .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                            .frame(height: 22)
                        Text(tool.title)
                            .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Capsule()
                            .fill(isSelected ? Color.white : .clear)
                            .frame(width: 16, height: 2)
                    }
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.38))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tool.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private var sessionBar: some View {
        HStack(spacing: 0) {
            Button(action: cancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.1), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel")
            Spacer(minLength: 8)
            Text(sessionTitle ?? current.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button(action: apply) {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 42, height: 38)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Apply")
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
    }
}
