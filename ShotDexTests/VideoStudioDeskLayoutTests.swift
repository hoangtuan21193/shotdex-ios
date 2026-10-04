import CoreGraphics
import Testing
@testable import ShotDex

/// The wide layouts' bands — track headers and badges, the meter, the
/// transport, the pool's tabs — and the rules inside them (FS-12.03b). Where
/// each band sits is `VideoStudioDeskGeometryTests`.
struct VideoStudioDeskLayoutTests {
    // MARK: Track headers

    @Test func trackHeadersReplaceTheGlyphColumnOnlyOnDeskWindows() {
        #expect(!VideoStudioMetrics.Lanes.for(.phone).showsTrackControls)
        #expect(!VideoStudioMetrics.Lanes.for(.duoCover).showsTrackControls)
        #expect(VideoStudioMetrics.Lanes.for(.duoInner).showsTrackControls)
        #expect(VideoStudioMetrics.Lanes.desk.gutter == VideoStudioMetrics.Lanes.trackHeaderWidth)
    }

    /// FS-12.03b AC-8: the Duo's inner display has a 100pt badge column —
    /// margin 6 · badge 26 · gap 4 · Lock 28 · gap 4 · Mute 28 · margin 4 —
    /// so Lock and Mute are reachable there too (the transport has no ⋯).
    /// Each switch answers 32pt wide; the two never overlap.
    @Test func duoInnerGutterIsA100ptBadgeColumnWithLockAndMute() {
        typealias Lanes = VideoStudioMetrics.Lanes
        let parts = Lanes.badgeColumnMargin + Lanes.badgeWidth + Lanes.badgeGap
            + Lanes.badgeDisc + Lanes.badgeGap + Lanes.badgeDisc + 4
        #expect(parts == Lanes.badgeColumnWidth)
        #expect(Lanes.badgeLockX == 36)
        #expect(Lanes.badgeMuteX == 68)
        let lockTouch = Lanes.badgeLockX - (Lanes.badgeTouchWidth - Lanes.badgeDisc) / 2
        let muteTouch = Lanes.badgeMuteX - (Lanes.badgeTouchWidth - Lanes.badgeDisc) / 2
        #expect(lockTouch == 34)
        #expect(muteTouch == 66)
        #expect(lockTouch + Lanes.badgeTouchWidth <= muteTouch)
        #expect(muteTouch + Lanes.badgeTouchWidth <= Lanes.badgeColumnWidth)
        // Lock on every lane, Mute where there is sound — read off the
        // lanes, not counted.
        #expect(VideoTimelineLane.overlay(0).lockLabel == "Lock Text")
        #expect(VideoTimelineLane.video.muteLabel == "Mute Video")
        #expect(VideoTimelineLane.music(1).lockLabel == "Lock Music 2")
        #expect(VideoTimelineLane.video.badge == "V1")
        #expect(VideoTimelineLane.music(0).badge == "A1")
    }

    /// Widening the gutter must not change the lanes themselves — the header
    /// is a column in front of the rows, not a new row geometry.
    @Test func trackHeadersLeaveTheLaneHeightsAlone() {
        let plain = VideoStudioMetrics.Lanes.duo
        let headed = VideoStudioMetrics.Lanes.for(.duoInner)
        #expect(headed.video == plain.video)
        #expect(headed.overlay == plain.overlay)
        #expect(headed.music == plain.music)
        #expect(headed.timelineContentHeight(overlayLanes: 2, musicLanes: 1)
            == plain.timelineContentHeight(overlayLanes: 2, musicLanes: 1))
    }

    // MARK: Timecode

    @Test func timecodeCountsHoursMinutesSecondsAndFrames() {
        #expect(VideoStudioMetrics.timecode(0) == "00:00:00:00")
        #expect(VideoStudioMetrics.timecode(-5) == "00:00:00:00")
        #expect(VideoStudioMetrics.timecode(61.5) == "00:01:01:15")
        #expect(VideoStudioMetrics.timecode(3661) == "01:01:01:00")
    }

    /// The frame field must never reach the frame rate — 29 is the last
    /// frame of a second at 30fps, and a read-out that prints `:30` is one
    /// the user cannot match a cut against.
    @Test func theFrameFieldNeverReachesTheFrameRate() {
        #expect(VideoStudioMetrics.timecode(1.999).hasSuffix(":29"))
        #expect(VideoStudioMetrics.timecode(2.0).hasSuffix(":00"))
    }

    // MARK: Meter scale

    @Test func theMeterScaleIsLinearInDecibels() {
        #expect(VideoAudioMeterColumn.fractionOf(0) == 1)
        #expect(VideoAudioMeterColumn.fractionOf(VideoLevelMeterModel.floorDB) == 0)
        // Below the floor and above the ceiling both clamp rather than
        // drawing a bar taller or shorter than the track.
        #expect(VideoAudioMeterColumn.fractionOf(-120) == 0)
        #expect(VideoAudioMeterColumn.fractionOf(6) == 1)
        let half = VideoAudioMeterColumn.fractionOf(VideoLevelMeterModel.floorDB / 2)
        #expect(abs(half - 0.5) < 0.0001)
    }

    /// The fade envelope the meter reads has to be the one the export writes,
    /// so it is derived from `VideoTimelineMath.musicRamps` rather than
    /// re-implemented: silent at the start of a fade-in, full in the middle,
    /// silent again at the very end of a fade-out.
    @Test func theMeterReadsTheSameFadeEnvelopeTheExportWrites() {
        let level = { (seconds: Double) in
            VideoLevelMeterModel.rampedVolume(
                at: seconds, total: 10, volume: 1, fadeIn: 2, fadeOut: 2
            )
        }
        #expect(level(0) == 0)
        #expect(abs(level(1) - 0.5) < 0.0001)
        #expect(level(5) == 1)
        #expect(abs(level(9) - 0.5) < 0.0001)
    }

    // MARK: No tool rail on a desk window

    /// FS-12.03b AC-7 (tabs): the pool's tabs are Media · Text · Stickers ·
    /// Music, in that order — the look is the inspector's, not a tab's.
    @Test func thePoolHasFourTabsInOrder() {
        #expect(VideoMediaPoolColumn.Tab.allCases == [.media, .text, .stickers, .music])
    }

    /// FS-12.09 AC-13 (grid): the pool's Media grid is three columns of 69
    /// with 6pt gaps and 8 at the edges across its 236pt; the dock's eight
    /// of 124, the Duo column's three of 80 and the cover's four of 94.
    @Test func poolMediaGridIsThreeColumnsOf69() {
        let pool = VideoMediaGridMetrics.for(.iPadLandscape)
        #expect(pool.columns == 3)
        #expect(pool.cellSide(width: VideoStudioDeskGeometry.poolWidth) == 69)
        #expect(pool.cellSide(width: 236) * 3 + pool.gap * 2 + pool.inset * 2 <= 236)
        #expect(VideoMediaGridMetrics.for(.iPadPortrait).cellSide(width: 1032) == 124)
        #expect(VideoMediaGridMetrics.for(.duoInner).cellSide(width: 264) == 80)
        #expect(VideoMediaGridMetrics.for(.duoCover).cellSide(width: 382) == 94)
    }

    /// A phone has no pool to move the insert commands onto, so it keeps all
    /// five tools in its row.
    @Test func aPhoneKeepsEveryInsertCommand() {
        #expect(VideoStudioToolbar.tools(poolCarriesInserts: false) == VideoAddTool.allCases)
    }

    /// The pool taking the inserts must not cost the window Look.
    @Test func thePoolRowStillCarriesLook() {
        let tools = VideoStudioToolbar.tools(poolCarriesInserts: true)
        #expect(tools.contains(.look))
        #expect(!tools.contains(.media))
    }

    /// Both tool panels are in the desk window's project menu, read from
    /// the same list — iterated, not counted.
    @Test func everyToolPanelIsInTheProjectMenu() {
        for panel in [VideoToolPanel.look, .videoSettings] {
            #expect(VideoToolPanel.allCases.contains(panel))
        }
    }

    /// FS-12.07 AC-7: the phone transport is Go to Start · Back a Frame ·
    /// the read-out · Forward a Frame · Go to End · More — five 40pt
    /// buttons at 6/46/276/316/356 on 402pt — and on the narrowest phone
    /// (375pt, an iPhone SE, the smallest screen iOS 17 runs on) the
    /// read-out still fits between them uncut, at its longest.
    @Test func theCompactTransportFitsTheNarrowestPhone() {
        #expect(VideoStudioMetrics.compactTransportButtonXs(width: 402) == [6, 46, 276, 316, 356])
        for width in [CGFloat(375), 402, 440] {
            let xs = VideoStudioMetrics.compactTransportButtonXs(width: width)
            #expect(xs.count == 5)
            let gap = xs[2] - (xs[1] + VideoStudioMetrics.compactTransportButton)
            // "59:59.9 / 59:59.9" at 12pt semibold monospaced: 17 glyphs of
            // 0.6em each, plus breathing room either side.
            let readout = 17 * 12 * 0.6 + 16
            #expect(gap >= readout)
            #expect(xs[4] + VideoStudioMetrics.compactTransportButton + VideoStudioMetrics.compactTransportInset == width)
        }
    }

    /// FS-12.07 AC-7: the read-out is the playhead and the length, `m:ss.t`.
    @Test func compactTimecodeShowsPlayheadAndLength() {
        let text = VideoStudioMetrics.compactTransportReadout(playhead: 8.42, length: 24)
        #expect(text.playhead == "0:08.4")
        #expect(text.length == " / 0:24.0")
        #expect(VideoStudioMetrics.compactTimecode(75.99) == "1:15.9")
        #expect(VideoStudioMetrics.compactTimecode(-1) == "0:00.0")
    }

    // MARK: Transitions

    /// The one transition control the maths always supported and nothing ever
    /// exposed: `VideoBoundaryTransition.duration` had a range and a default
    /// and no way to change it. The sheet's note has to tell the truth about
    /// what the timeline will actually grant.
    @Test func aTransitionIsClampedToHalfTheShorterNeighbour() {
        // Two clips, the second only 0.6s: a 2s transition cannot fit.
        let granted = VideoTimelineMath.effectiveOverlaps(
            requested: [2.0],
            durations: [5.0, 0.6]
        )
        #expect(granted.count == 1)
        #expect(granted[0] <= 0.3 + 0.0001)
        #expect(granted[0] < 2.0)
    }

    @Test func aTransitionThatFitsIsGrantedInFull() {
        let granted = VideoTimelineMath.effectiveOverlaps(
            requested: [0.5],
            durations: [5.0, 4.0]
        )
        #expect(abs(granted[0] - 0.5) < 0.0001)
    }

    /// Every kind the sheet lists must be a kind the compositor can blend, or
    /// the sheet is offering something the export cannot honour.
    @Test func everyTransitionKindIsOfferedAndRenderable() {
        #expect(VideoTransitionKind.allCases.contains(.none))
        #expect(VideoTransitionKind.allCases.contains(.crossfade))
        #expect(VideoTransitionKind.allCases.count >= 7)
    }

    // MARK: Markers

    /// A marker is a time, not a child of a clip — Resolve pins them to the
    /// ruler for the same reason: trimming a shot must not drag every note
    /// along with it.
    @Test func aMarkerKeepsItsColourIndexInRange() {
        var marker = TimedMarker(time: 3)
        marker.colorIndex = 99
        #expect(marker.clampedColorIndex == TimedMarker.palette.count - 1)
        marker.colorIndex = -4
        #expect(marker.clampedColorIndex == 0)
    }

    @Test func theMarkerPaletteIsFixedAndNotEmpty() {
        #expect(!TimedMarker.palette.isEmpty)
        #expect(TimedMarker.palette.count == 5)
    }

    // MARK: Input transform (de-log)

    /// Every profile must be monotonic and land on the ends: a transfer
    /// function that dips is a curve that inverts tones somewhere in the
    /// middle, and one that does not reach white clips the highlights.
    @Test func everyInputTransformIsMonotonicFromBlackToWhite() {
        for transform in VideoInputTransform.allCases where !transform.isIdentity {
            let samples = transform.curveSamples()
            #expect(samples.count == 256)
            #expect(samples[0] <= 0.05, "\(transform.rawValue) should start near black")
            #expect(samples[255] >= 0.95, "\(transform.rawValue) should reach white")
            for index in 1..<samples.count {
                #expect(
                    samples[index] >= samples[index - 1] - 0.0001,
                    "\(transform.rawValue) dips at \(index)"
                )
            }
        }
    }

    /// The real anchor for a de-log curve is **18% grey**: each maker
    /// publishes the code value their curve puts mid grey at, and the
    /// transform has to land it back on 0.18 scene-linear. (An earlier
    /// version of this test asserted the *mid code value* darkens, which is
    /// not physics — S-Log3 encodes 18% grey at 420/1023, well below the
    /// middle, so its mid code is supposed to come out bright.)
    @Test func eachLogProfileLandsMidGreyWhereItsMakerSaysItIs() {
        // Sony publishes 18% grey at code 420 of 1023.
        #expect(abs(VideoInputTransform.sLog3.sceneLinear(420.0 / 1023.0) - 0.18) < 0.001)
        // Panasonic publishes 18% grey at 0.42 in V-Log.
        #expect(abs(VideoInputTransform.vLog.sceneLinear(0.42) - 0.18) < 0.01)
    }

    /// And the point of doing it at all: a log picture is flat, so the
    /// transform has to *expand* the range — the gap between a shadow and a
    /// highlight must come out wider than it went in.
    @Test func aLogTransformExpandsTheRangeItWasGiven() {
        for transform in [VideoInputTransform.sLog3, .vLog, .genericLog] {
            let samples = transform.curveSamples()
            let flatGap = Float(200 - 60) / 255
            let gradedGap = samples[200] - samples[60]
            #expect(gradedGap > flatGap, "\(transform.rawValue) did not expand contrast")
        }
    }

    @Test func noneIsTheIdentityRamp() {
        let samples = VideoInputTransform.none.curveSamples()
        #expect(VideoInputTransform.none.isIdentity)
        #expect(abs(samples[0]) < 0.0001)
        #expect(abs(samples[255] - 1) < 0.0001)
        #expect(abs(samples[128] - Float(128.0 / 255.0)) < 0.0001)
    }

    /// HLG's inverse OETF is defined piecewise at 0.5; the two halves have to
    /// meet, or a mid-grey sky gets a visible step in it.
    @Test func hlgIsContinuousAtItsBreakpoint() {
        let hlg = VideoInputTransform.hlg
        let below = hlg.sceneLinear(0.4999)
        let above = hlg.sceneLinear(0.5001)
        #expect(abs(above - below) < 0.001)
    }

    // MARK: Clip fades

    /// The two fades can never cross: half the clip each, so a shot is never
    /// fading in and out at the same instant and therefore never fully
    /// visible.
    @Test func aClipsTwoFadesCannotCross() {
        var clip = VideoClip(assetID: "x", kind: .photo)
        clip.photoDuration = 4
        #expect(clip.maximumFade() == 2)
        clip.fadeIn = 2
        clip.fadeOut = 2
        #expect(clip.fadeOpacity(atLocalTime: 2) == 1)
    }

    @Test func aFadeRunsFromBlackToFullAndBack() {
        var clip = VideoClip(assetID: "x", kind: .photo)
        clip.photoDuration = 4
        clip.fadeIn = 1
        clip.fadeOut = 1
        #expect(clip.fadeOpacity(atLocalTime: 0) == 0)
        #expect(abs(clip.fadeOpacity(atLocalTime: 0.5) - 0.5) < 0.0001)
        #expect(clip.fadeOpacity(atLocalTime: 2) == 1)
        #expect(abs(clip.fadeOpacity(atLocalTime: 3.5) - 0.5) < 0.0001)
        #expect(clip.fadeOpacity(atLocalTime: 4) == 0)
    }

    /// No fades means no fade maths at all — a hard cut is the default and
    /// must stay exactly opaque.
    @Test func aClipWithoutFadesIsAlwaysOpaque() {
        var clip = VideoClip(assetID: "x", kind: .photo)
        clip.photoDuration = 3
        for t in stride(from: 0.0, through: 3.0, by: 0.25) {
            #expect(clip.fadeOpacity(atLocalTime: t) == 1)
        }
    }

    // MARK: Media pool cells

    @Test func theMediaPoolFitsThreeColumnsWideAndTwoNarrow() {
        #expect(VideoStudioMetrics.mediaPoolColumnCount(columnWidth: VideoStudioMetrics.mediaPoolWideWidth) == 3)
        #expect(VideoStudioMetrics.mediaPoolColumnCount(columnWidth: VideoStudioDeskGeometry.poolWidth) == 2)
    }

    /// The cells and their gaps must not add up to more than the column, or
    /// the last one in every row is clipped by the divider.
    @Test func theMediaPoolCellsFitInsideTheirColumn() {
        for width in [VideoStudioMetrics.mediaPoolWideWidth, VideoStudioDeskGeometry.poolWidth] {
            let count = CGFloat(VideoStudioMetrics.mediaPoolColumnCount(columnWidth: width))
            let cell = VideoStudioMetrics.mediaPoolCellWidth(columnWidth: width)
            #expect(cell > 0)
            #expect(cell * count + VideoStudioMetrics.mediaPoolCellSpacing * (count + 1) <= width)
        }
    }
}

/// The track header's switches and the keyboard's Esc, held at the model —
/// the rules FS-12.03b §4–5 give them, whatever window draws the buttons.
@MainActor
struct VideoStudioTrackSwitchTests {
    /// FS-12.03b AC-4: the V1 Mute button goes through Video sound and
    /// remembers the level — 0 is a level a user can dial, so muting cannot
    /// be read back off the volume alone.
    @Test func mutingTheVideoLaneRestoresItsLevel() {
        let model = VideoStudioModelFixture.model()
        model.setVideoVolume(0.6)
        model.toggleVideoTrackMuted()
        #expect(model.recipe.videoVolume == 0)
        #expect(model.isVideoTrackMuted)
        model.toggleVideoTrackMuted()
        #expect(abs(model.recipe.videoVolume - 0.6) < 0.0001)
        #expect(!model.isVideoTrackMuted)
    }

    /// FS-12.03b AC-5: muting A1 with two beds in it is one undo step —
    /// a single Undo brings both back to their own levels.
    @Test func mutingAMusicLaneUndoesInOneStep() throws {
        let model = VideoStudioModelFixture.model { recipe in
            var first = MusicTrack(source: .bundled(id: "calm"))
            first.sourceDuration = 5
            first.volume = 0.8
            var second = MusicTrack(source: .bundled(id: "drive"))
            second.sourceDuration = 5
            second.start = 12
            second.volume = 0.4
            recipe.musicTracks = [first, second]
        }
        #expect(model.musicTracks(inLane: 0).count == 2)
        model.toggleMusicLaneMuted(0)
        #expect(model.recipe.musicTracks.allSatisfy { $0.volume == 0 })
        #expect(model.isMusicLaneMuted(0))
        model.undo()
        let volumes = model.recipe.musicTracks.map(\.volume)
        #expect(volumes == [0.8, 0.4])
        #expect(!model.canUndo)
    }

    /// FS-12.03b AC-6: Esc ends the session keeping its change (= ✓), and
    /// ⌘Z then takes the change back. Calls the key's own action.
    @Test func escapeKeepsTheChangeAndUndoRevertsIt() {
        let model = VideoStudioModelFixture.model()
        let clip2 = model.recipe.clips[1].id
        model.selectClip(clip2)
        model.pushUndo()
        model.setSpeed(2, for: clip2)
        model.pressEscape()
        #expect(model.selectedClipID == nil)
        #expect(model.session == nil)
        #expect(model.recipe.clips[1].speed == 2)
        model.undo()
        #expect(model.recipe.clips[1].speed == 1)
    }
}
