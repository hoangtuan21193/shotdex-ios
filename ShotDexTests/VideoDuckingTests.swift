import AVFoundation
import Foundation
import Testing
@testable import ShotDex

actor CallLog {
    private(set) var calls: [(String, ClosedRange<Double>)] = []
    func record(_ assetID: String, _ range: ClosedRange<Double>) { calls.append((assetID, range)) }
    var count: Int { calls.count }
}

/// The clips' sound as the studio holds it (FS-12.13 §4, §6): listened to
/// off the main actor, by asset, never twice for the same part.
@MainActor
struct VideoDuckingModelTests {
    typealias Span = ClipSoundActivity.Span
    static let dummySource = VideoClipSource.photo(assetID: "x", pixelSize: .zero)

    static func needs(_ recipe: VideoProjectRecipe) -> [VideoDuckingModel.Need] {
        DuckingMath.neededRanges(recipe).map { .init(assetID: $0.key, range: $0.value, source: dummySource) }
    }

    private func settle(_ model: VideoDuckingModel) async {
        for _ in 0..<400 where model.isListening { try? await Task.sleep(for: .milliseconds(5)) }
    }

    static func listener(_ log: CallLog, fails: Set<String> = [], delay: Duration = .zero) -> VideoDuckingModel {
        VideoDuckingModel(analyze: { assetID, _, range in
            await log.record(assetID, range)
            if delay > .zero { try await Task.sleep(for: delay) }
            if fails.contains(assetID) { throw ClipSoundAnalyzer.Failure.unreadable }
            let voices = DuckingMathTests.sampleActivity[assetID]?.voices ?? []
            return ClipSoundActivity(analyzedStart: range.lowerBound, analyzedEnd: range.upperBound, voices: voices, rmsDB: [])
        })
    }

    /// AC-8: with ducking on and the clips analysed, swapping clips 2 and 3
    /// analyses nothing again — and the dips go with their clips.
    @Test func reorderAnalysesZeroTimes() async throws {
        let log = CallLog()
        let model = Self.listener(log)
        var recipe = DuckingMathTests.project()
        model.listen(to: Self.needs(recipe))
        await settle(model)
        #expect(await log.count == 3)

        recipe.clips.swapAt(1, 2)
        recipe.syncTransitionsWithClips()
        model.listen(to: Self.needs(recipe))
        await settle(model)
        #expect(await log.count == 3)

        // Lake (5.0s) now first video at 3.0: its voice, source 1.6–3.8,
        // is 4.6–6.8; Coast at 8.0 has 9.2–12.4.
        let spans = DuckingMath.triggers(recipe, activity: model.activity, trigger: .voices).flatMap(\.spans)
        let rounded = spans.map { [($0.start * 10).rounded() / 10, ($0.end * 10).rounded() / 10] }
        #expect(rounded.prefix(2) == [[4.6, 6.8], [9.2, 12.4]])
    }

    /// A trim that reaches further reads only the new part: Coast trimmed
    /// out from 6.2s to 8.0s asks for 6.2–8.0 alone.
    @Test func widerTrimReadsOnlyTheNewPart() async throws {
        let cache = AudioAnalysisCache(directory: nil)
        let known = ClipSoundActivity(analyzedStart: 0, analyzedEnd: 6.2, voices: [Span(start: 1.2, end: 4.4)], rmsDB: Array(repeating: -50, count: 124))
        await cache.store(known, for: ClipSoundAnalyzer.key("Coast"))
        #expect(known.missing(0, 8) == [6.2...8.0])
        #expect(known.missing(0, 6.2).isEmpty)
        #expect(known.missing(0.5, 5).isEmpty)
        // Before: whole 50 ms windows, so the two line up.
        let later = ClipSoundActivity(analyzedStart: 1.0, analyzedEnd: 4.0, voices: [], rmsDB: Array(repeating: -50, count: 60))
        #expect(later.missing(0.33, 4.0).first.map { abs($0.lowerBound - 0.3) < 1e-9 && $0.upperBound == 1.0 } == true)
        let tail = ClipSoundActivity(analyzedStart: 6.2, analyzedEnd: 8.0, voices: [Span(start: 6.2, end: 7.0)], rmsDB: Array(repeating: -20, count: 36))
        let joined = known.joined(with: tail)
        #expect(joined.analyzedStart == 0 && joined.analyzedEnd == 8.0)
        #expect(joined.rmsDB.count == 160)
        #expect(joined.voices == [Span(start: 1.2, end: 4.4), Span(start: 6.2, end: 7.0)])
    }

    /// AC-12: a clip that cannot be read makes no dip and is named in the
    /// summary — "· 1 clip not checked"; the others dip as before.
    @Test func unreadableClipIsNotChecked() async throws {
        let log = CallLog()
        let model = Self.listener(log, fails: ["Lake"])
        let recipe = DuckingMathTests.project()
        model.listen(to: Self.needs(recipe))
        await settle(model)
        #expect(model.unreadable == ["Lake"])
        let triggers = DuckingMath.triggers(recipe, activity: model.activity, trigger: .voices)
        #expect(triggers.count == 2)
        #expect(!triggers.map(\.clipID).contains(recipe.clips[2].id))
        #expect(VideoStudioCopy.clipsNotChecked(1) == " · 1 clip not checked")
        #expect(VideoStudioCopy.duckingSummary(.voices, clips: 2, seconds: 5.4) + VideoStudioCopy.clipsNotChecked(1)
            == "Voices in 2 clips · 5.4s · 1 clip not checked")
        // Not tried again on its own; a retry (it downloaded) reads it.
        model.listen(to: Self.needs(recipe))
        await settle(model)
        #expect(await log.count == 3)
        model.retryUnreadable()
        model.listen(to: Self.needs(recipe))
        await settle(model)
        #expect(await log.count == 4)
    }

    /// AC-14: closing the studio mid-analysis stops every task within a
    /// second, and nothing is kept half-done; opening again asks again.
    @Test func closeCancelsWithinOneSecond() async throws {
        let log = CallLog()
        let model = Self.listener(log, delay: .seconds(30))
        let recipe = DuckingMathTests.project()
        model.listen(to: Self.needs(recipe))
        #expect(model.isListening)
        let began = Date()
        model.cancelAll()
        #expect(!model.isListening)
        #expect(Date().timeIntervalSince(began) < 1)
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.activity.isEmpty && model.unreadable.isEmpty)

        let reopened = Self.listener(log)
        reopened.listen(to: Self.needs(recipe))
        await settle(reopened)
        #expect(reopened.activity.count == 3)
    }

    /// The summary line's words (§4).
    @Test func summaryWords() {
        #expect(VideoStudioCopy.duckingSummary(.voices, clips: 3, seconds: 8.6) == "Voices in 3 clips · 8.6s")
        #expect(VideoStudioCopy.duckingSummary(.voices, clips: 1, seconds: 3.2) == "Voices in 1 clip · 3.2s")
        #expect(VideoStudioCopy.noVoices(.voices) == "No voices in clip sound")
        #expect(VideoStudioCopy.decibels(-12) == "−12 dB")
        #expect(VideoStudioCopy.listeningForVoices == "Listening for voices…")
    }
}

/// The five settings on the studio (FS-12.13 §4, §6).
@MainActor
struct VideoDuckingSettingsTests {
    static func model() -> (VideoStudioModel, UUID) {
        var bed = MusicTrack(source: .bundled(id: "Morning Drive"))
        bed.sourceDuration = 18.4
        let id = bed.id
        return (VideoStudioModelFixture.model(configure: { $0.musicTracks = [bed] }), id)
    }

    /// AC-9 on the model: UNDER VOICES is one undo step each way.
    @Test func toggleIsOneUndo() {
        let (model, id) = Self.model()
        model.setDucking(true, for: id)
        #expect(model.recipe.musicTracks[0].ducking.isOn)
        model.undo()
        #expect(!model.recipe.musicTracks[0].ducking.isOn)
        #expect(!model.canUndo)
        model.redo()
        #expect(model.recipe.musicTracks[0].ducking.isOn)
    }

    /// AC-10: one drag of Amount from −12 to −18 dB is one undo step, the
    /// audio tier only — no structural rebuild is asked for.
    @Test func amountDragOneUndoNoRebuild() {
        let (model, id) = Self.model()
        model.setDucking(true, for: id)
        let rebuilds = model.structuralRebuildRequests
        let mixes = model.audioTierRequests
        model.beginUndoGroup()
        for value in stride(from: -12.0, through: -18.0, by: -0.5) { model.setDuckingAmount(value, for: id) }
        model.endUndoGroup()
        #expect(model.recipe.musicTracks[0].ducking.amountDB == -18)
        #expect(model.structuralRebuildRequests == rebuilds)
        #expect(model.audioTierRequests > mixes)
        model.undo()
        #expect(model.recipe.musicTracks[0].ducking.amountDB == -12)
        #expect(model.recipe.musicTracks[0].ducking.isOn)

        // Duck in, Recover, the trigger: clamped, rounded, audio tier. (An
        // undo is always the structural tier — a snapshot can differ in
        // anything — so count again from here.)
        let afterUndo = model.structuralRebuildRequests
        model.setDuckingDuckIn(0.04, for: id)
        model.setDuckingRecover(5, for: id)
        model.setDuckingTrigger(.anyClipSound, for: id)
        let ducking = model.recipe.musicTracks[0].ducking
        #expect(ducking.duckIn == 0.1 && ducking.recover == 2.0 && ducking.trigger == .anyClipSound)
        #expect(model.structuralRebuildRequests == afterUndo)
    }

    /// The Ducking command is on the music row now, after Beats.
    @Test func duckingCommandIsBuilt() {
        #expect(VideoItemCommand.commands(for: .music).prefix(2) == [.beats, .ducking])
    }
}

/// One audio mix for preview and export (FS-12.13 §4, D-12).
struct VideoAudioMixDuckingTests {
    static func layout(music: UUID, trackID: CMPersistentTrackID = 7, insertAt: Double = 0, duration: Double = 18.4) -> VideoCompositionBuilder.Layout {
        var layout = VideoCompositionBuilder.Layout()
        layout.musicAudio = [.init(musicID: music, trackID: trackID, insertAt: insertAt, duration: duration)]
        layout.totalDuration = 24
        return layout
    }

    /// The volume a mix gives `trackID` at each of `times`.
    static func volumes(_ mix: AVAudioMix, trackID: CMPersistentTrackID, at times: [Double]) -> [Float] {
        guard let params = mix.inputParameters.first(where: { $0.trackID == trackID }) else { return [] }
        return times.map { time in
            var start: Float = 0, end: Float = 0
            var range = CMTimeRange.zero
            let at = CMTime(seconds: time, preferredTimescale: 600)
            guard params.getVolumeRamp(for: at, startVolume: &start, endVolume: &end, timeRange: &range), range.duration.seconds > 0 else { return -1 }
            let progress = Float((time - range.start.seconds) / range.duration.seconds)
            return start + (end - start) * progress
        }
    }

    static let times = stride(from: 0.05, to: 18.4, by: 0.25).map { $0 }

    /// AC-9: ducking off gives exactly the mix that never had it, ramp for
    /// ramp; on, the same project dips at 4.2–7.4.
    @Test func offEqualsNeverOn() {
        var recipe = DuckingMathTests.project()
        recipe.musicTracks[0].ducking.isOn = false
        let layout = Self.layout(music: recipe.musicTracks[0].id)
        let off = VideoCompositionBuilder.audioMix(recipe: recipe, layout: layout, activity: DuckingMathTests.sampleActivity)
        let never = VideoCompositionBuilder.audioMix(recipe: recipe, layout: layout)
        #expect(Self.volumes(off, trackID: 7, at: Self.times) == Self.volumes(never, trackID: 7, at: Self.times))
        #expect(Self.volumes(off, trackID: 7, at: [5.8]) == [0.8])

        recipe.musicTracks[0].ducking.isOn = true
        let on = VideoCompositionBuilder.audioMix(recipe: recipe, layout: layout, activity: DuckingMathTests.sampleActivity)
        let dipped = Self.volumes(on, trackID: 7, at: [3.5, 5.8, 9.0, 12.0])
        #expect(abs(dipped[0] - 0.8) < 1e-4)
        #expect(abs(dipped[1] - 0.201) < 0.001)
        #expect(abs(dipped[2] - 0.8) < 1e-4)
        #expect(abs(dipped[3] - 0.201) < 0.001)
    }

    /// AC-6 through the mix: a muted clip 2 leaves 4.2–7.4 at full level.
    @Test func mutedClipLeavesTheMixAlone() {
        var recipe = DuckingMathTests.project()
        recipe.clips[1].isMuted = true
        let mix = VideoCompositionBuilder.audioMix(recipe: recipe, layout: Self.layout(music: recipe.musicTracks[0].id), activity: DuckingMathTests.sampleActivity)
        let levels = Self.volumes(mix, trackID: 7, at: [5.8, 12.0])
        #expect(abs(levels[0] - 0.8) < 1e-4)
        #expect(abs(levels[1] - 0.201) < 0.001)
    }

    /// §8's measure: 50 dips on one bed build in well under a frame's
    /// budget for the audio tier.
    @Test func fiftyDipsBuildQuickly() {
        var recipe = DuckingMathTests.project()
        recipe.musicTracks[0].sourceDuration = 200
        // 50 short voices far enough apart to stay 50 dips: spread over a
        // 100s clip at 2s spacing.
        let voices: [ClipSoundActivity.Span] = (0..<50).map { .init(start: Double($0) * 2 + 0.2, end: Double($0) * 2 + 0.5) }
        var long = VideoClip(assetID: "Long", kind: .video)
        long.sourceDuration = 100
        long.trimEnd = 100
        recipe.clips = [long]
        recipe.syncTransitionsWithClips()
        let activity = ["Long": ClipSoundActivity(analyzedStart: 0, analyzedEnd: 100, voices: voices, rmsDB: [])]
        let began = Date()
        let mix = VideoCompositionBuilder.audioMix(recipe: recipe, layout: Self.layout(music: recipe.musicTracks[0].id, duration: 100), activity: activity)
        let seconds = Date().timeIntervalSince(began)
        print("Ducking mix with 50 dips built in \(String(format: "%.1f", seconds * 1000)) ms")
        #expect(DuckingMath.dips(DuckingMath.triggers(recipe, activity: activity, trigger: .voices), ducking: recipe.musicTracks[0].ducking).count == 50)
        #expect(mix.inputParameters.count == 1)
        #expect(seconds < 0.05)
    }
}

/// AC-11 (D-12): a 440 Hz bed through the very `audioMix` export hands
/// `VideoExportWriter`, rendered by `AVAssetReaderAudioMixOutput` — 5–7s
/// is 12 ±1 dB under 1–3s.
struct VideoDuckingExportTests {
    static func writeSine(seconds: Double = 10, rate: Double = 44_100) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sine-\(UUID().uuidString).wav")
        let count = Int(seconds * rate)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
        buffer.frameLength = AVAudioFrameCount(count)
        let channel = buffer.floatChannelData![0]
        for index in 0..<count { channel[index] = 0.5 * Float(sin(2 * .pi * 440 * Double(index) / rate)) }
        try file.write(from: buffer)
        return url
    }

    @Test func sine440DipsTwelveDecibels() async throws {
        let url = try Self.writeSine()
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)
        let source = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let composition = AVMutableComposition()
        let track = try #require(composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid))
        try track.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: 10, preferredTimescale: 600)), of: source, at: .zero)

        // One 10s video clip with a voice at 5.0–7.0; the bed at Volume 80.
        var clip = VideoClip(assetID: "Voice", kind: .video)
        clip.sourceDuration = 10
        clip.trimEnd = 10
        var recipe = VideoProjectRecipe(clips: [clip])
        var music = MusicTrack(source: .bundled(id: "Sine 440"))
        music.sourceDuration = 10
        music.volume = 0.8
        music.fadeIn = 0
        music.fadeOut = 0
        music.ducking = MusicDucking(isOn: true)
        recipe.musicTracks = [music]
        var layout = VideoCompositionBuilder.Layout()
        layout.musicAudio = [.init(musicID: music.id, trackID: track.trackID, insertAt: 0, duration: 10)]
        layout.totalDuration = 10
        let activity = ["Voice": ClipSoundActivity(analyzedStart: 0, analyzedEnd: 10, voices: [.init(start: 5, end: 7)], rmsDB: [])]
        let mix = VideoCompositionBuilder.audioMix(recipe: recipe, layout: layout, activity: activity)

        let reader = try AVAssetReader(asset: composition)
        let output = AVAssetReaderAudioMixOutput(audioTracks: [track], audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        output.audioMix = mix
        reader.add(output)
        #expect(reader.startReading())
        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            if let block = CMSampleBufferGetDataBuffer(buffer) {
                let length = CMBlockBufferGetDataLength(block)
                var chunk = [Float](repeating: 0, count: length / 4)
                chunk.withUnsafeMutableBytes { raw in
                    _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
                }
                samples += chunk
            }
        }
        #expect(reader.status == .completed)
        func energy(_ from: Double, _ to: Double) -> Double {
            let slice = samples[Int(from * 44_100)..<min(samples.count, Int(to * 44_100))]
            return slice.reduce(0) { $0 + Double($1) * Double($1) } / Double(slice.count)
        }
        let difference = 10 * log10(energy(5, 7) / energy(1, 3))
        print("Sine 440 under a voice: \(String(format: "%.2f", difference)) dB")
        #expect(abs(difference + 12) <= 1)
    }
}
