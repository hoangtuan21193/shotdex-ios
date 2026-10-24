import SwiftUI

/// The Cull row, `[Reject 44] [★×5] [Pick 44]` — 340pt at the default sizes
/// (FS-01.12b §5).
///
/// Pick on = accent disc + black glyph; Reject on = red disc + white glyph,
/// the destructive "on". Tapping the flag a photo already has clears it,
/// and tapping its current star clears the stars.
struct PhotoMarkRow: View {
    /// Where the row is drawn, which decides only the off-state discs.
    enum Surface {
        /// Tier D (the culling pass): dark glass.
        case tierD
        /// The viewer: system fills, following light and dark.
        case viewer
    }

    let marks: PhotoMarkSummary
    var surface: Surface = .tierD
    /// Star cell width; 44 in the Cull row, 32 in the Duo's Survey cells.
    var starWidth: CGFloat = CullLayout.control
    var starGlyph: CGFloat = CullLayout.starGlyph
    var spacing: CGFloat = CullLayout.controlGap
    /// Photo name for VoiceOver, so two rows on one screen read apart.
    var photoName: String?
    let onRate: (Int) -> Void
    let onFlag: (PhotoFlag?) -> Void

    @Environment(\.appAccent) private var accent

    var body: some View {
        HStack(spacing: spacing) {
            flagButton(.reject, isOn: marks.flag == .reject)
            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { stars in
                    Button {
                        onRate(marks.rating == stars ? 0 : stars)
                    } label: {
                        Image(systemName: stars <= marks.rating ? "star.fill" : "star")
                            .font(.system(size: starGlyph))
                            .foregroundStyle(starColor(isOn: stars <= marks.rating))
                            .frame(width: starWidth, height: CullLayout.control)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(MarkCopy.starsAccessibility(stars))
                    .accessibilityAddTraits(stars <= marks.rating ? .isSelected : [])
                }
            }
            flagButton(.pick, isOn: marks.flag == .pick)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(photoName.map {
            String(localized: "Rating and flag for \($0)", comment: "VoiceOver: a compare frame's row of stars, Pick and Reject")
        } ?? MarkCopy.ratingAndFlag)
    }

    private func starColor(isOn: Bool) -> Color {
        switch surface {
        case .tierD: isOn ? .white : .white.opacity(0.28)
        case .viewer: isOn ? .primary : .secondary.opacity(0.6)
        }
    }

    private func flagButton(_ flag: PhotoFlag, isOn: Bool) -> some View {
        Button {
            onFlag(isOn ? nil : flag)
        } label: {
            Image(systemName: flag == .pick ? "flag.fill" : "xmark")
                .font(.system(size: flag == .pick ? 19 : 20, weight: .semibold))
                .foregroundStyle(glyphColor(flag, isOn: isOn))
                .frame(width: CullLayout.control, height: CullLayout.control)
                .background {
                    if isOn {
                        Circle().fill(flag == .pick ? accent : Color.red)
                    } else if surface == .viewer {
                        Circle().fill(Color(.tertiarySystemFill))
                    }
                }
                .modifier(TierDDisc(isActive: surface == .tierD, isOn: isOn))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(flag == .pick ? MarkCopy.pick : MarkCopy.reject)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func glyphColor(_ flag: PhotoFlag, isOn: Bool) -> Color {
        if isOn { return flag == .pick ? .black : .white }
        return surface == .tierD ? .white : .primary
    }

    /// Dark glass behind an off disc in tier D only.
    private struct TierDDisc: ViewModifier {
        let isActive: Bool
        let isOn: Bool

        func body(content: Content) -> some View {
            if isActive {
                content.editorGlass(Circle(), tint: isOn ? .clear : EditorTheme.glass)
            } else {
                content
            }
        }
    }
}
