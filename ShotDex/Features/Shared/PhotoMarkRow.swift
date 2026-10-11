import SwiftUI

/// The Cull row, `[Reject 44] [★×5] [Pick 44]` — 340pt at the default sizes
/// (FS-01.12b §5). One definition for the culling pass and for Compare's
/// frames on iPhone and the Duo (FS-01.08c §2), so the row is learned once.
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
    /// False dims Reject — Duplicates' last unflagged photo (FS-01.08c AC-15).
    var canReject = true
    /// Photo name for VoiceOver, so two rows on one screen read apart.
    var photoName: String?
    let onRate: (Int) -> Void
    let onFlag: (PhotoFlag?) -> Void

    @Environment(\.appAccent) private var accent

    var body: some View {
        HStack(spacing: spacing) {
            flagButton(.reject, isOn: marks.flag == .reject)
                .disabled(!canReject && marks.flag != .reject)
                .opacity(!canReject && marks.flag != .reject ? 0.3 : 1)
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

/// None · Pick · Reject, 44pt high — the flag control under a wide Compare
/// frame (FS-01.08c §2, AC-19). A native segmented picker: it is a standard
/// choice of one among three, on a standard surface.
struct PhotoFlagSegmented: View {
    let flag: PhotoFlag?
    var canReject = true
    var photoName: String?
    let onFlag: (PhotoFlag?) -> Void

    private enum Choice: Hashable { case none, pick, reject }

    static var noFlag: String {
        String(
            localized: "flag.none",
            defaultValue: "None",
            table: MarkCopy.table,
            comment: "Compare flag control: neither Pick nor Reject"
        )
    }

    var body: some View {
        Picker(selection: Binding(
            get: { choice(flag) },
            set: { newValue in
                guard newValue != .reject || canReject || flag == .reject else { return }
                onFlag(value(newValue))
            }
        )) {
            Text(Self.noFlag).tag(Choice.none)
            Text(MarkCopy.pick).tag(Choice.pick)
            Text(MarkCopy.reject).tag(Choice.reject)
        } label: {
            Text(MarkCopy.flag)
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .frame(height: CullLayout.control)
        .fixedSize()
        .accessibilityLabel(photoName.map {
            String(localized: "Flag for \($0)", comment: "VoiceOver: a compare frame's None / Pick / Reject control")
        } ?? MarkCopy.flag)
    }

    private func choice(_ flag: PhotoFlag?) -> Choice {
        switch flag {
        case .pick: .pick
        case .reject: .reject
        case nil: .none
        }
    }

    private func value(_ choice: Choice) -> PhotoFlag? {
        switch choice {
        case .none: nil
        case .pick: .pick
        case .reject: .reject
        }
    }
}
