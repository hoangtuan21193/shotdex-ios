import Photos
import SwiftUI
import UniformTypeIdentifiers

/// One duplicate group, two photos at a time (FS-06.06 §7.6, board
/// `PH_DuplicatesCompare`, redrawn 2026-10-22). Panes A and B are equal:
/// either can show any photo of the group — swipe a pane sideways to step
/// it, tap a filmstrip photo to put it in B, drag one onto A. Every photo
/// has its own Keep | Delete, so any number can stay (the model keeps at
/// least one). Chips on B say how it differs from A; holding a pane flips
/// it to the other pane's photo; a pinch zooms both. Stacked on a compact
/// screen, side by side on a wide one. Tier D, dark whatever the appearance.
struct DuplicatesCompareScreen: View {
    let model: DuplicatesModel
    let presentation: DuplicateComparePresentation
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(\.dismiss) private var dismiss
    /// The Duo's inner display, whose top corners the close button has to
    /// clear — see `CompareLayout.duoInnerTopInset`.
    @Environment(\.isDuoInner) private var isDuoInner
    @State private var synchronizer = CompareScrollSynchronizer()
    /// What each pane shows once the user has changed it; nil = its default.
    @State private var chosen: [String?] = [nil, nil]
    /// The pane being held, which shows the other pane's photo meanwhile.
    @State private var heldPane: Int?
    @State private var dropTargeted = false

    private var group: DuplicateGroup? {
        model.groups.first { $0.memberIds.contains(presentation.startId) }
    }

    /// A = the photo the group keeps, B = the photo tapped on the card (or
    /// the next one, when the tap was on the keeper).
    private func shown(_ group: DuplicateGroup) -> [String] {
        let ids = group.members.map(\.assetId)
        let a = chosen[0].flatMap { ids.contains($0) ? $0 : nil }
            ?? model.keeper(of: group)?.assetId ?? ids[0]
        let fallbackB = presentation.startId != a ? presentation.startId : (ids.first { $0 != a } ?? a)
        var b = chosen[1].flatMap { ids.contains($0) ? $0 : nil } ?? fallbackB
        if b == a { b = ids.first { $0 != a } ?? a }
        return [a, b]
    }

    var body: some View {
        ZStack {
            EditorTheme.background.ignoresSafeArea()
            if let group {
                GeometryReader { proxy in
                    let isWide = proxy.size.width >= 700
                    let ids = shown(group)
                    VStack(spacing: AppTheme.Spacing.sm) {
                        topBar(group)
                        panes(group, ids: ids, isWide: isWide)
                        filmstrip(group, ids: ids, side: isWide ? 64 : 56)
                        Text(String(localized: "Tap a photo for B, drag it onto A · swipe a photo to step",
                                    comment: "Duplicates compare: how to put photos into the two panes"))
                            .font(.caption)
                            .foregroundStyle(EditorTheme.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppTheme.Spacing.lg)
                            .padding(.bottom, AppTheme.Spacing.xs)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: group == nil) { _, gone in if gone { dismiss() } }
    }

    // MARK: Top bar

    private func topBar(_ group: DuplicateGroup) -> some View {
        let deleting = model.markedCount(in: group)
        return HStack(spacing: AppTheme.Spacing.md) {
            GlassIconButton(systemImage: "xmark", accessibilityLabel: String(localized: "Close")) { dismiss() }
            VStack(spacing: 2) {
                Text(String(localized: "\(group.kind.title) · \(group.count) photos",
                            comment: "Duplicates compare title: kind and how many photos the group has"))
                    .font(.headline)
                    .foregroundStyle(.white)
                (Text(String(localized: "Keeping \(group.count - deleting)", comment: "Duplicates compare: photos of the group that stay"))
                    .foregroundStyle(EditorTheme.secondaryText)
                 + Text(" · ").foregroundStyle(EditorTheme.secondaryText)
                 + Text(String(localized: "deleting \(deleting)", comment: "Duplicates compare: photos of the group marked for deletion"))
                    .foregroundStyle(deleting > 0 ? Color.red : EditorTheme.secondaryText))
                    .font(.footnote)
            }
            .monospacedDigit()
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            // Balances the close button so the title stays centred.
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, CullLayout.edgeInset)
        .padding(.top, isDuoInner ? CompareLayout.duoInnerTopInset : AppTheme.Spacing.sm)
    }

    // MARK: Panes

    @ViewBuilder
    private func panes(_ group: DuplicateGroup, ids: [String], isWide: Bool) -> some View {
        let layout = isWide ? AnyLayout(HStackLayout(spacing: AppTheme.Spacing.sm)) : AnyLayout(VStackLayout(spacing: 6))
        layout {
            pane(group, ids: ids, slot: 0)
            pane(group, ids: ids, slot: 1)
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
    }

    private func pane(_ group: DuplicateGroup, ids: [String], slot: Int) -> some View {
        let id = ids[slot]
        let other = ids[1 - slot]
        let member = group.members.first { $0.assetId == id }
        let isMarked = model.isMarked(id)
        return BurstBigFrame(
            asset: model.assetsById[id],
            photoLibrary: photoLibrary,
            synchronizer: synchronizer,
            paneIndex: slot,
            onSwipe: { swipe in
                switch swipe {
                case .left: step(slot, in: group, ids: ids, by: 1)
                case .right: step(slot, in: group, ids: ids, by: -1)
                case .down: dismiss()
                case .up: break
                }
            },
            onHoldChange: { holding in heldPane = holding ? slot : nil }
        )
        // A new scroll view per photo: the synchronizer replays the zoom
        // onto it, so the incoming photo opens at the same spot.
        .id(id)
        .overlay {
            // Hold = the other pane's photo, at the same zoom, laid over
            // this one so the hold recognizer underneath keeps running.
            if heldPane == slot {
                BurstBigFrame(asset: model.assetsById[other], photoLibrary: photoLibrary,
                              synchronizer: synchronizer, paneIndex: 2 + slot, onSwipe: { _ in })
                    .id("held-\(other)")
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
        .overlay {
            // The labels and the choice sit on the photo, not on the
            // letterbox around it.
            GeometryReader { geo in
                let fit = Self.fitted(geo.size, aspect: displayAspect(id: id, member: member))
                paneOverlay(group, id: id, otherId: other, member: member, slot: slot, isMarked: isMarked)
                    .frame(width: fit.width, height: fit.height)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
        .overlay {
            if slot == 0, dropTargeted {
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 3)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard slot == 0, let dropped = items.first, group.memberIds.contains(dropped) else { return false }
            show(dropped, in: 0, ids: ids)
            return true
        } isTargeted: { targeted in
            if slot == 0 { dropTargeted = targeted }
        }
        .sensoryFeedback(.selection, trigger: isMarked)
    }

    private func paneOverlay(_ group: DuplicateGroup, id: String, otherId: String, member: HashedPhoto?,
                             slot: Int, isMarked: Bool) -> some View {
        let position = (group.members.firstIndex { $0.assetId == id } ?? 0) + 1
        let other = group.members.first { $0.assetId == otherId }
        let differences = slot == 1 ? both(member, other).map { model.caption(of: $0.0, comparedWith: $0.1, in: group) } ?? [] : []
        return Color.clear
            .overlay {
                if isMarked {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .strokeBorder(Color.red, lineWidth: 3)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Text(Self.paneLetter(slot))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(.white))
                    Text(String(localized: "\(position) of \(group.count)", comment: "Duplicates compare: which photo of the group a pane shows"))
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
                .padding(.leading, 4)
                .padding(.trailing, 8)
                .frame(height: 24)
                .background(Color.black.opacity(0.55), in: Capsule())
                .padding(AppTheme.Spacing.sm)
                .allowsHitTesting(false)
                .accessibilityElement(children: .combine)
            }
            .overlay {
                if group.count > 2 {
                    HStack {
                        Image(systemName: "chevron.left")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if !differences.isEmpty {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        ForEach(differences, id: \.self) { chip($0) }
                    }
                    .padding(AppTheme.Spacing.sm)
                    .padding(.bottom, 52)
                    .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                decision(group, id: id, isMarked: isMarked)
                    .padding(AppTheme.Spacing.sm)
            }
    }

    /// Keep | Delete for this one photo. Every photo of the group may take
    /// Delete, the last one too.
    private func decision(_ group: DuplicateGroup, id: String, isMarked: Bool) -> some View {
        HStack(spacing: 0) {
            option(String(localized: "Keep", comment: "Duplicates compare: keep this photo"),
                   systemImage: "checkmark", isOn: !isMarked, onColor: .white.opacity(0.3)) {
                if isMarked { setMarked(false, id, in: group) }
            }
            option(String(localized: "Delete", comment: "Duplicates compare: delete this photo"),
                   systemImage: "trash", isOn: isMarked, onColor: .red) {
                if !isMarked { setMarked(true, id, in: group) }
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.6), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Keep or delete this photo", comment: "VoiceOver: the compare pane's Keep | Delete choice"))
    }

    private func option(_ title: String, systemImage: String, isOn: Bool, onColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, AppTheme.Spacing.md)
                .frame(minWidth: 84, minHeight: 36)
                .background(Capsule().fill(isOn ? onColor : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func setMarked(_ marked: Bool, _ id: String, in group: DuplicateGroup) {
        guard model.isMarked(id) != marked else { return }
        withAnimation(AppTheme.Motion.standard) { model.toggleMark(id, in: group) }
    }

    // MARK: Filmstrip

    private func filmstrip(_ group: DuplicateGroup, ids: [String], side: CGFloat) -> some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(group.members, id: \.assetId) { member in
                        thumbnail(member, group: group, ids: ids, side: side)
                            .id(member.assetId)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, 4)
                .frame(minWidth: 0)
            }
            .scrollClipDisabled()
            .frame(height: side + 8)
            .onAppear { reader.scrollTo(ids[1], anchor: .center) }
        }
    }

    private func thumbnail(_ member: HashedPhoto, group: DuplicateGroup, ids: [String], side: CGFloat) -> some View {
        let id = member.assetId
        let isMarked = model.isMarked(id)
        let pane = ids.firstIndex(of: id)
        let position = (group.members.firstIndex { $0.assetId == id } ?? 0) + 1
        return CullThumbnail(asset: model.assetsById[id], photoLibrary: photoLibrary, side: side)
            .frame(width: side, height: side)
            .opacity(isMarked ? 0.55 : 1)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Group {
                    if isMarked {
                        Circle().fill(Color.red)
                    } else {
                        Circle().fill(.white)
                            .overlay(Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.black))
                    }
                }
                .frame(width: 18, height: 18)
                .padding(3)
            }
            .overlay(alignment: .bottomLeading) {
                if let pane {
                    Text(Self.paneLetter(pane))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(.white))
                        .padding(3)
                }
            }
            .overlay {
                if pane != nil {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white, lineWidth: 2)
                        .padding(-3)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { show(id, in: 1, ids: ids) }
            .draggable(id) {
                CullThumbnail(asset: model.assetsById[id], photoLibrary: photoLibrary, side: side)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.thumbnailLabel(position: position, count: group.count, isMarked: isMarked, pane: pane))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: String(localized: "Show in A", comment: "VoiceOver: put this photo in compare pane A")) {
                show(id, in: 0, ids: ids)
            }
    }

    private static func thumbnailLabel(position: Int, count: Int, isMarked: Bool, pane: Int?) -> String {
        let fate = isMarked
            ? String(localized: "delete", comment: "VoiceOver: compare filmstrip photo is marked for deletion")
            : String(localized: "keep", comment: "VoiceOver: compare filmstrip photo stays")
        let base = String(localized: "Photo \(position) of \(count), \(fate)", comment: "VoiceOver: a compare filmstrip photo")
        guard let pane else { return base }
        return base + ", " + String(localized: "in pane \(paneLetter(pane))", comment: "VoiceOver: which compare pane shows this photo")
    }

    private static func paneLetter(_ slot: Int) -> String { slot == 0 ? "A" : "B" }

    // MARK: Changing what a pane shows

    /// Puts `id` in `slot`; when it is already in the other pane the two swap.
    private func show(_ id: String, in slot: Int, ids: [String]) {
        var next = ids
        if next[1 - slot] == id { next[1 - slot] = next[slot] }
        next[slot] = id
        withAnimation(AppTheme.Motion.standard) { chosen = next.map(Optional.some) }
    }

    /// Puts the next (or previous) photo of the group into `slot`, skipping
    /// the one the other pane shows. Nothing to step to in a pair.
    private func step(_ slot: Int, in group: DuplicateGroup, ids: [String], by delta: Int) {
        let all = group.members.map(\.assetId)
        guard all.count > 2, var index = all.firstIndex(of: ids[slot]) else { return }
        repeat {
            index = (index + delta + all.count) % all.count
        } while all[index] == ids[1 - slot]
        show(all[index], in: slot, ids: ids)
    }

    // MARK: Geometry

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

    /// The shape the photo is drawn in. PhotoKit's pixel size is already
    /// turned upright; the indexed width and height can be missing (then a
    /// panorama got a square red frame) or still sideways from EXIF.
    private func displayAspect(id: String, member: HashedPhoto?) -> CGFloat {
        if let asset = model.assetsById[id], asset.pixelWidth > 0, asset.pixelHeight > 0 {
            return CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
        }
        return member.map(Self.aspect) ?? 1
    }

    private func chip(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.yellow)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.55), in: Capsule())
    }
}

/// Both or nothing, for two optionals.
private func both<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}
