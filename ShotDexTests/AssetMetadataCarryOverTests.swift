import Foundation
import ShotDexKit
import Testing
@testable import ShotDex

/// FS-08.06 AC-17 — Save Changes edits the photo in place, so the asset's date
/// and location are the user's own data and never something a save clears.
/// PhotoKit change requests can't run in a unit test, so this reads the source
/// the way `EditorStringsTests` does.
struct AssetMetadataCarryOverTests {

    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// Code lines of a Swift file, comments left out.
    static func codeLines(of path: String) throws -> [String] {
        let text = try String(contentsOf: repository.appendingPathComponent(path), encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            var code = String(line)
            if let comment = code.range(of: "//") { code = String(code[..<comment.lowerBound]) }
            return code
        }
    }

    /// AC-17. No editing path clears an asset's date or location, and Save
    /// Changes takes no metadata switch that could ask it to.
    @Test func saveChangesNeverTouchesDateOrLocation() throws {
        let service = try Self.codeLines(of: "ShotDex/Data/Sources/PhotoEditingService.swift")
        for line in service {
            #expect(!line.contains("creationDate = nil"), "\(line)")
            #expect(!line.contains("location = nil"), "\(line)")
        }

        let body = service.joined(separator: "\n")
        let start = try #require(body.range(of: "func saveChanges("))
        let signature = body[start.lowerBound...].prefix { $0 != "{" }
        #expect(!signature.contains("includeMetadata"), "Save Changes offers no metadata choice")

        let controller = try Self.codeLines(of: "ShotDex/Features/Editing/PhotoEditorController.swift")
            .joined(separator: "\n")
        #expect(controller.contains("func saveChanges(format: PhotoOutputFormat) async"))
    }

    /// AC-12: a Save Copy at No Location gives the new asset the original's
    /// date and no location; All keeps both; No Metadata neither.
    @Test func saveCopyCarriesDateNotLocation() {
        #expect(AssetMetadataCarryOver(level: .noLocation) == .init(keepsDate: true, keepsLocation: false))
        #expect(AssetMetadataCarryOver(level: .all) == .init(keepsDate: true, keepsLocation: true))
        #expect(AssetMetadataCarryOver(level: .noMetadata) == .init(keepsDate: false, keepsLocation: false))
    }

    /// Every new asset a save creates goes through the carry-over, and the
    /// editor's Save Copy hands it the sheet's level.
    @Test func saveCopyUsesTheLevel() throws {
        let service = try Self.codeLines(of: "ShotDex/Data/Sources/PhotoEditingService.swift").joined(separator: "\n")
        #expect(service.components(separatedBy: "AssetMetadataCarryOver(level: metadata)").count - 1 == 2)
        #expect(!service.contains("includeMetadata"))
        let sheet = try Self.codeLines(of: "ShotDex/Features/Editing/PhotoEditorScreen.swift").joined(separator: "\n")
        #expect(sheet.contains("controller.saveCopy(format: format, metadata: copyMetadata)"))
        #expect(sheet.contains("MetadataLevel.sharingDefault()"))
    }
}
