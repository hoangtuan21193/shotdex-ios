import Foundation
import Testing
@testable import ShotDex

/// FS-06.06 §4 — one grouping pass, every photo in at most one kind.
struct DuplicateGrouperTests {

    private let base = 1_700_000_000
    /// Fixtures name hashes by their *difference* from a textured picture:
    /// XOR keeps every distance, and keeps `bits: 0` from reading as a flat
    /// frame (`PerceptualHash.isLowDetail`).
    static let textured: UInt64 = 0x5555_5555_5555_5555

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
        screenshot: Bool = false,
        raw: Bool = false,
        name: String? = nil
    ) -> HashedPhoto {
        HashedPhoto(
            assetId: id,
            hash: PerceptualHash(bits: raw ? bits : bits ^ Self.textured),
            width: width,
            height: height,
            fileSize: size,
            creationDate: created,
            isFavorite: favorite,
            focalLength: focal,
            isScreenshot: screenshot,
            hasCameraEXIF: camera,
            originalFilename: name
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
            ["A", "B", "C"]: .similar,
            ["G", "H"]: .exact,
            ["D", "E", "F"]: .burst,
        ])
        let all = groups.flatMap { $0.members.map(\.assetId) }
        #expect(all.count == Set(all).count)
    }

    /// A portrait and a landscape a few bits apart are two pictures.
    @Test func lookAlikesNeedTheSameShape() {
        let photos = [
            photo("A", bits: 0, width: 6000, height: 4000, created: base),
            photo("B", bits: 0b111, width: 4000, height: 6000, created: base + 86_400),
        ]
        #expect(DuplicateGrouper.groups(from: photos).isEmpty)
    }

    /// A smaller re-save is the same pixels scaled: another shape, or 9 bits
    /// off, is a different photo even with no camera EXIF to check.
    @Test func smallerCopyNeedsShapeAndCloseHash() {
        let photos = [
            photo("A", bits: 0, width: 4032, height: 3024, created: base),
            photo("B", bits: 0b111, width: 1080, height: 1920, size: 300_000, created: base + 86_400, camera: false),
            photo("C", bits: 0x1FF, width: 1600, height: 1200, size: 300_000, created: base + 86_400 * 2, camera: false),
        ]
        let groups = DuplicateGrouper.groups(from: photos)
        // B is another shape: in no group with A. C is 9 bits off: at most
        // a look-alike, never joined to A through the smaller-copy link.
        #expect(!groups.contains { Set($0.members.map(\.assetId)).isSuperset(of: ["A", "B"]) })
        #expect(!groups.contains { $0.kind == .exact })
    }

    /// AC-G2: a tripod run — one hash, one size, 3 s apart — is twenty moments,
    /// not twenty copies.
    @Test func tripodSequenceIsNotCopies() {
        let photos = (0..<20).map { photo("t\($0)", bits: 42, created: base + $0 * 3) }
        let groups = DuplicateGrouper.groups(from: photos)
        #expect(groups.count == 1)
        #expect(groups[0].kind == .burst)
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
        #expect(groups.map(\.kind) == [.similar])
    }

    @Test func smallerCopyWithCameraEXIFNeedsTheSameSecond() {
        let big = photo("big", bits: 7, created: base)
        let sameSecond = photo("export", bits: 7, width: 2048, height: 1365, created: base)
        let otherDay = photo("other", bits: 7, width: 2048, height: 1365, created: base + 86_400)
        #expect(DuplicateGrouper.groups(from: [big, sameSecond]).map(\.kind) == [.similar])
        #expect(DuplicateGrouper.groups(from: [big, otherDay]).map(\.kind) == [.similar])
    }

    /// No Screenshots kind (2026-10-21): two screenshots of one screen are
    /// grouped like any other pair.
    @Test func screenshotsGroupByTheirOwnKind() {
        let photos = [
            photo("s1", bits: 9, created: base, screenshot: true),
            photo("s2", bits: 9, created: base + 60, screenshot: true),
        ]
        #expect(DuplicateGrouper.groups(from: photos).map(\.kind) == [.similar])
    }

    /// Exact is the same pixels saved twice: a re-encode at another quality
    /// (same hash, size and second, 20% fewer bytes) is not exact.
    @Test func exactNeedsTheSameFileSize() {
        let same = [photo("a", bits: 7, size: 5_000_000, name: "IMG_1.JPG"),
                    photo("b", bits: 7, size: 5_020_000, name: "IMG_1 2.JPG")]
        #expect(kinds(DuplicateGrouper.groups(from: same)) == [["a", "b"]: .exact])
        let reencoded = [photo("a", bits: 7, size: 5_000_000), photo("b", bits: 7, size: 4_000_000)]
        #expect(!DuplicateGrouper.groups(from: reencoded).contains { $0.kind == .exact })
    }

    /// Two frames a camera shot in one second: same hash, size and second,
    /// 0.14% apart in bytes. Their names say they are two shots.
    @Test func framesOfOneSecondAreNotExact() {
        let frames = [photo("a", bits: 7, size: 8_537_924, name: "HAT_1079.JPG"),
                      photo("b", bits: 7, size: 8_526_216, name: "HAT_1080.JPG")]
        #expect(!DuplicateGrouper.groups(from: frames).contains { $0.kind == .exact })
        // No name to go by: only equal bytes prove a copy.
        let unnamed = [photo("a", bits: 7, size: 8_537_924), photo("b", bits: 7, size: 8_526_216)]
        #expect(!DuplicateGrouper.groups(from: unnamed).contains { $0.kind == .exact })
        // A re-export keeps the name and gains a suffix.
        let export = [photo("a", bits: 7, size: 3_439_437, name: "0O2A1489-Enhanced-NR.jpg"),
                      photo("b", bits: 7, size: 3_429_804, name: "0O2A1489-Enhanced-NR-2.jpg")]
        #expect(kinds(DuplicateGrouper.groups(from: export)) == [["a", "b"]: .exact])
    }

    @Test func copyStemDropsCopySuffixesOnly() {
        #expect(DuplicateGrouper.copyStem("IMG_1234 (1).HEIC") == "img_1234")
        #expect(DuplicateGrouper.copyStem("IMG_1234 2.JPG") == "img_1234")
        #expect(DuplicateGrouper.copyStem("IMG_1234 copy.jpg") == "img_1234")
        #expect(DuplicateGrouper.copyStem("IMG_1234-2.jpg") == "img_1234")
        // A phone numbers burst frames with "_003": that is another shot.
        #expect(DuplicateGrouper.copyStem("IMG_20140204_165712_003.jpg") != DuplicateGrouper.copyStem("IMG_20140204_165712_004.jpg"))
        #expect(DuplicateGrouper.copyStem("DSC_1536.JPG") != DuplicateGrouper.copyStem("DSC_1537.JPG"))
    }

    @Test func burstFramesAreOneMoment() {
        let photos = [
            photo("f1", bits: 0, created: base),
            photo("f2", bits: 0xFFFF_FFFF_0000_0000, created: base),
        ]
        let groups = DuplicateGrouper.groups(from: photos, bursts: ["f1": "B", "f2": "B"])
        #expect(groups.map(\.kind) == [.burst])
    }

    /// A flat frame hashes to a few bits, so every flat frame is "near"
    /// every other: unrelated pictures, sizes and years apart, chained into
    /// one Smaller copies group. Low-detail hashes match only exact copies.
    @Test func lowDetailHashesNeverNearMatch() {
        let flat: [UInt64] = [0, 0x8000_2040_4004_0288, 0x1002_0804_0000_0212, 0x0000_0024_0008_8900, 0x0208_4000_0000_0000]
        let photos = flat.enumerated().map { index, bits in
            photo("p\(index)", bits: bits, width: 4000 - index * 900, height: 3000 - index * 600,
                  created: base + index * 86_400 * 200, camera: false, raw: true)
        } + [photo("same0", bits: 0, width: 4000, height: 3000, created: base, camera: false, raw: true)]
        let groups = DuplicateGrouper.groups(from: photos)
        #expect(kinds(groups) == [["p0", "same0"]: .exact])
        #expect(PerceptualHash(bits: Self.textured).isLowDetail == false)
        // Two different gradients saved in the same second: same flat hash,
        // same size, other bytes — not copies.
        let gradients = [photo("g1", bits: 0, size: 300_000, raw: true), photo("g2", bits: 0, size: 310_000, raw: true)]
        #expect(DuplicateGrouper.groups(from: gradients).isEmpty)
        #expect(PerceptualHash(bits: ~UInt64(0x40)).isLowDetail)
    }

    @Test func nearMatchesDoNotChainIntoOneGroup() {
        // a~b and b~c but a and c are 20 bits apart: c is another picture.
        let groups = DuplicateGrouper.groups(from: [
            photo("a", bits: 0, created: base),
            photo("b", bits: 0x03FF, created: base + 3600),
            photo("c", bits: 0xF_FFFF, created: base + 7200),
        ])
        #expect(kinds(groups) == [["a", "b"]: .similar])
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
        HashedPhoto(assetId: id, hash: PerceptualHash(bits: bits ^ DuplicateGrouperTests.textured), width: 6000, height: 4000, fileSize: 10_000_000,
                    creationDate: base + second, isFavorite: false, focalLength: focal, exposureBias: ev)
    }

    /// AC-G4: five frames 0.3 s apart (same second here), −2…+2 EV.
    @Test func bracketIsSourceFrames() {
        let frames = [-2.0, -1, 0, 1, 2].enumerated().map { frame("f\($0.offset)", at: 0, ev: $0.element) }
        let groups = DuplicateGrouper.groups(from: frames)
        #expect(groups.count == 1)
        let set = groups[0].sourceSet
        #expect(set?.kind == .bracket)
        #expect(set?.title == "Bracket · 5 frames · ±2 EV")
        // No Source frames filter any more: a bracket is a Burst.
        #expect(groups[0].kind == .burst)
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
