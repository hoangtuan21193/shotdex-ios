import Foundation
import Testing
@testable import ShotDex

/// FS-17.01 §2: a folder listing becomes subfolders plus image tiles.
@Suite struct ServerFolderListingTests {
    private func file(_ name: String, _ size: Int64 = 100) -> RemoteEntry {
        RemoteEntry(name: name, isDirectory: false, size: size, modified: nil)
    }

    private func folder(_ name: String) -> RemoteEntry {
        RemoteEntry(name: name, isDirectory: true, size: 0, modified: nil)
    }

    /// AC-1.
    @Test func imagesOnlyAndPairs() {
        let entries = [
            file("A.CR3", 30_000_000), file("A.JPG", 6_000_000), file("B.heic"), file("C.png"), file("D.MOV"),
            file("notes.txt"), file(".DS_Store"), file("E.NEF"), file("e.jpeg"), folder("2025"), folder(".snapshots"),
        ]
        let contents = ServerFolderListing.contents(of: entries)
        #expect(contents.folders == ["2025"])
        #expect(contents.photos.map(\.id) == ["A.JPG", "B.heic", "C.png", "e.jpeg"])
        #expect(contents.photos.map(\.badge) == ["RAW+JPG", "HEIC", "PNG", "RAW+JPG"])
        #expect(contents.photos[0].files.map(\.name) == ["A.JPG", "A.CR3"])
        #expect(contents.photos[0].totalBytes == 36_000_000)
        #expect(contents.photos[3].raw?.name == "E.NEF")
        #expect(contents.hiddenFileCount == 2)
    }

    /// AC-2: the image set comes from ImageIO, not a hand list.
    @Test func formatsFromImageIO() {
        for name in ["a.heic", "a.dng", "a.cr3", "a.arw", "a.raf", "a.tif", "a.webp", "a.jpg", "a.png"] {
            #expect(ServerFolderListing.isImage(name), "\(name) should be an image")
        }
        for name in ["a.mov", "a.txt", "a.xmp", "a.mp4"] {
            #expect(!ServerFolderListing.isImage(name), "\(name) should not be an image")
        }
    }

    @Test func twoRawsWithOneJpegStaySeparate() {
        let contents = ServerFolderListing.contents(of: [file("X.CR3"), file("x.cr2"), file("X.JPG")])
        #expect(contents.photos.count == 3)
        #expect(contents.photos.allSatisfy { !$0.isPair })
    }

    @Test func rangeReadReadsOnlyTheHead() async throws {
        let client = InMemoryRemoteFileClient()
        client.put("Photos/a.CR3", Data((0..<1_000).map { UInt8($0 % 251) }))
        let head = try await client.readRange("Photos/a.CR3", offset: 0, length: 512)
        #expect(head.count == 512)
        #expect(client.bytesRead == 512)
        let tail = try await client.readRange("Photos/a.CR3", offset: 900, length: 512)
        #expect(tail.count == 100)
        let listed = try await client.entries(in: "Photos")
        #expect(listed.map(\.name) == ["a.CR3"])
        #expect(listed.first?.size == 1_000)
    }
}
