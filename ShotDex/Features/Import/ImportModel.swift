import Foundation

/// Drives the import screen: folder scan → browse/filter → import. Owns the
/// candidate list, the (smart-album-style) filter query, the RAW toggle, the
/// selection, and the two background jobs (EXIF scan, import). The heavy IO
/// lives in `ImportService`; this only orchestrates and publishes state.
@MainActor
@Observable
final class ImportModel {
    enum Phase: Equatable {
        case pickFolder     // no folder chosen yet
        case scanning       // enumerating files
        case browsing       // grid + filter
        case importing      // copying selected files into Photos
        case done           // import finished (summary)
    }

    @ObservationIgnored
    private let service: ImportService

    private(set) var phase: Phase = .pickFolder
    private(set) var folderName: String?
    private(set) var candidates: [ImportCandidate] = []
    private(set) var scanError: String?

    /// Advanced (camera/lens/ISO/…) filter, identical model to smart albums.
    var query = SmartAlbumQuery(matchMode: .all, rules: [])
    /// Quick default: hide RAW/DNG so only JPEG/HEIC show — the core need.
    var hideRaw = true

    /// Selected candidate ids (by file path). Hidden-by-filter items stay in
    /// the set but never import — `importTargets` intersects with what's shown.
    var selectedIds: Set<String> = []

    // Background EXIF scan progress.
    private(set) var exifScanned = 0
    private(set) var isExifScanComplete = false

    // Import progress / result.
    private(set) var importTotal = 0
    private(set) var importDone = 0
    private(set) var importedCount = 0
    private(set) var importFailures: [String] = []

    // Filter-option lists feeding the rule builder (from scanned metadata).
    private(set) var availableBrands: [String] = []
    private(set) var availableBodies: [String] = []
    private(set) var availableLenses: [String] = []

    @ObservationIgnored private var scopedURL: URL?
    @ObservationIgnored private var exifTask: Task<Void, Never>?
    @ObservationIgnored private var importTask: Task<Void, Never>?

    init(service: ImportService) {
        self.service = service
    }

    // MARK: Derived

    var rawCount: Int { candidates.lazy.filter(\.isRaw).count }

    /// Candidates shown in the grid: RAW toggle then the advanced query.
    var visibleCandidates: [ImportCandidate] {
        candidates.filter { candidate in
            if hideRaw && candidate.isRaw { return false }
            return query.matches(candidate.metadata)
        }
    }

    /// How many currently-visible candidates are selected (what Import copies).
    var importableCount: Int {
        visibleCandidates.reduce(0) { $0 + (selectedIds.contains($1.id) ? 1 : 0) }
    }

    // MARK: Folder scan

    func scanFolder(at url: URL) {
        exifTask?.cancel()
        // Release any previously-scoped folder before scoping the new one.
        releaseScopedAccess()
        scopedURL = url.startAccessingSecurityScopedResource() ? url : nil

        folderName = url.lastPathComponent
        phase = .scanning
        scanError = nil
        exifScanned = 0
        isExifScanComplete = false
        candidates = []
        selectedIds = []
        query = SmartAlbumQuery(matchMode: .all, rules: [])

        let composer = service.makeComposer()
        let service = self.service
        Task {
            do {
                let found = try await Task.detached(priority: .userInitiated) {
                    try service.scanFolder(at: url, using: composer)
                }.value
                guard !Task.isCancelled else { return }
                candidates = found
                phase = .browsing
                startExifScan(composer: composer)
            } catch {
                releaseScopedAccess()
                scanError = "Couldn't read this folder. Plug in the card and pick its DCIM folder, then try again."
                phase = .pickFolder
            }
        }
    }

    /// Reads EXIF for every candidate off the main actor, upgrading each
    /// placeholder to a full row so camera/lens/ISO filters become accurate.
    /// The task group's closure is nonisolated, so all state mutation hops
    /// back to the main actor through `applyMetadata` / `finishExifScan`.
    private func startExifScan(composer: MetadataComposer) {
        let service = self.service
        let snapshot = candidates
        exifTask = Task { [weak self] in
            await withTaskGroup(of: (Int, PhotoMetadata).self) { group in
                let concurrency = 8
                var next = 0
                func schedule(_ index: Int) {
                    let candidate = snapshot[index]
                    group.addTask(priority: .utility) {
                        (index, service.fullMetadata(for: candidate, using: composer))
                    }
                }
                while next < min(concurrency, snapshot.count) { schedule(next); next += 1 }

                var buffer: [(Int, PhotoMetadata)] = []
                var processed = 0
                for await result in group {
                    if Task.isCancelled { break }
                    buffer.append(result)
                    processed += 1
                    // Apply (and publish progress) in batches so a large card
                    // doesn't re-render the grid once per file.
                    if buffer.count >= 25 {
                        await self?.applyMetadata(buffer, snapshot: snapshot, scanned: processed)
                        buffer.removeAll(keepingCapacity: true)
                    }
                    if next < snapshot.count { schedule(next); next += 1 }
                }
                await self?.applyMetadata(buffer, snapshot: snapshot, scanned: processed)
            }
            if Task.isCancelled { return }
            await self?.finishExifScan()
        }
    }

    /// Writes a batch of freshly-read rows onto the matching candidates and
    /// publishes scan progress. Indices are validated against `snapshot` so a
    /// mid-scan folder change can't misalign the array.
    private func applyMetadata(_ batch: [(Int, PhotoMetadata)], snapshot: [ImportCandidate], scanned: Int) {
        for (index, meta) in batch
        where index < candidates.count && candidates[index].id == snapshot[index].id {
            candidates[index].metadata = meta
        }
        exifScanned = scanned
    }

    private func finishExifScan() {
        isExifScanComplete = true
        refreshFilterOptions()
    }

    private func refreshFilterOptions() {
        var brands: Set<String> = [], bodies: Set<String> = [], lenses: Set<String> = []
        for candidate in candidates {
            if let value = candidate.metadata.normalizedCameraManufacturer, !value.isEmpty { brands.insert(value) }
            if let value = candidate.metadata.normalizedCameraModel, !value.isEmpty { bodies.insert(value) }
            if let value = candidate.metadata.normalizedLensModel, !value.isEmpty { lenses.insert(value) }
        }
        availableBrands = brands.sorted()
        availableBodies = bodies.sorted()
        availableLenses = lenses.sorted()
    }

    // MARK: Selection

    func isSelected(_ id: String) -> Bool { selectedIds.contains(id) }

    func toggle(_ id: String) {
        if selectedIds.contains(id) { selectedIds.remove(id) } else { selectedIds.insert(id) }
    }

    func selectAllVisible() { selectedIds = Set(visibleCandidates.map(\.id)) }

    func clearSelection() { selectedIds.removeAll() }

    // MARK: Import

    func startImport() {
        let targets = visibleCandidates.filter { selectedIds.contains($0.id) }
        guard !targets.isEmpty else { return }
        phase = .importing
        importTotal = targets.count
        importDone = 0
        importedCount = 0
        importFailures = []
        let service = self.service
        importTask = Task {
            for candidate in targets {
                if Task.isCancelled { break }
                do {
                    _ = try await service.importAsset(candidate)
                    importedCount += 1
                } catch {
                    importFailures.append(candidate.filename)
                }
                importDone += 1
            }
            phase = .done
        }
    }

    // MARK: Teardown

    /// Cancels background work and relinquishes the security-scoped folder.
    /// Called when the import screen is dismissed.
    func teardown() {
        exifTask?.cancel()
        importTask?.cancel()
        releaseScopedAccess()
    }

    private func releaseScopedAccess() {
        if let scopedURL {
            scopedURL.stopAccessingSecurityScopedResource()
            self.scopedURL = nil
        }
    }
}
