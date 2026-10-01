import CoreGraphics
import Foundation
import Testing
@testable import ShotDex

/// FS-02.06 AC-12: a collage cell whose original does not come down stops
/// the export — nothing is saved with an empty or soft cell.
@MainActor
@Suite struct CollagePreparationTests {
    static func image(_ width: Int, _ height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }

    func cells(_ count: Int, side: Int = 200) -> [CollagePreparationTests.Cell] {
        (0..<count).map {
            .init(index: $0, item: OriginalItem(id: "P\($0)", filename: "IMG_\($0).HEIC", photo: PixelSize(width: 600, height: 400)), side: side)
        }
    }
    typealias Cell = CollageExportPreparation.Cell

    /// AC-12. Four cells, one only in iCloud and not coming down: the
    /// export fails before drawing, naming the one photo, with Retry.
    @Test func oneCellFailingStopsTheExport() async {
        let fake = FakeOriginalFetcher(script: .init("cloud=1,seconds=0.2,fail=1"), base: FixtureOriginalFetcher())
        let preparation = CollageExportPreparation(cells: cells(4), fetcher: fake)
        var loaded: [Int] = []
        let outcome = await preparation.run { cell, _ in
            loaded.append(cell.index)
            return Self.image(200, 133)
        }
        guard case .failed = outcome else { Issue.record("saved with a missing cell"); return }
        #expect(preparation.state.phase == .failed)
        #expect(preparation.state.failureTitle == "1 of 4 photos couldn't be downloaded from iCloud.")
        #expect(preparation.state.failedNames == ["IMG_0.HEIC"])
        #expect(loaded == [1, 2, 3])
    }

    /// §3. A cell that arrives soft — under 90% of its size — counts as not
    /// arrived; one at 90% is enough.
    @Test func aSoftCellIsAFailure() async {
        let fake = FakeOriginalFetcher(script: .init("cloud=none"), base: FixtureOriginalFetcher())
        let preparation = CollageExportPreparation(cells: cells(2, side: 300), fetcher: fake)
        let outcome = await preparation.run { cell, _ in
            cell.index == 0 ? Self.image(269, 179) : Self.image(270, 180)
        }
        guard case .failed = outcome else { Issue.record("a soft cell was drawn"); return }
        #expect(preparation.state.failedNames == ["IMG_0.HEIC"])
    }

    /// All cells in: the images go to the compositor.
    @Test func everyCellInDraws() async {
        let fake = FakeOriginalFetcher(script: .init("cloud=2,seconds=0.1"), base: FixtureOriginalFetcher())
        let preparation = CollageExportPreparation(cells: cells(4), fetcher: fake)
        let outcome = await preparation.run { _, _ in Self.image(200, 133) }
        guard case .ready(let images) = outcome else { Issue.record("failed"); return }
        #expect(images.count == 4)
        #expect(preparation.state.downloadCount == 2)
        #expect(fake.downloadCount == 2)
    }

    /// AC-12. The export returns before saving when the preparation failed.
    @Test func exportSavesNothingAfterAFailure() throws {
        let model = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Features/Collage/CollageEditorModel.swift")
            .joined(separator: "\n")
        let failed = try #require(model.range(of: "guard case .ready(let loaded) = outcome else { return }"))
        let save = try #require(model.range(of: "photoLibrary.saveImage("))
        let compose = try #require(model.range(of: "CollageCompositor.render(", range: failed.upperBound..<model.endIndex))
        #expect(failed.lowerBound < compose.lowerBound)
        #expect(failed.lowerBound < save.lowerBound)
    }
}
