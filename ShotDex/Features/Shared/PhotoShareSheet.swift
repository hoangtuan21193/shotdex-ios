import Photos
import ShotDexKit
import UIKit

/// Shared multi-asset share plumbing. Gathers shareable items for a set of
/// assets (downloading from iCloud when needed) and presents a single system
/// share sheet from the top-most view controller.
enum PhotoShareSheet {
    /// What a gather produced: the files for the share sheet, the names of
    /// the items that could not be prepared, and the scratch folder the files
    /// live in until the sheet closes.
    struct Prepared {
        var items: [Any]
        var failed: [String]
        var folder: URL?

        /// Removes the gathered copies. Videos are the library's own files and
        /// are never inside the folder.
        func removeFiles() {
            if let folder { try? FileManager.default.removeItem(at: folder) }
        }
    }

    /// Resolves shareable items for the given assets, in order, one file at a
    /// time (FS-08.06 §5). Photos share their current version with the
    /// metadata `level` keeps; videos share as they are. iCloud-only assets
    /// are downloaded; an item that still fails — or a photo whose metadata
    /// cannot be removed — is named in `failed` and left out, never shared
    /// with what the level promised to remove.
    static func gather(assets: [PHAsset], level: MetadataLevel = .sharingDefault()) async -> Prepared {
        guard let folder = try? ShareExportPipeline.makeFolder() else {
            return Prepared(items: [], failed: assets.map { ShareSource(asset: $0).filename }, folder: nil)
        }
        let pipeline = ShareExportPipeline(reader: PhotoKitShareReader(), folder: folder, level: level)
        let result = await pipeline.export(assets.map(ShareSource.init(asset:)))
        return Prepared(items: result.files, failed: result.failed, folder: folder)
    }

    /// Presents the share sheet for a gather, telling the user first which
    /// items were left out. The gathered copies are removed when the sheet
    /// closes, shared or not.
    @MainActor
    static func present(_ prepared: Prepared) {
        let share = { present(items: prepared.items) { prepared.removeFiles() } }
        guard !prepared.failed.isEmpty else { return share() }
        guard let presenter = topPresenter() else { return prepared.removeFiles() }
        let names = prepared.failed.joined(separator: ", ")
        let alert = UIAlertController(
            title: String(localized: prepared.items.isEmpty ? "Unable to Share" : "Not Everything Can Be Shared"),
            message: String(localized: "These couldn't be prepared and were left out: \(names)"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { _ in share() })
        presenter.present(alert, animated: true)
    }

    /// Presents one `UIActivityViewController` for the gathered items. No-op if
    /// there's nothing to share or no foreground window.
    /// `onFinished` runs when the sheet closes, shared or not — where a
    /// caller deletes the files it handed over (FS-17.06 §6).
    @MainActor
    static func present(items: [Any], onFinished: (() -> Void)? = nil) {
        guard !items.isEmpty, let presenter = topPresenter() else { onFinished?(); return }
        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let onFinished {
            activity.completionWithItemsHandler = { _, _, _, _ in onFinished() }
        }
        // On iPad the sheet is a popover and needs an anchor, or UIKit traps.
        if let popover = activity.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        presenter.present(activity, animated: true)
    }

    /// The view controller on top of the foreground window, which is where a
    /// sheet or an alert has to be presented from.
    @MainActor
    private static func topPresenter() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              var presenter = scene.keyWindow?.rootViewController
        else { return nil }
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        return presenter
    }
}
