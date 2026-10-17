import Photos
import SwiftUI

/// The first thing Duplicates shows (FS-06.06 §7.2, board `PH_DuplicatesSummary`):
/// how much could go, the safe part to clean in one go, the part that needs
/// the user's eye, and the source frames that are not junk at all.
/// **Review…** is the screen's one accent-filled button (DESIGN.md §4).
struct DuplicatesSummaryView: View {
    let model: DuplicatesModel
    let isRegular: Bool
    /// Opens the list on a filter.
    let open: (DuplicatesFilter) -> Void
    /// Opens the Quick clean sheet.
    let reviewQuickClean: () -> Void

    var body: some View {
        let summary = model.summary
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            header(summary)
            if model.isScanning { DuplicatesScanProgress(model: model) }
            if isRegular {
                HStack(alignment: .top, spacing: AppTheme.Spacing.lg) {
                    if !summary.quickClean.isEmpty { quickCleanCard(summary) }
                    if !summary.chooseYourself.isEmpty { chooseCard(summary) }
                }
            } else {
                if !summary.quickClean.isEmpty { quickCleanCard(summary) }
                if !summary.chooseYourself.isEmpty { chooseCard(summary) }
            }
            if summary.hasSourceFrames { sourceFramesCard(summary) }
        }
        // AC-W2: one centered 720pt block on a wide screen.
        .frame(maxWidth: isRegular ? 720 : .infinity, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private func header(_ summary: DuplicatesSummary) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(String(localized: "~\(DuplicatesScreen.byteFormatter.string(fromByteCount: Int64(summary.freeBytes))) to free",
                        comment: "Duplicates summary title: space keeping one per group would free"))
                .font(.largeTitle.weight(.bold))
                .monospacedDigit()
            Text(subtitle(summary))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.top, AppTheme.Spacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func subtitle(_ summary: DuplicatesSummary) -> String {
        let groups = summary.groupCount == 1
            ? String(localized: "1 group", comment: "Duplicates summary subtitle")
            : String(localized: "\(summary.groupCount.formatted()) groups", comment: "Duplicates summary subtitle")
        guard let checked = model.scanState?.scannedAt else { return groups }
        return groups + " · " + String(localized: "checked \(checked.formatted(.relative(presentation: .named)))",
                                       comment: "Duplicates summary subtitle: when the library was last checked")
    }

    // MARK: Cards

    private func quickCleanCard(_ summary: DuplicatesSummary) -> some View {
        card {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                eyebrow(String(localized: "Quick clean", comment: "Duplicates summary: card title"))
                Text(summary.quickCleanGroups == 1
                     ? String(localized: "1 copy · \(bytes(summary.quickCleanBytes))", comment: "Duplicates summary: Quick clean groups and size")
                     : String(localized: "\(summary.quickCleanGroups.formatted()) copies · \(bytes(summary.quickCleanBytes))",
                              comment: "Duplicates summary: Quick clean groups and size"))
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                Text(String(localized: "Exact copies and smaller re-shares. Your favorites, edits and album photos are never included.",
                            comment: "Duplicates summary: what Quick clean removes and what it never touches"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                rows(summary.quickClean)
                Button(action: reviewQuickClean) {
                    Text(String(localized: "Review \(summary.quickCleanGroups.formatted())…",
                                comment: "Duplicates summary: opens the Quick clean preview; the screen's one accent button"))
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: AppTheme.Radius.md))
                .controlSize(.large)
                .disabled(model.isBusy)
            }
        }
    }

    private func chooseCard(_ summary: DuplicatesSummary) -> some View {
        card {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                        eyebrow(String(localized: "Choose yourself", comment: "Duplicates summary: card title"))
                        Text(summary.chooseGroups == 1
                             ? String(localized: "1 group · \(bytes(summary.chooseBytes))", comment: "Duplicates summary: groups that need a choice and their size")
                             : String(localized: "\(summary.chooseGroups.formatted()) groups · \(bytes(summary.chooseBytes))",
                                      comment: "Duplicates summary: groups that need a choice and their size"))
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                    }
                    Spacer(minLength: AppTheme.Spacing.sm)
                    Button(String(localized: "Start", comment: "Duplicates summary: open the groups that need a choice")) {
                        open(.all)
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                    .foregroundStyle(.primary)
                    .controlSize(.regular)
                    .frame(minHeight: 44)
                }
                rows(summary.chooseYourself)
            }
        }
    }

    private func sourceFramesCard(_ summary: DuplicatesSummary) -> some View {
        card {
            HStack {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    eyebrow(String(localized: "Source frames", comment: "Duplicates summary: brackets and focus stacks"))
                    Text(summary.sourceFramesText)
                        .font(.headline)
                        .monospacedDigit()
                }
                Spacer(minLength: AppTheme.Spacing.sm)
                Button(String(localized: "Show", comment: "Duplicates summary: list the brackets and focus stacks")) {
                    open(.sourceFrames)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
                .foregroundStyle(.primary)
                .frame(minHeight: 44)
            }
        }
    }

    private func rows(_ rows: [DuplicatesSummary.Row]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().padding(.leading, 44) }
                Button {
                    open(.kind(row.kind))
                } label: {
                    HStack(spacing: AppTheme.Spacing.md) {
                        DuplicatesKindThumbnail(asset: model.firstAsset(of: row.kind))
                        Text(row.kind.title)
                            .foregroundStyle(.primary)
                        Spacer(minLength: AppTheme.Spacing.sm)
                        Text("\(row.groups.formatted()) · \(bytes(row.bytes))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding(AppTheme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle.app(AppTheme.Radius.lg))
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func bytes(_ count: Int) -> String {
        DuplicatesScreen.byteFormatter.string(fromByteCount: Int64(count))
    }
}

/// A 32pt thumbnail of a kind's first keeper, or a Quick clean row's keeper.
private struct DuplicatesKindThumbnail: View {
    @Environment(PhotoLibraryService.self) private var photoLibrary
    let asset: PHAsset?
    @State private var image: UIImage?
    @State private var requestId: PHImageRequestID?

    var body: some View {
        RoundedRectangle.app(AppTheme.Radius.sm)
            .fill(Color(.tertiarySystemFill))
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle.app(AppTheme.Radius.sm))
            .accessibilityHidden(true)
            .onAppear {
                guard let asset, image == nil else { return }
                let pixels = 32 * ActiveDisplay.scale
                requestId = photoLibrary.requestThumbnail(
                    for: asset, targetSize: CGSize(width: pixels, height: pixels), allowNetwork: false
                ) { result in
                    if let result { image = result }
                }
            }
            .onDisappear {
                if let requestId { photoLibrary.cancelThumbnailRequest(requestId) }
                requestId = nil
            }
    }
}

/// "Scanning 1,200 of 38,000 · 40 found so far" with Cancel (A4) — the
/// summary's copy of the list band's progress row.
struct DuplicatesScanProgress: View {
    let model: DuplicatesModel

    var body: some View {
        if case .scanning(let scan) = model.phase {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                HStack {
                    Text(DuplicatesScanProgress.text(scan, found: model.groups.count))
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                    Spacer()
                    Button(String(localized: "Cancel", comment: "Duplicates: stop the scan in progress")) { model.cancelScan() }
                        .font(.footnote.weight(.semibold))
                        .frame(minHeight: 44)
                }
                ProgressView(value: scan.fraction)
            }
        }
    }

    static func text(_ scan: DuplicateScanProgress, found: Int) -> String {
        guard scan.total > 0 else {
            return String(localized: "Preparing scan…", comment: "Duplicates header: before the first batch")
        }
        let scanning = String(localized: "Scanning \(scan.processed.formatted()) of \(scan.total.formatted())",
                              comment: "Duplicates header: scan progress")
        guard found > 0 else { return scanning }
        return scanning + " · " + String(localized: "\(found.formatted()) found so far",
                                         comment: "Duplicates header: groups already found while scanning")
    }
}

/// The Quick clean preview (§7.2): each copies group with what it keeps and
/// what it would mark, a tick per row, and one button that marks — nothing
/// is deleted here.
struct DuplicatesQuickCleanSheet: View {
    let model: DuplicatesModel
    @Environment(\.dismiss) private var dismiss
    @State private var items: [QuickCleanItem]?
    @State private var unticked: Set<String> = []

    private var selectedCount: Int {
        (items ?? []).filter { !unticked.contains($0.groupId) }.reduce(0) { $0 + $1.removal.remove.count }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let items {
                    List(items) { item in
                        row(item)
                    }
                    .listStyle(.insetGrouped)
                    .safeAreaInset(edge: .bottom) { footer }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(String(localized: "Quick clean", comment: "Duplicates: Quick clean sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", comment: "Duplicates Quick clean: close without marking")) { dismiss() }
                }
            }
        }
        .task {
            items = await model.quickCleanItems()
        }
    }

    private func row(_ item: QuickCleanItem) -> some View {
        let isTicked = !unticked.contains(item.groupId)
        return Button {
            if isTicked { unticked.insert(item.groupId) } else { unticked.remove(item.groupId) }
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: isTicked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isTicked ? Color.accentColor : Color.secondary)
                DuplicatesKindThumbnail(asset: model.assetsById[item.keeperId])
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Remove \(item.removal.remove.count) · \(DuplicatesScreen.byteFormatter.string(fromByteCount: Int64(item.removal.removeBytes)))",
                                comment: "Duplicates Quick clean row: copies it would mark and their size"))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    if let kept = DuplicateProtection.keptLine(item.removal.kept, namingAlbums: true) {
                        Text(kept)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isTicked ? .isSelected : [])
    }

    private var footer: some View {
        Button {
            model.applyQuickClean(items ?? [], excluding: unticked)
            dismiss()
        } label: {
            Text(selectedCount == 1
                 ? String(localized: "Select 1 photo", comment: "Duplicates Quick clean: mark the ticked copies")
                 : String(localized: "Select \(selectedCount.formatted()) photos", comment: "Duplicates Quick clean: mark the ticked copies"))
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: AppTheme.Radius.md))
        .controlSize(.large)
        .disabled(selectedCount == 0)
        .padding(.horizontal, AppTheme.Size.screenMargin)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(.bar)
    }
}

/// ⋯ ▸ Ignored (§9): every group the user said is not duplicates, each
/// with Show again.
struct DuplicatesIgnoredSheet: View {
    let model: DuplicatesModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(model.ignoredGroups) { group in
                HStack(spacing: AppTheme.Spacing.md) {
                    DuplicatesKindThumbnail(asset: model.assetsById[group.id])
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.sourceSet?.title ?? String(localized: "\(group.kind.title) · \(group.count) photos",
                                                              comment: "Duplicates card title: kind and size of the group"))
                        if let date = DuplicatesScreen.dateText(group) {
                            Text(date).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: AppTheme.Spacing.sm)
                    Button(String(localized: "Show again", comment: "Duplicates Ignored: put the group back in the list")) {
                        model.undismiss(group)
                    }
                    .buttonStyle(.bordered)
                }
                .frame(minHeight: 44)
            }
            .overlay {
                if model.ignoredGroups.isEmpty {
                    ContentUnavailableView(String(localized: "Nothing Ignored", comment: "Duplicates Ignored: empty"),
                                           systemImage: "eye")
                }
            }
            .navigationTitle(String(localized: "Ignored", comment: "Duplicates: sheet of groups marked Not duplicates"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done", comment: "Close the Ignored sheet")) { dismiss() }
                }
            }
        }
    }
}
