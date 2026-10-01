import Foundation
import os

/// The preparation of one batch's originals (FS-02.06 §5): ask each photo
/// with the network off, check the room for the rest, download them to disk —
/// at most four at a time, with indexing paused — and, when some fail, wait
/// for the user's Continue, Retry or Cancel. Nothing is written or deleted
/// by anyone before `run()` returns.
///
/// Observable, so the screen that started it — the Share modal, the Resize
/// and Collage processing modals — draws `state` as it moves.
@MainActor
@Observable
final class OriginalPreparation {
    /// What the batch ended as.
    enum Outcome: Equatable {
        /// Go on. `files` are the originals that were downloaded, by photo
        /// id; a photo with no entry was already on the device. `skipped`
        /// are the ones the user chose to go on without.
        case ready(files: [String: URL], skipped: Set<String>)
        /// Nothing is to happen: Cancel, or not enough room.
        case cancelled
    }

    enum Choice: Equatable { case continueWithout, retry, cancel }

    private(set) var state: OriginalPreparationState
    /// Past the 350 ms threshold (§3), or asking the user something.
    var isShown: Bool { state.isShown(elapsed: hasPassedShowDelay ? OriginalPreparationState.showDelay : .zero) }
    /// 15 s at 0% (§3). The downloads go on.
    private(set) var isStalled = false

    let items: [OriginalItem]
    /// Where the downloaded originals are, `ShotDexOriginals-<uuid>`. The
    /// caller removes it with `removeFiles()` once it is done with them.
    let folder: URL

    nonisolated static let prefix = "ShotDexOriginals-"

    private let fetcher: any OriginalFetching
    private let gate: IndexInteractionGate?
    private let availableBytes: @Sendable () -> Int64?
    private let limit: Int
    private let showDelay: Duration
    private let stallWindow: Duration

    private var hasPassedShowDelay = false
    @ObservationIgnored private var files: [String: URL] = [:]
    @ObservationIgnored private var choice: CheckedContinuation<Choice, Never>?
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var timers: [Task<Void, Never>] = []
    @ObservationIgnored private var isCancelled = false
    @ObservationIgnored private var zeroSince: ContinuousClock.Instant?
    @ObservationIgnored private var hasRun = false

    init(
        items: [OriginalItem],
        batchCount: Int? = nil,
        fetcher: any OriginalFetching,
        gate: IndexInteractionGate? = nil,
        availableBytes: @escaping @Sendable () -> Int64? = { DiskSpace.availableBytes() },
        limit: Int = 4,
        in directory: URL = FileManager.default.temporaryDirectory,
        showDelay: Duration = OriginalPreparationState.showDelay,
        stallWindow: Duration = OriginalPreparationState.stallWindow
    ) {
        self.items = items
        self.state = OriginalPreparationState(batchCount: batchCount ?? items.count)
        self.fetcher = fetcher
        self.gate = gate
        self.availableBytes = availableBytes
        self.limit = max(1, limit)
        self.folder = directory.appendingPathComponent(Self.prefix + UUID().uuidString, isDirectory: true)
        self.showDelay = showDelay
        self.stallWindow = stallWindow
    }

    /// Runs the whole preparation once. Returns when every original is here,
    /// the user chose, or the batch was cancelled.
    func run() async -> Outcome {
        guard !hasRun else { return .cancelled }
        hasRun = true
        gate?.beginInteraction()
        defer {
            gate?.endInteraction()
            for timer in timers { timer.cancel() }
            timers = []
        }
        let delay = showDelay
        timers.append(Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.hasPassedShowDelay = true
        })

        // 1. With the network off: what is already here passes straight on.
        let inCloud = await probeAll()
        guard !isCancelled else { return finishCancelled() }
        guard !inCloud.isEmpty else {
            state.phase = .ready
            return .ready(files: [:], skipped: [])
        }
        state.downloads = inCloud.map {
            .init(id: $0.id, filename: $0.filename, byteCount: $0.byteCount)
        }

        // 2. The room for the whole batch, before the first byte.
        for index in state.downloads.indices where state.downloads[index].byteCount == nil {
            if let item = inCloud.first(where: { $0.id == state.downloads[index].id }) {
                state.downloads[index].byteCount = await fetcher.byteCount(of: item)
            }
        }
        guard !isCancelled else { return finishCancelled() }
        let needed = state.totalBytes ?? 0
        let free = availableBytes()
        if !OriginalPreparationState.fits(needed: needed, free: free) {
            state.phase = .notEnoughSpace(needed: needed, free: free ?? 0)
            _ = await waitForChoice()
            return finishCancelled()
        }

        // 3. Download; 4. on failures, ask.
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        startStallWatch()
        while true {
            state.phase = .downloading
            zeroSince = state.isAtZero ? .now : nil
            await downloadPending(inCloud)
            if isCancelled { return finishCancelled() }
            if case .notEnoughSpace = state.phase {
                _ = await waitForChoice()
                return finishCancelled()
            }
            let failed = Set(state.downloads.filter(\.hasFailed).map(\.id))
            guard !failed.isEmpty else {
                state.phase = .ready
                return .ready(files: files, skipped: [])
            }
            state.phase = .failed
            switch await waitForChoice() {
            case .continueWithout:
                state.phase = .ready
                return .ready(files: files, skipped: failed)
            case .retry:
                for index in state.downloads.indices where state.downloads[index].hasFailed {
                    state.downloads[index].hasFailed = false
                    state.downloads[index].fraction = 0
                }
            case .cancel:
                return finishCancelled()
            }
        }
    }

    /// The user's answer to a failure (Continue, Retry, Cancel) or to the
    /// room message (OK, as `.cancel`).
    func choose(_ choice: Choice) {
        if choice == .cancel { isCancelled = true }
        let continuation = self.choice
        self.choice = nil
        continuation?.resume(returning: choice)
    }

    /// Stops every download at once (§5: ≤ 1 s) and removes what came down.
    func cancel() {
        isCancelled = true
        downloadTask?.cancel()
        choose(.cancel)
    }

    /// Removes the downloaded originals.
    func removeFiles() {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: Steps

    private func probeAll() async -> [OriginalItem] {
        let fetcher = self.fetcher
        let limit = self.limit
        let items = self.items
        let found = await withTaskGroup(of: (Int, OriginalAvailability).self) { group in
            var next = 0
            var results: [(Int, OriginalAvailability)] = []
            while next < min(limit, items.count) {
                let index = next, item = items[index]
                group.addTask { (index, await fetcher.probe(item)) }
                next += 1
            }
            while let result = await group.next() {
                results.append(result)
                if next < items.count {
                    let index = next, item = items[index]
                    group.addTask { (index, await fetcher.probe(item)) }
                    next += 1
                }
            }
            return results
        }
        // `.unknown` is downloaded too: a batch must not go on with a
        // preview it could not rule out.
        return found.sorted { $0.0 < $1.0 }.filter { $0.1 != .local }.map { items[$0.0] }
    }

    private func downloadPending(_ inCloud: [OriginalItem]) async {
        let pending = inCloud.filter { item in
            state.downloads.contains { $0.id == item.id && !$0.isFinished && !$0.hasFailed }
        }
        let fetcher = self.fetcher
        let folder = self.folder
        let limit = self.limit
        let task = Task { @MainActor [weak self] in
            await withTaskGroup(of: Void.self) { group in
                var next = 0
                func add(_ item: OriginalItem) {
                    let url = folder.appendingPathComponent(UUID().uuidString + "-" + item.filename)
                    group.addTask {
                        let result: Result<Void, Error>
                        do {
                            try await fetcher.fetch(item, to: url) { fraction in
                                Task { @MainActor in self?.report(item.id, fraction: fraction) }
                            }
                            result = .success(())
                        } catch {
                            result = .failure(error)
                        }
                        await self?.finish(item.id, url: url, result: result)
                    }
                }
                while next < min(limit, pending.count) { add(pending[next]); next += 1 }
                while await group.next() != nil {
                    if Task.isCancelled { group.cancelAll(); continue }
                    if next < pending.count { add(pending[next]); next += 1 }
                }
            }
        }
        downloadTask = task
        await task.value
        downloadTask = nil
    }

    private func report(_ id: String, fraction: Double) {
        guard let index = state.downloads.firstIndex(where: { $0.id == id }),
              !state.downloads[index].isFinished, !state.downloads[index].hasFailed else { return }
        state.downloads[index].fraction = fraction
        gate?.touch()
        if fraction > 0 {
            zeroSince = nil
            if isStalled { isStalled = false }
        } else if zeroSince == nil, state.isAtZero {
            zeroSince = .now
        }
    }

    private func finish(_ id: String, url: URL, result: Result<Void, Error>) {
        guard let index = state.downloads.firstIndex(where: { $0.id == id }) else { return }
        gate?.touch()
        switch result {
        case .success:
            state.downloads[index].isFinished = true
            state.downloads[index].fraction = 1
            files[id] = url
            zeroSince = nil
            isStalled = false
        case .failure(let error):
            try? FileManager.default.removeItem(at: url)
            if isCancelled || error is CancellationError { return }
            if (error as? OriginalFetchError) == .outOfSpace {
                // A space problem, never an iCloud one (§5).
                let remaining = state.downloads.filter { !$0.isFinished }.compactMap(\.byteCount).reduce(0, +)
                state.phase = .notEnoughSpace(needed: remaining, free: availableBytes() ?? 0)
                downloadTask?.cancel()
                return
            }
            state.downloads[index].hasFailed = true
        }
    }

    private func startStallWatch() {
        let window = stallWindow
        timers.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                let atZero = self.zeroSince.map { ContinuousClock.now - $0 } ?? .zero
                let stalled = self.zeroSince != nil && self.state.isAtZero && atZero >= window
                if stalled != self.isStalled { self.isStalled = stalled }
            }
        })
    }

    private func waitForChoice() async -> Choice {
        if isCancelled { return .cancel }
        return await withCheckedContinuation { continuation in
            choice = continuation
        }
    }

    private func finishCancelled() -> Outcome {
        isCancelled = true
        state.phase = .cancelled
        removeFiles()
        return .cancelled
    }
}
