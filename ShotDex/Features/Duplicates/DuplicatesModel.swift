import Foundation
import Photos
import SwiftUI

/// Payload for the compare cover opened from a duplicate group: the members
/// as `ComparePhoto`s, ready to render (DESIGN.md §10.5 — the item carries
/// its data, the cover never reads state back).
struct DuplicateComparePresentation: Identifiable {
    let id = UUID()
    let photos: [ComparePhoto]
}

/// Drives the Duplicates screen. Opening the screen reads the **cached**
/// groups of the last scan (`duplicate_groups`); hashing and regrouping only
/// happen when the user asks for a rescan — or once, automatically, when the
/// library has never been scanned. Marks for deletion are the user's own, per
/// group; nothing is pre-marked.
@MainActor
@Observable
final class DuplicatesModel {
    enum Phase: Equatable {
        case idle
        case loading
        case scanning(DuplicateScanProgress)
        case grouping
    }

    private let dependencies: AppDependencies
    private var photoLibrary: PhotoLibraryService { dependencies.photoLibrary }

    private(set) var phase: Phase = .loading
    private(set) var groups: [DuplicateGroup] = []
    private(set) var assetsById: [String: PHAsset] = [:]
    private(set) var coverage = PerceptualHashCoverage(hashedPhotos: 0, indexedPhotos: 0)
    /// Last grouping of the current strictness; `nil` until the first scan.
    private(set) var scanState: DuplicateScanState?
    /// Photos the next scan would hash — new or edited since the last one.
    private(set) var pendingCount = 0
    /// Members the user tapped to remove. Asset ids, so a mark survives a reload.
    var markedForDeletion: Set<String> = []
    var comparePresentation: DuplicateComparePresentation?
    var errorMessage: String?
    var isDeleting = false

    var strictness: DuplicateStrictness {
        didSet {
            guard strictness != oldValue else { return }
            UserDefaults.standard.set(strictness.rawValue, forKey: SettingsKeys.duplicateStrictness)
            loadCache()
        }
    }

    private var scanTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var hasLoadedOnce = false

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        let stored = UserDefaults.standard.string(forKey: SettingsKeys.duplicateStrictness)
        self.strictness = stored.flatMap(DuplicateStrictness.init(rawValue:)) ?? .similar
    }

    var isScanning: Bool {
        if case .scanning = phase { return true }
        return false
    }

    var isBusy: Bool { phase != .idle || isDeleting }

    /// The library has never been scanned at any strictness.
    var hasNeverScanned: Bool { scanState == nil && hasLoadedOnce && phase == .idle }

    var duplicatePhotoCount: Int { groups.reduce(0) { $0 + $1.count } }

    var markedBytes: Int {
        groups.lazy
            .flatMap(\.members)
            .filter { self.markedForDeletion.contains($0.assetId) }
            .reduce(0) { $0 + ($1.fileSize ?? 0) }
    }

    var markedCount: Int { markedForDeletion.count }

    // MARK: Load

    /// First appearance: show the cache, and kick off the one automatic scan
    /// if the library has never been scanned.
    func loadIfNeeded() {
        guard !hasLoadedOnce else { return }
        loadCache(autoScanIfNeverScanned: true)
    }

    /// Reads the cached groups of the current strictness off the main thread.
    func loadCache(autoScanIfNeverScanned: Bool = false) {
        guard !isScanning else { return }
        loadTask?.cancel()
        phase = .loading
        let store = dependencies.perceptualHashStore
        let strictness = self.strictness
        let retryingFailed = allowNetworkForScanning
        loadTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> CacheSnapshot? in
                guard let groups = try? store.cachedGroups(strictness: strictness) else {
                    // Never grouped at this strictness (or a read failure):
                    // report the rest so the screen can decide what to show.
                    return CacheSnapshot(
                        groups: nil,
                        assetsById: [:],
                        coverage: (try? store.coverage()) ?? PerceptualHashCoverage(hashedPhotos: 0, indexedPhotos: 0),
                        scanState: nil,
                        pendingCount: (try? store.pendingCount(retryingFailed: retryingFailed)) ?? 0
                    )
                }
                let ids = groups.flatMap { $0.members.map(\.assetId) }
                let assets = PhotoLibraryService.fetchAssets(ids: ids)
                return CacheSnapshot(
                    groups: groups,
                    assetsById: Dictionary(uniqueKeysWithValues: assets.map { ($0.localIdentifier, $0) }),
                    coverage: (try? store.coverage()) ?? PerceptualHashCoverage(hashedPhotos: 0, indexedPhotos: 0),
                    scanState: try? store.scanState(strictness: strictness),
                    pendingCount: (try? store.pendingCount(retryingFailed: retryingFailed)) ?? 0
                )
            }.value
            guard let self, !Task.isCancelled, let result else { return }
            self.hasLoadedOnce = true
            self.apply(result)
            if result.groups == nil, result.coverage.hashedPhotos > 0 {
                // Hashes exist but this strictness was never grouped (the
                // other one was) — grouping is cheap, do it now.
                await self.regroupAndCache(strictnesses: [strictness])
                self.loadCache()
                return
            }
            self.phase = .idle
            if autoScanIfNeverScanned, result.scanState == nil, result.coverage.hashedPhotos == 0 {
                self.startScan()
            }
        }
    }

    private struct CacheSnapshot: @unchecked Sendable {
        var groups: [DuplicateGroup]?
        var assetsById: [String: PHAsset]
        var coverage: PerceptualHashCoverage
        var scanState: DuplicateScanState?
        var pendingCount: Int
    }

    private func apply(_ snapshot: CacheSnapshot) {
        let groups = snapshot.groups ?? []
        // Members whose PHAsset is gone (deleted outside the app) drop out;
        // groups that fall to one member vanish.
        self.groups = groups.compactMap { group in
            let present = group.members.filter { snapshot.assetsById[$0.assetId] != nil }
            return present.count > 1 ? DuplicateGroup(members: present) : nil
        }
        assetsById = snapshot.assetsById
        coverage = snapshot.coverage
        scanState = snapshot.scanState
        pendingCount = snapshot.pendingCount
        let liveIds = Set(self.groups.flatMap { $0.members.map(\.assetId) })
        markedForDeletion = markedForDeletion.intersection(liveIds)
        UserDefaults.standard.set(self.groups.count, forKey: SettingsKeys.duplicateGroupCount)
    }

    /// Cheap refresh after the library changed: how many photos a rescan
    /// would cover. Never triggers a scan by itself.
    func refreshPendingCount() {
        guard hasLoadedOnce, !isScanning else { return }
        let store = dependencies.perceptualHashStore
        let retryingFailed = allowNetworkForScanning
        Task { [weak self] in
            let count = await Task.detached(priority: .utility) {
                (try? store.pendingCount(retryingFailed: retryingFailed)) ?? 0
            }.value
            self?.pendingCount = count
        }
    }

    // MARK: Scan

    /// Hashes what is new or edited, regroups **both** strictness levels, caches
    /// them, and reloads the current one.
    func startScan() {
        guard scanTask == nil, !isDeleting else { return }
        loadTask?.cancel()
        let pipeline = dependencies.duplicateScanPipeline
        let allowNetwork = allowNetworkForScanning
        phase = .scanning(DuplicateScanProgress(processed: 0, total: 0))
        scanTask = Task { [weak self] in
            defer { self?.scanTask = nil }
            do {
                let summary = try await pipeline.run(allowNetwork: allowNetwork) { progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.isScanning else { return }
                        self.phase = .scanning(progress)
                    }
                }
                guard let self else { return }
                if summary.didNotStart {
                    self.phase = .idle
                    return
                }
                await self.regroupAndCache(strictnesses: DuplicateStrictness.allCases)
                self.loadCache()
            } catch {
                guard let self else { return }
                self.phase = .idle
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    /// Same policy as indexing (`LibraryModel.allowNetworkForIndexing`): an
    /// unmetered path always, a metered one only on the cellular opt-in.
    private var allowNetworkForScanning: Bool {
        !dependencies.networkStatus.isExpensivePath
            || UserDefaults.standard.bool(forKey: SettingsKeys.allowCellularIndexing)
    }

    /// Groups every stored hash at each given strictness and writes the caches.
    private func regroupAndCache(strictnesses: [DuplicateStrictness]) async {
        phase = .grouping
        let store = dependencies.perceptualHashStore
        await Task.detached(priority: .userInitiated) {
            guard let photos = try? store.hashedPhotos() else { return }
            let now = Date()
            for strictness in strictnesses {
                let groups = DuplicateGrouper.groups(from: photos, strictness: strictness)
                try? store.replaceGroups(groups, strictness: strictness, scannedAt: now)
            }
        }.value
    }

    // MARK: Marks

    func isMarked(_ assetId: String) -> Bool {
        markedForDeletion.contains(assetId)
    }

    func toggleMark(_ assetId: String) {
        if markedForDeletion.contains(assetId) {
            markedForDeletion.remove(assetId)
        } else {
            markedForDeletion.insert(assetId)
        }
    }

    /// Marks every other member of `group` — the fast path for "this is the
    /// one I keep".
    func keepOnly(_ assetId: String, in group: DuplicateGroup) {
        for member in group.members {
            if member.assetId == assetId {
                markedForDeletion.remove(member.assetId)
            } else {
                markedForDeletion.insert(member.assetId)
            }
        }
    }

    func clearMarks(in group: DuplicateGroup) {
        for member in group.members {
            markedForDeletion.remove(member.assetId)
        }
    }

    func clearAllMarks() {
        markedForDeletion.removeAll()
    }

    func markedCount(in group: DuplicateGroup) -> Int {
        group.members.filter { markedForDeletion.contains($0.assetId) }.count
    }

    // MARK: Compare

    func canCompare(_ group: DuplicateGroup) -> Bool {
        group.count >= CompareScreen.minPhotoCount
    }

    /// Opens the group in the compare screen, where each pane carries its own
    /// trash toggle bound to `markedForDeletion`.
    func compare(_ group: DuplicateGroup) {
        guard canCompare(group) else { return }
        let ids = group.members.map(\.assetId)
        let metadata = (try? dependencies.database.reader.read { db in
            try PhotoMetadata.fetchAll(db, keys: ids)
        }) ?? []
        let metadataById = Dictionary(uniqueKeysWithValues: metadata.map { ($0.assetId, $0) })
        let photos = ids.compactMap { id -> ComparePhoto? in
            guard let asset = assetsById[id] else { return nil }
            return ComparePhoto(metadata: metadataById[id], asset: asset)
        }
        guard photos.count >= 2 else { return }
        comparePresentation = DuplicateComparePresentation(photos: photos)
    }

    // MARK: Delete

    /// Deletes the marked photos through PhotoKit (system confirmation, then
    /// Recently Deleted) and prunes the local rows — metadata, hash and group
    /// cache — so the groups update at once. A cancelled system dialog keeps
    /// the marks. Returns whether anything was deleted.
    @discardableResult
    func deleteMarked() async -> Bool {
        let ids = markedForDeletion
        let assets = ids.compactMap { assetsById[$0] }
        guard !assets.isEmpty, !isDeleting else { return false }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await photoLibrary.deleteAssets(assets)
        } catch let error as PHPhotosError where error.code == .userCancelled {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
        let idList = Array(ids)
        try? dependencies.metadataStore.deleteAssets(ids: idList)
        try? dependencies.perceptualHashStore.delete(assetIds: idList)
        try? dependencies.perceptualHashStore.removeFromGroups(assetIds: idList)
        for id in ids {
            assetsById.removeValue(forKey: id)
        }
        groups = groups.compactMap { group in
            let remaining = group.members.filter { !ids.contains($0.assetId) }
            return remaining.count > 1 ? DuplicateGroup(members: remaining) : nil
        }
        markedForDeletion.removeAll()
        UserDefaults.standard.set(groups.count, forKey: SettingsKeys.duplicateGroupCount)
        return true
    }
}
