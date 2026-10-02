import Foundation
import Testing
@testable import ShotDex

/// FS-02.06 §5–§9: the numbers and sentences of one batch's preparation.
@Suite struct OriginalPreparationStateTests {
    /// AC-2. The ring has no number; VoiceOver reads the percent, rounded
    /// down, held to 0…100.
    @Test func accessibilityPercent() {
        #expect(OriginalPreparationState.accessibilityProgress(0.41) == "Downloading from iCloud, 41 percent")
        #expect(OriginalPreparationState.accessibilityProgress(0.999) == "Downloading from iCloud, 99 percent")
        #expect(OriginalPreparationState.accessibilityProgress(1.2) == "Downloading from iCloud, 100 percent")
        #expect(OriginalPreparationState.accessibilityProgress(-1) == "Downloading from iCloud, 0 percent")
        let viewer = try? AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Features/Library/PhotoDetailScreen.swift")
            .joined(separator: "\n")
        #expect(viewer?.contains("OriginalPreparationState.accessibilityProgress(downloadProgress)") == true)
    }

    /// AC-14. The message the room check shows.
    @Test func notEnoughSpaceWording() {
        #expect(OriginalPreparationState.notEnoughSpaceMessage(needed: 1_400_000_000, free: 380_000_000)
            == "Not enough space to download these originals — needs 1.4 GB, 380 MB free.")
        #expect(!OriginalPreparationState.fits(needed: 1_400_000_000, free: 380_000_000))
        #expect(OriginalPreparationState.fits(needed: 300_000_000, free: 380_000_000))
        #expect(OriginalPreparationState.fits(needed: 1_400_000_000, free: nil))
    }

    /// AC-2. Zoomed in, the chrome is hidden, so the download shows as the
    /// ring alone in the corner — or the stall glyph — and as nothing once
    /// the original is here. With the chrome up it stays in the panel.
    @Test func zoomedDownloadShowsTheRingAlone() throws {
        typealias I = ViewerDownloadIndicator
        #expect(I.placement(isChromeVisible: false, isZoomed: true, isDownloading: true, isStalled: false) == .cornerRing)
        #expect(I.placement(isChromeVisible: false, isZoomed: true, isDownloading: true, isStalled: true) == .cornerStall)
        #expect(I.placement(isChromeVisible: false, isZoomed: true, isDownloading: false, isStalled: false) == .none)
        #expect(I.placement(isChromeVisible: true, isZoomed: false, isDownloading: true, isStalled: false) == .panel)
        // A video in fullscreen hides the chrome without a zoom: no ring.
        #expect(I.placement(isChromeVisible: false, isZoomed: false, isDownloading: true, isStalled: false) == .none)
        let viewer = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Features/Library/PhotoDetailScreen.swift")
            .joined(separator: "\n")
        #expect(viewer.contains(".overlay(alignment: .topTrailing) { zoomedDownloadCorner }"))
        let corner = try #require(viewer.range(of: "private var zoomedDownloadCorner: some View {"))
        let body = String(viewer[corner.lowerBound...].prefix(900))
        #expect(body.contains("ICloudDownloadRing(progress: downloadProgress)"))
        #expect(body.contains(".padding(.trailing, 20)"))
    }
}
