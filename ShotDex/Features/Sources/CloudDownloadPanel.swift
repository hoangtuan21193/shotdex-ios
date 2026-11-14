import Observation
import SwiftUI

/// Opening a file that is only in the cloud (FS-19.01b §4, AC-16; boards
/// `PH40_ViewerCloudDownload` and the matching iPad, Duo and Mac boards):
/// the viewer page downloads exactly that file — progress and Cancel — and,
/// once its source has read it, turns into the photo.
@MainActor
@Observable
final class CloudDownloadModel {
    enum Phase: Equatable {
        case preparing
        case downloading(fraction: Double?)
        case cancelled
        case failed(String)
        case done
    }

    private(set) var phase: Phase = .preparing
    private(set) var file: FolderSourceRunner.CloudFile?
    @ObservationIgnored private var task: Task<Void, Never>?

    let photoId: String

    init(photoId: String) {
        self.photoId = photoId
    }

    /// Starts the download; a page that is not on screen never calls it, so
    /// paging past a cloud file downloads nothing.
    func start(runner: FolderSourceRunner, downloader: any CloudFileDownloading, onDone: @escaping @MainActor () -> Void) {
        guard task == nil else { return }
        phase = .preparing
        let photoId = photoId
        task = Task { [weak self] in
            do {
                guard let file = try await runner.cloudFile(photoId: photoId) else {
                    self?.finish(onDone)
                    return
                }
                self?.file = file
                self?.phase = .downloading(fraction: nil)
                let sink = ProgressSink(model: self)
                let outcome = try await runner.download(file, with: downloader) { fraction in
                    Task { @MainActor in sink.model?.progressed(fraction) }
                }
                switch outcome {
                case .downloaded:
                    self?.finish(onDone)
                case .unavailable:
                    self?.fail(String(localized: "The folder can't be opened right now.",
                                      comment: "Viewer: a cloud file could not be downloaded because its source folder is unavailable"))
                case .notEnoughSpace(let short):
                    self?.fail(String(localized: "Not enough space on this device. Free up \(short.formatted(.byteCount(style: .file))) and try again.",
                                      comment: "Viewer: a cloud file was not downloaded because the device is short of space; the argument is how much"))
                }
            } catch is CancellationError {
                self?.phase = .cancelled
                self?.task = nil
            } catch {
                self?.fail(String(localized: "Couldn't download this file. Check your connection and try again.",
                                  comment: "Viewer: downloading a cloud file failed"))
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    /// The downloader reports from its own thread; the model is held weakly
    /// so a page that went away is not kept alive by its download.
    private struct ProgressSink: Sendable {
        weak var model: CloudDownloadModel?
    }

    private func progressed(_ fraction: Double?) {
        guard case .downloading = phase else { return }
        phase = .downloading(fraction: fraction)
    }

    private func finish(_ onDone: @MainActor () -> Void) {
        phase = .done
        task = nil
        onDone()
    }

    private func fail(_ message: String) {
        phase = .failed(message)
        task = nil
    }

    #if DEBUG
    static var downloader: any CloudFileDownloading {
        ProcessInfo.processInfo.arguments.contains(SimulatedCloudDownloader.argument)
            ? SimulatedCloudDownloader() : UbiquitousFileDownloader()
    }
    #else
    static var downloader: any CloudFileDownloading { UbiquitousFileDownloader() }
    #endif
}

struct CloudDownloadPanel: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: CloudDownloadModel
    let filename: String?
    let isActive: Bool
    let onDownloaded: () -> Void

    init(photoId: String, filename: String?, isActive: Bool, onDownloaded: @escaping () -> Void) {
        _model = State(initialValue: CloudDownloadModel(photoId: photoId))
        self.filename = filename
        self.isActive = isActive
        self.onDownloaded = onDownloaded
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "icloud.and.arrow.down")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.6))
                .accessibilityHidden(true)
            Text(model.file?.filename ?? filename ?? "")
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
            status
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear { if isActive { start() } }
        .onChange(of: isActive) { _, active in if active { start() } }
        .onDisappear { model.cancel() }
    }

    @ViewBuilder
    private var status: some View {
        switch model.phase {
        case .preparing, .downloading:
            Text("Downloading from iCloud Drive…", comment: "Viewer: a file only in the cloud is being downloaded")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
            progress
            Button(String(localized: "Cancel", comment: "Viewer: stops downloading a cloud file")) { model.cancel() }
                .buttonStyle(.bordered)
                .tint(.white)
        case .cancelled, .failed:
            if case .failed(let message) = model.phase {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            } else {
                Text("Only in iCloud Drive", comment: "Viewer: a cloud file whose download was cancelled")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Button(String(localized: "Download", comment: "Viewer: downloads a file that is only in the cloud")) { start() }
                .buttonStyle(.bordered)
                .tint(.white)
        case .done:
            ProgressView().tint(.white)
        }
    }

    @ViewBuilder
    private var progress: some View {
        let fraction: Double? = if case .downloading(let value) = model.phase { value } else { nil }
        VStack(spacing: AppTheme.Spacing.xs) {
            if let fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView(value: nil as Double?)
                    .progressViewStyle(.linear)
            }
            if let size = model.file?.size {
                Text(sizeText(size, fraction: fraction))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: 220)
        .tint(.white)
    }

    private func sizeText(_ size: Int64, fraction: Double?) -> String {
        let total = size.formatted(.byteCount(style: .file))
        guard let fraction else { return total }
        let done = Int64(Double(size) * fraction).formatted(.byteCount(style: .file))
        return String(localized: "\(done) of \(total)", comment: "Viewer: bytes of a cloud file downloaded so far, of its size")
    }

    private func start() {
        model.start(runner: dependencies.folderSources, downloader: CloudDownloadModel.downloader) {
            Task {
                await dependencies.photoLibrary.fileThumbnails.reloadInBackground(dependencies.database)
                dependencies.sources.cloudFileDownloaded()
                onDownloaded()
            }
        }
    }
}
