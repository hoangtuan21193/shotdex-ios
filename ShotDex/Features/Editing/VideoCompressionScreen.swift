import Photos
import SwiftUI

/// What opens Compress Videos: the selected videos, in pick order, and how
/// many photos the selection held that this tool leaves out (FS-24 §1.1).
struct VideoCompressionRequest: Identifiable {
    let id = UUID()
    let videoIDs: [String]
    let leftOutPhotoCount: Int

    /// From a mixed selection: `imageIDs` are the photos among `selection`.
    init?(selection: [String], imageIDs: [String]) {
        let images = Set(imageIDs)
        let videos = selection.filter { !images.contains($0) }
        guard !videos.isEmpty else { return nil }
        videoIDs = videos
        leftOutPhotoCount = imageIDs.count
    }
}

/// FS-24 Compress Videos — a tier-D tool like Resize (DESIGN.md §2): dark
/// stage, drawn choice chips, one accent button. Choices → running list →
/// summary, on one screen, so the user never loses the list of their files.
struct VideoCompressionScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.appAccent) private var accent

    let request: VideoCompressionRequest

    @State private var batch: VideoCompressionBatch?
    @State private var assets: [String: PHAsset] = [:]
    @State private var width: CGFloat = 0
    @State private var isStopConfirmationPresented = false
    /// Compare Videos open on this file (FS-24 §10).
    @State private var comparing: CompareStart?

    struct CompareStart: Identifiable {
        let id: String
    }

    private var isWide: Bool { width >= WideLayout.minimumWidth }

    var body: some View {
        NavigationStack {
            ZStack {
                EditorTheme.background.ignoresSafeArea()
                if let batch {
                    content(batch)
                        .measureWidth(into: $width)
                } else {
                    ProgressView(VideoCompressionCopy.preparing)
                        .tint(.white)
                        .foregroundStyle(.white)
                }
            }
            .navigationTitle(VideoCompressionCopy.title(request.videoIDs.count))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if batch?.phase == .setup || batch == nil {
                        Button("Cancel") { dismiss() }
                    }
                }
                // Wide, once the job runs: Stop and Done sit on the
                // toolbar's trailing edge (FS-21.02b §2) and the screen
                // below is the job itself.
                ToolbarItem(placement: .confirmationAction) {
                    if isWide, let batch {
                        switch batch.phase {
                        case .setup:
                            EmptyView()
                        case .running:
                            Button(VideoCompressionCopy.stop) { isStopConfirmationPresented = true }
                                .fontWeight(.regular)
                                .tint(.white)
                        case .finished:
                            Button(VideoCompressionCopy.done) { dismiss() }
                                .fontWeight(.semibold)
                                .tint(accent)
                        }
                    }
                }
            }
            .toolbarBackground(EditorTheme.panelSolid, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(batch?.phase == .running)
        .task {
            guard batch == nil else { return }
            // Only what PhotoKit says is a video: the screens split the
            // selection by what their model has loaded, which can miss a photo.
            let fetched = PhotoLibraryService.fetchAssets(ids: request.videoIDs).filter { $0.mediaType == .video }
            assets = Dictionary(uniqueKeysWithValues: fetched.map { ($0.localIdentifier, $0) })
            let worker = PhotoKitVideoCompressionWorker(
                fetcher: dependencies.originalFetcher,
                delete: { [editing = dependencies.photoEditing] ids in
                    try await editing.deleteAssets(ids: ids)
                }
            )
            let newBatch = VideoCompressionBatch(
                videoIDs: request.videoIDs.filter { assets[$0] != nil },
                leftOutPhotoCount: request.leftOutPhotoCount,
                worker: worker
            )
            newBatch.names = assets.mapValues { Self.filename($0) }
            batch = newBatch
            await newBatch.load()
        }
        .fullScreenCover(item: $comparing) { start in
            if let batch {
                VideoCompareScreen(batch: batch, startID: start.id)
            }
        }
        .confirmationDialog(
            String(localized: "Stop compressing?", comment: "Compress Videos: confirm Stop"),
            isPresented: $isStopConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(VideoCompressionCopy.stop, role: .destructive) { batch?.stop() }
            Button(String(localized: "Keep Going", comment: "Compress Videos: dismiss the Stop confirmation"), role: .cancel) {}
        } message: {
            Text(String(localized: "Videos already compressed stay saved.", comment: "Compress Videos: Stop confirmation message"))
        }
    }

    // MARK: Layout

    @ViewBuilder
    private func content(_ batch: VideoCompressionBatch) -> some View {
        if isWide, batch.phase != .setup {
            // Wide, running or finished: the job owns the screen — one
            // centred column, progress (then the result) at its top, the
            // files under it. The setup inspector beside a 1000pt list left
            // the progress as a small bar in a corner and half the screen
            // empty (boards `IP_VideoCompressRun`, `DI_VideoCompressRun`).
            ScrollView {
                VStack(spacing: AppTheme.Spacing.sm) {
                    Group {
                        if batch.phase == .running {
                            runningHero(batch)
                        } else {
                            finishedHero(batch)
                        }
                    }
                    .padding(AppTheme.Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(EditorTheme.control, in: RoundedRectangle.app(AppTheme.Radius.lg))
                    .padding(.bottom, AppTheme.Spacing.md)
                    rows(batch)
                }
                .padding(.horizontal, AppTheme.Spacing.xl)
                .padding(.vertical, AppTheme.Spacing.xl)
                .frame(maxWidth: Self.jobColumnWidth)
                .frame(maxWidth: .infinity)
            }
        } else if isWide {
            // Wide (iPad, the Duo's inner display): the list of videos fills
            // the leading side and the choices are an inspector beside it,
            // the button pinned under them — the same frame as Resize
            // (board `DI_Compress`).
            HStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.sm) {
                        header(batch)
                        rows(batch)
                    }
                    .padding(AppTheme.Spacing.xl)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 0) {
                    ScrollView {
                        inspector(batch)
                            .padding(AppTheme.Spacing.lg)
                    }
                    primaryButton(batch)
                        .padding(AppTheme.Spacing.lg)
                }
                .frame(width: Self.inspectorWidth)
                .background(EditorTheme.panelSolid)
                .overlay(alignment: .leading) {
                    Rectangle().fill(EditorTheme.hairline).frame(width: 1)
                }
            }
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.lg) {
                        header(batch)
                        if batch.phase == .setup {
                            strip(batch)
                            inspector(batch)
                        } else {
                            inspector(batch)
                            rows(batch)
                        }
                    }
                    .padding(AppTheme.Spacing.lg)
                    .frame(maxWidth: Self.maximumFormWidth)
                    .frame(maxWidth: .infinity)
                }
                primaryButton(batch)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.vertical, AppTheme.Spacing.md)
                    .frame(maxWidth: Self.maximumFormWidth)
                    .background(EditorTheme.background)
            }
        }
    }

    private static let inspectorWidth: CGFloat = 340
    /// The running and finished column on a wide screen: rows stay readable
    /// as one unit and the hero sits where the eye lands.
    private static let jobColumnWidth: CGFloat = 760 + 2 * AppTheme.Spacing.xl
    private static let maximumFormWidth: CGFloat = 700

    @ViewBuilder
    private func header(_ batch: VideoCompressionBatch) -> some View {
        if batch.leftOutPhotoCount > 0, batch.phase == .setup {
            Label(VideoCompressionCopy.leftOut(batch.leftOutPhotoCount), systemImage: "photo")
                .font(.footnote)
                .foregroundStyle(EditorTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The choices while setting up; the batch's progress or summary after.
    @ViewBuilder
    private func inspector(_ batch: VideoCompressionBatch) -> some View {
        switch batch.phase {
        case .setup: choices(batch)
        case .running: progress(batch)
        case .finished: summary(batch)
        }
    }

    // MARK: Setup

    private func choices(_ batch: VideoCompressionBatch) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                CompressionGroupLabel(text: VideoCompressionCopy.quality)
                ForEach(VideoCompressionQuality.allCases) { quality in
                    Button {
                        batch.quality = quality
                    } label: {
                        HStack(spacing: AppTheme.Spacing.md) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(VideoCompressionCopy.name(quality))
                                    .font(.subheadline.weight(batch.quality == quality ? .semibold : .medium))
                                Text(VideoCompressionCopy.detail(quality))
                                    .font(.caption)
                                    .foregroundStyle(EditorTheme.secondaryText)
                            }
                            Spacer(minLength: 0)
                            if batch.quality == quality {
                                Image(systemName: "checkmark")
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(CompressionChoiceStyle(selected: batch.quality == quality))
                    .accessibilityAddTraits(batch.quality == quality ? .isSelected : [])
                }
            }
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                CompressionGroupLabel(text: VideoCompressionCopy.size)
                HStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(VideoCompressionSize.allCases) { size in
                        Button {
                            batch.size = size
                        } label: {
                            Text(VideoCompressionCopy.name(size))
                                .font(.subheadline.weight(batch.size == size ? .semibold : .medium))
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(CompressionChoiceStyle(selected: batch.size == size))
                        .accessibilityAddTraits(batch.size == size ? .isSelected : [])
                    }
                }
            }
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(VideoCompressionCopy.estimate(before: batch.sourceBytes, after: batch.estimatedBytes))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(EditorTheme.secondaryText)
                Text(VideoCompressionCopy.note)
                    .font(.caption)
                    .foregroundStyle(EditorTheme.dimText)
            }
        }
    }

    /// The phone's horizontal strip of the videos about to be compressed.
    private func strip(_ batch: VideoCompressionBatch) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.sm) {
                ForEach(batch.items) { item in
                    thumbnail(item, side: 96)
                }
            }
        }
    }

    // MARK: Running and finished

    private func progress(_ batch: VideoCompressionBatch) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            ProgressView(value: batch.overallProgress)
                .tint(accent)
            Text(VideoCompressionCopy.progress(batch.completedCount, of: batch.items.count))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(EditorTheme.secondaryText)
            Text(VideoCompressionCopy.note)
                .font(.caption)
                .foregroundStyle(EditorTheme.dimText)
        }
    }

    // MARK: Wide job heroes

    private func runningHero(_ batch: VideoCompressionBatch) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(VideoCompressionCopy.running(batch.completedCount, of: batch.items.count))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: AppTheme.Spacing.md)
                Text(VideoCompressionCopy.percent(batch.overallProgress))
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(EditorTheme.secondaryText)
            }
            ProgressView(value: batch.overallProgress)
                .tint(accent)
                .scaleEffect(x: 1, y: 1.5, anchor: .center)
            let detail = [
                batch.savedBytes > 0 ? VideoCompressionCopy.savedSoFar(batch.savedBytes) : nil,
                batch.secondsLeft().map(VideoCompressionCopy.timeLeft),
            ].compactMap { $0 }
            if !detail.isEmpty {
                Text(detail.joined(separator: " · "))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(EditorTheme.secondaryText)
            }
            Text(VideoCompressionCopy.note)
                .font(.caption)
                .foregroundStyle(EditorTheme.dimText)
        }
        .accessibilityElement(children: .combine)
    }

    private func finishedHero(_ batch: VideoCompressionBatch) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(VideoCompressionCopy.savedHeadline(batch.savedBytes))
                    .font(.largeTitle.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                Text(VideoCompressionCopy.doneDetail(done: batch.doneCount, skipped: batch.skippedCount))
                    .font(.footnote)
                    .foregroundStyle(EditorTheme.secondaryText)
            }
            if let reason = batch.stopReason {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            HStack(spacing: AppTheme.Spacing.md) {
                if let first = batch.comparePairs.first {
                    Button {
                        comparing = CompareStart(id: first.id)
                    } label: {
                        Label(VideoCompressionCopy.compareBeforeAfter, systemImage: "rectangle.split.2x1")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(CompressionChoiceStyle(selected: false))
                }
                if batch.hasDeletedOriginals {
                    Label(VideoCompressionCopy.originalsDeleted, systemImage: "trash")
                        .font(.footnote)
                        .foregroundStyle(EditorTheme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                } else if batch.doneCount > 0 {
                    Button(role: .destructive) {
                        Task { await batch.deleteOriginals() }
                    } label: {
                        Label(VideoCompressionCopy.deleteOriginals, systemImage: "trash")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(CompressionChoiceStyle(selected: false))
                }
            }
            if let error = batch.deleteError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if !batch.comparePairs.isEmpty {
                Text(VideoCompressionCopy.summaryHint)
                    .font(.caption)
                    .foregroundStyle(EditorTheme.dimText)
            }
        }
    }

    private func summary(_ batch: VideoCompressionBatch) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text(VideoCompressionCopy.summary(done: batch.doneCount, saved: batch.savedBytes))
                .font(.headline)
                .foregroundStyle(.white)
            if let reason = batch.stopReason {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if let first = batch.comparePairs.first {
                Button {
                    comparing = CompareStart(id: first.id)
                } label: {
                    Label(VideoCompressionCopy.compareBeforeAfter, systemImage: "rectangle.split.2x1")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(CompressionChoiceStyle(selected: false))
            }
            if batch.hasDeletedOriginals {
                Label(VideoCompressionCopy.originalsDeleted, systemImage: "trash")
                    .font(.footnote)
                    .foregroundStyle(EditorTheme.secondaryText)
            } else if batch.doneCount > 0 {
                Button(role: .destructive) {
                    Task { await batch.deleteOriginals() }
                } label: {
                    // Red inside the label: the chip style colours its
                    // content grey, and a delete must read as one.
                    Label(VideoCompressionCopy.deleteOriginals, systemImage: "trash")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(CompressionChoiceStyle(selected: false))
            }
            if let error = batch.deleteError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if !batch.comparePairs.isEmpty {
                Text(VideoCompressionCopy.summaryHint)
                    .font(.caption)
                    .foregroundStyle(EditorTheme.dimText)
            }
        }
    }

    private func rows(_ batch: VideoCompressionBatch) -> some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            ForEach(batch.items) { item in
                let pair = batch.comparePairs.first { $0.id == item.id }
                Button {
                    if let pair { comparing = CompareStart(id: pair.id) }
                } label: {
                HStack(spacing: AppTheme.Spacing.md) {
                    thumbnail(item, side: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Self.filename(assets[item.id]))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(pair.map(VideoCompressionCopy.result) ?? Self.detail(item))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Self.isProblem(item.state) ? .orange : EditorTheme.secondaryText)
                            .lineLimit(2)
                        if let fraction = Self.fraction(item.state) {
                            ProgressView(value: fraction).tint(accent)
                        }
                    }
                    Spacer(minLength: 0)
                    Self.badge(item.state)
                    if pair != nil {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(EditorTheme.dimText)
                    }
                }
                .padding(AppTheme.Spacing.sm)
                .background(EditorTheme.control, in: RoundedRectangle.app(AppTheme.Radius.md))
                .contentShape(RoundedRectangle.app(AppTheme.Radius.md))
                }
                .buttonStyle(.plain)
                .allowsHitTesting(pair != nil)
                .accessibilityElement(children: .combine)
                .accessibilityHint(pair == nil ? "" : VideoCompressionCopy.compareBeforeAfter)
            }
        }
    }

    private func thumbnail(_ item: VideoCompressionBatch.Item, side: CGFloat) -> some View {
        CullThumbnail(asset: assets[item.id], photoLibrary: dependencies.photoLibrary, side: side)
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle.app(AppTheme.Radius.sm))
            .overlay(alignment: .bottomTrailing) {
                if let asset = assets[item.id] {
                    Text(Duration.seconds(asset.duration).formatted(.time(pattern: .minuteSecond)))
                        .font(.caption2.monospacedDigit().weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(4)
                }
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func primaryButton(_ batch: VideoCompressionBatch) -> some View {
        switch batch.phase {
        case .setup:
            let isDisabled = batch.items.allSatisfy { $0.source == nil }
            Button {
                batch.start()
            } label: {
                Label(VideoCompressionCopy.compress, systemImage: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isDisabled ? EditorTheme.dimText : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppTheme.Size.primaryActionHeight)
                    .background(isDisabled ? EditorTheme.control : accent, in: RoundedRectangle.app(AppTheme.Radius.md))
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
        case .running:
            Button {
                isStopConfirmationPresented = true
            } label: {
                Text(VideoCompressionCopy.stop)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppTheme.Size.primaryActionHeight)
                    .background(EditorTheme.control, in: RoundedRectangle.app(AppTheme.Radius.md))
            }
            .buttonStyle(.plain)
        case .finished:
            Button {
                dismiss()
            } label: {
                Text(VideoCompressionCopy.done)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppTheme.Size.primaryActionHeight)
                    .background(accent, in: RoundedRectangle.app(AppTheme.Radius.md))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Row text

    private static func filename(_ asset: PHAsset?) -> String {
        guard let asset else { return String(localized: "Video", comment: "Compress Videos: row name when the file name is unknown") }
        let resources = PHAssetResource.assetResources(for: asset)
        return resources.first { $0.type == .video || $0.type == .fullSizeVideo }?.originalFilename
            ?? resources.first?.originalFilename
            ?? String(localized: "Video", comment: "Compress Videos: row name when the file name is unknown")
    }

    private static func detail(_ item: VideoCompressionBatch.Item) -> String {
        if case .waiting = item.state, let source = item.source {
            return VideoCompressionCopy.bytes(source.byteCount)
        }
        return VideoCompressionCopy.state(item.state)
    }

    private static func fraction(_ state: VideoCompressionBatch.ItemState) -> Double? {
        switch state {
        case .downloading(let value), .encoding(let value): value
        default: nil
        }
    }

    /// Only a failure is a problem; "Already compact" is an answer.
    private static func isProblem(_ state: VideoCompressionBatch.ItemState) -> Bool {
        switch state {
        case .failed: true
        default: false
        }
    }

    @ViewBuilder
    private static func badge(_ state: VideoCompressionBatch.ItemState) -> some View {
        switch state {
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        case .skipped:
            Image(systemName: "minus.circle.fill").foregroundStyle(EditorTheme.secondaryText)
        case .saving:
            ProgressView().controlSize(.small).tint(.white)
        case .waiting, .stopped, .encoding, .downloading:
            EmptyView()
        }
    }
}
