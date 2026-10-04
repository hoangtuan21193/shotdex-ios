import Foundation
import ShotDexKit
import Testing
@testable import ShotDex

/// FS-03.04b AC-14: Resize over a batch holding RAWs the decoder can't read.
@MainActor
@Suite(.serialized) struct CompressionRAWPairTests {
    struct Option: Equatable {
        let name: String
        let isRAW: Bool
    }

    static let raw = Option(name: "DSC_0001.ARW", isRAW: true)
    static let jpeg = Option(name: "DSC_0001.JPG", isRAW: false)

    /// Q6: a pair whose RAW the decoder refuses is resized from its JPEG.
    @Test func unreadablePairUsesJPEG() async throws {
        var tried: [String] = []
        let loaded = try await ReadableSource.load(
            preferred: Self.raw, among: [Self.raw, Self.jpeg], isRAW: \.isRAW
        ) { option -> String in
            tried.append(option.name)
            if option.isRAW { throw PhotoEditingError.unsupportedRAW }
            return option.name
        }
        #expect(loaded == "DSC_0001.JPG")
        #expect(tried == ["DSC_0001.ARW", "DSC_0001.JPG"])
    }

    @Test func readablePairKeepsRAW() async throws {
        let loaded = try await ReadableSource.load(
            preferred: Self.raw, among: [Self.raw, Self.jpeg], isRAW: \.isRAW
        ) { $0.name }
        #expect(loaded == "DSC_0001.ARW")
    }

    /// A RAW-only photo has no twin: the decoder's refusal is the photo's
    /// failure, not a silent switch to anything else.
    @Test func unreadableRAWOnlyFails() async {
        await #expect(throws: PhotoEditingError.unsupportedRAW) {
            try await ReadableSource.load(preferred: Self.raw, among: [Self.raw], isRAW: \.isRAW) { option -> String in
                throw PhotoEditingError.unsupportedRAW
            }
        }
    }

    /// Only the decoder's refusal falls back; a RAW that failed for another
    /// reason (iCloud, a damaged write) fails as itself.
    @Test func otherFailuresDoNotFallBack() async {
        await #expect(throws: PhotoEditingError.missingSource) {
            try await ReadableSource.load(
                preferred: Self.raw, among: [Self.raw, Self.jpeg], isRAW: \.isRAW
            ) { option -> String in
                if option.isRAW { throw PhotoEditingError.missingSource }
                return option.name
            }
        }
    }

    /// The preview is the first photo that loads; the RAW first in the
    /// batch does not fail the whole sheet.
    @Test func previewTakesFirstReadable() async throws {
        let batch = ["RAW-1", "JPG-2", "JPG-3"]
        let first = try await ReadableSource.firstLoadable(batch) { name -> String in
            if name.hasPrefix("RAW") { throw PhotoEditingError.unsupportedRAW }
            return "preview of \(name)"
        }
        #expect(first.item == "JPG-2")
        #expect(first.loaded == "preview of JPG-2")
    }

    @Test func previewOfNothingReadableFails() async {
        await #expect(throws: PhotoEditingError.unsupportedRAW) {
            try await ReadableSource.firstLoadable(["RAW-1"]) { _ -> String in
                throw PhotoEditingError.unsupportedRAW
            }
        }
    }

    /// AC-14's run: 2 JPEGs, an unreadable RAW-only and a pair (resized from
    /// its JPEG by the service) → three copies, one line in the failure list
    /// naming the RAW, and only the three resized originals deleted.
    @Test func batchListsTheRAWAndCarriesOn() async throws {
        var created: [String] = []
        var deleted: [String] = []
        let photos = [
            OriginalItem.test("01"),
            OriginalItem(id: "02", filename: "DSC_0002.ARW", photo: PixelSize(width: 60, height: 40)),
            OriginalItem.test("03"),
            OriginalItem(id: "04", filename: "DSC_0004.JPG", photo: PixelSize(width: 60, height: 40)),
        ]
        let operations = ResizeOperations(
            compress: { photo, _, _ in
                if photo.id == "02" { throw PhotoEditingError.unsupportedRAW }
                created.append("copy-\(photo.id)")
                return PhotoSaveResult(assetID: "copy-\(photo.id)", format: .jpeg, fellBackToJPEG: false)
            },
            deleteOriginals: { deleted += $0 },
            removeCreated: { _ in }
        )
        let fetcher = FakeOriginalFetcher(script: .init("cloud=none"), base: FixtureOriginalFetcher())
        let controller = CompressionController(photos: photos, operations: operations, fetcher: fetcher)
        controller.deleteOriginals = true
        controller.startExport()
        for _ in 0..<150 where !controller.didFinish { try await Task.sleep(for: .milliseconds(40)) }
        #expect(controller.didFinish)
        #expect(created == ["copy-01", "copy-03", "copy-04"])
        #expect(controller.failures.map(\.filename) == ["DSC_0002.ARW"])
        #expect(controller.failures.first?.message == PhotoEditingError.unsupportedRAW.localizedDescription)
        #expect(deleted == ["01", "03", "04"])
    }
}
