import Foundation
import Testing
@testable import ShotDex

/// FS-02.06 AC-17: the grid has no iCloud mark, because telling which
/// originals are in iCloud means asking PhotoKit about every visible cell
/// (NF-01 rules 1 and 4). The mark lives in the viewer and the filmstrip.
@Suite struct GridICloudFreeTests {
    /// AC-17. Nothing the grid draws a cell with asks PhotoKit for resources,
    /// image data or an in-cloud flag, and no cell says "Original in iCloud".
    @Test func gridHasNoPerCellResourceQuery() throws {
        let files = [
            "ShotDex/Features/Shared/PhotoGridCollectionView.swift",
            "ShotDex/Features/Shared/PhotoGridLayout.swift",
            "ShotDex/Domain/Grid/PhotoGridSections.swift",
        ]
        let forbidden = [
            "PHAssetResource",
            "requestImageDataAndOrientation",
            "requestImageData(",
            "PHImageResultIsInCloudKey",
            "OriginalFetching",
            "Original in iCloud",
            "icloud",
        ]
        for path in files {
            let code = try AssetMetadataCarryOverTests.codeLines(of: path)
            #expect(code.count > 20, "\(path) was not read")
            for (number, line) in code.enumerated() {
                for word in forbidden where line.localizedCaseInsensitiveContains(word) {
                    Issue.record("\(path):\(number + 1) has \(word)")
                }
            }
        }
    }
}
