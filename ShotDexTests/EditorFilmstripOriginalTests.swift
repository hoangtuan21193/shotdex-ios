import Foundation
import Testing
@testable import ShotDex

/// FS-02.06 AC-13: a filmstrip cell says where its original is — a glyph
/// while it is only in iCloud, a ring while the preloader brings it down.
@MainActor
@Suite struct EditorFilmstripOriginalTests {
    /// AC-13. The preloader's progress moves the cell from glyph to ring to
    /// nothing; a download that stops goes back to the glyph.
    @Test func reportsPerPhotoProgress() throws {
        let session = EditorSession(photos: [])
        session.reportOriginalDownload("3", fraction: 0.25)
        #expect(session.originalStates["3"] == .downloading(0.25))
        session.reportOriginalDownload("3", fraction: 0.6)
        #expect(session.originalStates["3"] == .downloading(0.6))
        session.markOriginalLocal("3")
        #expect(session.originalStates["3"] == .local)
        session.reportOriginalDownload("3", fraction: 0.1)
        #expect(session.originalStates["3"] == .local)

        session.reportOriginalDownload("4", fraction: 0.4)
        session.markOriginalDownloadEnded("4")
        #expect(session.originalStates["4"] == .inCloud)

        let preloader = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Features/Editing/EditorPreviewPreloader.swift")
            .joined(separator: "\n")
        #expect(preloader.contains("run?.reportOriginalDownload(photo.id, fraction: fraction)"))
        let cell = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Features/Editing/EditorSession.swift")
            .joined(separator: "\n")
        #expect(cell.contains("ICloudDownloadRing(progress: fraction)"))
        #expect(cell.contains("Image(systemName: \"icloud\")"))
    }
}
