import Foundation

/// A source that is told the batch's order before it starts, so it can
/// fetch ahead.
protocol ExportPrefetching: Sendable {
    func prepare(_ files: [(item: FileExportItem, file: FileExportSourceFile)]) async
    /// The run ended: nothing more downloads, nothing stays on disk.
    func cancelAll() async
}

/// iCloud originals for Export…, downloaded **rolling** (FS-03.07c §1 item 5,
/// the exception written into FS-02.06 §5): while one photo is written the
/// next ones download, never more than 20 photos or 2 GB downloaded and not
/// yet written. A photo whose download fails is that photo's problem — the
/// summary names it and Retry Failed fetches only it. Never a preview: the
/// bytes are the resource's, or nothing.
actor RollingOriginalPrefetcher: ExportAssetSource, ExportPrefetching {
    static let maximumItems = 20
    static let maximumBytes: Int64 = 2_000_000_000

    private let base: any ExportAssetSource
    /// Whether an asset's original has to come from iCloud — asked once,
    /// offline.
    private let isInCloud: @Sendable (FileExportItem) async -> Bool
    private let directory: URL
    private let maximumItems: Int
    private let maximumBytes: Int64

    private enum Slot {
        case downloading(Task<URL, Error>)
        case ready(URL)
        case failed(Error)
    }

    private var queue: [(item: FileExportItem, file: FileExportSourceFile)] = []
    private var cloud: [String: Bool] = [:]
    private var slots: [String: Slot] = [:]
    private var progress: [String: Double] = [:]
    private var listeners: [String: @Sendable (Double) -> Void] = [:]
    private var pump: Task<Void, Never>?
    /// Downloaded and not yet written, at its most — what the tests hold to
    /// the window.
    private(set) var peakAheadItems = 0
    private(set) var peakAheadBytes: Int64 = 0
    private(set) var downloads: [String] = []

    init(
        base: any ExportAssetSource,
        directory: URL,
        maximumItems: Int = RollingOriginalPrefetcher.maximumItems,
        maximumBytes: Int64 = RollingOriginalPrefetcher.maximumBytes,
        isInCloud: @escaping @Sendable (FileExportItem) async -> Bool
    ) {
        self.base = base
        self.directory = directory
        self.maximumItems = maximumItems
        self.maximumBytes = maximumBytes
        self.isInCloud = isInCloud
    }

    func prepare(_ files: [(item: FileExportItem, file: FileExportSourceFile)]) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        queue = files.filter { slots[$0.file.key] == nil || isFailed($0.file.key) }
        for entry in queue where isFailed(entry.file.key) { slots[entry.file.key] = nil }
        startPump()
    }

    nonisolated func copy(
        _ file: FileExportSourceFile,
        of item: FileExportItem,
        to url: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        if let local = try await downloaded(file, of: item, progress: progress) {
            defer { Task { await self.written(file) } }
            try Self.copyInBlocks(from: local, to: url)
        } else {
            try await base.copy(file, of: item, to: url, progress: progress)
        }
    }

    // MARK: Window

    private func isFailed(_ key: String) -> Bool {
        if case .failed = slots[key] { return true }
        return false
    }

    /// The local copy of an iCloud file, waiting for its download; nil for a
    /// file that is on this device.
    private func downloaded(_ file: FileExportSourceFile, of item: FileExportItem, progress: @escaping @Sendable (Double) -> Void) async throws -> URL? {
        listeners[file.key] = progress
        if let fraction = self.progress[file.key] { progress(fraction) }
        if slots[file.key] == nil {
            guard await cloudState(item) else { return nil }
            // Asked out of order (a retry, a remaining run): fetch now.
            if slots[file.key] == nil { startDownload(item, file) }
        }
        switch slots[file.key] {
        case .ready(let url)?: return url
        case .failed(let error)?: throw error
        case .downloading(let task)?: return try await task.value
        case nil: return nil
        }
    }

    private func cloudState(_ item: FileExportItem) async -> Bool {
        if let known = cloud[item.id] { return known }
        let answer = await isInCloud(item)
        cloud[item.id] = answer
        return answer
    }

    private var aheadItems: Int {
        Set(slots.compactMap { key, slot -> String? in
            if case .failed = slot { return nil }
            return key
        }).count
    }

    private var aheadBytes: Int64 {
        let keys = Set(slots.compactMap { key, slot -> String? in
            if case .failed = slot { return nil }
            return key
        })
        return queue.filter { keys.contains($0.file.key) }.reduce(0) { $0 + $1.file.byteCount }
    }

    private func startPump() {
        guard pump == nil else { return }
        pump = Task { await self.fill() }
    }

    /// Starts downloads in batch order until the window is full; called
    /// again whenever a file is written.
    private func fill() async {
        defer { pump = nil }
        for entry in queue where slots[entry.file.key] == nil {
            if Task.isCancelled { return }
            guard aheadItems < maximumItems, aheadBytes + entry.file.byteCount <= maximumBytes || aheadItems == 0 else { return }
            guard await cloudState(entry.item) else { continue }
            if slots[entry.file.key] == nil { startDownload(entry.item, entry.file) }
        }
    }

    private func startDownload(_ item: FileExportItem, _ file: FileExportSourceFile) {
        let url = directory.appendingPathComponent("\(UUID().uuidString)-\(file.filename)")
        let base = base
        downloads.append(file.key)
        let key = file.key
        let report: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { await self?.report(fraction, for: key) }
        }
        let task = Task<URL, Error> {
            try await base.copy(file, of: item, to: url, progress: report)
            return url
        }
        slots[file.key] = .downloading(task)
        peakAheadItems = max(peakAheadItems, aheadItems)
        peakAheadBytes = max(peakAheadBytes, aheadBytes)
        Task {
            let result = await task.result
            self.finished(file.key, result)
        }
    }

    private func report(_ fraction: Double, for key: String) {
        progress[key] = fraction
        listeners[key]?(fraction)
    }

    private func finished(_ key: String, _ result: Result<URL, Error>) {
        guard case .downloading = slots[key] else { return }
        switch result {
        case .success(let url): slots[key] = .ready(url)
        case .failure(let error):
            // The device filling up is a space problem, never an iCloud one.
            slots[key] = .failed(FileExportFailure.classify(error) == .full ? FileExportFailure.full : FileExportFailure.downloadFailed)
        }
    }

    /// The file is at the destination: its local copy goes, the window
    /// moves on.
    private func written(_ file: FileExportSourceFile) {
        if case .ready(let url)? = slots[file.key] { try? FileManager.default.removeItem(at: url) }
        slots.removeValue(forKey: file.key)
        queue.removeAll { $0.file.key == file.key }
        listeners[file.key] = nil
        startPump()
    }

    /// Ends the run: downloads ahead are stopped and their files removed.
    func cancelAll() {
        pump?.cancel()
        for (_, slot) in slots {
            switch slot {
            case .downloading(let task): task.cancel()
            case .ready(let url): try? FileManager.default.removeItem(at: url)
            case .failed: break
            }
        }
        slots = slots.filter { if case .failed = $0.value { true } else { false } }
    }

    /// 1 MB blocks: a 50 MB RAW never sits in memory whole (NF-02).
    static func copyInBlocks(from source: URL, to destination: URL) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        if !FileManager.default.fileExists(atPath: destination.path) {
            FileManager.default.createFile(atPath: destination.path, contents: nil)
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        try output.truncate(atOffset: 0)
        while let block = try input.read(upToCount: 1 << 20), !block.isEmpty {
            try Task.checkCancellation()
            try output.write(contentsOf: block)
        }
    }
}
