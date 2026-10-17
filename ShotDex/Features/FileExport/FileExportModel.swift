import Foundation
import Observation
import Photos
import ShotDexKit

/// The Export… sheet (FS-03.07b §3): what goes where, under which names.
/// Every rule lives here; the views only draw it.
@MainActor
@Observable
final class FileExportModel: Identifiable {
    /// What was picked, as the sheet counts it.
    struct Selection: Equatable, Sendable {
        var photoCount = 0
        var videoCount = 0
        /// Photos with an edit made in Photos — the Version row shows only
        /// when there is one.
        var editedCount = 0
        /// Indexed bytes of the originals; nil while unknown.
        var byteCount: Int64?
        /// Some of the picked photos had no indexed size.
        var isByteEstimate = false
        /// The first photo of the batch, in export order — the File Name
        /// example is built from it.
        var first: FileNameValues?
        var firstExtension = "jpg"
    }

    let id = UUID()
    let assetIds: [String]
    private(set) var selection: Selection
    let presets: [ResizePreset]

    /// The choices remembered for next time; saved as they change.
    var settings: FileExportSettings {
        didSet { settingsStore.save(settings) }
    }
    /// Not remembered: always the Settings level (FS-08.06 §4).
    var metadata: MetadataLevel
    /// Not remembered: always Edited.
    var version: FileExportVersion = .edited

    private let settingsStore: FileExportSettingsStore
    let folders: ExportFolderStore
    private let environment: FileExportEnvironment?
    /// The forms' remembered watermark (FS-05.04 §4–5); nil where the sheet
    /// does not stamp.
    let watermarkContext: ShareWatermarkContext?
    /// What this run stamps, worked out once the batch is named.
    private var runWatermark: ShareWatermark?

    /// Where the sheet is: the form, the run, the summary.
    enum Stage: Equatable {
        case choosing
        /// Reading the folder and naming the batch.
        case planning
        /// Replace: N files will be replaced — asked once, before the first byte.
        case confirmingReplace(Int)
        case running
        case finished
    }

    private(set) var stage: Stage = .choosing
    /// The remembered folder in use, as it is now.
    private(set) var folderState: ExportFolderState?
    /// Shown once when a remembered folder will not open anymore.
    var goneFolderAlert = false
    var isPickingFolder = false
    /// Not enough room: said before the first byte, nothing written.
    var spaceAlert = false
    /// Free bytes where the folder is, for the footer; nil when unknown.
    private(set) var freeBytes: Int64?
    private(set) var progress = FileExportProgress()
    private(set) var report: FileExportReport?
    /// A problem that stopped the batch before the first byte.
    private(set) var preflightFailure: FileExportFailure?
    private(set) var plan: FileExportPlan?
    private var job: FileExportJob?
    private var runner: FileExportRunner?
    private var task: Task<Void, Never>?

    init(
        assetIds: [String],
        selection: Selection,
        presets: [ResizePreset],
        settingsStore: FileExportSettingsStore = FileExportSettingsStore(),
        metadataDefault: MetadataLevel = .sharingDefault(),
        folders: ExportFolderStore? = nil,
        environment: FileExportEnvironment? = nil,
        watermarkContext: ShareWatermarkContext? = nil
    ) {
        self.watermarkContext = watermarkContext
        self.assetIds = assetIds
        self.selection = selection
        self.presets = ServerExportSizes.offered(presets)
        self.settingsStore = settingsStore
        self.settings = settingsStore.load()
        self.metadata = metadataDefault
        self.folders = folders ?? ExportFolderStore(defaults: settingsStore.defaults)
        self.environment = environment
        refreshFolder()
    }

    // MARK: Rows

    var mode: FileExportMode {
        get { settings.mode }
        set { settings.mode = newValue }
    }

    /// The Resize preset; one deleted since last time is Original.
    var preset: ResizePreset {
        presets.first { $0.id == settings.presetId } ?? .original
    }

    /// Picks a size the way Resize does: a preset of the user's own brings
    /// its format and quality with it.
    func choosePreset(_ id: UUID) {
        guard let preset = presets.first(where: { $0.id == id }) else { return }
        settings.presetId = id
        if !preset.isBuiltIn {
            // The preset's own quality, exactly — 85% stays 85% (§3a).
            settings.quality = FileExportQuality.clamped(preset.quality)
            settings.format = preset.format
        }
    }

    var template: FileNameTemplate { FileNameTemplate(settings.nameTemplate) }

    /// What Current Version renders with: the rows as they stand.
    var renderOptions: FileExportRenderOptions {
        FileExportRenderOptions(
            preset: preset, format: settings.format, quality: settings.quality,
            metadata: metadata, colorSpace: settings.colorSpace
        )
    }

    /// The Version row: only for Current Version, only with an edited photo.
    var showsVersion: Bool { mode == .currentVersion && selection.editedCount > 0 }
    var showsLivePhotoVideo: Bool { mode == .unmodifiedOriginal }
    var showsRenderRows: Bool { mode == .currentVersion }

    // MARK: Watermark (FS-05.04)

    /// The Watermark row: Current Version only — Unmodified Original is the
    /// original, and an original never carries a stamp (§2). Switching to
    /// it hides the row and leaves the remembered choice as it was.
    var showsWatermark: Bool { mode == .currentVersion && watermarkContext != nil }

    /// The row's value: the preset's name, Off, or None.
    var watermarkRowValue: String {
        guard let context = watermarkContext, context.hasPresets else { return WatermarkCopy.none() }
        return watermarkTemplate?.name ?? WatermarkCopy.off()
    }

    /// The remembered stamp, before tokens; nil when it is off.
    var watermarkTemplate: WatermarkStamp? {
        guard let context = watermarkContext else { return nil }
        let images = OverlayImageStore()
        return context.settings.formStamp(in: context.presets.presets) {
            WatermarkAvailability.of($0, imageExists: { images.imageExists(id: $0) }).isSelectable
        }
    }

    /// The Watermark screen, one page per picked photo.
    func makeWatermarkModel(photoLibrary: PhotoLibraryService, queries: LibraryQueries?) -> WatermarkModel? {
        guard let context = watermarkContext else { return nil }
        let assets = PhotoLibraryService.fetchAssets(ids: assetIds).filter { $0.mediaType == .image }
        let rows = (try? queries?.metadata(assetIds: assets.map(\.localIdentifier))) ?? [:]
        let preset = preset
        let pages = assets.map { asset in
            WatermarkPreviewPage(
                id: asset.localIdentifier,
                filename: Self.filename(asset),
                exportSize: preset.outputPixelSize(source: CGSize(width: asset.pixelWidth, height: asset.pixelHeight)),
                tokens: OverlayTokenValues(metadata: rows[asset.localIdentifier]),
                load: { await photoLibrary.detailCGImage(for: asset, longEdge: 1_200) },
                loadDetail: { await photoLibrary.detailCGImage(for: asset, longEdge: $0) }
            )
        }
        return WatermarkModel(
            settings: context.settings, presets: context.presets, pages: pages, formTitle: ExportCopy.title
        )
    }

    var subtitle: String {
        ExportCopy.countsTitle(photos: selection.photoCount, videos: selection.videoCount)
    }

    var summaryLines: [String] {
        var lines = [ExportCopy.summary(
            photos: selection.photoCount, videos: selection.videoCount,
            bytes: selection.byteCount, isEstimate: selection.isByteEstimate
        )]
        if let freeBytes, let place = folders.current?.place, hasDestination {
            lines.append(ExportCopy.freeOn(freeBytes, place: place))
        }
        switch mode {
        case .currentVersion where selection.videoCount > 0: lines.append(ExportCopy.videosAsTheyAre)
        case .unmodifiedOriginal: lines.append(ExportCopy.originalsAsTheyAre)
        default: break
        }
        return lines
    }

    /// The example under Name: the first photo of the batch.
    var exampleName: String? {
        guard let first = selection.first else { return nil }
        let base = template.baseName(
            for: first, sequence: 1,
            sequenceWidth: FileNameTemplate.sequenceWidth(count: selection.photoCount + selection.videoCount)
        )
        return "\(base).\(exampleExtension)"
    }

    private var exampleExtension: String {
        guard mode == .currentVersion else { return selection.firstExtension }
        switch settings.format {
        case .jpeg: return "jpg"
        case .heic: return "heic"
        case .preserve: return ["heic", "heif"].contains(selection.firstExtension.lowercased()) ? "heic" : "jpg"
        }
    }

    /// `2026/2026-09-20` under Date Folders: where the first photo goes.
    var dateFolderExample: String? {
        selection.first.map { ServerUploadPath.dayFolder(folder: "", captureDate: $0.captureDate) }
    }

    /// The footer of the File Name screen: what a photo with no camera — a
    /// screenshot — would be called, third in the batch.
    var missingTokenExample: String? {
        // Only a template with a token that can be missing has a case to show.
        guard settings.nameTemplate.contains("{camera}") || settings.nameTemplate.contains("{lens}"),
              var values = selection.first else { return nil }
        values.camera = nil
        values.lens = nil
        let base = template.baseName(
            for: values, sequence: 3,
            sequenceWidth: FileNameTemplate.sequenceWidth(count: selection.photoCount + selection.videoCount)
        )
        return "\(base).\(exampleExtension)"
    }

    /// Picks one of the three built-in templates.
    func chooseTemplate(_ template: FileNameTemplate) {
        settings.nameTemplate = template.pattern
    }

    /// The Custom field's text: the remembered custom template.
    var customTemplate: String {
        get { settings.customNameTemplate }
        set {
            settings.customNameTemplate = newValue
            settings.nameTemplate = newValue
        }
    }

    /// A chip: appended to the custom template, which becomes the one in
    /// use. Returns where the Text chip's word sits, to select it.
    @discardableResult
    func insert(_ chip: FileNameChip) -> Range<String.Index>? {
        let result = chip.appended(to: customTemplate)
        customTemplate = result.pattern
        return result.typedRange
    }

    var usesCustomTemplate: Bool { !template.isBuiltIn }

    /// Dims Export: no folder yet, or a name template that names nothing.
    var canExport: Bool {
        template.isUsable && hasDestination
    }

    /// A folder that opens (FS-03.07b §4), or a folder on a connection (§7).
    var hasDestination: Bool {
        if connection != nil { return true }
        if case .available = folderState { return true }
        return false
    }

    /// The writer for where the batch goes, and the security-scoped URL to
    /// open around it (a folder in Files only).
    private func destination() -> (writer: any ExportDestinationWriter, scope: URL?)? {
        guard let environment else { return nil }
        if let connection, let makeRemoteWriter = environment.makeRemoteWriter {
            return (makeRemoteWriter(connection.server, connection.path), nil)
        }
        if case .available(let url) = folderState { return (environment.makeWriter(url), url) }
        return nil
    }

    /// A folder on a saved connection, picked in the Folder menu (§7). Not
    /// remembered: the recents are folders in Files.
    private(set) var connection: ExportConnection?

    func useConnection(_ server: FileServer, path: String) {
        connection = ExportConnection(server: server, path: path)
    }

    // MARK: Folder

    /// Opens the folder in use again — at sheet open, after the app comes
    /// back, after a pick.
    func refreshFolder() {
        guard let current = folders.current else {
            folderState = nil
            return
        }
        let state = folders.resolve(current)
        if state == .gone { goneFolderAlert = true }
        folderState = state == .gone ? folders.current.map(folders.resolve) : state
        freeBytes = nil
        if case .available(let url) = folderState, let environment {
            Task { [weak self] in
                let isAccessing = url.startAccessingSecurityScopedResource()
                let free = await environment.makeWriter(url).freeBytes()
                if isAccessing { url.stopAccessingSecurityScopedResource() }
                self?.freeBytes = free
            }
        }
    }

    /// A folder from the system picker becomes the one in use.
    func pickFolder(_ url: URL?) {
        isPickingFolder = false
        guard let url else { return }
        connection = nil
        _ = try? folders.remember(url)
        refreshFolder()
    }

    func useFolder(_ folder: ExportFolder) {
        connection = nil
        folders.use(folder)
        refreshFolder()
    }

    /// `T7 › Exports`, or None.
    var folderTitle: String { connection?.title ?? folders.current?.title ?? ExportCopy.noFolder }
    /// The destination as the summary names it.
    var summaryFolder: ExportFolder? {
        guard let connection else { return folders.current }
        return ExportFolder(bookmark: Data(), name: connection.name, place: connection.server.name, path: connection.path)
    }

    /// The folder's own name, for "Exported 3 photos to “Exports”."
    var folderName: String { connection?.name ?? folders.current?.name ?? "" }
    var isFolderNotConnected: Bool { folderState == .notConnected }

    // MARK: Run

    /// The run's own Format: Same as Original resolved per photo.
    private func renderExtension(_ item: FileExportItem) -> String {
        KitExportRenderer.format(for: item, requested: settings.format).fileExtension
    }

    /// Export: reads the folder once, names the whole batch, asks about
    /// Replace if it must, then runs (FS-03.07c §2).
    func start() {
        guard canExport, stage == .choosing, let environment, let (writer, scope) = destination() else { return }
        stage = .planning
        preflightFailure = nil
        let assetIds = assetIds
        let settings = settings
        let template = template
        task = Task { [weak self] in
            let isAccessing = scope?.startAccessingSecurityScopedResource() ?? false
            defer { if isAccessing { scope?.stopAccessingSecurityScopedResource() } }
            let items = await environment.items(assetIds)
            var existing: [String: Set<String>] = [:]
            do {
                for folder in FileExportPlan.folders(for: items, dateFolders: settings.dateFolders) {
                    existing[folder] = try await writer.existingNames(in: folder)
                }
            } catch {
                guard let self else { return }
                self.preflightFailure = FileExportRunner.failure(for: error)
                self.stage = .finished
                self.task = nil
                return
            }
            guard let self else { return }
            // The stamp, per photo, before the first byte (FS-05.04).
            self.runWatermark = settings.mode == .currentVersion
                ? await self.watermarkContext?.formWatermark(ids: assetIds)
                : nil
            let plan = FileExportPlan.make(
                items: items, mode: settings.mode, template: template, policy: settings.conflictPolicy,
                dateFolders: settings.dateFolders, includesLivePhotoVideo: settings.includesLivePhotoVideo,
                renderExtension: self.renderExtension, existing: existing
            )
            // Room for the whole batch, before the first byte (07c §3).
            let needed = FileExportSpaceEstimate.neededBytes(plan, preset: self.preset)
            if let failure = FileExportSpaceEstimate.check(needed: needed, free: await writer.freeBytes()) {
                self.preflightFailure = failure
                self.spaceAlert = true
                self.stage = .choosing
                self.task = nil
                return
            }
            self.plan = plan
            self.task = nil
            if settings.conflictPolicy == .replace, plan.replaceCount > 0 {
                self.stage = .confirmingReplace(plan.replaceCount)
            } else {
                self.run(nil)
            }
        }
    }

    /// Replace confirmed.
    func confirmReplace() {
        guard case .confirmingReplace = stage else { return }
        run(nil)
    }

    /// Cancel at the Replace question: nothing changed, back to the form.
    func cancelReplace() {
        guard case .confirmingReplace = stage else { return }
        plan = nil
        stage = .choosing
    }

    /// Export Remaining: every planned file not written yet, under the
    /// names planned (FS-03.07c §2).
    func exportRemaining() {
        guard stage == .finished, let plan, let report else { return }
        run(Set(report.remaining(in: plan)))
    }

    /// Retry Failed: only the photos that failed.
    func retryFailed() {
        guard stage == .finished, let report, !report.failed.isEmpty else { return }
        run(Set(report.failedIds))
    }

    /// Stop: the current file's part is removed; what is written stays.
    func cancel() {
        task?.cancel()
    }

    private func run(_ ids: Set<String>?) {
        guard let plan, let environment, let (writer, scope) = destination() else { return }
        stage = .running
        let total = ids.map { $0.count } ?? plan.writtenEntries.count
        progress = FileExportProgress(total: total, totalBytes: Self.estimatedBytes(plan, ids: ids))
        let job = job ?? FileExportJob(
            plan: plan, mode: settings.mode, version: version,
            render: renderOptions,
            stamp: runWatermark.map(WatermarkExportStamping.init(watermark:))
        )
        self.job = job
        let runner = runner ?? FileExportRunner(
            source: environment.source, writer: writer, rendering: environment.rendering,
            onEvent: { [weak self] event in Task { @MainActor in self?.progress.apply(event) } }
        )
        self.runner = runner
        environment.holdScreen(true)
        task = Task { [weak self] in
            let isAccessing = scope?.startAccessingSecurityScopedResource() ?? false
            let report = await runner.run(job, only: ids)
            if isAccessing { scope?.stopAccessingSecurityScopedResource() }
            guard let self else { return }
            environment.holdScreen(false)
            self.report = report
            self.task = nil
            self.stage = .finished
            if report.stoppedBy == .disconnected { self.refreshFolder() }
        }
    }

    private static func estimatedBytes(_ plan: FileExportPlan, ids: Set<String>?) -> Int64 {
        plan.writtenEntries
            .filter { ids?.contains($0.id) ?? true }
            .reduce(0) { total, entry in
                total + entry.outputs.reduce(0) { $0 + ($1.source?.byteCount ?? entry.item.originalBytes) }
            }
    }

    var isRunning: Bool { stage == .running || stage == .planning }
}

/// What the sheet needs from the app to run, so a test runs it on files.
struct FileExportEnvironment {
    var source: any ExportAssetSource
    var rendering: any ExportRendering
    var items: @Sendable ([String]) async -> [FileExportItem]
    var holdScreen: @MainActor (Bool) -> Void = { _ in }
    /// The writer for a folder in Files; a test hands in one that reports
    /// little free space or a drive that goes away.
    var makeWriter: @Sendable (URL) -> any ExportDestinationWriter = { LocalFolderWriter(root: $0) }
    /// The writer for a folder on a saved connection; nil where there are none.
    var makeRemoteWriter: (@Sendable (FileServer, String) -> any ExportDestinationWriter)?
}

/// A folder on a saved connection as the destination (FS-03.07b §7).
struct ExportConnection: Equatable {
    let server: FileServer
    let path: String

    var name: String { path.isEmpty ? server.name : ServerUploadPath.lastComponent(of: path) }
    /// `NAS › Trip/Exports`.
    var title: String { path.isEmpty ? server.name : "\(server.name) › \(path)" }
}

extension FileExportModel {
    /// The sheet for picked library assets, counted from PhotoKit and the
    /// index.
    static func make(assetIds: [String], dependencies: AppDependencies) -> FileExportModel {
        let queries = dependencies.libraryQueries
        let folders = ExportFolderStore()
        #if DEBUG
        rememberFixtureFolder(in: folders)
        #endif
        return FileExportModel(
            assetIds: assetIds,
            selection: selection(of: assetIds, queries: queries),
            presets: dependencies.compressionPresets.allPresets,
            folders: folders,
            environment: FileExportEnvironment(
                source: prefetcher(fetcher: dependencies.originalFetcher),
                rendering: KitExportRenderer(renderer: dependencies.photoRenderer),
                items: { ids in
                    let metadata = (try? queries.metadata(assetIds: ids)) ?? [:]
                    return PhotoKitExportSource.items(for: ids, metadata: metadata)
                },
                holdScreen: { holds in
                    if holds { ScreenAwakeCoordinator.shared.beginHold() } else { ScreenAwakeCoordinator.shared.endHold() }
                },
                makeRemoteWriter: remoteWriter(dependencies: dependencies)
            ),
            watermarkContext: dependencies.shareWatermark
        )
    }

    /// A folder on a saved connection: one login for the run, each file sent
    /// through `ServerEditWriter` (FS-03.07b §7).
    private static func remoteWriter(dependencies: AppDependencies) -> @Sendable (FileServer, String) -> any ExportDestinationWriter {
        let store = dependencies.fileServers
        return { server, path in
            let session = ServerBrowseSession(server: server, client: RemoteFileClientFactory.make(
                for: server, password: store.password(for: server.id) ?? ""
            ))
            return RemoteFolderWriter(
                access: session, folder: path,
                scratch: FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(FileExportRunner.prefix)Remote-\(UUID().uuidString)", isDirectory: true)
            )
        }
    }

    /// PhotoKit behind the rolling iCloud window (FS-03.07c §1 item 5): a
    /// photo the offline probe calls "in iCloud" downloads ahead of its turn.
    private static func prefetcher(fetcher: any OriginalFetching) -> RollingOriginalPrefetcher {
        RollingOriginalPrefetcher(
            base: PhotoKitExportSource(fetcher: fetcher),
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("\(FileExportRunner.prefix)iCloud-\(UUID().uuidString)", isDirectory: true)
        ) { item in
            let original = OriginalItem(id: item.id, filename: item.filename,
                                        photo: PixelSize(width: item.pixelWidth, height: item.pixelHeight))
            return await fetcher.probe(original) == .inCloud
        }
    }

    #if DEBUG
    /// `-ShotDexExportFolder <name>`: a UI script cannot drive the system
    /// folder picker, so it starts with `<Documents>/<name>` remembered — the
    /// first pick, as a stand-in. Remembered once; after that the store's own
    /// order stands, as after a real pick.
    private static func rememberFixtureFolder(in folders: ExportFolderStore) {
        guard let name = UserDefaults.standard.string(forKey: "ShotDexExportFolder"), !name.isEmpty,
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return }
        let url = documents.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        guard !folders.recents.contains(where: { $0.path == url.standardizedFileURL.path }) else { return }
        _ = try? folders.remember(url)
    }
    #endif

    static func selection(of assetIds: [String], queries: LibraryQueries) -> Selection {
        let assets = PhotoLibraryService.fetchAssets(ids: assetIds)
        var selection = Selection()
        for asset in assets {
            if asset.mediaType == .video { selection.videoCount += 1 } else { selection.photoCount += 1 }
            if asset.hasAdjustments, asset.mediaType == .image { selection.editedCount += 1 }
        }
        let metadata = (try? queries.metadata(assetIds: assetIds)) ?? [:]
        let sizes = assetIds.map { metadata[$0]?.fileSize.map(Int64.init) }
        let known = sizes.compactMap { $0 }
        selection.byteCount = known.isEmpty ? nil : known.reduce(0, +)
        selection.isByteEstimate = known.count < assetIds.count
        // Export order: capture date, then original name (FS-03.07b §5).
        let first = assets.min { lhs, rhs in
            let left = lhs.creationDate ?? .distantPast, right = rhs.creationDate ?? .distantPast
            return left == right ? Self.filename(lhs) < Self.filename(rhs) : left < right
        }
        if let first {
            let name = Self.filename(first)
            let row = metadata[first.localIdentifier]
            selection.first = FileNameValues(
                original: (name as NSString).deletingPathExtension,
                captureDate: first.creationDate ?? Date(),
                camera: row?.normalizedCameraModel,
                lens: row?.normalizedLensModel
            )
            selection.firstExtension = (name as NSString).pathExtension
        }
        return selection
    }

    private static func filename(_ asset: PHAsset) -> String {
        let resources = PHAssetResource.assetResources(for: asset)
        return resources.first { $0.type == .photo || $0.type == .video }?.originalFilename
            ?? resources.first?.originalFilename ?? "Photo"
    }
}
