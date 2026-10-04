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

    var body: some View {
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
