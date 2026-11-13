import Photos
import SwiftUI

/// Duplicates on the Mac (FS-06.06, board `MAC_Duplicates`): the same model
/// as iOS — a check only when asked, groups confirmed by Vision, a list that
/// never re-orders under the pointer — drawn the Mac way. Title and the
/// last check in the toolbar, sort / Check Again / the selection / Delete
/// beside it, the kind filter and one fixed-height status line over a grid
/// of cards. Every photo in a card is the same size (user, 2026-11-10); the
/// kept one carries a Keep badge. A click on a photo marks it; the right
/// click has Keep Just This One, Keep All and Not Duplicates.
struct MacDuplicatesScreen: View {
    @Environment(MacDependencies.self) private var dependencies
    @State private var showsQuickClean = false
    @State private var containerWidth: CGFloat = 0

    private var model: DuplicatesModel { dependencies.duplicates }

    /// Cards are at least this wide; the board fits two beside a 228 sidebar.
    static let minimumCardWidth: CGFloat = 420
    static let cardSpacing: CGFloat = 16
    static let margin: CGFloat = 24
    /// Photos per card row (the board's four).
    static let photosPerRow = 4

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            // Nothing to filter, nothing running, never checked: no band.
            if !model.presentFilters.isEmpty || model.checkStep != nil || model.scanState != nil {
                header
                Divider()
            }
            list
            Divider()
            footer
        }
        .background(MacTheme.content)
        .navigationTitle(String(localized: "Duplicates", comment: "Mac Duplicates title"))
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
        .task {
            model.loadIfNeeded()
            model.startScoring()
        }
        .onDisappear { model.stopScoring() }
        .sheet(isPresented: $showsQuickClean) {
            MacQuickCleanSheet(model: model)
        }
        .alert(model.notice?.title ?? "", isPresented: Binding(
            get: { model.notice != nil }, set: { if !$0 { model.notice = nil } }
        ), presenting: model.notice) { _ in
            Button("OK", role: .cancel) {}
        } message: { notice in
            Text(notice.message)
        }
    }

    private var subtitle: String {
        guard let scanState = model.scanState else {
            return String(localized: "Not checked yet", comment: "Mac Duplicates subtitle before the first check")
        }
        _ = scanState
        // When it was checked is in the status slot under the filter.
        let groups = model.groups.count
        return groups == 1
            ? String(localized: "1 group", comment: "Mac Duplicates subtitle: one group")
            : String(localized: "\(groups) groups", comment: "Mac Duplicates subtitle: group count")
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        @Bindable var model = model
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Picker(String(localized: "Sort", comment: "Mac Duplicates sort menu"), selection: $model.sort) {
                    ForEach(DuplicateSort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label(String(localized: "Sort Groups", comment: "Mac Duplicates toolbar"), systemImage: "arrow.up.arrow.down")
            }
            .help(String(localized: "Sort groups", comment: "Mac Duplicates toolbar tooltip"))
            Button {
                model.startScan()
            } label: {
                Label(String(localized: "Check Again", comment: "Mac Duplicates toolbar: scan the library again"), systemImage: "arrow.clockwise")
            }
            .disabled(model.isBusy)
            .help(String(localized: "Check the library again", comment: "Mac Duplicates toolbar tooltip"))
        }
        if model.markedCount > 0 {
            ToolbarItemGroup(placement: .primaryAction) {
                Text("\(model.markedCount) selected · \(DuplicatesModel.byteFormatter.string(fromByteCount: Int64(model.markedBytes)))",
                     comment: "Mac Duplicates toolbar: marked photos and their size")
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                Button(role: .destructive) {
                    Task { await model.deleteMarked() }
                } label: {
                    Label(String(localized: "Delete \(model.markedCount)", comment: "Mac Duplicates toolbar: delete the marked photos"),
                          systemImage: "trash")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(MacTheme.redText)
                }
                .disabled(model.isBusy)
                .keyboardShortcut(.delete, modifiers: .command)
            }
        }
    }

    // MARK: Header

    /// The kind filter and one status line of fixed height — the progress
    /// of a check or when the last one ran — so the cards below never move
    /// when a check starts or ends.
    @ViewBuilder
    private var header: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 8) {
            if !model.presentFilters.isEmpty {
                Picker(String(localized: "Kind", comment: "Mac Duplicates kind filter"), selection: $model.filter) {
                    ForEach(model.presentFilters, id: \.self) { filter in
                        Text("\(filter.title) \(model.groupCount(filter))").tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            MacDuplicatesStatus(model: model)
                .frame(maxWidth: 520, alignment: .leading)
                .frame(height: 44, alignment: .top)
        }
        .padding(.horizontal, Self.margin)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: List

    @ViewBuilder
    private var list: some View {
        if model.sortedGroups.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: Self.cardSpacing) {
                    if model.offersQuickClean, case .kind(let kind) = model.filter, kind.isCopy {
                        MacQuickCleanBand(model: model) { showsQuickClean = true }
                            .frame(maxWidth: 720)
                    }
                    cards
                }
                .padding(Self.margin)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
        }
    }

    /// Cards in rows of equal columns, in list order — never re-dealt.
    private var cards: some View {
        let content = max(0, containerWidth - Self.margin * 2)
        let count = max(1, Int((content + Self.cardSpacing) / (Self.minimumCardWidth + Self.cardSpacing)))
        let cardWidth = (content - Self.cardSpacing * CGFloat(count - 1)) / CGFloat(count)
        let metrics = DuplicateCardMetrics(innerWidth: cardWidth - DuplicateCardMetrics.cardPadding * 2,
                                           copyColumns: Self.photosPerRow - 1)
        let columns = Array(repeating: GridItem(.flexible(), spacing: Self.cardSpacing, alignment: .top), count: count)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: Self.cardSpacing) {
            ForEach(model.sortedGroups) { group in
                if model.isCollapsed(group) {
                    MacDuplicateFoldedRow(group: group, model: model)
                } else {
                    MacDuplicateCard(group: group, model: model, metrics: metrics)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.phase == .loading {
            ProgressView().controlSize(.small)
        } else if model.checkStep != nil {
            // The status line says what runs; the list fills when it ends.
            Color.clear
        } else if model.hasNeverScanned {
            ContentUnavailableView {
                Label(String(localized: "Not Checked Yet", comment: "Duplicates: the library was never checked"), systemImage: "square.on.square")
            } description: {
                Text(String(localized: "Check your library once. The results are saved, and you can check again any time.",
                            comment: "Duplicates: before the first check"))
            } actions: {
                Button(String(localized: "Check Library", comment: "Duplicates: run the first check")) { model.startScan() }
                    .buttonStyle(.borderedProminent)
                    .tint(MacTheme.accentFill)
            }
        } else {
            ContentUnavailableView {
                Label(String(localized: "No Duplicates", comment: "Duplicates: nothing found"), systemImage: "checkmark.circle")
            } description: {
                Text(String(localized: "No duplicates among \(model.coverage.hashedPhotos) photos.", comment: "Duplicates: empty list"))
            } actions: {
                Button(String(localized: "Check Again", comment: "Duplicates: scan the library again")) { model.startScan() }
                    .disabled(model.isBusy)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if let summary = model.lastDeleteSummary {
                Text(summary)
            } else if model.markedCount > 0 {
                Text("\(model.markedCount) selected in \(model.groupsWithMarks.count) groups · marks are kept until you delete or unmark them",
                     comment: "Mac Duplicates footer: what is marked")
            }
            Spacer()
            Text(String(localized: "Photos Library items: Recently Deleted keeps them 30 days",
                        comment: "Mac Duplicates footer: where deleted photos go"))
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .lineLimit(1)
        .padding(.horizontal, 16)
        .frame(height: 30)
    }
}

// MARK: - Status line

/// The check's progress (three steps, each with its bar) or when the last
/// check ran — one slot, the same height either way.
private struct MacDuplicatesStatus: View {
    let model: DuplicatesModel

    var body: some View {
        if let step = model.checkStep {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title(step)).font(.system(size: 12, weight: .semibold))
                    Text(detail(step)).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if step != .grouping {
                        Button(String(localized: "Cancel", comment: "Duplicates: stop the check in progress")) { model.cancelScan() }
                            .controlSize(.small)
                    }
                }
                .monospacedDigit()
                .lineLimit(1)
                if let fraction = fraction(step) {
                    ProgressView(value: fraction).tint(MacTheme.accent)
                } else {
                    ProgressView().progressViewStyle(.linear).tint(MacTheme.accent)
                }
            }
        } else if let scanState = model.scanState {
            VStack(alignment: .leading, spacing: 0) {
                Text("Checked \(scanState.scannedAt.formatted(.relative(presentation: .named)))",
                     comment: "Duplicates header: when the last scan ran")
                    .font(.system(size: 12, weight: .semibold))
                Text(pending)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .lineLimit(1)
        }
    }

    private var pending: String {
        if model.pendingCount > 0 {
            return String(localized: "\(model.pendingCount) photos not checked yet", comment: "Duplicates header: photos a rescan would cover")
        }
        return String(localized: "Every photo checked", comment: "Duplicates header: nothing left for a rescan")
    }

    private func fraction(_ step: DuplicatesCheckStep) -> Double? {
        switch step {
        case .reading(let scan): scan.total > 0 ? scan.fraction : nil
        case .grouping: nil
        case .comparing(let progress): progress.total > 0 ? Double(progress.processed) / Double(progress.total) : nil
        }
    }

    private func title(_ step: DuplicatesCheckStep) -> String {
        switch step {
        case .reading: String(localized: "Step 1 of 3 · Reading photos", comment: "Duplicates header: first step of the check")
        case .grouping: String(localized: "Step 2 of 3 · Grouping", comment: "Duplicates header: second step of the check")
        case .comparing: String(localized: "Step 3 of 3 · Comparing matches", comment: "Duplicates header: third step, Vision confirms each group")
        }
    }

    private func detail(_ step: DuplicatesCheckStep) -> String {
        switch step {
        case .reading(let scan):
            scan.total > 0
                ? String(localized: "\(scan.processed.formatted()) of \(scan.total.formatted()) photos", comment: "Duplicates header: check progress")
                : String(localized: "Getting ready…", comment: "Duplicates header: before the first batch of the check")
        case .grouping:
            String(localized: "Finding photos that look alike…", comment: "Duplicates header: grouping step")
        case .comparing(let progress):
            String(localized: "\(progress.processed.formatted()) of \(progress.total.formatted()) photos · list updates when done",
                   comment: "Duplicates header: comparing step progress")
        }
    }
}

// MARK: - Quick clean

private struct MacQuickCleanBand: View {
    let model: DuplicatesModel
    let review: () -> Void

    var body: some View {
        let pending = model.pendingQuickClean
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(String(localized: "Quick clean", comment: "Duplicates list: band over the cards"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(pending.copies == 0
                     ? String(localized: "Every copy decided", comment: "Duplicates Quick clean band: nothing left for it")
                     : String(localized: "\(pending.copies.formatted()) copies · \(DuplicatesModel.byteFormatter.string(fromByteCount: Int64(pending.bytes)))",
                              comment: "Duplicates Quick clean band: copies to remove and their size"))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                Text(String(localized: "Identical copies. Favorites, edits and album photos stay.",
                            comment: "Duplicates Quick clean band: what it removes and what it never touches"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(String(localized: "Review…", comment: "Duplicates Quick clean band: opens the preview"), action: review)
                .buttonStyle(.borderedProminent)
                .tint(MacTheme.accentFill)
                .disabled(model.isBusy || pending.copies == 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(MacTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(MacTheme.separator))
    }
}

/// What Quick clean would mark, one row per group, each untickable. Nothing
/// is deleted here: the rows become marks, and Delete does the rest.
private struct MacQuickCleanSheet: View {
    let model: DuplicatesModel
    @Environment(\.dismiss) private var dismiss
    @State private var items: [QuickCleanItem]?
    @State private var unticked: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            Text(String(localized: "Quick clean", comment: "Duplicates Quick clean sheet title"))
                .font(.system(size: 15, weight: .semibold))
                .padding(.vertical, 14)
            Divider()
            Group {
                if let items {
                    List(items) { item in
                        Toggle(isOn: Binding(get: { !unticked.contains(item.groupId) },
                                             set: { if $0 { unticked.remove(item.groupId) } else { unticked.insert(item.groupId) } })) {
                            Text("Remove \(item.removal.remove.count)", comment: "Duplicates Quick clean row: copies this group would mark")
                                .monospacedDigit()
                        }
                        .toggleStyle(.checkbox)
                    }
                } else {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minHeight: 280)
            Divider()
            HStack {
                Button(String(localized: "Cancel", comment: "Duplicates Quick clean sheet")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                let count = items.map { QuickClean.selection($0, excluding: unticked).count } ?? 0
                Button(String(localized: "Select \(count) Photos", comment: "Duplicates Quick clean sheet: mark the ticked copies")) {
                    if let items { model.applyQuickClean(items, excluding: unticked) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(count == 0)
            }
            .padding(16)
        }
        .frame(width: 440, height: 440)
        .task { items = await model.quickCleanItems() }
    }
}

// MARK: - Card

/// One group: every photo the same size, in the group's own order; the one
/// to keep has a Keep badge, a marked one a red frame and a trash disc.
private struct MacDuplicateCard: View {
    let group: DuplicateGroup
    let model: DuplicatesModel
    let metrics: DuplicateCardMetrics

    var body: some View {
        let keeper = model.keeper(of: group)
        ZStack(alignment: .topLeading) {
            ForEach(Array(group.members.enumerated()), id: \.element.id) { index, member in
                let origin = metrics.origin(at: index)
                tile(member, keeper: keeper)
                    .offset(x: origin.x, y: origin.y)
            }
        }
        .frame(height: metrics.gridHeight(photoCount: group.count), alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DuplicateCardMetrics.cardPadding)
        .background(MacTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(MacTheme.separator))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "\(group.kind.title), \(group.count) photos", comment: "VoiceOver: a Duplicates card"))
        .onAppear { model.loadTraits(for: group) }
    }

    private func tile(_ member: HashedPhoto, keeper: HashedPhoto?) -> some View {
        let isMarked = model.isMarked(member.assetId)
        let isKeeper = member.assetId == keeper?.assetId
        let caption = isKeeper ? [] : model.caption(of: member, in: group, keeper: keeper)
        return MacDuplicateTile(
            asset: model.assetsById[member.assetId],
            side: metrics.tile,
            isMarked: isMarked,
            showsKeep: isKeeper && !isMarked,
            caption: caption.first
        )
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.15)) { model.toggleMark(member.assetId, in: group) }
        }
        .help(isMarked
              ? String(localized: "Click to keep this photo", comment: "Mac Duplicates tile tooltip, marked")
              : String(localized: "Click to delete this photo", comment: "Mac Duplicates tile tooltip"))
        .contextMenu {
            Button(String(localized: "Keep Just This One", comment: "Duplicates tile menu: keep this photo, mark the rest")) {
                model.keepOnly(member.assetId, in: group)
            }
            Button(isMarked
                   ? String(localized: "Don't Delete", comment: "Mac Duplicates tile menu: take the mark away")
                   : String(localized: "Delete", comment: "Mac Duplicates tile menu: mark for deletion")) {
                model.toggleMark(member.assetId, in: group)
            }
            Divider()
            Button(model.isKeptAll(group)
                   ? String(localized: "Keeping All", comment: "Duplicates tile menu: the group is kept whole; choose to undo")
                   : String(localized: "Keep All", comment: "Duplicates tile menu: keep every photo of the group")) {
                model.toggleKeepAll(group)
            }
            Button(String(localized: "Not Duplicates", comment: "Duplicates card: these photos are not duplicates")) {
                model.dismiss(group)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isKeeper
                            ? String(localized: "Suggested to keep", comment: "VoiceOver: the photo the Duplicates card suggests keeping")
                            : String(localized: "Copy", comment: "VoiceOver: a copy on a Duplicates card"))
        .accessibilityValue(isMarked
                            ? String(localized: "will be deleted", comment: "VoiceOver: a tile marked for deletion")
                            : String(localized: "won't be deleted", comment: "VoiceOver: a tile not marked"))
        .accessibilityAddTraits(.isButton)
    }
}

private struct MacDuplicateTile: View {
    @Environment(MacDependencies.self) private var dependencies
    let asset: PHAsset?
    let side: CGFloat
    let isMarked: Bool
    let showsKeep: Bool
    let caption: String?

    @State private var image: NSImage?
    @State private var requestId: PHImageRequestID?
    @State private var isHovered = false

    var body: some View {
        MacTheme.fill2
            .frame(width: side, height: side)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill().opacity(isMarked ? 0.45 : 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isMarked ? Color.red : MacTheme.separator, lineWidth: isMarked ? 2.5 : 1)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: isMarked ? "trash.circle.fill" : "circle")
                    .symbolRenderingMode(isMarked ? .palette : .monochrome)
                    .foregroundStyle(.white, .red)
                    .font(.system(size: 18))
                    .shadow(color: .black.opacity(0.35), radius: 1.5)
                    .opacity(isMarked || isHovered ? 1 : 0.85)
                    .padding(6)
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 4) {
                    if showsKeep {
                        Label(String(localized: "Keep", comment: "Duplicates: badge on the photo to keep"), systemImage: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .foregroundStyle(MacTheme.onAccentFill)
                            .background(MacTheme.accentFill, in: Capsule())
                    } else if let caption {
                        Text(caption)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .frame(height: 18)
                            .foregroundStyle(.white)
                            .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                }
                .padding(6)
            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onAppear(perform: load)
            .onChange(of: side) { load() }
            .onDisappear {
                if let requestId { dependencies.photoLibrary.cancelThumbnailRequest(requestId) }
                requestId = nil
            }
    }

    private func load() {
        guard let asset else { return }
        if let requestId { dependencies.photoLibrary.cancelThumbnailRequest(requestId) }
        let pixels = side * 2
        requestId = dependencies.photoLibrary.requestThumbnail(for: asset, targetSize: CGSize(width: pixels, height: pixels),
                                                               allowNetwork: false) { result in
            if let result { image = result }
        }
    }
}

// MARK: - Folded row

private struct MacDuplicateFoldedRow: View {
    let group: DuplicateGroup
    let model: DuplicatesModel

    var body: some View {
        let marked = model.markedCount(in: group)
        HStack(spacing: 12) {
            HStack(spacing: -10) {
                ForEach(group.members.prefix(2)) { member in
                    MacDuplicateTile(asset: model.assetsById[member.assetId], side: 36,
                                     isMarked: false, showsKeep: false, caption: nil)
                        .allowsHitTesting(false)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(model.isKeptAll(group)
                     ? String(localized: "\(group.kind.title) · Keeping all \(group.count)", comment: "Mac Duplicates folded row: group kept whole")
                     : String(localized: "\(group.kind.title) · Keeping \(group.count - marked) · deleting \(marked)", comment: "Mac Duplicates folded row"))
                    .font(.system(size: 13, weight: .semibold))
                if let date = DuplicateReview.newestDate(group) as Int?, date > 0 {
                    Text(Date(timeIntervalSince1970: TimeInterval(date)).formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            Spacer(minLength: 0)
            Button(String(localized: "Show", comment: "Mac Duplicates folded row: open the group again")) {
                model.expand(group)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(MacTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(MacTheme.separator))
    }
}
