import Photos
import SwiftUI

/// Navigation value for the Duplicates utility, pushed from the Collections tab.
struct DuplicatesDestination: Hashable {}

/// Duplicates utility (tier A, DESIGN.md §2; FS-06.06 §7). A pinned band —
/// kind filter, sort, how many groups are reviewed, the last scan and Rescan —
/// over a list of **decision cards**: the suggested keeper big with "Keep" and
/// why, the copies beside it each saying what it lacks; a hold on a photo
/// offers Keep all and Not duplicates. A decided group folds to one line. Marks
/// gather in a floating bar with Delete. Pinch changes copies per row.
/// Nothing is marked until the user taps, and nothing rescans unless asked.
struct DuplicatesScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @AppStorage(SettingsKeys.duplicateCopyColumnsCompact)
    private var compactColumns = DuplicateCardMetrics.compactColumns
    @AppStorage(SettingsKeys.duplicateCopyColumnsRegular)
    private var regularColumns = DuplicateCardMetrics.regularColumns

    @State private var model: DuplicatesModel?
    @State private var containerWidth: CGFloat = 0
    /// Magnification at the last density step of the pinch in progress.
    @State private var pinchAnchor: CGFloat = 1
    @State private var isPinching = false
    @State private var hudVisible = false
    @State private var hudTask: Task<Void, Never>?
    @State private var showsQuickClean = false
    @State private var showsSelected = false

    private var isRegular: Bool { horizontalSizeClass == .regular }

    /// A5: say how much of the library the screen can see.
    private func permissionAccess(_ model: DuplicatesModel) -> DuplicatesPermissionBanner.Access? {
        switch photoLibrary.authorizationState {
        case .limited: .limited(visible: model.coverage.indexedPhotos)
        case .denied, .restricted: .denied
        default: nil
        }
    }

    private var copyColumns: Int {
        get { isRegular ? regularColumns : compactColumns }
        nonmutating set {
            let clamped = min(max(newValue, DuplicateCardMetrics.columnRange.lowerBound),
                              DuplicateCardMetrics.columnRange.upperBound)
            if isRegular { regularColumns = clamped } else { compactColumns = clamped }
        }
    }

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Duplicates")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil { model = DuplicatesModel(dependencies: dependencies) }
        }
    }

    @ViewBuilder
    private func content(_ model: DuplicatesModel) -> some View {
        @Bindable var model = model
        let hasMarks = model.markedCount > 0
        ScrollView {
            cardList(model)
                .padding(.horizontal, AppTheme.Size.screenMargin)
                .padding(.top, AppTheme.Spacing.md)
                .padding(.bottom, hasMarks ? 96 : AppTheme.Spacing.lg)
            if #unavailable(iOS 26.0) {
                Color.clear.frame(height: hasMarks ? 0 : 90)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
        .simultaneousGesture(pinch)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if let access = permissionAccess(model) {
                    DuplicatesPermissionBanner(access: access)
                        .padding(.horizontal, AppTheme.Size.screenMargin)
                        .padding(.vertical, AppTheme.Spacing.sm)
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                }
                DuplicatesHeaderBand(model: model, isRegular: isRegular)
            }
        }
        .overlay(alignment: .top) {
            if hudVisible {
                Text("\(copyColumns) per row", comment: "Duplicates: HUD while pinching, copies per row on a card")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .frame(height: 36)
                    .glassBackground(Capsule())
                    .padding(.top, AppTheme.Spacing.lg)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if hasMarks {
                deleteBar(model)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .toolbar(hasMarks ? .hidden : .automatic, for: .tabBar)
        .onChange(of: hasMarks) { navigation.hidesTabBar = hasMarks }
        .onDisappear {
            navigation.hidesTabBar = false
            model.stopScoring()
        }
        .sensoryFeedback(.selection, trigger: copyColumns)
        .task {
            guard photoLibrary.authorizationState.canReadLibrary else { return }
            model.loadIfNeeded()
            // Back from a pushed screen: carry on scoring.
            model.startScoring()
        }
        .task(id: photoLibrary.assetChangeToken) {
            guard photoLibrary.authorizationState.canReadLibrary else { return }
            model.refreshPendingCount()
        }
        .sheet(isPresented: $showsQuickClean) {
            DuplicatesQuickCleanSheet(model: model)
        }
        .sheet(isPresented: $showsSelected) {
            DuplicatesSelectedSheet(model: model)
                .environment(photoLibrary)
        }
        .photoStackCover($model.stackPresentation, onSaved: { _ in model.loadCache() })
        .fullScreenCover(item: $model.framePicker) { request in
            BurstFramesScreen(
                request: request,
                onDone: { kept in model.didChooseFrames(request, kept: kept) },
                groupDelete: { ids in await model.delete(ids: Set(ids)) }
            )
            .environment(dependencies)
            .environment(photoLibrary)
        }
        .toolbar {
            // Sort, then Check Again — the only two controls up top (user,
            // 2026-10-22: no ⋯, no Ignored, no Clear Selection), each its own
            // glass button, not one shared capsule (user, 2026-10-23).
            ToolbarItem(placement: .topBarTrailing) {
                sortMenu(model)
            }
            if #available(iOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            ToolbarItem(placement: .topBarTrailing) {
                rescanButton(model)
            }
        }
        .fullScreenCover(item: $model.comparePresentation) { presentation in
            DuplicatesCompareScreen(model: model, presentation: presentation)
                .environment(photoLibrary)
        }
        .modifier(DuplicatesAlerts(model: model))
        .sensoryFeedback(.success, trigger: model.deleteSuccessCount)
        .animation(AppTheme.Motion.standard, value: hasMarks)
        .animation(AppTheme.Motion.standard, value: hudVisible)
    }

    private func sortMenu(_ model: DuplicatesModel) -> some View {
        @Bindable var model = model
        return Menu {
            Picker("Sort", selection: $model.sort) {
                ForEach(DuplicateSort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .tint(.primary)
        .disabled(model.isScanning)
        .accessibilityLabel(String(localized: "Sort groups", comment: "VoiceOver: the Duplicates sort menu"))
        .accessibilityValue(model.sort.title)
    }

    private func rescanButton(_ model: DuplicatesModel) -> some View {
        Button {
            model.startScan()
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .tint(.primary)
        .disabled(model.isBusy || !photoLibrary.authorizationState.canReadLibrary)
        .accessibilityLabel(String(localized: "Check Again", comment: "Duplicates toolbar: scan the library again"))
    }

    // MARK: Cards

    @ViewBuilder
    private func cardList(_ model: DuplicatesModel) -> some View {
        if model.sortedGroups.isEmpty {
            emptyState(model)
                .frame(maxWidth: .infinity)
                .padding(.top, AppTheme.Spacing.xxl)
        } else {
            VStack(spacing: AppTheme.Spacing.md) {
                if showsQuickCleanBand(model) {
                    DuplicatesQuickCleanBand(model: model) { showsQuickClean = true }
                        .frame(maxWidth: isRegular ? 720 : .infinity)
                        .transition(.opacity)
                }
                cards(model)
            }
        }
    }

    /// The band rides the list while copies are undecided and the filter
    /// could show them.
    private func showsQuickCleanBand(_ model: DuplicatesModel) -> Bool {
        guard !model.isScanning, model.pendingQuickClean.copies > 0 else { return false }
        switch model.filter {
        case .kind(let kind): return kind.isCopy
        }
    }

    private func cards(_ model: DuplicatesModel) -> some View {
        let contentWidth = max(0, containerWidth - AppTheme.Size.screenMargin * 2)
        let columnCount = DuplicateCardMetrics.cardColumns(contentWidth: contentWidth, isRegular: isRegular)
        let cardWidth = DuplicateCardMetrics.cardWidth(contentWidth: contentWidth, columns: columnCount)
        let metrics = DuplicateCardMetrics(
            innerWidth: cardWidth - DuplicateCardMetrics.cardPadding * 2,
            copyColumns: copyColumns
        )
        let columns = distribute(model.sortedGroups, into: columnCount, model: model, metrics: metrics)
        return HStack(alignment: .top, spacing: DuplicateCardMetrics.cardSpacing) {
            ForEach(columns.indices, id: \.self) { index in
                LazyVStack(spacing: AppTheme.Spacing.md) {
                    ForEach(columns[index]) { group in
                        groupView(group, model: model, metrics: metrics)
                            .id(group.id)
                    }
                }
                .frame(width: columnCount > 1 ? cardWidth : nil)
            }
        }
    }

    @ViewBuilder
    private func groupView(_ group: DuplicateGroup, model: DuplicatesModel, metrics: DuplicateCardMetrics) -> some View {
        if model.isCollapsed(group) {
            DuplicateCollapsedRow(group: group, model: model)
        } else if group.sourceSet != nil {
            DuplicateSourceSetCard(group: group, model: model, metrics: metrics)
        } else {
            DuplicateDecisionCard(group: group, model: model, metrics: metrics)
        }
    }

    /// Masonry: each card goes to the shortest column so far, in sort order,
    /// so a folded row does not leave a hole beside a full card.
    private func distribute(
        _ groups: [DuplicateGroup],
        into count: Int,
        model: DuplicatesModel,
        metrics: DuplicateCardMetrics
    ) -> [[DuplicateGroup]] {
        guard count > 1 else { return [groups] }
        var columns = Array(repeating: [DuplicateGroup](), count: count)
        var heights = Array(repeating: CGFloat(0), count: count)
        for group in groups {
            let target = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            columns[target].append(group)
            heights[target] += estimatedHeight(group, model: model, metrics: metrics) + AppTheme.Spacing.md
        }
        return columns
    }

    private func estimatedHeight(_ group: DuplicateGroup, model: DuplicatesModel, metrics: DuplicateCardMetrics) -> CGFloat {
        if model.isCollapsed(group) { return 56 }
        if group.sourceSet != nil {
            let rows = (group.count + metrics.gridColumns - 1) / metrics.gridColumns
            return CGFloat(rows) * (metrics.tile + DuplicateCardMetrics.copyGap) + AppTheme.Spacing.md
        }
        let body = metrics.gridHeight(copyCount: group.count - 1)
        return body + AppTheme.Spacing.md
    }

    // MARK: Pinch

    /// Pinch out for bigger tiles (fewer per row), in for more — the Library
    /// grid's gesture, in whole steps.
    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if !isPinching {
                    isPinching = true
                    pinchAnchor = 1
                    showHUD()
                }
                let ratio = value.magnification / pinchAnchor
                if ratio > 1.25, copyColumns > DuplicateCardMetrics.columnRange.lowerBound {
                    withAnimation(AppTheme.Motion.standard) { copyColumns -= 1 }
                    pinchAnchor = value.magnification
                    showHUD()
                } else if ratio < 0.8, copyColumns < DuplicateCardMetrics.columnRange.upperBound {
                    withAnimation(AppTheme.Motion.standard) { copyColumns += 1 }
                    pinchAnchor = value.magnification
                    showHUD()
                }
            }
            .onEnded { _ in
                isPinching = false
                showHUD()
            }
    }

    private func showHUD() {
        hudVisible = true
        hudTask?.cancel()
        hudTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, !isPinching else { return }
            hudVisible = false
        }
    }

    // MARK: Bottom bar

    private func deleteBar(_ model: DuplicatesModel) -> some View {
        let count = model.markedCount
        let bytes = DuplicatesScreen.byteFormatter.string(fromByteCount: Int64(model.markedBytes))
        let inAlbums = model.markedInAlbumsCount
        return HStack(spacing: AppTheme.Spacing.sm) {
            // The pill opens the list of what will go (06b §3).
            Button {
                showsSelected = true
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(count) selected · \(bytes) ›", comment: "Duplicates: floating bar, number of marked photos and their size; opens the list")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text(inAlbums > 0
                         ? String(localized: "\(inAlbums) are in albums · kept photo joins them", comment: "Duplicates: floating bar, marked photos that are in albums")
                         : String(localized: "Recently Deleted keeps them 30 days", comment: "Duplicates: floating bar, where deleted photos go"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.85)
                }
                .lineLimit(1)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .frame(maxWidth: isRegular ? nil : .infinity, minHeight: 48, alignment: .leading)
                .glassBackground(Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint(String(localized: "Shows the photos that will be deleted", comment: "VoiceOver hint on the Duplicates selection pill"))

            Button {
                Task { await model.deleteMarked() }
            } label: {
                Label {
                    Text("Delete \(count)", comment: "Duplicates: floating bar button, deletes the marked photos")
                } icon: {
                    Image(systemName: "trash")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, AppTheme.Spacing.xl)
                .frame(height: 48)
                .background(Color.red, in: Capsule())
                .shadow(color: .black.opacity(0.18), radius: 7, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)
            .accessibilityLabel(count == 1
                ? String(localized: "Delete 1 photo", comment: "VoiceOver: the Delete button")
                : String(localized: "Delete \(count) photos", comment: "VoiceOver: the Delete button"))
        }
        .padding(.horizontal, AppTheme.Size.screenMargin)
        .padding(.bottom, AppTheme.Spacing.sm)
        .background {
            LinearGradient(
                colors: [Color(.systemGroupedBackground).opacity(0), Color(.systemGroupedBackground).opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    // MARK: Empty

    private func emptyDescription(_ model: DuplicatesModel) -> String {
        let scanned = model.coverage.hashedPhotos
        if scanned == 1 {
            return String(localized: "Nothing to compare with one photo.", comment: "Duplicates: empty list, one photo checked")
        }
        return String(localized: "No duplicates among \(scanned) photos.", comment: "Duplicates: empty list")
    }

    @ViewBuilder
    private func emptyState(_ model: DuplicatesModel) -> some View {
        if !photoLibrary.authorizationState.canReadLibrary {
            // The banner above says why and links to Settings; no scan runs.
            ContentUnavailableView(
                String(localized: "No Access to Photos", comment: "Duplicates empty state when Photos access is denied"),
                systemImage: "eye.slash"
            )
        } else if model.isScanning {
            EmptyView()
        } else if model.phase == .grouping {
            ProgressView("Grouping duplicates…")
        } else if model.phase == .loading {
            ProgressView()
        } else if model.coverage.indexedPhotos == 0 {
            ContentUnavailableView(
                "No Photos",
                systemImage: "photo.on.rectangle.angled",
                description: Text("Photos in your library show up here once ShotDex has read them.")
            )
        } else if model.freedToday > 0, model.sortedGroups.isEmpty {
            // AC-D8: the list ran out because the user cleared it.
            ContentUnavailableView {
                Label(String(localized: "All reviewed", comment: "Duplicates: nothing left to decide"), systemImage: "checkmark.seal")
            } description: {
                Text(String(localized: "\(DuplicatesScreen.byteFormatter.string(fromByteCount: Int64(model.freedToday))) freed today",
                            comment: "Duplicates: space deleted from Duplicates today"))
            } actions: {
                ForEach(model.presentFilters.filter { $0 != model.filter }, id: \.self) { filter in
                    Button(String(localized: "Show \(filter.title) (\(model.groupCount(filter)))",
                                  comment: "Duplicates All reviewed: a kind that still has groups")) {
                        model.filter = filter
                    }
                    .buttonStyle(.bordered)
                }
            }
        } else if model.hasNeverScanned {
            ContentUnavailableView {
                Label(String(localized: "Not Checked Yet", comment: "Duplicates: the library was never checked"), systemImage: "square.on.square")
            } description: {
                Text(String(localized: "Check your library once. The results are saved, and you can check again any time.", comment: "Duplicates: before the first check"))
            } actions: {
                Button(String(localized: "Check Library", comment: "Duplicates: run the first check")) {
                    model.startScan()
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView {
                Label(String(localized: "No Duplicates", comment: "Duplicates: nothing found"), systemImage: "checkmark.circle")
            } description: {
                Text(emptyDescription(model))
            } actions: {
                Button(String(localized: "Check Again", comment: "Duplicates: scan the library again")) { model.startScan() }
                    .buttonStyle(.bordered)
                    .disabled(model.isBusy)
            }
        }
    }

    static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    static func dateText(_ group: DuplicateGroup) -> String? {
        let newest = DuplicateReview.newestDate(group)
        guard newest > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(newest)).formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - Header band

/// The pinned band under the navigation bar: kind filter, scan progress
/// and what is still unchecked. Sort and Check Again sit in the navigation
/// bar. Cards scroll beneath it.
private struct DuplicatesHeaderBand: View {
    @Bindable var model: DuplicatesModel
    let isRegular: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            filterRow
            Group {
                if model.isScanning {
                    progress
                        .frame(maxWidth: isRegular ? 420 : .infinity, alignment: .leading)
                        .padding(.horizontal, AppTheme.Size.screenMargin)
                } else if let status = statusText {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .padding(.horizontal, AppTheme.Size.screenMargin)
                }
            }
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// One segment per filter that has something — Exact · Similar · Burst,
    /// no All (§7.3); a PhotoKit burst is a Burst group (§4). A segmented
    /// control, not pills (user, 2026-10-22): always exactly one is chosen.
    private var filterRow: some View {
        Picker("Kind", selection: $model.filter) {
            ForEach(model.presentFilters, id: \.self) { filter in
                Text("\(filter.title) \(model.groupCount(filter).formatted())")
                    .monospacedDigit()
                    .accessibilityLabel("\(filter.title), \(model.groupCount(filter))")
                    .tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: isRegular ? 420 : .infinity)
        .padding(.horizontal, AppTheme.Size.screenMargin)
        .disabled(model.isBusy && !model.isScanning)
    }

    @ViewBuilder
    private var progress: some View {
        if case .scanning(let scan) = model.phase {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                HStack {
                    Text(DuplicatesScanProgress.text(scan, found: model.groups.count))
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                    Spacer()
                    // Accent, not red: on this screen red only ever means
                    // "this photo goes" (Q8). Cancelling keeps every batch saved.
                    Button("Cancel") { model.cancelScan() }
                        .font(.footnote.weight(.semibold))
                        .frame(minHeight: 44)
                }
                ProgressView(value: scan.fraction)
            }
        }
        // No "~4.2 GB to free" and no "Reviewed x of y" (user, 2026-10-22).
    }

    /// "Checked 2 min ago · 148 photos only in iCloud — will check on Wi-Fi";
    /// the band shows it only when something waits (A4).
    private var statusText: String? {
        guard let scanState = model.scanState else { return nil }
        let pending: String
        if !model.canUseNetwork, model.cloudOnlyCount > 0 {
            pending = model.cloudOnlyCount == 1
                ? String(localized: "1 photo only in iCloud — will check on Wi-Fi", comment: "Duplicates header: photos whose thumbnails need the network")
                : String(localized: "\(model.cloudOnlyCount.formatted()) photos only in iCloud — will check on Wi-Fi",
                         comment: "Duplicates header: photos whose thumbnails need the network")
        } else if model.pendingCount > 0 {
            pending = model.pendingCount == 1
                ? String(localized: "1 photo not checked yet", comment: "Duplicates header: photos a rescan would cover")
                : String(localized: "\(model.pendingCount.formatted()) photos not checked yet",
                         comment: "Duplicates header: photos a rescan would cover")
        } else {
            return nil
        }
        let checked = String(localized: "Checked \(scanState.scannedAt.formatted(.relative(presentation: .named)))",
                             comment: "Duplicates header: when the last scan ran")
        return "\(checked) · \(pending)"
    }
}

// MARK: - Decision card

/// One group as a decision: the keeper over 2×2 cells with "Keep", its
/// reasons and its sizes on the photo, the copies square in the cells beside
/// and below it. No button row (2026-10-21): the ring marks, a tap opens
/// Compare (Choose frames on a burst), a hold offers Keep all and Not
/// duplicates. A burst puts its keeper first and the rest in capture order
/// (FS-06.06 §7.4).
private struct DuplicateDecisionCard: View {
    let group: DuplicateGroup
    let model: DuplicatesModel
    let metrics: DuplicateCardMetrics
    /// The photo the user just marked from the big slot. Marking the
    /// suggested keeper makes the model suggest another one; without this
    /// the marked photo would leave the slot at once (into a cell, or out of
    /// sight in a folded group) and the ring would look dead.
    @State private var pinnedSlotId: String?

    var body: some View {
        let keeper = model.keeper(of: group)
        let slot = slotMember(keeper: keeper)
        // Only photos and the words on them (2026-10-21): no title, no
        // "to free", no notes, and every photo shown — no Show all.
        VStack(alignment: .leading, spacing: 0) {
            if let slot {
                // Burst: the keeper first, the rest in capture order.
                keeperGrid(slot, keeper: keeper,
                           copies: group.members.filter { $0.assetId != slot.assetId })
            }
        }
        .padding(DuplicateCardMetrics.cardPadding)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle.app(AppTheme.Radius.lg))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "\(group.sourceSet?.title ?? group.kind.title), \(group.count) photos",
                                   comment: "VoiceOver: a Duplicates card, which shows no title on screen"))
        .onAppear { model.loadTraits(for: group) }
    }

    /// The big slot holds the keeper, unless the user marked the photo in
    /// it — that one stays put, red, until it is unmarked.
    private func slotMember(keeper: HashedPhoto?) -> HashedPhoto? {
        if let pinnedSlotId, model.isMarked(pinnedSlotId),
           let pinned = group.members.first(where: { $0.assetId == pinnedSlotId }) {
            return pinned
        }
        return keeper
    }

    private func toggleMark(_ member: HashedPhoto, inSlot: Bool) {
        if inSlot, !model.isMarked(member.assetId) { pinnedSlotId = member.assetId }
        withAnimation(AppTheme.Motion.standard) { model.toggleMark(member.assetId, in: group) }
        if !model.isMarked(member.assetId), pinnedSlotId == member.assetId { pinnedSlotId = nil }
    }

    /// The keeper's reasons, or "Checking sharpness…" while the pass has not
    /// reached this group (§3 step 5).
    private func keeperChips(_ keeper: HashedPhoto?) -> [String] {
        if model.isChecking(group) {
            return [String(localized: "Checking sharpness…", comment: "Duplicates: chip on the kept photo while the group is being scored")]
        }
        return model.reasons(for: group, keeper: keeper).map(\.title)
    }

    /// The keeper over 2×2 cells at the top left, the copies in the cells
    /// beside and below it — every copy square, the card filled (board
    /// `PH_DuplicatesLargeGroup`). Sizes and reasons ride on the photos.
    /// - Parameter keeper: picked once per card — every caption is worded
    ///   against it, and picking it again per tile cost a group's worth of
    ///   scoring per tile on each redraw.
    private func keeperGrid(_ slot: HashedPhoto, keeper: HashedPhoto?, copies: [HashedPhoto]) -> some View {
        let origins = metrics.copyOrigins(count: copies.count)
        return ZStack(alignment: .topLeading) {
            tile(slot, side: metrics.keeper, radius: AppTheme.Radius.md, inSlot: true, keeper: keeper)
            ForEach(Array(copies.enumerated()), id: \.element.id) { index, member in
                tile(member, side: metrics.tile, radius: AppTheme.Radius.sm, inSlot: false, keeper: keeper)
                    .offset(x: origins[index].x, y: origins[index].y)
            }
        }
        .frame(height: metrics.gridHeight(copyCount: copies.count), alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func facts(_ member: HashedPhoto) -> String {
        var parts: [String] = []
        if let dimensions = DuplicateReview.dimensions(member) { parts.append(dimensions) }
        if let size = member.fileSize {
            parts.append(DuplicatesScreen.byteFormatter.string(fromByteCount: Int64(size)))
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    /// The caption inside a copy (§7.4): plain words, at most two lines,
    /// none on the keeper — its chips speak for it.
    private func captionLines(_ member: HashedPhoto, keeper: HashedPhoto?) -> [String] {
        member.assetId == keeper?.assetId ? [] : model.caption(of: member, in: group, keeper: keeper)
    }

    private func tile(_ member: HashedPhoto, side: CGFloat, radius: CGFloat, inSlot: Bool, keeper: HashedPhoto?) -> some View {
        let isKeeper = member.assetId == keeper?.assetId
        let isMarked = model.isMarked(member.assetId)
        return DuplicateThumbnail(
            asset: model.assetsById[member.assetId],
            side: side,
            radius: radius,
            isMarked: isMarked,
            showsKeep: isKeeper && !isMarked,
            onToggleMark: { toggleMark(member, inSlot: inSlot) },
            factLines: captionLines(member, keeper: keeper),
            chips: inSlot && isKeeper ? keeperChips(keeper) : [],
            isKeeper: isKeeper
        )
        // D7: a tap looks, the ring marks. A burst is looked at frame by
        // frame (2026-10-21: the card has no button row any more).
        .onTapGesture { open(member) }
        .sensoryFeedback(.selection, trigger: isMarked)
        .contextMenu {
            Button {
                pinnedSlotId = nil
                withAnimation(AppTheme.Motion.standard) { model.keepOnly(member.assetId, in: group) }
            } label: {
                Label(String(localized: "Keep just this one", comment: "Duplicates tile menu: keep this photo, mark the rest"),
                      systemImage: "checkmark.circle")
            }
            Button {
                toggleMark(member, inSlot: inSlot)
            } label: {
                Label(isMarked
                      ? String(localized: "Don't remove", comment: "Duplicates tile menu: take the mark away")
                      : String(localized: "Remove", comment: "Duplicates tile menu: mark for removal"),
                      systemImage: isMarked ? "trash.slash" : "trash")
            }
            if model.canCompare(group) {
                Button {
                    model.compare(group)
                } label: {
                    Label("Compare", systemImage: "rectangle.split.2x1")
                }
            }
            Divider()
            // Keep all and Not duplicates left the card's button row for
            // this menu (2026-10-21).
            let keptAll = model.isKeptAll(group)
            Button {
                withAnimation(AppTheme.Motion.standard) { model.toggleKeepAll(group) }
            } label: {
                Label(keptAll
                      ? String(localized: "Keeping all", comment: "Duplicates tile menu: the group is kept whole; tap to undo")
                      : String(localized: "Keep all", comment: "Duplicates tile menu: keep every photo of the group"),
                      systemImage: keptAll ? "checkmark" : "checkmark.circle.badge.plus")
            }
            Button {
                withAnimation(AppTheme.Motion.standard) { model.dismiss(group) }
            } label: {
                Label(String(localized: "Not duplicates", comment: "Duplicates card: these photos are not duplicates; never show them again"),
                      systemImage: "eye.slash")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(member, keeper: keeper, isMarked: isMarked))
        .accessibilityAddTraits(isMarked ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { open(member) }
        .accessibilityAction(named: isMarked
                             ? String(localized: "Don't remove", comment: "VoiceOver action on a tile")
                             : String(localized: "Remove", comment: "VoiceOver action on a tile")) {
            toggleMark(member, inSlot: inSlot)
        }
    }

    private func open(_ member: HashedPhoto) {
        if group.kind == .burst {
            model.openFrames(group, at: member.assetId)
        } else {
            model.compare(group, from: member.assetId)
        }
    }

    private func accessibilityLabel(_ member: HashedPhoto, keeper: HashedPhoto?, isMarked: Bool) -> String {
        let isKeeper = member.assetId == keeper?.assetId
        var parts: [String] = []
        if isKeeper { parts.append(String(localized: "Suggested to keep", comment: "VoiceOver: the photo the Duplicates card suggests keeping")) }
        parts.append(facts(member))
        let traits = model.traits(of: member.assetId)
        if traits.isFavorite { parts.append(String(localized: "favorite")) }
        if traits.isEdited { parts.append(String(localized: "edited")) }
        if traits.hasRAW { parts.append(String(localized: "RAW")) }
        if traits.isLive { parts.append(String(localized: "Live Photo")) }
        if !isKeeper { parts += model.caption(of: member, in: group, keeper: keeper) }
        parts.append(isMarked
                     ? String(localized: "will be removed", comment: "VoiceOver: a tile marked for removal")
                     : String(localized: "won't be removed", comment: "VoiceOver: a tile not marked"))
        return parts.joined(separator: ", ")
    }
}

// MARK: - Folded row

/// A decided group folded to one line: up to three thumbnails (marked ones
/// dimmed with a red edge), what is kept and deleted, and a chevron to open it.
private struct DuplicateCollapsedRow: View {
    let group: DuplicateGroup
    let model: DuplicatesModel

    var body: some View {
        Button {
            withAnimation(AppTheme.Motion.standard) { model.expand(group) }
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                HStack(spacing: AppTheme.Spacing.xs) {
                    ForEach(group.members.prefix(3)) { member in
                        let marked = model.isMarked(member.assetId)
                        DuplicateThumbnail(
                            asset: model.assetsById[member.assetId],
                            side: 32,
                            radius: 6,
                            isMarked: marked,
                            showsKeep: false,
                            showsMarkBadge: false
                        )
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    title
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .monospacedDigit()
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(height: 56)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle.app(AppTheme.Radius.lg))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Expand")
    }

    private var marked: Int { model.markedCount(in: group) }

    private var title: Text {
        if model.isKeptAll(group) {
            return Text("Keeping all \(group.count)", comment: "Duplicates folded row: the group is kept whole")
        }
        let keeping = Text("Keeping \(group.count - marked)", comment: "Duplicates folded row: photos kept")
        let deleting = Text(" · deleting \(marked)", comment: "Duplicates folded row: photos marked, follows 'Keeping N'")
            .foregroundStyle(.red)
        return keeping + deleting
    }

    private var detail: String {
        var parts: [String] = []
        if let date = DuplicatesScreen.dateText(group) { parts.append(date) }
        if model.isKeptAll(group) {
            parts.append(String(localized: "nothing to delete", comment: "Duplicates folded row of a group kept whole"))
        } else {
            let bytes = group.members
                .filter { model.isMarked($0.assetId) }
                .reduce(0) { $0 + ($1.fileSize ?? 0) }
            parts.append(String(localized: "\(DuplicatesScreen.byteFormatter.string(fromByteCount: Int64(bytes))) to free",
                                comment: "Duplicates folded row: size of the marked photos"))
        }
        return parts.joined(separator: " · ")
    }

    private var accessibilityText: String {
        let date = DuplicatesScreen.dateText(group) ?? ""
        if model.isKeptAll(group) {
            return String(localized: "Reviewed group, \(date): keeping all \(group.count)")
        }
        return String(localized: "Reviewed group, \(date): keeping \(group.count - marked), deleting \(marked)")
    }
}

// MARK: - Thumbnail

/// Square thumbnail. Marked = trash disc white-on-red, 3pt red edge, image at
/// 45% (red is destructive, apart from the grid's accent "selected" tick);
/// unmarked = an empty white ring. The keeper carries a "Keep" badge.
struct DuplicateThumbnail: View {
    @Environment(PhotoLibraryService.self) private var photoLibrary

    let asset: PHAsset?
    let side: CGFloat
    let radius: CGFloat
    let isMarked: Bool
    let showsKeep: Bool
    var showsMarkBadge = true
    /// The ring's action. Its hit area is 44pt even though it draws 26pt
    /// (AC-C2); the rest of the tile belongs to the tap that opens Compare.
    var onToggleMark: (() -> Void)?
    /// Pixel size and file size (or a series frame's seconds), on the photo
    /// rather than under it (board `PH_DuplicatesLargeGroup`).
    var factLines: [String] = []
    /// The keeper's reasons — Edited, RAW, Favorite — top left on the photo.
    var chips: [String] = []
    var isKeeper = false

    @State private var image: UIImage?
    @State private var requestId: PHImageRequestID?
    @State private var requestedSide: CGFloat = 0

    var body: some View {
        Color(.tertiarySystemBackground)
            .frame(width: side, height: side)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .opacity(isMarked ? 0.45 : 1)
                } else {
                    Image(systemName: "photo")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                }
            }
            .clipShape(RoundedRectangle.app(radius))
            .overlay {
                if isMarked {
                    RoundedRectangle.app(radius)
                        .strokeBorder(.red, lineWidth: showsMarkBadge ? 3 : 2)
                }
            }
            .overlay(alignment: .topTrailing) {
                if showsMarkBadge {
                    let ring = Image(systemName: isMarked ? "trash.circle.fill" : "circle")
                        .symbolRenderingMode(isMarked ? .palette : .monochrome)
                        .foregroundStyle(.white, .red)
                        .font(.system(size: 26))
                        .shadow(color: .black.opacity(0.35), radius: 2)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                    if let onToggleMark {
                        Button(action: onToggleMark) { ring }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isMarked
                                ? String(localized: "Don't remove", comment: "VoiceOver: the ring on a marked tile")
                                : String(localized: "Remove", comment: "VoiceOver: the ring on a tile"))
                    } else {
                        ring.accessibilityHidden(true)
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                if !chips.isEmpty {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        ForEach(chips, id: \.self) { chip in
                            Text(chip)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .frame(height: 20)
                                .background(Color.black.opacity(0.55), in: Capsule())
                        }
                    }
                    .padding(AppTheme.Spacing.sm)
                }
            }
            .overlay(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: 6) {
                    if showsKeep {
                        Label("Keep", systemImage: "checkmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                            .labelStyle(KeepBadgeLabelStyle())
                            .padding(.horizontal, AppTheme.Spacing.sm)
                            .frame(height: 24)
                            .background(Color.black.opacity(0.55), in: Capsule())
                    }
                    if !factLines.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(factLines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .fontWeight(index == 0 ? .semibold : .regular)
                                    .opacity(index == 0 ? 1 : 0.85)
                            }
                        }
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
                .padding(side > 120 ? AppTheme.Spacing.sm : 5)
                .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .onAppear(perform: loadThumbnail)
            .onChange(of: side) { loadThumbnail() }
            .onDisappear(perform: cancelThumbnail)
    }

    /// Asks again whenever the tile grows — a copy promoted to keeper goes
    /// from one cell to 2x2, and its small image would otherwise stay,
    /// scaled up and soft. Not gated on a request in flight: PhotoKit often
    /// answers the degraded pass synchronously, before the id is stored.
    private func loadThumbnail() {
        guard let asset, side > requestedSide + 1 || image == nil else { return }
        cancelThumbnail()
        let size = side
        requestedSide = size
        request(asset, size: size, allowNetwork: false)
    }

    /// Local first; a final answer that is only the Optimize Storage proxy
    /// asks iCloud for the real pixels — a soft tile cannot be judged
    /// against its neighbour. The network pass waits for a free slot.
    private func request(_ asset: PHAsset, size: CGFloat, allowNetwork: Bool, attempt: Int = 0) {
        let pixels = size * ActiveDisplay.scale
        requestId = photoLibrary.requestThumbnail(
            for: asset,
            targetSize: CGSize(width: pixels, height: pixels),
            allowNetwork: allowNetwork
        ) { result, delivery in
            // A late answer to a smaller request must not replace a sharper one.
            guard size == requestedSide else { return }
            if let result { image = result }
            guard !delivery.isDegraded, !delivery.isSharp, attempt < 5 else { return }
            if result != nil, allowNetwork { return }
            // Local proxy only, or the network gate was full: try iCloud.
            Task { @MainActor in
                if allowNetwork || result == nil { try? await Task.sleep(for: .seconds(1)) }
                guard size == requestedSide, requestId != nil else { return }
                request(asset, size: size, allowNetwork: true, attempt: attempt + 1)
            }
        }
    }

    private func cancelThumbnail() {
        if let requestId {
            photoLibrary.cancelThumbnailRequest(requestId)
        }
        requestId = nil
    }
}

struct KeepBadgeLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            configuration.icon.font(.caption.weight(.bold))
            configuration.title
        }
    }
}

/// The screen's alerts, out of `content` so the type checker keeps up.
private struct DuplicatesAlerts: ViewModifier {
    @Bindable var model: DuplicatesModel

    func body(content: Content) -> some View {
        content
            .alert(
            model.notice?.title ?? "",
            isPresented: Binding(
                get: { model.notice != nil },
                set: { if !$0 { model.notice = nil } }
            ),
            presenting: model.notice
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { notice in
            Text(notice.message)
        }
            .alert(
            "Duplicates Error",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

