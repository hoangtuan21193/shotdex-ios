import SwiftUI

/// The pick / reject / star controls, in the two shapes culling needs them.
///
/// `CullControlBar` is the working control — 44pt targets, used where there is
/// room for them (a compare pane). `CullBadgeRow` is the same state read-only
/// and small, for a survey tile: five 44pt stars do not fit across a tile in a
/// 4×3 grid, and shrinking them below 44 to make them fit would make the
/// smallest targets in the app the ones the user taps hundreds of times in a
/// culling pass. The tile keeps the badges and puts the actions in its context
/// menu instead.
struct CullControlBar: View {
    let state: PhotoCullState
    let setFlag: (PhotoFlag) -> Void
    let setRating: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            flagButton(.rejected, systemImage: "xmark.bin", tint: .red)
            flagButton(.picked, systemImage: "flag.fill", tint: EditorTheme.accent)

            Divider()
                .frame(height: 22)
                .overlay(EditorTheme.dimText.opacity(0.4))
                .padding(.horizontal, AppTheme.Spacing.xs)

            ForEach(1...5, id: \.self) { star in
                Button {
                    // Tapping the star a photo already carries clears the
                    // rating: the alternative is dragging to zero, and three
                    // stars is most often set by a mis-tap on three stars.
                    setRating(state.rating == star ? 0 : star)
                } label: {
                    Image(systemName: state.rating >= star ? "star.fill" : "star")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(state.rating >= star ? EditorTheme.accent : EditorTheme.dimText)
                        .frame(width: AppTheme.Size.minTouch, height: AppTheme.Size.minTouch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                .accessibilityAddTraits(state.rating >= star ? .isSelected : [])
            }
        }
    }

    private func flagButton(_ flag: PhotoFlag, systemImage: String, tint: Color) -> some View {
        Button {
            setFlag(state.flag == flag ? .unflagged : flag)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(state.flag == flag ? tint : EditorTheme.dimText)
                .frame(width: AppTheme.Size.minTouch, height: AppTheme.Size.minTouch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(flag.title)
        .accessibilityAddTraits(state.flag == flag ? .isSelected : [])
    }
}

/// Flag and rating as they stand, small enough to sit on a thumbnail.
struct CullBadgeRow: View {
    let state: PhotoCullState

    var body: some View {
        if !state.isEmpty {
            HStack(spacing: 4) {
                if state.flag != .unflagged {
                    Image(systemName: state.flag == .picked ? "flag.fill" : "xmark.bin")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(state.flag == .picked ? EditorTheme.accent : .red)
                }
                if state.rating > 0 {
                    Text(String(repeating: "★", count: state.rating))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(EditorTheme.accent)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(Capsule().fill(.black.opacity(0.55)))
            .accessibilityLabel(Self.label(state))
        }
    }

    static func label(_ state: PhotoCullState) -> String {
        var parts: [String] = []
        if state.flag != .unflagged { parts.append(state.flag.title) }
        if state.rating > 0 { parts.append("\(state.rating) stars") }
        return parts.isEmpty ? "Not culled" : parts.joined(separator: ", ")
    }
}

extension View {
    /// The same flag and rating actions as a context menu, for anywhere the
    /// 44pt bar does not fit.
    func cullContextMenu(
        state: PhotoCullState,
        setFlag: @escaping (PhotoFlag) -> Void,
        setRating: @escaping (Int) -> Void
    ) -> some View {
        contextMenu {
            ForEach(PhotoFlag.allCases) { flag in
                Button {
                    setFlag(flag)
                } label: {
                    Label(flag.title, systemImage: flag.systemImage)
                }
                .disabled(state.flag == flag)
            }
            Divider()
            ForEach(Array(PhotoCullState.ratingRange).reversed(), id: \.self) { rating in
                Button {
                    setRating(rating)
                } label: {
                    Label(
                        rating == 0 ? "No Rating" : String(repeating: "★", count: rating),
                        systemImage: rating == 0 ? "star.slash" : "star.fill"
                    )
                }
                .disabled(state.rating == rating)
            }
        }
    }
}
