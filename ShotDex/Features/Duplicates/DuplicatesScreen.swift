import Photos
import SwiftUI

/// Navigation value for the Duplicates utility, pushed from the Collections tab.
struct DuplicatesDestination: Hashable {}

/// Duplicates utility (tier A, DESIGN.md §2; FS-06.06 §7). A pinned band —
/// strictness, sort, how many groups are reviewed, the last scan and Rescan —
/// over a list of **decision cards**: the suggested keeper big with "Keep" and
/// why, the copies beside it each saying what it lacks, and one-tap Mark the
/// other N · Keep all · Compare. A decided group folds to one line. Marks
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

    private var isRegular: Bool { horizontalSizeClass == .regular }

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
            DuplicatesHeaderBand(model: model, isRegular: isRegular)
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
        .onDisappear { navigation.hidesTabBar = false }
        .sensoryFeedback(.selection, trigger: copyColumns)
        .task {
            guard photoLibrary.authorizationState.canReadLibrary else { return }
            model.loadIfNeeded()
        }
        .task(id: photoLibrary.assetChangeToken) {
            guard photoLibrary.authorizationState.canReadLibrary else { return }
            model.refreshPendingCount()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        model.startScan()
                    } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isBusy)
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
        }
        .fullScreenCover(item: $model.comparePresentation) { presentation in
            PhotoDetailScreen(
                model: presentation.source,
                currentIndex: presentation.request.startIndex,
                compareRequest: presentation.request
            )
        }
        .alert(mergeAlertTitle(model), isPresented: $model.isConfirmingMerge) {
            Button("Merge") { Task { await model.mergeAll() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(mergeAlertMessage(model))
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
        .animation(AppTheme.Motion.standard, value: hasMarks)
        .animation(AppTheme.Motion.standard, value: hudVisible)
    }

    // MARK: Cards

    @ViewBuilder
    private func cardList(_ model: DuplicatesModel) -> some View {
        if model.groups.isEmpty {
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
        let captionRow = metrics.tile + AppTheme.Spacing.xs + 15
        let body: CGFloat
        if model.strictness == .series {
            let perRow = metrics.copyColumns + 2
            let rows = CGFloat((group.count + perRow - 1) / perRow)
            body = rows * captionRow + (rows - 1) * AppTheme.Spacing.sm
        } else {
            let copies = group.count - 1
            let rows = CGFloat((copies + metrics.copyColumns - 1) / metrics.copyColumns)
            body = max(metrics.keeper + 44, rows * captionRow + (rows - 1) * AppTheme.Spacing.sm)
        }
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
        return switch model.strictness {
        case .exact: "No exact duplicates among \(scanned) photos."
        case .similar: "No similar duplicates among \(scanned) photos."
        case .series: "No runs of \(DuplicateStrictness.seriesMinCount) or more frames of one moment among \(scanned) photos."
        }
    }

    @ViewBuilder
    private func emptyState(_ model: DuplicatesModel) -> some View {
        if model.isScanning {
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
            ContentUnavailableView(
                model.strictness == .series ? "No Series" : "No Duplicates",
                systemImage: "checkmark.circle",
                description: Text(emptyDescription(model))
            )
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

/// The pinned band under the navigation bar: strictness, sort, review
/// progress, last scan and Rescan. Cards scroll beneath it.
private struct DuplicatesHeaderBand: View {
    @Bindable var model: DuplicatesModel
    let isRegular: Bool

    var body: some View {
        Group {
            if isRegular {
                // One row when it fits (iPad landscape, the board); iPad
                // portrait and the Duo inner put the scan line under the
                // progress instead of truncating it.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppTheme.Spacing.md) {
                        strictnessPicker.frame(width: 330)
                        sortMenu
                        progress.frame(width: 400)
                        Spacer(minLength: AppTheme.Spacing.md)
                        if !model.isScanning {
                            statusLine.fixedSize()
                            rescanButton
                        }
                    }
                    HStack(spacing: AppTheme.Spacing.md) {
                        strictnessPicker.frame(width: 300)
                        sortMenu
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            progress
                            if !model.isScanning { statusLine }
                        }
                        .frame(maxWidth: 420)
                        Spacer(minLength: 0)
                        if !model.isScanning { rescanButton }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        strictnessPicker
                        sortMenu
                    }
                    HStack(alignment: .center, spacing: AppTheme.Spacing.sm) {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            progress
                            if !model.isScanning { statusLine }
                        }
                        if !model.isScanning { rescanButton }
                    }
                }
            }
        }
        .padding(.horizontal, AppTheme.Size.screenMargin)
        .padding(.vertical, AppTheme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var strictnessPicker: some View {
        Picker("Match", selection: $model.strictness) {
            ForEach(DuplicateStrictness.allCases) { strictness in
                Text(strictness.title).tag(strictness)
            }
        }
        .pickerStyle(.segmented)
        .disabled(model.isBusy)
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
                    Text(scan.total > 0
                         ? "Scanning \(scan.processed) of \(scan.total)"
                         : "Preparing scan…")
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

    private var reviewedText: String {
        let total = model.groups.count
        let done = model.reviewedCount
        if model.strictness == .series {
            return String(localized: "Reviewed \(done) of \(total) series", comment: "Duplicates header, Series")
        }
        return total == 1
            ? String(localized: "Reviewed \(done) of 1 group", comment: "Duplicates header, one group")
            : String(localized: "Reviewed \(done) of \(total) groups", comment: "Duplicates header")
    }

    private var freeText: String {
        let bytes = model.totalFreeBytes
        guard model.strictness != .series, bytes > 0 else { return "" }
        let size = DuplicatesScreen.byteFormatter.string(fromByteCount: Int64(bytes))
        return " · " + String(localized: "~\(size) to free", comment: "Duplicates header: space freed by keeping one per group")
    }

    @ViewBuilder
    private var statusLine: some View {
        if let scanState = model.scanState {
            let scanned = String(localized: "Scanned \(scanState.scannedAt.formatted(.relative(presentation: .named)))",
                                 comment: "Duplicates header: when the last scan ran")
            let pending = model.pendingCount == 0
                ? String(localized: "Library up to date", comment: "Duplicates header: nothing new to scan")
                : String(localized: "\(model.pendingCount) photos not scanned yet", comment: "Duplicates header: photos a rescan would cover")
            Text("\(scanned) · \(pending)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private var rescanButton: some View {
        Button {
            model.startScan()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.body.weight(.medium))
                .frame(width: 32, height: 32)
                .background(Color(.secondarySystemFill), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .disabled(model.isBusy)
        .accessibilityLabel("Rescan")
    }
}

// MARK: - Decision card

/// One group as a decision: keeper big on the left with "Keep" and its
/// reasons, the copies beside it each with what it lacks, and the three
/// one-tap actions. A series has no keeper — its frames sit in one grid in
/// capture order (FS-06.06 §6).
private struct DuplicateDecisionCard: View {
    let group: DuplicateGroup
    let model: DuplicatesModel
    let metrics: DuplicateCardMetrics

    var body: some View {
        let keeper = model.keeper(of: group)
        VStack(alignment: .leading, spacing: 0) {
            header(keeper: keeper)
                .padding(.bottom, AppTheme.Spacing.sm)

            if let keeper {
                HStack(alignment: .top, spacing: DuplicateCardMetrics.keeperGap) {
                    keeperColumn(keeper)
                    copiesGrid(group.members.filter { $0.assetId != keeper.assetId }, columns: metrics.copyColumns)
                }
            } else {
                copiesGrid(group.members, columns: metrics.copyColumns + 2)
            }

            notices
            actions(keeper: keeper)
                .padding(.top, AppTheme.Spacing.sm)
        }
        .padding(DuplicateCardMetrics.cardPadding)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle.app(AppTheme.Radius.lg))
        .onAppear { model.loadTraits(for: group) }
    }

    private func header(keeper: HashedPhoto?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.count == 1 ? "1 photo" : "\(group.count) photos")
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

    private var subtitle: String {
        var parts: [String] = []
        if let date = DuplicatesScreen.dateText(group) { parts.append(date) }
        if model.strictness == .exact {
            parts.append(String(localized: "Identical files", comment: "Duplicates card, Exact: the copies are the same file"))
        } else if let span = DuplicateReview.spanText(group.members) {
            parts.append(span)
        }
        return parts.joined(separator: " · ")
    }

    private func keeperColumn(_ keeper: HashedPhoto) -> some View {
        let reasons = model.reasons(for: group)
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            tile(keeper, side: metrics.keeper, radius: AppTheme.Radius.md, isKeeper: true)
            Text(facts(keeper))
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
            if !reasons.isEmpty {
                HStack(spacing: AppTheme.Spacing.xs) {
                    ForEach(reasons, id: \.self) { reason in
                        Text(reason.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, AppTheme.Spacing.sm)
                            .frame(height: 20)
                            .background(Color(.secondarySystemFill), in: Capsule())
                    }
                }
            }
        }
        .frame(width: metrics.keeper, alignment: .leading)
    }

    private func facts(_ member: HashedPhoto) -> String {
        var parts: [String] = []
        if let dimensions = DuplicateReview.dimensions(member) { parts.append(dimensions) }
        if let size = member.fileSize {
            parts.append(DuplicatesScreen.byteFormatter.string(fromByteCount: Int64(size)))
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func copiesGrid(_ members: [HashedPhoto], columns: Int) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(metrics.tile), spacing: DuplicateCardMetrics.copyGap, alignment: .topLeading), count: columns),
            alignment: .leading,
            spacing: AppTheme.Spacing.sm
        ) {
            ForEach(members) { member in
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    tile(member, side: metrics.tile, radius: AppTheme.Radius.sm, isKeeper: false)
                    Text(caption(member))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .frame(width: metrics.tile, alignment: .leading)
                }
            }
        }
    }

    /// Under a copy: what it lacks next to the keeper. Under a series frame:
    /// seconds after the first frame.
    private func caption(_ member: HashedPhoto) -> String {
        if model.strictness == .series {
            let first = group.members.compactMap(\.creationDate).min()
            guard let first, let date = member.creationDate else { return "—" }
            return "+\(date - first) s"
        }
        return model.difference(of: member, in: group)
    }

    private func tile(_ member: HashedPhoto, side: CGFloat, radius: CGFloat, isKeeper: Bool) -> some View {
        let isMarked = model.isMarked(member.assetId)
        let isLast = model.isLastUnmarked(member.assetId, in: group)
        return DuplicateThumbnail(
            asset: model.assetsById[member.assetId],
            side: side,
            radius: radius,
            isMarked: isMarked,
            showsKeep: isKeeper && !isMarked
        )
        .onTapGesture {
            withAnimation(AppTheme.Motion.standard) {
                _ = model.toggleMark(member.assetId, in: group)
            }
        }
        .sensoryFeedback(.warning, trigger: model.blockedGroupId == group.id) { _, blocked in blocked }
        .contextMenu {
            Button {
                withAnimation(AppTheme.Motion.standard) { model.keepOnly(member.assetId, in: group) }
            } label: {
                Label("Keep Only This", systemImage: "checkmark.circle")
            }
            Button {
                withAnimation(AppTheme.Motion.standard) { _ = model.toggleMark(member.assetId, in: group) }
            } label: {
                Label(isMarked ? "Unmark" : "Mark for Deletion", systemImage: isMarked ? "trash.slash" : "trash")
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
        if !isKeeper { parts.append(caption(member)) }
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
        } else if model.blockedGroupId == group.id {
            Label("Keep at least one photo in this group.", systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, AppTheme.Spacing.sm)
                .transition(.opacity)
        }
    }

    private func actions(keeper: HashedPhoto?) -> some View {
        let marked = model.markedCount(in: group)
        let keptAll = model.isKeptAll(group)
        return HStack(spacing: AppTheme.Spacing.sm) {
            if marked > 0 {
                pill(String(localized: "Unmark", comment: "Duplicates card: clear this group's marks"), color: .primary) {
                    model.unmark(group)
                }
            } else if keeper != nil {
                let others = group.count - 1
                pill(others == 1
                     ? String(localized: "Mark the other one", comment: "Duplicates card: mark every photo but the kept one")
                     : String(localized: "Mark the other \(others)", comment: "Duplicates card: mark every photo but the kept one"),
                     color: .red) {
                    model.markOthers(in: group)
                }
                .accessibilityLabel(others == 1 ? "Mark the other photo for deletion" : "Mark the other \(others) photos for deletion")
            }
            pill(keptAll
                 ? String(localized: "Keeping all", comment: "Duplicates card: the group is kept whole; tap to undo")
                 : String(localized: "Keep all", comment: "Duplicates card: keep every photo of the group"),
                 color: .accentColor,
                 systemImage: keptAll ? "checkmark" : nil) {
                model.toggleKeepAll(group)
            }
            Spacer(minLength: 0)
            if model.canCompare(group) {
                pill(String(localized: "Compare", comment: "Duplicates card: open the group side by side"), color: .accentColor) {
                    model.compare(group)
                }
            }
        }
    }

    private func pill(_ title: String, color: Color, systemImage: String? = nil, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(AppTheme.Motion.standard) { action() }
        } label: {
            HStack(spacing: AppTheme.Spacing.xs) {
                if let systemImage { Image(systemName: systemImage).font(.footnote.weight(.bold)) }
                Text(title)
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
private struct DuplicateThumbnail: View {
    @Environment(PhotoLibraryService.self) private var photoLibrary

    let asset: PHAsset?
    let side: CGFloat
    let radius: CGFloat
    let isMarked: Bool
    let showsKeep: Bool
    var showsMarkBadge = true

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
                    Image(systemName: isMarked ? "trash.circle.fill" : "circle")
                        .symbolRenderingMode(isMarked ? .palette : .monochrome)
                        .foregroundStyle(.white, .red)
                        .font(.system(size: 22))
                        .shadow(color: .black.opacity(0.35), radius: 2)
                        .padding(side > 120 ? AppTheme.Spacing.sm : AppTheme.Spacing.xs)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if showsKeep {
                    Label("Keep", systemImage: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .labelStyle(KeepBadgeLabelStyle())
                        .padding(.horizontal, AppTheme.Spacing.sm)
                        .frame(height: 24)
                        .background(Color.black.opacity(0.55), in: Capsule())
                        .padding(AppTheme.Spacing.sm)
                }
            }
            .contentShape(Rectangle())
            .onAppear(perform: loadThumbnail)
            .onChange(of: side) { loadThumbnail() }
            .onDisappear(perform: cancelThumbnail)
    }

    private func loadThumbnail() {
        guard let asset, side > requestedSide + 1 || image == nil, requestId == nil else { return }
        requestedSide = side
        let pixels = side * ActiveDisplay.scale
        requestId = photoLibrary.requestThumbnail(
            for: asset,
            targetSize: CGSize(width: pixels, height: pixels),
            allowNetwork: false
        ) { result in
            if let result { image = result }
            requestId = nil
        }
    }

    private func cancelThumbnail() {
        if let requestId {
            photoLibrary.cancelThumbnailRequest(requestId)
        }
        requestId = nil
    }
}

private struct KeepBadgeLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            configuration.icon.font(.caption.weight(.bold))
            configuration.title
        }
    }
}
