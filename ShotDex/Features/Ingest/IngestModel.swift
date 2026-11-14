import Foundation
import Observation

/// What an import needs from the app, on iOS and on the Mac (FS-20): the
/// database, where folder sources live, a read of the destination as photos
/// land, and a word when it ends.
@MainActor
protocol IngestEnvironment: AnyObject {
    var database: AppDatabase { get }
    var folderRoots: FolderSourceRoots { get }
    func readImportedSource(_ sourceId: String) async
    func announceImport(_ text: String)
}

#if os(iOS)
extension AppDependencies: IngestEnvironment {
    func readImportedSource(_ sourceId: String) async { await sources.read(sourceId: sourceId) }
    func announceImport(_ text: String) { banner.show(text) }
}
#endif

/// One card's Import from Card screen (FS-20 §5–8): its photos, which are
/// new, what is ticked, where they go, and the run. Kept by `IngestCenter`
/// while it runs, so leaving the screen never stops an import (AC-17).
@MainActor
@Observable
final class IngestModel {
    enum Segment: Hashable { case all, new }

    enum Phase: Equatable {
        case loading
        case ready
        case running
        case finished(IngestSummary)
        case failedToRead
    }

    let card: RememberedCard
    let root: URL

    private(set) var phase: Phase = .loading
    private(set) var items: [CardItem] = []
    private(set) var imported: Set<String> = []
    var selection = IngestSelection(items: [], imported: [])
    var segment: Segment = .new
    /// Saved a moment after the last change, not on every keystroke in the
    /// name and metadata fields; a run saves what it starts with at once.
    var settings: IngestSettings {
        didSet { scheduleSave() }
    }
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            IngestSettingsStore.save(self.settings)
        }
    }

    /// Writes the settings now (FS-20 §6: remembered for next time).
    func saveSettings() {
        saveTask?.cancel()
        saveTask = nil
        IngestSettingsStore.save(settings)
    }
    private(set) var progress = IngestProgress()
    private(set) var isPaused = false
    /// The run's file list (board `MAC_IngestProgress`): the last photos
    /// done, the one in hand, the next waiting — never the whole batch.
    private(set) var files = IngestFileList()
    /// Photos whose every file is in the destination and verified, and
    /// those whose backup copy is too, this run.
    private(set) var verifiedCount = 0
    private(set) var backedUpCount = 0
    /// Bytes of the photo in hand copied so far: the Copy bar moves inside
    /// a 50 MB RAW, not only between photos.
    private(set) var inHandBytes: Int64 = 0
    /// Pause asked and the runner has stopped between photos: until then
    /// the photo in hand is still going in ("Pausing…").
    private(set) var isParked = false
    /// Stop Import pressed; the runner is finishing the file in hand and
    /// sweeping part files.
    private(set) var isStopping = false
    /// Photos that failed this run, for "2 couldn't be copied".
    private(set) var failedCount = 0
    /// What this run is: a fresh import, the rest of one, or only backups.
    enum RunKind: Equatable { case fresh, rest, backupOnly }
    private(set) var runKind = RunKind.fresh
    /// Pause and Resume reach the runner one after another, in the order
    /// pressed, each with the state at that moment.
    @ObservationIgnored private var pauseTask: Task<Void, Never>?
    /// Which run a byte count belongs to: one from a run that ended is dropped.
    @ObservationIgnored private var runGeneration = 0
    /// Time spent copying this run, pauses left out, for "2 min left".
    @ObservationIgnored private var activeSince: ContinuousClock.Instant?
    @ObservationIgnored private var activeBefore: Duration = .zero
    /// What the last run left: failed photos (Retry Failed), photos never
    /// started (Import Remaining), photos not yet on the backup.
    private(set) var lastSummary: IngestSummary?
    /// Used and total bytes of the card, for the header.
    private(set) var cardSpace: (used: Int64, total: Int64)?
    private(set) var destinations: [SourceStore.Source] = []

    @ObservationIgnored private let dependencies: any IngestEnvironment
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var runner: IngestRunner?
    @ObservationIgnored private var lastSourceRead = ContinuousClock.now
    @ObservationIgnored private var plan: FileExportPlan?
    @ObservationIgnored private var activeRecorder: IngestRecorder?
    @ObservationIgnored private var matches: [IngestStatus.Key: IngestStatus.Match] = [:]
    /// What the background hash found, by card path (AC-22).
    @ObservationIgnored private var hashed: [String: IngestStatus.Hashed] = [:]
    @ObservationIgnored private var hashTask: Task<Void, Never>?
    @ObservationIgnored var onUserStart: (@MainActor (IngestModel) -> Void)?
    /// A run that ended, wherever the user is: the Mac ejects the card here
    /// (After Import › Eject), not in a page that may be gone.
    @ObservationIgnored var onFinish: (@MainActor (IngestModel, IngestSummary) -> Void)?

    init(card: RememberedCard, root: URL, dependencies: any IngestEnvironment) {
        self.card = card
        self.root = root
        self.dependencies = dependencies
        settings = IngestSettingsStore.load()
    }

    var reader: FolderCardReader {
        var reader = FolderCardReader(root: root, name: card.name)
        #if DEBUG
        // `-ShotDexSlowIngest`: a pause per chunk, so a UI script can
        // photograph the run on a card of small test files.
        if ProcessInfo.processInfo.arguments.contains("-ShotDexSlowIngest") { reader.pace = .milliseconds(700) }
        #endif
        return reader
    }
    var isRunning: Bool { phase == .running }

    // MARK: Loading

    func load() async {
        loadDestinations()
        let isAccessing = root.startAccessingSecurityScopedResource()
        defer { if isAccessing { root.stopAccessingSecurityScopedResource() } }
        if let values = try? root.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
           let total = values.volumeTotalCapacity, let free = values.volumeAvailableCapacity {
            cardSpace = (Int64(total - free), Int64(total))
        }
        guard let files = try? await reader.list() else {
            phase = .failedToRead
            return
        }
        items = CardCatalog.items(files)
        refreshImported()
        selection = IngestSelection(items: items, imported: imported)
        phase = .ready
        startHashPass()
    }

    /// The background read that corrects the history (FS-20 §5, AC-22): a
    /// photo the hash moves to New arrives ticked; one it finds already in a
    /// source loses its tick. Import never waits for it.
    private func startHashPass() {
        hashTask?.cancel()
        let root = self.root
        let pass = CardHashPass(database: dependencies.database, reader: reader,
                                fileURL: { root.appendingPathComponent($0.path) })
        let files = items.map(\.primary)
        let sink = IngestEventSink(model: self)
        hashTask = Task.detached(priority: .utility) {
            let isAccessing = root.startAccessingSecurityScopedResource()
            defer { if isAccessing { root.stopAccessingSecurityScopedResource() } }
            await pass.run(files) { path, result in
                await sink.model?.hashed(path, result)
            }
        }
    }

    /// Before an eject: the background hash lets go of the card.
    func cancelHashPass() {
        hashTask?.cancel()
        hashTask = nil
    }

    private func hashed(_ path: String, _ result: IngestStatus.Hashed) {
        hashed[path] = result
        guard !isRunning, let item = items.first(where: { $0.primary.path == path }) else { return }
        let isImported = IngestStatus.isImported(item, matches: matches, hashed: hashed)
        guard isImported != imported.contains(item.id) else { return }
        if isImported { imported.insert(item.id) } else { imported.remove(item.id) }
        var checked = selection.checked
        if isImported { checked.remove(item.id) } else { checked.insert(item.id) }
        selection = IngestSelection(items: items, imported: imported, keeping: checked)
    }

    func loadDestinations() {
        destinations = ((try? SourceStore(database: dependencies.database).sources()) ?? [])
            .filter { $0.kind == "folder" || $0.kind == "drive" }
        if settings.destinationSourceId == nil || !destinations.contains(where: { $0.id == settings.destinationSourceId }) {
            settings.destinationSourceId = destinations.first?.id
        }
    }

    /// The history, read again (FS-20 §5): imported means the copy it
    /// made is still in the destination.
    func refreshImported() {
        let roots = dependencies.folderRoots
        matches = (try? CardImportStore(database: dependencies.database).matches(for: items.map(\.primary)) { sourceId, path in
            roots.root(sourceId).map { FileManager.default.fileExists(atPath: $0.appendingPathComponent(path).path) }
        }) ?? [:]
        imported = Set(items.filter { IngestStatus.isImported($0, matches: matches, hashed: hashed) }.map(\.id))
    }

    // MARK: Grid

    var newCount: Int { items.count - imported.count }

    var days: [IngestStatus.Day] {
        let all = IngestStatus.days(items, imported: imported)
        guard segment == .new else { return all }
        return all.compactMap { day in
            let fresh = day.items.filter { !imported.contains($0.id) }
            return fresh.isEmpty ? nil : IngestStatus.Day(date: day.date, items: fresh, importedIds: [])
        }
    }

    func toggle(_ item: CardItem) { selection.toggle(item.id) }
    func checkAll() { selection.checkAll(items) }
    func uncheckAll() { selection.uncheckAll() }
    var checkedCount: Int { selection.checked.count }
    var checkedBytes: Int64 { selection.bytes(items) }

    // MARK: Destination

    var destination: SourceStore.Source? { destinations.first { $0.id == settings.destinationSourceId } }

    var destinationRoot: URL? { settings.destinationSourceId.flatMap { dependencies.folderRoots.root($0) } }

    var backupRoot: URL? {
        guard settings.backsUp, let folder = settings.backupFolder else { return nil }
        var isStale = false
        // Security-scoped on the Mac: a plain bookmark resolves after a relaunch but cannot be written to.
        guard let url = try? SourceBookmark.resolve(folder.bookmark, isStale: &isStale) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return (try? url.checkResourceIsReachable()) == true ? url : nil
    }

    var readiness: IngestReadiness {
        let destinationDrive = destination.map { source in
            IngestReadiness.Drive(name: source.name, isConnected: destinationRoot != nil,
                                  freeBytes: destinationRoot.flatMap { DiskSpace.availableBytes(for: $0) })
        }
        // Ticked with no folder yet (its panel is open): nothing to check until one is chosen.
        let backupDrive: IngestReadiness.Drive? = settings.backsUp && settings.backupFolder != nil ? {
            let root = backupRoot
            return .init(name: settings.backupFolder?.place.isEmpty == false ? settings.backupFolder!.place : (settings.backupFolder?.name ?? ""),
                         isConnected: root != nil, freeBytes: root.flatMap { DiskSpace.availableBytes(for: $0) })
        }() : nil
        return IngestReadiness(checkedCount: checkedCount, checkedBytes: checkedBytes,
                               destination: destinationDrive, backup: backupDrive)
    }

    /// `2026-10-03_Kyoto_6123.CR3`, from the first ticked photo.
    var exampleName: String? {
        guard let first = items.first(where: { selection.checked.contains($0.id) }) ?? items.first else { return nil }
        let item = IngestPlan.exportItem(first)
        let base = settings.template.baseName(for: item.nameValues, sequence: 1, sequenceWidth: 3)
        return base + "." + (first.primary.name as NSString).pathExtension
    }

    var exampleFolder: String? {
        guard let first = items.first, let date = first.date else { return nil }
        return settings.folders.folder(for: date)
    }

    // MARK: Running

    /// Import N Photos (FS-20 §7).
    func startImport() {
        saveSettings()
        let ids = selection.checked
        guard readiness.canImport, !ids.isEmpty else { return }
        run(ids: ids, freshPlan: true)
    }

    func importRemaining() {
        guard let remaining = lastSummary?.remaining, !remaining.isEmpty else { return }
        run(ids: Set(remaining), freshPlan: false)
    }

    func retryFailed() {
        guard let failed = lastSummary?.failed.keys, !failed.isEmpty else { return }
        run(ids: Set(failed), freshPlan: false)
    }

    func backUpRemaining() {
        guard let summary = lastSummary else { return }
        let rest = Set(summary.imported).subtracting(summary.backedUp)
        guard !rest.isEmpty else { return }
        run(ids: rest, freshPlan: false, copiesPrimary: false)
    }

    /// Stop Import… → Stop: within a second, part files swept, the card kept.
    func stop() {
        guard isRunning else { return }
        isStopping = true
        runTask?.cancel()
    }

    /// A pause asked while the plan is still being made reaches the runner
    /// when it is made (see `run`).
    func pause() {
        isPaused = true
        pushPause()
    }

    func resume() {
        isPaused = false
        pushPause()
    }

    private func pushPause() {
        let previous = pauseTask
        pauseTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await self.runner?.setPaused(self.isPaused)
        }
    }

    /// The time-left clock runs only while the runner copies.
    private func park(_ parked: Bool) {
        isParked = parked
        if parked {
            if let activeSince { activeBefore += ContinuousClock.now - activeSince }
            activeSince = nil
        } else if activeSince == nil {
            activeSince = .now
        }
    }

    /// Bytes copied so far, the photo in hand included.
    var copiedBytes: Int64 { progress.bytesDone + inHandBytes }

    /// The progress every surface shows — the page header, Activity, the
    /// system's — with the photo in hand's bytes in, so they say one number.
    var liveProgress: IngestProgress {
        var live = progress
        live.bytesDone = copiedBytes
        return live
    }

    /// About how long the rest takes, from this run's own pace; nil in the
    /// first seconds and while paused, when a guess would be noise.
    var secondsLeft: Int? {
        guard !isPaused, !isParked, let activeSince else { return nil }
        let active = activeBefore + (ContinuousClock.now - activeSince)
        let seconds = Double(active.components.seconds) + Double(active.components.attoseconds) / 1e18
        let copied = copiedBytes
        guard seconds >= 3, copied > 0, progress.bytesTotal > copied else { return nil }
        return Int((Double(progress.bytesTotal - copied) / (Double(copied) / seconds)).rounded(.up))
    }

    private func run(ids: Set<String>, freshPlan: Bool, copiesPrimary: Bool = true) {
        guard let destinationRoot, let destination else { return }
        phase = .running
        onUserStart?(self)
        isPaused = false
        isParked = false
        isStopping = false
        failedCount = 0
        runKind = !copiesPrimary ? .backupOnly : (freshPlan ? .fresh : .rest)
        runGeneration += 1
        let generation = runGeneration
        let chosenItems = items.filter { ids.contains($0.id) }
        // The size is known before the first photo: the bar and "of 24.6 GB" from the start.
        progress = IngestProgress(total: ids.count, bytesTotal: chosenItems.reduce(0) { $0 + $1.byteCount })
        // Back Up Remaining: every photo of the run is verified already.
        verifiedCount = copiesPrimary ? 0 : ids.count
        backedUpCount = 0
        inHandBytes = 0
        activeBefore = .zero
        activeSince = .now
        files = IngestFileList(order: chosenItems.map { IngestFileList.Entry(id: $0.id, name: $0.primary.name, bytes: $0.byteCount) })
        let reader = self.reader
        let settings = self.settings
        let backupRoot = settings.backsUp ? self.backupRoot : nil
        let backupName = settings.backupFolder?.title ?? ""
        let chosen = chosenItems
        let existingPlan = freshPlan ? nil : plan
        activeRecorder = makeRecorder()
        let sink = IngestEventSink(model: self)
        runTask = Task { [weak self] in
            let isAccessing = reader.root.startAccessingSecurityScopedResource()
            defer { if isAccessing { reader.root.stopAccessingSecurityScopedResource() } }
            let writer = LocalFolderWriter(root: destinationRoot)
            let plan: FileExportPlan
            if let existingPlan {
                plan = existingPlan
            } else {
                let exportItems = chosen.map { IngestPlan.exportItem($0) }
                var existing: [String: Set<String>] = [:]
                for folder in IngestPlan.folders(for: exportItems, template: settings.folders) {
                    existing[folder] = (try? await writer.existingNames(in: folder)) ?? []
                }
                plan = IngestPlan.make(exportItems, template: settings.template, folders: settings.folders, existing: existing)
            }
            let runner = IngestRunner(
                card: reader, plan: plan,
                primary: IngestTarget(destination: writer, name: destination.name),
                backup: backupRoot.map { IngestTarget(destination: LocalFolderWriter(root: $0), name: backupName) },
                onEvent: { event in await sink.model?.handle(event) },
                onCopied: { itemId, bytes in
                    Task { @MainActor in sink.model?.copied(itemId: itemId, bytes: bytes, generation: generation) }
                }
            )
            self?.plan = plan
            self?.runner = runner
            // Pause pressed while the plan was being made.
            if let self { await runner.setPaused(self.isPaused) }
            // The order the runner goes in, now that the plan is known.
            let runEntries = plan.writtenEntries.filter { ids.contains($0.id) }
            self?.files.reorder(runEntries.map(\.id),
                                folders: Dictionary(runEntries.map { ($0.id, $0.folder) }, uniquingKeysWith: { first, _ in first }))
            let summary = await runner.run(only: ids, copiesPrimary: copiesPrimary, backsUp: backupRoot != nil)
            self?.finish(summary)
        }
    }

    private func handle(_ event: IngestEvent) async {
        activeRecorder?.handle(event)
        switch event {
        case .imported(let itemId):
            verifiedCount += 1
            inHandBytes = 0
            files.verified(itemId)
            imported.insert(itemId)
            selection = IngestSelection(items: items, imported: imported, keeping: selection.checked)
            readSourceIfDue()
        case .progress(let progress):
            self.progress = progress
            inHandBytes = 0
            files.finishInHand()
        case .stage(let itemId, let stage):
            if stage == .copying, files.inHand?.id != itemId { inHandBytes = 0 }
            files.set(itemId, stage)
        case .backedUp(let itemId, _):
            backedUpCount += 1
            files.backedUp(itemId)
        case .failed(let itemId, _):
            failedCount += 1
            files.failed(itemId)
        case .parked(let parked):
            park(parked)
        case .fileVerified:
            break
        }
    }

    /// A chunk count from the runner, which may land after the photo is
    /// done: only the photo still copying takes it.
    fileprivate func copied(itemId: String, bytes: Int64, generation: Int) {
        guard generation == runGeneration, phase == .running, let inHand = files.inHand, inHand.id == itemId, case .copying = inHand.state else { return }
        inHandBytes = min(bytes, inHand.bytes)
        files.copied(itemId, fraction: inHand.bytes > 0 ? Double(bytes) / Double(inHand.bytes) : 0)
    }

    private func makeRecorder() -> IngestRecorder? {
        guard let sourceId = settings.destinationSourceId, let root = destinationRoot else { return nil }
        return IngestRecorder(database: dependencies.database, cardId: card.id, cardName: card.name, sourceId: sourceId,
                              destinationRoot: root, metadata: settings.metadata,
                              items: Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) }))
    }

    /// Photos join the source as they land (FS-20 §7.5): the destination is
    /// read again at most every 10 s, and once at the end.
    private func readSourceIfDue(force: Bool = false) {
        guard let sourceId = settings.destinationSourceId else { return }
        guard force || ContinuousClock.now - lastSourceRead > .seconds(10) else { return }
        lastSourceRead = .now
        let dependencies = self.dependencies
        Task { await dependencies.readImportedSource(sourceId) }
    }

    private func finish(_ summary: IngestSummary) {
        lastSummary = summary
        if let activeSince { activeBefore += ContinuousClock.now - activeSince }
        activeSince = nil
        isParked = false
        isStopping = false
        inHandBytes = 0
        files.finishInHand()
        runner = nil
        runTask = nil
        isPaused = false
        phase = .finished(summary)
        readSourceIfDue(force: true)
        onFinish?(self, summary)
        let count = summary.imported.count
        if summary.canEject(backupEnabled: settings.backsUp) {
            // A card in Files can't be ejected from an app on iOS: say it is
            // safe to remove instead (plan Q3).
            dependencies.announceImport(IngestCopy.finishedBanner(count: count, card: card.name, ejected: false,
                                                               canRemove: settings.ejectsAfterImport))
        } else if summary.ending == .finished, summary.failed.isEmpty, !summary.backupIncomplete {
            dependencies.announceImport(IngestCopy.finishedBanner(count: count, card: card.name, ejected: false, canRemove: false))
        }
    }

    var endingMessage: String? {
        guard let lastSummary else { return nil }
        return IngestCopy.endingMessage(lastSummary, card: card.name, destination: destination?.name ?? "")
    }
}

/// The runner reports from its own actor; the model is held weakly so a
/// screen that went away is not kept alive by its run alone.
private struct IngestEventSink: Sendable {
    weak var model: IngestModel?
}

extension IngestSelection {
    /// After a photo is imported mid-run: its tick goes, the rest stay.
    init(items: [CardItem], imported: Set<String>, keeping checked: Set<String>) {
        self.init(items: items, imported: imported)
        uncheckAll()
        for id in checked.subtracting(imported) { toggle(id) }
    }
}

/// The import that is running, wherever the user is (FS-20 §7): the card's
/// row in Sources shows its progress, and the screen opens on it again.
@MainActor
@Observable
final class IngestCenter {
    private(set) var models: [String: IngestModel] = [:]
    /// A run the user started: the background service asks iOS 26 to let
    /// it carry on after the app leaves (AC-26).
    @ObservationIgnored var onUserStart: (@MainActor (IngestModel) -> Void)?

    func model(for card: RememberedCard, root: URL, dependencies: any IngestEnvironment) -> IngestModel {
        if let existing = models[card.id] { return existing }
        let model = IngestModel(card: card, root: root, dependencies: dependencies)
        model.onUserStart = { [weak self] in self?.onUserStart?($0) }
        models[card.id] = model
        return model
    }

    var running: IngestModel? { models.values.first { $0.isRunning } }

    /// A card pulled out with nothing running: its screen goes.
    func forget(_ cardId: String) {
        guard models[cardId]?.isRunning != true else { return }
        models[cardId] = nil
    }
}
