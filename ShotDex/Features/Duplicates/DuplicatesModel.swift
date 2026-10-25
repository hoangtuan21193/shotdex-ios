import CoreLocation
import Foundation
import Photos
import SwiftUI
import UniformTypeIdentifiers

/// An alert the Duplicates screen owes the user: a merge that failed for some
/// groups, or a Delete the system refused.
struct DuplicateNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// Which group the side-by-side opens on, and which photo goes first
/// (FS-06.06 §7.6).
struct DuplicateComparePresentation: Identifiable, Equatable {
    let id = UUID()
    let groupId: String
    let startId: String
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
    private(set) var groups: [DuplicateGroup] = [] {
        didSet { groupsVersion &+= 1 }
    }
    @ObservationIgnored private var groupsVersion = 0
    private(set) var assetsById: [String: PHAsset] = [:]
    private(set) var coverage = PerceptualHashCoverage(hashedPhotos: 0, indexedPhotos: 0)
    /// Last grouping; `nil` until the first scan.
    private(set) var scanState: DuplicateScanState?
    /// Photos the next scan would hash — new or edited since the last one.
    private(set) var pendingCount = 0
    /// Photos whose thumbnail could not be read: only in iCloud while the
    /// network is off for scanning (A4).
    private(set) var cloudOnlyCount = 0
    /// Whether this run may use the network — the iCloud line says "will
    /// check on Wi-Fi" only when it may not.
    var canUseNetwork: Bool { allowNetworkForScanning }
    /// Groups found so far while a scan runs (A4): regrouped from the hashes
    /// written so far every few seconds, shown at once, cached at the end.
    @ObservationIgnored private var lastInterimGrouping = ContinuousClock.now
    @ObservationIgnored private var interimTask: Task<Void, Never>?
    /// The user's marks and decisions; lives in `AppDependencies` so it
    /// outlasts this model (FS-06.06b §1).
    let session: DuplicateReviewSession
    /// Edited / RAW / Live / favourite per member, read per card as it appears.
    private(set) var traits: [String: DuplicateMemberTraits] = [:]
    /// What the scoring pass measured, per member (FS-06.06 §6).
    private(set) var scores: [String: DuplicateQualityScore] = [:] {
        didSet { scoresVersion &+= 1 }
    }
    @ObservationIgnored private var scoresVersion = 0
    @ObservationIgnored private var sortedGroupsCache: (key: SortedGroupsKey, groups: [DuplicateGroup])?
    /// The scoring pass's progress while it runs; `nil` when idle.
    private(set) var scoring: DuplicateScoringProgress?
    @ObservationIgnored private var scoringTask: Task<Void, Never>?
    /// Which `startScoring` the running task belongs to: an older task that
    /// finishes late must not clear a newer one's state.
    @ObservationIgnored private var scoringGeneration = 0
    /// Exposure read by the pass since the last cache read: a regroup-free
    /// reload picks up brackets once the pass ends.
    @ObservationIgnored private var scoringReadExposure = false
    @ObservationIgnored private var traitsRequested: Set<String> = []
    /// Members whose traits the next flush reads (`loadTraits(for:)`).
    @ObservationIgnored private var traitsQueue: [PHAsset] = []
    @ObservationIgnored private var traitsFlush: Task<Void, Never>?
    var comparePresentation: DuplicateComparePresentation?
    var errorMessage: String?
    /// Title + message of the alert raised when Merge could not write some
    /// groups, or the system refused a Delete.
    var notice: DuplicateNotice?
    var isDeleting = false
    /// Bumped after each delete that went through, for the success haptic.
    private(set) var deleteSuccessCount = 0

    /// Asset ids marked for deletion — what Compare binds to.
    var markedForDeletion: Set<String> { session.marks }

    var sort: DuplicateSort {
        didSet {
            guard sort != oldValue else { return }
            UserDefaults.standard.set(sort.rawValue, forKey: SettingsKeys.duplicateSort)
        }
    }

    /// What the list shows. Filtering changes which cards show, never the
    /// marks or the Delete count (06b §1).
    /// There is no All: one kind always shows. A remembered kind that has
    /// no group left falls back to the first one that has.
    var filter: DuplicatesFilter {
        get {
            let present = presentFilters
            return present.isEmpty || present.contains(chosenFilter) ? chosenFilter : present[0]
        }
        set { chosenFilter = newValue }
    }

    private var chosenFilter: DuplicatesFilter {
        didSet {
            guard chosenFilter != oldValue else { return }
            UserDefaults.standard.set(chosenFilter.storedValue, forKey: SettingsKeys.duplicateKindFilter)
        }
    }

    private var scanTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var hasLoadedOnce = false

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        self.session = dependencies.duplicateReview
        self.chosenFilter = DuplicatesFilter(stored: UserDefaults.standard.string(forKey: SettingsKeys.duplicateKindFilter))
        let storedSort = UserDefaults.standard.string(forKey: SettingsKeys.duplicateSort)
        self.sort = storedSort.flatMap(DuplicateSort.init(rawValue:)) ?? .easiestFirst
    }

    var isScanning: Bool {
        if case .scanning = phase { return true }
        return false
    }

    var isBusy: Bool { phase != .idle || isDeleting }

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

    /// Marked photos in an album the user made: the kept photo will join
    /// those albums (06b §2–§3).
    var markedInAlbumsCount: Int {
        scopedMarks.filter { !(traits[$0]?.albums.isEmpty ?? true) }.count
    }

    /// Groups holding a mark, in list order, for the Selected sheet (06b §3).
    var groupsWithMarks: [DuplicateGroup] {
        let marks = session.marks
        return sortedGroupsAll.filter { $0.members.contains { marks.contains($0.assetId) } }
    }

    private var sortedGroupsAll: [DuplicateGroup] {
        DuplicateReview.sorted(groups, by: sort, freeBytes: { self.freeBytes(of: $0) ?? 0 })
    }

    // MARK: Review

    /// Groups of the kind the filter shows, in the order the sort menu asks for.
    ///
    /// Sorted once per change of the groups, the scores, the filter or the
    /// sort — not per trait read or mark: cards load their traits as they
    /// scroll in, and re-sorting every group (a keeper pick each) on each of
    /// those made the list stutter and the cards jump under the finger.
    var sortedGroups: [DuplicateGroup] {
        // Read so the list keeps observing them; the cache key does the rest.
        _ = groups.count
        _ = scores.count
        let key = SortedGroupsKey(groups: groupsVersion, scores: scoresVersion, filter: filter, sort: sort)
        if let cache = sortedGroupsCache, cache.key == key { return cache.groups }
        let shown = groups.filter(filter.includes)
        let sorted = DuplicateReview.sorted(shown, by: sort, freeBytes: { self.freeBytes(of: $0) ?? 0 }) { group in
            self.keeper(of: group).map { DuplicateReview.scoreGap(group, keeper: $0, scores: self.scores) } ?? 0
        }
        sortedGroupsCache = (key, sorted)
        return sorted
    }

    private struct SortedGroupsKey: Equatable {
        var groups: Int
        var scores: Int
        var filter: DuplicatesFilter
        var sort: DuplicateSort
    }

    /// Kinds that have at least one group, in filter-row order.
    var presentKinds: [DuplicateKind] {
        let kinds = Set(groups.map(\.kind))
        return DuplicateKind.allCases.filter(kinds.contains)
    }

    /// Filters that would show something, in filter-row order (§7.3).
    var presentFilters: [DuplicatesFilter] {
        presentKinds.map(DuplicatesFilter.kind)
    }

    func groupCount(_ filter: DuplicatesFilter) -> Int { groups.filter(filter.includes).count }

    // MARK: Quick clean

    /// Copies groups nobody has decided yet, and what they would free: the
    /// Quick clean band over the list (§7.2) shows while this is not zero.
    var pendingQuickClean: (copies: Int, bytes: Int) {
        groups.reduce(into: (copies: 0, bytes: 0)) { total, group in
            guard group.kind.isCopy, group.sourceSet == nil, !isReviewed(group) else { return }
            total.copies += group.count - 1
            total.bytes += freeBytes(of: group) ?? 0
        }
    }

    /// The Quick clean sheet's rows, once every copy's favorite / edit /
    /// album is known — a protected photo must never be ticked (A2).
    func quickCleanItems() async -> [QuickCleanItem] {
        let copies = groups.filter { $0.kind.isCopy && $0.sourceSet == nil }
        await loadAllTraits(copies)
        return QuickClean.items(groups: copies, keeper: { self.keeper(of: $0) }, traits: traits)
    }

    /// Select N photos: the ticked rows' copies get marked. Nothing is
    /// deleted; the Delete bar takes it from here (§7.2).
    func applyQuickClean(_ items: [QuickCleanItem], excluding unticked: Set<String>) {
        for item in items where !unticked.contains(item.groupId) {
            guard let group = groups.first(where: { $0.id == item.groupId }) else { continue }
            session.setMarks(of: group.members.map(\.assetId), to: Set(item.removal.remove))
            session.setKeptAll(group.memberIds, false)
        }
    }

    /// The member the card puts big with "Keep": the user's pick, else the
    /// suggestion.
    func keeper(of group: DuplicateGroup) -> HashedPhoto? {
        if let picked = session.keeper(among: group.members.map(\.assetId)),
           let member = group.members.first(where: { $0.assetId == picked }) {
            return member
        }
        // A regroup can hand a group marks made elsewhere: never suggest
        // keeping a photo the user marked while an unmarked one is there.
        let unmarked = group.members.filter { !session.isMarked($0.assetId) }
        let pool = unmarked.isEmpty ? group.members : unmarked
        return DuplicateReview.keeper(of: pool, traits: traits, scores: scores)
    }

    /// Bytes freed by keeping only the keeper. `nil` for a bracket or focus
    /// stack: raw material never counts toward "~GB to free" (§5).
    func freeBytes(of group: DuplicateGroup) -> Int? {
        guard group.sourceSet == nil, let keeper = keeper(of: group) else { return nil }
        return DuplicateReview.freeBytes(members: group.members, keeper: keeper)
    }

    func reasons(for group: DuplicateGroup, keeper: HashedPhoto? = nil) -> [DuplicateKeepReason] {
        guard let keeper = keeper ?? self.keeper(of: group) else { return [] }
        return DuplicateReview.reasons(keeper: keeper, members: group.members, traits: traits, scores: scores)
    }

    /// Up to two lines inside a copy: what it lacks, where it is from, what
    /// was shot differently (§7.4). Empty for the keeper.
    /// - Parameter keeper: `keeper(of: group)` when the caller has it already.
    func caption(of member: HashedPhoto, in group: DuplicateGroup, keeper: HashedPhoto? = nil) -> [String] {
        guard let keeper = keeper ?? self.keeper(of: group), keeper.assetId != member.assetId else { return [] }
        if group.sourceSet != nil {
            return DuplicateReview.settings(of: member, members: group.members).map { [$0] } ?? []
        }
        return DuplicateReview.caption(of: member, keeper: keeper, members: group.members, traits: traits, scores: scores)
    }

    /// What sets `member` apart from `other` (Softer, Eyes closed, Smaller…),
    /// for the compare screen, where the photo in pane A plays the keeper.
    func caption(of member: HashedPhoto, comparedWith other: HashedPhoto, in group: DuplicateGroup) -> [String] {
        guard member.assetId != other.assetId else { return [] }
        if group.sourceSet != nil {
            return DuplicateReview.settings(of: member, members: group.members).map { [$0] } ?? []
        }
        return DuplicateReview.caption(of: member, keeper: other, members: group.members, traits: traits, scores: scores)
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

    func expand(_ group: DuplicateGroup) {
        session.setCollapsed(group.memberIds, false)
    }

    /// What Remove the other N would mark: every member but the keeper,
    /// minus favorites, edits and album photos (A2).
    func removal(in group: DuplicateGroup) -> DuplicateRemoval? {
        guard let keeper = keeper(of: group) else { return nil }
        return DuplicateRemoval.plan(members: group.members, keeper: keeper, traits: traits)
    }

    /// How long the red frames of a shortcut stay on screen before the card
    /// folds — long enough to see what was marked (D9, AC-C5).
    static let foldDelay: Duration = .milliseconds(600)

    /// "Remove the other N": marks what `removal(in:)` names, then folds
    /// after `foldDelay`.
    func markOthers(in group: DuplicateGroup) {
        guard let removal = removal(in: group), !removal.remove.isEmpty else { return }
        session.setMarks(of: group.members.map(\.assetId), to: Set(removal.remove))
        session.setKeptAll(group.memberIds, false)
        foldLater(group)
    }

    private func foldLater(_ group: DuplicateGroup) {
        let members = group.memberIds
        Task { [weak self] in
            try? await Task.sleep(for: Self.foldDelay)
            guard let self, self.isReviewed(group) else { return }
            withAnimation(AppTheme.Motion.standard) { self.session.setCollapsed(members, true) }
        }
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
            foldLater(group)
        }
    }

    /// Reads edited / RAW / Live for the members of a group not read yet —
    /// once per member per screen, off the main thread, local resources only.
    func loadTraits(for group: DuplicateGroup) {
        let missing = group.members.map(\.assetId).filter { !traitsRequested.contains($0) }
        guard !missing.isEmpty else { return }
        traitsRequested.formUnion(missing)
        traitsQueue += missing.compactMap { assetsById[$0] }
        guard traitsFlush == nil else { return }
        // Cards appear one after another while the list scrolls: one read and
        // one merge per burst of them, so every visible card redraws once,
        // not once per card that scrolled in.
        traitsFlush = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self else { return }
            let assets = self.traitsQueue
            self.traitsQueue = []
            self.traitsFlush = nil
            let read = await Task.detached(priority: .userInitiated) {
                Self.readTraits(assets)
            }.value
            self.traits.merge(read) { _, new in new }
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
    nonisolated private static func userAlbums(containing asset: PHAsset) -> [(id: String, title: String)] {
        let albums = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil)
        var found: [(id: String, title: String)] = []
        albums.enumerateObjects { album, _, _ in
            if album.assetCollectionSubtype == .albumRegular, let title = album.localizedTitle {
                found.append((album.localIdentifier, title))
            }
        }
        return found.sorted { $0.title < $1.title }
    }

    nonisolated private static func readTraits(_ assets: [PHAsset]) -> [String: DuplicateMemberTraits] {
        var result: [String: DuplicateMemberTraits] = [:]
        for asset in assets {
            let resources = PHAssetResource.assetResources(for: asset)
            let hasRAW = resources.contains { resource in
                UTType(resource.uniformTypeIdentifier)?.conforms(to: .rawImage) == true
            }
            let albums = userAlbums(containing: asset)
            result[asset.localIdentifier] = DuplicateMemberTraits(
                isEdited: resources.contains { $0.type == .adjustmentData },
                hasRAW: hasRAW,
                isLive: asset.mediaSubtypes.contains(.photoLive),
                isFavorite: asset.isFavorite,
                albums: albums.map(\.title),
                albumIds: albums.map(\.id)
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
                    scores: (try? qualityStore.scores(for: ids)) ?? [:],
                    cloudOnlyCount: (try? store.unreadableCount()) ?? 0
                )
            }.value
            guard let self, !Task.isCancelled, let result else { return }
            self.hasLoadedOnce = true
            self.apply(result)
            await self.mergeBursts()
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
        var cloudOnlyCount = 0
    }

    private func apply(_ snapshot: CacheSnapshot) {
        let groups = snapshot.groups ?? []
        // Members whose PHAsset is gone (deleted outside the app) drop out;
        // groups that fall to one member vanish.
        let present = groups.compactMap { group -> DuplicateGroup? in
            let present = group.members.filter { snapshot.assetsById[$0.assetId] != nil }
            return present.count > 1 ? DuplicateGroup(members: present, kind: group.kind, sourceSet: group.sourceSet) : nil
        }
        // Not duplicates (§9): hidden for good, unless a new photo joined.
        self.groups = present.filter { group in
            if case .hidden = session.dismissal(of: group.memberIds) { return false }
            return true
        }
        assetsById = snapshot.assetsById
        coverage = snapshot.coverage
        scanState = snapshot.scanState
        pendingCount = snapshot.pendingCount
        scores = snapshot.scores
        cloudOnlyCount = snapshot.cloudOnlyCount
        // Marks are not cut on reload (§1): marks are per photo, and a regroup
        // that moves a photo keeps its mark.
        UserDefaults.standard.set(self.groups.count, forKey: SettingsKeys.duplicateGroupCount)
        UserDefaults.standard.set(totalFreeBytes, forKey: SettingsKeys.duplicateFreeBytes)
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
                self.groupSoFar()
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
                self.interimTask?.cancel()
                self.interimTask = nil
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
        interimTask?.cancel()
        stopScoring()
    }

    /// Regroups what is hashed so far, at most every 3 s, so groups show and
    /// open while the scan runs ("40 found so far"). The cache is written
    /// once, when the scan ends.
    private func groupSoFar() {
        guard interimTask == nil, ContinuousClock.now - lastInterimGrouping >= .seconds(3) else { return }
        lastInterimGrouping = .now
        let store = dependencies.perceptualHashStore
        interimTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .utility) { () -> CacheSnapshot? in
                guard let photos = try? store.hashedPhotos() else { return nil }
                let groups = DuplicateGrouper.groups(from: photos)
                let assets = PhotoLibraryService.fetchAssets(ids: groups.flatMap { $0.members.map(\.assetId) })
                return CacheSnapshot(groups: groups,
                                     assetsById: Dictionary(uniqueKeysWithValues: assets.map { ($0.localIdentifier, $0) }),
                                     coverage: PerceptualHashCoverage(hashedPhotos: photos.count, indexedPhotos: 0),
                                     scanState: nil, pendingCount: 0)
            }.value
            guard let self else { return }
            self.interimTask = nil
            guard let snapshot, self.isScanning, !Task.isCancelled else { return }
            self.groups = (snapshot.groups ?? []).compactMap { group in
                let present = group.members.filter { snapshot.assetsById[$0.assetId] != nil }
                guard present.count > 1 else { return nil }
                let kept = DuplicateGroup(members: present, kind: group.kind, sourceSet: group.sourceSet)
                return self.isHidden(kept) ? nil : kept
            }
            self.assetsById.merge(snapshot.assetsById) { _, new in new }
            await self.mergeBursts()
        }
    }

    // MARK: Scoring

    /// The group is waiting for the pass: its chip reads "Checking
    /// sharpness…" instead of a reason (§3 step 5).
    func isChecking(_ group: DuplicateGroup) -> Bool {
        scoring != nil && !group.members.allSatisfy(\.isScreenshot) && !DuplicateReview.isScored(group.members, scores)
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

    /// Marks or unmarks one tile. Every photo of a group can be marked —
    /// the whole group goes when the user wants it gone (2026-10-24).
    func toggleMark(_ assetId: String, in group: DuplicateGroup) {
        if session.isMarked(assetId) {
            session.setMarked([assetId], false)
            if markedCount(in: group) == 0 { session.setCollapsed(group.memberIds, false) }
            return
        }
        session.setMarked([assetId], true)
        session.setKeptAll(group.memberIds, false)
    }

    /// Keep Only This: the picked member becomes the group's keeper and every
    /// other member is marked — the fast path for "this is the one I keep".
    func keepOnly(_ assetId: String, in group: DuplicateGroup) {
        let ids = group.members.map(\.assetId)
        session.setKeeper(assetId, groupMembers: ids)
        session.setMarks(of: ids, to: group.memberIds.subtracting([assetId]))
        session.setKeptAll(group.memberIds, false)
    }

    /// Merge to HDR / Focus Stack on a source set (§5, AC-G5).
    var stackPresentation: PhotoStackPresentation?

    /// Opens the merge a source set is material for, on exactly its frames
    /// in capture order. Nothing is marked; cancelling there leaves the card
    /// as it was.
    func merge(_ group: DuplicateGroup) {
        guard let set = group.sourceSet else { return }
        let ids = group.members.map(\.assetId)
        let assets = ids.compactMap { assetsById[$0] }
        guard assets.count >= CombinePurpose.minimumPhotoCount else { return }
        stackPresentation = PhotoStackPresentation(assets: assets, purpose: set.kind == .bracket ? .hdr : .focusStack)
    }

    /// Not duplicates (§9): the group leaves the list and every count, for
    /// good — until a new photo joins it.
    func dismiss(_ group: DuplicateGroup) {
        clearMarks(in: group)
        session.dismiss(group.memberIds)
        groups.removeAll { $0.id == group.id }
    }

    /// A group shown again because a photo joined it after Not duplicates.
    func hasNewPhotoSinceDismissal(_ group: DuplicateGroup) -> Bool {
        if case .newPhotoSince = session.dismissal(of: group.memberIds) { return true }
        return false
    }

    // MARK: Frame picker

    /// The shared frame picker on screen (§8).
    var framePicker: BurstFramesRequest?

    /// Opens the frame picker on `group`, keeping its unmarked frames when
    /// some are marked — the picker's keeps **are** the group's marks.
    func openFrames(_ group: DuplicateGroup, at assetId: String? = nil) {
        let ids = group.members.map(\.assetId)
        var request = BurstFramesRequest(frames: ids, startFrameId: assetId ?? keeper(of: group)?.assetId)
        let marked = group.memberIds.intersection(session.marks)
        if !marked.isEmpty { request.initiallyKept = group.memberIds.subtracting(marked) }
        let sharpest = group.members.compactMap { scores[$0.assetId]?.sharpness }.max()
        let scored = DuplicateReview.isScored(group.members, scores)
        for member in group.members {
            guard let score = scores[member.assetId] else { continue }
            if let face = score.faceRect { request.faceRects[member.assetId] = face }
            let soft = scored && (sharpest ?? 0) > 0 && (score.sharpness ?? 0) <= (sharpest ?? 0) * DuplicateQuality.softRatio
            if score.hasEyesClosed || soft { request.weakFrameIds.insert(member.assetId) }
            var chips: [String] = []
            if score.hasEyesClosed { chips.append(String(localized: "Eyes closed", comment: "Duplicates: caption — someone in this photo has their eyes closed")) }
            if soft { chips.append(String(localized: "Soft", comment: "Duplicates: caption — this photo is noticeably less sharp than the sharpest")) }
            if scored, chips.isEmpty, score.sharpness == sharpest {
                chips.append(String(localized: "Sharpest", comment: "Duplicates: reason chip — the kept photo is the sharpest of the group"))
            }
            request.chips[member.assetId] = chips
        }
        request.title = group.sourceSet?.title ?? group.kind.title
        framePicker = request
    }

    /// Done in the frame picker: the keeps become the group's marks (nothing
    /// kept → marks unchanged). Its delete runs `delete(ids:)` directly, so
    /// the kept frame inherits like any other keeper.
    func didChooseFrames(_ request: BurstFramesRequest, kept: [String]) {
        guard case .frames(let ids) = request.source, !kept.isEmpty else { return }
        let present = ids.filter { assetsById[$0] != nil }
        session.setMarks(of: present, to: Set(present).subtracting(kept))
    }

    // MARK: Bursts

    /// PhotoKit bursts are Burst groups (§4): read once per load, their
    /// frames taken out of any other group so a photo is in one place only.
    func mergeBursts() async {
        let library = dependencies.bursts
        var burstGroups: [DuplicateGroup] = []
        // Frames the index knows keep their file size and facts.
        let known = Dictionary(groups.flatMap(\.members).map { ($0.assetId, $0) }, uniquingKeysWith: { first, _ in first })
        for row in await library.bursts() {
            let frames = await library.frames(ofBurst: row.id)
            let members: [HashedPhoto] = frames.compactMap { frame in
                guard let asset = library.asset(for: frame.id) else { return nil }
                assetsById[frame.id] = asset
                if let photo = known[frame.id] { return photo }
                return HashedPhoto(
                    assetId: frame.id, hash: PerceptualHash(bits: 0),
                    width: asset.pixelWidth, height: asset.pixelHeight, fileSize: nil,
                    creationDate: asset.creationDate.map { Int($0.timeIntervalSince1970) },
                    isFavorite: asset.isFavorite
                )
            }
            guard members.count >= 2 else { continue }
            burstGroups.append(DuplicateGroup(members: members, kind: .burst))
        }
        guard !burstGroups.isEmpty else { return }
        let taken = Set(burstGroups.flatMap { $0.members.map(\.assetId) })
        let others = groups.compactMap { group -> DuplicateGroup? in
            let rest = group.members.filter { !taken.contains($0.assetId) }
            return rest.count > 1 ? DuplicateGroup(members: rest, kind: group.kind, sourceSet: group.sourceSet) : nil
        }
        groups = others + burstGroups.filter { !isHidden($0) }
    }

    private func isHidden(_ group: DuplicateGroup) -> Bool {
        if case .hidden = session.dismissal(of: group.memberIds) { return true }
        return false
    }

    func clearMarks(in group: DuplicateGroup) {
        session.setMarked(group.members.map(\.assetId), false)
    }

    func markedCount(in group: DuplicateGroup) -> Int {
        group.members.filter { session.marks.contains($0.assetId) }.count
    }

    // MARK: Compare

    func canCompare(_ group: DuplicateGroup) -> Bool {
        group.count >= CompareSession.minimumCount
    }

    /// Opens the group side by side, `assetId` first: every photo pinches
    /// together, and a pane's trash button is the tile's mark (§7.6).
    func compare(_ group: DuplicateGroup, from assetId: String? = nil) {
        guard canCompare(group) else { return }
        let start = assetId ?? keeper(of: group)?.assetId ?? group.members[0].assetId
        comparePresentation = DuplicateComparePresentation(groupId: group.id, startId: start)
    }

    // MARK: Delete

    /// Deletes the marked photos through PhotoKit (system confirmation, then
    /// Recently Deleted) and prunes the local rows — metadata, hash and group
    /// cache — so the groups update at once. A cancelled system dialog keeps
    /// the marks. Returns whether anything was deleted.
    @discardableResult
    func deleteMarked() async -> Bool {
        await delete(ids: scopedMarks)
    }

    /// Deletes a subset of the marks and leaves the rest marked.
    ///
    /// The selected sheet deletes what it lists, which may be fewer than
    /// every mark.
    ///
    /// One system dialog. Then each group's kept photo takes what its deleted
    /// copies had (06b §2) — **after** the delete went through, so a Don't
    /// Allow changes nothing at all (PhotoKit's atomicity across the dialog is
    /// unmeasured; this is the order the user chose for that case). Then the
    /// banner says where the photos went.
    func delete(ids: Set<String>) async -> Bool {
        let assets = ids.compactMap { assetsById[$0] }
        guard !assets.isEmpty, !isDeleting else { return false }
        isDeleting = true
        defer { isDeleting = false }
        let affected = groups.filter { !$0.memberIds.isDisjoint(with: ids) }
        await loadAllTraits(affected)
        let plans = DuplicateInheritance.plan(groups: affected, deleting: ids, traits: traits)
        let donors = Dictionary(uniqueKeysWithValues: assets.map { ($0.localIdentifier, $0) })
        let keepers = Dictionary(uniqueKeysWithValues: plans.compactMap { plan in
            assetsById[plan.keeperId].map { (plan.keeperId, $0) }
        })
        let goingMembers = groups.flatMap(\.members).filter { ids.contains($0.assetId) }
        // A frame the index never read has no size: say nothing rather than
        // a number that is too low.
        let bytes = goingMembers.contains { $0.fileSize == nil } ? 0 : goingMembers.reduce(0) { $0 + ($1.fileSize ?? 0) }
        do {
            try await photoLibrary.deleteAssetsCheckingServer(assets)
        } catch let error as PHPhotosError where error.code == .userCancelled {
            return false
        } catch {
            notice = DuplicateNotice(
                title: assets.count == 1
                    ? String(localized: "Couldn't Delete 1 Photo", comment: "Duplicates: the system delete failed")
                    : String(localized: "Couldn't Delete \(assets.count) Photos", comment: "Duplicates: the system delete failed"),
                message: error.localizedDescription + " "
                    + String(localized: "Nothing was deleted; your selection is kept.", comment: "Duplicates: after a failed delete")
            )
            return false
        }
        didDelete(ids: ids)
        recordFreed(bytes)
        let missedAlbums = await inherit(plans, keepers: keepers, donors: donors)
        showDeletedBanner(count: assets.count, bytes: bytes, missedAlbums: missedAlbums)
        deleteSuccessCount += 1
        return true
    }

    /// Writes the plans in one change block; returns how many photos' albums
    /// could not be updated (an album outside a limited selection, a refusal).
    private func inherit(
        _ plans: [DuplicateInheritance],
        keepers: [String: PHAsset],
        donors: [String: PHAsset]
    ) async -> Int {
        let work = plans.filter { !$0.isEmpty && keepers[$0.keeperId] != nil }
        guard !work.isEmpty else { return 0 }
        var missed = 0
        var writes: [(PHAsset, DuplicateInheritance, CLLocation?, Date?, [PHAssetCollection])] = []
        // Facts read now, not when the cards appeared: the user may have
        // changed a favorite or an album in Photos since.
        let fresh = Dictionary(uniqueKeysWithValues: PhotoLibraryService.fetchAssets(ids: work.map(\.keeperId)).map { ($0.localIdentifier, $0) })
        for plan in work {
            guard let keeper = fresh[plan.keeperId] ?? keepers[plan.keeperId] else { continue }
            var plan = plan
            if keeper.isFavorite { plan.favorite = false }
            let givers = plan.donorIds.compactMap { donors[$0] }
            let location = keeper.location == nil ? givers.compactMap(\.location).first : nil
            let earliest = plan.takesEarliestDate ? givers.compactMap(\.creationDate).min() : nil
            let date = earliest.flatMap { $0 < (keeper.creationDate ?? .distantFuture) ? $0 : nil }
            let found = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: plan.albumIds, options: nil)
            var albums: [PHAssetCollection] = []
            found.enumerateObjects { album, _, _ in albums.append(album) }
            if albums.count < plan.albumIds.count { missed += 1 }
            writes.append((keeper, plan, location, date, albums))
        }
        // One block per keeper: an album the app may no longer edit must not
        // sink every other keeper's favorite and location with it.
        var written: [(PHAsset, DuplicateInheritance, CLLocation?, Date?, [PHAssetCollection])] = []
        for write in writes {
            let (keeper, plan, location, date, albums) = write
            do {
                var refused = false
                try await PHPhotoLibrary.shared().performChanges {
                    if plan.favorite || location != nil || date != nil {
                        let request = PHAssetChangeRequest(for: keeper)
                        if plan.favorite { request.isFavorite = true }
                        if let location { request.location = location }
                        if let date { request.creationDate = date }
                    }
                    for album in albums {
                        if let request = PHAssetCollectionChangeRequest(for: album) {
                            request.addAssets([keeper] as NSArray)
                        } else {
                            refused = true
                        }
                    }
                }
                if refused, albums.count == plan.albumIds.count { missed += 1 }
                written.append(write)
            } catch {
                missed += 1
            }
        }
        writes = written
        for (keeper, plan, location, date, _) in writes {
            let id = keeper.localIdentifier
            if plan.favorite { try? dependencies.metadataStore.updateFavorite(assetId: id, isFavorite: true) }
            if let location {
                try? dependencies.metadataStore.updateLocation(
                    assetIds: [id], latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            }
            if let date { try? dependencies.metadataStore.updateCreationDate(assetIds: [id], date: date) }
            traits[id] = nil
            traitsRequested.remove(id)
        }
        return missed
    }

    /// Bytes deleted from Duplicates today, for "All reviewed · 1.4 GB freed
    /// today" (06b §3). Kept per calendar day in user defaults.
    var freedToday: Int {
        let stored = UserDefaults.standard.dictionary(forKey: SettingsKeys.duplicateFreedToday)
        guard stored?["day"] as? String == Self.today else { return 0 }
        return stored?["bytes"] as? Int ?? 0
    }

    private func recordFreed(_ bytes: Int) {
        UserDefaults.standard.set(["day": Self.today, "bytes": freedToday + bytes], forKey: SettingsKeys.duplicateFreedToday)
    }

    private static var today: String {
        Date().formatted(.iso8601.year().month().day())
    }

    /// "37 photos moved to Recently Deleted · 210 MB freed · kept for 30
    /// days" + Open Photos (06b §3). No Undo: an app cannot read Recently
    /// Deleted back.
    private func showDeletedBanner(count: Int, bytes: Int, missedAlbums: Int) {
        let size = DuplicatesScreen.byteFormatter.string(fromByteCount: Int64(bytes))
        var text = count == 1
            ? String(localized: "1 photo moved to Recently Deleted", comment: "Duplicates: banner after deleting")
            : String(localized: "\(count) photos moved to Recently Deleted", comment: "Duplicates: banner after deleting")
        if bytes > 0 {
            text += "\n" + String(localized: "\(size) freed · kept for 30 days", comment: "Duplicates: banner after deleting, space and how long Photos keeps them")
        }
        if missedAlbums > 0 {
            text += "\n" + (missedAlbums == 1
                ? String(localized: "1 kept photo couldn't take its copies' albums or favorite",
                         comment: "Duplicates: banner, inheritance could not be written for one kept photo")
                : String(localized: "\(missedAlbums) kept photos couldn't take their copies' albums or favorite",
                         comment: "Duplicates: banner, inheritance could not be written for several kept photos"))
        }
        dependencies.banner.show(text, actionTitle: String(localized: "Open Photos", comment: "Duplicates banner: open the Photos app")) {
            if let url = URL(string: "photos-redirect://") { UIApplication.shared.open(url) }
        }
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
        UserDefaults.standard.set(totalFreeBytes, forKey: SettingsKeys.duplicateFreeBytes)
    }
}
