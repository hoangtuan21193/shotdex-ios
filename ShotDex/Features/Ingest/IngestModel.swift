import Foundation
import Observation

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
    var settings: IngestSettings {
        didSet { IngestSettingsStore.save(settings) }
    }
    private(set) var progress = IngestProgress()
    private(set) var isPaused = false
    /// What the last run left: failed photos (Retry Failed), photos never
    /// started (Import Remaining), photos not yet on the backup.
    private(set) var lastSummary: IngestSummary?
    /// Used and total bytes of the card, for the header.
    private(set) var cardSpace: (used: Int64, total: Int64)?
    private(set) var destinations: [SourceStore.Source] = []

    @ObservationIgnored private let dependencies: AppDependencies
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var runner: IngestRunner?
    @ObservationIgnored private var lastSourceRead = ContinuousClock.now
    @ObservationIgnored private var plan: FileExportPlan?
    @ObservationIgnored private var activeRecorder: IngestRecorder?
    @ObservationIgnored private var matches: [IngestStatus.Key: IngestStatus.Match] = [:]
    /// What the background hash found, by card path (AC-22).
    @ObservationIgnored private var hashed: [String: IngestStatus.Hashed] = [:]
    @ObservationIgnored private var hashTask: Task<Void, Never>?

    init(card: RememberedCard, root: URL, dependencies: AppDependencies) {
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
        guard let url = try? URL(resolvingBookmarkData: folder.bookmark, bookmarkDataIsStale: &isStale) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return (try? url.checkResourceIsReachable()) == true ? url : nil
    }

    var readiness: IngestReadiness {
        let destinationDrive = destination.map { source in
            IngestReadiness.Drive(name: source.name, isConnected: destinationRoot != nil,
                                  freeBytes: destinationRoot.flatMap { DiskSpace.availableBytes(for: $0) })
        }
        let backupDrive: IngestReadiness.Drive? = settings.backsUp ? {
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
        runTask?.cancel()
    }

    func pause() {
        isPaused = true
        Task { await runner?.pause() }
    }

    func resume() {
        isPaused = false
        Task { await runner?.resume() }
    }

    private func run(ids: Set<String>, freshPlan: Bool, copiesPrimary: Bool = true) {
        guard let destinationRoot, let destination else { return }
        phase = .running
        isPaused = false
        progress = IngestProgress(total: ids.count)
        let reader = self.reader
        let settings = self.settings
        let backupRoot = settings.backsUp ? self.backupRoot : nil
        let backupName = settings.backupFolder?.title ?? ""
        let chosen = items.filter { ids.contains($0.id) }
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
                onEvent: { event in await sink.model?.handle(event) }
            )
            self?.plan = plan
            self?.runner = runner
            let summary = await runner.run(only: ids, copiesPrimary: copiesPrimary, backsUp: backupRoot != nil)
            self?.finish(summary)
        }
    }

    private func handle(_ event: IngestEvent) async {
        activeRecorder?.handle(event)
        switch event {
        case .imported(let itemId):
            imported.insert(itemId)
            selection = IngestSelection(items: items, imported: imported, keeping: selection.checked)
            readSourceIfDue()
        case .progress(let progress):
            self.progress = progress
        case .fileVerified, .backedUp, .failed:
            break
        }
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
        let sources = dependencies.sources
        Task { await sources.read(sourceId: sourceId) }
    }

    private func finish(_ summary: IngestSummary) {
        lastSummary = summary
        runner = nil
        runTask = nil
        isPaused = false
        phase = .finished(summary)
        readSourceIfDue(force: true)
        let count = summary.imported.count
        if summary.canEject(backupEnabled: settings.backsUp) {
            // A card in Files can't be ejected from an app on iOS: say it is
            // safe to remove instead (plan Q3).
            dependencies.banner.show(IngestCopy.finishedBanner(count: count, card: card.name, ejected: false,
                                                               canRemove: settings.ejectsAfterImport))
        } else if summary.ending == .finished, summary.failed.isEmpty, !summary.backupIncomplete {
            dependencies.banner.show(IngestCopy.finishedBanner(count: count, card: card.name, ejected: false, canRemove: false))
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

    func model(for card: RememberedCard, root: URL, dependencies: AppDependencies) -> IngestModel {
        if let existing = models[card.id] { return existing }
        let model = IngestModel(card: card, root: root, dependencies: dependencies)
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
