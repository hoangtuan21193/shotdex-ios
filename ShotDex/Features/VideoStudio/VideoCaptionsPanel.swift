import SwiftUI
import ShotDexKit

/// The caption lane's panel (FS-12.14 §3, §5) under its command row Edit ·
/// Style · Split · Merge · Language · Delete.
///
/// The phone and the Duo show one section at a time — Edit (the progress
/// card, Language, the list of cues), Style, or the language list — as
/// every other item does there. The iPad shows the selected cue's words,
/// its time and the whole Style at once (boards F4_IL, F4_IP), the way its
/// text panel shows every section.
struct VideoCaptionsPanel: View {
    @Bindable var model: VideoStudioModel
    let actions: VideoInspectorActions
    /// The iPad's inspector (`.inspector`) or dock (`.dock`); else the
    /// phone's and the Duo's band and column.
    var shape: Shape = .band

    enum Shape { case band, inspector, dock }

    @State private var isConfirmingLanguage: String?

    private var lane: VideoCaptionLane? { model.recipe.captions }
    private var isDesk: Bool { shape != .band }
    private var inset: CGFloat { shape == .dock ? 0 : 16 }

    var body: some View {
        Group {
            switch shape {
            case .band: bandBody
            case .inspector: inspectorBody
            case .dock: dockBody
            }
        }
        .alert(
            isConfirmingLanguage.map { VideoStudioCopy.transcribeAgainTitle(CaptionLanguages.name(of: $0)) } ?? "",
            isPresented: Binding(get: { isConfirmingLanguage != nil }, set: { if !$0 { isConfirmingLanguage = nil } }),
            presenting: isConfirmingLanguage
        ) { language in
            Button(VideoStudioCopy.transcribe) { model.changeCaptionLanguage(language) }
            Button(VideoStudioCopy.cancel, role: .cancel) {}
        } message: { _ in
            Text(VideoStudioCopy.transcribeAgainMessage(model.editedCaptionCount))
        }
    }

    // MARK: Phone and Duo

    @ViewBuilder
    private var bandBody: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                switch model.activeItemCommand {
                case .style: styleSection
                case .language: languageList
                default: editSection
                }
            }
            .padding(.bottom, 12)
        }
    }

    /// Edit: the card, Language, CAPTIONS · N and the cues.
    @ViewBuilder
    private var editSection: some View {
        card.padding(.horizontal, 16).padding(.top, 4)
        unreadableLine.padding(.horizontal, 16)
        if let lane {
            languageRow(lane).padding(.top, 6)
            Text(VideoStudioCopy.captionListTitle(model.placedCaptions.count))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(EditorTheme.dimText)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(model.placedCaptions.enumerated()), id: \.element.cue.id) { index, placed in
                cueRow(placed, index: index)
            }
        }
    }

    /// "English (US) ›" — opens the language list.
    private func languageRow(_ lane: VideoCaptionLane) -> some View {
        Button {
            model.toggleItemSection(.language)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Text(VideoStudioCopy.language)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Text(verbatim: CaptionLanguages.name(of: lane.language))
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 16)
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("captionLanguageRow")
    }

    /// One cue: its start, its words; the selected one is the field.
    @ViewBuilder
    private func cueRow(_ placed: CaptionTimeline.Placed, index: Int) -> some View {
        let isSelected = placed.cue.id == model.selectedCaptionID
        HStack(spacing: 12) {
            Button {
                model.selectCaption(placed.cue.id, seeks: true)
            } label: {
                Text(verbatim: VideoStudioMetrics.captionTime(placed.start))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: "\(CaptionChunker.name(at: index)), \(VideoStudioMetrics.captionTime(placed.start))"))
            if isSelected {
                CaptionTextField(model: model, cue: placed.cue, isDesk: false)
                Button {
                    actions.onEditCaption(placed.cue.id)
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 32, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(VideoStudioCopy.expandTextField)
            } else {
                Button {
                    model.selectCaption(placed.cue.id)
                } label: {
                    Text(verbatim: placed.cue.text)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.08) : .clear)
        )
        .padding(.horizontal, 8)
    }

    /// Style: the four looks, Size, Bottom · Middle · Top, Burn into video.
    @ViewBuilder
    private var styleSection: some View {
        if let lane {
            if let cue = model.selectedCaption {
                HStack(spacing: 8) {
                    CaptionTextField(model: model, cue: cue, isDesk: false)
                    Button {
                        actions.onEditCaption(cue.id)
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(width: 32, height: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(VideoStudioCopy.expandTextField)
                }
                .padding(.leading, 12)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous).fill(Color.white.opacity(0.06)))
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
            Text(VideoStudioCopy.captionStyle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(EditorTheme.dimText)
                .textCase(.uppercase)
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 5)
            CaptionChipRow(items: CaptionStyle.allCases.map { ($0, VideoStudioCopy.captionStyleName($0)) }, selection: lane.style) {
                model.setCaptionStyle($0)
            }
            .padding(.horizontal, 16)
            InspectorSlider(
                label: VideoStudioCopy.captionSize, value: lane.sizePercent, range: VideoCaptionLane.sizeRange,
                valueText: "\(Int(lane.sizePercent.rounded()))%", model: model,
                set: { model.setCaptionSize($0) },
                reset: { model.pushUndo(); model.setCaptionSize(VideoCaptionLane.defaultSizePercent) }
            )
            CaptionChipRow(items: CaptionPosition.allCases.map { ($0, VideoStudioCopy.captionPositionName($0)) }, selection: lane.position, fills: true) {
                model.setCaptionPosition($0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
            burnRow(lane).padding(.horizontal, 16).padding(.top, 6)
            Label {
                Text(verbatim: VideoStudioCopy.captionsSummary(count: model.placedCaptions.count, language: CaptionLanguages.name(of: lane.language)))
            } icon: {
                Image(systemName: "checkmark")
            }
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    /// Burn into video, and — off — what that means (AC-16).
    private func burnRow(_ lane: VideoCaptionLane) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(get: { lane.burnsIn }, set: { model.setCaptionBurnsIn($0) })) {
                Label {
                    Text(VideoStudioCopy.burnIntoVideo).font(.system(size: isDesk ? 17 : 13.5))
                } icon: {
                    Image(systemName: "square.and.arrow.down").font(.system(size: isDesk ? 15 : 12))
                }
                .foregroundStyle(.white)
            }
            .tint(.green)
            .frame(height: isDesk ? 44 : 32)
            if !lane.burnsIn {
                Text(VideoStudioCopy.subtitleTrackNote)
                    .font(.system(size: isDesk ? 13 : 11.5))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("captionSubtitleTrackNote")
            }
        }
    }

    /// Language: every language the system recognises; those not on the
    /// device are dimmed and do nothing (AC-4).
    @ViewBuilder
    private var languageList: some View {
        if let lane {
            ForEach(model.captions.languageOptions) { option in
                Button {
                    guard option.isAvailable, option.id != lane.language else { return }
                    if model.editedCaptionCount > 0 {
                        isConfirmingLanguage = option.id
                    } else {
                        model.changeCaptionLanguage(option.id)
                    }
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: option.name)
                                .font(.system(size: isDesk ? 17 : 14))
                                .foregroundStyle(.white)
                            if !option.isAvailable {
                                Text(VideoStudioCopy.notOnThisDevice)
                                    .font(.system(size: isDesk ? 13 : 11.5))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        Spacer(minLength: 0)
                        if option.id == lane.language {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .opacity(option.isAvailable ? 1 : 0.35)
                    .padding(.horizontal, inset == 0 ? 0 : 16)
                    .frame(minHeight: isDesk ? 44 : 42)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(option.id == lane.language ? .isSelected : [])
                .accessibilityHint(option.isAvailable ? Text(verbatim: "") : Text(VideoStudioCopy.notOnThisDevice))
            }
        }
    }

    // MARK: The card

    @ViewBuilder
    private var card: some View {
        switch model.captionCard {
        case .running(let percent, let done, let total):
            VStack(alignment: .leading, spacing: isDesk ? 4 : 7) {
                HStack {
                    Text(VideoStudioCopy.transcribing)
                        .font(.system(size: isDesk ? 15 : 13.5, weight: .semibold))
                    Spacer(minLength: 8)
                    Text(verbatim: "\(percent)%")
                        .font(.system(size: isDesk ? 15 : 13.5, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(.white)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(Color.white).frame(width: geo.size.width * CGFloat(percent) / 100)
                    }
                }
                .frame(height: 5)
                Text(VideoStudioCopy.transcribingDetail(done: done, total: total))
                    .font(.system(size: isDesk ? 13 : 11.5))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, isDesk ? 8 : 12)
            .background(cardFill)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("captionProgressCard")
        case .stopped(let percent):
            HStack(spacing: 10) {
                Text(VideoStudioCopy.captionsStopped(at: percent))
                    .font(.system(size: isDesk ? 15 : 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Button(VideoStudioCopy.continueCaptions) { model.continueCaptions() }
                    .font(.system(size: isDesk ? 15 : 13.5, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
                    .accessibilityIdentifier("captionContinue")
            }
            .padding(12)
            .background(cardFill)
        case .denied, .restricted:
            VStack(alignment: .leading, spacing: 8) {
                Text(VideoStudioCopy.speechRecognitionOff)
                    .font(.system(size: isDesk ? 15 : 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                if model.captionCard == .denied {
                    Button(VideoStudioCopy.openSettings) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .font(.system(size: isDesk ? 15 : 13.5, weight: .semibold))
                    .accessibilityIdentifier("captionOpenSettings")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(cardFill)
            .accessibilityIdentifier("captionPermissionCard")
        case .noSpeech:
            Text(VideoStudioCopy.noSpeechFound)
                .font(.system(size: isDesk ? 15 : 13.5, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(cardFill)
                .accessibilityIdentifier("captionNoSpeech")
        case .asking, nil:
            EmptyView()
        }
    }

    private var cardFill: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous).fill(Color.white.opacity(0.06))
    }

    /// "1 clip couldn't be read — it's in iCloud." + Retry (AC-13).
    @ViewBuilder
    private var unreadableLine: some View {
        let count = model.captions.unreadableClipIDs.count
        if count > 0, !model.captions.isRunning {
            HStack(spacing: 8) {
                Text(VideoStudioCopy.clipsUnreadable(count))
                    .font(.system(size: isDesk ? 13 : 11.5))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button(VideoStudioCopy.retry) { Task { await model.retryUnreadableCaptions() } }
                    .font(.system(size: isDesk ? 15 : 13, weight: .semibold))
                    .accessibilityIdentifier("captionRetry")
            }
            .padding(.top, 6)
        }
    }

    // MARK: iPad inspector (F4_IL)

    private var inspectorBody: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                card.padding(.top, 2)
                unreadableLine
                if model.activeItemCommand == .language {
                    deskTitle(VideoStudioCopy.language)
                    languageList
                } else if lane != nil {
                    selectedCueBlock
                    deskStyleBlock
                }
            }
            .padding(.horizontal, inset)
            .padding(.bottom, 16)
        }
    }

    /// "Caption 2", its field with Expand Text Field, and its time — or the
    /// list of cues when none is selected.
    @ViewBuilder
    private var selectedCueBlock: some View {
        if let cue = model.selectedCaption, let index = model.placedCaptions.firstIndex(where: { $0.cue.id == cue.id }) {
            let placed = model.placedCaptions[index]
            deskTitle(CaptionChunker.name(at: index), top: 8, height: 22)
            HStack(spacing: 0) {
                CaptionTextField(model: model, cue: cue, isDesk: true)
                    .padding(.leading, 12)
                Button {
                    actions.onEditCaption(cue.id)
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(VideoStudioCopy.expandTextField)
            }
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous).fill(Color.white.opacity(0.08)))
            Label {
                Text(verbatim: "\(VideoStudioMetrics.captionTime(placed.start)) → \(VideoStudioMetrics.captionTime(placed.end))")
                    .font(.system(size: 15, design: .monospaced))
            } icon: {
                Image(systemName: "clock")
            }
            .foregroundStyle(.white.opacity(0.75))
            .frame(height: 32)
        } else {
            deskTitle(VideoStudioCopy.captionListTitle(model.placedCaptions.count).capitalized)
            ForEach(Array(model.placedCaptions.enumerated()), id: \.element.cue.id) { index, placed in
                cueRow(placed, index: index).padding(.horizontal, -8)
            }
        }
    }

    @ViewBuilder
    private var deskStyleBlock: some View {
        if let lane {
            deskTitle(VideoStudioCopy.captionStyle, top: 4, height: 22)
            VideoDeskSegmented(
                items: CaptionStyle.allCases.map { ($0, VideoStudioCopy.captionStyleName($0), "captionStyle.\($0.rawValue)") },
                selection: Binding(get: { lane.style }, set: { model.setCaptionStyle($0) }),
                label: Text(VideoStudioCopy.captionStyle)
            )
            DeskSliderRow(
                label: VideoStudioCopy.captionSize, value: lane.sizePercent, range: VideoCaptionLane.sizeRange,
                valueText: "\(Int(lane.sizePercent.rounded()))%", model: model,
                set: { model.setCaptionSize($0) },
                reset: { model.pushUndo(); model.setCaptionSize(VideoCaptionLane.defaultSizePercent) }
            )
            .padding(.top, 2)
            HStack(spacing: 12) {
                Text(VideoStudioCopy.captionPosition)
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                    .frame(width: 84, alignment: .leading)
                VideoDeskSegmented(
                    items: CaptionPosition.allCases.map { ($0, VideoStudioCopy.captionPositionName($0), "captionPosition.\($0.rawValue)") },
                    selection: Binding(get: { lane.position }, set: { model.setCaptionPosition($0) }),
                    label: Text(VideoStudioCopy.captionPosition)
                )
            }
            .frame(height: 36)
            burnRow(lane).padding(.top, 4)
        }
    }

    private func deskTitle(_ text: String, top: CGFloat = 8, height: CGFloat = 28) -> some View {
        Text(verbatim: text)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, top)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: iPad dock (F4_IP)

    /// Three columns of 312: the cue │ Style and Size │ Position and Burn.
    private var dockBody: some View {
        DockColumns(gap: VideoStudioDeskGeometry.dockColumnGap) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    card
                    unreadableLine
                    if model.activeItemCommand == .language { languageList } else { selectedCueBlock }
                }
            }
        } second: {
            VStack(alignment: .leading, spacing: 8) {
                if let lane {
                    deskTitle(VideoStudioCopy.captionStyle)
                    VideoDeskSegmented(
                        items: CaptionStyle.allCases.map { ($0, VideoStudioCopy.captionStyleName($0), "captionStyle.\($0.rawValue)") },
                        selection: Binding(get: { lane.style }, set: { model.setCaptionStyle($0) }),
                        label: Text(VideoStudioCopy.captionStyle)
                    )
                    DeskSliderRow(
                        label: VideoStudioCopy.captionSize, value: lane.sizePercent, range: VideoCaptionLane.sizeRange,
                        valueText: "\(Int(lane.sizePercent.rounded()))%", model: model,
                        set: { model.setCaptionSize($0) },
                        reset: { model.pushUndo(); model.setCaptionSize(VideoCaptionLane.defaultSizePercent) }
                    )
                }
                Spacer(minLength: 0)
            }
        } third: {
            VStack(alignment: .leading, spacing: 8) {
                if let lane {
                    deskTitle(VideoStudioCopy.captionPosition)
                    VideoDeskSegmented(
                        items: CaptionPosition.allCases.map { ($0, VideoStudioCopy.captionPositionName($0), "captionPosition.\($0.rawValue)") },
                        selection: Binding(get: { lane.position }, set: { model.setCaptionPosition($0) }),
                        label: Text(VideoStudioCopy.captionPosition)
                    )
                    burnRow(lane)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: VideoStudioDeskGeometry.dockParamHeight)
    }
}

/// A cue's words as a field: typing edits the cue (it loses its word
/// times); one focus, one undo step — like the text overlay's field.
struct CaptionTextField: View {
    @Bindable var model: VideoStudioModel
    let cue: CaptionCue
    let isDesk: Bool

    @FocusState private var isFocused: Bool
    @State private var draft = ""

    var body: some View {
        TextField(VideoStudioCopy.captions, text: $draft)
            .textFieldStyle(.plain)
            .font(.system(size: isDesk ? 17 : 14))
            .foregroundStyle(.white)
            .tint(EditorTheme.accent)
            .submitLabel(.done)
            .focused($isFocused)
            .task(id: cue.id) { draft = cue.text }
            .onChange(of: cue.text) { if cue.text != draft { draft = cue.text } }
            .onChange(of: draft) {
                guard draft != cue.text else { return }
                model.setCaptionText(draft, for: cue.id)
            }
            .onChange(of: isFocused) { if isFocused { model.beginUndoGroup() } else { model.endUndoGroup() } }
            .accessibilityIdentifier("captionTextField")
    }
}

/// A row of 28pt chips, one chosen — the phone's Style and Position.
struct CaptionChipRow<Value: Hashable>: View {
    let items: [(Value, String)]
    let selection: Value
    /// Chips share the row's width instead of hugging their titles.
    var fills = false
    /// 28 in the panels; 30 for the phone's COMPARE row (board F7_P).
    var height: CGFloat = 28
    let choose: (Value) -> Void

    var body: some View {
        if fills {
            HStack(spacing: 6) { chips }
        } else {
            // Wrapping, as the Duo's 264 column draws Word by Word on a
            // second line (board F4_DI).
            EditorChipFlowLayout(spacing: 6) { chips }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var chips: some View {
            ForEach(items, id: \.0) { value, title in
                let isOn = value == selection
                Button {
                    choose(value)
                } label: {
                    Text(verbatim: title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: fills ? .infinity : nil)
                        .frame(height: height)
                        .background(VideoMediaPanelMetrics.tabFill(isOn: isOn))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
    }
}
