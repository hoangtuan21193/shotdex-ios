import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import os
import Testing
import UniformTypeIdentifiers
@testable import ShotDex

/// FS-19.08 §5: finding the photos several server folders share.
@Suite struct CommonPhotosMatcherTests {
    private func file(_ folder: Int, _ path: String, _ size: Int64) -> CommonPhotosFile {
        CommonPhotosFile(folder: folder, relativePath: path, size: size, modified: nil)
    }

    /// AC-115 (listing and size filter): sizes one folder lacks are dropped
    /// and not one byte of any photo is read.
    @Test func sizeFilterReadsNothingElse() async throws {
        let nas = InMemoryRemoteFileClient()
        nas.put("A/a1.jpg", Data(repeating: 1, count: 1_000))
        nas.put("A/a2.jpg", Data(repeating: 2, count: 2_000))
        nas.put("A/a3.jpg", Data(repeating: 3, count: 3_000))
        nas.put("B/b2.jpg", Data(repeating: 2, count: 2_000))
        nas.put("B/b4.jpg", Data(repeating: 4, count: 4_000))
        let scanner = CommonPhotosScanner(client: nas)

        let listing = try await scanner.list(["A", "B"])
        let groups = CommonPhotosMatcher.sizeGroups(listing.files)

        #expect(groups.count == 1)
        #expect(groups.first?.size == 2_000)
        #expect(groups.first?.files.map { $0.map(\.name) } == [["a2.jpg"], ["b2.jpg"]])
        #expect(nas.bytesRead == 0)
        #expect(nas.rangeReadPaths.isEmpty)
        #expect(nas.sha256Paths.isEmpty)

        let photos = try await CommonPhotosVerifier(client: nas).verify(CommonPhotosMatcher.preview(listing.files), folders: ["A", "B"])

        // A 2,000-byte file is read whole once: that read is its SHA-256.
        #expect(photos.count == 1)
        #expect(Set(nas.rangeReadPaths) == ["A/a2.jpg", "B/b2.jpg"])
        #expect(nas.bytesRead == 4_000)
        #expect(nas.sha256Paths.isEmpty)
    }

    /// AC-116: the same bytes under another name are Same.
    @Test func renamedFileMatches() async throws {
        let nas = InMemoryRemoteFileClient()
        let bytes = Data((0..<300_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        nas.put("A/IMG_1.JPG", bytes)
        nas.put("B/2025-06-01 IMG_1.JPG", bytes)
        let listing = try await CommonPhotosScanner(client: nas).list(["A", "B"])

        let photos = try await CommonPhotosVerifier(client: nas).verify(CommonPhotosMatcher.preview(listing.files), folders: ["A", "B"])

        #expect(photos.map { $0.files.map { $0.map(\.name) } } == [[["IMG_1.JPG"], ["2025-06-01 IMG_1.JPG"]]])
        #expect(photos.first?.sha256 == FileChecksum.hex(SHA256.hash(data: bytes)))
        #expect(nas.sha256Paths.count == 2)
    }

    /// AC-117: same size and name, one byte apart in the middle — Likely
    /// after the listing, dropped by the samples, never fully hashed.
    @Test func sameSizeDifferentBytesDropped() async throws {
        let nas = InMemoryRemoteFileClient()
        var bytes = Data((0..<1_000_000).map { UInt8(truncatingIfNeeded: $0 &* 7) })
        nas.put("A/IMG_1.JPG", bytes)
        bytes[500_000] ^= 0xFF
        nas.put("B/IMG_1.JPG", bytes)
        let listing = try await CommonPhotosScanner(client: nas).list(["A", "B"])
        let preview = CommonPhotosMatcher.preview(listing.files)

        let photos = try await CommonPhotosVerifier(client: nas).verify(preview, folders: ["A", "B"])

        #expect(preview.likelyCount == 1)
        #expect(photos.isEmpty)
        #expect(nas.sha256Paths.isEmpty)
    }

    /// A difference in the first or last 64 KB is caught by the samples.
    @Test(arguments: [0, 999_999]) func headAndTailSamples(flip: Int) async throws {
        let nas = InMemoryRemoteFileClient()
        var bytes = Data((0..<1_000_000).map { UInt8(truncatingIfNeeded: $0 &* 7) })
        nas.put("A/IMG_1.JPG", bytes)
        bytes[flip] ^= 0xFF
        nas.put("B/IMG_1.JPG", bytes)
        let listing = try await CommonPhotosScanner(client: nas).list(["A", "B"])

        let photos = try await CommonPhotosVerifier(client: nas).verify(CommonPhotosMatcher.preview(listing.files), folders: ["A", "B"])

        #expect(photos.isEmpty)
        #expect(nas.sha256Paths.isEmpty)
    }

    /// A difference the samples miss is caught by the full SHA-256.
    @Test func fullHashCatchesWhatSamplesMiss() async throws {
        let nas = InMemoryRemoteFileClient()
        var bytes = Data((0..<1_000_000).map { UInt8(truncatingIfNeeded: $0 &* 7) })
        nas.put("A/IMG_1.JPG", bytes)
        bytes[200_000] ^= 0xFF
        nas.put("B/IMG_1.JPG", bytes)
        let listing = try await CommonPhotosScanner(client: nas).list(["A", "B"])

        let photos = try await CommonPhotosVerifier(client: nas).verify(CommonPhotosMatcher.preview(listing.files), folders: ["A", "B"])

        #expect(photos.isEmpty)
        #expect(nas.rangeReadPaths.count == 6)
        #expect(nas.sha256Paths.count == 2)
    }

    /// AC-119: X in A, B and D is Same; Y only in A and B is not.
    @Test func intersectionOfAllFolders() async throws {
        let nas = InMemoryRemoteFileClient()
        let x = Data(repeating: 1, count: 1_000)
        let y = Data(repeating: 2, count: 2_000)
        for folder in ["A", "B", "D"] { nas.put("\(folder)/x.jpg", x) }
        for folder in ["A", "B"] { nas.put("\(folder)/y.jpg", y) }
        // D holds a file of Y's size with other bytes: the size passes, the
        // intersection must not.
        nas.put("D/z.jpg", Data(repeating: 3, count: 2_000))
        let folders = ["A", "B", "D"]
        let listing = try await CommonPhotosScanner(client: nas).list(folders)

        let photos = try await CommonPhotosVerifier(client: nas).verify(CommonPhotosMatcher.preview(listing.files), folders: folders)

        #expect(photos.map(\.size) == [1_000])
        #expect(photos.first?.files.count == 3)
        #expect(nas.rangeReadPaths.contains("A/y.jpg"))
    }

    /// A SHA-256 already taken (with a write time) is not taken again; the
    /// other side is, and samples still run on both.
    @Test func knownHashesAreNotReadAgain() async throws {
        let nas = InMemoryRemoteFileClient()
        let bytes = Data(repeating: 9, count: 500_000)
        nas.put("A/p.jpg", bytes)
        nas.put("B/q.jpg", bytes)
        nas.modified = ["A/p.jpg": Date(timeIntervalSince1970: 100)]
        let listing = try await CommonPhotosScanner(client: nas).list(["A", "B"])
        let indexed = try #require(listing.files[0].first)

        let photos = try await CommonPhotosVerifier(client: nas).verify(
            CommonPhotosMatcher.preview(listing.files), folders: ["A", "B"],
            knownHashes: [indexed: FileChecksum.hex(SHA256.hash(data: bytes))])

        #expect(photos.count == 1)
        #expect(nas.sha256Paths == ["B/q.jpg"])
        #expect(nas.rangeReadPaths.count == 6)
    }

    /// A cached hash is not trusted for a copy outside the first folder —
    /// Move deletes on those.
    @Test func cachedHashOnlyForTheFirstFolder() async throws {
        let nas = InMemoryRemoteFileClient()
        let bytes = Data(repeating: 9, count: 500_000)
        nas.put("A/p.jpg", bytes)
        nas.put("B/q.jpg", bytes)
        nas.modified = ["A/p.jpg": Date(timeIntervalSince1970: 1), "B/q.jpg": Date(timeIntervalSince1970: 2)]
        let listing = try await CommonPhotosScanner(client: nas).list(["A", "B"])
        let sha = FileChecksum.hex(SHA256.hash(data: bytes))

        let photos = try await CommonPhotosVerifier(client: nas).verify(
            CommonPhotosMatcher.preview(listing.files), folders: ["A", "B"],
            knownHashes: Dictionary(uniqueKeysWithValues: listing.files.joined().map { ($0, sha) }))

        #expect(photos.count == 1)
        #expect(nas.sha256Paths == ["B/q.jpg"])
    }

    /// A cached hash with no write time to vouch for it is ignored, and a
    /// photo whose every hash came from the cache is hashed once more — a
    /// wrong cache must not make a Move delete a unique photo.
    @Test func cachedHashesAreChecked() async throws {
        let nas = InMemoryRemoteFileClient()
        let bytes = Data(repeating: 9, count: 500_000)
        nas.put("A/p.jpg", bytes)
        nas.put("B/q.jpg", bytes)
        nas.put("A/r.jpg", Data(repeating: 4, count: 600_000))
        nas.put("B/s.jpg", Data(repeating: 4, count: 600_000))
        nas.modified = ["A/p.jpg": Date(timeIntervalSince1970: 1), "B/q.jpg": Date(timeIntervalSince1970: 2)]
        let listing = try await CommonPhotosScanner(client: nas).list(["A", "B"])
        let file = { (path: String) in listing.files.joined().first { $0.relativePath == path }! }
        let sha = FileChecksum.hex(SHA256.hash(data: bytes))

        let photos = try await CommonPhotosVerifier(client: nas).verify(
            CommonPhotosMatcher.preview(listing.files), folders: ["A", "B"],
            knownHashes: [file("p.jpg"): sha, file("q.jpg"): sha, file("r.jpg"): "stale", file("s.jpg"): "stale"])

        #expect(photos.count == 2)
        #expect(Set(nas.sha256Paths) == ["B/q.jpg", "A/r.jpg", "B/s.jpg"])
    }

    /// A stale cache that agrees with itself but not with the server is not
    /// Same.
    @Test func staleCacheIsNotSame() async throws {
        let nas = InMemoryRemoteFileClient()
        let bytes = Data(repeating: 9, count: 500_000)
        nas.put("A/p.jpg", bytes)
        nas.put("B/q.jpg", bytes)
        nas.modified = ["A/p.jpg": Date(timeIntervalSince1970: 1), "B/q.jpg": Date(timeIntervalSince1970: 2)]
        let listing = try await CommonPhotosScanner(client: nas).list(["A", "B"])

        let photos = try await CommonPhotosVerifier(client: nas).verify(
            CommonPhotosMatcher.preview(listing.files), folders: ["A", "B"],
            knownHashes: Dictionary(uniqueKeysWithValues: listing.files.joined().map { ($0, "stale") }))

        #expect(photos.isEmpty)
    }

    /// A read shorter than asked drops the file rather than hashing what
    /// came back; the scan goes on and counts it.
    @Test func shortReadDropsTheFile() async throws {
        let nas = InMemoryRemoteFileClient()
        nas.put("A/a.jpg", Data(repeating: 1, count: 150_000))
        nas.put("B/b.jpg", Data(repeating: 1, count: 150_000))
        nas.put("A/c.jpg", Data(repeating: 2, count: 1_000))
        nas.put("B/d.jpg", Data(repeating: 2, count: 1_000))
        nas.shortRangeReads = ["B/b.jpg"]
        let listing = try await CommonPhotosScanner(client: nas).list(["A", "B"])
        let reports = OSAllocatedUnfairLock(initialState: [CommonPhotosVerifier.Progress]())

        let photos = try await CommonPhotosVerifier(client: nas).verify(
            CommonPhotosMatcher.preview(listing.files), folders: ["A", "B"],
            progress: { report in reports.withLock { $0.append(report) } })

        #expect(photos.map(\.size) == [1_000])
        #expect(reports.withLock { $0.last?.unreadableCount } == 1)
    }

    /// Progress counts photos and bytes of the first folder, so its totals
    /// are the sheet's; found photos arrive group by group.
    @Test func progressInSheetUnits() async throws {
        let nas = InMemoryRemoteFileClient()
        for folder in ["A", "B", "D"] {
            nas.put("\(folder)/x.jpg", Data(repeating: 1, count: 1_000))
            nas.put("\(folder)/y.jpg", Data(repeating: 2, count: 3_000))
        }
        let folders = ["A", "B", "D"]
        let listing = try await CommonPhotosScanner(client: nas).list(folders)
        let preview = CommonPhotosMatcher.preview(listing.files)
        let reports = OSAllocatedUnfairLock(initialState: [CommonPhotosVerifier.Progress]())
        let batches = OSAllocatedUnfairLock(initialState: [Int]())

        _ = try await CommonPhotosVerifier(client: nas).verify(
            preview, folders: folders,
            found: { photos in batches.withLock { $0.append(photos.count) } },
            progress: { report in reports.withLock { $0.append(report) } })

        let last = try #require(reports.withLock { $0.last })
        #expect(last.totalFiles == preview.candidateCount)
        #expect(last.totalFiles == 2)
        #expect(last.totalBytes == 4_000)
        #expect(last.checkedBytes == 4_000)
        #expect(last.bytesLeft == 0)
        #expect(last.sameCount == 2)
        #expect(batches.withLock { $0 } == [1, 1])
    }

    /// Empty files are never candidates.
    @Test func emptyFilesIgnored() {
        let preview = CommonPhotosMatcher.preview([[file(0, "a.jpg", 0)], [file(1, "a.jpg", 0)]])

        #expect(preview.groups.isEmpty)
    }

    /// A cancelled scan stops.
    @Test func cancelStops() async throws {
        let nas = InMemoryRemoteFileClient()
        nas.put("A/a.jpg", Data(repeating: 1, count: 1_000))
        nas.put("B/a.jpg", Data(repeating: 1, count: 1_000))
        let listing = try await CommonPhotosScanner(client: nas).list(["A", "B"])
        let preview = CommonPhotosMatcher.preview(listing.files)

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await CommonPhotosVerifier(client: nas).verify(preview, folders: ["A", "B"])
        }

        await #expect(throws: CancellationError.self) { try await task.value }
    }

    /// Groups holding a Likely file are checked first.
    @Test func likelyGroupsFirst() async throws {
        let nas = InMemoryRemoteFileClient()
        nas.put("A/c.jpg", Data(repeating: 1, count: 4_000))
        nas.put("B/d.jpg", Data(repeating: 1, count: 4_000))
        nas.put("A/IMG_1.JPG", Data(repeating: 2, count: 1_000))
        nas.put("B/IMG_1.JPG", Data(repeating: 2, count: 1_000))
        let listing = try await CommonPhotosScanner(client: nas).list(["A", "B"])

        _ = try await CommonPhotosVerifier(client: nas).verify(CommonPhotosMatcher.preview(listing.files), folders: ["A", "B"])

        #expect(nas.rangeReadPaths.first?.hasSuffix("IMG_1.JPG") == true)
    }

    /// The listing skips dot names, the `.shotdex/` index, part files and
    /// documents, walks subfolders, and keeps `.xmp` apart.
    @Test func listingKeepsPhotosVideosAndSidecars() async throws {
        let nas = InMemoryRemoteFileClient()
        nas.put("A/2025/06/IMG_1.JPG", Data(count: 10))
        nas.put("A/2025/06/IMG_1.xmp", Data(count: 3))
        nas.put("A/clip.MOV", Data(count: 20))
        nas.put("A/.DS_Store", Data(count: 1))
        nas.put("A/.shotdex/index.json", Data(count: 1))
        nas.put("A/IMG_2.JPG.shotdex-part", Data(count: 5))
        nas.put("A/notes.txt", Data(count: 5))

        let listing = try await CommonPhotosScanner(client: nas).list(["A"])

        #expect(listing.files[0].map(\.relativePath) == ["2025/06/IMG_1.JPG", "clip.MOV"])
        #expect(listing.sidecars[0].map(\.relativePath) == ["2025/06/IMG_1.xmp"])
    }

    /// AC-118: the same capture time with a different size is neither Likely
    /// nor a candidate at all.
    @Test func sameCaptureDifferentSizeIgnored() {
        let a = file(0, "DSC_1.JPG", 5_000)
        let b = file(1, "edited.JPG", 4_800)
        let keys = [a: "2025:06:01 10:00:00|42|Z 8", b: "2025:06:01 10:00:00|42|Z 8"]

        let preview = CommonPhotosMatcher.preview([[a], [b]], captureKeys: keys)

        #expect(preview.groups.isEmpty)
        #expect(preview.likely.isEmpty)
        #expect(preview.candidateCount == 0)
    }

    /// Same size plus same name, same subfolder or same capture time is
    /// Likely; same size alone is only a candidate.
    @Test func likelyNeedsASecondSign() {
        let byName = [file(0, "IMG_1.JPG", 100), file(1, "img_1.jpg", 100)]
        let bySubfolder = [file(0, "2025/06/a.jpg", 200), file(1, "2025/06/b.jpg", 200)]
        let byCapture = [file(0, "a.jpg", 300), file(1, "b.jpg", 300)]
        let sizeOnly = [file(0, "c.jpg", 400), file(1, "d.jpg", 400)]
        let topLevel = [file(0, "e.jpg", 500), file(1, "f.jpg", 500)]
        let keys = [byCapture[0]: "t|1|R5", byCapture[1]: "t|1|R5"]
        let all = [byName, bySubfolder, byCapture, sizeOnly, topLevel]

        let preview = CommonPhotosMatcher.preview([all.map { $0[0] }, all.map { $0[1] }], captureKeys: keys)

        #expect(preview.candidateCount == 5)
        #expect(preview.likelyCount == 3)
        #expect(preview.likely == Set(byName + bySubfolder + byCapture))
        #expect(preview.candidateBytes == 1_500)
    }

    /// Likely must hold in every folder, not just two of three.
    @Test func likelyInEveryFolder() {
        let a = file(0, "IMG_1.JPG", 100)
        let b = file(1, "IMG_1.JPG", 100)
        let d = file(2, "other.JPG", 100)

        let preview = CommonPhotosMatcher.preview([[a], [b], [d]])

        #expect(preview.groups.count == 1)
        #expect(preview.likely.isEmpty)
    }

    /// A capture key is read only for groups name and subfolder leave
    /// unmatched, and never for a video.
    @Test func captureKeysReadOnlyWhereNeeded() async throws {
        let nas = InMemoryRemoteFileClient()
        nas.put("A/IMG_1.JPG", Data(repeating: 1, count: 100))
        nas.put("B/IMG_1.JPG", Data(repeating: 1, count: 100))
        nas.put("A/x.MOV", Data(repeating: 2, count: 200))
        nas.put("B/y.MOV", Data(repeating: 2, count: 200))
        nas.put("A/p.JPG", Data(repeating: 3, count: 300))
        nas.put("B/q.JPG", Data(repeating: 3, count: 300))
        let scanner = CommonPhotosScanner(client: nas)
        let listing = try await scanner.list(["A", "B"])

        _ = try await scanner.captureKeys(for: CommonPhotosMatcher.sizeGroups(listing.files), folders: ["A", "B"])

        #expect(Set(nas.rangeReadPaths) == ["A/p.JPG", "B/q.JPG"])
    }

    /// AC-120: 20,000 files a folder, 300 shared and 100 more pairs of one
    /// size with nothing else alike — size filter and Likely in memory
    /// within a second (best of three, a Debug build under parallel tests).
    @Test func twentyThousandEachUnderOneSecond() {
        var a: [CommonPhotosFile] = []
        var b: [CommonPhotosFile] = []
        for index in 0..<20_000 {
            a.append(file(0, "2025/\(index % 12)/A_\(index).JPG", 1_000_000 + Int64(index) * 2))
            b.append(file(1, "B/\(index % 7)/B_\(index).JPG", 1_000_001 + Int64(index) * 2))
        }
        for index in 0..<300 {
            let size = 50_000_000 + Int64(index)
            a.append(file(0, "shared/IMG_\(index).JPG", size))
            b.append(file(1, "from-a/IMG_\(index).JPG", size))
        }
        for index in 0..<100 {
            let size = 60_000_000 + Int64(index)
            a.append(file(0, "x/P_\(index).JPG", size))
            b.append(file(1, "y/Q_\(index).JPG", size))
        }

        var best = Double.infinity
        var preview: CommonPhotosMatcher.Preview?
        for _ in 0..<3 {
            let start = Date()
            preview = CommonPhotosMatcher.preview([a, b])
            best = min(best, Date().timeIntervalSince(start))
        }

        #expect(best < 1)
        #expect(preview?.candidateCount == 400)
        #expect(preview?.likelyCount == 300)
    }

    /// Two files of one size in a folder, one of them named like the other
    /// folder's: both are candidates, only the named one is Likely, and all
    /// three heads are read for a capture key.
    @Test func duplicatesInOneFolder() async throws {
        let nas = InMemoryRemoteFileClient()
        nas.put("A/IMG_1.JPG", Data(repeating: 1, count: 100))
        nas.put("A/copy.JPG", Data(repeating: 1, count: 100))
        nas.put("B/IMG_1.JPG", Data(repeating: 1, count: 100))
        let scanner = CommonPhotosScanner(client: nas)
        let listing = try await scanner.list(["A", "B"])

        let preview = CommonPhotosMatcher.preview(listing.files)
        _ = try await scanner.captureKeys(for: preview.groups, folders: ["A", "B"])

        #expect(preview.candidateCount == 2)
        #expect(preview.likely.map(\.relativePath).sorted() == ["IMG_1.JPG", "IMG_1.JPG"])
        #expect(Set(nas.rangeReadPaths) == ["A/IMG_1.JPG", "A/copy.JPG", "B/IMG_1.JPG"])
    }

    /// Subfolder and capture time must hold in every folder too.
    @Test func everySignNeedsEveryFolder() {
        let bySubfolder = [file(0, "2025/06/a.jpg", 100), file(1, "2025/06/b.jpg", 100), file(2, "other/c.jpg", 100)]
        let byCapture = [file(0, "p.jpg", 200), file(1, "q.jpg", 200), file(2, "r.jpg", 200)]
        let keys = [byCapture[0]: "t|1|R5", byCapture[1]: "t|1|R5", byCapture[2]: "t|2|R5"]

        let preview = CommonPhotosMatcher.preview(
            [[bySubfolder[0], byCapture[0]], [bySubfolder[1], byCapture[1]], [bySubfolder[2], byCapture[2]]],
            captureKeys: keys)

        #expect(preview.groups.count == 2)
        #expect(preview.likely.isEmpty)
    }

    /// One Unicode form, any case, for names and subfolders.
    @Test func namesMatchAcrossUnicodeForms() {
        let composed = file(0, "Chuyến đi/Ảnh.jpg", 100)
        let decomposed = file(1, "chuyến đi/ảnh.JPG".decomposedStringWithCanonicalMapping, 100)

        let preview = CommonPhotosMatcher.preview([[composed], [decomposed]])

        #expect(preview.likelyCount == 1)
    }

    /// A capture key needs the original time and the camera; the fraction
    /// joins it when written.
    @Test func captureKeyFromAJPEGHead() throws {
        let jpeg = try Self.jpeg(exif: [kCGImagePropertyExifDateTimeOriginal: "2025:06:01 10:00:00",
                                       kCGImagePropertyExifSubsecTimeOriginal: "42"],
                                 model: "Z 8")
        var padded = jpeg
        padded.append(Data(count: 200_000))

        #expect(CommonPhotosCaptureKey.key(fromHead: padded.prefix(CommonPhotosCaptureKey.headLength)) == "2025:06:01 10:00:00|42|Z 8")
        #expect(CommonPhotosCaptureKey.key(fromHead: try Self.jpeg(exif: [kCGImagePropertyExifDateTimeOriginal: "2025:06:01 10:00:00"], model: nil)) == nil)
        #expect(CommonPhotosCaptureKey.key(fromHead: Data("xx2025:06:01 10:00:00\0yy".utf8)) == nil)
    }

    /// Two same-size files with different names and the same capture time
    /// are Likely through the head read.
    @Test func sameCaptureTimeIsLikely() async throws {
        let shot = try Self.jpeg(exif: [kCGImagePropertyExifDateTimeOriginal: "2025:06:01 10:00:00",
                                       kCGImagePropertyExifSubsecTimeOriginal: "42"],
                                 model: "Z 8")
        let nas = InMemoryRemoteFileClient()
        nas.put("A/DSC_1.JPG", shot)
        nas.put("B/renamed.JPG", shot)
        let scanner = CommonPhotosScanner(client: nas)
        let listing = try await scanner.list(["A", "B"])
        let groups = CommonPhotosMatcher.sizeGroups(listing.files)

        let keys = try await scanner.captureKeys(for: groups, folders: ["A", "B"])
        let preview = CommonPhotosMatcher.preview(listing.files, captureKeys: keys)

        #expect(preview.likelyCount == 1)
    }

    /// Keys the index already holds are not read again; a file gone since
    /// the listing gives no key and does not stop the scan.
    @Test func captureKeysUseIndexAndSkipUnreadable() async throws {
        let nas = InMemoryRemoteFileClient()
        nas.put("A/p.JPG", Data(repeating: 3, count: 300))
        nas.put("B/q.JPG", Data(repeating: 3, count: 300))
        nas.put("B/gone.JPG", Data(repeating: 3, count: 300))
        let scanner = CommonPhotosScanner(client: nas)
        let listing = try await scanner.list(["A", "B"])
        let groups = CommonPhotosMatcher.sizeGroups(listing.files)
        let indexed = try #require(listing.files[0].first)
        try await nas.remove("B/gone.JPG")

        let keys = try await scanner.captureKeys(for: groups, folders: ["A", "B"], known: [indexed: "t|1|R5"])

        #expect(keys[indexed] == "t|1|R5")
        #expect(!nas.rangeReadPaths.contains("A/p.JPG"))
        #expect(nas.rangeReadPaths.contains("B/q.JPG"))
    }

    /// FS-19.08 §4: fewer than two folders, a folder inside another, or a
    /// destination inside a source cannot run.
    @Test func selectionProblems() {
        #expect(CommonPhotosSelection.problem(folders: ["A"], destination: "C") == .tooFewFolders)
        #expect(CommonPhotosSelection.problem(folders: ["A", "/a/"], destination: "C") == .tooFewFolders)
        #expect(CommonPhotosSelection.problem(folders: ["A", "A/B"], destination: "C") == .nested(outer: "A", inner: "A/B"))
        #expect(CommonPhotosSelection.problem(folders: ["A", "B", "A"], destination: "C") == .nested(outer: "A", inner: "A"))
        #expect(CommonPhotosSelection.problem(folders: ["A", "B"], destination: "B/Shared") == .destinationInsideSource(source: "B"))
        #expect(CommonPhotosSelection.problem(folders: ["A", "AB"], destination: "Shared") == nil)
        #expect(CommonPhotosSelection.problem(folders: ["A", "B"], destination: nil) == nil)
    }

    private static func jpeg(exif: [CFString: Any], model: String?) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        let context = try #require(CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        let image = try #require(context.makeImage())
        var properties: [CFString: Any] = [kCGImagePropertyExifDictionary: exif]
        if let model { properties[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFModel: model] }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

/// A WebDAV 206 must answer for the bytes asked.
@Suite struct WebDAVRangeStartTests {
    @Test func parsesContentRange() {
        #expect(WebDAVFileClient.rangeStart("bytes 100-199/1000") == 100)
        #expect(WebDAVFileClient.rangeStart("bytes 0-0/1") == 0)
        #expect(WebDAVFileClient.rangeStart(nil) == nil)
        #expect(WebDAVFileClient.rangeStart("garbage") == nil)
    }
}
