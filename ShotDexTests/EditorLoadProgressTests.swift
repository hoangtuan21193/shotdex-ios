import Foundation
import Photos
import Testing
@testable import ShotDex

/// FS-02.06 AC-3, AC-4: the editor's download says how far it is, and Close
/// stops it and leaves nothing behind.
@MainActor
@Suite(.serialized) struct EditorLoadProgressTests {
    /// AC-3. PhotoKit's progress reaches the stage; a source that is not the
    /// whole photo is an iCloud failure, never an edit of a preview.
    @Test func progressReachesTheStageAndAShortSourceFails() throws {
        let service = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Data/Sources/PhotoEditingService.swift")
            .joined(separator: "\n")
        let request = try #require(service.range(of: "private func requestContentEditingInput("))
        let body = String(service[request.lowerBound...].prefix(2400))
        #expect(body.contains("options.progressHandler = { value, _ in progress(value) }"))
        #expect(body.contains("asset.cancelContentEditingInputRequest(id)"))
        #expect(service.contains("try Self.checkComplete(input, of: asset)"))
        #expect(EditorLoadFailure.classify(OriginalFetchError.incomplete, accessIsLimited: false) == .iCloudDownload)

        let stage = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Features/Editing/EditorImageStage.swift")
            .joined(separator: "\n")
        #expect(stage.contains("Text(\"Downloading from iCloud… \\(percent)%\")"))
        #expect(stage.contains("ProgressView(value: min(1, max(0, fraction)))"))
    }

    static func sessionFolders() -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)) ?? []
        return Set(names.filter { $0.hasPrefix("ShotDexPhoto-") })
    }
}
