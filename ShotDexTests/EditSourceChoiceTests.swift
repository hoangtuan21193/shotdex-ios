import Foundation
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
}
