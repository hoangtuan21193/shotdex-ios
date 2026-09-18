import Foundation
import Testing
@testable import ShotDex

/// The people-and-pets pass: what it puts on its work list, what it writes,
/// and what it deliberately leaves alone.
struct SubjectScanTests {

    private func makeRecord(_ id: String, kind: MediaKind = .photo, created: Int = 1_700_000_000) -> PhotoMetadata {
        PhotoMetadata(
            assetId: id,
            creationDate: created,
            modificationDate: created,
            mediaType: kind.storedValue,
            cameraManufacturer: nil,
            cameraModel: nil,
            normalizedCameraModel: nil,
            normalizedCameraManufacturer: nil,
            lensManufacturer: nil,
            lensModel: nil,
            normalizedLensModel: nil,
            originalFilename: nil,
            iso: nil,
            aperture: nil,
            shutterSpeedSeconds: nil,
            shutterSpeedDisplay: nil,
            focalLength: nil,
            focalLengthIn35mm: nil,
            calculatedEquivalentFocalLength: nil,
            equivalentFocalLength: nil,
            sensorFormat: nil,
            cropFactor: nil,
            width: 6000,
            height: 4000,
            fileSize: 10_000_000,
            latitude: nil,
            longitude: nil,
            isFavorite: false,
            indexedAt: created,
            exifStatus: ExifStatus.indexed.rawValue
        )
    }

    private func makeStore() throws -> (AppDatabase, MetadataStore) {
        let database = try AppDatabase.makeEmpty()
        return (database, MetadataStore(database: database))
    }

    @Test func workListHoldsUnscannedPhotosOnly() throws {
        let (_, store) = try makeStore()
        for record in [makeRecord("a"), makeRecord("b"), makeRecord("clip", kind: .video)] {
            try store.upsert(record)
        }
        try store.applySubjectObservations([
            SubjectObservation(assetId: "a", faceCount: 0, animalCount: 0, didRead: true),
        ])
        // "a" was looked at and found empty — still scanned, so off the list.
        // The video was never a candidate: the reader handles stills only.
        #expect(try store.assetIdsMissingSubjectScan() == ["b"])
    }

    @Test func zeroFoundStillCountsAsScanned() throws {
        let (_, store) = try makeStore()
        try store.upsert(makeRecord("a"))
        try store.applySubjectObservations([
            SubjectObservation(assetId: "a", faceCount: 0, animalCount: 0, didRead: true),
        ])
        let coverage = try store.subjectScanCoverage()
        #expect(coverage == (scanned: 1, total: 1))
    }

    @Test func clearingPutsEverythingBackOnTheList() throws {
        let (_, store) = try makeStore()
        try store.upsert(makeRecord("a"))
        try store.applySubjectObservations([
            SubjectObservation(assetId: "a", faceCount: 2, animalCount: 0, didRead: true),
        ])
        try store.clearSubjectObservations()
        #expect(try store.assetIdsMissingSubjectScan() == ["a"])
        #expect(try store.subjectScanCoverage().scanned == 0)
    }

    /// Re-indexing must not throw the scan away. The indexer upserts a whole
    /// `PhotoMetadata` record, so a face count kept as a column of that table
    /// would be blanked every re-index — and rebuilding it costs a full decode
    /// of every photo, which is exactly what the feature is rationed around.
    @Test func reindexKeepsSubjectResults() throws {
        let (_, store) = try makeStore()
        try store.upsert(makeRecord("a"))
        try store.applySubjectObservations([
            SubjectObservation(assetId: "a", faceCount: 2, animalCount: 0, didRead: true),
        ])
        try store.upsert(makeRecord("a", created: 1_800_000_000))
        #expect(try store.assetIdsMissingSubjectScan().isEmpty)
        #expect(try store.subjectScanCoverage() == (scanned: 1, total: 1))
    }

    @Test func collectionsSplitPeopleFromPets() async throws {
        let (database, store) = try makeStore()
        for record in [makeRecord("person", created: 2), makeRecord("pet", created: 1), makeRecord("empty", created: 3)] {
            try store.upsert(record)
        }
        try store.applySubjectObservations([
            SubjectObservation(assetId: "person", faceCount: 3, animalCount: 0, didRead: true),
            SubjectObservation(assetId: "pet", faceCount: 0, animalCount: 1, didRead: true),
            SubjectObservation(assetId: "empty", faceCount: 0, animalCount: 0, didRead: true),
        ])
        let queries = LibraryQueries(database: database)
        #expect(try await queries.assetIdsWithFaces() == ["person"])
        #expect(try await queries.assetIdsWithAnimals() == ["pet"])
    }

    /// A photo that could not be read at all stays pending, so a later run
    /// retries it instead of recording a false "nobody in this one".
    @Test func unreadablePhotoStaysPending() async throws {
        let (_, store) = try makeStore()
        for record in [makeRecord("ok"), makeRecord("unreadable")] { try store.upsert(record) }
        let pipeline = SubjectScanPipeline(
            store: store,
            reader: StubSubjectReader(unreadable: ["unreadable"], faces: ["ok": 1])
        )
        let summary = await pipeline.run(allowNetwork: false) { _ in }
        #expect(summary.scanned == 1)
        #expect(summary.failed == 1)
        #expect(try store.assetIdsMissingSubjectScan() == ["unreadable"])
    }

    @Test func progressReachesEveryPhotoOnTheList() async throws {
        let (_, store) = try makeStore()
        for index in 0..<250 { try store.upsert(makeRecord("a\(index)", created: index)) }
        let pipeline = SubjectScanPipeline(store: store, reader: StubSubjectReader())
        let updates = ProgressLog()
        let summary = await pipeline.run(allowNetwork: false) { update in
            updates.append(update)
        }
        #expect(summary.scanned == 250)
        // Three batches of 100, 100, 50, plus the zero the run opens with.
        #expect(updates.processedValues == [0, 100, 200, 250])
        #expect(updates.totals.allSatisfy { $0 == 250 })
    }

    @Test func secondRunWhileOneIsGoingDoesNothing() async throws {
        let (_, store) = try makeStore()
        try store.upsert(makeRecord("a"))
        let pipeline = SubjectScanPipeline(store: store, reader: StubSubjectReader())
        async let first = pipeline.run(allowNetwork: false) { _ in }
        async let second = pipeline.run(allowNetwork: false) { _ in }
        let summaries = await [first, second]
        #expect(summaries.filter(\.didNotStart).count == 1)
    }
}

/// Collects the progress callbacks from a run, which arrive off the actor.
private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var updates: [SubjectScanProgress] = []

    func append(_ update: SubjectScanProgress) {
        lock.lock()
        updates.append(update)
        lock.unlock()
    }

    var processedValues: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return updates.map(\.processed)
    }

    var totals: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return updates.map(\.total)
    }
}

/// Stand-in for Vision: answers from a script instead of decoding anything.
private struct StubSubjectReader: SubjectVisionReading {
    var unreadable: Set<String> = []
    var faces: [String: Int] = [:]
    var animals: [String: Int] = [:]

    func observe(assetId: String, allowNetwork: Bool) async -> SubjectObservation {
        SubjectObservation(
            assetId: assetId,
            faceCount: faces[assetId] ?? 0,
            animalCount: animals[assetId] ?? 0,
            didRead: !unreadable.contains(assetId)
        )
    }
}
