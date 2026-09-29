import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

struct EditClipboardSparseLookTests {
    /// FS-03.14 E6. An imported look naming Exposure and Red Hue changes
    /// exactly those; a look made in ShotDex (no names) still replaces the
    /// whole look cut.
    @Test func importedLookLeavesUnnamedSettingsAlone() {
        var source = PhotoEditRecipe.identity
        source.adjustments[.exposure] = 0.5
        source.color.mixer[.red].hue = -0.2
        source.adjustments[.contrast] = 0.9 // not named: must not travel
        var photo = PhotoEditRecipe.identity
        photo.adjustments[.contrast] = -0.3
        photo.adjustments[.vibrance] = 0.4
        let named: Set<LookSettingKey> = [.adjustment(.exposure), .mixer(.red, .hue)]
        let sparse = EditorSyncScope.applyLook(source, named: named, onto: photo)
        #expect(sparse.adjustments[.exposure] == 0.5)
        #expect(sparse.color.mixer[.red].hue == -0.2)
        #expect(sparse.adjustments[.contrast] == -0.3)
        #expect(sparse.adjustments[.vibrance] == 0.4)
        let whole = EditorSyncScope.applyLook(source, named: nil, onto: photo)
        #expect(whole.adjustments[.contrast] == 0.9)
        #expect(whole.adjustments[.vibrance] == 0)
    }
}
