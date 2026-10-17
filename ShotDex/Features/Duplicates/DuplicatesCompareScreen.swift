import Photos
import SwiftUI

/// One duplicate group side by side (FS-06.06 §7.6, board
/// `PH_DuplicatesCompare`): pinch any photo and every pane zooms to the same
/// spot, so the sharp copy shows itself. Two panes stacked on a compact
/// screen, up to six in a grid on a wide one; swipe a pane sideways to put
/// another photo of the group in it. Each pane has one control — the trash
/// button, which is the tile's mark. Tier D, dark whatever the appearance.
struct DuplicatesCompareScreen: View {
    let model: DuplicatesModel
    let presentation: DuplicateComparePresentation
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var synchronizer = CompareScrollSynchronizer()
    /// Photos put into a pane by a swipe; a pane not in here shows its
    /// default from `ordered`.
    @State private var swapped: [Int: String] = [:]

    static let widePaneLimit = 6

    private var group: DuplicateGroup? {
        model.groups.first { $0.memberIds.contains(presentation.startId) }
    }

    /// The group with the tapped photo first, the rest in the card's order.
    private func ordered(_ group: DuplicateGroup) -> [String] {
        let ids = group.members.map(\.assetId)
        return [presentation.startId] + ids.filter { $0 != presentation.startId }
    }

    private func slots(_ group: DuplicateGroup, paneCount: Int) -> [String] {
        let ids = ordered(group)
        return (0..<min(paneCount, ids.count)).map { slot in
            if let id = swapped[slot], ids.contains(id) { return id }
            return ids[slot]
        }
    }

    var body: some View {
        ZStack {
            EditorTheme.background.ignoresSafeArea()
            if let group {
                GeometryReader { proxy in
                    let isWide = proxy.size.width >= 700
                    let paneCount = isWide ? min(group.count, Self.widePaneLimit) : 2
                    VStack(spacing: AppTheme.Spacing.sm) {
                        topBar(group)
                        panes(group, ids: slots(group, paneCount: paneCount), isWide: isWide)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: group == nil) { _, gone in if gone { dismiss() } }
        .sensoryFeedback(.warning, trigger: model.blockedGroupId == group?.id) { _, blocked in blocked }
    }

    // MARK: Top bar

    private func topBar(_ group: DuplicateGroup) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            GlassIconButton(systemImage: "xmark", accessibilityLabel: String(localized: "Close")) { dismiss() }
            Text(String(localized: "\(group.kind.title) · \(group.count) photos",
                        comment: "Duplicates compare title: kind and how many photos the group has"))
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            // Balances the close button so the title stays centred.
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, CullLayout.edgeInset)
        .padding(.top, AppTheme.Spacing.sm)
    }

    // MARK: Panes

    @ViewBuilder
    private func panes(_ group: DuplicateGroup, ids: [String], isWide: Bool) -> some View {
        if isWide {
            GeometryReader { proxy in
                let columns = Self.columns(for: ids.count, in: proxy.size, aspect: aspect(of: group))
                let rows = Int(ceil(Double(ids.count) / Double(max(columns, 1))))
                VStack(spacing: 4) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: 4) {
                            ForEach(0..<columns, id: \.self) { column in
                                let slot = row * columns + column
                                if slot < ids.count {
                                    pane(group, id: ids[slot], slot: slot, shown: ids)
                                } else {
                                    Color.clear
                                }
                            }
                        }
                    }
                }
            }
        } else {
            VStack(spacing: 4) {
                ForEach(Array(ids.enumerated()), id: \.offset) { slot, id in
                    pane(group, id: id, slot: slot, shown: ids)
                }
            }
        }
    }

    private func pane(_ group: DuplicateGroup, id: String, slot: Int, shown: [String]) -> some View {
        let member = group.members.first { $0.assetId == id }
        let isMarked = model.isMarked(id)
        let position = (group.members.firstIndex { $0.assetId == id } ?? 0) + 1
        return BurstBigFrame(
            asset: model.assetsById[id],
            photoLibrary: photoLibrary,
            synchronizer: synchronizer,
            paneIndex: slot,
            onSwipe: { swipe in
                switch swipe {
                case .left: step(slot, in: group, shown: shown, by: 1)
                case .right: step(slot, in: group, shown: shown, by: -1)
                case .down: dismiss()
                case .up: break
                }
            }
        )
        // A new scroll view per photo: the synchronizer replays the zoom
        // onto it, so the incoming photo opens at the same spot.
        .id(id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay {
            // The labels and the button sit on the photo, not on the
            // letterbox around it.
            GeometryReader { geo in
                let fit = Self.fitted(geo.size, aspect: member.map(Self.aspect) ?? 1)
                paneOverlay(group, id: id, member: member, position: position, isMarked: isMarked)
                    .frame(width: fit.width, height: fit.height)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
        .sensoryFeedback(.selection, trigger: isMarked)
    }

    private func paneOverlay(_ group: DuplicateGroup, id: String, member: HashedPhoto?, position: Int, isMarked: Bool) -> some View {
        Color.clear
            .overlay {
                if isMarked {
                    Rectangle().strokeBorder(Color.red, lineWidth: 3).allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: AppTheme.Spacing.xs) {
                    chip("\(position)/\(group.count)")
                    if model.keeper(of: group)?.assetId == id, !isMarked {
                        chip(String(localized: "Keep", comment: "Duplicates compare: this pane shows the photo the group keeps"))
                    }
                }
                .monospacedDigit()
                .padding(AppTheme.Spacing.sm)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                if let member {
                    Text(facts(member, in: group))
                        .font(.caption)
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .lineLimit(2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(AppTheme.Spacing.sm)
                        .padding(.trailing, 52)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    withAnimation(AppTheme.Motion.standard) { _ = model.toggleMark(id, in: group) }
                } label: {
                    Image(systemName: isMarked ? "trash.slash" : "trash")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(isMarked ? Color.red : Color.black.opacity(0.55)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(AppTheme.Spacing.sm)
                .accessibilityLabel(isMarked
                                    ? String(localized: "Don't remove", comment: "Duplicates compare: take this photo's mark away")
                                    : String(localized: "Remove", comment: "Duplicates compare: mark this photo for removal"))
            }
    }

    /// Puts the next (or previous) photo of the group not already on
    /// screen into `slot`. Nothing to swap in when every photo is shown.
    private func step(_ slot: Int, in group: DuplicateGroup, shown: [String], by delta: Int) {
        let ids = group.members.map(\.assetId)
        guard ids.count > shown.count, let current = ids.firstIndex(of: shown[slot]) else { return }
        var index = current
        repeat {
            index = (index + delta + ids.count) % ids.count
        } while shown.contains(ids[index]) && index != current
        guard index != current else { return }
        withAnimation(AppTheme.Motion.standard) { swapped[slot] = ids[index] }
    }

    /// Size and MB, then the card's caption (Soft, Eyes closed, Edited…).
    private func facts(_ member: HashedPhoto, in group: DuplicateGroup) -> String {
        var parts: [String] = []
        if let dimensions = DuplicateReview.dimensions(member) { parts.append(dimensions) }
        if let size = member.fileSize { parts.append(DuplicatesScreen.byteFormatter.string(fromByteCount: Int64(size))) }
        var lines = [parts.joined(separator: " · ")]
        let caption = model.caption(of: member, in: group)
        if !caption.isEmpty { lines.append(caption.joined(separator: " · ")) }
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Columns for `count` panes that show the photos biggest in `area`.
    static func columns(for count: Int, in area: CGSize, aspect: CGFloat) -> Int {
        guard count > 1, area.width > 0, area.height > 0 else { return max(count, 1) }
        var best = (columns: 1, side: CGFloat(0))
        for columns in 1...count {
            let rows = Int(ceil(Double(count) / Double(columns)))
            let cell = CGSize(width: (area.width - CGFloat(columns - 1) * 4) / CGFloat(columns),
                              height: (area.height - CGFloat(rows - 1) * 4) / CGFloat(rows))
            let width = fitted(cell, aspect: aspect).width
            if width > best.side { best = (columns, width) }
        }
        return best.columns
    }

    /// The aspect-fit size of a photo of `aspect` (width / height) in `size`.
    static func fitted(_ size: CGSize, aspect: CGFloat) -> CGSize {
        guard aspect > 0, size.height > 0 else { return size }
        return size.width / size.height > aspect
            ? CGSize(width: size.height * aspect, height: size.height)
            : CGSize(width: size.width, height: size.width / aspect)
    }

    static func aspect(_ member: HashedPhoto) -> CGFloat {
        guard let width = member.width, let height = member.height, height > 0 else { return 1 }
        return CGFloat(width) / CGFloat(height)
    }

    private func aspect(of group: DuplicateGroup) -> CGFloat {
        Self.aspect(group.members[0])
    }

    private func chip(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.55), in: Capsule())
    }
}
