import Photos
import SwiftUI

/// Media (FS-12.09): the photo library inside the studio's own panel — the
/// phone's panel, the iPad dock, the Duo's column and cover panel, the iPad
/// pool's Media tab. A tap inserts at the playhead; the system picker is not
/// used here at all (§2).
struct VideoMediaPanel: View {
    @Bindable var model: VideoStudioModel
    @Environment(\.videoMediaGrid) private var metrics
    @Environment(AppDependencies.self) private var dependencies
    @State private var library: VideoMediaLibrary?

    var body: some View {
        VStack(spacing: 0) {
            if let library {
                VideoMediaGridView(
                    library: library,
                    revision: library.revision,
                    metrics: metrics,
                    uses: MediaUsage.uses(in: model.recipe),
                    onTap: { insert($0) }
                )
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: model.photoLibrary.assetChangeToken) {
            let library = library ?? VideoMediaLibrary(photoLibrary: model.photoLibrary)
            library.reload()
            self.library = library
        }
    }

    /// A tap: in at the playhead. A RAW this iOS cannot read asks the
    /// question it asks at the door first (FS-03.04b AC-18).
    private func insert(_ asset: PHAsset) {
        let pick = VideoMediaPick(assetID: asset.localIdentifier, kind: asset.mediaType == .video ? .video : .photo)
        let unreadable = dependencies.unsupportedRAWIndex.assetIds
        guard unreadable.contains(pick.assetID) else {
            model.insertMedia([pick])
            return
        }
        Task { @MainActor in
            guard let kept = await UnsupportedRAWBatchPrompt.resolve([asset], unreadable: unreadable),
                  !kept.isEmpty
            else { return }
            model.insertMedia([pick])
        }
    }
}

private struct VideoMediaGridKey: EnvironmentKey {
    static let defaultValue = VideoMediaGridMetrics.phone
}

extension EnvironmentValues {
    /// The Media grid's shape for the window the studio is drawn in
    /// (FS-12.09 §3). Each layout sets its own.
    var videoMediaGrid: VideoMediaGridMetrics {
        get { self[VideoMediaGridKey.self] }
        set { self[VideoMediaGridKey.self] = newValue }
    }
}
