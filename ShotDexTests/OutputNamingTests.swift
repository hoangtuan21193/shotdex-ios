import CryptoKit
import ImageIO
import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-18 AC-52 / FS-03.06 §2 — Save as Copy beside the original.
struct OutputNamingTests {
    @Test func editedSuffixAndCounter() {
        #expect(OutputNaming.editedCopy(of: "DSCF4127.RAF", fileExtension: "jpg", existing: ["DSCF4127.RAF"])
                == "DSCF4127 (edited).jpg")
        #expect(OutputNaming.editedCopy(of: "DSCF4127.RAF", fileExtension: "jpg", existing: ["DSCF4127.RAF", "dscf4127 (EDITED).JPG"])
                == "DSCF4127 (edited) (2).jpg")
        #expect(OutputNaming.editedCopy(of: "DSCF4127.RAF", fileExtension: "jpg",
                                        existing: ["DSCF4127 (edited).jpg", "DSCF4127 (edited) (2).jpg"])
                == "DSCF4127 (edited) (3).jpg")
        #expect(OutputNaming.copyExtension(of: "IMG_1.HEIC", format: .preserve, encodesHEIC: true) == "heic")
        #expect(OutputNaming.copyExtension(of: "IMG_1.HEIC", format: .preserve, encodesHEIC: false) == "jpg")
        #expect(OutputNaming.copyExtension(of: "DSCF4127.RAF", format: .preserve, encodesHEIC: true) == "jpg")
    }

    /// Two Save as Copy runs: `(edited)` then `(edited) (2)`, each a whole
    /// JPEG, no part file left, and the original's bytes unchanged.
    @Test func writesBesideTheOriginalTwice() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SaveCopy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let original = folder.appendingPathComponent("DSCF4127.JPG")
        try MetadataFixture.encode(.jpeg, options: MetadataFixture.Options()).write(to: original)
        let before = SHA256.hash(data: try Data(contentsOf: original))

        var recipe = PhotoEditRecipe.identity
        recipe.adjustments.exposure = 0.65
        let writer = EditedCopyWriter()
        let first = try await writer.write(recipe, of: original, format: .preserve)
        let second = try await writer.write(recipe, of: original, format: .preserve)

        #expect(first.lastPathComponent == "DSCF4127 (edited).jpg")
        #expect(second.lastPathComponent == "DSCF4127 (edited) (2).jpg")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(names == ["DSCF4127 (edited) (2).jpg", "DSCF4127 (edited).jpg", "DSCF4127.JPG"])
        #expect(SHA256.hash(data: try Data(contentsOf: original)) == before)
        #expect(CGImageSourceCreateWithURL(first as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) } != nil)
    }
}
