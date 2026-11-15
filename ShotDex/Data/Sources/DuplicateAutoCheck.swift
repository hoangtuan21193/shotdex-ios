import Foundation
import os

/// Groups every stored hash once and writes the cache (FS-06.06 §3–§4,
/// §14.1–§14.2): checksums for photos that could be byte-identical, the
/// hash grouper, then the print nominations. Shared by the Check button and
/// the automatic check of new photos — always through
/// `DuplicateScanPipeline.regroup`, which runs one at a time.
enum DuplicateRegroup {
    /// - Returns: whether the cache was written (false when cancelled or
    ///   the store could not be read).
    @discardableResult
    static func run(store: PerceptualHashStore, allowNetwork: Bool) async -> Bool {
        guard !Task.isCancelled, var photos = try? store.hashedPhotos() else { return false }
        // §14.2: read in full only what could be byte-identical and is not
        // read yet; then group with the checksums.
        let unread = ContentChecksum.candidates(photos, missingOnly: true, retryingFailed: allowNetwork)
        if !unread.isEmpty {
            await ContentChecksumReader.read(unread, allowNetwork: allowNetwork) { batch in
                try? store.upsertChecksums(batch)
            }
            guard !Task.isCancelled else { return false }
            if let fresh = try? store.hashedPhotos() { photos = fresh }
        }
        var groups = DuplicateGrouper.groups(from: photos)
        guard !Task.isCancelled else { return false }
        // §14.1: the print nominates what the hash missed — only where prints
        // can tell pictures apart (never on the simulator, §4a).
        if DuplicateQualityReader.printsTellPicturesApart {
            groups += FeaturePrintCandidates.nominate(photos, grouped: Set(groups.flatMap(\.memberIds)))
        }
        guard !Task.isCancelled else { return false }
        return (try? store.replaceGroups(groups, scannedAt: Date())) != nil
    }
}

/// When the app may check new photos for duplicates by itself (FS-06.06
/// §14.3): only after the user ran the first check (the first automatic scan
/// once grouped far too much, 2026-11-10), only when an index run changed
/// photos, never on Low Power or a hot device, never while the editor or
/// Video Studio is open.
enum DuplicateAutoCheckPolicy {
    static func shouldRun(
        hasChecked: Bool,
        changedPhotos: Int,
        isLowPower: Bool,
        thermalState: ProcessInfo.ThermalState,
        toolIsOpen: Bool = false
    ) -> Bool {
        hasChecked && changedPhotos > 0 && !isLowPower && !toolIsOpen
            && thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue
    }
}

extension Notification.Name {
    /// The automatic check rewrote the duplicate cache; an open Duplicates
    /// screen reads it again. Posted on the main actor.
    static let duplicateGroupsDidChange = Notification.Name("ShotDex.duplicateGroupsDidChange")
}

/// Checks new and changed photos after index runs (§14.3): hashes what has no
/// hash yet — the runs' photos — and regroups, so opening Duplicates shows
/// them already grouped. Off the network: an automatic check never downloads
/// from iCloud.
///
/// The index observer only records that something changed and returns
/// (review 2026-11-16: awaiting the hash inside the observer held the index
/// run open for minutes). Work starts after a quiet period, so a burst of
/// index runs costs one check; changes that land while a check runs cause one
/// more pass, not a lost one. A manual Check cancels it and waits.
actor DuplicateAutoCheck {
    static let defaultQuietPeriod: Duration = .seconds(30)

    private let store: PerceptualHashStore
    private let pipeline: DuplicateScanPipeline
    private let quietPeriod: Duration
    private let onFinished: @Sendable () async -> Void
    private var hasPendingChanges = false
    private var task: Task<Void, Never>?
    /// Editor / Video Studio screens open right now — counted synchronously
    /// so appear and disappear can never be reordered.
    private let toolsOpen = OSAllocatedUnfairLock(initialState: 0)

    init(
        store: PerceptualHashStore,
        pipeline: DuplicateScanPipeline,
        quietPeriod: Duration = DuplicateAutoCheck.defaultQuietPeriod,
        onFinished: @escaping @Sendable () async -> Void = {}
    ) {
        self.store = store
        self.pipeline = pipeline
        self.quietPeriod = quietPeriod
        self.onFinished = onFinished
    }

    nonisolated func toolOpened() { toolsOpen.withLock { $0 += 1 } }
    nonisolated func toolClosed() { toolsOpen.withLock { $0 -= 1 } }

    /// Index-run observer: returns at once.
    func handle(_ changes: IndexRunChanges) {
        guard !changes.changed.isEmpty else { return }
        hasPendingChanges = true
        guard task == nil else { return }
        task = Task(priority: .utility) { await self.drain() }
    }

    /// A manual Check is starting: stop, and wait until the hash pipeline
    /// is free for it.
    func cancel() async {
        hasPendingChanges = false
        let running = task
        running?.cancel()
        await running?.value
    }

    /// Whether a check is waiting or running — for tests.
    var isBusy: Bool { task != nil }

    private func mayRun() -> Bool {
        let info = ProcessInfo.processInfo
        return DuplicateAutoCheckPolicy.shouldRun(
            hasChecked: (try? store.scanState()) != nil,
            changedPhotos: 1,
            isLowPower: info.isLowPowerModeEnabled,
            thermalState: info.thermalState,
            toolIsOpen: toolsOpen.withLock { $0 > 0 }
        )
    }

    private func drain() async {
        defer { task = nil }
        while hasPendingChanges {
            // Changes arriving during the wait join this pass.
            try? await Task.sleep(for: quietPeriod)
            guard !Task.isCancelled else { return }
            hasPendingChanges = false
            // Not now: the photos stay unhashed and the next index run, or
            // the user's Check, picks them up.
            guard mayRun() else { continue }
            let toolsOpen = self.toolsOpen
            let summary = try? await pipeline.run(
                allowNetwork: false,
                onProgress: { _ in },
                keepsGoing: {
                    let info = ProcessInfo.processInfo
                    return !info.isLowPowerModeEnabled && toolsOpen.withLock { $0 <= 0 }
                        && info.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue
                }
            )
            // A manual Check holds the pipeline: it regroups when it ends.
            guard let summary, !summary.didNotStart, !summary.wasCancelled, !Task.isCancelled else { return }
            guard mayRun() else { continue }
            guard await pipeline.regroup(allowNetwork: false, priority: .utility), !Task.isCancelled else { return }
            await onFinished()
        }
    }
}
