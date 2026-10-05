import LinkPresentation
import os
import ShotDexKit
import UIKit

/// A share that opens the share sheet at once and prepares nothing until a
/// destination asks (FS-02.06 §9, FS-08.06 §5), the way Photos does: every
/// item is a lazy provider that only names its type. The first provider the
/// destination asks starts the batch — originals from iCloud, then the
/// metadata rewrite — in the centered modal; every provider waits for the
/// whole batch, so a destination receives nothing before the user has
/// answered a failure, and nothing at all after Cancel.
@MainActor
@Observable
final class LazyShareBatch: Identifiable {
    enum Stage: Equatable {
        /// The share sheet is open; no destination has asked yet.
        case waiting
        /// Downloading originals (`preparation` has the numbers).
        case preparing
        /// Writing the shared copies at the share's level: `done` of the
        /// share's items.
        case writing(done: Int)
        /// Some photos could not be written without what the level removes:
        /// they are named, and the rest are shared on the user's word.
        case leftOut(names: [String], sharing: Int)
        case finished
        case cancelled
    }

    let id = UUID()
    let sources: [ShareSource]
    let level: MetadataLevel
    let rawChoice: RAWChoice
    /// What this share stamps (FS-05.04); nil for none.
    let watermark: ShareWatermark?
    nonisolated let results = LazyShareResults()

    private(set) var stage: Stage = .waiting
    private(set) var preparation: OriginalPreparation?
    private var hasPassedShowDelay = false

    /// Runs when the batch is cancelled, to close the share sheet.
    @ObservationIgnored var onCancel: (() -> Void)?

    private let originals: [String: OriginalItem]
    private let fetcher: any OriginalFetching
    private let gate: IndexInteractionGate?
    private let availableBytes: @Sendable () -> Int64?
    private let reader: any ShareAssetReader
    private let directory: URL
    @ObservationIgnored private(set) var shareFolder: URL?
    @ObservationIgnored private var leftOutChoice: CheckedContinuation<Bool, Never>?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var isCancelled = false

    /// `originals`: the photo items by source id — what the preparation
    /// needs to know about each still. `reader` reads the photos already on
    /// the device, and the videos.
    init(
        sources: [ShareSource],
        originals: [String: OriginalItem],
        level: MetadataLevel,
        rawChoice: RAWChoice = .skip,
        fetcher: any OriginalFetching,
        gate: IndexInteractionGate? = nil,
        availableBytes: @escaping @Sendable () -> Int64? = { DiskSpace.availableBytes() },
        reader: any ShareAssetReader,
        directory: URL = FileManager.default.temporaryDirectory,
        watermark: ShareWatermark? = nil
    ) {
        self.watermark = watermark
        self.sources = sources
        self.originals = originals
        self.level = level
        self.rawChoice = rawChoice
        self.fetcher = fetcher
        self.gate = gate
        self.availableBytes = availableBytes
        self.reader = reader
        self.directory = directory
    }

    /// Whether the centered modal is up: past 350 ms of work (§3), or asking
    /// the user something.
    var isShown: Bool {
        switch stage {
        case .waiting, .finished, .cancelled: false
        case .leftOut: true
        case .preparing: preparation?.isShown ?? false
        case .writing: hasPassedShowDelay || (preparation?.isShown ?? false)
        }
    }

    // MARK: Providers

    /// One lazy provider per item, in order. The first carries the header.
    func providers(header: ShareHeader?) -> [LazyShareItemProvider] {
        let skip = Set(MetadataLevel.allCases.map(ShareLevelRow.activityType(for:)))
        let start: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in await self?.start() }
        }
        return sources.enumerated().map { index, source in
            LazyShareItemProvider(
                index: index,
                placeholder: Self.placeholder(for: source, level: level, rawChoice: rawChoice, in: directory, watermark: watermark),
                results: results,
                start: start,
                skippedTypes: skip,
                header: index == 0 ? header : nil
            )
        }
    }

    /// The file URL a provider shows the share sheet before anything is
    /// prepared: the name and type the item will have. Nothing is there yet.
    nonisolated static func placeholder(
        for source: ShareSource, level: MetadataLevel, rawChoice: RAWChoice, in directory: URL,
        watermark: ShareWatermark? = nil
    ) -> URL {
        var name = source.filename
        if let watermark, case .stamp = watermark.decision(for: source) {
            // A stamped copy is written again: its own type and name.
            let type = ShareWatermarkRenderer.outputType(sourceType: source.uniformType, level: level)
            name = ShareWatermarkRenderer.outputName(for: name, type: type)
        } else if source.kind == .raw, level != .all, rawChoice == .shareAsJPEG {
            name = (name as NSString).deletingPathExtension + ".jpg"
        } else if source.kind == .photo, let type = source.uniformType,
                  MetadataRewriter.convertsToJPEG(type, at: level) {
            name = (name as NSString).deletingPathExtension + ".jpg"
        }
        return directory.appendingPathComponent("ShotDexSharePlaceholder", isDirectory: true)
            .appendingPathComponent(name)
    }

    // MARK: Running

    /// Prepares the whole share, once: the originals, then the copies at the
    /// share's level, then hands every provider its file.
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        stage = .preparing
        Task { [weak self] in
            try? await Task.sleep(for: OriginalPreparationState.showDelay)
            self?.hasPassedShowDelay = true
        }

        let stills = sources.compactMap { originals[$0.id] }
        let preparation = OriginalPreparation(
            items: stills, batchCount: sources.count, fetcher: fetcher, gate: gate,
            availableBytes: availableBytes, in: directory
        )
        self.preparation = preparation
        let outcome = await preparation.run()
        guard case .ready(let downloaded, let skipped) = outcome, !isCancelled else {
            return finishCancelled()
        }

        // The rewrite runs after the download, in the same modal (FS-08.06 §5).
        stage = .writing(done: 0)
        guard let folder = try? ShareExportPipeline.makeFolder(in: directory) else { return finishCancelled() }
        shareFolder = folder
        var pipeline = ShareExportPipeline(
            reader: PreparedShareReader(files: downloaded, fallback: reader), folder: folder, level: level
        )
        pipeline.rawChoice = rawChoice
        pipeline.watermark = watermark
        var files: [Int: URL] = [:]
        var leftOut: [String] = []
        gate?.beginInteraction()
        for (index, source) in sources.enumerated() {
            if isCancelled { break }
            defer { stage = .writing(done: index + 1) }
            guard !skipped.contains(source.id) else { continue }
            do {
                files[index] = try await pipeline.export(source, index: index)
            } catch is ShareExportPipeline.Skipped {
                continue
            } catch {
                leftOut.append(source.filename)
            }
            gate?.touch()
        }
        gate?.endInteraction()
        preparation.removeFiles()
        guard !isCancelled else { return finishCancelled() }

        if !leftOut.isEmpty {
            stage = .leftOut(names: leftOut, sharing: files.count)
            let goesOn = await withCheckedContinuation { leftOutChoice = $0 }
            guard goesOn, !files.isEmpty, !isCancelled else { return finishCancelled() }
        }
        stage = .finished
        results.resolve(files)
    }

    /// Share the rest, after some were left out.
    func shareRest() {
        let continuation = leftOutChoice
        leftOutChoice = nil
        continuation?.resume(returning: true)
    }

    /// Stops the batch: downloads end, the destination gets nothing, the
    /// share sheet closes, the copies go.
    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        preparation?.cancel()
        let continuation = leftOutChoice
        leftOutChoice = nil
        continuation?.resume(returning: false)
        if !hasStarted { finishCancelled() }
    }

    /// Removes every copy this share made. Run when the share sheet closes.
    func removeFiles() {
        preparation?.removeFiles()
        if let shareFolder { try? FileManager.default.removeItem(at: shareFolder) }
    }

    private func finishCancelled() {
        isCancelled = true
        stage = .cancelled
        results.cancelAll()
        removeFiles()
        onCancel?()
        onCancel = nil
    }
}

/// The share sheet header's text and image for a lazy share.
struct ShareHeader {
    var title: String
    var note: String?
    /// A small image of the first photo, already on the device, written to
    /// a file: the header draws a file provider and not an in-memory image.
    var imageFile: URL?
}

/// Reads downloaded originals from disk, and everything else from `fallback`.
struct PreparedShareReader: ShareAssetReader {
    let files: [String: URL]
    let fallback: any ShareAssetReader

    func writePhoto(_ source: ShareSource, to url: URL) async throws {
        if let file = files[source.id] {
            try FileManager.default.copyItem(at: file, to: url)
        } else {
            try await fallback.writePhoto(source, to: url)
        }
    }

    func videoURL(for source: ShareSource) async throws -> URL {
        try await fallback.videoURL(for: source)
    }
}

/// What every provider of one share waits on, from UIKit's background queue.
final class LazyShareResults: @unchecked Sendable {
    private let condition = NSCondition()
    private var hasStarted = false
    private var files: [Int: URL]?
    private var isCancelled = false

    /// True for the first provider to ask, which starts the batch.
    func claimStart() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        guard !hasStarted else { return false }
        hasStarted = true
        return true
    }

    var hasBeenAsked: Bool {
        condition.lock()
        defer { condition.unlock() }
        return hasStarted
    }

    /// Blocks until the batch is prepared or cancelled. `nil` when cancelled.
    func wait() -> [Int: URL]? {
        condition.lock()
        defer { condition.unlock() }
        while files == nil && !isCancelled { condition.wait() }
        return isCancelled ? nil : files
    }

    func resolve(_ files: [Int: URL]) {
        condition.lock()
        self.files = files
        condition.broadcast()
        condition.unlock()
    }

    func cancelAll() {
        condition.lock()
        isCancelled = true
        condition.broadcast()
        condition.unlock()
    }
}

/// One item of a lazy share. UIKit asks for `item` on a background queue
/// once a destination is chosen; the provider waits there for the batch.
final class LazyShareItemProvider: UIActivityItemProvider, @unchecked Sendable {
    let index: Int
    private let results: LazyShareResults
    private let start: @Sendable () -> Void
    private let skippedTypes: Set<UIActivity.ActivityType>
    private let header: ShareHeader?
    private static let log = Logger(subsystem: "com.hoangtuan.shotdex", category: "share")

    init(
        index: Int, placeholder: URL, results: LazyShareResults, start: @escaping @Sendable () -> Void,
        skippedTypes: Set<UIActivity.ActivityType>, header: ShareHeader?
    ) {
        self.index = index
        self.results = results
        self.start = start
        self.skippedTypes = skippedTypes
        self.header = header
        super.init(placeholderItem: placeholder)
    }

    override var item: Any { item(for: activityType) }

    /// The item for the activity the user chose.
    func item(for activityType: UIActivity.ActivityType?) -> Any {
        // The app's own level rows reopen the sheet: nothing to prepare.
        if let type = activityType, skippedTypes.contains(type) { return placeholderItem ?? NSNull() }
        guard !Thread.isMainThread else {
            Self.log.error("share item asked for on the main thread; nothing to wait on there")
            return NSNull()
        }
        if results.claimStart() { start() }
        guard let file = results.wait()?[index] else { return NSNull() }
        return file
    }

    override func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        guard let header else { return nil }
        let metadata = LPLinkMetadata()
        metadata.title = header.title
        if let note = header.note {
            let shown = URL(fileURLWithPath: "/" + note)
            metadata.originalURL = shown
            metadata.url = shown
        }
        if let file = header.imageFile, let provider = NSItemProvider(contentsOf: file) {
            metadata.imageProvider = provider
            metadata.iconProvider = provider
        }
        return metadata
    }
}
