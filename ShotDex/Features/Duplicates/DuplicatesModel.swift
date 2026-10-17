import Foundation
import Photos
import SwiftUI
import UniformTypeIdentifiers

/// An alert the Duplicates screen owes the user: a merge that failed for some
/// groups, or a Delete that would have emptied a group.
struct DuplicateNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// Payload for the viewer opened in Compare on a duplicate group (DESIGN.md
/// §10.5 — the item carries its data, the cover never reads state back).
struct DuplicateComparePresentation: Identifiable {
    let id = UUID()
    let source: PhotoListModel
    let request: CompareRequest
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
    /// Last grouping; `nil` until the first scan.
    private(set) var scanState: DuplicateScanState?
    /// Photos the next scan would hash — new or edited since the last one.
    private(set) var pendingCount = 0
    /// The user's marks and decisions; lives in `AppDependencies` so it
    /// outlasts this model (FS-06.06b §1).
    let session: DuplicateReviewSession
    /// Edited / RAW / Live / favourite per member, read per card as it appears.
    private(set) var traits: [String: DuplicateMemberTraits] = [:]
    /// What the scoring pass measured, per member (FS-06.06 §6).
    private(set) var scores: [String: DuplicateQualityScore] = [:]
    /// The scoring pass's progress while it runs; `nil` when idle.
    private(set) var scoring: DuplicateScoringProgress?
    @ObservationIgnored private var scoringTask: Task<Void, Never>?
    /// Which `startScoring` the running task belongs to: an older task that
    /// finishes late must not clear a newer one's state.
    @ObservationIgnored private var scoringGeneration = 0
    /// Exposure read by the pass since the last cache read: a regroup-free
    /// reload picks up brackets once the pass ends.
    @ObservationIgnored private var scoringReadExposure = false
    private var traitsRequested: Set<String> = []
    var comparePresentation: DuplicateComparePresentation?
    /// The Bursts tab (FS-06.06 §7b) — not a kind of group: it
    /// lists real bursts from PhotoKit and needs no scan.
    var showsBursts = false
    /// The comparison on screen, kept past its dismissal for `didCloseCompare`.
    @ObservationIgnored private var openCompare: DuplicateComparePresentation?
    var errorMessage: String?
    /// Title + message of the alert raised when Merge could not write some
    /// groups, or Delete would empty a group.
    var notice: DuplicateNotice?
    var isConfirmingMerge = false
    var isDeleting = false
    private(set) var isMerging = false
    /// Group whose last unmarked photo the user just tried to mark; the card
    /// shows "Keep at least one photo in this group." for a moment.
    private(set) var blockedGroupId: String?
    private var blockedResetTask: Task<Void, Never>?

    /// Asset ids marked for deletion — what Compare binds to.
    var markedForDeletion: Set<String> { session.marks }

    var sort: DuplicateSort {
        didSet {
            guard sort != oldValue else { return }
            UserDefaults.standard.set(sort.rawValue, forKey: SettingsKeys.duplicateSort)
        }
    }

    /// The kind the list is filtered to; `nil` is All. Filtering changes
    /// which cards show, never the marks or the Delete count (06b §1).
    var kindFilter: DuplicateKind? {
        didSet {
            guard kindFilter != oldValue else { return }
            UserDefaults.standard.set(kindFilter?.rawValue ?? "", forKey: SettingsKeys.duplicateKindFilter)
        }
    }

    private var scanTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var hasLoadedOnce = false

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        self.session = dependencies.duplicateReview
        let stored = UserDefaults.standard.string(forKey: SettingsKeys.duplicateKindFilter)
        self.kindFilter = stored.flatMap(DuplicateKind.init(rawValue:))
        let storedSort = UserDefaults.standard.string(forKey: SettingsKeys.duplicateSort)
        self.sort = storedSort.flatMap(DuplicateSort.init(rawValue:)) ?? .easiestFirst
    }

    var isScanning: Bool {
        if case .scanning = phase { return true }
        return false
    }

    var isBusy: Bool { phase != .idle || isDeleting || isMerging }

    /// The library has never been scanned.
    var hasNeverScanned: Bool { scanState == nil && hasLoadedOnce && phase == .idle }

    var duplicatePhotoCount: Int { groups.reduce(0) { $0 + $1.count } }

    /// Every mark that is in a group — whatever the filter shows (06b §1,
    /// AC-M5). A mark on a photo no longer in any group waits until it is.
    var scopedMarks: Set<String> {
        let marks = session.marks
        guard !marks.isEmpty else { return [] }
        var scoped: Set<String> = []
        for group in groups {
            for member in group.members where marks.contains(member.assetId) {
                scoped.insert(member.assetId)
            }
        }
        return scoped
    }

    var markedBytes: Int {
        let scoped = scopedMarks
        var seen: Set<String> = []
        var bytes = 0
        for member in groups.lazy.flatMap(\.members)
        where scoped.contains(member.assetId) && seen.insert(member.assetId).inserted {
            bytes += member.fileSize ?? 0
        }
        return bytes
    }

    var markedCount: Int { scopedMarks.count }

    // MARK: Review

    /// Groups of the kind the filter shows, in the order the sort menu asks for.
    var sortedGroups: [DuplicateGroup] {
        let shown = kindFilter.map { kind in groups.filter { $0.kind == kind } } ?? groups
        return DuplicateReview.sorted(shown, by: sort, freeBytes: { self.freeBytes(of: $0) ?? 0 }) { group in
            self.keeper(of: group).map { DuplicateReview.scoreGap(group, keeper: $0, scores: self.scores) } ?? 0
        }
    }

    /// Kinds that have at least one group, in filter-row order.
    var presentKinds: [DuplicateKind] {
        let kinds = Set(groups.map(\.kind))
        return DuplicateKind.allCases.filter(kinds.contains)
    }

    /// The member the card puts big with "Keep": the user's pick, else the
    /// suggestion.
    func keeper(of group: DuplicateGroup) -> HashedPhoto? {
        if let picked = session.keeper(among: group.members.map(\.assetId)),
           let member = group.members.first(where: { $0.assetId == picked }) {
            return member
        }
        return DuplicateReview.keeper(of: group.members, traits: traits, scores: scores)
    }

    /// Bytes freed by keeping only the keeper. `nil` for a bracket or focus
    /// stack: raw material never counts toward "~GB to free" (§5).
    func freeBytes(of group: DuplicateGroup) -> Int? {
        guard group.sourceSet == nil, let keeper = keeper(of: group) else { return nil }
        return DuplicateReview.freeBytes(members: group.members, keeper: keeper)
    }

    func reasons(for group: DuplicateGroup) -> [DuplicateKeepReason] {
        guard let keeper = keeper(of: group) else { return [] }
        return DuplicateReview.reasons(keeper: keeper, members: group.members, traits: traits, scores: scores)
    }

    /// Up to two lines inside a copy: what it lacks, where it is from, what
    /// was shot differently (§7.4). Empty for the keeper.
    func caption(of member: HashedPhoto, in group: DuplicateGroup) -> [String] {
        guard let keeper = keeper(of: group), keeper.assetId != member.assetId else { return [] }
        if group.sourceSet != nil {
            return DuplicateReview.settings(of: member, members: group.members).map { [$0] } ?? []
        }
        return DuplicateReview.caption(of: member, keeper: keeper, members: group.members, traits: traits, scores: scores)
    }

    func traits(of assetId: String) -> DuplicateMemberTraits {
        traits[assetId] ?? DuplicateMemberTraits(isFavorite: assetsById[assetId]?.isFavorite ?? false)
    }

    func isKeptAll(_ group: DuplicateGroup) -> Bool {
        session.isKeptAll(group.memberIds)
    }

    /// Decided = something in it is marked, or the user kept it whole.
    func isReviewed(_ group: DuplicateGroup) -> Bool {
        isKeptAll(group) || markedCount(in: group) > 0
    }

    func isCollapsed(_ group: DuplicateGroup) -> Bool {
        session.isCollapsed(group.memberIds) && isReviewed(group)
    }

    var reviewedCount: Int { groups.filter(isReviewed).count }

    /// "~96 MB to free" in the header: what keeping one per group would free.
    var totalFreeBytes: Int {
        groups.reduce(0) { $0 + (freeBytes(of: $1) ?? 0) }
    }

    /// Every member of the group carries a mark — possible when marks made
    /// before a regroup fill a group of this one (§1).
    func isFullyMarked(_ group: DuplicateGroup) -> Bool {
        group.members.allSatisfy { session.marks.contains($0.assetId) }
    }

    func expand(_ group: DuplicateGroup) {
        session.setCollapsed(group.memberIds, false)
    }

    /// What Remove the other N would mark: every member but the keeper,
    /// minus favorites, edits and album photos (A2).
    func removal(in group: DuplicateGroup) -> DuplicateRemoval? {
        guard let keeper = keeper(of: group) else { return nil }
        return DuplicateRemoval.plan(members: group.members, keeper: keeper, traits: traits)
    }

    /// "Remove the other N": marks what `removal(in:)` names, then folds.
    func markOthers(in group: DuplicateGroup) {
        guard let removal = removal(in: group), !removal.remove.isEmpty else { return }
        session.setMarks(of: group.members.map(\.assetId), to: Set(removal.remove))
        session.setKeptAll(group.memberIds, false)
        session.setCollapsed(group.memberIds, true)
    }

    /// "Unmark": drops every mark in the group, and the group is open again.
    func unmark(_ group: DuplicateGroup) {
        clearMarks(in: group)
        session.setCollapsed(group.memberIds, false)
    }

    /// "Keep all" toggles: on, it clears the group's marks and folds it as
    /// "Keeping all N"; off, the group is undecided again.
    func toggleKeepAll(_ group: DuplicateGroup) {
        let members = group.memberIds
        if session.isKeptAll(members) {
            session.setKeptAll(members, false)
            session.setCollapsed(members, false)
        } else {
            clearMarks(in: group)
            session.setKeptAll(members, true)
            session.setCollapsed(members, true)
        }
    }

    /// Reads edited / RAW / Live for the members of a group not read yet —
    /// once per member per screen, off the main thread, local resources only.
    func loadTraits(for group: DuplicateGroup) {
        let missing = group.members.map(\.assetId).filter { !traitsRequested.contains($0) }
        guard !missing.isEmpty else { return }
        traitsRequested.formUnion(missing)
        let assets = missing.compactMap { assetsById[$0] }
        Task { [weak self] in
            let read = await Task.detached(priority: .userInitiated) {
                Self.readTraits(assets)
            }.value
            self?.traits.merge(read) { _, new in new }
        }
    }

    /// Same as `loadTraits(for:)` for many groups at once, awaited — Merge
    /// needs the edited flag of every member before it picks keepers.
    private func loadAllTraits(_ groups: [DuplicateGroup]) async {
        let missing = groups.flatMap { $0.members.map(\.assetId) }.filter { traits[$0] == nil }
        guard !missing.isEmpty else { return }
        traitsRequested.formUnion(missing)
        let assets = missing.compactMap { assetsById[$0] }
        let read = await Task.detached(priority: .userInitiated) {
            Self.readTraits(assets)
        }.value
        traits.merge(read) { _, new in new }
    }

    /// Titles of the albums the user made that hold `asset` — not smart
    /// albums, not shared ones the user cannot edit.
    nonisolated private static func userAlbums(containing asset: PHAsset) -> [String] {
        let albums = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil)
        var titles: [String] = []
        albums.enumerateObjects { album, _, _ in
            if album.assetCollectionSubtype == .albumRegular, let title = album.localizedTitle { titles.append(title) }
        }
        return titles.sorted()
    }

    nonisolated private static func readTraits(_ assets: [PHAsset]) -> [String: DuplicateMemberTraits] {
        var result: [String: DuplicateMemberTraits] = [:]
        for asset in assets {
            let resources = PHAssetResource.assetResources(for: asset)
            let hasRAW = resources.contains { resource in
                UTType(resource.uniformTypeIdentifier)?.conforms(to: .rawImage) == true
            }
            result[asset.localIdentifier] = DuplicateMemberTraits(
                isEdited: resources.contains { $0.type == .adjustmentData },
                hasRAW: hasRAW,
                isLive: asset.mediaSubtypes.contains(.photoLive),
                isFavorite: asset.isFavorite,
                albums: userAlbums(containing: asset)
            )
        }
        return result
    }

    // MARK: Load

    /// First appearance: show the cache, and kick off the one automatic scan
    /// if the library has never been scanned.
    func loadIfNeeded() {
        guard !hasLoadedOnce else { return }
        loadCache(autoScanIfNeverScanned: true)
    }

    /// Reads the cached groups off the main thread.
    func loadCache(autoScanIfNeverScanned: Bool = false) {
        guard !isScanning else { return }
        loadTask?.cancel()
        phase = .loading
        let store = dependencies.perceptualHashStore
        let qualityStore = DuplicateQualityStore(database: dependencies.database)
        let retryingFailed = allowNetworkForScanning
        loadTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> CacheSnapshot? in
                guard let groups = try? store.cachedGroups() else {
                    // Never grouped (or a read failure):
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
                    scanState: try? store.scanState(),
                    pendingCount: (try? store.pendingCount(retryingFailed: retryingFailed)) ?? 0,
                    scores: (try? qualityStore.scores(for: ids)) ?? [:]
                )
            }.value
            guard let self, !Task.isCancelled, let result else { return }
            self.hasLoadedOnce = true
            self.apply(result)
            if result.groups == nil, result.coverage.hashedPhotos > 0 {
                // Hashes exist but were never grouped (a scan from before
                // kinds) — grouping is cheap, do it now.
                await self.regroupAndCache()
                self.loadCache()
                return
            }
            self.phase = .idle
            if autoScanIfNeverScanned, result.scanState == nil, result.coverage.hashedPhotos == 0 {
                self.startScan()
            } else {
                // The groups may have changed under a running pass.
                self.stopScoring()
                self.startScoring()
            }
        }
    }

    /// Built on a detached task and handed to the main actor once, never
    /// touched again off it: `PHAsset` is immutable, just not marked Sendable.
    private struct CacheSnapshot: @unchecked Sendable {
        var groups: [DuplicateGroup]?
        var assetsById: [String: PHAsset]
        var coverage: PerceptualHashCoverage
        var scanState: DuplicateScanState?
        var pendingCount: Int
        var scores: [String: DuplicateQualityScore] = [:]
    }

    private func apply(_ snapshot: CacheSnapshot) {
        let groups = snapshot.groups ?? []
        // Members whose PHAsset is gone (deleted outside the app) drop out;
        // groups that fall to one member vanish.
        self.groups = groups.compactMap { group in
            let present = group.members.filter { snapshot.assetsById[$0.assetId] != nil }
            return present.count > 1 ? DuplicateGroup(members: present, kind: group.kind, sourceSet: group.sourceSet) : nil
        }
        assetsById = snapshot.assetsById
        coverage = snapshot.coverage
        scanState = snapshot.scanState
        pendingCount = snapshot.pendingCount
        scores = snapshot.scores
        // Marks are not cut on reload (§1): marks are per photo, and a regroup
        // that moves a photo keeps its mark.
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

    /// Hashes what is new or edited, regroups, caches, and reloads.
    func startScan() {
        guard scanTask == nil, !isDeleting else { return }
        loadTask?.cancel()
        stopScoring()
        let pipeline = dependencies.duplicateScanPipeline
        let allowNetwork = allowNetworkForScanning
        phase = .scanning(DuplicateScanProgress(processed: 0, total: 0))
        // Built outside the task, so it captures `self` weakly once instead of
        // reading the task's own captured `self` from another concurrency
        // domain every time the pipeline reports — which Swift 6 rejects.
        let report: @Sendable (DuplicateScanProgress) -> Void = { [weak self] progress in
            Task { @MainActor in
                guard let self, self.isScanning else { return }
                self.phase = .scanning(progress)
            }
        }
        scanTask = Task { [weak self] in
            defer { self?.scanTask = nil }
            do {
                let summary = try await pipeline.run(allowNetwork: allowNetwork, onProgress: report)
                guard let self else { return }
                if summary.didNotStart {
                    self.phase = .idle
                    return
                }
                await self.regroupAndCache()
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
        stopScoring()
    }

    // MARK: Scoring

    /// The group is waiting for the pass: its chip reads "Checking
    /// sharpness…" instead of a reason (§3 step 5).
    func isChecking(_ group: DuplicateGroup) -> Bool {
        scoring != nil && group.kind != .screenshots && !DuplicateReview.isScored(group.members, scores)
    }

    /// Scores grouped photos that lack a score. Each batch lands in the
    /// cards at once; when the pass ends, the cache is read again so
    /// brackets the new exposure readings reveal show as source sets.
    func startScoring() {
        guard scoringTask == nil, !groups.isEmpty else { return }
        scoringGeneration += 1
        let token = scoringGeneration
        let pass = dependencies.duplicateQualityPass
        let groups = self.groups
        let allowNetwork = allowNetworkForScanning
        scoring = DuplicateScoringProgress(processed: 0, total: 0)
        let report: @Sendable ([DuplicateQualityRecord], DuplicateScoringProgress) -> Void = { [weak self] records, progress in
            Task { @MainActor in
                guard let self, self.scoringGeneration == token else { return }
                // Scores land even after a stop: they are on disk already.
                for record in records { self.scores[record.assetId] = record.score }
                if records.contains(where: { $0.exposureBias != nil }) { self.scoringReadExposure = true }
                if self.scoringTask != nil { self.scoring = progress }
            }
        }
        scoringTask = Task { [weak self] in
            try? await pass.run(groups: groups, allowNetwork: allowNetwork, onBatch: report)
            guard let self, self.scoringGeneration == token else { return }
            let reload = self.scoringReadExposure && !Task.isCancelled
            self.scoringTask = nil
            self.scoring = nil
            self.scoringReadExposure = false
            if reload { self.loadCache() }
        }
    }

    /// Leaving the screen or cancelling: what was scored is kept (AC-Q5).
    func stopScoring() {
        scoringTask?.cancel()
        scoringTask = nil
        scoring = nil
    }

    /// Same policy as indexing (`LibraryModel.allowNetworkForIndexing`): an
    /// unmetered path always, a metered one only on the cellular opt-in.
    private var allowNetworkForScanning: Bool {
        !dependencies.networkStatus.isExpensivePath
            || UserDefaults.standard.bool(forKey: SettingsKeys.allowCellularIndexing)
    }

    /// Groups every stored hash once, into kinds, and writes the cache.
    private func regroupAndCache() async {
        phase = .grouping
        let store = dependencies.perceptualHashStore
        await Task.detached(priority: .userInitiated) {
            guard let photos = try? store.hashedPhotos() else { return }
            try? store.replaceGroups(DuplicateGrouper.groups(from: photos), scannedAt: Date())
        }.value
    }

    // MARK: Marks

    func isMarked(_ assetId: String) -> Bool {
        markedForDeletion.contains(assetId)
    }

    /// Whether marking `assetId` would leave its group with nothing to keep.
    func isLastUnmarked(_ assetId: String, in group: DuplicateGroup) -> Bool {
        !session.isMarked(assetId)
            && group.members.allSatisfy { $0.assetId == assetId || session.isMarked($0.assetId) }
    }

    /// Marks or unmarks one tile. Returns `false` — and changes nothing — when
    /// the tile is the group's last unmarked photo (§1): a group is never
    /// marked whole from this screen.
    @discardableResult
    func toggleMark(_ assetId: String, in group: DuplicateGroup) -> Bool {
        if session.isMarked(assetId) {
            session.setMarked([assetId], false)
            if markedCount(in: group) == 0 { session.setCollapsed(group.memberIds, false) }
            return true
        }
        guard !isLastUnmarked(assetId, in: group) else {
            showBlocked(group)
            return false
        }
        session.setMarked([assetId], true)
        session.setKeptAll(group.memberIds, false)
        return true
    }

    private func showBlocked(_ group: DuplicateGroup) {
        blockedGroupId = group.id
        blockedResetTask?.cancel()
        blockedResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.blockedGroupId = nil
        }
    }

    /// Keep Only This: the picked member becomes the group's keeper and every
    /// other member is marked — the fast path for "this is the one I keep".
    func keepOnly(_ assetId: String, in group: DuplicateGroup) {
        let ids = group.members.map(\.assetId)
        session.setKeeper(assetId, groupMembers: ids)
        session.setMarks(of: ids, to: group.memberIds.subtracting([assetId]))
        session.setKeptAll(group.memberIds, false)
    }

    func clearMarks(in group: DuplicateGroup) {
        session.setMarked(group.members.map(\.assetId), false)
    }

    /// Clear Selection in ⋯: every mark and decision in the list.
    func clearAllMarks() {
        for group in groups {
            clearMarks(in: group)
            session.setKeptAll(group.memberIds, false)
            session.setCollapsed(group.memberIds, false)
        }
    }

    // MARK: Merge

    /// Merge is only offered on Copies: a look-alike or a frame of a moment
    /// is not the same picture, and copying a date across would be wrong.
    /// (v2 path; task 23 replaces it with inheritance at delete time.)
    var canMerge: Bool { groups.contains { $0.kind == .copies } }

    /// Folds every Exact group down to one photo, the way Photos' own Merge
    /// does: the keeper (D3) inherits anything its copies have and it lacks —
    /// the favourite flag, a location, the earliest capture date — and only
    /// once that is saved are the rest marked. A group whose write fails is
    /// left unmarked, the others go on, and one alert names the failures.
    func mergeAll() async {
        guard canMerge, !isBusy else { return }
        isMerging = true
        defer { isMerging = false }
        let groups = self.groups.filter { $0.kind == .copies }
        await loadAllTraits(groups)
        var failures: [Error] = []
        for group in groups {
            guard let keeper = DuplicateReview.keeper(of: group.members, traits: traits),
                  let keeperAsset = assetsById[keeper.assetId]
            else { continue }
            let others = group.members
                .filter { $0.assetId != keeper.assetId }
                .compactMap { assetsById[$0.assetId] }
            do {
                try await adoptMetadata(into: keeperAsset, from: others)
            } catch {
                failures.append(error)
                continue
            }
            session.setKeeper(keeper.assetId, groupMembers: group.members.map(\.assetId))
            markOthers(in: group)
        }
        if let first = failures.first {
            let count = failures.count
            notice = DuplicateNotice(
                title: count == 1
                    ? String(localized: "Couldn't Merge 1 Group", comment: "Duplicates: Merge failed for one group")
                    : String(localized: "Couldn't Merge \(count) Groups", comment: "Duplicates: Merge failed for several groups"),
                message: first.localizedDescription + " "
                    + String(localized: "Their photos are not marked.", comment: "Duplicates: after a failed merge, nothing in the failed groups is marked")
            )
        }
    }

    /// Gives `keeper` the facts its duplicates have and it does not. Throws
    /// when Photos refuses the change, so the caller leaves that group alone.
    private func adoptMetadata(into keeper: PHAsset, from others: [PHAsset]) async throws {
        let shouldFavorite = !keeper.isFavorite && others.contains { $0.isFavorite }
        let adoptedLocation = keeper.location == nil
            ? others.compactMap(\.location).first
            : nil
        // Earliest wins: a re-saved copy carries the date it was re-saved, and
        // the original moment is the one worth keeping.
        let earliest = ([keeper] + others).compactMap(\.creationDate).min()
        let adoptedDate = earliest.flatMap { $0 < (keeper.creationDate ?? .distantFuture) ? $0 : nil }

        guard shouldFavorite || adoptedLocation != nil || adoptedDate != nil else { return }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest(for: keeper)
            if shouldFavorite { request.isFavorite = true }
            if let adoptedLocation { request.location = adoptedLocation }
            if let adoptedDate { request.creationDate = adoptedDate }
        }
        if shouldFavorite {
            try? dependencies.metadataStore.updateFavorite(
                assetId: keeper.localIdentifier, isFavorite: true
            )
        }
        if let adoptedLocation {
            try? dependencies.metadataStore.updateLocation(
                assetIds: [keeper.localIdentifier],
                latitude: adoptedLocation.coordinate.latitude,
                longitude: adoptedLocation.coordinate.longitude
            )
        }
        if let adoptedDate {
            try? dependencies.metadataStore.updateCreationDate(
                assetIds: [keeper.localIdentifier], date: adoptedDate
            )
        }
    }

    func markedCount(in group: DuplicateGroup) -> Int {
        group.members.filter { session.marks.contains($0.assetId) }.count
    }

    // MARK: Compare

    func canCompare(_ group: DuplicateGroup) -> Bool {
        group.count >= CompareSession.minimumCount
    }

    /// Opens the group in the viewer's Compare (FS-01.08c §7). Reject there
    /// is the real flag; the keep-one gate rides along with the group.
    func compare(_ group: DuplicateGroup) {
        guard canCompare(group) else { return }
        let ids = group.members.map(\.assetId).filter { assetsById[$0] != nil }
        let source = PhotoListModel(assetIds: ids, dependencies: dependencies)
        source.load()
        guard var request = CompareRequest(selection: ids, source: source, duplicateGroup: ids) else { return }
        request.onDeleted = { [weak self] gone in self?.didDelete(ids: gone) }
        // Compare speaks only in flags (plan K2): this group's marks become
        // Reject before it opens, so the frames show what the tiles showed.
        let marked = ids.filter { session.isMarked($0) && dependencies.photoMarks.flag(for: $0) != .reject }
        Task {
            if !marked.isEmpty { _ = await dependencies.photoMarks.setFlag(.reject, ids: marked) }
            let presentation = DuplicateComparePresentation(source: source, request: request)
            openCompare = presentation
            comparePresentation = presentation
        }
    }

    /// Back from Compare: the group's tiles take what its flags say now — a
    /// Reject set there marks the tile, one taken back unmarks it
    /// (FS-01.08c AC-17).
    func didCloseCompare() {
        guard let presentation = openCompare else { return }
        openCompare = nil
        let ids = presentation.request.ids.filter { assetsById[$0] != nil }
        let rejected = ids.filter { dependencies.photoMarks.flag(for: $0) == .reject }
        session.setMarks(of: ids, to: Set(rejected))
        if let group = groups.first(where: { $0.members.contains { ids.contains($0.assetId) } }), !rejected.isEmpty {
            session.setKeptAll(group.memberIds, false)
        }
    }

    // MARK: Delete

    /// Deletes the marked photos through PhotoKit (system confirmation, then
    /// Recently Deleted) and prunes the local rows — metadata, hash and group
    /// cache — so the groups update at once. A cancelled system dialog keeps
    /// the marks. Returns whether anything was deleted.
    @discardableResult
    func deleteMarked() async -> Bool {
        let full = groups.filter(isFullyMarked)
        guard full.isEmpty else {
            notice = DuplicateNotice(
                title: full.count == 1
                    ? String(localized: "1 Group Has Every Copy Marked", comment: "Duplicates: Delete blocked because a group would lose every photo")
                    : String(localized: "\(full.count) Groups Have Every Copy Marked", comment: "Duplicates: Delete blocked because groups would lose every photo"),
                message: String(localized: "Nothing would be kept from them. Unmark at least one photo in each, then delete.", comment: "Duplicates: how to get past the every-copy-marked block")
            )
            return false
        }
        return await delete(ids: scopedMarks)
    }

    /// Deletes a subset of the marks and leaves the rest marked.
    ///
    /// The Compare screen only ever shows one group, so its Delete button must
    /// act on that group alone — otherwise a mark left in another group would
    /// be swept up by a button whose count never mentioned it.
    func delete(ids: Set<String>) async -> Bool {
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
        didDelete(ids: ids)
        return true
    }

    /// Prunes photos that are gone — deleted here or from Compare — from the
    /// rows, the hash cache and the groups, so the screen updates at once.
    func didDelete(ids: Set<String>) {
        let idList = Array(ids)
        try? dependencies.metadataStore.deleteAssets(ids: idList)
        try? dependencies.perceptualHashStore.delete(assetIds: idList)
        try? dependencies.perceptualHashStore.removeFromGroups(assetIds: idList)
        for id in ids {
            assetsById.removeValue(forKey: id)
        }
        groups = groups.compactMap { group in
            let remaining = group.members.filter { !ids.contains($0.assetId) }
            return remaining.count > 1
                ? DuplicateGroup(members: remaining, kind: group.kind, sourceSet: DuplicateSourceSet.detect(remaining))
                : nil
        }
        session.forget(ids)
        UserDefaults.standard.set(groups.count, forKey: SettingsKeys.duplicateGroupCount)
    }
}
