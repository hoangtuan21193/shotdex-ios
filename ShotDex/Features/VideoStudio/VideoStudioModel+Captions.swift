import Foundation

/// Auto captions (FS-12.14): starting a run, merging what each clip says
/// into the lane, the lane as one item on the timeline, and its cues.
///
/// The lane is a session of its own — `.captions` — opened **before** the
/// lane is made, so ✕ during the first run takes the lane back with every
/// step since the panel opened (AC-11). A cue is a selection inside that
/// session, not an item of its own: tapping another cue keeps the session.
extension VideoStudioModel {
    // MARK: The lane on screen

    /// The visible cues, in timeline order.
    var placedCaptions: [CaptionTimeline.Placed] {
        CaptionTimeline.placed(recipe.captions, in: recipe)
    }

    /// The selected cue, if it is still in the lane.
    var selectedCaption: CaptionCue? {
        guard let selectedCaptionID else { return nil }
        return recipe.captions?.cues.first { $0.id == selectedCaptionID }
    }

    /// The cue playing at the playhead.
    var captionAtPlayhead: CaptionTimeline.Placed? {
        CaptionTimeline.cue(at: currentTime, in: placedCaptions)
    }

    /// What Auto Captions' row says and does: Auto Captions, or — once the
    /// project has a lane — Edit Captions (§3).
    var hasCaptionLane: Bool { recipe.captions != nil }

    /// The row is dimmed when no language at all can be recognised here.
    var canAutoCaption: Bool { captions.hasAnyModel }

    // MARK: Starting

    /// Auto Captions tapped (FS-12.14 §4, AC-1, AC-2): opens the lane's
    /// panel, asks for the permission the first time, then makes the lane —
    /// one undo step — and reads the clips one by one. With a lane already
    /// there it only opens it.
    func startAutoCaptions() async {
        if recipe.captions != nil {
            openCaptions(cue: nil)
            return
        }
        guard canAutoCaption, let language = captions.defaultLanguage else { return }
        openCaptions(cue: nil)
        let answer = await captions.authorize()
        guard answer == .authorized, inspectorTarget == .caption, recipe.captions == nil else { return }
        let planned = CaptionRecognitionPlan.clipIDs(in: recipe)
        guard !planned.isEmpty else {
            captions.reportNoSpeech()
            return
        }
        pushUndo()
        laneMadeAtStep = history.newestSequence
        var lane = VideoCaptionLane()
        lane.language = language
        lane.recognition.plannedClipIDs = planned
        recipe.captions = lane
        markEdited()
        runCaptionRecognition(planned)
    }

    /// Reads `clipIDs` in order, merging each into the lane as it lands.
    func runCaptionRecognition(_ clipIDs: [UUID]) {
        guard let lane = recipe.captions else { return }
        let clips: [VideoCaptionSession.Clip] = clipIDs.compactMap { id in
            guard let clip = recipe.clips.first(where: { $0.id == id }) else { return nil }
            let source = sources[id] ?? .unavailable(assetID: clip.assetID)
            return VideoCaptionSession.Clip(id: id, source: source, window: CaptionRecognitionPlan.sourceWindow(of: clip))
        }
        let lengths = Dictionary(
            recipe.clips.filter { lane.recognition.plannedClipIDs.contains($0.id) }.map { ($0.id, $0.effectiveDuration) },
            uniquingKeysWith: { first, _ in first }
        )
        let done = recipe.clips
            .filter { lane.recognition.finishedClipIDs.contains($0.id) && lengths[$0.id] != nil }
            .reduce(0) { $0 + $1.effectiveDuration }
        recipe.captions?.recognition.stoppedAtPercent = nil
        captions.run(
            clips,
            language: lane.language,
            lengths: lengths,
            alreadyDone: done,
            onClip: { [weak self] id, words in
                self?.mergeCaptions(words, clipID: id) ?? false
            },
            onUnreadable: { [weak self] id in
                self?.updateLaneEverywhere { CaptionRecognitionPlan.markUnreadable(id, in: &$0) }
            },
            onEnd: { [weak self] heard in
                self?.captionRunEnded(heardAnything: heard)
            }
        )
    }

    /// One clip's words into the lane — on the project and on every undo
    /// snapshot that has the lane, so neither Undo nor ✕ of a later edit
    /// takes back what was heard, and no undo step is added (plan K4).
    /// False when the lane is gone: undone past its making, recognition
    /// stops.
    func mergeCaptions(_ words: [CaptionWord], clipID: UUID) -> Bool {
        guard recipe.captions != nil else { return false }
        let cues = CaptionChunker.cues(from: words, clipID: clipID)
        let order = recipe.clips.map(\.id)
        updateLaneEverywhere { CaptionRecognitionPlan.merge(cues, clipID: clipID, into: &$0, order: order) }
        markEdited()
        return true
    }

    /// The run read every clip. No words anywhere: the lane goes, and so
    /// does the step that made it, when it is still the newest (AC-14).
    func captionRunEnded(heardAnything: Bool) {
        guard let lane = recipe.captions else { return }
        guard !heardAnything, lane.cues.isEmpty, captions.unreadableClipIDs.isEmpty else { return }
        if let step = laneMadeAtStep, let before = takeBackStep(step) {
            recipe.captions = before.captions
        } else {
            recipe.captions = nil
        }
        laneMadeAtStep = nil
        selectedCaptionID = nil
    }

    /// Applies `change` to the lane of the project, of the open session's
    /// start and of every undo and redo snapshot that has one.
    func updateLaneEverywhere(_ change: (inout VideoCaptionLane) -> Void) {
        if var lane = recipe.captions {
            change(&lane)
            recipe.captions = lane
        }
        patchHistory { snapshot in
            guard var lane = snapshot.captions else { return }
            change(&lane)
            snapshot.captions = lane
        }
        patchSessionStart { snapshot in
            guard var lane = snapshot.captions else { return }
            change(&lane)
            snapshot.captions = lane
        }
    }

    // MARK: Selecting

    /// Opens the lane's panel, with `cue` selected when given. Keeps the
    /// session when the lane is already open: a cue is not an item.
    func openCaptions(cue: UUID?) {
        if inspectorTarget != .caption {
            clearSelection()
            isCaptionLaneOpen = true
            beginCaptionSession()
            activeItemCommand = .edit
        }
        selectedCaptionID = cue
    }

    /// A cue tapped on C1 or on the frame: selects it, and moves the
    /// playhead to its start when asked (the Edit list's times).
    func selectCaption(_ id: UUID, seeks: Bool = false) {
        guard !isLaneLocked(.captions) else { return }
        openCaptions(cue: id)
        if seeks, let placed = placedCaptions.first(where: { $0.cue.id == id }) {
            seek(to: placed.start)
        }
    }

    /// The lane's own name in ✕ · name · ✓ when no cue is selected.
    var captionFooterTitle: VideoItemTitle.Lines {
        let placed = placedCaptions
        if let id = selectedCaptionID, let index = placed.firstIndex(where: { $0.cue.id == id }) {
            let cue = placed[index]
            return VideoItemTitle.Lines(
                name: CaptionChunker.name(at: index),
                detail: "\(VideoStudioMetrics.captionTime(cue.start)) → \(VideoStudioMetrics.captionTime(cue.end))"
            )
        }
        return VideoItemTitle.Lines(name: VideoStudioCopy.captions, detail: VideoStudioCopy.captionCount(placed.count))
    }

    /// The recogniser a studio opens with: the system's, or — on a UI route
    /// — the stand-in `-ShotDexFakeSpeech` asks for (plan K8).
    static func launchCaptionSession() -> VideoCaptionSession {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ShotDexFakeSpeechDenied") { return .fake(denied: true) }
        // `-ShotDexFakeSpeechSlow`: 15 s a clip, so a route can photograph
        // the card part-way with a cue selected (boards F4_*).
        if arguments.contains("-ShotDexFakeSpeechSlow") { return .fake(denied: false, delay: .seconds(15)) }
        if arguments.contains("-ShotDexFakeSpeech") { return .fake(denied: false) }
        #endif
        return .system()
    }

    /// ✕ while the first run is on: the run stops and the session's own
    /// rollback takes the lane back (AC-11).
    func stopCaptionsForCancel() {
        captions.cancel()
        laneMadeAtStep = nil
    }
}

// MARK: - Clips changing under the lane (plan K7)

extension VideoStudioModel {
    /// Keeps captions with their words after the clips changed: a split
    /// clip's cues go to its pieces, a duplicate gets copies, a deleted or
    /// replaced clip's go. Part of the same undo step as the clip edit.
    func reconcileCaptions(from old: [VideoClip]) {
        guard let lane = recipe.captions, old != recipe.clips else { return }
        let reconciled = CaptionTimeline.reconciled(lane, from: old, to: recipe.clips)
        if reconciled != lane { recipe.captions = reconciled }
        if let id = selectedCaptionID, !reconciled.cues.contains(where: { $0.id == id }) { selectedCaptionID = nil }
    }
}

// MARK: - Editing the lane (FS-12.14 §5) — each change one undo step

extension VideoStudioModel {
    /// One change to the lane as it is now; no lane, no change.
    private func editLane(_ change: (inout VideoCaptionLane) -> Void) {
        guard var lane = recipe.captions else { return }
        change(&lane)
        guard lane != recipe.captions else { return }
        recipe.captions = lane
        markEdited()
    }

    /// Typing in a cue's field. The field groups its keystrokes into one
    /// step (it opens an undo group while focused).
    func setCaptionText(_ text: String, for id: UUID) {
        editLane { lane in
            guard let index = lane.cues.firstIndex(where: { $0.id == id }) else { return }
            lane.cues[index] = CaptionEditing.editing(lane.cues[index], text: text)
        }
    }

    func setCaptionStyle(_ style: CaptionStyle) {
        guard recipe.captions?.style != style else { return }
        pushUndo()
        editLane { $0.style = style }
    }

    /// Size, 3–12 % — a drag is one step (the slider groups it).
    func setCaptionSize(_ percent: Double) {
        let value = (min(max(percent, VideoCaptionLane.sizeRange.lowerBound), VideoCaptionLane.sizeRange.upperBound) * 2).rounded() / 2
        editLane { $0.sizePercent = value }
    }

    func setCaptionPosition(_ position: CaptionPosition) {
        guard recipe.captions?.position != position else { return }
        pushUndo()
        editLane { $0.position = position }
    }

    /// Burn into video (AC-16): one undo step either way.
    func setCaptionBurnsIn(_ burnsIn: Bool) {
        guard let lane = recipe.captions, lane.burnsIn != burnsIn else { return }
        pushUndo()
        editLane { $0.burnsIn = burnsIn }
    }

    /// A block dragged on C1 — one undo step; a locked lane does not move.
    func dragCaption(_ id: UUID, edge: CaptionTimeline.DragEdge, by delta: Double) {
        guard !isLaneLocked(.captions), let moved = CaptionTimeline.dragged(id, edge: edge, by: delta, in: recipe),
              moved != recipe.captions?.cues.first(where: { $0.id == id })
        else { return }
        pushUndo()
        editLane { lane in
            guard let index = lane.cues.firstIndex(where: { $0.id == id }) else { return }
            lane.cues[index] = moved
        }
    }

    // MARK: Split · Merge · Delete

    /// Split (AC-7): the selected cue at the playhead, at the word boundary
    /// nearest it. Dimmed when the playhead is not inside the cue.
    var captionSplit: (CaptionCue, CaptionCue)? {
        guard let id = selectedCaptionID, let placed = placedCaptions.first(where: { $0.cue.id == id }),
              currentTime > placed.start, currentTime < placed.end
        else { return nil }
        let clip = recipe.clips[placed.clipIndex]
        let placement = clipPlacements[placed.clipIndex]
        let source = CaptionTimeline.sourceTime(atTimeline: currentTime, clip: clip, placement: placement)
        return CaptionEditing.split(placed.cue, atSource: source)
    }

    func splitSelectedCaption() {
        guard let id = selectedCaptionID, let (left, right) = captionSplit else { return }
        pushUndo()
        editLane { lane in
            guard let index = lane.cues.firstIndex(where: { $0.id == id }) else { return }
            lane.cues.replaceSubrange(index...index, with: [left, right])
        }
        selectedCaptionID = left.id
    }

    /// Merge (AC-8): the selected cue and the one after it, from the same
    /// clip. Dimmed on the last cue.
    var captionMergePartner: CaptionCue? {
        guard let id = selectedCaptionID, let next = CaptionEditing.next(after: id, in: placedCaptions),
              let cue = selectedCaption, next.cue.clipID == cue.clipID
        else { return nil }
        return next.cue
    }

    func mergeSelectedCaption() {
        guard let cue = selectedCaption, let partner = captionMergePartner,
              let merged = CaptionEditing.merge(cue, partner)
        else { return }
        pushUndo()
        editLane { lane in
            lane.cues.removeAll { $0.id == partner.id }
            if let index = lane.cues.firstIndex(where: { $0.id == cue.id }) { lane.cues[index] = merged }
        }
    }

    /// Delete: the selected cue; with no cue selected — the lane chosen by
    /// its C1 label — the whole lane.
    func deleteSelectedCaption() {
        guard recipe.captions != nil else { return }
        guard let id = selectedCaptionID else {
            deleteCaptionLane()
            return
        }
        pushUndo()
        editLane { $0.cues.removeAll { $0.id == id } }
        selectedCaptionID = nil
    }

    func deleteCaptionLane() {
        guard recipe.captions != nil else { return }
        captions.cancel()
        pushUndo()
        recipe.captions = nil
        markEdited()
        endCaptionPanel()
    }

    /// Closes the lane's panel keeping what it changed (= ✓).
    func endCaptionPanel() {
        guard isCaptionLaneOpen else { return }
        clearSelection()
    }

    // MARK: Language (AC-4, task 5)

    /// Captions typed over by hand: a new language would replace them.
    var editedCaptionCount: Int {
        recipe.captions?.cues.filter(\.isEdited).count ?? 0
    }

    /// The lane recognised again in `language` — one undo step for the
    /// whole change. A language with no model on the device changes nothing.
    func changeCaptionLanguage(_ language: String) {
        guard let lane = recipe.captions, lane.language != language, captions.isAvailable(language) else { return }
        captions.cancel()
        pushUndo()
        let planned = CaptionRecognitionPlan.clipIDs(in: recipe)
        editLane { lane in
            lane.language = language
            lane.cues = []
            lane.recognition = CaptionRecognitionState(plannedClipIDs: planned)
        }
        selectedCaptionID = nil
        runCaptionRecognition(planned)
    }

    // MARK: Stopping and going on (AC-12, AC-13)

    /// The percentage the card shows while the run goes.
    var captionPercent: Int {
        CaptionRecognitionPlan.percent(captions.progress, isComplete: recipe.captions?.recognition.isComplete ?? false)
    }

    /// Back with a run going: it stops, and the lane remembers where — the
    /// reopened project says "Captions stopped at 58%" with Continue.
    func stopCaptionsForLeaving() {
        guard captions.isRunning, recipe.captions != nil else { return }
        let percent = captionPercent
        captions.cancel()
        updateLaneEverywhere { $0.recognition.stoppedAtPercent = percent }
    }

    /// Continue: only the clips not read yet.
    func continueCaptions() {
        guard let lane = recipe.captions else { return }
        let remaining = lane.recognition.remainingClipIDs.filter { id in recipe.clips.contains { $0.id == id } }
        guard !remaining.isEmpty else {
            updateLaneEverywhere { $0.recognition.stoppedAtPercent = nil }
            return
        }
        runCaptionRecognition(remaining)
    }

    /// Retry: the clips that could not be read, loaded again and read.
    func retryUnreadableCaptions() async {
        let ids = captions.unreadableClipIDs
        guard !ids.isEmpty, recipe.captions != nil else { return }
        let clips = recipe.clips.filter { ids.contains($0.id) }
        let loaded = await reloadSources(for: clips)
        guard !loaded.isEmpty, recipe.captions != nil else { return }
        updateLaneEverywhere { lane in
            for id in loaded where !lane.recognition.plannedClipIDs.contains(id) {
                lane.recognition.plannedClipIDs.append(id)
            }
        }
        runCaptionRecognition(loaded)
    }

    /// What the card says, in the order a person needs it.
    enum CaptionCard: Equatable {
        case asking, denied, restricted, noSpeech
        case running(percent: Int, done: Int, total: Int)
        case stopped(percent: Int)
    }

    var captionCard: CaptionCard? {
        switch captions.status {
        case .asking: return .asking
        case .denied: return .denied
        case .restricted: return .restricted
        case .noSpeech: return recipe.captions == nil ? .noSpeech : nil
        case .running:
            let lane = recipe.captions?.recognition
            let total = lane?.plannedClipIDs.count ?? captions.plannedCount
            let done = lane?.finishedClipIDs.filter { lane?.plannedClipIDs.contains($0) == true }.count ?? 0
            return .running(percent: captionPercent, done: done, total: max(total, done))
        case .idle:
            if let stopped = recipe.captions?.recognition.stoppedAtPercent { return .stopped(percent: stopped) }
            return nil
        }
    }
}
