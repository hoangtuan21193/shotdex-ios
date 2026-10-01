import Foundation
import ImageIO
import Testing
@testable import ShotDex

/// FS-02.06 AC-11: the pixel count, not PhotoKit's "final result" label,
/// decides whether the original is on hand.
@Suite struct OriginalCompletenessTests {
    let photo = PixelSize(width: 6000, height: 4000)

    /// AC-11. A 1536×1024 preview that PhotoKit labels final is not the
    /// original of a 6000×4000 photo.
    @Test func optimizeStoragePreviewIsNotTheOriginal() {
        #expect(!OriginalCompleteness.isOriginal(received: PixelSize(width: 1536, height: 1024), photo: photo))
        #expect(OriginalAvailability.judge(received: PixelSize(width: 1536, height: 1024), photo: photo) == .inCloud)
        #expect(OriginalAvailability.judge(received: nil, photo: photo) == .inCloud)
        #expect(OriginalCompleteness.isOriginal(received: photo, photo: photo))
        #expect(OriginalAvailability.judge(received: photo, photo: photo) == .local)
    }

    /// AC-11. A file stored 4000×6000 with a quarter-turn orientation is
    /// shown 6000×4000: it is the original. Without the turn it is not.
    @Test func quarterTurnSwapsTheEdges() {
        let stored = PixelSize(width: 4000, height: 6000)
        for orientation in [CGImagePropertyOrientation.right, .left, .rightMirrored, .leftMirrored] {
            #expect(OriginalCompleteness.isOriginal(received: stored, orientation: orientation, photo: photo))
        }
        #expect(!OriginalCompleteness.isOriginal(received: stored, orientation: .up, photo: photo))
        #expect(!OriginalCompleteness.isOriginal(received: photo, orientation: .right, photo: photo))
    }

    /// AC-11. A rendition asked for at 1800px: 1620 (90%) is enough, 1619 is
    /// not; a photo smaller than the size asked for is judged on its own
    /// long edge.
    @Test func sizedRenditionAtNinetyPercent() {
        #expect(OriginalCompleteness.isSufficient(received: PixelSize(width: 1620, height: 1080), requestedLongEdge: 1800, photo: photo))
        #expect(!OriginalCompleteness.isSufficient(received: PixelSize(width: 1619, height: 1079), requestedLongEdge: 1800, photo: photo))
        #expect(OriginalCompleteness.isSufficient(received: PixelSize(width: 1080, height: 1620), requestedLongEdge: 1800, photo: photo))
        let small = PixelSize(width: 1200, height: 800)
        #expect(OriginalCompleteness.isSufficient(received: PixelSize(width: 1080, height: 720), requestedLongEdge: 1800, photo: small))
        #expect(!OriginalCompleteness.isSufficient(received: PixelSize(width: 1079, height: 719), requestedLongEdge: 1800, photo: small))
    }

    /// The check reads the header only: a written JPEG reports its stored
    /// size and orientation.
    @Test func measuresAFileWithoutDecoding() throws {
        var options = MetadataFixture.Options()
        options.width = 64
        options.height = 32
        let data = try MetadataFixture.encode(.jpeg, options: options)
        let measured = try #require(OriginalCompleteness.measure(data))
        #expect(measured.size == PixelSize(width: 64, height: 32))
    }
}
