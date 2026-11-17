import AppKit
import Photos
import SwiftUI

/// Image › Compress Videos… (board `MAC_VideoCompress`, FS-24): the same
/// batch as on iOS — HEVC at constant quality, HDR kept, copies back into
/// Photos — as a page over the library like Resize: the list of videos on
/// the left, the options inspector of 300 on the right. Two files at once:
/// the Mac's encoder has the headroom HandBrake uses its workers for.
struct MacVideoCompressPage: View {
    @Bindable var batch: VideoCompressionBatch
    let close: () -> Void
    @State private var thumbnails: [String: NSImage] = [:]
    @State private var names: [String: String]
    @State private var asksStop = false

    init(batch: VideoCompressionBatch, names: [String: String] = [:], close: @escaping () -> Void) {
        self.batch = batch
        self.close = close
        _names = State(initialValue: names)
    }

    static func makeBatch(ids: [String], photoLibrary: PhotoLibraryService) -> VideoCompressionBatch {
        let worker = PhotoKitVideoCompressionWorker(
            fetcher: PhotoKitOriginalFetcher(),
            delete: { ids in
                try await photoLibrary.deleteAssetsCheckingServer(PhotoLibraryService.fetchAssets(ids: ids))
            }
        )
        return VideoCompressionBatch(videoIDs: ids, worker: worker, maxConcurrent: 2)
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(batch.items) { item in
                        row(item)
                    }
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Rectangle().fill(MacTheme.Editor.hairline).frame(width: 1)
            inspector
                .frame(width: 300)
                .background(MacTheme.Editor.inspector)
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .tint(MacTheme.Editor.label)
        .navigationTitle(VideoCompressionCopy.title(batch.items.count))
        .navigationSubtitle(VideoCompressionCopy.bytes(batch.sourceBytes))
        .toolbar { toolbar }
        .onExitCommand { if batch.phase != .running { close() } }
        .task {
            if batch.items.allSatisfy({ $0.source == nil }) { await batch.load() }
            await loadThumbnails()
        }
        // Any way out of the page (window closed, sidebar jump) ends the run:
        // a batch nobody can see or stop must not keep encoding.
        .onDisappear { if batch.phase == .running { batch.stop() } }
        .confirmationDialog(
            String(localized: "Stop compressing?", comment: "Compress Videos: confirm Stop"),
            isPresented: $asksStop
        ) {
            Button(VideoCompressionCopy.stop, role: .destructive) { batch.stop() }
            Button(String(localized: "Keep Going", comment: "Compress Videos: dismiss the Stop confirmation"), role: .cancel) {}
        } message: {
            Text(String(localized: "Videos already compressed stay saved.", comment: "Compress Videos: Stop confirmation message"))
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: close) {
                Label(String(localized: "Back", comment: "Mac toolbar"), systemImage: "chevron.left")
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(batch.phase == .running)
            .accessibilityIdentifier("videoCompress.back")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            switch batch.phase {
            case .setup:
                Button(String(localized: "Cancel", comment: "Mac Compress Videos toolbar: leave"), action: close)
                Button(VideoCompressionCopy.compress) { batch.start() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(MacPushButtonStyle(isDefault: true, isToolbarCommand: true))
                    .disabled(batch.items.allSatisfy { $0.source == nil })
                    .accessibilityIdentifier("videoCompress.go")
            case .running:
                Button(VideoCompressionCopy.stop) { asksStop = true }
                    .accessibilityIdentifier("videoCompress.stop")
            case .finished:
                Button(VideoCompressionCopy.done, action: close)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(MacPushButtonStyle(isDefault: true, isToolbarCommand: true))
            }
        }
    }

    // MARK: Inspector

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch batch.phase {
            case .setup:
                group(VideoCompressionCopy.quality) {
                    Picker(VideoCompressionCopy.quality, selection: $batch.quality) {
                        ForEach(VideoCompressionQuality.allCases) { quality in
                            VStack(alignment: .leading) {
                                Text(VideoCompressionCopy.name(quality))
                                Text(VideoCompressionCopy.detail(quality))
                                    .font(.system(size: 11))
                                    .foregroundStyle(MacTheme.Editor.secondaryText)
                            }
                            .tag(quality)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
                group(VideoCompressionCopy.size) {
                    Picker(VideoCompressionCopy.size, selection: $batch.size) {
                        ForEach(VideoCompressionSize.allCases) { size in
                            Text(VideoCompressionCopy.name(size)).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                Text(VideoCompressionCopy.estimate(before: batch.sourceBytes, after: batch.estimatedBytes))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(MacTheme.Editor.label)
            case .running:
                group(String(localized: "Progress", comment: "Mac Compress Videos inspector: section")) {
                    ProgressView(value: batch.overallProgress)
                    Text(VideoCompressionCopy.progress(batch.completedCount, of: batch.items.count))
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(MacTheme.Editor.secondaryText)
                }
            case .finished:
                group(String(localized: "Finished", comment: "Mac Compress Videos inspector: section")) {
                    Text(VideoCompressionCopy.summary(done: batch.doneCount, saved: batch.savedBytes))
                        .font(.system(size: 13, weight: .semibold))
                    if let reason = batch.stopReason {
                        Text(reason).font(.system(size: 12)).foregroundStyle(.orange)
                    }
                    if batch.hasDeletedOriginals {
                        Text(VideoCompressionCopy.originalsDeleted)
                            .font(.system(size: 12))
                            .foregroundStyle(MacTheme.Editor.secondaryText)
                    } else if batch.doneCount > 0 {
                        Button(VideoCompressionCopy.deleteOriginals, role: .destructive) {
                            Task { await batch.deleteOriginals() }
                        }
                    }
                    if let error = batch.deleteError {
                        Text(error).font(.system(size: 12)).foregroundStyle(.orange)
                    }
                }
            }
            Text(VideoCompressionCopy.note)
                .font(.system(size: 11))
                .foregroundStyle(MacTheme.Editor.secondaryText)
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(MacTheme.Editor.secondaryText)
            content()
        }
    }

    // MARK: Rows

    private func row(_ item: VideoCompressionBatch.Item) -> some View {
        HStack(spacing: 12) {
            Group {
                if let image = thumbnails[item.id] {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    // Until PhotoKit answers (or for a video it cannot draw):
                    // a film glyph on a lifted ground, not an invisible box.
                    ZStack {
                        Color.white.opacity(0.08)
                        Image(systemName: "film")
                            .font(.system(size: 14))
                            .foregroundStyle(MacTheme.Editor.secondaryText)
                    }
                }
            }
            .frame(width: 64, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 3) {
                Text(names[item.id] ?? String(localized: "Video", comment: "Compress Videos: row name when the file name is unknown"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MacTheme.Editor.label)
                    .lineLimit(1)
                Text(detail(item))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(MacTheme.Editor.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            switch item.state {
            case .downloading(let value), .encoding(let value):
                ProgressView(value: value).frame(width: 120)
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            case .skipped:
                Image(systemName: "minus.circle.fill").foregroundStyle(MacTheme.Editor.secondaryText)
            case .saving:
                ProgressView().controlSize(.small)
            case .waiting, .stopped:
                EmptyView()
            }
        }
        .padding(8)
        .background(MacTheme.Editor.control, in: RoundedRectangle(cornerRadius: 8))
    }

    private func detail(_ item: VideoCompressionBatch.Item) -> String {
        if case .waiting = item.state, let source = item.source {
            return VideoCompressionCopy.bytes(source.byteCount)
        }
        return VideoCompressionCopy.state(item.state)
    }

    private func loadThumbnails() async {
        let assets = PhotoLibraryService.fetchAssets(ids: batch.items.map(\.id))
        for asset in assets {
            let resources = PHAssetResource.assetResources(for: asset)
            names[asset.localIdentifier] = resources.first { $0.type == .video || $0.type == .fullSizeVideo }?.originalFilename
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true
            let id = asset.localIdentifier
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: 128, height: 80), contentMode: .aspectFill, options: options
            ) { image, _ in
                Task { @MainActor in if let image { thumbnails[id] = image } }
            }
        }
    }
}

#if DEBUG
extension MacVideoCompressPage {
    static let demoFiles: [(id: String, name: String, bytes: Int64, seconds: Double)] = [
        ("demo-vc:1", "IMG_4021.MOV", 1_200_000_000, 161),
        ("demo-vc:2", "MVI_0388.MP4", 3_400_000_000, 365),
        ("demo-vc:3", "IMG_4033.MOV", 612_000_000, 72),
        ("demo-vc:4", "MVI_0391.MP4", 2_100_000_000, 260),
        ("demo-vc:5", "IMG_4040.MOV", 248_000_000, 31),
    ]

    static var demoNames: [String: String] {
        Dictionary(uniqueKeysWithValues: demoFiles.map { ($0.id, $0.name) })
    }

    static func demoBatch() -> VideoCompressionBatch {
        VideoCompressionBatch(videoIDs: demoFiles.map(\.id), worker: DemoWorker(), maxConcurrent: 2)
    }

    /// Plays a batch for screenshots: sparse files stand in for the videos,
    /// so nothing is read from or written to Photos and no disk is used.
    struct DemoWorker: VideoCompressionWorking {
        func preflight(_ id: String) async -> VideoCompressionSource? {
            guard let file = MacVideoCompressPage.demoFiles.first(where: { $0.id == id }) else { return nil }
            return VideoCompressionSource(byteCount: file.bytes, duration: file.seconds,
                                          pixelSize: CGSize(width: 3840, height: 2160), frameRate: 30, hasAudio: true)
        }

        func fetchOriginal(_ id: String, to url: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
            let bytes = MacVideoCompressPage.demoFiles.first { $0.id == id }?.bytes ?? 1
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: UInt64(bytes))
            try handle.close()
            progress(1)
        }

        func encode(_ source: URL, to output: URL, settings: VideoCompressionEncoder.Settings,
                    progress: @escaping @Sendable (Double) -> Void) async throws {
            for step in 1...60 {
                try await Task.sleep(for: .milliseconds(500))
                progress(Double(step) / 60)
            }
            let bytes = (try FileManager.default.attributesOfItem(atPath: source.path)[.size] as? Int64) ?? 1
            FileManager.default.createFile(atPath: output.path, contents: nil)
            let handle = try FileHandle(forWritingTo: output)
            try handle.truncate(atOffset: UInt64(Double(bytes) * 0.42))
            try handle.close()
        }

        func save(_ file: URL, copying id: String) async throws -> String { "demo-saved:\(id)" }
        func freeBytes() -> Int64? { nil }
        func deleteOriginals(_ ids: [String]) async throws {}
    }
}
#endif
