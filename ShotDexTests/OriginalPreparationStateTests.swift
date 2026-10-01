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
}
