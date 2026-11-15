import Foundation
import Photos
import Testing
@testable import ShotDex

/// FS-06.06 §14.3 — when new photos are checked by themselves.
struct DuplicateAutoCheckTests {
    /// AC-I8: never before the first Check.
    @Test func neverRunsBeforeTheFirstCheck() {
        #expect(!DuplicateAutoCheckPolicy.shouldRun(hasChecked: false, changedPhotos: 5, isLowPower: false, thermalState: .nominal))
        #expect(DuplicateAutoCheckPolicy.shouldRun(hasChecked: true, changedPhotos: 5, isLowPower: false, thermalState: .nominal))
    }

    /// AC-I9: Low Power and a hot device wait for the next index run.
    @Test func yieldsToLowPowerAndHeat() {
        #expect(!DuplicateAutoCheckPolicy.shouldRun(hasChecked: true, changedPhotos: 5, isLowPower: true, thermalState: .nominal))
        #expect(!DuplicateAutoCheckPolicy.shouldRun(hasChecked: true, changedPhotos: 5, isLowPower: false, thermalState: .serious))
        #expect(DuplicateAutoCheckPolicy.shouldRun(hasChecked: true, changedPhotos: 5, isLowPower: false, thermalState: .fair))
    }

    /// An open editor or Video Studio holds the check back (§14.3).
    @Test func waitsWhileAToolIsOpen() {
        #expect(!DuplicateAutoCheckPolicy.shouldRun(hasChecked: true, changedPhotos: 5, isLowPower: false, thermalState: .nominal, toolIsOpen: true))
    }

    /// Nothing changed in the index run: nothing to check.
    @Test func idleRunsCheckNothing() {
        #expect(!DuplicateAutoCheckPolicy.shouldRun(hasChecked: true, changedPhotos: 0, isLowPower: false, thermalState: .nominal))
    }

    /// AC-I7 (store level): after a first check, the regroup a new copy
    /// triggers puts it in its group — no tap.
    @Test func newCopiesJoinWithoutATap() async throws {
        let fixture = try Fixture()
        try fixture.add(["a", "b"])
        await DuplicateRegroup.run(store: fixture.store, allowNetwork: false)
        #expect(try fixture.store.cachedGroups()?.first?.memberIds == ["a", "b"])
        // A third copy arrives and is hashed by the next index run.
        try fixture.add(["c"])
        await DuplicateRegroup.run(store: fixture.store, allowNetwork: false)
        #expect(try fixture.store.cachedGroups()?.first?.memberIds == ["a", "b", "c"])
    }

    /// The index observer returns at once; three runs in a burst cost one
    /// check, after the quiet period (review 2026-11-16).
    @Test func aBurstOfIndexRunsIsOneCheck() async throws {
        let fixture = try Fixture()
        try fixture.add(["a", "b"])
        await DuplicateRegroup.run(store: fixture.store, allowNetwork: false)
        let finished = AutoCheckCount()
        let check = DuplicateAutoCheck(store: fixture.store, pipeline: fixture.pipeline, quietPeriod: .milliseconds(100)) {
            await finished.add()
        }
        try fixture.add(["c"])
        for id in ["c", "c", "c"] {
            await check.handle(IndexRunChanges(changed: [id], deleted: [], isFullWalk: false, accessIsFull: true))
        }
        #expect(await check.isBusy)
        try await waitUntilIdle(check)
        #expect(await finished.value == 1)
        #expect(try fixture.store.cachedGroups()?.first?.memberIds == ["a", "b", "c"])
    }

    /// AC-I8 on the actor: no first Check, no work at all.
    @Test func idleBeforeTheFirstCheck() async throws {
        let fixture = try Fixture()
        try fixture.add(["a", "b"])
        let finished = AutoCheckCount()
        let check = DuplicateAutoCheck(store: fixture.store, pipeline: fixture.pipeline, quietPeriod: .milliseconds(20)) {
            await finished.add()
        }
        await check.handle(IndexRunChanges(changed: ["b"], deleted: [], isFullWalk: false, accessIsFull: true))
        try await waitUntilIdle(check)
        #expect(await finished.value == 0)
        #expect(try fixture.store.cachedGroups() == nil)
    }

    /// The user's Check takes over: the waiting check stops and never writes.
    @Test func aManualCheckCancelsIt() async throws {
        let fixture = try Fixture()
        try fixture.add(["a", "b"])
        await DuplicateRegroup.run(store: fixture.store, allowNetwork: false)
        let finished = AutoCheckCount()
        let check = DuplicateAutoCheck(store: fixture.store, pipeline: fixture.pipeline, quietPeriod: .seconds(30)) {
            await finished.add()
        }
        await check.handle(IndexRunChanges(changed: ["a"], deleted: [], isFullWalk: false, accessIsFull: true))
        await check.cancel()
        #expect(await !check.isBusy)
        #expect(await finished.value == 0)
    }

    /// An open editor: the check waits for the next index run.
    @Test func anOpenEditorSkipsTheCheck() async throws {
        let fixture = try Fixture()
        try fixture.add(["a", "b"])
        await DuplicateRegroup.run(store: fixture.store, allowNetwork: false)
        let finished = AutoCheckCount()
        let check = DuplicateAutoCheck(store: fixture.store, pipeline: fixture.pipeline, quietPeriod: .milliseconds(20)) {
            await finished.add()
        }
        check.toolOpened()
        await check.handle(IndexRunChanges(changed: ["a"], deleted: [], isFullWalk: false, accessIsFull: true))
        try await waitUntilIdle(check)
        #expect(await finished.value == 0)
        check.toolClosed()
    }

    private func waitUntilIdle(_ check: DuplicateAutoCheck) async throws {
        for _ in 0..<200 where await check.isBusy {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(await !check.isBusy)
    }
}

private actor AutoCheckCount {
    private(set) var value = 0
    func add() { value += 1 }
}

/// Never reads PhotoKit: every photo the tests add is hashed already.
private struct NoReader: PerceptualHashReading {
    func hash(for asset: PHAsset, allowNetwork: Bool) async -> PerceptualHash? { nil }
}

private struct Fixture {
    let metadata: MetadataStore
    let store: PerceptualHashStore
    let pipeline: DuplicateScanPipeline
    let bits: UInt64 = 0x0F0F_00FF_0F0F_00FF

    init() throws {
        let database = try AppDatabase.makeEmpty()
        metadata = MetadataStore(database: database)
        store = PerceptualHashStore(database: database)
        pipeline = DuplicateScanPipeline(store: store, reader: NoReader())
    }

    func add(_ ids: [String]) throws {
        for id in ids {
            try metadata.upsert(PhotoMetadata(
                assetId: id, creationDate: 1_700_000_000, modificationDate: 1_700_000_000,
                mediaType: MediaKind.photo.storedValue, cameraManufacturer: nil, cameraModel: nil,
                normalizedCameraModel: nil, normalizedCameraManufacturer: nil, lensManufacturer: nil,
                lensModel: nil, normalizedLensModel: nil, originalFilename: "IMG_1.HEIC", iso: nil,
                aperture: nil, shutterSpeedSeconds: nil, shutterSpeedDisplay: nil, focalLength: nil,
                focalLengthIn35mm: nil, calculatedEquivalentFocalLength: nil, equivalentFocalLength: nil,
                sensorFormat: nil, cropFactor: nil, width: 4032, height: 3024, fileSize: 2_000_000,
                latitude: nil, longitude: nil, isFavorite: false, indexedAt: 1, exifStatus: ExifStatus.indexed.rawValue))
        }
        try store.upsert(ids.map { PerceptualHashRecord(assetId: $0, hash: PerceptualHash(bits: bits), modificationDate: 1_700_000_000, computedAt: 1) })
    }
}
