import Photos
import SwiftUI
import UIKit

/// Rating ▸ and Flag ▸ (FS-01.12 §6) — one definition for the viewer's ⋯,
/// the selection's ⋯ (SwiftUI) and the tile's long-press menu (UIKit), so the
/// rows, their order and their icons cannot drift apart. Every row calls
/// `PhotoMarks.apply`, the same path the keys take.
///
/// The current value carries a check only for a single photo: for a
/// selection of 300 the menu would have to read 300 assets to say "mixed".
struct PhotoMarkMenus: View {
    let ids: [String]
    @Environment(PhotoMarks.self) private var marks: PhotoMarks?

    var body: some View {
        if let marks {
            let current = Self.current(ids: ids, marks: marks)
            Menu {
                ForEach(StarRating.range.reversed(), id: \.self) { stars in
                    Button {
                        Task { await marks.apply(.rate(stars), to: ids) }
                    } label: {
                        Self.check(current?.rating == stars, Self.ratingRowTitle(stars))
                    }
                    .accessibilityLabel(stars == 0 ? MarkCopy.noRating : MarkCopy.starsAccessibility(stars))
                }
            } label: {
                Label(MarkCopy.rating, systemImage: "star")
                if let current, current.rating > 0 { Text(MarkCopy.stars(current.rating)) }
            }
            Menu {
                Button {
                    Task { await marks.apply(.flag(.pick), to: ids) }
                } label: {
                    Label(MarkCopy.pick, systemImage: current?.flag == .pick ? "checkmark" : "flag.fill")
                }
                Button {
                    Task { await marks.apply(.flag(.reject), to: ids) }
                } label: {
                    Label(MarkCopy.reject, systemImage: current?.flag == .reject ? "checkmark" : "xmark")
                }
                Button(MarkCopy.clearFlag) {
                    Task { await marks.apply(.flag(nil), to: ids) }
                }
                .disabled(current != nil && current?.flag == nil)
            } label: {
                Label(MarkCopy.flag, systemImage: "flag.fill")
                if let flag = current?.flag { Text(MarkCopy.flagWord(flag)) }
            }
        }
    }

    @ViewBuilder
    private static func check(_ isOn: Bool, _ title: String) -> some View {
        if isOn {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    /// `None`, `★` … `★★★★★`.
    static func ratingRowTitle(_ stars: Int) -> String {
        stars == 0 ? MarkCopy.noRating : String(repeating: "★", count: stars)
    }

    /// The single photo's marks; nil for a selection.
    @MainActor
    static func current(ids: [String], marks: PhotoMarks) -> PhotoMarkSummary? {
        guard ids.count == 1, let id = ids.first else { return nil }
        _ = marks.version
        let photosRating = PhotoLibraryService.fetchAssets(ids: [id]).first?.photosStarRating
        return marks.summary(for: id, photosRating: photosRating)
    }

    /// The same two submenus for a `UIMenu` (the grid's long-press).
    @MainActor
    static func uiMenus(ids: [String], marks: PhotoMarks) -> [UIMenuElement] {
        let current = current(ids: ids, marks: marks)
        let ratingRows: [UIMenuElement] = StarRating.range.reversed().map { stars in
            let action = UIAction(
                title: ratingRowTitle(stars),
                state: current?.rating == stars ? .on : .off
            ) { _ in Task { await marks.apply(.rate(stars), to: ids) } }
            action.accessibilityLabel = stars == 0 ? MarkCopy.noRating : MarkCopy.starsAccessibility(stars)
            return action
        }
        let rating = UIMenu(
            title: MarkCopy.rating,
            subtitle: current.flatMap { $0.rating > 0 ? MarkCopy.stars($0.rating) : nil },
            image: UIImage(systemName: "star"),
            children: ratingRows
        )
        let clear = UIAction(
            title: MarkCopy.clearFlag,
            attributes: current != nil && current?.flag == nil ? .disabled : []
        ) { _ in Task { await marks.apply(.flag(nil), to: ids) } }
        let flag = UIMenu(
            title: MarkCopy.flag,
            subtitle: current?.flag.map { MarkCopy.flagWord($0) },
            image: UIImage(systemName: "flag.fill"),
            children: [
                UIAction(title: MarkCopy.pick, image: UIImage(systemName: "flag.fill"), state: current?.flag == .pick ? .on : .off) { _ in
                    Task { await marks.apply(.flag(.pick), to: ids) }
                },
                UIAction(title: MarkCopy.reject, image: UIImage(systemName: "xmark"), state: current?.flag == .reject ? .on : .off) { _ in
                    Task { await marks.apply(.flag(.reject), to: ids) }
                },
                clear,
            ]
        )
        return [rating, flag]
    }
}

/// `0`–`5`, `P`, `X`, `U` on hidden buttons for a surface with a set of
/// photos in focus (FS-01.12 §6): a shortcut inside a closed `Menu` never
/// fires, so the keys hang here and call what the menu rows call. `ids` is
/// read when the key fires — a key command keeps the closure it was first
/// registered with.
struct PhotoMarkKeyButtons: View {
    let ids: () -> [String]
    @Environment(PhotoMarks.self) private var marks: PhotoMarks?

    var body: some View {
        ZStack {
            ForEach(MarkKeyCommand.bindings, id: \.key) { binding in
                Button(binding.action.shortcutTitle) {
                    let targets = ids()
                    guard let marks, !targets.isEmpty else { return }
                    Task { await marks.apply(binding.action, to: targets) }
                }
                .keyboardShortcut(KeyEquivalent(binding.key), modifiers: [])
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}
