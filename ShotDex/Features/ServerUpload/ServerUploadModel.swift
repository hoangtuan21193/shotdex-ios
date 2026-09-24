import Foundation
import Observation

/// Something that keeps the screen from locking while it is held.
@MainActor
protocol ScreenHolding: AnyObject {
    func beginHold()
    func endHold()
}

extension ScreenAwakeCoordinator: ScreenHolding {}

/// One run of the upload sheet (FS-15.02): prepare → upload → (conflict) →
/// result, for the assets picked in the grid.
@MainActor
@Observable
final class ServerUploadModel {
    enum Stage: Equatable {
        case preparing
        case uploading
        case finished
    }

    struct Progress: Equatable {
        var fileIndex = 0
        var fileCount = 0
        var filename = ""
        var phase: ServerUploadPhase = .preparing
        var bytesDone: Int64 = 0
        var bytesTotal: Int64 = 0
        /// Seconds left from the last 30 s of throughput; nil until measured.
        var secondsLeft: Double?

        var fraction: Double {
            bytesTotal > 0 ? min(1, Double(bytesDone) / Double(bytesTotal)) : 0
        }
    }

    struct Failure: Identifiable, Equatable {
        let id: Int
        let filename: String
        let reason: String
    }

    struct Summary: Equatable {
        var uploadedPhotoCount = 0
        var uploadedBytes: Int64 = 0
        var skippedFileCount = 0
        var failures: [Failure] = []
        var notAttemptedCount = 0
        var stopMessage: String?
        /// Assets safe to delete: every original verified on some server.
        var deletableAssetIds: [String] = []
        /// Assets partly uploaded, with the originals still missing.
        var partiallyUploaded: [String: [String]] = [:]
    }

    let assetIds: [String]
    private(set) var stage: Stage = .preparing
    private(set) var servers: [FileServer] = []
    var selectedServerId: String?
    var fileKind: ServerUploadFileKind = .allOriginals
    private(set) var entries: [AssetUploadEntry]?
    private(set) var progress = Progress()
    private(set) var summary = Summary()
    private(set) var pendingConflict: ServerUploadConflict?
    private(set) var isDeleting = false
    var deleteError: String?

    private let fileServers: FileServerStore
    private let uploads: ServerUploadStore
    private let index: ServerUploadIndex?
    private let screenHold: ScreenHolding
    private let listEntries: @Sendable ([String]) async -> [AssetUploadEntry]
    private let makeClient: (FileServer, String) -> any RemoteFileClient
    private let exporter: any AssetFileExporting
    private let deleteAssets: ([String]) async throws -> Void

    private var task: Task<Void, Never>?
    private var session: ServerUploadSession?
    private var conflictContinuation: CheckedContinuation<ServerUploadConflictDecision, Never>?
    private var isHolding = false
    private var lastItems: [ServerUploadItem] = []
    private var lastOutcomes: [ServerUploadOutcome] = []
    private var samples: [(time: Date, bytes: Int64)] = []

    init(
        assetIds: [String],
        fileServers: FileServerStore,
        uploads: ServerUploadStore,
        index: ServerUploadIndex?,
        screenHold: ScreenHolding,
        listEntries: @escaping @Sendable ([String]) async -> [AssetUploadEntry],
        makeClient: @escaping (FileServer, String) -> any RemoteFileClient,
        exporter: any AssetFileExporting,
        deleteAssets: @escaping ([String]) async throws -> Void
    ) {
        self.assetIds = assetIds
        self.fileServers = fileServers
        self.uploads = uploads
        self.index = index
        self.screenHold = screenHold
        self.listEntries = listEntries
        self.makeClient = makeClient
        self.exporter = exporter
        self.deleteAssets = deleteAssets
    }

    convenience init(assetIds: [String], dependencies: AppDependencies) {
        let library = dependencies.photoLibrary
        let metadata = dependencies.metadataStore
        self.init(
            assetIds: assetIds,
            fileServers: dependencies.fileServers,
            uploads: dependencies.serverUploads,
            index: dependencies.serverUploadIndex,
            screenHold: ScreenAwakeCoordinator.shared,
            listEntries: { ids in
                await Task.detached(priority: .userInitiated) { PhotoKitOriginalExporter.entries(for: ids) }.value
            },
            makeClient: RemoteFileClientFactory.make(for:password:),
            exporter: PhotoKitOriginalExporter(),
            deleteAssets: { ids in
                try await library.deleteAssets(PhotoLibraryService.fetchAssets(ids: ids))
                try? metadata.deleteAssets(ids: ids)
            }
        )
    }

    // MARK: Prepare

    var selectedServer: FileServer? {
        servers.first { $0.id == selectedServerId }
    }

    var planSummary: ServerUploadPlan.Summary? {
        entries.map { ServerUploadPlan.summary(of: $0.map(\.files), kind: fileKind) }
    }

    var canStart: Bool {
        stage == .preparing && selectedServer != nil && (planSummary?.fileCount ?? 0) > 0
    }

    func load() async {
        reloadServers()
        if entries == nil {
            entries = await listEntries(assetIds)
        }
    }

    /// Reads the server list again (after Add Server), keeping the pick — or
    /// taking `select` when the form just saved one.
    func reloadServers(select: String? = nil) {
        servers = (try? fileServers.fetchAll()) ?? []
        if let select {
            selectedServerId = select
        } else if selectedServer == nil {
            selectedServerId = (try? fileServers.mostRecentlyUsed())?.id ?? servers.first?.id
        }
    }

    // MARK: Upload

    func start() {
        guard let server = selectedServer, let entries else { return }
        let items = entries.flatMap { entry in
            ServerUploadPlan.files(of: entry.files, kind: fileKind).map { file in
                ServerUploadItem(
                    assetId: entry.assetId,
                    file: file,
                    remotePath: ServerUploadPath.remotePath(
                        folder: server.folder, captureDate: entry.captureDate, filename: file.filename
                    )
                )
            }
        }
        run(items, on: server)
    }

    /// Everything the last batch did not get onto the server, skipped files
    /// aside — the user already chose to skip those.
    func uploadRemaining() {
        guard let server = selectedServer else { return }
        let remaining = zip(lastItems, lastOutcomes).compactMap { item, outcome -> ServerUploadItem? in
            switch outcome {
            case .failed, .notAttempted: item
            case .uploaded, .alreadyThere, .skipped: nil
            }
        }
        guard !remaining.isEmpty else { return }
        run(remaining, on: server)
    }

    var hasRemaining: Bool {
        lastOutcomes.contains { if case .failed = $0 { true } else { $0 == .notAttempted } }
    }

    private func run(_ items: [ServerUploadItem], on server: FileServer) {
        guard task == nil else { return }
        try? fileServers.markUsed(server.id)
        lastItems = items
        stage = .uploading
        progress = Progress(fileCount: items.count)
        samples = []
        beginHold()

        let password = fileServers.password(for: server.id) ?? ""
        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(TemporaryWorkspace.serverUploadPrefix)\(UUID().uuidString)", isDirectory: true)
        let uploads = uploads
        let session = ServerUploadSession(
            client: makeClient(server, password),
            exporter: exporter,
            serverId: server.id,
            serverName: server.name,
            workDirectory: workDirectory,
            resolveConflict: { [weak self] conflict in
                await self?.ask(conflict) ?? .init(choice: .skip)
            },
            onEvent: { [weak self] event in
                Task { @MainActor in self?.handle(event, items: items) }
            },
            record: { try uploads.record($0) }
        )
        self.session = session
        task = Task { [weak self] in
            let result = await session.run(items)
            try? FileManager.default.removeItem(at: workDirectory)
            self?.finish(result, items: items)
        }
    }

    /// The Cancel button, and leaving the app: stop after cleaning the part
    /// on the server.
    func cancel() {
        task?.cancel()
        answerConflict(.init(choice: .skip))
    }

    /// Closing the sheet without waiting — nothing is left holding the
    /// screen awake.
    func tearDown() {
        cancel()
        endHold()
    }

    private func handle(_ event: ServerUploadEvent, items: [ServerUploadItem]) {
        switch event {
        case .fileStarted(let index, let phase):
            progress.fileIndex = index
            progress.filename = items[index].file.filename
            progress.phase = phase
        case .phase(let index, let phase):
            progress.fileIndex = index
            progress.phase = phase
        case .bytes(let done, let total):
            progress.bytesDone = max(progress.bytesDone, done)
            progress.bytesTotal = total
            recordSample(done)
        case .fileFinished:
            break
        }
    }

    private func recordSample(_ bytes: Int64) {
        let now = Date()
        samples.append((now, bytes))
        samples.removeAll { now.timeIntervalSince($0.time) > 30 }
        guard let first = samples.first, now.timeIntervalSince(first.time) > 2 else { return }
        let rate = Double(bytes - first.bytes) / now.timeIntervalSince(first.time)
        progress.secondsLeft = rate > 0 ? Double(progress.bytesTotal - bytes) / rate : nil
    }

    private func finish(_ result: ServerUploadResult, items: [ServerUploadItem]) {
        task = nil
        session = nil
        lastOutcomes = result.outcomes
        endHold()

        var summary = Summary()
        var uploadedAssets = Set<String>()
        for (index, (item, outcome)) in zip(items, result.outcomes).enumerated() {
            switch outcome {
            case .uploaded, .alreadyThere:
                uploadedAssets.insert(item.assetId)
                summary.uploadedBytes += item.file.estimatedBytes
            case .skipped:
                summary.skippedFileCount += 1
            case .failed(let reason):
                summary.failures.append(Failure(id: index, filename: item.file.filename, reason: reason))
            case .notAttempted:
                summary.notAttemptedCount += 1
            }
        }
        summary.uploadedPhotoCount = uploadedAssets.count
        switch result.stopReason {
        case .cancelled: summary.stopMessage = String(localized: "Upload stopped. Files already uploaded stay on the server.", comment: "Upload to Server result after Cancel")
        case .error(let error): summary.stopMessage = error.localizedDescription
        case nil: break
        }

        // Every picked photo, not just this run's: after Upload Remaining the
        // ones the first run finished are still safe to delete. The history
        // decides, so a photo sent last month to another server counts too.
        let keys = (try? uploads.uploadedFileKeys(assetIds: assetIds)) ?? [:]
        let verdict = ServerUploadEligibility.evaluate(
            assets: (entries ?? []).map { ($0.assetId, $0.files) },
            uploadedKeys: keys
        )
        summary.deletableAssetIds = verdict.deletable
        summary.partiallyUploaded = verdict.missing
        index?.insert(uploadedAssets)
        self.summary = summary
        stage = .finished
    }

    // MARK: Conflicts

    private func ask(_ conflict: ServerUploadConflict) async -> ServerUploadConflictDecision {
        if Task.isCancelled || task?.isCancelled == true { return .init(choice: .skip) }
        return await withCheckedContinuation { continuation in
            conflictContinuation = continuation
            pendingConflict = conflict
        }
    }

    func answerConflict(_ decision: ServerUploadConflictDecision) {
        pendingConflict = nil
        conflictContinuation?.resume(returning: decision)
        conflictContinuation = nil
    }

    /// The "On Server" half of the comparison, on local disk.
    func downloadConflictPreview(_ conflict: ServerUploadConflict) async -> URL? {
        try? await session?.downloadForPreview(conflict.item.remotePath)
    }

    // MARK: Delete

    func deleteUploaded() async {
        let ids = summary.deletableAssetIds
        guard !ids.isEmpty else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await deleteAssets(ids)
            summary.deletableAssetIds = []
        } catch {
            // Declining the system's own confirmation is a cancel, not an error.
            let nsError = error as NSError
            if nsError.domain == "PHPhotosErrorDomain", nsError.code == 3072 { return }
            deleteError = error.localizedDescription
        }
    }

    // MARK: Screen

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
