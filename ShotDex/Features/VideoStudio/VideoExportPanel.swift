import SwiftUI

/// Export Video (FS-12.10b §2–§4): the panel the Export button opens —
/// opening it never starts an export. While ready it holds, until the
/// export presets of FS-12.16 replace it, one Custom row (the project's
/// Video Settings; a tap opens them) and one Export button; then it shows
/// the export running, saving, or what went wrong.
struct VideoExportPanel: View {
    @Bindable var model: VideoStudioModel
    /// A project of server photos (FS-17.06 §5b): the file goes to the
    /// export sheet, not to Photos.
    var server: ServerVideoStudioLaunch?
    /// Every destination of a server run has the video.
    var onServerExported: () -> Void = {}
    /// The iPad's sheet closes itself; the panels close as a tool.
    var onClose: (() -> Void)?
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.videoMediaGrid) private var window
    /// Which window this is — the grid's metrics cannot tell the phone from
    /// the Duo's cover (both are four columns edge to edge).
    @Environment(\.videoStudioWindowClass) private var windowClass
    @State private var serverExportModel: ServerExportModel?
    /// Cancel Export asks first: what has been rendered is thrown away.
    @State private var isConfirmingCancel = false
    /// When this export began, for "About N min left".
    @State private var exportStartedAt = Date()

    private var inset: CGFloat { isDuo ? 14 : 20 }

    /// The iPad: a form sheet over a scrim, not a panel (FS-12.10b §2,
    /// boards IL5_Export, IP_Export, F8_IL_ExportPresets).
    private var isSheet: Bool { onClose != nil && (window == .pool || window == .dock) }

    var body: some View {
        Group {
            if isSheet {
                sheetBody
            } else {
                panelBody
            }
        }
        .onChange(of: model.composedFile) { _, file in
            guard let file, let server else { return }
            serverExportModel = .makeComposed(
                .init(file: file, tool: .video, firstFilename: server.photos.first?.photo.primary.name ?? ""),
                photos: server.photos,
                context: server.export,
                dependencies: dependencies
            )
        }
        .onChange(of: exportFraction == nil) { _, isIdle in
            // A finished export takes its confirmation with it.
            if isIdle { isConfirmingCancel = false } else { exportStartedAt = Date() }
        }
        .confirmationDialog(
            String(localized: "Cancel Export?", comment: "Video Studio Export: title of the confirmation before stopping a running export"),
            isPresented: $isConfirmingCancel,
            titleVisibility: .visible
        ) {
            Button(VideoStudioCopy.cancelExport, role: .destructive) { model.cancelExport() }
            Button(String(localized: "Keep Exporting", comment: "Video Studio Export: closes the cancel confirmation, export continues"), role: .cancel) {}
        } message: {
            Text(String(localized: "The video rendered so far is discarded.", comment: "Video Studio Export: what cancelling a running export loses"))
        }
        .silencesVideoStudioKeys(model, while: serverExportModel != nil)
        .sheet(item: $serverExportModel, onDismiss: { model.composedFile = nil }) { exportModel in
            ServerExportSheet(model: exportModel) {
                serverExportModel = nil
                onServerExported()
            }
        }
    }

    // MARK: iPad sheet

    private typealias Sheet = VideoStudioMetrics.ExportSheet

    /// 700 wide, 620 tall while ready and 572 while exporting, 24 in: the
    /// title over the project's summary with Close at the right; the
    /// choices; then a foot under a rule — what the file will be on the
    /// left and the one way on at the right: Export (270×44). While it
    /// runs, the choices and the foot give way to the progress.
    private var sheetBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(VideoStudioCopy.exportVideo)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(height: 28)
                    Text(verbatim: VideoStudioCopy.projectSummary(
                        clips: model.recipe.clips.count,
                        ratio: model.recipe.aspect.displayName,
                        length: VideoStudioMetrics.shortDuration(model.totalDuration)
                    ))
                    .font(.system(size: 15))
                    .foregroundStyle(EditorTheme.secondaryText)
                    .frame(height: 20)
                }
                .lineLimit(1)
                .padding(.top, Sheet.titleTop)
                Spacer(minLength: 0)
                if !model.isExportBusy {
                    Button {
                        onClose?()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: Sheet.closeSize, height: Sheet.closeSize)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, Sheet.closeTop)
                    .padding(.trailing, Sheet.closeTrailing - Sheet.inset)
                    .accessibilityLabel(Text(VideoStudioCopy.close))
                }
            }
            if model.isExportBusy {
                // While it runs the export is the sheet (FS-12.10b §4): the
                // choices cannot change mid-render, so they give way to the
                // progress at the column's full width — and the write to
                // Photos after it stays in the same place, a full bar.
                sheetExporting(exportFraction)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    sheetChoices
                }
                .padding(.top, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if model.missingLUTLookCount > 0 {
                    VideoMissingLUTBanner(count: model.missingLUTLookCount)
                        .padding(.bottom, 10)
                }
                sheetFoot
            }
        }
        .padding(.horizontal, Sheet.inset)
        .frame(width: Sheet.width, height: model.isExportBusy ? Sheet.exportingHeight : Sheet.readyHeight)
        .background(EditorTheme.sheet)
    }

    /// The export's fraction while it renders; nil in every other state.
    private var exportFraction: Double? {
        if case .exporting(let progress) = model.exportState { min(max(progress, 0), 1) } else { nil }
    }

    /// The running export on the iPad (board IL5_Export, exporting state):
    /// "Exporting 62%" in `.title3` semibold, a bar the column's full width
    /// (652), one footnote line — length · codec · time left once it can be
    /// told — and Cancel Export, 240×44 and centred, which asks first.
    /// `progress` nil is the write to Photos that follows: "Saving to
    /// Photos…" over a full bar, no time left and no Cancel (the file is
    /// already made; the write is a moment).
    private func sheetExporting(_ progress: Double?) -> some View {
        let isSaving = progress == nil
        let fraction = progress ?? 1
        let percent = Int((fraction * 100).rounded(.down))
        let timeLeft = isSaving ? nil : JobProgressCard<EmptyView>.timeLeft(fraction: fraction, since: exportStartedAt)
        let detail = [
            VideoStudioMetrics.shortDuration(model.totalDuration),
            model.exportSpec.codec.displayName,
            timeLeft,
        ].compactMap { $0 }.joined(separator: " · ")
        let headline: String = if isSaving {
            VideoStudioCopy.savingToPhotos
        } else if model.isListeningForExport {
            // A bed that ducks waits for the voices first (FS-12.13 §6).
            VideoStudioCopy.listeningForVoices
        } else {
            String(localized: "Exporting \(percent)%", comment: "Video Studio Export (iPad): headline while the video renders")
        }
        return VStack(spacing: AppTheme.Spacing.md) {
            Text(headline)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                // The bar says it with its value; "Listening for voices" has
                // nothing on the bar, so that one stays readable.
                .accessibilityHidden(!model.isListeningForExport || isSaving)
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(EditorTheme.accent)
                .accessibilityLabel(Text(isSaving ? headline : VideoStudioCopy.exportingAccessibility(percent)))
            Text(verbatim: detail)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(EditorTheme.secondaryText)
            if !isSaving {
                sheetCancelButton
            }
        }
        .padding(.top, 48)
    }

    /// Cancel Export under the iPad's progress, 240×44; asks first.
    private var sheetCancelButton: some View {
        Button(role: .destructive) {
            isConfirmingCancel = true
        } label: {
            Text(VideoStudioCopy.cancelExport)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(EditorTheme.timelineDestructive)
                .frame(width: Self.sheetCancelWidth, height: AppTheme.Size.minTouch)
                .background(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(EditorTheme.timelineDestructive.opacity(0.18)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, AppTheme.Spacing.sm)
        .accessibilityIdentifier("exportCancelButton")
    }

    /// Cancel Export under the iPad's progress.
    private static let sheetCancelWidth: CGFloat = 240

    /// The choices (FS-12.16 §5, F8_IL / F8_IP): Where Is It Going — the
    /// five presets and Custom as 320×72 cards in two columns — then Your
    /// Project Is 16:9 with Fit · Fill when the ratios differ, the line of
    /// what and where, and what went wrong.
    @ViewBuilder
    private var sheetChoices: some View {
        Text(VideoStudioCopy.whereIsItGoing)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(height: 24, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
        LazyVGrid(
            columns: [GridItem(.fixed(Sheet.cardSize.width), spacing: 12), GridItem(.fixed(Sheet.cardSize.width), spacing: 12)],
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(VideoExportPreset.allCases) { preset in
                presetRow(.preset(preset), style: .card)
            }
            presetRow(.custom, style: .card)
        }
        .padding(.top, 8)
        .disabled(model.isExportBusy)
        .opacity(model.isExportBusy ? 0.4 : 1)
        if model.exportNeedsFraming {
            Text(VideoStudioCopy.yourProjectIsTitle(model.recipe.aspect.displayName))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(height: 24, alignment: .leading)
                .padding(.top, 20)
            VideoDeskSegmented(
                items: [VideoFraming.fit, .fill].map { ($0, VideoStudioCopy.exportFraming($0), "exportFraming.\($0.rawValue)") },
                selection: Binding(get: { model.exportFraming }, set: { model.setExportFraming($0) }),
                label: Text(VideoStudioCopy.yourProjectIsTitle(model.recipe.aspect.displayName))
            )
            .padding(.top, 10)
        }
        Text(VideoStudioCopy.exportInfoLine(
            length: VideoStudioMetrics.shortDuration(model.totalDuration),
            codec: model.exportSpec.codec.displayName,
            isServerRun: server != nil
        ))
            .font(.system(size: 13))
            .foregroundStyle(EditorTheme.secondaryText)
            .padding(.top, 12)
            .accessibilityIdentifier("exportDestination")
        failureLines(fontSize: 15)
    }

    @ViewBuilder
    private func failureLines(fontSize: CGFloat) -> some View {
        if case .failed(let message) = model.exportState {
            Text(message)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(EditorTheme.timelineDestructive)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
                .accessibilityIdentifier("exportError")
            if model.exportFailureOffersSettings {
                Button(VideoStudioCopy.openSettings) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(.system(size: fontSize, weight: .semibold))
                .padding(.top, 6)
            }
        }
    }

    /// How a preset row is drawn: the iPad's card, the phone's 54pt row,
    /// the Duo inner column's 45 and the cover's 43.
    enum RowStyle {
        case card, phone, duoColumn, cover

        var height: CGFloat {
            switch self {
            case .card: 72
            case .phone: 54
            case .duoColumn: 45
            case .cover: 43
            }
        }
    }

    /// One destination: its shape, name, numbers, size and — chosen — a
    /// white rule and ✓. YouTube 4K is dimmed with the 4K gate's reason;
    /// Custom opens Video Settings.
    private func presetRow(_ target: VideoExportTarget, style: RowStyle) -> some View {
        let isSelected = model.exportTarget == target
        let isCard = style == .card
        let refusal: String? = if case .preset(let preset) = target, preset.resolution == .uhd4K { model.fourKPresetRefusal } else { nil }
        let name: String
        let line: String
        let aspect: VideoAspect
        switch target {
        case .preset(let preset):
            name = preset.name
            line = refusal ?? preset.specLine
            aspect = preset.aspect
        case .custom:
            name = VideoStudioCopy.custom
            line = model.customExportLine
            aspect = model.recipe.aspect
        }
        let bytes = model.estimatedBytes(for: target)
        let compact = style == .duoColumn || style == .cover
        return Button {
            if target == .custom {
                model.chooseCustomExport()
                onClose?()
            } else {
                model.chooseExportTarget(target)
            }
        } label: {
            HStack(spacing: compact ? 8 : 12) {
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: compact ? 28 : 34, height: compact ? 28 : 34)
                    .overlay { VideoSettingsPanel.ratioGlyph(aspect, side: compact ? 14 : 18) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: name)
                        .font(.system(size: isCard ? 17 : (compact ? 12.5 : 13.5), weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(verbatim: line)
                        .font(.system(size: isCard ? 13 : (compact ? 9.5 : 10.5), design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .layoutPriority(1)
                Spacer(minLength: 4)
                if refusal == nil {
                    Text(verbatim: VideoExportEstimate.label(bytes))
                        .font(.system(size: isCard ? 15 : (compact ? 10.5 : 11.5), weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .fixedSize()
                }
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: compact ? 11 : 13, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, compact ? 8 : 12)
            .frame(maxWidth: .infinity)
            .frame(width: isCard ? Sheet.cardSize.width : nil, height: style.height)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.08 : (isCard ? 0.05 : 0)))
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .strokeBorder(Color.white, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(refusal != nil)
        .opacity(refusal == nil ? 1 : 0.28)
        .accessibilityLabel(Text(verbatim: accessibilityName(target, bytes: bytes)))
        .accessibilityHint(refusal.map { Text(verbatim: $0) } ?? Text(verbatim: ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("exportPreset.\(target.storedID)")
    }

    private func accessibilityName(_ target: VideoExportTarget, bytes: Int64) -> String {
        let megabytes = Int((Double(bytes) / 1_000_000).rounded())
        switch target {
        case .preset(let preset): return VideoStudioCopy.presetAccessibility(preset, megabytes: megabytes)
        case .custom: return "\(VideoStudioCopy.custom), \(model.customExportLine)"
        }
    }

    private var sheetFoot: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(verbatim: exportFootSummary)
                .font(.system(size: 15, design: .monospaced))
                .foregroundStyle(EditorTheme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                model.export()
            } label: {
                Text(server != nil ? Self.exportTitle(isServerRun: true) : model.exportButtonTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 8)
                    .frame(width: Sheet.exportSize.width, height: Sheet.exportSize.height)
                    .background(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous).fill(EditorTheme.accent))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.isExportBusy)
            .accessibilityIdentifier("exportStartButton")
        }
        .frame(height: Sheet.footHeight)
        .padding(.bottom, Sheet.footBottom)
        .overlay(alignment: .top) {
            Rectangle().fill(EditorTheme.hairline).frame(height: 1).padding(.horizontal, -Sheet.inset)
        }
    }

    // MARK: Panel (phone, Duo)

    private var panelBody: some View {
        VStack(spacing: 0) {
            // The cover's panel has no title row and no ✕ (board F8_DC):
            // a tool in the rail closes it, Export in the rail exports.
            if windowClass != .duoCover || model.isExportBusy {
                header
                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
            }
            VStack(alignment: .leading, spacing: 0) {
                switch model.exportState {
                case .idle, .failed:
                    ready
                case .exporting(let progress):
                    exporting(progress)
                case .saving:
                    saving
                }
            }
            .padding(.horizontal, inset)
            // The Duo's column starts its rows right under the title (F8_DI).
            .padding(.top, windowClass == .duoInner ? 1 : (windowClass == .duoCover ? 8 : 14))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(EditorTheme.panelSolid)
    }

    /// Where the video goes: Photos, or — for server photos — the export
    /// sheet of FS-17.06, which asks (FS-12.10b §5).
    static func destination(isServerRun: Bool) -> String {
        isServerRun ? VideoStudioCopy.chooseWhereItGoes : VideoStudioCopy.savedToPhotos
    }

    static func exportTitle(isServerRun: Bool) -> String {
        isServerRun ? VideoStudioCopy.exportEllipsis : VideoStudioCopy.export
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .frame(width: 24, height: 24)
                .overlay {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
            Text(VideoStudioCopy.exportVideo)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(.white)
            Text(verbatim: VideoStudioMetrics.shortDuration(model.totalDuration))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
            Spacer(minLength: 0)
            // ✕ goes while the export runs: Cancel Export is the one way out.
            if !model.isExportBusy {
                Button {
                    if let onClose { onClose() } else { model.showToolPanel(nil) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: closeSize, height: closeSize)
                        .background(Circle().fill(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(VideoStudioCopy.close))
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(height: VideoStudioMetrics.musicPanelTitleHeight)
    }

    // MARK: States

    /// The size line of the foot: "1080×1920 · 0:24 · ~30 MB".
    private var exportFootSummary: String {
        let spec = model.exportSpec
        return "\(Int(spec.size.width))×\(Int(spec.size.height)) · \(VideoStudioMetrics.shortDuration(model.totalDuration)) · \(VideoExportEstimate.label(model.estimatedExportBytes))"
    }

    private var rowStyle: RowStyle {
        switch windowClass {
        case .duoInner: .duoColumn
        case .duoCover: .cover
        default: .phone
        }
    }

    /// Ready (FS-12.16 §5, F8_P / F8_DI / F8_DC): the five presets — and
    /// Custom on the phone — then YOUR PROJECT IS 16:9 with Fit · Fill when
    /// the ratios differ; the phone's one accent, "Export for …", at the
    /// foot. The Duo has no second button: its Export exports.
    @ViewBuilder
    private var ready: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: rowStyle == .phone ? 2 : 0) {
                ForEach(VideoExportPreset.allCases) { preset in
                    presetRow(.preset(preset), style: rowStyle)
                }
                if !isDuo {
                    presetRow(.custom, style: rowStyle)
                }
                if model.exportNeedsFraming {
                    Text(VideoStudioCopy.yourProjectIs(model.recipe.aspect.displayName))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(EditorTheme.dimText)
                        .padding(.top, 10)
                        .padding(.bottom, 6)
                    CaptionChipRow(
                        items: [VideoFraming.fit, .fill].map { ($0, VideoStudioCopy.exportFraming($0)) },
                        selection: model.exportFraming,
                        fills: true
                    ) { model.setExportFraming($0) }
                }
                if windowClass == .duoCover {
                    Text(VideoStudioCopy.railExportNote)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.top, 8)
                }
                failureLines(fontSize: 12.5)
            }
            .padding(.bottom, 8)
        }
        Spacer(minLength: 8)
        // A look whose LUT is gone exports without it, and says so here
        // rather than stopping the export (FS-12.06c §6).
        if model.missingLUTLookCount > 0 {
            VideoMissingLUTBanner(count: model.missingLUTLookCount)
                .padding(.bottom, 10)
        }
        // The Duo has no second export button: a second tap on the one in
        // its bottom row or rail exports (FS-12.10b §2).
        if !isDuo {
            Button {
                model.export()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 15, weight: .semibold))
                    Text(server != nil ? Self.exportTitle(isServerRun: true) : model.exportButtonTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    Text(verbatim: VideoExportEstimate.label(model.estimatedExportBytes))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .opacity(0.7)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous).fill(EditorTheme.accent))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
            .accessibilityIdentifier("exportStartButton")
        }
    }

    /// ✕: 32, 28 in the Duo's inner column (F8_DI).
    private var closeSize: CGFloat { windowClass == .duoInner ? 28 : 32 }

    private var isDuo: Bool { windowClass == .duoInner || windowClass == .duoCover }

    private func exporting(_ progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.isListeningForExport
                ? VideoStudioCopy.listeningForVoices
                : VideoStudioCopy.exportingPercent(Int((progress * 100).rounded(.down))))
                .font(.system(size: 13.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.white)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(Color.white).frame(width: geo.size.width * CGFloat(min(max(progress, 0), 1)))
                }
            }
            .frame(height: 6)
            .accessibilityElement()
            .accessibilityLabel(Text(VideoStudioCopy.exportingAccessibility(Int((progress * 100).rounded(.down)))))
            Spacer(minLength: 12)
            Button(role: .destructive) {
                isConfirmingCancel = true
            } label: {
                Text(VideoStudioCopy.cancelExport)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(EditorTheme.timelineDestructive)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .fill(EditorTheme.timelineDestructive.opacity(0.18)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
            .accessibilityIdentifier("exportCancelButton")
        }
    }

    private var saving: some View {
        HStack(spacing: 10) {
            ProgressView().tint(.white)
            Text(VideoStudioCopy.savingToPhotos)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.top, 4)
    }
}
