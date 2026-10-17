import CoreGraphics
import Foundation
import os
import Testing
@testable import ShotDex

/// FS-06.06 §6 — sharpness and clipping measured on generated images (no
/// photos, no faces: AC-Q1, AC-Q3).
struct DuplicateQualityTests {

    private static let width = 160, height = 120

    /// A deterministic scene: soft gradients, blocks and fine stripes, so a
    /// blur visibly lowers the Laplacian's variance.
    private static func scene() -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height)
        var seed: UInt32 = 12345
        for y in 0..<height {
            for x in 0..<width {
                seed = seed &* 1_103_515_245 &+ 12345
                let noise = Int((seed >> 16) & 0x1F)
                let stripes = (x / 3 + y / 7) % 2 == 0 ? 70 : 0
                let block = (x / 20 + y / 20) % 2 == 0 ? 60 : 0
                pixels[y * width + x] = UInt8(clamping: 40 + x / 4 + stripes + block + noise)
            }
        }
        return pixels
    }

    /// Separable Gaussian blur with a kernel of radius 3σ.
    private static func blur(_ input: [UInt8], sigma: Double) -> [UInt8] {
        let radius = Int((sigma * 3).rounded(.up))
        let kernel = (-radius...radius).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
        let total = kernel.reduce(0, +)
        func pass(_ source: [Double], horizontal: Bool) -> [Double] {
            var output = [Double](repeating: 0, count: source.count)
            for y in 0..<height {
                for x in 0..<width {
                    var sum = 0.0
                    for (offset, weight) in zip(-radius...radius, kernel) {
                        let sx = horizontal ? min(max(x + offset, 0), width - 1) : x
                        let sy = horizontal ? y : min(max(y + offset, 0), height - 1)
                        sum += source[sy * width + sx] * weight
                    }
                    output[y * width + x] = sum / total
                }
            }
            return output
        }
        let blurred = pass(pass(input.map(Double.init), horizontal: true), horizontal: false)
        return blurred.map { UInt8(clamping: Int($0.rounded())) }
    }

    private func photo(_ id: String, size: Int) -> HashedPhoto {
        HashedPhoto(assetId: id, hash: PerceptualHash(bits: 0), width: 6000, height: 4000, fileSize: size,
                    creationDate: 1_700_000_000, isFavorite: false)
    }

    /// AC-Q1: the sharp frame is kept and says *Sharpest*; the σ=3 frame —
    /// the biggest file — is *Soft*; no chip says *Biggest file*.
    @Test func sharpestBeatsBiggestFile() {
        let sharp = Self.scene()
        let scores: [String: DuplicateQualityScore] = [
            "P": DuplicateQuality.measure(luma: sharp, width: Self.width, height: Self.height),
            "Q": DuplicateQuality.measure(luma: Self.blur(sharp, sigma: 3), width: Self.width, height: Self.height),
            "R": DuplicateQuality.measure(luma: Self.blur(sharp, sigma: 1.5), width: Self.width, height: Self.height),
        ]
        let p = photo("P", size: 3_000_000), q = photo("Q", size: 9_000_000), r = photo("R", size: 4_000_000)
        let members = [q, r, p]
        let keeper = DuplicateReview.keeper(of: members, traits: [:], scores: scores)
        #expect(keeper?.assetId == "P")
        let reasons = DuplicateReview.reasons(keeper: p, members: members, traits: [:], scores: scores)
        #expect(reasons.contains(.sharpest))
        #expect(!reasons.contains(.biggestFile))
        let sharpest = scores.values.compactMap(\.sharpness).max()
        #expect(DuplicateReview.difference(of: q, from: p, traits: [:], scores: scores, groupSharpest: sharpest) == "Soft")
    }

    /// AC-Q3: 4% of pixels at 255 against a keeper at 0.2%.
    @Test func clippingCaption() {
        func image(clippedShare: Double) -> [UInt8] {
            let count = Self.width * Self.height
            let clipped = Int(Double(count) * clippedShare)
            return Self.scene().enumerated().map { $0.offset < clipped ? 255 : min($0.element, 200) }
        }
        let scores: [String: DuplicateQualityScore] = [
            "K": DuplicateQuality.measure(luma: image(clippedShare: 0.002), width: Self.width, height: Self.height),
            "B": DuplicateQuality.measure(luma: image(clippedShare: 0.04), width: Self.width, height: Self.height),
        ]
        #expect(abs((scores["B"]?.highlightClip ?? 0) - 0.04) < 0.001)
        let k = photo("K", size: 1), b = photo("B", size: 1)
        // Same sharpness by construction is not guaranteed; pin the caption
        // rule on clipping by passing the keeper's own sharpness as the best.
        let caption = DuplicateReview.difference(of: b, from: k, traits: [:], scores: scores,
                                                 groupSharpest: scores["B"]?.sharpness)
        #expect(caption == "Blown highlights")
    }

    @Test func flatImageHasNoSharpness() {
        let flat = [UInt8](repeating: 128, count: Self.width * Self.height)
        let score = DuplicateQuality.measure(luma: flat, width: Self.width, height: Self.height)
        #expect(score.sharpness == 0)
        #expect(score.highlightClip == 0 && score.shadowClip == 0)
    }

    @Test func tooSmallImageIsNotScored() {
        #expect(!DuplicateQuality.measure(luma: [1, 2], width: 1, height: 2).isScored)
    }
}

struct DuplicateQualityStoreTests {
    @Test func scoresRoundTripAndEditRequeues() throws {
        let database = try AppDatabase.makeEmpty()
        try database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO photo_metadata (assetId, mediaType, isFavorite, indexedAt, exifStatus, modificationDate)
                VALUES ('a', 1, 0, 1, 'indexed', 100), ('b', 1, 0, 1, 'indexed', 200), ('c', 1, 0, 1, 'indexed', 300)
                """)
        }
        let store = DuplicateQualityStore(database: database)
        let face = CGRect(x: 0.25, y: 0.1, width: 0.2, height: 0.3)
        try store.upsert([
            DuplicateQualityRecord(assetId: "a", modificationDate: 100,
                                   score: .init(sharpness: 812.5, eyesOpen: 0.9, eyeConfidence: 0.95, highlightClip: 0.01, faceRect: face),
                                   exposureBias: -2, software: "Adobe Lightroom", scoredAt: 1),
            DuplicateQualityRecord(assetId: "b", modificationDate: 150, score: .init(sharpness: 5), scoredAt: 1),
            DuplicateQualityRecord(assetId: "c", modificationDate: 300, score: .init(sharpness: nil), scoredAt: 1),
        ])
        let scores = try store.scores(for: ["a", "b", "c"])
        #expect(scores["a"]?.sharpness == 812.5)
        #expect(scores["a"]?.faceRect == face)
        // b was edited since; c could not be read and waits for the network.
        #expect(Set(try store.pendingAssetIds(among: ["a", "b", "c"], retryingFailed: false)) == ["b"])
        #expect(Set(try store.pendingAssetIds(among: ["a", "b", "c"], retryingFailed: true)) == ["b", "c"])

        let hashes = PerceptualHashStore(database: database)
        try hashes.upsert([PerceptualHashRecord(assetId: "a", hash: PerceptualHash(bits: 1), modificationDate: 100, computedAt: 1)])
        #expect(try hashes.hashedPhotos().first?.exposureBias == -2)
        #expect(try hashes.hashedPhotos().first?.software == "Adobe Lightroom")
    }
}

/// FS-06.06 §3 step 5, AC-Q5 (logic half): only grouped photos, never
/// screenshots, and a cancel keeps what was scored.
struct DuplicateQualityPassTests {
    private struct Stub: DuplicateQualityReading {
        let seen: OSAllocatedUnfairLock<[String]>
        let delay: Duration
        func measure(assetId: String, allowNetwork: Bool) async -> DuplicateQualityRecord? {
            try? await Task.sleep(for: delay)
            seen.withLock { $0.append(assetId) }
            return DuplicateQualityRecord(assetId: assetId, modificationDate: 1, score: .init(sharpness: 10), scoredAt: 1)
        }
    }

    private func database(_ ids: [String]) throws -> AppDatabase {
        let database = try AppDatabase.makeEmpty()
        try database.writer.write { db in
            for id in ids {
                try db.execute(sql: "INSERT INTO photo_metadata (assetId, mediaType, isFavorite, indexedAt, exifStatus, modificationDate) VALUES (?, 1, 0, 1, 'indexed', 1)",
                               arguments: [id])
            }
        }
        return database
    }

    private func group(_ ids: [String], _ kind: DuplicateKind) -> DuplicateGroup {
        DuplicateGroup(members: ids.map { HashedPhoto(assetId: $0, hash: PerceptualHash(bits: 0), width: 1, height: 1,
                                                      fileSize: 1, creationDate: 1, isFavorite: false) }, kind: kind)
    }

    @Test func scoresGroupedPhotosButNotScreenshots() async throws {
        let database = try database(["a", "b", "s1", "s2"])
        let seen = OSAllocatedUnfairLock<[String]>(initialState: [])
        let pass = DuplicateQualityPass(store: DuplicateQualityStore(database: database),
                                        reader: Stub(seen: seen, delay: .zero), shouldPause: { false })
        try await pass.run(groups: [group(["a", "b"], .lookAlikes), group(["s1", "s2"], .screenshots)],
                           allowNetwork: false) { _, _ in }
        #expect(Set(seen.withLock { $0 }) == ["a", "b"])
        // A second run has nothing left to do.
        try await pass.run(groups: [group(["a", "b"], .lookAlikes)], allowNetwork: false) { _, _ in }
        #expect(seen.withLock { $0 }.count == 2)
    }

    @Test func cancelKeepsWhatWasScored() async throws {
        let ids = (0..<60).map { "p\($0)" }
        let database = try database(ids)
        let seen = OSAllocatedUnfairLock<[String]>(initialState: [])
        let store = DuplicateQualityStore(database: database)
        let pass = DuplicateQualityPass(store: store, reader: Stub(seen: seen, delay: .milliseconds(5)), shouldPause: { false })
        let task = Task {
            try await pass.run(groups: [group(ids, .sameMoment)], allowNetwork: false) { _, _ in }
        }
        try await Task.sleep(for: .milliseconds(150))
        let cancelledAt = ContinuousClock.now
        task.cancel()
        _ = await task.result
        #expect(ContinuousClock.now - cancelledAt < .milliseconds(500))
        let scored = try store.scores(for: ids).count
        #expect(scored > 0)
        #expect(scored < ids.count)
        #expect(scored == seen.withLock { $0 }.count)
    }
}
