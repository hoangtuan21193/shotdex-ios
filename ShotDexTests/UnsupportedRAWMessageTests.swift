import Foundation
import ShotDexKit
import Testing
@testable import ShotDex

/// FS-03.04b AC-3: Edit on a RAW this iOS build can't read names the camera
/// and the version, says what to do, and opens nothing.
@MainActor
struct UnsupportedRAWMessageTests {
    typealias F = RAWVerdictFixtures

    static let ac3 = "iOS 27.0 doesn't support RAW files from the Sony ILCE-7M5 yet. Convert the file to DNG with Adobe DNG Converter, or wait for an iOS update that adds this camera."

    @Test func namesCameraAndVersion() {
        let message = UnsupportedRAWMessage.make(cameraName: "Sony ILCE-7M5", filename: "DSC_0001.ARW", iOSVersion: "27.0")
        #expect(message.text == Self.ac3)
        #expect(message.title == "Can't Edit This RAW")
    }

    /// The viewer's Edit reads it from the index alone: no file, no download.
    @Test func indexAnswersBeforeAnythingLoads() async throws {
        let arws = F.rows("s", 2, ext: "ARW", make: "SONY", model: "ILCE-7M5")
        let index = UnsupportedRAWIndex(
            store: RAWVerdictStore(database: try F.database(arws)),
            probe: FakeRAWProbe(local: ["s1", "s2"]),
            release: F.release
        )
        index.runPass()
        await index.waitForPass()
        #expect(index.message(for: "s1")?.text == Self.ac3)
        #expect(index.message(for: "someone-else") == nil)
    }

    /// The editor and Resize, for a photo the index had not judged: the
    /// camera comes from the file's own header.
    @Test(.enabled(if: RAWFixtures.has(RAWFixtures.fuji), "needs the RAW samples in ~/Library/Caches/ShotDexFixtures/raw/"))
    func fileHeaderNamesTheCamera() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("msg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = try #require(try RAWFixtures.unsupportedCamera(in: folder))
        let error = RAWFileCamera.error(for: url, filename: "DSCF0001.RAF", release: F.release)
        #expect(error.localizedDescription == "iOS 27.0 doesn't support RAW files from the Fujifilm X-Q9 yet. Convert the file to DNG with Adobe DNG Converter, or wait for an iOS update that adds this camera.")
        #expect(EditorLoadFailure.classify(error, accessIsLimited: false) == .unsupportedRAW(error.message))
    }

    @Test func editorFailureCarriesTheMessage() {
        let message = UnsupportedRAWMessage.make(cameraName: "Sony ILCE-7M5", filename: nil, iOSVersion: "27.0")
        let failure = EditorLoadFailure.classify(UnsupportedRAWError(message: message), accessIsLimited: false)
        #expect(failure.isUnsupportedRAW)
        #expect(failure.title == "Can't Edit This RAW")
        #expect(failure.message == Self.ac3)
        #expect(!failure.offersSettings)
        // The kit's bare refusal is still a RAW message, never "couldn't be decoded".
        #expect(EditorLoadFailure.classify(PhotoEditingError.unsupportedRAW, accessIsLimited: false).isUnsupportedRAW)
    }

    /// Resize's failure line is the same sentence (AC-14), and a pair still
    /// falls back to its JPEG on the named error.
    @Test func resizeFallsBackOnTheNamedError() async throws {
        let error = UnsupportedRAWError(message: .make(cameraName: "Sony ILCE-7M5", filename: nil, iOSVersion: "27.0"))
        #expect(error.localizedDescription == Self.ac3)
        let loaded = try await ReadableSource.load(preferred: "ARW", among: ["ARW", "JPG"], isRAW: { $0 == "ARW" }) { option -> String in
            if option == "ARW" { throw error }
            return option
        }
        #expect(loaded == "JPG")
    }
}

/// FS-03.04b Q7: in a multi-photo run, Skip leaves an unreadable photo for
/// the next one.
@MainActor
struct MultiPhotoEditSkipTests {
    static func origin(_ name: String) -> PhotoEditOrigin {
        let entry = RemoteEntry(name: name, isDirectory: false, size: 1, modified: nil)
        return .serverFile(FetchedServerPhoto(
            serverId: "S1", folder: "Trip", photo: ServerPhoto(files: [entry]),
            files: [FetchedFile(file: entry, url: URL(fileURLWithPath: "/tmp/\(name)"), sha256: "")]
        ))
    }

    @Test func skipGoesToTheNextPhotoOrBack() {
        let session = EditorSession(photos: ["a.JPG", "b.ARW", "c.JPG"].map(Self.origin), startIndex: 1)
        #expect(session.skipTarget == 2)
        session.moveToPhoto(at: 2)
        #expect(session.skipTarget == 1)
        #expect(EditorSession(photos: [Self.origin("b.ARW")]).skipTarget == nil)
    }

    /// The editor offers Skip, not a close that would drop the run's edits.
    @Test func alertOffersSkipInARun() throws {
        let screen = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Features/Editing/PhotoEditorScreen.swift")
            .joined(separator: "\n")
        #expect(screen.contains("if failure.isUnsupportedRAW, let skip {"))
        #expect(screen.contains("newController.failWithoutLoading(.unsupportedRAW(message))"))
    }
}
