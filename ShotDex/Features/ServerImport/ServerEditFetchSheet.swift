import SwiftUI

/// The originals coming down before Edit, Share, Copy, Paste Edits or Resize
/// can run (FS-17.06 §4). Tier A — the same progress block as Import.
struct ServerEditFetchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let model: ServerEditFetchModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(String(localized: "Downloading", comment: "Server photo command: originals coming down, sheet title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if model.stage == .downloading {
                            Button("Cancel") { model.cancel() }
                        } else {
                            Button("Done") { dismiss() }
                        }
                    }
                }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(model.stage == .downloading)
        .task { model.start() }
        // Leaving the app stops the download, as Import does.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, model.stage == .downloading { model.cancel() }
        }
        .onChange(of: model.stage) { _, stage in
            if stage == .fetched || stage == .cancelled { dismiss() }
        }
        .onDisappear { if model.stage == .downloading { model.cancel() } }
    }

    @ViewBuilder
    private var content: some View {
        switch model.stage {
        case .failed(let message):
            ContentUnavailableView {
                Label(String(localized: "Couldn't Download", comment: "Server photo command: fetch failed, title"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
        default:
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Downloading \(model.progress.index + 1) of \(model.photos.count)", comment: "Server photo command: fetch progress headline")
                            .font(.headline)
                        ProgressView(value: model.progress.fraction)
                            .accessibilityLabel(String(localized: "Download progress", comment: "Server photo command: progress bar, VoiceOver"))
                            .accessibilityValue(Text(model.progress.fraction, format: .percent.precision(.fractionLength(0))))
                        Text(byteLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 6)
                    if !model.progress.filename.isEmpty {
                        Text(model.progress.filename)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } footer: {
                    Text("The originals stay on the server. Keep ShotDex open until the download finishes.", comment: "Server photo command: fetch sheet footer")
                }
            }
        }
    }

    private var byteLine: String {
        let done = ByteCountFormatter.string(fromByteCount: model.progress.bytesDone, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: model.totalBytes, countStyle: .file)
        return String(localized: "\(done) of \(total)", comment: "Download from server: bytes received of total")
    }
}
