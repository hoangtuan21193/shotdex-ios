import Foundation

/// Ducking (FS-12.13): what the clips are listened to for, the bed's five
/// settings, and what the panel and the graph read. Every setting is the
/// audio tier only — a new mix, never a new composition (§4).
extension VideoStudioModel {
    /// The part of each asset the project plays, over every clip that uses
    /// it — videos with their own sound only.
    var duckingNeeds: [VideoDuckingModel.Need] {
        var audible: [String: VideoClipSource] = [:]
        for clip in recipe.clips where clip.kind == .video {
            guard let source = sources[clip.id], case let .video(_, _, audioTrack, _, _, _) = source, audioTrack != nil else { continue }
            audible[clip.assetID] = source
        }
        return DuckingMath.neededRanges(recipe).compactMap { assetID, range in
            audible[assetID].map { .init(assetID: assetID, range: range, source: $0) }
        }
        .sorted { $0.assetID < $1.assetID }
    }

    /// Listens to what is not known yet — when a bed ducks, or `force`
    /// when the Ducking tab opens. A result rebuilds the mix.
    func refreshDucking(force: Bool = false) {
        guard force || recipe.musicTracks.contains(where: \.ducking.isOn) else { return }
        if ducking.onChange == nil {
            ducking.onChange = { [weak self] in self?.applyAudioTier() }
        }
        ducking.listen(to: duckingNeeds)
    }

    // MARK: Settings

    private func updateDucking(_ id: UUID, _ change: (inout MusicDucking) -> Void) {
        guard let index = recipe.musicTracks.firstIndex(where: { $0.id == id }) else { return }
        var value = recipe.musicTracks[index].ducking
        change(&value)
        guard value != recipe.musicTracks[index].ducking else { return }
        recipe.musicTracks[index].ducking = value
        markEdited()
        applyAudioTier()
    }

    /// UNDER VOICES — one undo step; turning it on listens to the clips.
    func setDucking(_ isOn: Bool, for id: UUID) {
        guard let track = recipe.musicTracks.first(where: { $0.id == id }), track.ducking.isOn != isOn else { return }
        pushUndo()
        updateDucking(id) { $0.isOn = isOn }
        if isOn { refreshDucking() }
    }

    /// Amount, in whole dB; a drag is one step (the slider's undo group).
    func setDuckingAmount(_ decibels: Double, for id: UUID) {
        let value = min(max(Int(decibels.rounded()), MusicDucking.amountRange.lowerBound), MusicDucking.amountRange.upperBound)
        updateDucking(id) { $0.amountDB = value }
    }

    /// Duck in, to a tenth of a second.
    func setDuckingDuckIn(_ seconds: Double, for id: UUID) {
        let value = min(max((seconds * 10).rounded() / 10, MusicDucking.duckInRange.lowerBound), MusicDucking.duckInRange.upperBound)
        updateDucking(id) { $0.duckIn = value }
    }

    /// Recover, to a tenth of a second.
    func setDuckingRecover(_ seconds: Double, for id: UUID) {
        let value = min(max((seconds * 10).rounded() / 10, MusicDucking.recoverRange.lowerBound), MusicDucking.recoverRange.upperBound)
        updateDucking(id) { $0.recover = value }
    }

    /// Voices · Any Clip Sound — one undo step, nothing analysed again
    /// (D-13: one read serves both).
    func setDuckingTrigger(_ trigger: MusicDucking.Trigger, for id: UUID) {
        guard let track = recipe.musicTracks.first(where: { $0.id == id }), track.ducking.trigger != trigger else { return }
        pushUndo()
        updateDucking(id) { $0.trigger = trigger }
    }

    // MARK: What the panel reads

    /// The clips that make `track` dip, on the timeline.
    func duckingTriggers(for track: MusicTrack) -> [DuckingMath.ClipTrigger] {
        DuckingMath.triggers(recipe, activity: ducking.activity, trigger: track.ducking.trigger)
    }

    /// The bed's dips, merged — empty while it does not duck.
    func duckingDips(for track: MusicTrack) -> [ClipSoundActivity.Span] {
        guard track.ducking.isOn else { return [] }
        return DuckingMath.dips(duckingTriggers(for: track), ducking: track.ducking)
    }

    /// Clips with sound to check that could not be read (§6).
    var duckingNotCheckedCount: Int {
        recipe.clips.filter { clip in
            DuckingMath.canTrigger(clip, videoVolume: recipe.videoVolume) && ducking.unreadable.contains(clip.assetID)
        }.count
    }

    /// "Voices in 3 clips · 8.6s", "Listening for voices…", "No voices in
    /// clip sound", with "· 1 clip not checked" when one could not be read.
    func duckingSummary(for track: MusicTrack) -> String {
        if ducking.isListening { return VideoStudioCopy.listeningForVoices }
        let summary = DuckingMath.summary(duckingTriggers(for: track))
        let text = summary.clipCount == 0
            ? VideoStudioCopy.noVoices(track.ducking.trigger)
            : VideoStudioCopy.duckingSummary(track.ducking.trigger, clips: summary.clipCount, seconds: summary.seconds)
        let unchecked = duckingNotCheckedCount
        return unchecked > 0 ? text + VideoStudioCopy.clipsNotChecked(unchecked) : text
    }

    /// The bed's level at timeline second `time` — the graph and the line
    /// on the lane read the mix's own arithmetic.
    func duckingLevel(for track: MusicTrack, at time: Double, dips: [ClipSoundActivity.Span]) -> Double {
        DuckingMath.level(
            at: time - track.start,
            total: max(track.effectiveDuration, 0.001),
            volume: track.isMuted ? 0 : track.volume,
            fadeIn: track.fadeIn,
            fadeOut: track.fadeOut,
            insertAt: track.start,
            dips: dips,
            ducking: track.ducking
        )
    }

    /// Voice stretches of every clip, on the timeline — the Voice labels on
    /// V1 and the blue on the graph's clip strip.
    var voiceSpansOnTimeline: [ClipSoundActivity.Span] {
        DuckingMath.triggers(recipe, activity: ducking.activity, trigger: .voices).flatMap(\.spans)
    }
}
