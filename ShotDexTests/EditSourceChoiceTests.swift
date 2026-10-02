import Foundation
import ShotDexKit
import Testing
@testable import ShotDex

/// FS-03.04b AC-5: every RAW + JPEG pair asks *Edit which version?*; a RAW
/// iOS can't read is offered dimmed with the reason.
@MainActor
struct EditSourceChoiceTests {
    typealias F = RAWVerdictFixtures

    @Test func pairAsksInEitherOrder() {
        for resources: [EditSourceChoice.Resource] in [[.rendered, .raw], [.raw, .rendered]] {
            let choice = EditSourceChoice(resources: resources, rawIsReadable: true)
            #expect(choice.isPair)
            #expect(choice.offersRAW)
            #expect(choice.rawReason == nil)
            #expect(choice.title == "Edit which version?")
        }
        #expect(!EditSourceChoice(resources: [.raw], rawIsReadable: true).isPair)
        #expect(!EditSourceChoice(resources: [.rendered], rawIsReadable: true).isPair)
    }

    @Test func unreadableRAWIsDimmedWithTheReason() {
        let choice = EditSourceChoice(resources: [.rendered, .raw], rawIsReadable: false)
        #expect(choice.isPair)
        #expect(!choice.offersRAW)
        #expect(choice.rawReason == "iOS can't read this RAW yet")
    }

    /// A pair is never in the marked set, but its camera's verdict still
    /// dims its RAW: the index row names the JPEG and the camera.
    @Test func pairOfAnUnreadableCamera() async throws {
        let rows = [F.row("pair", file: "DSCF0001.JPG", make: "FUJIFILM", model: "X-Q9")]
            + F.rows("raf", 2, ext: "RAF", make: "FUJIFILM", model: "X-Q9")
        let index = UnsupportedRAWIndex(
            store: RAWVerdictStore(database: try F.database(rows)), probe: FakeRAWProbe(local: ["raf1", "raf2"]), release: F.release
        )
        index.runPass()
        await index.waitForPass()
        #expect(!index.assetIds.contains("pair"))
        #expect(index.isCameraUnreadable(assetId: "pair"))
        #expect(index.message(for: "pair") == nil)
        #expect(!index.isCameraUnreadable(assetId: "unknown-photo"))
    }

    /// The editor opens the file chosen, and the Source menu dims an
    /// unreadable RAW and reports a failed switch instead of swallowing it.
    @Test func editorHonoursTheChoice() throws {
        let controller = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Features/Editing/PhotoEditorController.swift").joined(separator: "\n")
        #expect(controller.contains("let chosen = requestedSource.flatMap { source in"))
        let screen = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Features/Editing/PhotoEditorScreen.swift").joined(separator: "\n")
        #expect(!screen.contains("try? await controller.selectSource(option)"))
        #expect(screen.contains("let isDimmed = option.isRAW && controller.isRAWSourceUnreadable"))
        let viewer = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Features/Library/PhotoDetailScreen.swift").joined(separator: "\n")
        #expect(viewer.contains("guard let source = await EditSourcePrompt.ask(choice) else { return }"))
    }

    // MARK: AC-16 — moving a saved edit between the pair's files

    static func savedOnRAW() -> PhotoEditRecipe {
        var recipe = PhotoEditRecipe.identity
        recipe.source = .raw
        recipe.sourceFilename = "DSC_0001.ARW"
        recipe.adjustments.exposure = 1
        recipe.adjustments.rawTemperature = 0.4
        recipe.adjustments.rawTint = -0.2
        recipe.adjustments.rawSharpness = 0.3
        recipe.adjustments.rawLuminanceNoise = 0.5
        recipe.adjustments.rawColorNoise = 0.6
        recipe.adjustments.rawWhiteBalanceKelvin = 5200
        recipe.adjustments.rawWhiteBalanceTint = 4
        return recipe
    }

    /// Q1: Edit JPEG on a pair edited on its RAW keeps Exposure +1 and drops
    /// the RAW group (Temperature among it).
    @Test func switchingToJPEGDropsRAWOnlyKinds() throws {
        let carried = try #require(EditSourceChoice.startingRecipe(saved: Self.savedOnRAW(), opening: .rendered))
        #expect(carried.adjustments.exposure == 1)
        for kind in PhotoAdjustmentKind.allCases where kind.isRAWOnly {
            #expect(carried.adjustments[kind] == 0, "\(kind) came along")
        }
        #expect(PhotoAdjustmentKind.allCases.filter(\.isRAWOnly).count == 5)
        #expect(carried.adjustments.rawWhiteBalanceKelvin == nil)
        #expect(carried.adjustments.rawWhiteBalanceTint == nil)
    }

    /// Q9: Edit RAW on a pair edited on its JPEG starts from the RAW as shot.
    @Test func switchingToRAWStartsFresh() {
        var onJPEG = PhotoEditRecipe.identity
        onJPEG.source = .rendered
        onJPEG.sourceFilename = "DSC_0001.JPG"
        onJPEG.adjustments.exposure = 1
        onJPEG.adjustments.contrast = 0.2
        #expect(EditSourceChoice.startingRecipe(saved: onJPEG, opening: .raw) == nil)
        // A recipe that only names its file decides by the file.
        var automatic = onJPEG
        automatic.source = .automatic
        #expect(EditSourceChoice.startingRecipe(saved: automatic, opening: .raw) == nil)
    }

    @Test func sameFileKeepsTheEdit() {
        let raw = Self.savedOnRAW()
        #expect(EditSourceChoice.startingRecipe(saved: raw, opening: .raw) == raw)
        #expect(EditSourceChoice.startingRecipe(saved: nil, opening: .rendered) == nil)
    }

    /// Lần nào cũng hỏi: the viewer keeps no "last choice", and the editor
    /// starts every load from the rule above.
    @Test func everyEditAsksAgain() throws {
        let viewer = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Features/Library/PhotoDetailScreen.swift").joined(separator: "\n")
        #expect(viewer.contains("guard choice.isPair else {"))
        #expect(!viewer.contains("lastEditSource"))
        let controller = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Features/Editing/PhotoEditorController.swift").joined(separator: "\n")
        #expect(controller.contains("var initialRecipe = EditSourceChoice.startingRecipe("))
    }
}
