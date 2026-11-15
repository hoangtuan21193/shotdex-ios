import Foundation
import Testing
@testable import ShotDex

/// FS-06.06 §14.1 (after Immich's CLIP neighbours): the Vision print, not
/// only the hash, nominates look-alikes — inside day × camera buckets.
struct FeaturePrintCandidatesTests {
    private let day = 1_772_323_200 // 2026-03-01 00:00 UTC

    private func photo(_ id: String, bits: UInt64, at seconds: Int, camera: String? = "ILCE-7M4",
                       focal: Double? = 35, screenshot: Bool = false) -> HashedPhoto {
        var photo = HashedPhoto(assetId: id, hash: PerceptualHash(bits: bits), width: 4000, height: 3000,
                                fileSize: 5_000_000, creationDate: day + seconds, isFavorite: false)
        photo.cameraModel = camera
        photo.focalLength = focal
        photo.isScreenshot = screenshot
        return photo
    }

    /// AC-I1: a 20% crop, 18 bits off on the hash, print 0.22 → one Similar
    /// group once the prints are read.
    @Test func featurePrintNominatesACrop() {
        let original = photo("a", bits: 0x0F0F_0F0F_0F0F_0F0F, at: 3600)
        // An export or a crop keeps its original's capture time.
        let crop = photo("b", bits: 0x0F0F_0F0F_0F0F_0F0F ^ 0x3FFFF, at: 3600, focal: 35)
        let nominated = FeaturePrintCandidates.nominate([original, crop], grouped: [])
        #expect(nominated.count == 1)
        let verified = DuplicateVerifier.verify(nominated) { _, _ in 0.22 }
        #expect(verified.map { Set($0.memberIds) } == [["a", "b"]])
        #expect(verified.first?.kind == .similar)
    }

    /// AC-I2: different scenes of one day (print 0.64) stay apart; without
    /// prints nothing shows at all.
    @Test func featurePrintKeepsDifferentScenesApart() {
        let nominated = FeaturePrintCandidates.nominate([photo("a", bits: 1, at: 10), photo("b", bits: 2, at: 10)], grouped: [])
        #expect(DuplicateVerifier.verify(nominated) { _, _ in 0.64 }.isEmpty)
        #expect(DuplicateVerifier.verify(nominated) { _, _ in nil }.isEmpty)
    }

    /// AC-I3 (review 2026-11-16: one capture second, not one day): no bucket
    /// spans two seconds, two cameras, or a photo and a screenshot; photos
    /// already in a group are left alone; a bucket never passes the cap and
    /// a lone photo left over by the cut is dropped, not grouped.
    @Test func bucketsBoundThePairs() {
        let photos = [
            photo("s1a", bits: 1, at: 100), photo("s1b", bits: 2, at: 100),
            photo("s2", bits: 3, at: 101),
            photo("other", bits: 4, at: 100, camera: "iPhone 17 Pro"),
            photo("shot", bits: 6, at: 100, screenshot: true),
            photo("taken", bits: 7, at: 100),
        ]
        let nominated = FeaturePrintCandidates.nominate(photos, grouped: ["taken"])
        #expect(nominated.map { Set($0.memberIds) } == [["s1a", "s1b"]])

        let crowded = (0..<(FeaturePrintCandidates.bucketCap * 2 + 1)).map {
            photo(String(format: "p%03d", $0), bits: UInt64($0 + 1) &* 0x9E37_79B9_7F4A_7C15, at: 500)
        }
        let buckets = FeaturePrintCandidates.nominate(crowded, grouped: [])
        #expect(buckets.count == 2)
        #expect(buckets.allSatisfy { $0.members.count == FeaturePrintCandidates.bucketCap })
    }

    /// Five frames of one second at −2…+2 EV are a bracket, not look-alikes:
    /// never nominated here (they would skip the print check).
    @Test func bracketsAreNotNominated() {
        let frames = (0..<5).map { index -> HashedPhoto in
            var frame = photo("b\(index)", bits: UInt64(index), at: 900)
            frame.exposureBias = Double(index - 2)
            return frame
        }
        #expect(FeaturePrintCandidates.nominate(frames, grouped: []).isEmpty)
    }

    /// A photo with no capture date is never nominated by the print.
    @Test func undatedPhotosAreNotNominated() {
        var a = photo("a", bits: 1, at: 0), b = photo("b", bits: 2, at: 0)
        a.creationDate = nil; b.creationDate = nil
        #expect(FeaturePrintCandidates.nominate([a, b], grouped: []).isEmpty)
    }
}
