import Foundation
import Testing
@testable import ShotDex

/// FS-19.01 §2 — what a folder source reads.
@Suite struct FolderEnumerationTests {
    /// AC-4: `Pictures` holds a Photos library package (500 photos inside),
    /// 20 JPGs and 3 dot files. Adding it finds exactly the 20 JPGs (and the
    /// sidecar beside one of them, as a sidecar); nothing inside the package
    /// is listed. A text file is not a photo.
    @Test func skipsPackagesAndDotFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Pictures-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let jpeg = try MetadataFixture.encode(.jpeg, options: MetadataFixture.Options())
        let library = root.appendingPathComponent("Photos Library.photoslibrary/originals/0", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        for n in 0..<500 { try jpeg.write(to: library.appendingPathComponent("IMG_\(n).JPG")) }
        let day = root.appendingPathComponent("2026 Japan/Day 1", isDirectory: true)
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        for n in 0..<20 { try jpeg.write(to: day.appendingPathComponent("DSC0\(4500 + n).JPG")) }
        try Data("<x:xmpmeta/>".utf8).write(to: day.appendingPathComponent("DSC04500.xmp"))
        for name in [".DS_Store", ".hidden.jpg", "._DSC04500.JPG"] { try jpeg.write(to: day.appendingPathComponent(name)) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".Trashes/1"), withIntermediateDirectories: true)
        try jpeg.write(to: root.appendingPathComponent(".Trashes/1/old.jpg"))
        try Data("notes".utf8).write(to: day.appendingPathComponent("notes.txt"))

        let entries = FolderEnumeration.entries(in: root, includeSubfolders: true)
        let photos = entries.filter { !$0.isSidecar }
        #expect(photos.count == 20)
        #expect(photos.allSatisfy { $0.relativePath.hasPrefix("2026 Japan/Day 1/DSC0") })
        #expect(entries.filter(\.isSidecar).map(\.relativePath) == ["2026 Japan/Day 1/DSC04500.xmp"])
        #expect(photos.first?.size == Int64(jpeg.count))

        // Subfolders off: only the top level, which holds no photo here.
        #expect(FolderEnumeration.entries(in: root, includeSubfolders: false).isEmpty)
        #expect(FolderEnumeration.isReadable(URL(fileURLWithPath: "/x/DSC04512.ARW")))
        #expect(FolderEnumeration.isReadable(URL(fileURLWithPath: "/x/IMG_0420.HEIC")))
        #expect(FolderEnumeration.isReadable(URL(fileURLWithPath: "/x/clip.MOV")))
        #expect(!FolderEnumeration.isReadable(URL(fileURLWithPath: "/x/notes.txt")))
    }
}
