import Foundation
import Testing
@testable import ShotDex

/// FS-17.06 §6b: one file made from several server photos — a collage, a
/// combined photo, a video — goes out once per destination under the name
/// typed in the sheet.
@Suite struct ServerComposedExportTests {
    typealias Fixture = ServerEditExportTests.Fixture

    private func composedFile(_ fixture: Fixture, _ bytes: String = "collage") throws -> URL {
        let folder = fixture.directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("render.jpg")
        try Data(bytes.utf8).write(to: url)
        return url
    }

    /// AC-77: the name starts as the first photo's, with the tool's suffix.
    @Test func composedNamesFromFirstPhoto() {
        #expect(ServerComposedName.defaultBase(firstFilename: "DSCF1000.JPG", tool: .collage) == "DSCF1000_collage")
        #expect(ServerComposedName.defaultBase(firstFilename: "DSCF1000.RAF", tool: .focusStack) == "DSCF1000_focus-stack")
        #expect(ServerComposedName.defaultBase(firstFilename: "IMG_1.HEIC", tool: .panorama) == "IMG_1_panorama")
        #expect(ServerComposedName.defaultBase(firstFilename: "a.jpg", tool: .stack) == "a_stack")
        #expect(ServerComposedName.defaultBase(firstFilename: "a.jpg", tool: .video) == "a_video")
    }

    /// AC-78: a name that leaves nothing once cleaned is no name.
    @Test func composedNameIsCleaned() {
        #expect(ServerComposedName.sanitized("") == nil)
        #expect(ServerComposedName.sanitized("   ") == nil)
        #expect(ServerComposedName.sanitized("/") == nil)
        #expect(ServerComposedName.sanitized(" / : \\ ") == nil)
        #expect(ServerComposedName.sanitized("Trip/Day 1") == "TripDay 1")
        #expect(ServerComposedName.sanitized(".hidden") == "hidden")
        #expect(ServerComposedName.filename(typed: " Trip ", fileExtension: "jpg") == "Trip.jpg")
        #expect(ServerComposedName.filename(typed: "/", fileExtension: "jpg") == nil)
    }

    /// AC-77: Original Folder gets `DSCF1000_collage.jpg`, a second export
    /// ` (2)`, a typed name its own — the originals untouched, nothing
    /// replaced.
    @Test func composedWritesUnderTypedNameAndNeverReplaces() async throws {
        let fixture = Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let photos = [try fixture.photo("DSCF1000.JPG"), try fixture.photo("DSCF1001.JPG")]
        let originals = fixture.client.files
        let file = try composedFile(fixture)

        func export(_ name: String) async -> ServerExportReport {
            await fixture.exporter(fixture.services()).run(.init(
                photos: photos, destinations: [.originalFolder], placement: .newFile, format: .jpeg,
                composed: ComposedOutput(file: file, filename: name, folder: "Trip")
            ))
        }

        let first = await export("DSCF1000_collage.jpg")
        #expect(first.outcome(.originalFolder, ComposedOutput.id) == .done("Trip/DSCF1000_collage.jpg"))
        #expect(first.isComplete(ids: [ComposedOutput.id], destinations: [.originalFolder]))
        let second = await export("DSCF1000_collage.jpg")
        #expect(second.outcome(.originalFolder, ComposedOutput.id) == .done("Trip/DSCF1000_collage (2).jpg"))
        let typed = await export("Trip.jpg")
        #expect(typed.outcome(.originalFolder, ComposedOutput.id) == .done("Trip/Trip.jpg"))

        #expect(fixture.client.files["Trip/DSCF1000_collage.jpg"] == Data("collage".utf8))
        for (path, data) in originals { #expect(fixture.client.files[path] == data) }
        #expect(!fixture.client.files.keys.contains { $0.contains("_edited") })
        #expect(!fixture.client.files.keys.contains { $0.hasSuffix(ServerUploadPath.partSuffix) })
    }

    /// Photos and Share see the typed name, not the render's scratch name.
    @Test func composedCarriesItsNameToPhotosAndShare() async throws {
        let fixture = Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let photos = [try fixture.photo("DSCF1000.JPG")]
        let saved = ServerEditExportTests.SavedBox()
        let file = try composedFile(fixture)

        let report = await fixture.exporter(fixture.services(saved: saved)).run(.init(
            photos: photos, destinations: [.photosLibrary, .share], placement: .newFile, format: .jpeg,
            composed: ComposedOutput(file: file, filename: "Trip.jpg", folder: "Trip")
        ))

        #expect(report.isComplete(ids: [ComposedOutput.id], destinations: [.photosLibrary, .share]))
        #expect(saved.items.map(\.name) == ["Trip.jpg"])
        #expect(saved.items.first?.data == Data("collage".utf8))
        #expect(report.shareFiles.map(\.lastPathComponent) == ["Trip.jpg"])
    }

    /// AC-81: a video goes into Photos as a video.
    @Test func moviesAreRecognisedByExtension() {
        #expect(ServerExportRules.isMovie(URL(fileURLWithPath: "/t/a_video.mp4")))
        #expect(ServerExportRules.isMovie(URL(fileURLWithPath: "/t/a.MOV")))
        #expect(!ServerExportRules.isMovie(URL(fileURLWithPath: "/t/a_collage.jpg")))
    }
}
