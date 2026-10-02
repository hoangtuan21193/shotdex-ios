import Foundation
import ShotDexKit
import Testing
import UniformTypeIdentifiers
@testable import ShotDex

/// FS-03.04b §2: what the kit calls a RAW the decoder can't read.
@Suite struct PhotoRenderServiceInspectTests {
    let folder: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("inspect-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    @Test(.enabled(if: RAWFixtures.has(RAWFixtures.sony), "needs the RAW samples in ~/Library/Caches/ShotDexFixtures/raw/"))
    func readableRAWInspects() async throws {
        let url = try #require(RAWFixtures.available(RAWFixtures.sony))
        #expect(PhotoRenderService.canDecodeRAW(at: url))
        let info = try await PhotoRenderService().inspectSource(at: url)
        #expect(info.isRAW)
    }

    /// `CIRAWFilter(imageURL:)` is never nil, so the old nil check let these
    /// through to fail later as "couldn't be rendered".
    @Test(.enabled(if: RAWFixtures.has(RAWFixtures.fuji), "needs the RAW samples in ~/Library/Caches/ShotDexFixtures/raw/"))
    func cameraTheDecoderDoesNotKnowIsUnsupported() async throws {
        let url = try #require(try RAWFixtures.unsupportedCamera(in: folder))
        #expect(!PhotoRenderService.canDecodeRAW(at: url))
        await #expect(throws: PhotoEditingError.unsupportedRAW) {
            try await PhotoRenderService().inspectSource(at: url)
        }
    }

    @Test(.enabled(if: RAWFixtures.has(RAWFixtures.sony), "needs the RAW samples in ~/Library/Caches/ShotDexFixtures/raw/"))
    func cutOffRAWIsUnsupported() async throws {
        let url = try #require(try RAWFixtures.truncated(RAWFixtures.sony, bytes: 200_000, in: folder))
        await #expect(throws: PhotoEditingError.unsupportedRAW) {
            try await PhotoRenderService().inspectSource(at: url)
        }
    }

    @Test func junkIsNotDecodable() throws {
        #expect(!PhotoRenderService.canDecodeRAW(at: try RAWFixtures.junk(extension: "ARW", in: folder)))
    }

    /// AC-9: ImageIO can't read even the header — still a RAW refusal,
    /// by the file's extension or the resource's type.
    @Test func unreadableHeaderOfARAWIsUnsupported() async throws {
        let junk = try RAWFixtures.junk(extension: "ARW", in: folder)
        await #expect(throws: PhotoEditingError.unsupportedRAW) {
            try await PhotoRenderService().inspectSource(at: junk)
        }
        let renamed = folder.appendingPathComponent("source-1.image")
        try FileManager.default.copyItem(at: junk, to: renamed)
        await #expect(throws: PhotoEditingError.unsupportedRAW) {
            try await PhotoRenderService().inspectSource(at: renamed, typeHint: UTType("com.sony.arw-raw-image"))
        }
    }

    @Test(.enabled(if: RAWFixtures.has(RAWFixtures.sony), "needs the RAW samples in ~/Library/Caches/ShotDexFixtures/raw/"))
    func firstTwoKilobytesOfAnARWAreUnsupported() async throws {
        let url = try #require(try RAWFixtures.truncated(RAWFixtures.sony, bytes: 2_000, in: folder))
        await #expect(throws: PhotoEditingError.unsupportedRAW) {
            try await PhotoRenderService().inspectSource(at: url)
        }
        // And the message names the extension, since there is no camera.
        let error = RAWFileCamera.error(for: url, filename: "DSC00001.ARW", release: RAWVerdictFixtures.release)
        #expect(error.localizedDescription.hasPrefix("iOS 27.0 doesn't support RAW files like this .ARW yet."))
        #expect(!error.localizedDescription.contains("couldn't be decoded"))
    }

    /// A broken JPEG is not a RAW: the generic sentence stays.
    @Test func junkJPEGIsStillCannotDecode() async throws {
        let junk = try RAWFixtures.junk(extension: "jpg", in: folder)
        await #expect(throws: PhotoEditingError.cannotDecode) {
            try await PhotoRenderService().inspectSource(at: junk)
        }
    }
}
