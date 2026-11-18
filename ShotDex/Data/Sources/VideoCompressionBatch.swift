import Foundation
import Observation
#if os(iOS)
import UIKit
#endif

/// The side effects one compression run needs, so the batch can be tested
/// with fakes and the real one can be PhotoKit (`PhotoKitVideoCompressionWorker`).
protocol VideoCompressionWorking: Sendable {
    /// What the estimate knows about a video before anything is downloaded.
    func preflight(_ id: String) async -> VideoCompressionSource?
    /// Writes the video's original to `url`, downloading it if needed.
    func fetchOriginal(_ id: String, to url: URL, progress: @escaping @Sendable (Double) -> Void) async throws
    /// Re-encodes `source` into `output`.
    func encode(_ source: URL, to output: URL, settings: VideoCompressionEncoder.Settings,
                progress: @escaping @Sendable (Double) -> Void) async throws
    /// Adds `file` to the library as a copy of the video `id` (date, place,
    /// favourite, albums). Returns the new asset's identifier.
    func save(_ file: URL, copying id: String) async throws -> String
    /// Space a write may use right now, nil when it cannot be read.
    func freeBytes() -> Int64?
    /// Moves the given videos to Recently Deleted.
    func deleteOriginals(_ ids: [String]) async throws
}

/// FS-24 §4–§8: the queue behind Compress Videos on every device. One file
/// at a time on iPhone and iPad (the hardware encoder is shared, a second
/// stream only splits it), `maxConcurrent` on the Mac.
@MainActor
@Observable
final class VideoCompressionBatch {
    enum Phase: Equatable {
        case setup
        case running
        case finished
    }

    enum ItemState: Equatable {
        case waiting
        case downloading(Double)
        case encoding(Double)
        case saving
        /// Saved; bytes saved against the original.
        case done(savedBytes: Int64)
        /// Not worth keeping, or not attempted; nothing saved.
        case skipped(String)
        case failed(String)
        case stopped

        var isFinal: Bool {
            switch self {
            case .done, .skipped, .failed, .stopped: true
            case .waiting, .downloading, .encoding, .saving: false
            }
        }
    }

    struct Item: Identifiable, Equatable {
        let id: String
        var source: VideoCompressionSource?
        var state: ItemState = .waiting
        /// The compressed copy in the library, once saved (FS-24 §10).
        var copyID: String?
        /// The original's real size and the copy's, once saved.
        var originalBytes: Int64?
        var copyBytes: Int64?
        /// The original went to Recently Deleted (from the summary or Compare).
        var isOriginalDeleted = false
    }

    private(set) var items: [Item]
    var quality: VideoCompressionQuality = .high
    var size: VideoCompressionSize = .original
    private(set) var phase: Phase = .setup
    /// Photos in the selection that this screen leaves out (FS-24 §1.1).
    let leftOutPhotoCount: Int
    /// Set when the run stopped early for want of space.
    private(set) var stopReason: String?
    private(set) var hasDeletedOriginals = false
    /// File names by video id, filled by the screen that reads them
    /// (PhotoKit resources), for rows and Compare's title.
    var names: [String: String] = [:]

    func filename(of id: String) -> String {
        names[id] ?? String(localized: "Video", comment: "Compress Videos: row name when the file name is unknown")
    }
    private(set) var deleteError: String?

    private let worker: any VideoCompressionWorking
    private let maxConcurrent: Int
    private let workDirectory: URL
    private var runTask: Task<Void, Never>?

    init(
        videoIDs: [String],
        leftOutPhotoCount: Int = 0,
        worker: any VideoCompressionWorking,
        maxConcurrent: Int = 1,
        workDirectory: URL = URL.temporaryDirectory.appendingPathComponent("VideoCompression", isDirectory: true)
    ) {
        self.items = videoIDs.map { Item(id: $0) }
        self.leftOutPhotoCount = leftOutPhotoCount
        self.worker = worker
        self.maxConcurrent = max(1, maxConcurrent)
        self.workDirectory = workDirectory
    }

    // MARK: Setup

    /// Reads what the estimate needs for every video.
    func load() async {
        for index in items.indices {
            let id = items[index].id
            items[index].source = await worker.preflight(id)
        }
    }

    /// Total bytes of the originals that could be read.
    var sourceBytes: Int64 {
        items.compactMap(\.source?.byteCount).reduce(0, +)
    }

    /// Estimated total after compression with the current choices.
    var estimatedBytes: Int64 {
        items.compactMap(\.source).reduce(0) {
            $0 + VideoCompressionRules.estimatedBytes(for: $1, quality: quality, size: size)
        }
    }

    // MARK: Run

    var completedCount: Int { items.filter { $0.state.isFinal }.count }

    /// 0…1 over the whole batch; a running file counts by its own progress.
    var overallProgress: Double {
        guard !items.isEmpty else { return 0 }
        let sum = items.reduce(0.0) { total, item in
            switch item.state {
            case .waiting: total
            case .downloading(let value): total + value * 0.2
            case .encoding(let value): total + 0.2 + value * 0.75
            case .saving: total + 0.95
            case .done, .skipped, .failed, .stopped: total + 1
            }
        }
        return min(sum / Double(items.count), 1)
    }

    var savedBytes: Int64 {
        items.reduce(0) {
            if case .done(let saved) = $1.state { return $0 + saved }
            return $0
        }
    }

    var doneCount: Int {
        items.filter { if case .done = $0.state { true } else { false } }.count
    }

    func start() {
        guard phase == .setup, !items.isEmpty else { return }
        phase = .running
        stopReason = nil
        let settings = VideoCompressionEncoder.Settings(quality: quality, size: size)
        runTask = Task { [weak self] in
            guard let self else { return }
            let activity = self.beginKeepingAlive()
            await self.run(settings: settings)
            Self.endKeepingAlive(activity)
            self.phase = .finished
        }
    }

    /// Stops the current file and every file not started; finished files stay.
    func stop() {
        runTask?.cancel()
    }

    /// Waits for the run to end (tests, and the Mac's window close).
    func waitUntilFinished() async {
        await runTask?.value
    }

    private func run(settings: VideoCompressionEncoder.Settings) async {
        // Its own folder per run: a second batch (another Mac window) must
        // not clear this one's files from under it.
        let runDirectory = workDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: runDirectory) }
        // Files are started in order, at most `maxConcurrent` at a time.
        var next = 0
        await withTaskGroup(of: Void.self) { group in
            var running = 0
            while true {
                while running < maxConcurrent, next < items.count, !Task.isCancelled, stopReason == nil {
                    let index = next
                    next += 1
                    running += 1
                    group.addTask { @MainActor in await self.process(index: index, settings: settings, in: runDirectory) }
                }
                guard running > 0, await group.next() != nil else { break }
                running -= 1
            }
        }
        for index in items.indices where !items[index].state.isFinal {
            items[index].state = .stopped
        }
    }

    private func process(index: Int, settings: VideoCompressionEncoder.Settings, in workDirectory: URL) async {
        let id = items[index].id
        guard !Task.isCancelled else { items[index].state = .stopped; return }
        let sourceBytes = items[index].source?.byteCount ?? 0
        if let free = worker.freeBytes(), !VideoCompressionRules.hasRoom(freeBytes: free, sourceBytes: sourceBytes) {
            stopReason = String(localized: "Not enough free space to compress more videos.", comment: "Compress Videos: the batch stopped because storage is low")
            items[index].state = .stopped
            return
        }
        let token = UUID().uuidString
        let original = workDirectory.appendingPathComponent("\(token)-original.mov")
        let output = workDirectory.appendingPathComponent("\(token).mp4")
        defer {
            try? FileManager.default.removeItem(at: original)
            try? FileManager.default.removeItem(at: output)
        }
        do {
            items[index].state = .downloading(0)
            try await worker.fetchOriginal(id, to: original) { value in
                Task { @MainActor in self.update(index, .downloading(value)) }
            }
            try Task.checkCancellation()
            let originalBytes = (try? FileManager.default.attributesOfItem(atPath: original.path)[.size] as? Int64) ?? sourceBytes
            // Again with the real size: PhotoKit may not have known it, and
            // the download itself used space. The original's copy is already
            // on disk, so what is left to find is the output and Photos' copy.
            if let free = worker.freeBytes(),
               !VideoCompressionRules.hasRoom(freeBytes: free + originalBytes, sourceBytes: originalBytes) {
                stopReason = String(localized: "Not enough free space to compress more videos.", comment: "Compress Videos: the batch stopped because storage is low")
                items[index].state = .stopped
                return
            }
            items[index].state = .encoding(0)
            try await worker.encode(original, to: output, settings: settings) { value in
                Task { @MainActor in self.update(index, .encoding(value)) }
            }
            try Task.checkCancellation()
            guard let outputBytes = try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int64,
                  outputBytes > 0 else {
                throw VideoCompressionEncoder.EncodeError(errorDescription: String(localized: "The compressed copy is empty.", comment: "Compress Videos: the encoder wrote nothing"))
            }
            if VideoCompressionRules.shouldSkip(outputBytes: outputBytes, sourceBytes: originalBytes) {
                items[index].state = .skipped(String(localized: "Already compact", comment: "Compress Videos: the compressed copy was not smaller, so it was not saved"))
                return
            }
            items[index].state = .saving
            let copyID = try await worker.save(output, copying: id)
            items[index].copyID = copyID
            items[index].originalBytes = originalBytes
            items[index].copyBytes = outputBytes
            items[index].state = .done(savedBytes: originalBytes - outputBytes)
        } catch is CancellationError {
            items[index].state = .stopped
        } catch {
            items[index].state = Task.isCancelled ? .stopped : .failed(error.localizedDescription)
        }
    }

    /// Progress callbacks arrive after hops; a late one must not overwrite a
    /// later phase.
    private func update(_ index: Int, _ state: ItemState) {
        switch (items[index].state, state) {
        case (.downloading, .downloading), (.encoding, .encoding):
            items[index].state = state
        default:
            break
        }
    }

    // MARK: Finish

    /// The files Compare Videos walks through (FS-24 §10): saved, with
    /// their original still in the library.
    var comparePairs: [VideoCompareRules.Pair] {
        items.compactMap { item in
            guard case .done = item.state, !item.isOriginalDeleted, let copyID = item.copyID,
                  let originalBytes = item.originalBytes, let copyBytes = item.copyBytes else { return nil }
            return VideoCompareRules.Pair(id: item.id, copyID: copyID,
                                          originalBytes: originalBytes, copyBytes: copyBytes)
        }
    }

    /// Moves the originals of every saved copy to Recently Deleted.
    func deleteOriginals() async {
        let ids = items.compactMap { item -> String? in
            if case .done = item.state, !item.isOriginalDeleted { return item.id }
            return nil
        }
        guard !ids.isEmpty else { return }
        await delete(ids)
    }

    /// Moves one original to Recently Deleted — Compare's Delete Original.
    /// False when PhotoKit refused (the user said Don't Allow, or it failed).
    @discardableResult
    func deleteOriginal(of id: String) async -> Bool {
        guard let item = items.first(where: { $0.id == id }), case .done = item.state,
              !item.isOriginalDeleted else { return false }
        return await delete([id])
    }

    @discardableResult
    private func delete(_ ids: [String]) async -> Bool {
        do {
            try await worker.deleteOriginals(ids)
            for index in items.indices where ids.contains(items[index].id) {
                items[index].isOriginalDeleted = true
            }
            hasDeletedOriginals = !items.contains { item in
                if case .done = item.state { return !item.isOriginalDeleted }
                return false
            }
            deleteError = nil
            return true
        } catch {
            deleteError = error.localizedDescription
            return false
        }
    }

    // MARK: Keeping the run alive

    /// A batch runs for minutes: the screen must not lock under it, and a
    /// switch to another app gets the system's grace period to finish the
    /// current file (HandBrake's `preventSleep`, for a phone).
    private func beginKeepingAlive() -> Any? {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = true
        // When the grace period runs out, stop cleanly — the current file's
        // temporary copies are removed and the files already saved stay —
        // rather than be killed with gigabytes left in tmp.
        return UIApplication.shared.beginBackgroundTask(withName: "video-compress") { [weak self] in
            Task { @MainActor in self?.stop() }
        }
        #else
        return ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Compressing videos"
        )
        #endif
    }

    private static func endKeepingAlive(_ token: Any?) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = false
        if let id = token as? UIBackgroundTaskIdentifier, id != .invalid {
            UIApplication.shared.endBackgroundTask(id)
        }
        #else
        if let activity = token as? NSObjectProtocol {
            ProcessInfo.processInfo.endActivity(activity)
        }
        #endif
    }
}
