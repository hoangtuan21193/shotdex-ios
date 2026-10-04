import Foundation
import Testing
@testable import ShotDex

/// FS-12.09 §5: the Media panel is a session — ✕ puts the project back as
/// it was when Media opened and leaves no undo step; ✓ keeps each step.
@MainActor
struct VideoStudioMediaSessionTests {
    private func sample() -> VideoStudioModel {
        let recipe = VideoStudioModelFixture.mediaSampleRecipe()
        return VideoStudioModelFixture.model(clips: recipe.clips) { $0 = recipe }
    }

    /// AC-8: Media open, two taps → ✕ → the five clips of 24.0 s, the undo
    /// history exactly as deep as when Media opened, and nothing to redo.
    @Test func cancelRestoresAndLeavesUndoDepth() {
        let model = sample()
        defer { model.close() }
        // One earlier edit, so "as deep as at open" is not just "empty".
        model.pushUndo()
        model.setPhotoDuration(4, for: model.recipe.clips[0].id)
        let before = model.recipe
        let depth = model.history.undoEntries.count
        let couldUndo = model.canUndo

        model.showToolPanel(.media)
        model.seek(to: 8.4)
        model.insertMedia([VideoMediaPick(assetID: "One", kind: .photo)])
        model.insertMedia([VideoMediaPick(assetID: "Two", kind: .photo)])
        #expect(model.recipe.clips.count == 8)
        #expect(model.sessionFooterTitle?.name == VideoStudioCopy.media)

        model.cancelSession()
        #expect(model.recipe == before)
        #expect(model.recipe.clips.count == 5)
        #expect(model.history.undoEntries.count == depth)
        #expect(model.canUndo == couldUndo)
        #expect(!model.canRedo)
        #expect(model.activeToolPanel == nil)
    }

    /// ✓ keeps each insert as its own undo step.
    @Test func commitKeepsEachStep() {
        let model = sample()
        defer { model.close() }
        model.showToolPanel(.media)
        model.insertMedia([VideoMediaPick(assetID: "One", kind: .photo)])
        model.insertMedia([VideoMediaPick(assetID: "Two", kind: .photo)])
        model.commitSession()
        #expect(model.activeToolPanel == nil)
        #expect(model.recipe.clips.count == 7)
        model.undo()
        #expect(model.recipe.clips.count == 6)
    }
}

extension VideoStudioMediaSessionTests {
    /// AC-2: Select, pick three, Add (3) → three clips after the cut at
    /// 8.4 in the order picked (1-2-3), one undo back to the five clips.
    /// Unpicking renumbers; Select again drops every pick.
    @Test func addThreeInSelectionOrderOneUndo() {
        let model = sample()
        defer { model.close() }
        model.showToolPanel(.media)
        model.seek(to: 8.4)
        model.toggleMediaSelecting()
        for id in ["C", "X", "A", "B"] { model.toggleMediaPick(VideoMediaPick(assetID: id, kind: .photo)) }
        model.toggleMediaPick(VideoMediaPick(assetID: "X", kind: .photo))
        #expect(model.mediaPickNumber("C") == 1)
        #expect(model.mediaPickNumber("A") == 2)
        #expect(model.mediaPickNumber("B") == 3)
        #expect(model.mediaPickNumber("X") == nil)
        #expect(model.sessionFooterTitle?.detail.hasPrefix("3 selected") == true)

        model.addSelectedMedia()
        #expect(model.recipe.clips.map(\.assetID) == ["Falls", "Coast", "C", "A", "B", "Coast", "Lake", "Night", "Forest"])
        #expect(!model.isSelectingMedia)
        model.undo()
        #expect(model.recipe.clips.map(\.assetID) == ["Falls", "Coast", "Lake", "Night", "Forest"])

        model.toggleMediaSelecting()
        model.toggleMediaPick(VideoMediaPick(assetID: "A", kind: .photo))
        model.toggleMediaSelecting()
        #expect(model.mediaSelection == nil)
    }

    /// ✓ with picks not yet added adds them first, then closes Media.
    @Test func confirmAddsPendingSelection() {
        let model = sample()
        defer { model.close() }
        model.showToolPanel(.media)
        model.toggleMediaSelecting()
        model.toggleMediaPick(VideoMediaPick(assetID: "A", kind: .photo))
        model.toggleMediaPick(VideoMediaPick(assetID: "B", kind: .photo))
        model.commitSession()
        #expect(model.recipe.clips.count == 7)
        #expect(model.activeToolPanel == nil)
        #expect(model.mediaSelection == nil)
        // ✕ with picks adds nothing.
        model.showToolPanel(.media)
        model.toggleMediaSelecting()
        model.toggleMediaPick(VideoMediaPick(assetID: "C", kind: .photo))
        model.cancelSession()
        #expect(model.recipe.clips.count == 7)
    }
}

extension VideoStudioMediaSessionTests {
    /// AC-7 (model): tapping Coast in In Video puts the playhead at 3.0 and
    /// selects clip 2; Media closes as ✓.
    @Test func inVideoTapJumpsAndSelects() throws {
        let model = sample()
        defer { model.close() }
        model.showToolPanel(.media)
        let coast = try #require(model.inVideoRows.first { $0.assetID == "Coast" })
        model.goToInVideoRow(coast)
        #expect(model.currentTime == 3.0)
        #expect(model.selectedClipID == model.recipe.clips[1].id)
        #expect(model.activeToolPanel == nil)
        let road = try #require(model.inVideoRows.first { $0.assetID == "Road" })
        model.goToInVideoRow(road)
        #expect(model.currentTime == 6.0)
        #expect(model.selectedOverlayID == model.recipe.overlays[0].id)
    }
}

extension VideoStudioMediaSessionTests {
    /// The lanes as the timeline would publish them: 402pt wide, the
    /// playhead at x 201, 50pt a second, lanes from y 300 to 500.
    private func lanes() -> VideoDropGeometry {
        VideoDropGeometry(
            frame: CGRect(x: 0, y: 300, width: 402, height: 200),
            lineBand: CGRect(x: 0, y: 380, width: 402, height: 56),
            mapping: .timeline(playheadX: 201, pointsPerSecond: 50)
        )
    }

    /// AC-3 (model): held at 14.5 s over the lanes, the seam is 14.2; let
    /// go, the video is clip 4 and one Undo takes it back.
    @Test func dropLandsOnTheNearestSeam() {
        let model = sample()
        defer { model.close() }
        for clip in model.recipe.clips { model.sources[clip.id] = .unavailable(assetID: clip.assetID) }
        model.timelineDropGeometry = lanes()
        model.seek(to: 12)
        let before = model.recipe
        model.beginMediaDrag(VideoMediaPick(assetID: "Fourteen", kind: .video, duration: 14),
                             at: CGPoint(x: 200, y: 700), from: CGRect(x: 0, y: 650, width: 99, height: 99), image: nil)
        #expect(model.mediaDrag?.target == nil)
        // 14.5 s is 2.5 s right of the playhead at 12: x 201 + 125.
        #expect(model.moveMediaDrag(to: CGPoint(x: 326, y: 400)))
        #expect(model.mediaDrag?.target?.boundary.index == 3)
        #expect(abs((model.mediaDrag?.target?.line.midX ?? 0) - 311) < 0.5)
        #expect(model.endMediaDrag())
        #expect(model.mediaDrag == nil)
        #expect(model.recipe.clips.map(\.assetID) == ["Falls", "Coast", "Lake", "Fourteen", "Night", "Forest"])
        #expect(model.currentTime == 12)
        model.undo()
        #expect(model.recipe == before)
    }

    /// AC-4: let go anywhere but a drop target — the grid, the frame, off
    /// the screen — and nothing changes, not even the undo state.
    @Test func cancelledDropChangesNothing() {
        let model = sample()
        defer { model.close() }
        model.timelineDropGeometry = lanes()
        let before = model.recipe
        let couldUndo = model.canUndo
        model.beginMediaDrag(VideoMediaPick(assetID: "X", kind: .photo),
                             at: CGPoint(x: 50, y: 700), from: CGRect(x: 0, y: 650, width: 99, height: 99), image: nil)
        model.moveMediaDrag(to: CGPoint(x: 300, y: 400))
        #expect(model.mediaDrag?.target != nil)
        model.moveMediaDrag(to: CGPoint(x: 120, y: 720))
        #expect(model.mediaDrag?.target == nil)
        #expect(!model.endMediaDrag())
        #expect(model.mediaDrag?.isReturning == true)
        #expect(model.recipe == before)
        #expect(model.canUndo == couldUndo)
    }

    /// Dragging a picked cell while selecting carries every pick, in order.
    @Test func draggingAPickCarriesTheGroup() {
        let model = sample()
        defer { model.close() }
        model.showToolPanel(.media)
        model.toggleMediaSelecting()
        for id in ["B", "A"] { model.toggleMediaPick(VideoMediaPick(assetID: id, kind: .photo)) }
        model.beginMediaDrag(VideoMediaPick(assetID: "A", kind: .photo), at: .zero, from: .zero, image: nil)
        #expect(model.mediaDrag?.picks.map(\.assetID) == ["B", "A"])
        model.cancelMediaDrag()
    }
}
