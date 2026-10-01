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
        /// The part of `failed` that never arrived from the library.
        var unread: [String] = []
        var folder: URL?
        /// The metadata level the photos were prepared at.
        var level: MetadataLevel = .all
        /// Prepares the same share again at another level, for the share
        /// sheet's one-shot rows. `nil` where a share offers no rows.
        var regather: (@MainActor (MetadataLevel) async -> Prepared)?

        /// Photos are the files gathered into the folder; anything else is a
        /// video the library handed over as it is.
        var photoCount: Int {
            guard let folder else { return 0 }
            return items.compactMap { $0 as? URL }.filter { $0.path.hasPrefix(folder.path) }.count
        }

        var plan: ShareBatchPlan {
            ShareBatchPlan(level: level, photoCount: photoCount, videoCount: items.count - photoCount)
        }

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
    static func gather(
        assets: [PHAsset],
        level: MetadataLevel = .sharingDefault(),
        allowsNetworkAccess: Bool = true
    ) async -> Prepared {
        guard let folder = try? ShareExportPipeline.makeFolder() else {
            return Prepared(items: [], failed: assets.map { ShareSource(asset: $0).filename }, folder: nil)
        }
        let sources = assets.map(ShareSource.init(asset:))
        var pipeline = ShareExportPipeline(
            reader: PhotoKitShareReader(allowsNetworkAccess: allowsNetworkAccess),
            folder: folder,
            level: level
        )
        let plan = ShareBatchPlan(sources: sources, level: level)
        if plan.asksAboutRAW {
            pipeline.rawChoice = await askAboutRAW(plan)
        }
        let result = await pipeline.export(sources)
        return Prepared(
            items: result.files, failed: result.failed, unread: result.unread, folder: folder, level: level,
            regather: { await gather(assets: assets, level: $0, allowsNetworkAccess: allowsNetworkAccess) }
        )
    }

    /// Asks, once for the whole share, what to do with RAW files whose
    /// metadata cannot be removed (FS-08.06 §5). Skip leaves them out; a
    /// share of only RAW files then opens no share sheet at all.
    @MainActor
    static func askAboutRAW(_ plan: ShareBatchPlan) async -> RAWChoice {
        guard let presenter = topPresenter() else { return .skip }
        let question = plan.rawQuestion
        let title: String = switch (question.count, question.removes) {
        case (1, .location): String(localized: "This RAW file can't have its location removed")
        case (1, .metadata): String(localized: "This RAW file can't have its metadata removed")
        case (_, .location): String(localized: "\(question.count) RAW files can't have their location removed")
        case (_, .metadata): String(localized: "\(question.count) RAW files can't have their metadata removed")
        }
        let message = plan.offersJPEG ? nil : String(localized: "iOS can't read this RAW yet, so it can't be shared as a JPEG.")
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            let jpeg = UIAlertAction(title: String(localized: "Share as JPEG"), style: .default) { _ in
                continuation.resume(returning: .shareAsJPEG)
            }
            jpeg.isEnabled = plan.offersJPEG
            alert.addAction(jpeg)
            alert.addAction(UIAlertAction(title: String(localized: "Share RAW with Location"), style: .default) { _ in
                continuation.resume(returning: .shareRAWWithLocation)
            })
            alert.addAction(UIAlertAction(title: String(localized: "Skip"), style: .cancel) { _ in
                continuation.resume(returning: .skip)
            })
            presenter.present(alert, animated: true)
        }
    }

    /// Presents the share sheet for a gather, telling the user first which
    /// items were left out. The gathered copies are removed when the sheet
    /// closes, shared or not.
    @MainActor
    static func present(_ prepared: Prepared) {
        let share = { presentSheet(for: prepared) }
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
        anchor(activity, in: presenter)
        presenter.present(activity, animated: true)
    }

    /// The share sheet for a photo share: a header naming the level in
    /// force, and the app's rows for the other two (FS-08.06 §4). Choosing a
    /// row closes the sheet, prepares the share again at that level and
    /// opens it again; Settings is not touched.
    @MainActor
    private static func presentSheet(for prepared: Prepared) {
        let plan = prepared.plan
        var items = prepared.items
        if plan.photoCount > 0, let first = items.first as? URL {
            let name = first.deletingPathExtension().lastPathComponent
            let title = items.count == 1 ? "\(name) · \(plan.subtitle.text)" : plan.subtitle.text
            // One line each: the level on the title, the video note on the
            // line below it, where the file name would be.
            let note = plan.notesVideosKeepMetadata ? String(localized: "Videos keep their metadata") : nil
            let isPhoto = prepared.folder.map { first.path.hasPrefix($0.path) } ?? false
            items[0] = ShareHeaderItem(file: first, title: title, note: note, showsImage: isPhoto)
        }
        let rows = prepared.regather == nil ? [] : plan.rows.map(ShareLevelRow.init(level:))
        present(items: items, activities: rows) { chosen in
            prepared.removeFiles()
            guard let chosen, let regather = prepared.regather,
                  let level = MetadataLevel.allCases.first(where: { ShareLevelRow.activityType(for: $0) == chosen })
            else { return }
            Task { @MainActor in
                let again = await regather(level)
                await waitForDismissal()
                present(again)
            }
        }
    }

    /// Waits, briefly, for the share sheet that just closed to finish leaving
    /// the screen: UIKit will not present over a controller on its way out.
    @MainActor
    private static func waitForDismissal() async {
        for _ in 0..<20 {
            guard let top = topPresenter(), top is UIActivityViewController || top.isBeingDismissed else { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Presents a `UIActivityViewController` with the app's own rows.
    /// `onFinished` gets the chosen activity's type — `nil` when the sheet
    /// was dismissed — once the sheet closes.
    @MainActor
    private static func present(
        items: [Any],
        activities: [UIActivity],
        onFinished: @escaping (UIActivity.ActivityType?) -> Void
    ) {
        guard !items.isEmpty, let presenter = topPresenter() else { onFinished(nil); return }
        let activity = UIActivityViewController(activityItems: items, applicationActivities: activities)
        activity.completionWithItemsHandler = { type, completed, _, _ in onFinished(completed ? type : nil) }
        anchor(activity, in: presenter)
        presenter.present(activity, animated: true)
    }

    /// On iPad the sheet is a popover and needs an anchor, or UIKit traps.
    @MainActor
    private static func anchor(_ activity: UIActivityViewController, in presenter: UIViewController) {
        if let popover = activity.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
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
