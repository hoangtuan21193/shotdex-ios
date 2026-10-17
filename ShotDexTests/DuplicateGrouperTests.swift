import Foundation
import Testing
@testable import ShotDex

/// FS-06.06 §4 — one grouping pass, every photo in at most one kind.
struct DuplicateGrouperTests {

    private let base = 1_700_000_000

    private func photo(
        _ id: String,
        bits: UInt64,
        width: Int? = 6000,
        height: Int? = 4000,
        size: Int? = 10_000_000,
        created: Int? = 1_700_000_000,
        favorite: Bool = false,
        focal: Double? = nil,
        camera: Bool = true,
        screenshot: Bool = false
    ) -> HashedPhoto {
        HashedPhoto(
            assetId: id,
            hash: PerceptualHash(bits: bits),
            width: width,
            height: height,
            fileSize: size,
            creationDate: created,
            isFavorite: favorite,
            focalLength: focal,
            isScreenshot: screenshot,
            hasCameraEXIF: camera
        )
    }

    private func kinds(_ groups: [DuplicateGroup]) -> [Set<String>: DuplicateKind] {
        Dictionary(uniqueKeysWithValues: groups.map { (Set($0.members.map(\.assetId)), $0.kind) })
    }

    @Test func singletonsAreNotGroups() {
        let groups = DuplicateGrouper.groups(from: [photo("a", bits: 1), photo("b", bits: 0xFFFF_FFFF)])
        #expect(groups.isEmpty)
    }

    /// AC-G1: copies, a smaller re-save and a run of one moment, each in
    /// exactly one group of the right kind.
    @Test func everyPhotoLandsInExactlyOneKind() {
        let hashA: UInt64 = 0x0123_4567_89AB_CDEF
        let hashG: UInt64 = 0xFEDC_BA98_7654_3210
        let photos = [
            photo("A", bits: hashA, width: 4032, height: 3024, created: base),
            photo("B", bits: hashA, width: 4032, height: 3024, created: base),
            // 3 bits off, a third the size, sent through a messenger: no camera
            // EXIF, dated the day it arrived.
            photo("C", bits: hashA ^ 0b111, width: 1600, height: 1200, size: 400_000, created: base + 86_400 * 30, camera: false),
            photo("G", bits: hashG, width: 3000, height: 2000, created: base + 5000),
            photo("H", bits: hashG, width: 3000, height: 2000, created: base + 5000),
            // Each step 12–15 bits, 2 s apart.
            photo("D", bits: 0x0, created: base + 9000),
            photo("E", bits: 0xFFF, created: base + 9002),
            photo("F", bits: 0xFFF ^ 0x7FFF_0000, created: base + 9004),
        ]
        let groups = DuplicateGrouper.groups(from: photos)
        #expect(kinds(groups) == [
            ["A", "B", "C"]: .smallerCopies,
            ["G", "H"]: .copies,
            ["D", "E", "F"]: .sameMoment,
        ])
        let all = groups.flatMap { $0.members.map(\.assetId) }
        #expect(all.count == Set(all).count)
    }

    /// AC-G2: a tripod run — one hash, one size, 3 s apart — is twenty moments,
    /// not twenty copies.
    @Test func tripodSequenceIsNotCopies() {
        let photos = (0..<20).map { photo("t\($0)", bits: 42, created: base + $0 * 3) }
        let groups = DuplicateGrouper.groups(from: photos)
        #expect(groups.count == 1)
        #expect(groups[0].kind == .sameMoment)
        #expect(groups[0].count == 20)
    }

    /// AC-G3: the same scene at 24mm and 35mm is two framings.
    @Test func differentFocalLengthNeverGroups() {
        let photos = [
            photo("wide", bits: 0, created: base, focal: 24),
            photo("normal", bits: 0b1111, created: base + 600, focal: 35),
        ]
        #expect(DuplicateGrouper.groups(from: photos).isEmpty)
        // Within 10% still groups.
        let close = [
            photo("a", bits: 0, created: base, focal: 50),
            photo("b", bits: 0b1111, created: base + 600, focal: 52),
        ]
        #expect(DuplicateGrouper.groups(from: close).count == 1)
    }

    @Test func sameHashOtherSecondIsALookAlike() {
        let photos = [photo("a", bits: 42, created: base), photo("b", bits: 42, created: base + 3600)]
        let groups = DuplicateGrouper.groups(from: photos)
        #expect(groups.map(\.kind) == [.lookAlikes])
    }

    @Test func smallerCopyWithCameraEXIFNeedsTheSameSecond() {
        let big = photo("big", bits: 7, created: base)
        let sameSecond = photo("export", bits: 7, width: 2048, height: 1365, created: base)
        let otherDay = photo("other", bits: 7, width: 2048, height: 1365, created: base + 86_400)
        #expect(DuplicateGrouper.groups(from: [big, sameSecond]).map(\.kind) == [.smallerCopies])
        #expect(DuplicateGrouper.groups(from: [big, otherDay]).map(\.kind) == [.lookAlikes])
    }

    @Test func allScreenshotGroupIsScreenshots() {
        let photos = [
            photo("s1", bits: 9, created: base, screenshot: true),
            photo("s2", bits: 9, created: base + 60, screenshot: true),
        ]
        #expect(DuplicateGrouper.groups(from: photos).map(\.kind) == [.screenshots])
    }

    @Test func burstFramesAreOneMoment() {
        let photos = [
            photo("f1", bits: 0, created: base),
            photo("f2", bits: 0xFFFF_FFFF_0000_0000, created: base),
        ]
        let groups = DuplicateGrouper.groups(from: photos, bursts: ["f1": "B", "f2": "B"])
        #expect(groups.map(\.kind) == [.sameMoment])
    }

    @Test func nearMatchesChainIntoOneGroup() {
        // a~b and b~c but a and c are 20 bits apart: one connected component.
        let groups = DuplicateGrouper.groups(from: [
            photo("a", bits: 0, created: base),
            photo("b", bits: 0x03FF, created: base + 3600),
            photo("c", bits: 0xF_FFFF, created: base + 7200),
        ])
        #expect(groups.count == 1)
        #expect(groups[0].count == 3)
        #expect(groups[0].kind == .lookAlikes)
    }

    /// Plan §8.1: one keeper rule — the grouper hands members over in the
    /// order `DuplicateReview.keeper` would pick them (favourite, bigger
    /// file, more pixels), then the oldest.
    @Test func groupOrderUsesTheKeeperRule() {
        let photos = [
            photo("lighter", bits: 1, size: 8_000_000, created: base + 100),
            photo("favorite", bits: 1, size: 8_000_000, created: base + 200, favorite: true),
            photo("heavy", bits: 1, size: 12_000_000, created: base + 300),
            photo("older", bits: 1, size: 8_000_000, created: base),
        ]
        let groups = DuplicateGrouper.groups(from: photos)
        #expect(groups.count == 1)
        #expect(groups[0].members.map(\.assetId) == ["favorite", "heavy", "older", "lighter"])
        #expect(groups[0].members[0].assetId == DuplicateReview.keeper(of: photos, traits: [:])?.assetId)
    }

    @Test func groupsAreOrderedNewestFirst() {
        let photos = [
            photo("old1", bits: 1, created: 100), photo("old2", bits: 1, created: 200),
            photo("new1", bits: 0xFFFF_0000, created: 9000), photo("new2", bits: 0xFFFF_0000, created: 8000),
        ]
        let groups = DuplicateGrouper.groups(from: photos)
        #expect(groups.map(\.id) == ["new2", "old1"])
    }

    @Test func manyIdenticalHashesStayCheap() {
        // 5 000 blank frames an hour apart plus one near neighbour: the near
        // search runs over distinct hashes only, so this must finish quickly.
        var photos = (0..<5000).map { photo("blank\($0)", bits: 0, created: base + $0 * 3600) }
        photos.append(photo("near", bits: 0b111, created: base - 3600))
        let groups = DuplicateGrouper.groups(from: photos)
        #expect(groups.count == 1)
        #expect(groups[0].count == 5001)
    }
}

/// FS-06.06 §5 — brackets and focus stacks are raw material, not junk.
struct DuplicateSourceSetTests {

    private let base = 1_700_000_000

    private func frame(_ id: String, bits: UInt64 = 0, at second: Int, ev: Double?, focal: Double = 50) -> HashedPhoto {
        HashedPhoto(assetId: id, hash: PerceptualHash(bits: bits), width: 6000, height: 4000, fileSize: 10_000_000,
                    creationDate: base + second, isFavorite: false, focalLength: focal, exposureBias: ev)
    }

    /// AC-G4: five frames 0.3 s apart (same second here), −2…+2 EV.
    @Test func bracketIsSourceFrames() {
        let frames = [-2.0, -1, 0, 1, 2].enumerated().map { frame("f\($0.offset)", at: 0, ev: $0.element) }
        let groups = DuplicateGrouper.groups(from: frames)
        #expect(groups.count == 1)
        let set = try? #require(groups[0].sourceSet)
        #expect(set?.kind == .bracket)
        #expect(set?.title == "Bracket · 5 frames · ±2 EV")
        // Read in capture order, like a run.
        #expect(groups[0].members.map(\.assetId) == ["f0", "f1", "f2", "f3", "f4"])
    }

    @Test func missingExposureIsNotABracket() {
        let frames = [frame("a", at: 0, ev: -2), frame("b", at: 0, ev: nil), frame("c", at: 0, ev: 2)]
        #expect(DuplicateSourceSet.detect(frames) == nil)
    }

    @Test func unevenStepsAreNotABracket() {
        let frames = [frame("a", at: 0, ev: -2), frame("b", at: 1, ev: 0), frame("c", at: 2, ev: 0.5)]
        #expect(DuplicateSourceSet.detect(frames) == nil)
    }

    /// AC-C7's case: −1/0/+1 but 40 s apart is not a bracket.
    @Test func slowFramesAreNotABracket() {
        let frames = [frame("a", at: 0, ev: -1), frame("b", at: 40, ev: 0), frame("c", at: 80, ev: 1)]
        #expect(DuplicateSourceSet.detect(frames) == nil)
    }

    @Test func focusStackNeedsTenFrames() {
        let ten = (0..<10).map { frame("s\($0)", bits: UInt64(1) << UInt64($0 % 4), at: $0 / 2, ev: 0) }
        #expect(DuplicateSourceSet.detect(ten)?.kind == .focusStack)
        #expect(DuplicateSourceSet.detect(ten)?.title == "Focus stack? · 10 frames")
        #expect(DuplicateSourceSet.detect(Array(ten.prefix(9))) == nil)
    }

    @Test func asymmetricRangeReadsFromTo() {
        let frames = [frame("a", at: 0, ev: -1), frame("b", at: 0, ev: 0), frame("c", at: 1, ev: 1), frame("d", at: 1, ev: 2)]
        #expect(DuplicateSourceSet.detect(frames)?.evText == "−1 to +2 EV")
    }
}
