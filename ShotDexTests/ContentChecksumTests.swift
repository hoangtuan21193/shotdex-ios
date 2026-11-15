import CryptoKit
import Foundation
import Testing
@testable import ShotDex

/// FS-06.06 §14.2 (after Immich's file checksum): byte-identical photos are
/// Exact whatever they are called, and only the photos that could be are
/// read in full.
struct ContentChecksumTests {
    private func photo(_ id: String, bits: UInt64 = 7, size: Int? = 2_481_337, created: Int? = 1_700_000_000,
                       name: String? = nil, checksum: String? = nil) -> HashedPhoto {
        var photo = HashedPhoto(assetId: id, hash: PerceptualHash(bits: bits), width: 4032, height: 3024,
                                fileSize: size, creationDate: created, isFavorite: false)
        photo.originalFilename = name
        photo.contentChecksum = checksum
        return photo
    }

    /// AC-I4: AirDrop renamed it and dropped the EXIF date — equal bytes
    /// still make it Exact.
    @Test func equalChecksumIsExactWhateverTheName() {
        let a = photo("a", created: 1_700_000_000, name: "IMG_1234.HEIC", checksum: "abc")
        let b = photo("b", created: nil, name: "photo.heic", checksum: "abc")
        let groups = DuplicateGrouper.groups(from: [a, b])
        #expect(groups.count == 1)
        #expect(groups.first?.kind == .exact)
        // Without the checksum the names and times keep them apart.
        var plainA = a, plainB = b
        plainA.contentChecksum = nil
        plainB.contentChecksum = nil
        #expect(DuplicateGrouper.groups(from: [plainA, plainB]).first?.kind != .exact)
    }

    /// Different bytes never join through the checksum.
    @Test func differentChecksumsDoNotJoin() {
        let a = photo("a", created: 1, name: "x.heic", checksum: "abc")
        let b = photo("b", created: 999, name: "y.heic", checksum: "def")
        #expect(DuplicateGrouper.groups(from: [a, b]).isEmpty)
    }

    /// AC-I6: only photos sharing hash, pixel size and exact byte count are
    /// read in full.
    @Test func onlyCandidatesAreHashed() {
        let photos = [
            photo("a"), photo("b"),                      // same everything → candidates
            photo("c", size: 2_481_338),                 // one byte off
            photo("d", bits: 8),                         // other hash
            photo("e", size: nil), photo("f", size: nil), // unknown size: no
        ]
        #expect(Set(ContentChecksum.candidates(photos).map(\.assetId)) == ["a", "b"])
        var known = photos
        known[0].contentChecksum = "x"; known[1].contentChecksum = "x"
        #expect(ContentChecksum.candidates(known, missingOnly: true).isEmpty)
        // A failed read is retried only when the network may be used.
        var failed = photos
        failed[0].checksumTried = true; failed[1].checksumTried = true
        #expect(ContentChecksum.candidates(failed, missingOnly: true).isEmpty)
        #expect(ContentChecksum.candidates(failed, missingOnly: true, retryingFailed: true).count == 2)
    }

    /// Review 2026-11-16: an edited or Live photo shares its original's bytes
    /// with the untouched copy but not what the user sees — never Exact by
    /// checksum, never read.
    @Test func editedOrLivePhotosNeverJoinOnTheChecksum() {
        var edited = photo("a", created: 1, name: "x.heic", checksum: "abc")
        edited.isEditedOrLive = true
        let plain = photo("b", created: 999, name: "y.heic", checksum: "abc")
        #expect(DuplicateGrouper.groups(from: [edited, plain]).isEmpty)
        #expect(ContentChecksum.candidates([edited, photo("c")]).isEmpty)
    }

    /// The digest is built chunk by chunk — never the whole file in memory —
    /// and equals the one-shot SHA-256.
    @Test func streamsWithoutLoadingTheFile() {
        let data = Data((0..<300_000).map { UInt8($0 % 251) })
        var hasher = ContentChecksum.Hasher()
        for start in stride(from: 0, to: data.count, by: 65_536) {
            hasher.update(data[start..<min(start + 65_536, data.count)])
        }
        let expected = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(hasher.finalize() == expected)
    }
}
