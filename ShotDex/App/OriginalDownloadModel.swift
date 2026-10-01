import SwiftUI
import ShotDexKit
import UIKit

/// The app-level owner of the Share modal: one for every way into Share —
/// viewer, grid, selection, tile menu, albums (FS-02.06 §9). It hosts the
/// modal in a window of its own above the share sheet, shown only while the
/// running share wants it, so it never takes a touch otherwise.
@MainActor
@Observable
final class OriginalDownloadModel {
    let fetcher: any OriginalFetching
    let gate: IndexInteractionGate?
    let availableBytes: @Sendable () -> Int64?
    private(set) var activeShare: LazyShareBatch?
    @ObservationIgnored private var window: UIWindow?

    init(
        fetcher: any OriginalFetching,
        gate: IndexInteractionGate?,
        availableBytes: @escaping @Sendable () -> Int64? = { DiskSpace.availableBytes() }
    ) {
        self.fetcher = fetcher
        self.gate = gate
        self.availableBytes = availableBytes
    }

    func makeShare(
        sources: [ShareSource], originals: [String: OriginalItem], level: MetadataLevel,
        rawChoice: RAWChoice, reader: any ShareAssetReader
    ) -> LazyShareBatch {
        let batch = LazyShareBatch(
            sources: sources, originals: originals, level: level, rawChoice: rawChoice,
            fetcher: fetcher, gate: gate, availableBytes: availableBytes, reader: reader
        )
        activeShare = batch
        track(batch)
        return batch
    }

    /// The share sheet closed: that share's modal is gone for good.
    func end(_ batch: LazyShareBatch) {
        guard activeShare === batch else { return }
        activeShare = nil
        sync()
    }

    private func track(_ batch: LazyShareBatch) {
        withObservationTracking {
            _ = batch.isShown
        } onChange: { [weak self, weak batch] in
            Task { @MainActor in
                guard let self, let batch, self.activeShare === batch else { return }
                self.sync()
                self.track(batch)
            }
        }
    }

    private func sync() {
        guard let batch = activeShare, batch.isShown else {
            window?.isHidden = true
            window = nil
            return
        }
        guard window == nil else { return }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        let host = UIHostingController(rootView: OriginalDownloadModal(batch: batch))
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.backgroundColor = .clear
        window.isHidden = false
        self.window = window
    }
}
