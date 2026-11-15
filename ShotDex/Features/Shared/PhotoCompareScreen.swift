import Photos
import SwiftUI
import UniformTypeIdentifiers

/// What a comparison shows and what it does with a choice. Two sources: a
/// Duplicates group (`DuplicateCompareSource`, where Delete only marks and
/// the list deletes) and a selection from a grid (`SelectionCompareModel`,
/// which deletes from here).
@MainActor
protocol PhotoCompareSource {
    /// "Similar · 4 photos".
    var title: String { get }
    /// Every photo of the comparison, in order. Fewer than two closes it.
    var ids: [String] { get }
    /// The photo pane A opens on; nil = the first.
    var preferredA: String? { get }
    func asset(for id: String) -> PHAsset?
    /// Width / height from the index, for a photo PhotoKit has no size for.
    func storedAspect(of id: String) -> CGFloat?
    /// Chips on pane B: how `id` differs from `other`.
    func differences(of id: String, comparedWith other: String) -> [String]
    func isMarked(_ id: String) -> Bool
    func setMarked(_ marked: Bool, _ id: String)
    /// The top bar's Delete, when the deletion happens here.
    var deletion: PhotoCompareDeletion? { get }
    /// Reads the facts *What differs* sets side by side (FS-06.06 §14.7);
    /// nil hides it.
    var factsLoader: PhotoFactsLoader? { get }
}

extension PhotoCompareSource {
    var factsLoader: PhotoFactsLoader? { nil }
}

/// Delete N on the top bar (FS-01.08 §4).
struct PhotoCompareDeletion {
    /// "Delete 2", or "Delete" with nothing marked.
    let title: String
    let isEnabled: Bool
    let run: @MainActor () async -> Void
}

/// The photos of one comparison, two at a time (FS-06.06 §7.6, FS-01.08,
/// boards `PH_DuplicatesCompare` and `PH_Compare`). Panes A and B are equal:
/// either can show any photo — swipe a pane sideways to step it, tap a
/// filmstrip photo to put it in B, drag one onto A. Every photo has its own
/// Keep | Delete. Chips on B say how it differs from A; holding a pane flips
/// it to the other pane's photo; a pinch zooms both. Stacked on a compact
/// screen, side by side on a wide one. Tier D, dark whatever the appearance.
struct PhotoCompareScreen: View {
    let source: any PhotoCompareSource
    /// The photo the comparison was opened from: pane B, unless it is A.
    let startId: String
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
    @State private var isDeleting = false
    /// What *What differs* compares, read once per set of photos.
    @State private var facts: [String: PhotoFacts] = [:]
    @State private var showsDifferences = false
    @State private var differencesExpanded = false

    private var isGone: Bool { source.ids.count < CompareSession.minimumCount }

    /// A = the preferred photo (the group's keeper), B = the photo the
    /// comparison was opened from (or the next one, when that is A).
    private func shown(_ ids: [String]) -> [String] {
        let a = chosen[0].flatMap { ids.contains($0) ? $0 : nil }
            ?? source.preferredA.flatMap { ids.contains($0) ? $0 : nil } ?? ids[0]
        let fallbackB = startId != a && ids.contains(startId) ? startId : (ids.first { $0 != a } ?? a)
        var b = chosen[1].flatMap { ids.contains($0) ? $0 : nil } ?? fallbackB
        if b == a { b = ids.first { $0 != a } ?? a }
        return [a, b]
    }

    var body: some View {
        ZStack {
            EditorTheme.background.ignoresSafeArea()
            if !isGone {
                GeometryReader { proxy in
                    let isWide = proxy.size.width >= 700
                    let all = source.ids
                    let ids = shown(all)
                    VStack(spacing: AppTheme.Spacing.sm) {
                        topBar(all)
                        panes(all, ids: ids, isWide: isWide)
                        filmstrip(all, ids: ids, side: isWide ? 64 : 56)
                        // Only once both photos' facts are read: "no rows"
                        // must mean "nothing differs", never "not known yet".
                        if let rows = differenceRows(ids) {
                            // iPad has height to spare: the table stays open.
                            // iPhone and the Duo (669pt tall) open it on demand.
                            Group {
                                if isWide && !isDuoInner {
                                    differencesTable(rows, all: all, ids: ids, columns: 2)
                                        .padding(.horizontal, AppTheme.Spacing.lg)
                                } else {
                                    differencesButton(count: rows.count)
                                }
                            }
                            .transition(.opacity)
                        }
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
        .onChange(of: isGone) { _, gone in if gone { dismiss() } }
        .task(id: source.ids) {
            guard let loader = source.factsLoader else { return }
            let loaded = await loader.load(ids: source.ids)
            withAnimation(AppTheme.Motion.standard) { facts = loaded }
        }
        .background { if !isGone { compareKeys } }
        .overlay(alignment: .bottom) {
            if showsDifferences, !isGone {
                differencesPanel
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(AppTheme.Motion.standard, value: showsDifferences)
    }

    // MARK: Keyboard (FS-06.06 §14.8)

    /// ←/→ step pane B, K keeps it, ⌫ marks it, Esc closes (or closes
    /// What differs first).
    private var compareKeys: some View {
        // Read A/B when the key is pressed, not when the button was built.
        func panes() -> [String]? {
            let all = source.ids
            return all.count < CompareSession.minimumCount ? nil : shown(all)
        }
        func stepB(_ step: Int) {
            guard let ids = panes() else { return }
            let others = source.ids.filter { $0 != ids[0] }
            guard let index = others.firstIndex(of: ids[1]) else { return }
            chosen[1] = others[(index + step + others.count) % others.count]
        }
        return Group {
            Button(String(localized: "Next Photo in B", comment: "Compare keyboard shortcut")) { stepB(1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button(String(localized: "Previous Photo in B", comment: "Compare keyboard shortcut")) { stepB(-1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button(String(localized: "Keep Photo B", comment: "Compare keyboard shortcut: keep the photo in pane B")) {
                guard let ids = panes() else { return }
                withAnimation(AppTheme.Motion.standard) { source.setMarked(false, ids[1]) }
            }
            .keyboardShortcut("k", modifiers: [])
            Button(String(localized: "Mark Photo B for Deletion", comment: "Compare keyboard shortcut: mark the photo in pane B; nothing is deleted yet")) {
                guard let ids = panes() else { return }
                withAnimation(AppTheme.Motion.standard) { source.setMarked(true, ids[1]) }
            }
            .keyboardShortcut(.delete, modifiers: [])
            Button(String(localized: "Close Compare", comment: "Compare keyboard shortcut: close What differs, else the comparison")) {
                if showsDifferences { showsDifferences = false } else { dismiss() }
            }
            .keyboardShortcut(.escape, modifiers: [])
        }
        .opacity(0)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    // MARK: What differs (FS-06.06 §14.7)

    /// Nil until both photos' facts are read.
    private func differenceRows(_ ids: [String]) -> [PhotoDifference.Row]? {
        guard ids.count == 2, let a = facts[ids[0]], let b = facts[ids[1]] else { return nil }
        return PhotoDifference.rows(a, b)
    }

    @ScaledMetric(relativeTo: .footnote) private var labelColumn: CGFloat = 110

    private func differencesButton(count: Int) -> some View {
        Button {
            differencesExpanded = false
            showsDifferences = true
        } label: {
            Label {
                Text(count == 0
                     ? String(localized: "Same photo info", comment: "Compare: A and B differ in no listed field; opens the list")
                     : String(localized: "What differs · \(count)", comment: "Compare: opens the list of fields that differ between A and B, with how many"))
            } icon: {
                Image(systemName: "info.circle")
            }
            .labelStyle(SpacedLabelStyle(spacing: 6))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .frame(minWidth: 160, minHeight: 36)
            .editorGlass(Capsule())
        }
        .buttonStyle(.plain)
        .minimumHitTarget(drawnHeight: 36)
    }

    /// iPhone and Duo: the list rises from the bottom over the lower pane —
    /// an in-screen panel like every tier-D panel (DESIGN.md §2), not a
    /// system sheet. Drag down or tap the dim to close.
    private var differencesPanel: some View {
        let all = source.ids
        let ids = shown(all)
        return ZStack(alignment: .bottom) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { showsDifferences = false }
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 36, height: 5)
                    .padding(.top, 6)
                    .padding(.bottom, AppTheme.Spacing.sm)
                    .accessibilityHidden(true)
                ScrollView {
                    differencesTable(differenceRows(ids) ?? [], all: all, ids: ids, columns: 1)
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .padding(.bottom, AppTheme.Spacing.lg)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxWidth: .infinity)
            .frame(height: isDuoInner ? 300 : 404)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: AppTheme.Radius.lg, topTrailingRadius: AppTheme.Radius.lg, style: .continuous)
                    .fill(EditorTheme.panelSolid)
                    .ignoresSafeArea(edges: .bottom)
            )
            // Simultaneous: the rows scroll, and a pull down still closes.
            .simultaneousGesture(DragGesture(minimumDistance: 12).onEnded { value in
                if value.translation.height > 60 { showsDifferences = false }
            })
            .accessibilityAction(.escape) { showsDifferences = false }
            .accessibilityAddTraits(.isModal)
        }
    }

    /// The table: title, how many fields differ, the A/B header, the rows —
    /// in one column on a phone, split into two side by side on iPad.
    private func differencesTable(_ rows: [PhotoDifference.Row], all: [String], ids: [String], columns: Int) -> some View {
        let shownRows = PhotoDifference.visible(rows, expanded: differencesExpanded)
        let hidden = PhotoDifference.hiddenCount(rows)
        let split = columns > 1 ? (shownRows.count + 1) / 2 : shownRows.count
        let parts = [Array(shownRows.prefix(split)), Array(shownRows.dropFirst(split))].filter { !$0.isEmpty }
        return VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "What differs", comment: "Compare: title of the list of fields that differ between A and B"))
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text(rows.isEmpty
                 ? String(localized: "Same photo info", comment: "Compare: A and B differ in no listed field")
                 : String(localized: "\(rows.count) of \(PhotoDifference.Field.allCases.count) fields differ",
                          comment: "Compare: how many of the listed fields differ between A and B"))
                .font(.footnote)
                .foregroundStyle(EditorTheme.secondaryText)
                .padding(.bottom, AppTheme.Spacing.md)
            if !rows.isEmpty {
                HStack(alignment: .top, spacing: AppTheme.Spacing.xl) {
                    ForEach(parts.indices, id: \.self) { index in
                        VStack(spacing: 0) {
                            differenceHeader(all: all, ids: ids)
                            ForEach(parts[index]) { row in
                                differenceRow(label: row.field.title, a: row.a, b: row.b)
                            }
                        }
                    }
                }
                if hidden > 0 {
                    Button {
                        withAnimation(AppTheme.Motion.standard) { differencesExpanded.toggle() }
                    } label: {
                        Label(
                            differencesExpanded
                                ? String(localized: "Show less", comment: "Compare: fold the list of fields that differ back to five")
                                : String(localized: "Show \(hidden) more", comment: "Compare: unfold the fields that differ beyond the first five"),
                            systemImage: differencesExpanded ? "chevron.up" : "chevron.down"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(EditorTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: AppTheme.Size.minTouch)
                }
            }
        }
        .padding(columns > 1 ? AppTheme.Spacing.lg : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if columns > 1 {
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous).fill(EditorTheme.panelSolid)
            }
        }
    }

    /// "Ⓐ 1 of 5 · keep" | "Ⓑ 3 of 5 · delete" — the panes' own A/B discs.
    private func differenceHeader(all: [String], ids: [String]) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Color.clear.frame(width: labelColumn, height: 1)
            ForEach(0..<2, id: \.self) { slot in
                let id = ids[slot]
                let position = (all.firstIndex(of: id) ?? 0) + 1
                let marked = source.isMarked(id)
                HStack(spacing: 6) {
                    Text(Self.paneLetter(slot))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(.white))
                    Text(marked
                         ? String(localized: "\(position) of \(all.count) · delete", comment: "Compare: What differs column header, the photo's place in the group and that it is marked for deletion")
                         : String(localized: "\(position) of \(all.count) · keep", comment: "Compare: What differs column header, the photo's place in the group and that it is kept"))
                        .foregroundStyle(marked ? Color.red : .white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .font(.footnote.weight(.semibold))
        .frame(minHeight: 32)
        .overlay(alignment: .bottom) { Rectangle().fill(EditorTheme.hairline).frame(height: 1) }
    }

    private func differenceRow(label: String, a: String, b: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(EditorTheme.secondaryText)
                .frame(width: labelColumn, alignment: .leading)
            Text(a).frame(maxWidth: .infinity, alignment: .leading)
            Text(b).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline.monospacedDigit())
        .foregroundStyle(.white)
        .lineLimit(3)
        .frame(minHeight: 36)
        .padding(.vertical, AppTheme.Spacing.xs)
        .overlay(alignment: .bottom) { Rectangle().fill(EditorTheme.panelDivider).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    // MARK: Top bar

    private func topBar(_ all: [String]) -> some View {
        let deleting = all.filter(source.isMarked).count
        return HStack(spacing: AppTheme.Spacing.md) {
            GlassIconButton(systemImage: "xmark", accessibilityLabel: String(localized: "Close")) { dismiss() }
            VStack(spacing: 2) {
                Text(source.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                (Text(String(localized: "Keeping \(all.count - deleting)", comment: "Duplicates compare: photos of the group that stay"))
                    .foregroundStyle(EditorTheme.secondaryText)
                 + Text(" · ").foregroundStyle(EditorTheme.secondaryText)
                 + Text(String(localized: "deleting \(deleting)", comment: "Duplicates compare: photos of the group marked for deletion"))
                    .foregroundStyle(deleting > 0 ? Color.red : EditorTheme.secondaryText))
                    .font(.footnote)
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity)
            if let deletion = source.deletion {
                deleteButton(deletion)
            } else {
                // Balances the close button so the title stays centred.
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, CullLayout.edgeInset)
        .padding(.top, isDuoInner ? CompareLayout.duoInnerTopInset : AppTheme.Spacing.sm)
    }

    private func deleteButton(_ deletion: PhotoCompareDeletion) -> some View {
        Button(role: .destructive) {
            isDeleting = true
            Task {
                await deletion.run()
                isDeleting = false
            }
        } label: {
            Label(deletion.title, systemImage: "trash")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, AppTheme.Spacing.md)
                .frame(minHeight: 44)
                .background(Capsule().fill(deletion.isEnabled ? Color.red : Color.white.opacity(0.15)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!deletion.isEnabled || isDeleting)
        .opacity(deletion.isEnabled ? 1 : 0.5)
        .keyboardShortcut(.delete, modifiers: .command)
    }

    // MARK: Panes

    @ViewBuilder
    private func panes(_ all: [String], ids: [String], isWide: Bool) -> some View {
        let layout = isWide ? AnyLayout(HStackLayout(spacing: AppTheme.Spacing.sm)) : AnyLayout(VStackLayout(spacing: 6))
        layout {
            pane(all, ids: ids, slot: 0)
            pane(all, ids: ids, slot: 1)
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
    }

    private func pane(_ all: [String], ids: [String], slot: Int) -> some View {
        let id = ids[slot]
        let other = ids[1 - slot]
        let isMarked = source.isMarked(id)
        return BurstBigFrame(
            asset: source.asset(for: id),
            photoLibrary: photoLibrary,
            synchronizer: synchronizer,
            paneIndex: slot,
            onSwipe: { swipe in
                switch swipe {
                case .left: step(slot, in: all, ids: ids, by: 1)
                case .right: step(slot, in: all, ids: ids, by: -1)
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
                BurstBigFrame(asset: source.asset(for: other), photoLibrary: photoLibrary,
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
                let fit = Self.fitted(geo.size, aspect: displayAspect(id: id))
                paneOverlay(all, id: id, otherId: other, slot: slot, isMarked: isMarked)
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
            guard slot == 0, let dropped = items.first, all.contains(dropped) else { return false }
            show(dropped, in: 0, ids: ids)
            return true
        } isTargeted: { targeted in
            if slot == 0 { dropTargeted = targeted }
        }
        .sensoryFeedback(.selection, trigger: isMarked)
    }

    private func paneOverlay(_ all: [String], id: String, otherId: String, slot: Int, isMarked: Bool) -> some View {
        let position = (all.firstIndex(of: id) ?? 0) + 1
        let differences = slot == 1 ? source.differences(of: id, comparedWith: otherId) : []
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
                    Text(String(localized: "\(position) of \(all.count)", comment: "Duplicates compare: which photo of the group a pane shows"))
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
                if all.count > 2 {
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
                decision(id: id, isMarked: isMarked)
                    .padding(AppTheme.Spacing.sm)
            }
    }

    /// Keep | Delete for this one photo. Every photo may take Delete, the
    /// last one too.
    private func decision(id: String, isMarked: Bool) -> some View {
        // A narrow photo (portrait on a phone) drops the words before a word
        // breaks across two lines.
        ViewThatFits(in: .horizontal) {
            decisionPill(id: id, isMarked: isMarked, showsTitles: true)
            decisionPill(id: id, isMarked: isMarked, showsTitles: false)
        }
    }

    private func decisionPill(id: String, isMarked: Bool, showsTitles: Bool) -> some View {
        HStack(spacing: 0) {
            option(String(localized: "Keep", comment: "Duplicates compare: keep this photo"),
                   systemImage: "checkmark", isOn: !isMarked, onColor: .white.opacity(0.3), showsTitle: showsTitles) {
                if isMarked { setMarked(false, id) }
            }
            option(String(localized: "Delete", comment: "Duplicates compare: delete this photo"),
                   systemImage: "trash", isOn: isMarked, onColor: .red, showsTitle: showsTitles) {
                if !isMarked { setMarked(true, id) }
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.6), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Keep or delete this photo", comment: "VoiceOver: the compare pane's Keep | Delete choice"))
    }

    private func option(_ title: String, systemImage: String, isOn: Bool, onColor: Color, showsTitle: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(TitleOrIconLabelStyle(showsTitle: showsTitle))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, AppTheme.Spacing.md)
                .frame(minWidth: showsTitle ? 84 : 44, minHeight: 36)
                .background(Capsule().fill(isOn ? onColor : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func setMarked(_ marked: Bool, _ id: String) {
        guard source.isMarked(id) != marked else { return }
        withAnimation(AppTheme.Motion.standard) { source.setMarked(marked, id) }
    }

    // MARK: Filmstrip

    private func filmstrip(_ all: [String], ids: [String], side: CGFloat) -> some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(all, id: \.self) { id in
                        thumbnail(id, all: all, ids: ids, side: side)
                            .id(id)
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

    private func thumbnail(_ id: String, all: [String], ids: [String], side: CGFloat) -> some View {
        let isMarked = source.isMarked(id)
        let pane = ids.firstIndex(of: id)
        let position = (all.firstIndex(of: id) ?? 0) + 1
        return CullThumbnail(asset: source.asset(for: id), photoLibrary: photoLibrary, side: side)
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
                CullThumbnail(asset: source.asset(for: id), photoLibrary: photoLibrary, side: side)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.thumbnailLabel(position: position, count: all.count, isMarked: isMarked, pane: pane))
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

    /// Puts the next (or previous) photo into `slot`, skipping the one the
    /// other pane shows. Nothing to step to in a pair.
    private func step(_ slot: Int, in all: [String], ids: [String], by delta: Int) {
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

    /// The shape the photo is drawn in. PhotoKit's pixel size is already
    /// turned upright; the indexed width and height can be missing (then a
    /// panorama got a square red frame) or still sideways from EXIF.
    private func displayAspect(id: String) -> CGFloat {
        if let asset = source.asset(for: id), asset.pixelWidth > 0, asset.pixelHeight > 0 {
            return CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
        }
        return source.storedAspect(of: id) ?? 1
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

/// One Duplicates group as a comparison. Delete only marks here; the
/// Duplicates list deletes (FS-06.06b).
struct DuplicateCompareSource: PhotoCompareSource {
    let model: DuplicatesModel
    let startId: String

    private var group: DuplicateGroup? {
        model.groups.first { $0.memberIds.contains(startId) }
    }

    private func member(_ id: String) -> HashedPhoto? {
        group?.members.first { $0.assetId == id }
    }

    var title: String {
        guard let group else { return "" }
        return String(localized: "\(group.kind.title) · \(group.count) photos",
                      comment: "Duplicates compare title: kind and how many photos the group has")
    }

    var ids: [String] { group?.members.map(\.assetId) ?? [] }
    var preferredA: String? { group.flatMap { model.keeper(of: $0)?.assetId } }
    func asset(for id: String) -> PHAsset? { model.assetsById[id] }

    func storedAspect(of id: String) -> CGFloat? {
        guard let member = member(id), let width = member.width, let height = member.height, height > 0 else { return nil }
        return CGFloat(width) / CGFloat(height)
    }

    func differences(of id: String, comparedWith other: String) -> [String] {
        guard let group, let member = member(id), let otherMember = self.member(other) else { return [] }
        return model.caption(of: member, comparedWith: otherMember, in: group)
    }

    func isMarked(_ id: String) -> Bool { model.isMarked(id) }

    func setMarked(_ marked: Bool, _ id: String) {
        guard let group, model.isMarked(id) != marked else { return }
        model.toggleMark(id, in: group)
    }

    var deletion: PhotoCompareDeletion? { nil }
    var factsLoader: PhotoFactsLoader? { model.factsLoader }
}

/// The whole label, or its icon alone where the words do not fit.
private struct TitleOrIconLabelStyle: LabelStyle {
    let showsTitle: Bool

    func makeBody(configuration: Configuration) -> some View {
        if showsTitle {
            Label(configuration)
        } else {
            configuration.icon
        }
    }
}

/// A Label with a set gap between icon and title (the board's 6pt).
private struct SpacedLabelStyle: LabelStyle {
    let spacing: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            configuration.icon
            configuration.title
        }
    }
}
