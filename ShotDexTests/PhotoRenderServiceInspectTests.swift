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
}
