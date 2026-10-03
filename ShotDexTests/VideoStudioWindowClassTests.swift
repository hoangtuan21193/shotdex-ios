import CoreGraphics
import Testing
@testable import ShotDex

/// The Video Studio's layout is chosen by the window — size and trailing
/// inset — not by the device (FS-12.03 §1, FS-12.07b §1). The table is the
/// one the wide-and-Duo plan specified for its task 4.
struct VideoStudioWindowClassTests {
    @Test(arguments: [
        (CGSize(width: 402, height: 874), CGFloat(0), VideoStudioWindowClass.phone),
        (CGSize(width: 466, height: 678), 84, .duoCover),
        (CGSize(width: 466, height: 678), 0, .phone),
        (CGSize(width: 951, height: 669), 0, .duoInner),
        (CGSize(width: 1376, height: 1032), 0, .iPadLandscape),
        (CGSize(width: 1032, height: 1376), 0, .iPadPortrait),
        (CGSize(width: 639, height: 1376), 0, .iPadPortrait),
        (CGSize(width: 507, height: 1032), 0, .phone),
        (CGSize(width: 1000, height: 800), 0, .iPadLandscape),
        (CGSize(width: 1000, height: 700), 0, .duoInner),
    ])
    func windowsResolveToTheirLayout(window: CGSize, trailingInset: CGFloat, expected: VideoStudioWindowClass) {
        #expect(VideoStudioWindowClass.resolve(window: window, trailingInset: trailingInset) == expected)
    }

    /// The Duo's cover reports its 84pt rail a beat after the first layout.
    /// Until it does, a compact window has no class — the screen draws
    /// nothing rather than a phone frame that then jumps to the rail. A
    /// wide window does not wait.
    @Test func aCompactWindowWaitsForItsTrailingInset() {
        let cover = CGSize(width: 466, height: 678)
        #expect(VideoStudioWindowClass.resolve(window: cover, knownTrailingInset: nil) == nil)
        #expect(VideoStudioWindowClass.resolve(window: cover, knownTrailingInset: 84) == .duoCover)
        #expect(VideoStudioWindowClass.resolve(window: cover, knownTrailingInset: 0) == .phone)
        let duoInner = CGSize(width: 951, height: 669)
        #expect(VideoStudioWindowClass.resolve(window: duoInner, knownTrailingInset: nil) == .duoInner)
    }

    /// The reader sits inside the safe area; the window is that plus the
    /// insets — the cover's 382pt of content is a 466pt window.
    @Test func theWindowIsTheContentPlusItsInsets() {
        let window = VideoStudioWindowClass.windowSize(
            content: CGSize(width: 382, height: 644), top: 0, bottom: 34, leading: 0, trailing: 84
        )
        #expect(window == CGSize(width: 466, height: 678))
        #expect(VideoStudioWindowClass.resolve(window: window, knownTrailingInset: 84) == .duoCover)
    }

    /// FS-12.03 AC-7 (class half): a Stage Manager window dragged from 800
    /// to 700 tall changes class — iPad landscape to the Duo inner layout —
    /// and nothing else about the window does.
    @Test func shrinkingAStageManagerWindowChangesClassOnly() {
        #expect(VideoStudioWindowClass.resolve(window: CGSize(width: 1000, height: 800), trailingInset: 0) == .iPadLandscape)
        #expect(VideoStudioWindowClass.resolve(window: CGSize(width: 1000, height: 720), trailingInset: 0) == .iPadLandscape)
        #expect(VideoStudioWindowClass.resolve(window: CGSize(width: 1000, height: 719), trailingInset: 0) == .duoInner)
        #expect(VideoStudioWindowClass.resolve(window: CGSize(width: 1000, height: 700), trailingInset: 0) == .duoInner)
    }

    /// FS-12.03 AC-7, FS-12.07b AC-8: the selection and its ✕ snapshot
    /// live in the model, not in a layout. Clip 2 selected, Speed 2×, the
    /// window changes class (what the screen does then is write the draft);
    /// clip 2 is still selected with its session, and ✕ takes Speed back
    /// to 1×.
    @MainActor
    @Test func aClassChangeKeepsTheSelectionAndItsCancel() {
        let model = VideoStudioModelFixture.model()
        let clip2 = model.recipe.clips[1].id
        model.selectClip(clip2)
        model.pushUndo()
        model.setSpeed(2, for: clip2)
        let session = model.session
        var columns = VideoDeskColumns(isPoolOpen: true, isInspectorOpen: true)
        _ = VideoStudioDeskGeometry.iPadLandscape(.init(
            window: CGSize(width: 1000, height: 800), canvas: CGSize(width: 16, height: 9),
            isPoolOpen: columns.isPoolOpen ?? false, isInspectorOpen: columns.isInspectorOpen
        ))
        model.sceneDidChange()
        _ = VideoStudioDeskGeometry.duoInner(.init(
            window: CGSize(width: 1000, height: 700), canvas: CGSize(width: 16, height: 9),
            isPoolOpen: false, isInspectorOpen: true
        ))
        columns.presentsSheetChanged(from: true, to: true)
        #expect(model.selectedClipID == clip2)
        #expect(model.session == session)
        #expect(columns == VideoDeskColumns(isPoolOpen: true, isInspectorOpen: true))
        model.cancelSession()
        #expect(model.recipe.clips[1].speed == 1)
        #expect(model.selectedClipID == nil)
    }

    @Test func shortWindowsAreUnder720() {
        for height in [CGFloat(669), 678, 719.5] {
            #expect(VideoStudioWindowClass.isShortWindow(height: height))
        }
        for height in [CGFloat(720), 812, 874, 1032] {
            #expect(!VideoStudioWindowClass.isShortWindow(height: height))
        }
    }

    /// FS-12.04 AC-2: every layout offers all five tools — iterated over the
    /// layouts and over the tools, compared element by element, not counted.
    @Test func everyLayoutOffersTheFiveAddTools() {
        for windowClass in VideoStudioWindowClass.allCases {
            let offered = VideoAddTool.addTools(for: windowClass)
            for tool in VideoAddTool.allCases {
                #expect(offered.contains(tool), "\(windowClass) is missing \(tool)")
            }
        }
        // iPad: four inserts in the pool or the dock, Look as the default panel.
        for windowClass in [VideoStudioWindowClass.iPadLandscape, .iPadPortrait] {
            #expect(VideoAddTool.placement(of: .look, in: windowClass) == .defaultPanel)
            for tool in [VideoAddTool.media, .text, .sticker, .music] {
                #expect(VideoAddTool.placement(of: tool, in: windowClass) != .defaultPanel)
            }
        }
    }
}

/// The five tools while an item is selected (FS-12.04 §5).
@MainActor
struct VideoToolsWhileSelectingTests {
    /// FS-12.04 AC-8 (rule half): on the Duo, inner and cover, the tools go
    /// inert while an item is selected; on the phone the row is replaced; on
    /// an iPad they stay or make way. Iterated over every window class.
    @Test func toolsAreInertWhileSelectingOnTheDuo() {
        for windowClass in VideoStudioWindowClass.allCases {
            let inert = VideoAddTool.toolsAreInert(in: windowClass, isSelecting: true)
            #expect(inert == (windowClass == .duoInner || windowClass == .duoCover), "\(windowClass)")
            #expect(!VideoAddTool.toolsAreInert(in: windowClass, isSelecting: false))
        }
        #expect(VideoAddTool.selectionBehaviour(in: .phone) == .replacedBySessionFooter)
        #expect(VideoAddTool.selectionBehaviour(in: .iPadLandscape) == .usableCommittingFirst)
        #expect(VideoAddTool.selectionBehaviour(in: .iPadPortrait) == .yieldsToCommands)
    }

    /// iPad landscape: inserting from the pool while clip 2 is selected is
    /// ✓ for clip 2 first — its change stays, its session is over.
    @Test func insertingFromThePoolCommitsTheSelection() {
        let model = VideoStudioModelFixture.model()
        let clip2 = model.recipe.clips[1].id
        model.selectClip(clip2)
        model.setSpeed(2, for: clip2)
        model.appendMedia([VideoMediaPick(assetID: "pool-pick", kind: .photo)])
        #expect(model.session == nil)
        #expect(model.selectedClipID == nil)
        #expect(model.recipe.clips[1].speed == 2)
        #expect(model.recipe.clips.last?.assetID == "pool-pick")
    }
}
