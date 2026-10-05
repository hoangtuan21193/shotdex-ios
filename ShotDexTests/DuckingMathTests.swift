import Foundation
import Testing
@testable import ShotDex

/// Ducking on FS-12.13 §7's project: 3.0s photo · 6.2s video · 5.0s video ·
/// 3.0s photo · 6.8s video (24.0s), Morning Drive on A1 0.0–18.4 at Volume
/// 80, no fades; voices at 4.2–7.4, 10.8–13.0 and 18.7–21.9 on the
/// timeline — source 1.2–4.4 of Coast, 1.6–3.8 of Lake, 1.5–4.7 of Forest.
struct DuckingMathTests {
    typealias Span = ClipSoundActivity.Span

    static let ducking = MusicDucking(isOn: true)

    static func project() -> VideoProjectRecipe {
        var recipe = CutToBeatMathTests.project()
        var music = MusicTrack(source: .bundled(id: "Morning Drive"))
        music.sourceDuration = 18.4
        music.volume = 0.8
        music.fadeIn = 0
        music.fadeOut = 0
        music.ducking = ducking
        recipe.musicTracks = [music]
        return recipe
    }

    static func activity(_ voices: [Span], start: Double = 0, end: Double = 10, rms: [Float] = []) -> ClipSoundActivity {
        ClipSoundActivity(analyzedStart: start, analyzedEnd: end, voices: voices, rmsDB: rms)
    }

    static let sampleActivity: [String: ClipSoundActivity] = [
        "Coast": activity([Span(start: 1.2, end: 4.4)]),
        "Lake": activity([Span(start: 1.6, end: 3.8)]),
        "Forest": activity([Span(start: 1.5, end: 4.7)], end: 6.8),
    ]

    /// The bed's level at `time` from the ramps the mix is given.
    static func level(_ ramps: [VideoTimelineMath.VolumeRamp], at time: Double) -> Double {
        DuckingMath.fadeGain(at: time, fades: ramps)
    }

    static func ramps(dips: [Span], fadeOut: Double = 0, total: Double = 18.4) -> [VideoTimelineMath.VolumeRamp] {
        DuckingMath.ramps(total: total, volume: 0.8, fadeIn: 0, fadeOut: fadeOut, insertAt: 0, dips: dips, ducking: ducking)
    }

    /// AC-2: 0.8 to 3.9s; straight down to 0.201 at 4.2; held to 7.4;
    /// back at 0.8 by 8.2.
    @Test func singleDipShape() {
        let dips = DuckingMath.dips([.init(clipID: UUID(), spans: [Span(start: 4.2, end: 7.4)])], ducking: Self.ducking)
        let ramps = Self.ramps(dips: dips)
        #expect(abs(Self.level(ramps, at: 0) - 0.8) < 1e-9)
        #expect(abs(Self.level(ramps, at: 3.9) - 0.8) < 1e-9)
        #expect(abs(Self.level(ramps, at: 4.2) - 0.201) < 0.0005)
        #expect(abs(Self.level(ramps, at: 4.05) - (0.8 + 0.201) / 2) < 0.001)
        #expect(abs(Self.level(ramps, at: 7.4) - 0.201) < 0.0005)
        #expect(abs(Self.level(ramps, at: 8.2) - 0.8) < 1e-9)
        #expect(abs(Self.level(ramps, at: 12) - 0.8) < 1e-9)
        // The ramps tile the bed, end to end.
        #expect(ramps.first?.start == 0)
        #expect(abs((ramps.last.map { $0.start + $0.duration } ?? 0) - 18.4) < 1e-9)
        for (a, b) in zip(ramps, ramps.dropFirst()) { #expect(abs(a.start + a.duration - b.start) < 1e-9) }
    }

    /// AC-3: 4.2–5.0 and 5.8–6.5 — 0.8s apart, under Duck in + Recover
    /// (1.1) — make one dip, 3.9 to 7.3, with no rise between.
    @Test func shortGapHoldsTheFloor() {
        let dips = DuckingMath.dips([.init(clipID: UUID(), spans: [Span(start: 4.2, end: 5.0), Span(start: 5.8, end: 6.5)])], ducking: Self.ducking)
        #expect(dips == [Span(start: 4.2, end: 6.5)])
        let ramps = Self.ramps(dips: dips)
        #expect(abs(Self.level(ramps, at: 3.9) - 0.8) < 1e-9)
        #expect(abs(Self.level(ramps, at: 5.4) - 0.201) < 0.0005)
        #expect(abs(Self.level(ramps, at: 7.3) - 0.8) < 1e-9)
        #expect(Self.level(ramps, at: 7.0) < 0.8)
        // 1.2s apart is two dips.
        let apart = DuckingMath.merged([Span(start: 4.2, end: 5.0), Span(start: 6.2, end: 6.5)], gap: 1.1)
        #expect(apart.count == 2)
    }

    /// AC-4: a 2.0s fade out at the bed's end and a voice 16.0–18.4 —
    /// at 17.4 the level is 0.8 × 0.5 × 0.251 = 0.100 ±0.005; where both
    /// slope the stretch is four straight pieces (D-11).
    @Test func fadeAndDuckMultiply() {
        let dips = DuckingMath.dips([.init(clipID: UUID(), spans: [Span(start: 16.0, end: 18.4)])], ducking: Self.ducking)
        let ramps = Self.ramps(dips: dips, fadeOut: 2)
        #expect(abs(Self.level(ramps, at: 17.4) - 0.100) < 0.005)
        let exact = DuckingMath.level(at: 17.4, total: 18.4, volume: 0.8, fadeIn: 0, fadeOut: 2, insertAt: 0, dips: dips, ducking: Self.ducking)
        #expect(abs(exact - 0.8 * 0.5 * Self.ducking.floorGain) < 1e-9)
        // Duck in (15.7–16.0) runs inside the fade (16.4–18.4)? No: it ends
        // before; but a dip whose ramp crosses the fade is cut in four.
        let crossing = DuckingMath.dips([.init(clipID: UUID(), spans: [Span(start: 17.0, end: 17.2)])], ducking: Self.ducking)
        let pieces = Self.ramps(dips: crossing, fadeOut: 2).filter { $0.start >= 16.7 - 1e-9 && $0.start < 17.0 - 1e-9 }
        #expect(pieces.count == 4)
        for ramp in Self.ramps(dips: crossing, fadeOut: 2) {
            let middle = ramp.start + ramp.duration / 2
            let truth = DuckingMath.level(at: middle, total: 18.4, volume: 0.8, fadeIn: 0, fadeOut: 2, insertAt: 0, dips: crossing, ducking: Self.ducking)
            #expect(abs((ramp.fromVolume + ramp.toVolume) / 2 - truth) < 0.01 * 0.8)
        }
    }

    /// AC-7: Speed 2×, trim 0–10s, placed at 3.0s, voice at source 4.0–6.0
    /// — the dip's floor is exactly 5.0–6.0 on the timeline.
    @Test func speedTwoMapsSourceToTimeline() {
        var photo = VideoClip(assetID: "Falls", kind: .photo)
        photo.photoDuration = 3
        var fast = VideoClip(assetID: "Coast", kind: .video)
        fast.sourceDuration = 10
        fast.trimEnd = 10
        fast.speed = 2
        var recipe = VideoProjectRecipe(clips: [photo, fast])
        recipe.syncTransitionsWithClips()
        let triggers = DuckingMath.triggers(recipe, activity: ["Coast": Self.activity([Span(start: 4, end: 6)])], trigger: .voices)
        #expect(triggers.count == 1)
        let span = triggers[0].spans[0]
        #expect(abs(span.start - 5.0) < 1e-9 && abs(span.end - 6.0) < 1e-9)
        // A trim that starts at 5 keeps only the second half: 3.0–3.5.
        recipe.clips[1].trimStart = 5
        let trimmed = DuckingMath.triggers(recipe, activity: ["Coast": Self.activity([Span(start: 4, end: 6)])], trigger: .voices)
        #expect(abs(trimmed[0].spans[0].start - 3.0) < 1e-9 && abs(trimmed[0].spans[0].end - 3.5) < 1e-9)
    }

    /// The sample project: three clips, 8.6s of voice — "Voices in 3 clips
    /// · 8.6s" — at 4.2–7.4, 10.8–13.0, 18.7–21.9.
    @Test func sampleProjectTriggers() {
        let triggers = DuckingMath.triggers(Self.project(), activity: Self.sampleActivity, trigger: .voices)
        let spans = triggers.flatMap(\.spans).map { [($0.start * 10).rounded() / 10, ($0.end * 10).rounded() / 10] }
        #expect(spans == [[4.2, 7.4], [10.8, 13.0], [18.7, 21.9]])
        let summary = DuckingMath.summary(triggers)
        #expect(summary.clipCount == 3)
        #expect(abs(summary.seconds - 8.6) < 1e-9)
    }

    /// AC-6: a muted clip never triggers, nor does a photo, a clip at 0, or
    /// any clip while V1 is silenced; the summary does not count them.
    @Test func mutedClipNeverTriggers() {
        var recipe = Self.project()
        recipe.clips[1].isMuted = true
        var triggers = DuckingMath.triggers(recipe, activity: Self.sampleActivity, trigger: .voices)
        #expect(!triggers.map(\.clipID).contains(recipe.clips[1].id))
        #expect(DuckingMath.summary(triggers).clipCount == 2)

        recipe.clips[1].isMuted = false
        recipe.clips[2].volume = 0
        triggers = DuckingMath.triggers(recipe, activity: Self.sampleActivity, trigger: .voices)
        #expect(!triggers.map(\.clipID).contains(recipe.clips[2].id))

        recipe.clips[2].volume = 1
        recipe.videoVolume = 0
        #expect(DuckingMath.triggers(recipe, activity: Self.sampleActivity, trigger: .voices).isEmpty)

        // A photo with "activity" under its asset id is still a photo.
        recipe.videoVolume = 1
        let photoActivity = ["Falls": Self.activity([Span(start: 0, end: 3)])]
        #expect(DuckingMath.triggers(recipe, activity: photoActivity, trigger: .anyClipSound).isEmpty)
        #expect(!DuckingMath.canTrigger(recipe.clips[0], videoVolume: 1))
    }

    /// AC-5: wind at −30 dBFS and no voice — Voices: no dip; Any Clip
    /// Sound: the whole clip dips. At 5 % the same wind is −56 dB: none.
    @Test func windWithoutVoice() {
        let wind = Self.activity([], end: 10, rms: Array(repeating: -30, count: 200))
        let recipe = Self.project()
        #expect(DuckingMath.triggers(recipe, activity: ["Lake": wind], trigger: .voices).isEmpty)
        let sound = DuckingMath.triggers(recipe, activity: ["Lake": wind], trigger: .anyClipSound)
        #expect(sound.count == 1)
        #expect(abs(sound[0].spans[0].start - 9.2) < 1e-9 && abs(sound[0].spans[0].end - 14.2) < 1e-9)
        var quiet = recipe
        quiet.clips[2].volume = 0.05
        #expect(DuckingMath.triggers(quiet, activity: ["Lake": wind], trigger: .anyClipSound).isEmpty)
    }

    /// AC-9 at the math: off, or on with nothing to dip under, the ramps
    /// are exactly the fade ramps the mix had before ducking.
    @Test func offIsThePlainRamps() {
        let dips = [Span(start: 4.2, end: 7.4)]
        var off = Self.ducking
        off.isOn = false
        let plain = VideoTimelineMath.musicRamps(total: 18.4, volume: 0.8, fadeIn: 1, fadeOut: 2)
        #expect(DuckingMath.ramps(total: 18.4, volume: 0.8, fadeIn: 1, fadeOut: 2, insertAt: 0, dips: dips, ducking: off) == plain)
        #expect(DuckingMath.ramps(total: 18.4, volume: 0.8, fadeIn: 1, fadeOut: 2, insertAt: 0, dips: [], ducking: Self.ducking) == plain)
    }

    /// A bed placed later reads its dips in timeline seconds: inserted at
    /// 4.0, a voice at 10.8–13.0 bottoms out at bed second 6.8.
    @Test func laterBedShiftsItsDips() {
        let ramps = DuckingMath.ramps(total: 14, volume: 1, fadeIn: 0, fadeOut: 0, insertAt: 4, dips: [Span(start: 10.8, end: 13)], ducking: Self.ducking)
        #expect(abs(Self.level(ramps, at: 6.8) - Self.ducking.floorGain) < 1e-6)
        #expect(abs(Self.level(ramps, at: 6.5) - 1) < 1e-9)
    }

    /// AC-13's geometry: in a 370pt graph of 24s, the 18.4s bed is 283.7pt;
    /// a −12 dB dip is 26pt, −24 dB 50 — the box's floor.
    @Test func graphGeometry() {
        #expect(abs(370 * 18.4 / 24 - 283.7) < 0.1)
        #expect(DuckingMath.dipDepth(amountDB: -12) == 26)
        #expect(DuckingMath.dipDepth(amountDB: -6) == 13)
        #expect(DuckingMath.dipDepth(amountDB: -24) == 50)
        #expect(abs(MusicDucking(amountDB: -12).floorGain - 0.2512) < 0.0001)
    }

    /// The recipe keeps the five settings; missing keys are the defaults,
    /// broken or out-of-range ones are their default or their clamp.
    @Test func decodesLeniently() throws {
        let missing = try JSONDecoder().decode(MusicDucking.self, from: Data("{}".utf8))
        #expect(missing == MusicDucking())
        let odd = try JSONDecoder().decode(MusicDucking.self, from: Data(#"{"isOn":true,"amountDB":-40,"duckIn":"x","recover":9,"trigger":"wind"}"#.utf8))
        #expect(odd == MusicDucking(isOn: true, amountDB: -24, duckIn: 0.3, recover: 2, trigger: .voices))
        var track = MusicTrack(source: .bundled(id: "Morning Drive"))
        track.ducking = MusicDucking(isOn: true, amountDB: -18, trigger: .anyClipSound)
        let round = try JSONDecoder().decode(MusicTrack.self, from: JSONEncoder().encode(track))
        #expect(round.ducking == track.ducking)
    }
}
