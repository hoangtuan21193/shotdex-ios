import Photos
import ShotDexKit
import UIKit

/// *Edit which version?* for a RAW + JPEG pair (FS-03.04b §3). UIKit, because
/// a SwiftUI confirmation dialog cannot show a dimmed row, and Edit RAW of a
/// RAW iOS can't read is shown dimmed with the reason rather than left out.
enum EditSourcePrompt {
    /// The photo's own files: `.photo` and `.alternatePhoto` only — an edit's
    /// rendering (`.fullSizePhoto`) does not make a RAW a pair.
    @MainActor
    static func resources(of asset: PHAsset) -> [EditSourceChoice.Resource] {
        PHAssetResource.assetResources(for: asset)
            .filter { $0.type == .photo || $0.type == .alternatePhoto }
            .map { SystemRAWDecoderProbe.isRAW($0) ? .raw : .rendered }
    }

    /// The source chosen, or nil for Cancel.
    @MainActor
    static func ask(_ choice: EditSourceChoice) async -> PhotoEditSource? {
        guard let presenter = PhotoShareSheet.topPresenter() else { return nil }
        return await withCheckedContinuation { continuation in
            let sheet = UIAlertController(title: choice.title, message: choice.rawReason, preferredStyle: .actionSheet)
            let raw = UIAlertAction(title: String(localized: "Edit RAW", comment: "Action sheet: open the RAW of a pair"), style: .default) { _ in
                continuation.resume(returning: .raw)
            }
            raw.isEnabled = choice.offersRAW
            sheet.addAction(raw)
            sheet.addAction(UIAlertAction(title: String(localized: "Edit JPEG", comment: "Action sheet: open the JPEG of a pair"), style: .default) { _ in
                continuation.resume(returning: .rendered)
            })
            sheet.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel) { _ in
                continuation.resume(returning: nil)
            })
            // iPad: a popover over the viewer's action bar, where Edit is.
            if let popover = sheet.popoverPresentationController {
                let bounds = presenter.view.bounds
                popover.sourceView = presenter.view
                popover.sourceRect = CGRect(
                    x: bounds.midX, y: bounds.maxY - presenter.view.safeAreaInsets.bottom - 44, width: 1, height: 1
                )
                popover.permittedArrowDirections = .down
            }
            presenter.present(sheet, animated: true)
        }
    }
}
