import Foundation
import Testing
@testable import ShotDex
import ShotDexKit

/// The Text tool's panel on the phone and the Duo (FS-12.04 §3, AC-5,
/// AC-16; FS-12.14 §3).
@MainActor
struct VideoTextPanelTests {
    /// FS-12.04 AC-16: Text opens the panel — nothing is added, no undo
    /// step, the Text cell lights.
    @Test func textOpensPanelAddsNothing() {
        let model = VideoStudioModelFixture.model()
        let overlays = model.recipe.overlays
        model.toggleToolPanel(.text)
        #expect(model.activeToolPanel == .text)
        #expect(model.presentsSheet)
        #expect(model.recipe.overlays == overlays)
        #expect(!model.canUndo)
        // ✕ only closes: the panel changed nothing.
        model.cancelSession()
        #expect(model.activeToolPanel == nil)
        #expect(model.recipe.overlays == overlays)
        #expect(!model.canUndo)
    }

    /// FS-12.04 AC-5: Text, Add Text, ✕ — the block came in at the
    /// playhead with Edit open, the panel went, and ✕ takes the block
    /// away leaving the undo stack as it was.
    @Test func addTextThenCancelLeavesNothing() {
        let model = VideoStudioModelFixture.model()
        model.seek(to: 4)
        model.toggleToolPanel(.text)
        let id = model.addTextFromPanel()
        #expect(model.activeToolPanel == nil)
        #expect(model.selectedOverlayID == id)
        #expect(model.inspectorTextTool == .edit)
        #expect(model.recipe.overlays.first { $0.id == id }?.start == 4)
        model.cancelSession()
        #expect(model.recipe.overlays.isEmpty)
        #expect(!model.canUndo)
    }

    /// A font row: the block wears that font, and the font is remembered.
    @Test func fontRowAddsInThatFont() {
        let model = VideoStudioModelFixture.model()
        let georgia = OverlayFontChoice(postScriptName: "Georgia", familyName: "Georgia", displayName: "Georgia")
        model.toggleToolPanel(.text)
        let id = model.addTextFromPanel(font: georgia)
        #expect(model.recipe.overlays.first { $0.id == id }?.overlay.fontPostScriptName == "Georgia")
        #expect(model.fontRecents.contains { $0.postScriptName == "Georgia" })
    }

    /// FS-12.14 AC-1 (entry): Auto Captions in the panel closes it and
    /// opens the caption lane's panel.
    @Test func autoCaptionsFromPanelOpensTheLane() async {
        let model = FakeCaptions.model { recipe in FakeCaptions.session(authorizer: CountingAuthorizer(), assetOf: FakeCaptions.assets(recipe)) }
        model.toggleToolPanel(.text)
        await model.startAutoCaptionsFromPanel()
        await FakeCaptions.settle(model)
        #expect(model.activeToolPanel == nil)
        #expect(model.inspectorTarget == .caption)
        #expect(model.recipe.captions != nil)
    }
}
