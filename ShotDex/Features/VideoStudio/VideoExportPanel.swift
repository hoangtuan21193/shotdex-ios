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
    @State private var serverExportModel: ServerExportModel?

    private var inset: CGFloat { window == .cover ? 14 : 20 }

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
    /// left and the one way on at the right: Export (270×44), or while it
    /// runs the progress (360×6) and Cancel Export (180×44).
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
            VStack(alignment: .leading, spacing: 0) {
                switch model.exportState {
                case .idle, .failed, .exporting:
                    sheetChoices
                case .saving:
                    saving
                }
            }
            .padding(.top, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if model.missingLUTLookCount > 0 {
                VideoMissingLUTBanner(count: model.missingLUTLookCount)
                    .padding(.bottom, 10)
            }
            sheetFoot
        }
        .padding(.horizontal, Sheet.inset)
        .frame(width: Sheet.width, height: model.isExportBusy ? Sheet.exportingHeight : Sheet.readyHeight)
        .background(EditorTheme.sheet)
    }

    /// The choices: the project's own settings as the one row until the
    /// export presets land (FS-12.16), where it goes, and what went wrong.
    @ViewBuilder
    private var sheetChoices: some View {
        Button {
            model.openVideoSettingsFromExport()
            onClose?()
        } label: {
            HStack(spacing: 12) {
                VideoSettingsPanel.ratioGlyph(model.recipe.aspect, side: 20)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(VideoStudioCopy.custom)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(verbatim: model.exportSpecSummary)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(EditorTheme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.horizontal, 14)
            .frame(width: Sheet.cardSize.width, height: Sheet.cardSize.height)
            .background(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous).fill(Color.white.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isExportBusy)
        .opacity(model.isExportBusy ? 0.4 : 1)
        .accessibilityIdentifier("exportCustomRow")
        Text(Self.destination(isServerRun: server != nil))
            .font(.system(size: 13))
            .foregroundStyle(EditorTheme.secondaryText)
            .padding(.top, 12)
            .accessibilityIdentifier("exportDestination")
        if case .failed(let message) = model.exportState {
            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(EditorTheme.timelineDestructive)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
                .accessibilityIdentifier("exportError")
            if model.exportFailureOffersSettings {
                Button(VideoStudioCopy.openSettings) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 6)
            }
        }
    }

    private var sheetFoot: some View {
        HStack(alignment: .center, spacing: 16) {
            if case .exporting(let progress) = model.exportState {
                let percent = Int((progress * 100).rounded(.down))
                VStack(alignment: .leading, spacing: 8) {
                    Text(VideoStudioCopy.exportingPercent(percent))
                        .font(.system(size: 17, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(Color.white).frame(width: Sheet.progressWidth * CGFloat(min(max(progress, 0), 1)))
                    }
                    .frame(width: Sheet.progressWidth, height: 6)
                    .accessibilityElement()
                    .accessibilityLabel(Text(VideoStudioCopy.exportingAccessibility(percent)))
                }
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    model.cancelExport()
                } label: {
                    Text(VideoStudioCopy.cancelExport)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(EditorTheme.timelineDestructive)
                        .frame(width: Sheet.cancelSize.width, height: Sheet.cancelSize.height)
                        .background(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                            .fill(EditorTheme.timelineDestructive.opacity(0.18)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("exportCancelButton")
            } else {
                Text(verbatim: model.outputSummary(includesLength: true))
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(EditorTheme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    model.export()
                } label: {
                    Text(Self.exportTitle(isServerRun: server != nil))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: Sheet.exportSize.width, height: Sheet.exportSize.height)
                        .background(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous).fill(EditorTheme.accent))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.isExportBusy)
                .accessibilityIdentifier("exportStartButton")
            }
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
            header
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
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
            .padding(.top, 14)
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
            Spacer(minLength: 0)
            // ✕ goes while the export runs: Cancel Export is the one way out.
            if !model.isExportBusy {
                Button {
                    if let onClose { onClose() } else { model.showToolPanel(nil) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
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

    @ViewBuilder
    private var ready: some View {
        Button {
            model.openVideoSettingsFromExport()
            onClose?()
        } label: {
            HStack(spacing: 12) {
                VideoSettingsPanel.ratioGlyph(model.recipe.aspect, side: 18)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(VideoStudioCopy.custom)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(verbatim: model.exportSpecSummary)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Text(verbatim: VideoExportEstimate.label(model.estimatedExportBytes))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
            .background(VideoMediaPanelMetrics.tabFill(isOn: false))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("exportCustomRow")
        Text(Self.destination(isServerRun: server != nil))
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.45))
            .padding(.top, 10)
            .accessibilityIdentifier("exportDestination")
        if case .failed(let message) = model.exportState {
            Text(message)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(EditorTheme.timelineDestructive)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
                .accessibilityIdentifier("exportError")
            if model.exportFailureOffersSettings {
                Button(VideoStudioCopy.openSettings) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(.system(size: 12.5, weight: .semibold))
                .padding(.top, 6)
            }
        }
        Spacer(minLength: 12)
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
                Text(Self.exportTitle(isServerRun: server != nil))
                    .font(.system(size: 16, weight: .semibold))
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

    private var isDuo: Bool { window == .duoColumn || window == .cover }

    private func exporting(_ progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(VideoStudioCopy.exportingPercent(Int((progress * 100).rounded(.down))))
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
                model.cancelExport()
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
