import SwiftUI

/// Export settings + progress. The export runs on the model so it survives
/// the sheet; the sheet mirrors `exportState`. Success dismisses the whole
/// studio via the model's `onSaved`.
struct VideoExportSheet: View {
    @Bindable var model: VideoStudioModel
    /// A project of server photos: the file goes to the export sheet
    /// (FS-17.06 §5b), not to Photos.
    var server: ServerVideoStudioLaunch?
    /// Every destination of a server run has the video.
    var onServerExported: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(AppDependencies.self) private var dependencies
    @State private var serverExportModel: ServerExportModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export Video")
                .font(EditorTheme.panelTitle)
                .foregroundStyle(.white)
                .padding(.top, 22)

            Picker("Quality", selection: Binding(
                get: { model.recipe.resolution },
                set: { model.recipe.resolution = $0 }
            )) {
                ForEach(VideoResolution.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isBusy)

            HStack {
                Label(
                    durationText,
                    systemImage: "clock"
                )
                .font(EditorTheme.rowLabel)
                .foregroundStyle(EditorTheme.secondaryText)
                Spacer()
            }

            switch model.exportState {
            case .idle:
                exportButton
            case .exporting(let progress):
                progressSection(progress, label: String(localized: "Exporting…"))
            case .saving:
                progressSection(nil, label: String(localized: "Saving to Photos…"))
            case .failed(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .font(EditorTheme.rowLabel)
                        .foregroundStyle(.red)
                    exportButton
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EditorTheme.panelSolid)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isBusy)
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

    private var isBusy: Bool {
        switch model.exportState {
        case .exporting, .saving: true
        default: false
        }
    }

    private var durationText: String {
        let total = Int(model.totalDuration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var exportButton: some View {
        Button {
            model.export()
        } label: {
            Label(server == nil
                  ? String(localized: "Export")
                  : String(localized: "Export…", comment: "Video of server photos: choose where the video goes"),
                  systemImage: "square.and.arrow.down")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
        }
        .buttonStyle(.borderedProminent)
        .tint(EditorTheme.accent)
    }

    @ViewBuilder
    private func progressSection(_ progress: Double?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let progress {
                ProgressView(value: progress)
                    .tint(EditorTheme.accent)
                Text("\(label) \(Int(progress * 100))%")
                    .font(EditorTheme.rowLabel)
                    .foregroundStyle(EditorTheme.secondaryText)
            } else {
                ProgressView()
                Text(label)
                    .font(EditorTheme.rowLabel)
                    .foregroundStyle(EditorTheme.secondaryText)
            }
            if progress != nil {
                Button(String(localized: "Cancel Export"), role: .destructive) {
                    model.cancelExport()
                }
                .font(EditorTheme.rowLabel)
            }
        }
    }
}
