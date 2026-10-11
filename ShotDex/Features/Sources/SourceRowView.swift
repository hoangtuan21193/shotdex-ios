import SwiftUI

/// One source in Settings › Sources (board `PH_SettingsSources`): tile, name
/// with its kind badge, and a status line with a dot.
struct SourceRowView: View {
    let row: SourcesModel.Row
    var onGrantAccess: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            SettingsTileIcon(systemImage: Self.systemImage(row.text.kind), tint: Self.tint(row.text.kind))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Text(row.name)
                        .font(.body)
                        .lineLimit(1)
                    Text(row.text.badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(.secondaryLabel))
                        .padding(.horizontal, AppTheme.Spacing.xs)
                        .padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                        .fixedSize()
                }
                HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.xs) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(row.text.detail())
                        .font(.subheadline)
                        .foregroundStyle(row.text.needsAttention ? Color.orange : Color(.secondaryLabel))
                        .lineLimit(2)
                }
                if row.text.status == .needsAccess, let onGrantAccess {
                    Button(String(localized: "Grant Access…", comment: "Sources: choose a folder again after its permission was lost"),
                           action: onGrantAccess)
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.borderless)
                        .padding(.top, 2)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var dotColor: Color {
        switch row.text.dot {
        case .ok: .green
        case .away: Color(.systemGray)
        case .attention: .orange
        }
    }

    static func systemImage(_ kind: SourceRowText.Kind) -> String {
        switch kind {
        case .photos: "photo.on.rectangle"
        case .onDevice: "folder"
        case .iCloudDrive: "icloud"
        case .drive: "externaldrive"
        case .server: "server.rack"
        }
    }

    static func tint(_ kind: SourceRowText.Kind) -> SettingsTint {
        switch kind {
        case .photos, .onDevice: .blue
        case .iCloudDrive: .cyan
        case .drive: .gray
        case .server: .indigo
        }
    }
}
