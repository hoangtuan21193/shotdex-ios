import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-18 AC-48 / FS-03.09b — Sync by ticked groups.
struct EditorSyncGroupsTests {

    /// Every slider of `PhotoAdjustments` set to its own value, found by
    /// reflection so a slider added later is in the fixture without asking.
    private func everySlider(offset: Double) throws -> PhotoAdjustments {
        var values: [String: Double] = [:]
        for (index, child) in Mirror(reflecting: PhotoAdjustments.zero).children.enumerated() {
            guard let label = child.label else { continue }
            values[label] = offset + Double(index) / 1000
        }
        let adjustments = try JSONDecoder().decode(PhotoAdjustments.self, from: JSONEncoder().encode(values))
        for child in Mirror(reflecting: adjustments).children {
            let zero = Mirror(reflecting: PhotoAdjustments.zero).children.first { $0.label == child.label }?.value
            #expect("\(child.value)" != "\(zero ?? "")", "\(child.label ?? "?") did not decode")
        }
        return adjustments
    }

    private func photoA() throws -> PhotoEditRecipe {
        var recipe = PhotoEditRecipe.identity
        recipe.adjustments = try everySlider(offset: 0.1)
        recipe.filterIntensity = 0.6
        recipe.lutID = "classic-chrome"
        recipe.crop.rect = NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        recipe.overlays = [PhotoOverlay.shape(.oval)]
        recipe.color.calibration.redHue = 0.3
        recipe.color.grayMixer.red = 0.2
        recipe.curve.region.shadows = 0.4
        recipe.upright.mode = .vertical
        recipe.lensBlur.amount = 0.7
        recipe.vignetteStyle = .colorPriority
        recipe.healing = [PhotoHealingSpot(mode: .heal, center: NormalizedPoint(x: 0.3, y: 0.3), source: NormalizedPoint(x: 0.6, y: 0.3))]
        recipe.redEyes = [PhotoRedEyeSpot(center: NormalizedPoint(x: 0.4, y: 0.4), radius: 0.02)]
        recipe.sourceFilename = "A.RAF"
        return recipe
    }

    private func photoB() throws -> PhotoEditRecipe {
        var recipe = PhotoEditRecipe.identity
        recipe.adjustments = try everySlider(offset: 0.5)
        recipe.crop.rect = NormalizedRect(x: 0, y: 0, width: 0.8, height: 0.8)
        recipe.sourceFilename = "B.RAF"
        return recipe
    }

    /// Every group ticked is Sync Everything, field for field — a slider no
    /// group names would show up here. Only which photo it is stays B's.
    @Test func everyGroupIsEverything() throws {
        let a = try photoA(), b = try photoB()
        let synced = EditorSyncGroups.everything.apply(a, onto: b)
        var expected = EditorSyncScope.everything.apply(a, onto: b)
        expected.source = b.source
        expected.sourceFilename = b.sourceFilename
        expected.sourceAssetIdentifier = b.sourceAssetIdentifier
        #expect(synced == expected)
    }

    /// The Look column is Sync Look plus Lens Blur, which the board puts
    /// under The Look; This Frame Only stays B's.
    @Test func lookColumnIsSyncLook() throws {
        let a = try photoA(), b = try photoB()
        var ticks = EditorSyncGroups.look
        ticks.groups.remove(.lensBlur)
        #expect(ticks.apply(a, onto: b) == EditorSyncScope.look.apply(a, onto: b))

        let synced = EditorSyncGroups.look.apply(a, onto: b)
        #expect(synced.lensBlur == a.lensBlur)
        #expect(synced.crop == b.crop)
        #expect(synced.overlays.isEmpty)
        #expect(synced.healing.isEmpty && synced.redEyes.isEmpty)
        #expect(synced.upright.mode == .vertical && synced.upright.guides.isEmpty)
    }

    /// AC-48: crop ticked on top of The Look carries the crop and nothing
    /// else of the frame; Light unticked keeps B's exposure.
    @Test func ticksAreIndependent() throws {
        let a = try photoA(), b = try photoB()
        var ticks = EditorSyncGroups.look
        ticks.groups.insert(.cropAndStraighten)
        ticks.groups.remove(.light)
        let synced = ticks.apply(a, onto: b)
        #expect(synced.crop == a.crop)
        #expect(synced.masks == b.masks && synced.overlays == b.overlays)
        #expect(synced.adjustments.exposure == b.adjustments.exposure)
        #expect(synced.adjustments.clarity == a.adjustments.clarity)
    }

    @Test func groupsAreInOneColumnEach() {
        #expect(EditorSyncGroup.lookColumn.count == 15)
        #expect(EditorSyncGroup.frameColumn.map(\.title)
                == ["Crop and Straighten", "Masks", "Heal and Clone Spots", "Red Eye", "Markup Layers", "Upright Guides"])
        #expect(EditorSyncGroups(.look) == .look && EditorSyncGroups(.everything) == .everything)
    }

    /// Remembered ticks decode lossily: a group this build no longer knows
    /// is dropped, the rest kept.
    @Test func ticksSurviveAnUnknownGroup() throws {
        let data = Data(#"{"groups":["light","masks","sparkle"]}"#.utf8)
        let ticks = try JSONDecoder().decode(EditorSyncGroups.self, from: data)
        #expect(ticks.groups == [.light, .masks])
        #expect(try JSONDecoder().decode(EditorSyncGroups.self, from: JSONEncoder().encode(ticks)) == ticks)
    }
}
