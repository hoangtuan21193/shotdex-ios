import SwiftUI
import UIKit

/// The system colour a Settings icon tile is drawn in (FS-08.01b §2).
///
/// System colours only, so light, dark and Increase Contrast come for free;
/// never the amber accent, which DESIGN.md keeps for state ShotDex draws.
enum SettingsTint: String, CaseIterable, Hashable, Sendable {
    case blue, indigo, pink, teal, brown, green, purple, cyan, mint, red, gray, orange

    private var base: UIColor {
        switch self {
        case .blue: .systemBlue
        case .indigo: .systemIndigo
        case .pink: .systemPink
        case .teal: .systemTeal
        case .brown: .systemBrown
        case .green: .systemGreen
        case .purple: .systemPurple
        case .cyan: .systemCyan
        case .mint: .systemMint
        case .red: .systemRed
        case .gray: .systemGray
        case .orange: .systemOrange
        }
    }

    /// The tile's fill: the colour at 14% in light mode, 24% in dark.
    var fill: Color {
        let base = base
        return Color(uiColor: UIColor { traits in
            let opacity = traits.userInterfaceStyle == .dark
                ? AppTheme.Size.settingsTileFillOpacityDark
                : AppTheme.Size.settingsTileFillOpacityLight
            return base.resolvedColor(with: traits).withAlphaComponent(opacity)
        })
    }

    /// The glyph: the same colour's high-contrast variant — darker in light
    /// mode, lighter in dark — so it holds 4.5:1 against its own pale fill
    /// (FS-08.01b AC-9), where the plain colour would not.
    var glyph: Color {
        let base = base
        return Color(uiColor: UIColor { traits in
            base.resolvedColor(with: traits.modifyingTraits { $0.accessibilityContrast = .high })
        })
    }
}

/// The rounded, tinted square that leads every Settings row.
///
/// Decorative: the row's title already says what the row is, so VoiceOver
/// skips the tile (FS-08.01b AC-7).
struct SettingsTileIcon: View {
    let systemImage: String
    let tint: SettingsTint
    var isCompact = false

    var body: some View {
        let size = isCompact ? AppTheme.Size.settingsSidebarTile : AppTheme.Size.settingsTile
        let radius = isCompact ? AppTheme.Radius.sm : AppTheme.Size.settingsTileCornerRadius
        let glyph = isCompact ? AppTheme.Size.settingsSidebarTileGlyph : AppTheme.Size.settingsTileGlyph
        Image(systemName: systemImage)
            .font(.system(size: glyph, weight: .medium))
            .foregroundStyle(tint.glyph)
            .frame(width: size, height: size)
            .background(tint.fill, in: RoundedRectangle.app(radius))
            .accessibilityHidden(true)
    }
}

/// Tile + title + one value line: the shape of every Settings row
/// (FS-08.01b §2). The control that changes the row — a switch, a picker, a
/// chevron — is the container's to add.
struct SettingsTileRowLabel: View {
    let title: String
    let value: String?
    let systemImage: String
    let tint: SettingsTint
    var titleStyle: TitleStyle = .standard
    /// One line on the root, where the boards truncate; a section page lets a
    /// value wrap once rather than clip the half that explains it.
    var valueLineLimit = 1

    /// How the title reads: a setting, an action (tinted, like a button in a
    /// list), or an action that throws something away (red, red tile).
    enum TitleStyle {
        case standard, action, destructive
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            SettingsTileIcon(systemImage: systemImage, tint: titleStyle == .destructive ? .red : tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(titleColor)
                    .lineLimit(2)
                if let value, !value.isEmpty {
                    Text(value)
                        .font(.subheadline)
                        .monospacedDigit()
                        // A fixed colour, not `.secondary`: inside a
                        // destructive button that resolves to a pale red.
                        .foregroundStyle(Color(.secondaryLabel))
                        .lineLimit(valueLineLimit)
                        // "4 built-in · 3 custom" is read with a pause, not as
                        // "dot".
                        .accessibilityLabel(value.replacingOccurrences(of: " · ", with: ", "))
                }
            }
            // The separator starts under the title, not under the tile.
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        }
        .frame(minHeight: AppTheme.Size.settingsRowMinHeight - 2 * AppTheme.Spacing.sm)
    }

    private var titleColor: AnyShapeStyle {
        switch titleStyle {
        case .standard: AnyShapeStyle(Color(.label))
        case .action: AnyShapeStyle(.tint)
        case .destructive: AnyShapeStyle(.red)
        }
    }
}

extension View {
    /// The row padding the boards draw — 8 above and below a 44pt tile-and-two-
    /// lines label, 16 at the sides — so a row is 60pt (FS-08.01b §2). The
    /// inset-grouped list's own vertical padding left them at 74.
    func settingsRowInsets() -> some View {
        listRowInsets(EdgeInsets(
            top: AppTheme.Spacing.sm,
            leading: AppTheme.Size.screenMargin,
            bottom: AppTheme.Spacing.sm,
            trailing: AppTheme.Size.screenMargin
        ))
    }
}
