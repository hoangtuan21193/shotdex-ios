import Foundation
import Observation

/// The progress sheet in front of every server photo command that needs the
/// original (FS-17.06 §4): check room, bring the files down, hand them on.
@MainActor
@Observable
final class ServerEditFetchModel {
    enum Stage: Equatable {
        case preparing
        case downloading
        /// Every photo failed, or the batch stopped; the sheet says why.
        case failed(String)
        case fetched
        case cancelled
    }

    let serverId: String
    let folder: String
    let photos: [ServerPhoto]
    private(set) var stage: Stage = .preparing
    private(set) var progress = ServerDownloadModel.Progress()
    /// What came down, once `stage == .fetched`.
    private(set) var fetched: [FetchedServerPhoto] = []
    /// The folder the originals come down to. Gone again after a cancel or
    /// a failure; from `.fetched` on it is the caller's to delete.
    private(set) var workDirectory: URL?
    /// Photos that failed on their own while others came down.
    private(set) var failures: [String] = []

    private let access: any RemoteFileAccess
    private let freeSpace: () -> Int64?
    private let screenHold: ScreenHolding
    private var task: Task<Void, Never>?
    private var isHolding = false

    init(
        serverId: String,
        folder: String,
        photos: [ServerPhoto],
        access: any RemoteFileAccess,
        freeSpace: @escaping () -> Int64?,
        screenHold: ScreenHolding
    ) {
        self.serverId = serverId
        self.folder = folder
        self.photos = photos
        self.access = access
        self.freeSpace = freeSpace
        self.screenHold = screenHold
    }

    var totalBytes: Int64 { photos.reduce(0) { $0 + $1.totalBytes } }

    /// Bytes short on this device, or nil when the originals fit with 1 GB
    /// to spare (FS-17.06 §4).
    var spaceShortfall: Int64? { DeviceSpaceCheck.shortfall(for: totalBytes, free: freeSpace()) }

    /// Starts the fetch; refuses — without reading a byte — when the
    /// originals would not fit.
    func start() {
        guard stage == .preparing, task == nil else { return }
        if let shortfall = spaceShortfall {
            let amount = ByteCountFormatter.string(fromByteCount: shortfall, countStyle: .file)
            stage = .failed(String(localized: "Not enough space on this device — about \(amount) more needed.", comment: "Download from server: free space too low"))
            return
        }
        stage = .downloading
        progress = ServerDownloadModel.Progress(count: photos.count)
        beginHold()
        let items = photos.map { ServerDownloadItem(photo: $0, folder: folder) }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(TemporaryWorkspace.serverEditPrefix)\(UUID().uuidString)", isDirectory: true)
        workDirectory = directory
        let fetch = ServerEditFetch(access: access, serverId: serverId, workDirectory: directory) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        task = Task { [weak self] in
            let result = await fetch.run(items)
            self?.finish(result, directory: directory)
        }
    }

    /// Stops the fetch; what came down so far is deleted.
    func cancel() {
        task?.cancel()
    }

    private func handle(_ event: ServerEditFetchEvent) {
        guard stage == .downloading else { return }
        switch event {
        case .itemStarted(let index):
            progress.index = index
            progress.filename = photos[index].primary.name
        case .bytes(let done, let total):
            progress.bytesDone = max(progress.bytesDone, done)
            progress.bytesTotal = total
        }
    }

    private func finish(_ result: ServerEditFetchResult, directory: URL) {
        task = nil
        endHold()
        failures = result.failures.sorted { $0.key < $1.key }.map { "\(photos[$0.key].primary.name): \($0.value)" }
        switch result.stopReason {
        case .cancelled:
            stage = .cancelled
        case .error(let error):
            stage = .failed(error.localizedDescription)
        case nil where result.photos.isEmpty:
            try? FileManager.default.removeItem(at: directory)
            stage = .failed(failures.first ?? String(localized: "Couldn't download the photo.", comment: "Server photo command: nothing came down"))
        case nil:
            fetched = result.photos
            stage = .fetched
        }
    }

    private func beginHold() {
        guard !isHolding else { return }
        isHolding = true
        screenHold.beginHold()
    }

    private func endHold() {
        guard isHolding else { return }
        isHolding = false
        screenHold.endHold()
    }
}
