import Photos
import SwiftUI

/// Navigation value for the Duplicates utility, pushed from the Collections tab.
struct DuplicatesDestination: Hashable {}

/// Duplicates utility (tier A, DESIGN.md §2; FS-06.06 §7). A pinned band —
/// kind filter, sort, how many groups are reviewed, the last scan and Rescan —
/// over a list of **decision cards**: the suggested keeper big with "Keep" and
/// why, the copies beside it each saying what it lacks, and one-tap Mark the
/// other N · Keep all · Compare. A decided group folds to one line. Marks
/// gather in a floating bar with Delete. Pinch changes copies per row.
/// Nothing is marked until the user taps, and nothing rescans unless asked.
struct DuplicatesScreen: View {
    /// The summary opens first (§7.2); the list is pushed from it and shares
    /// its model, so marks, scores and the scan carry across.
    enum Page { case summary, list }

    var page: Page = .summary
    var sharedModel: DuplicatesModel?

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
    @State private var burstList: BurstListModel?
    @State private var openBurst: BurstFramesRequest?
    @State private var showsList = false
    @State private var showsQuickClean = false

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
            if model == nil { model = sharedModel ?? DuplicatesModel(dependencies: dependencies) }
        }
    }

    @ViewBuilder
    private func content(_ model: DuplicatesModel) -> some View {
        @Bindable var model = model
        let hasMarks = model.markedCount > 0 && !model.showsBursts
        ScrollView {
            Group {
                if page == .summary {
                    summaryBody(model)
                } else if model.showsBursts, let burstList {
                    BurstListView(model: burstList, openBurst: $openBurst)
                } else {
                    cardList(model)
                }
            }
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
                let showsBand = page == .list
                if let access = permissionAccess(model) {
                    DuplicatesPermissionBanner(access: access)
                        .padding(.horizontal, AppTheme.Size.screenMargin)
                        .padding(.vertical, AppTheme.Spacing.sm)
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                }
                if showsBand {
                    DuplicatesHeaderBand(model: model, burstCount: burstList?.listed.count, isRegular: isRegular)
                }
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
            if model.showsBursts { await burstList?.reload() }
        }
        .task(id: model.showsBursts) {
            guard model.showsBursts, photoLibrary.authorizationState.canReadLibrary else { return }
            if burstList == nil { burstList = BurstListModel(library: dependencies.bursts) }
            await burstList?.reload()
        }
        .navigationDestination(isPresented: $showsList) {
            DuplicatesScreen(page: .list, sharedModel: model)
        }
        .sheet(isPresented: $showsQuickClean) {
            DuplicatesQuickCleanSheet(model: model)
        }
        .photoStackCover($model.stackPresentation, onSaved: { _ in model.loadCache() })
        .sheet(item: $model.viewer) { presentation in
            DuplicateGroupViewer(model: model, presentation: presentation)
                .environment(photoLibrary)
        }
        .fullScreenCover(item: $openBurst) { request in
            BurstFramesScreen(request: request)
                .environment(dependencies)
                .environment(photoLibrary)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !model.showsBursts { moreMenu(model) }
            }
        }
        .fullScreenCover(item: $model.comparePresentation, onDismiss: model.didCloseCompare) { presentation in
            PhotoDetailScreen(
                model: presentation.source,
                currentIndex: presentation.request.startIndex,
                compareRequest: presentation.request
            )
        }
        .modifier(DuplicatesAlerts(model: model, mergeTitle: mergeAlertTitle(model), mergeMessage: mergeAlertMessage(model)))
        .animation(AppTheme.Motion.standard, value: hasMarks)
        .animation(AppTheme.Motion.standard, value: hudVisible)
    }

    private func moreMenu(_ model: DuplicatesModel) -> some View {
        Menu {
            Button {
                model.startScan()
            } label: {
                Label(String(localized: "Check Again", comment: "Duplicates ⋯: scan the library again"), systemImage: "arrow.clockwise")
            }
            .disabled(model.isBusy || !photoLibrary.authorizationState.canReadLibrary)
            if model.canMerge {
                Button {
                    model.isConfirmingMerge = true
                } label: {
                    Label(mergeTitle(model), systemImage: "arrow.trianglehead.merge")
                }
                .disabled(model.isBusy)
            }
            Button {
                withAnimation(AppTheme.Motion.standard) { model.clearAllMarks() }
            } label: {
                Label("Clear Selection", systemImage: "xmark.circle")
            }
            .disabled(model.markedCount == 0 && model.reviewedCount == 0)
        } label: {
            Image(systemName: "ellipsis")
        }
        .tint(.primary)
        .accessibilityLabel("More")
    }

    // MARK: Summary

    @ViewBuilder
    private func summaryBody(_ model: DuplicatesModel) -> some View {
        if model.groups.isEmpty, !model.isScanning {
            emptyState(model)
                .frame(maxWidth: .infinity)
                .padding(.top, AppTheme.Spacing.xxl)
        } else {
            DuplicatesSummaryView(
                model: model,
                isRegular: isRegular,
                open: { filter in
                    model.filter = filter
                    model.showsBursts = false
                    showsList = true
                },
                reviewQuickClean: { showsQuickClean = true }
            )
        }
    }

    // MARK: Cards

    @ViewBuilder
    private func cardList(_ model: DuplicatesModel) -> some View {
        if model.sortedGroups.isEmpty {
            emptyState(model)
                .frame(maxWidth: .infinity)
                .padding(.top, AppTheme.Spacing.xxl)
        } else {
            let contentWidth = max(0, containerWidth - AppTheme.Size.screenMargin * 2)
            let columnCount = DuplicateCardMetrics.cardColumns(contentWidth: contentWidth, isRegular: isRegular)
            let cardWidth = DuplicateCardMetrics.cardWidth(contentWidth: contentWidth, columns: columnCount)
            let metrics = DuplicateCardMetrics(
                innerWidth: cardWidth - DuplicateCardMetrics.cardPadding * 2,
                copyColumns: copyColumns
            )
            let columns = distribute(model.sortedGroups, into: columnCount, model: model, metrics: metrics)
            HStack(alignment: .top, spacing: DuplicateCardMetrics.cardSpacing) {
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
            return 58 + CGFloat(rows) * (metrics.tile + DuplicateCardMetrics.copyGap) + 44 + AppTheme.Spacing.md * 2
        }
        let shown = model.isFolded(group) ? min(group.count - 1, metrics.copyColumns * 2) : group.count - 1
        let body = metrics.gridHeight(copyCount: shown) + (model.isFolded(group) ? 52 : 0)
        return 58 + body + AppTheme.Spacing.md + 44 + AppTheme.Spacing.md
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
        return HStack(spacing: AppTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(count) marked · \(bytes)", comment: "Duplicates: floating bar, number of marked photos and their size")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text("Recently Deleted for 30 days", comment: "Duplicates: floating bar, where deleted photos go")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .frame(maxWidth: isRegular ? nil : .infinity, minHeight: 48, alignment: .leading)
            .glassBackground(Capsule())
            .accessibilityElement(children: .combine)

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
            .accessibilityLabel(count == 1 ? "Delete 1 photo" : "Delete \(count) photos")
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

    // MARK: Merge alert

    private func mergeTitle(_ model: DuplicatesModel) -> String {
        let groups = model.groups.count
        return groups == 1
            ? String(localized: "Merge 1 Group…", comment: "Duplicates ⋯ menu, Exact only")
            : String(localized: "Merge \(groups) Groups…", comment: "Duplicates ⋯ menu, Exact only")
    }

    private func mergeAlertTitle(_ model: DuplicatesModel) -> String {
        let groups = model.groups.count
        return groups == 1
            ? String(localized: "Merge 1 Group?", comment: "Duplicates: merge confirmation title")
            : String(localized: "Merge \(groups) Groups?", comment: "Duplicates: merge confirmation title")
    }

    private func mergeAlertMessage(_ model: DuplicatesModel) -> String {
        let marked = model.duplicatePhotoCount - model.groups.count
        return String(
            localized: "Keeps one copy in each group and marks \(marked) photos for deletion. The kept copy takes the favorite, location and earliest date of its copies — saved to Photos now. Nothing is deleted until you tap Delete.",
            comment: "Duplicates: merge confirmation message"
        )
    }

    // MARK: Empty

    private func emptyDescription(_ model: DuplicatesModel) -> String {
        let scanned = model.coverage.hashedPhotos
        if model.filter != .all {
            return String(localized: "No \(model.filter.title) among \(scanned) photos.", comment: "Duplicates: empty list filtered to one kind")
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
        } else if model.hasNeverScanned {
            ContentUnavailableView {
                Label("Not Scanned Yet", systemImage: "square.on.square")
            } description: {
                Text("Scan your library once; the results are kept and you rescan whenever you like.")
            } actions: {
                Button("Scan Library") {
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

/// The pinned band under the navigation bar: kind filter, sort, review
/// progress, last scan and Rescan. Cards scroll beneath it.
private struct DuplicatesHeaderBand: View {
    @Bindable var model: DuplicatesModel
    /// Bursts listed in the Bursts tab, once read.
    let burstCount: Int?
    let isRegular: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            filterRow
            if model.showsBursts {
                if let burstCount {
                    Text(BurstSummary.countTitle(burstCount))
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, AppTheme.Size.screenMargin)
                }
            } else {
                HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
                    progress.frame(maxWidth: isRegular ? 420 : .infinity, alignment: .leading)
                    if isRegular { Spacer(minLength: 0) }
                    if !model.isScanning { sortMenu }
                }
                .padding(.horizontal, AppTheme.Size.screenMargin)
                if !model.isScanning, let status = statusText {
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

    /// One pill per filter that has something, plus Bursts until the shared
    /// frame picker absorbs it (plan task 20). Each pill is as wide as its own
    /// bold label, so choosing one never moves the others (A6, AC-L1).
    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.sm) {
                ForEach(model.presentFilters, id: \.self) { filter in
                    pill(filter.title, count: model.groupCount(filter),
                         isSelected: !model.showsBursts && model.filter == filter) {
                        model.showsBursts = false
                        model.filter = filter
                    }
                }
                pill(DuplicatesTab.bursts.title, count: burstCount, isSelected: model.showsBursts) {
                    model.showsBursts = true
                }
            }
            .padding(.horizontal, AppTheme.Size.screenMargin)
        }
        .scrollClipDisabled()
        .disabled(model.isBusy && !model.isScanning)
    }

    private func pill(_ title: String, count: Int?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                // The bold layout reserves the width either way.
                label(title, count: count, bold: true).hidden()
                label(title, count: count, bold: isSelected)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(height: 34)
            .background(isSelected ? Color(.systemBackground) : Color(.secondarySystemFill), in: Capsule())
            .overlay {
                if isSelected { Capsule().strokeBorder(Color(.separator), lineWidth: 0.5) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func label(_ title: String, count: Int?, bold: Bool) -> some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Text(title).fontWeight(bold ? .semibold : .regular).foregroundStyle(.primary)
            if let count {
                Text(count.formatted()).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .font(.subheadline)
        .lineLimit(1)
        .fixedSize()
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $model.sort) {
                ForEach(DuplicateSort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.xs) {
                Text(model.sort.title)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .font(.footnote.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(height: 32)
            .background(Color(.secondarySystemFill), in: Capsule())
        }
        .fixedSize()
        .accessibilityLabel("Sort groups: \(model.sort.title)")
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
        } else if !model.groups.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                (Text(reviewedText).fontWeight(.semibold) + Text(freeText).foregroundStyle(.secondary))
                    .font(.footnote)
                    .monospacedDigit()
                    .lineLimit(1)
                ProgressView(value: Double(model.reviewedCount), total: Double(max(1, model.groups.count)))
                    .tint(.green)
                    .accessibilityLabel("Groups reviewed")
            }
        }
    }

    /// "Reviewed 4 of 312" — short enough to leave room for the free space
    /// and the sort menu on a phone (board `PH_Duplicates`).
    private var reviewedText: String {
        let total = model.groups.filter(model.filter.includes).count
        let done = model.groups.filter { model.filter.includes($0) && model.isReviewed($0) }.count
        return String(localized: "Reviewed \(done) of \(total)", comment: "Duplicates header: groups decided out of the groups shown")
    }

    private var freeText: String {
        let bytes = model.totalFreeBytes
        guard bytes > 0 else { return "" }
        let size = DuplicatesScreen.byteFormatter.string(fromByteCount: Int64(bytes))
        return " · " + String(localized: "~\(size) to free", comment: "Duplicates header: space freed by keeping one per group")
    }

    /// "Checked 2 min ago · 148 photos only in iCloud — will check on Wi-Fi";
    /// the band shows it only when something waits (A4).
    private var statusText: String? {
        guard let scanState = model.scanState else { return nil }
        let pending: String
        if !model.canUseNetwork, model.cloudOnlyCount > 0 {
            pending = String(localized: "\(model.cloudOnlyCount.formatted()) photos only in iCloud — will check on Wi-Fi",
                             comment: "Duplicates header: photos whose thumbnails need the network")
        } else if model.pendingCount > 0 {
            pending = String(localized: "\(model.pendingCount.formatted()) photos not checked yet",
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
/// and below it, and the three one-tap actions. A same-moment run puts its
/// keeper first and the rest in capture order (FS-06.06 §7.4).
private struct DuplicateDecisionCard: View {
    let group: DuplicateGroup
    let model: DuplicatesModel
    let metrics: DuplicateCardMetrics
    /// Bumped by Remove the other N / Keep all, for a light impact (§7.4).
    @State private var shortcutTaps = 0

    var body: some View {
        let keeper = model.keeper(of: group)
        VStack(alignment: .leading, spacing: 0) {
            header(keeper: keeper)
                .padding(.bottom, AppTheme.Spacing.sm)

            if let keeper {
                // Same moment: the keeper first, the rest in capture order.
                let copies = group.members.filter { $0.assetId != keeper.assetId }
                let isFolded = model.isFolded(group)
                keeperGrid(keeper, copies: isFolded ? Array(copies.prefix(metrics.copyColumns * 2)) : copies)
                if isFolded {
                    // D9: a 52-photo burst would be four screens of tiles.
                    Button {
                        withAnimation(AppTheme.Motion.standard) { model.showAll(group) }
                    } label: {
                        Text(String(localized: "Show all \(copies.count)", comment: "Duplicates card: open every photo of a large group"))
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(Color(.secondarySystemFill), in: Capsule())
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, AppTheme.Spacing.sm)
                }
            }

            notices
            actions(keeper: keeper)
                .padding(.top, AppTheme.Spacing.sm)
        }
        .padding(DuplicateCardMetrics.cardPadding)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle.app(AppTheme.Radius.lg))
        .onAppear { model.loadTraits(for: group) }
        .sensoryFeedback(.impact(weight: .light), trigger: shortcutTaps)
    }

    private func header(keeper: HashedPhoto?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.sourceSet?.title
                     ?? String(localized: "\(group.kind.title) · \(group.count) photos", comment: "Duplicates card title: kind and size of the group"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let free = model.freeBytes(of: group), free > 0 {
                    Text("~\(DuplicatesScreen.byteFormatter.string(fromByteCount: Int64(free))) to free",
                         comment: "Duplicates card: space freed by keeping only the kept photo")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    /// The keeper's reasons, or "Checking sharpness…" while the pass has not
    /// reached this group (§3 step 5).
    private var keeperChips: [String] {
        if model.isChecking(group) {
            return [String(localized: "Checking sharpness…", comment: "Duplicates: chip on the kept photo while the group is being scored")]
        }
        return model.reasons(for: group).map(\.title)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let date = DuplicatesScreen.dateText(group) { parts.append(date) }
        if group.kind == .copies {
            parts.append(String(localized: "Identical files", comment: "Duplicates card, Copies: the copies are the same file"))
        } else if let span = DuplicateReview.spanText(group.members) {
            parts.append(span)
        }
        return parts.joined(separator: " · ")
    }

    /// The keeper over 2×2 cells at the top left, the copies in the cells
    /// beside and below it — every copy square, the card filled (board
    /// `PH_DuplicatesLargeGroup`). Sizes and reasons ride on the photos.
    private func keeperGrid(_ keeper: HashedPhoto, copies: [HashedPhoto]) -> some View {
        let origins = metrics.copyOrigins(count: copies.count)
        return ZStack(alignment: .topLeading) {
            tile(keeper, side: metrics.keeper, radius: AppTheme.Radius.md, isKeeper: true)
            ForEach(Array(copies.enumerated()), id: \.element.id) { index, member in
                tile(member, side: metrics.tile, radius: AppTheme.Radius.sm, isKeeper: false)
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
    private func captionLines(_ member: HashedPhoto, isKeeper: Bool) -> [String] {
        isKeeper ? [] : model.caption(of: member, in: group)
    }

    private func tile(_ member: HashedPhoto, side: CGFloat, radius: CGFloat, isKeeper: Bool) -> some View {
        let isMarked = model.isMarked(member.assetId)
        let isLast = model.isLastUnmarked(member.assetId, in: group)
        return DuplicateThumbnail(
            asset: model.assetsById[member.assetId],
            side: side,
            radius: radius,
            isMarked: isMarked,
            showsKeep: isKeeper && !isMarked,
            onToggleMark: {
                withAnimation(AppTheme.Motion.standard) { _ = model.toggleMark(member.assetId, in: group) }
            },
            factLines: captionLines(member, isKeeper: isKeeper),
            chips: isKeeper ? keeperChips : [],
            isKeeper: isKeeper
        )
        // D7: a tap looks, the ring marks.
        .onTapGesture { model.openViewer(member.assetId, in: group) }
        .sensoryFeedback(.selection, trigger: isMarked)
        .sensoryFeedback(.warning, trigger: model.blockedGroupId == group.id) { _, blocked in blocked }
        .contextMenu {
            Button {
                withAnimation(AppTheme.Motion.standard) { model.keepOnly(member.assetId, in: group) }
            } label: {
                Label(String(localized: "Keep just this one", comment: "Duplicates tile menu: keep this photo, mark the rest"),
                      systemImage: "checkmark.circle")
            }
            Button {
                withAnimation(AppTheme.Motion.standard) { _ = model.toggleMark(member.assetId, in: group) }
            } label: {
                Label(isMarked
                      ? String(localized: "Don't remove", comment: "Duplicates tile menu: take the mark away")
                      : String(localized: "Remove", comment: "Duplicates tile menu: mark for removal"),
                      systemImage: isMarked ? "trash.slash" : "trash")
            }
            .disabled(!isMarked && isLast)
            if model.canCompare(group) {
                Button {
                    model.compare(group)
                } label: {
                    Label("Compare", systemImage: "rectangle.split.2x1")
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(member, isKeeper: isKeeper, isMarked: isMarked))
        .accessibilityAddTraits(isMarked ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.openViewer(member.assetId, in: group) }
        .accessibilityAction(named: isMarked
                             ? String(localized: "Don't remove", comment: "VoiceOver action on a tile")
                             : String(localized: "Remove", comment: "VoiceOver action on a tile")) {
            _ = model.toggleMark(member.assetId, in: group)
        }
    }

    private func accessibilityLabel(_ member: HashedPhoto, isKeeper: Bool, isMarked: Bool) -> String {
        var parts: [String] = []
        if isKeeper { parts.append(String(localized: "Suggested keep", comment: "VoiceOver: the photo the Duplicates card suggests keeping")) }
        parts.append(facts(member))
        let traits = model.traits(of: member.assetId)
        if traits.isFavorite { parts.append(String(localized: "favorite")) }
        if traits.isEdited { parts.append(String(localized: "edited")) }
        if traits.hasRAW { parts.append(String(localized: "RAW")) }
        if traits.isLive { parts.append(String(localized: "Live Photo")) }
        if !isKeeper { parts += model.caption(of: member, in: group) }
        parts.append(isMarked
                     ? String(localized: "marked for deletion")
                     : String(localized: "not marked"))
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var notices: some View {
        if model.isFullyMarked(group) {
            Label("All copies marked — nothing will be kept", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
                .padding(.top, AppTheme.Spacing.sm)
        } else if model.markedCount(in: group) == 0, let removal = model.removal(in: group),
                  let kept = DuplicateProtection.keptLine(removal.kept, namingAlbums: false) {
            // A2: Remove the other N leaves these alone; say so before the tap.
            Text(kept)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, AppTheme.Spacing.sm)
        }
        if model.blockedGroupId == group.id {
            Label("Keep at least one photo in this group.", systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, AppTheme.Spacing.sm)
                .transition(.opacity)
        }
    }

    /// Remove the other N · Keep all · Compare. When a long count leaves no
    /// room, Compare drops to its icon before any word is cut.
    private func actions(keeper: HashedPhoto?) -> some View {
        ViewThatFits(in: .horizontal) {
            actionRow(compactCompare: false)
            actionRow(compactCompare: true)
        }
    }

    private func actionRow(compactCompare: Bool) -> some View {
        let marked = model.markedCount(in: group)
        let keptAll = model.isKeptAll(group)
        return HStack(spacing: AppTheme.Spacing.sm) {
            if marked > 0 {
                pill(String(localized: "Unmark", comment: "Duplicates card: clear this group's marks"), color: .primary) {
                    model.unmark(group)
                }
            } else if let removal = model.removal(in: group), !removal.remove.isEmpty {
                let others = removal.remove.count
                pill(others == 1
                     ? String(localized: "Remove the other one", comment: "Duplicates card: mark every photo but the kept one")
                     : String(localized: "Remove the other \(others)", comment: "Duplicates card: mark every photo but the kept one"),
                     color: .red) {
                    model.markOthers(in: group)
                    shortcutTaps += 1
                }
            }
            pill(keptAll
                 ? String(localized: "Keeping all", comment: "Duplicates card: the group is kept whole; tap to undo")
                 : String(localized: "Keep all", comment: "Duplicates card: keep every photo of the group"),
                 color: .accentColor,
                 systemImage: keptAll ? "checkmark" : nil) {
                model.toggleKeepAll(group)
                shortcutTaps += 1
            }
            Spacer(minLength: 0)
            if model.canCompare(group) {
                let title = String(localized: "Compare", comment: "Duplicates card: open the group side by side")
                if compactCompare {
                    pill("", color: .accentColor, systemImage: "rectangle.split.2x1") { model.compare(group) }
                        .accessibilityLabel(title)
                } else {
                    pill(title, color: .accentColor) { model.compare(group) }
                }
            }
        }
        .fixedSize(horizontal: !compactCompare, vertical: false)
    }

    private func pill(_ title: String, color: Color, systemImage: String? = nil, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(AppTheme.Motion.standard) { action() }
        } label: {
            HStack(spacing: AppTheme.Spacing.xs) {
                if let systemImage { Image(systemName: systemImage).font(.footnote.weight(.bold)) }
                if !title.isEmpty { Text(title) }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(height: 34)
            .background(Color(.secondarySystemFill), in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy)
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
    /// (AC-C2); the rest of the tile belongs to the tap that opens the viewer.
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
        let pixels = size * ActiveDisplay.scale
        requestId = photoLibrary.requestThumbnail(
            for: asset,
            targetSize: CGSize(width: pixels, height: pixels),
            // The keeper is the photo the decision rests on: fetch it from
            // iCloud when only a proxy is on the device.
            allowNetwork: isKeeper
        ) { result in
            // A late answer to a smaller request must not replace a sharper one.
            guard size == requestedSide, let result else { return }
            image = result
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
    let mergeTitle: String
    let mergeMessage: String

    func body(content: Content) -> some View {
        content
            .alert(mergeTitle, isPresented: $model.isConfirmingMerge) {
            Button("Merge") { Task { await model.mergeAll() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(mergeMessage)
        }
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

/// The Duplicates list's filter, or the Bursts list until the shared frame
/// picker replaces it (plan task 20).
enum DuplicatesTab: Hashable {
    case filter(DuplicatesFilter)
    case bursts

    var title: String {
        switch self {
        case .filter(let filter): filter.title
        case .bursts: String(localized: "Bursts", comment: "Duplicates tab: real bursts from Photos")
        }
    }
}
