import Photos
import SwiftUI

/// Navigation value for the Duplicates utility, pushed from the Collections tab.
struct DuplicatesDestination: Hashable {}

/// Duplicates utility (tier A, DESIGN.md §2): a list of duplicate groups, each
/// a card of square thumbnails, read from the cache of the last scan. Tapping a
/// thumbnail marks it for deletion, or Compare shows the group side by side
/// with a trash toggle per pane; the user decides per group what stays.
/// Nothing is pre-marked, and nothing rescans unless the user asks.
struct DuplicatesScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(PhotoLibraryService.self) private var photoLibrary

    @State private var model: DuplicatesModel?

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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                Picker("Match", selection: $model.strictness) {
                    Text("Exact").tag(DuplicateStrictness.exact)
                    Text("Similar").tag(DuplicateStrictness.similar)
                }
                .pickerStyle(.segmented)
                .disabled(model.isBusy)

                if case .scanning(let progress) = model.phase {
                    scanBanner(progress, model: model)
                } else if model.scanState != nil {
                    statusRow(model)
                }

                if !model.groups.isEmpty {
                    Text(summary(model))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                if model.groups.isEmpty {
                    emptyState(model)
                        .frame(maxWidth: .infinity)
                        .padding(.top, AppTheme.Spacing.xxl)
                } else {
                    ForEach(model.groups) { group in
                        DuplicateGroupCard(group: group, model: model)
                    }
                }

                if #unavailable(iOS 26.0) {
                    Color.clear.frame(height: 90)
                }
            }
            .padding(.horizontal, AppTheme.Size.screenMargin)
            .padding(.top, AppTheme.Spacing.sm)
        }
        .task {
            guard photoLibrary.authorizationState.canReadLibrary else { return }
            model.loadIfNeeded()
        }
        .task(id: photoLibrary.assetChangeToken) {
            guard photoLibrary.authorizationState.canReadLibrary else { return }
            model.refreshPendingCount()
        }
        .safeAreaInset(edge: .bottom) {
            if model.markedCount > 0 {
                deleteBar(model)
            }
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
                    Button {
                        Task { await model.mergeAll() }
                    } label: {
                        Label("Merge All Groups", systemImage: "arrow.trianglehead.merge")
                    }
                    .disabled(model.isBusy || model.groups.isEmpty)
                    Button {
                        model.clearAllMarks()
                    } label: {
                        Label("Clear Selection", systemImage: "xmark.circle")
                    }
                    .disabled(model.markedCount == 0)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .tint(.primary)
                .accessibilityLabel("More")
            }
        }
        .fullScreenCover(item: $model.comparePresentation) { presentation in
            CompareScreen(
                photos: presentation.photos,
                deletionMarks: $model.markedForDeletion,
                onDeleteMarked: { await model.deleteMarked() }
            )
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
        .animation(AppTheme.Motion.standard, value: model.markedCount > 0)
    }

    private func summary(_ model: DuplicatesModel) -> String {
        let groups = model.groups.count
        let photos = model.duplicatePhotoCount
        let reclaimable = model.groups.reduce(0) { $0 + $1.reclaimableBytes }
        var text = "\(groups) \(groups == 1 ? "group" : "groups") · \(photos) photos"
        if reclaimable > 0 {
            text += " · ~\(Self.byteFormatter.string(fromByteCount: Int64(reclaimable))) if one is kept per group"
        }
        return text
    }

    /// Last-scan line with the rescan button. The count of photos a rescan
    /// would cover tells the user whether it is worth pressing.
    private func statusRow(_ model: DuplicatesModel) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                if let scanState = model.scanState {
                    Text("Last scan \(scanState.scannedAt.formatted(.relative(presentation: .named)))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text(model.pendingCount == 0
                     ? "Library up to date."
                     : "\(model.pendingCount) \(model.pendingCount == 1 ? "photo" : "photos") not scanned yet.")
                    .font(.footnote)
                    .foregroundStyle(model.pendingCount == 0 ? .secondary : .primary)
                    .monospacedDigit()
            }
            Spacer()
            Button {
                model.startScan()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.isBusy)
        }
    }

    private func scanBanner(_ progress: DuplicateScanProgress, model: DuplicatesModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Text(progress.total > 0
                     ? "Scanning \(progress.processed) of \(progress.total)"
                     : "Preparing scan…")
                    .font(.subheadline)
                    .monospacedDigit()
                Spacer()
                Button("Cancel", role: .destructive) {
                    model.cancelScan()
                }
                .font(.subheadline)
            }
            ProgressView(value: progress.fraction)
        }
        .padding(AppTheme.Spacing.md)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle.app(AppTheme.Radius.lg))
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
                "No Indexed Photos",
                systemImage: "photo.on.rectangle.angled",
                description: Text("Index your library from the Library tab, then come back to find duplicates.")
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
                "No Duplicates",
                systemImage: "checkmark.circle",
                description: Text("No \(model.strictness == .exact ? "exact" : "similar") duplicates among \(model.coverage.hashedPhotos) photos.")
            )
        }
    }

    private func deleteBar(_ model: DuplicatesModel) -> some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Button(role: .destructive) {
                Task { await model.deleteMarked() }
            } label: {
                Label(
                    model.markedCount == 1 ? "Delete 1 Photo" : "Delete \(model.markedCount) Photos",
                    systemImage: "trash"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: AppTheme.Size.primaryActionHeight)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(model.isBusy)

            Text(deleteFootnote(model))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, AppTheme.Size.screenMargin)
        .padding(.top, AppTheme.Spacing.md)
        .padding(.bottom, bottomChromePadding)
        .background(Color(.systemGroupedBackground))
    }

    private func deleteFootnote(_ model: DuplicatesModel) -> String {
        let bytes = model.markedBytes
        let moved = "Photos move to Recently Deleted."
        guard bytes > 0 else { return moved }
        return "~\(Self.byteFormatter.string(fromByteCount: Int64(bytes))) · \(moved)"
    }

    /// Pre-26 the floating tab chrome still overlays a pushed screen.
    private var bottomChromePadding: CGFloat {
        if #available(iOS 26.0, *) { AppTheme.Spacing.sm } else { 90 }
    }

    static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}

/// One duplicate group: header with the member count and a Compare button
/// (2–4 members), then a grid of square thumbnails the user marks to delete.
private struct DuplicateGroupCard: View {
    let group: DuplicateGroup
    let model: DuplicatesModel

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: AppTheme.Spacing.sm)]

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                Text("\(group.count) Photos")
                    .font(.headline)
                Spacer()
                if model.canCompare(group) {
                    Button {
                        model.compare(group)
                    } label: {
                        Label("Compare", systemImage: "rectangle.split.2x1")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: AppTheme.Spacing.md) {
                ForEach(group.members) { member in
                    DuplicateTile(
                        member: member,
                        asset: model.assetsById[member.assetId],
                        isMarked: model.isMarked(member.assetId),
                        isLargest: member.assetId == group.members[0].assetId && group.reclaimableBytes > 0
                    )
                    .onTapGesture { model.toggleMark(member.assetId) }
                    .contextMenu {
                        Button {
                            model.keepOnly(member.assetId, in: group)
                        } label: {
                            Label("Keep Only This", systemImage: "checkmark.circle")
                        }
                        Button {
                            model.toggleMark(member.assetId)
                        } label: {
                            Label(
                                model.isMarked(member.assetId) ? "Unmark" : "Mark for Deletion",
                                systemImage: model.isMarked(member.assetId) ? "trash.slash" : "trash"
                            )
                        }
                        if model.canCompare(group) {
                            Button {
                                model.compare(group)
                            } label: {
                                Label("Compare", systemImage: "rectangle.split.2x1")
                            }
                        }
                    }
                }
            }

            if model.markedCount(in: group) > 0 {
                Button("Clear Selection") {
                    model.clearMarks(in: group)
                }
                .font(.footnote)
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle.app(AppTheme.Radius.lg))
    }
}

/// Square thumbnail with a trash badge when marked (destructive red — the
/// grid's accent check means "selected", this means "will be deleted"), and a
/// caption of dimensions, file size and date.
private struct DuplicateTile: View {
    @Environment(PhotoLibraryService.self) private var photoLibrary

    let member: HashedPhoto
    let asset: PHAsset?
    let isMarked: Bool
    let isLargest: Bool

    @State private var image: UIImage?
    @State private var requestId: PHImageRequestID?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Color(.tertiarySystemBackground)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .opacity(isMarked ? 0.82 : 1)
                    } else {
                        Image(systemName: "photo")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                    }
                }
                .clipShape(RoundedRectangle.app(AppTheme.Radius.sm))
                .overlay {
                    if isMarked {
                        RoundedRectangle.app(AppTheme.Radius.sm)
                            .strokeBorder(.red, lineWidth: 3)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: isMarked ? "trash.circle.fill" : "circle")
                        .symbolRenderingMode(isMarked ? .palette : .monochrome)
                        .foregroundStyle(.white, .red)
                        .font(.title3)
                        .shadow(color: .black.opacity(0.35), radius: 2)
                        .padding(AppTheme.Spacing.xs + 2)
                }

            Text(dimensions)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onAppear(perform: loadThumbnail)
        .onDisappear(perform: cancelThumbnail)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(dimensions), \(detail)\(isMarked ? ", marked for deletion" : "")")
        .accessibilityAddTraits(isMarked ? .isSelected : [])
    }

    private var dimensions: String {
        if let width = member.width, let height = member.height {
            return "\(width) × \(height)" + (isLargest ? " · Largest" : "")
        }
        return isLargest ? "Largest" : "—"
    }

    private var detail: String {
        var parts: [String] = []
        if let size = member.fileSize {
            parts.append(DuplicatesScreen.byteFormatter.string(fromByteCount: Int64(size)))
        }
        if let created = member.creationDate {
            parts.append(Date(timeIntervalSince1970: TimeInterval(created)).formatted(date: .abbreviated, time: .omitted))
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func loadThumbnail() {
        guard image == nil, requestId == nil, let asset else { return }
        let side = 120 * ActiveDisplay.scale
        requestId = photoLibrary.requestThumbnail(
            for: asset,
            targetSize: CGSize(width: side, height: side),
            allowNetwork: false
        ) { result in
            if let result { image = result }
        }
    }

    private func cancelThumbnail() {
        if let requestId {
            photoLibrary.cancelThumbnailRequest(requestId)
        }
        requestId = nil
    }
}
