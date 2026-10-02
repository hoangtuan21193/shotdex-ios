import Photos
import UIKit

/// The question Collage and Video Studio ask before taking in RAWs this iOS
/// build can't read (FS-03.04b §4): Convert to JPEG · Skip These N · Cancel.
enum UnsupportedRAWBatchPrompt {
    /// The photos to add, in order — all of them after Convert, the rest
    /// after Skip — or nil after Cancel. Asks nothing when every photo reads.
    @MainActor
    static func resolve(_ assets: [PHAsset], unreadable: Set<String>) async -> [PHAsset]? {
        let ids = assets.map(\.localIdentifier)
        guard ids.contains(where: unreadable.contains) else { return assets }
        let raws = assets.filter { unreadable.contains($0.localIdentifier) }
        let gate = UnsupportedRAWGate(
            ids: ids, unreadableSet: unreadable, smallestPreview: await EmbeddedRAWPreview.smallestSize(of: raws)
        )
        let answer = await ask(gate)
        guard let kept = gate.ids(after: answer) else { return nil }
        let byID = Dictionary(assets.map { ($0.localIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        return kept.compactMap { byID[$0] }
    }

    @MainActor
    static func ask(_ gate: UnsupportedRAWGate) async -> UnsupportedRAWGate.Answer {
        guard let presenter = PhotoShareSheet.topPresenter() else { return .cancel }
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: gate.title, message: gate.message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: gate.convertTitle, style: .default) { _ in
                continuation.resume(returning: .convertToJPEG)
            })
            alert.addAction(UIAlertAction(title: gate.skipTitle, style: .default) { _ in
                continuation.resume(returning: .skip)
            })
            alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel) { _ in
                continuation.resume(returning: .cancel)
            })
            presenter.present(alert, animated: true)
        }
    }
}
