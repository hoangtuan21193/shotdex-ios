import os
import Photos
import ShotDexKit
import UIKit

/// Shared multi-asset share plumbing. Library photos open the system share
/// sheet at once with lazy items and download in the Share modal once a
/// destination asks (FS-02.06 §9); server originals already on disk are
/// gathered first. One sheet, from the top-most view controller.
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

        /// RAW files in `items` that went as they are, at the user's word.
        var rawSharedAsIs = 0
        /// HEIC photos in `items` written as JPEG (No Metadata).
        var heicSentAsJPEG = 0

        var plan: ShareBatchPlan {
            ShareBatchPlan(
                level: level, photoCount: photoCount, videoCount: items.count - photoCount,
                rawSharedAsIsCount: rawSharedAsIs,
                heicAsJPEGCount: heicSentAsJPEG
            )
        }

        /// Runs once the share is over for good — not when a row reopens it.
        /// Where a caller deletes files of its own (FS-17.06 §6).
        var onClose: (@MainActor () -> Void)?

        /// Removes the gathered copies. Videos are the library's own files and
        /// are never inside the folder.
        func removeFiles() {
            if let folder { try? FileManager.default.removeItem(at: folder) }
        }

        /// The share is over: the copies go, and the caller hears about it.
        @MainActor
        func finish() {
            removeFiles()
            onClose?()
        }
    }

    /// Resolves shareable items, in order, one file at a time (FS-08.06 §5),
    /// before the sheet opens — the originals fetched from a file server
    /// (FS-17.06 §6), which are already on disk. Library photos take the lazy
    /// `share(assets:downloads:)` instead. Asks the RAW question first when
    /// the share needs it; an item that fails is named in `failed` and left
    /// out, never shared with what the level promised to remove.
    static func gather(
        sources: [ShareSource],
        reader: any ShareAssetReader,
        level: MetadataLevel,
        onClose: (@MainActor () -> Void)? = nil
    ) async -> Prepared {
        guard let folder = try? ShareExportPipeline.makeFolder() else {
            return Prepared(items: [], failed: sources.map(\.filename), folder: nil, onClose: onClose)
        }
        var pipeline = ShareExportPipeline(reader: reader, folder: folder, level: level)
        let plan = ShareBatchPlan(sources: sources, level: level)
        if plan.asksAboutRAW {
            pipeline.rawChoice = await askAboutRAW(plan)
        }
        let result = await pipeline.export(sources)
        return Prepared(
            items: result.files, failed: result.failed, unread: result.unread, folder: folder, level: level,
            regather: { await gather(sources: sources, reader: reader, level: $0, onClose: onClose) },
            rawSharedAsIs: result.rawSharedAsIs,
            heicSentAsJPEG: result.heicSentAsJPEG,
            onClose: onClose
        )
    }

    /// Shares library photos the way Photos does (FS-02.06 §9, FS-08.06 §5):
    /// the share sheet opens at once with a lazy item per photo and nothing
    /// downloaded or written; once a destination asks, the originals come
    /// down and the copies are written in the centered modal of `downloads`.
    /// The RAW question, when the share needs it, comes first.
    @MainActor
    static func share(
        assets: [PHAsset],
        downloads: OriginalDownloadModel?,
        level: MetadataLevel = .sharingDefault(),
        unreadableRAW: Set<String> = []
    ) async {
        // A RAW iOS can't decode has no JPEG to offer (FS-03.04b AC-8).
        var sources = assets.map { asset in
            var source = ShareSource(asset: asset)
            if source.kind == .raw, unreadableRAW.contains(source.id) { source.isReadable = false }
            return source
        }
        let full = ShareBatchPlan(sources: sources, level: level)
        var rawChoice = RAWChoice.skip
        if full.asksAboutRAW {
            rawChoice = await askAboutRAW(full)
        }
        // Skip leaves the RAW files out before the sheet opens, so it never
        // offers what will not come (a share of only RAW opens nothing).
        if level != .all, rawChoice == .skip { sources.removeAll { $0.kind == .raw } }
        guard !sources.isEmpty else { return }
        let byID = Dictionary(assets.map { ($0.localIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        var originals: [String: OriginalItem] = [:]
        for source in sources where source.kind != .video {
            if let asset = byID[source.id] { originals[source.id] = OriginalItem(asset: asset) }
        }
        let fetcher = downloads?.fetcher ?? PhotoKitOriginalFetcher()
        let reader = PhotoKitShareReader()
        let batch = downloads?.makeShare(
            sources: sources, originals: originals, level: level, rawChoice: rawChoice, reader: reader
        ) ?? LazyShareBatch(
            sources: sources, originals: originals, level: level, rawChoice: rawChoice,
            fetcher: fetcher, reader: reader
        )
        var plan = ShareBatchPlan(sources: sources, level: level)
        plan.rawSharedAsIsCount = rawChoice == .shareRAWWithLocation && level != .all ? plan.rawCount : 0
        plan.heicAsJPEGCount = sources.filter { source in
            source.kind == .photo && source.uniformType.map { MetadataRewriter.convertsToJPEG($0, at: level) } == true
        }.count
        let first = sources[0]
        let image = await localThumbnail(for: byID[first.id], isPhoto: first.kind != .video)
        let imageFile = image?.jpegData(compressionQuality: 0.8).flatMap { data -> URL? in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(ShareExportPipeline.prefix + "header-" + UUID().uuidString + ".jpg")
            return (try? data.write(to: url)) == nil ? nil : url
        }
        let header = ShareHeader(
            title: headerTitle(plan: plan, firstName: first.filename, count: sources.count),
            note: headerNote(plan: plan),
            imageFile: imageFile
        )
        let providers = batch.providers(header: plan.photoCount + plan.rawCount > 0 ? header : nil)
        let rows = plan.rows.map(ShareLevelRow.init(level:))
        let activity = present(items: providers, activities: rows) { chosen in
            batch.cancel()
            batch.removeFiles()
            if let imageFile { try? FileManager.default.removeItem(at: imageFile) }
            downloads?.end(batch)
            guard let chosen,
                  let again = MetadataLevel.allCases.first(where: { ShareLevelRow.activityType(for: $0) == chosen })
            else { return }
            // A level row: the same share again at that level, still lazy.
            Task { @MainActor in
                await waitForDismissal()
                await share(assets: assets, downloads: downloads, level: again, unreadableRAW: unreadableRAW)
            }
        }
        batch.onCancel = { [weak activity] in activity?.dismiss(animated: true) }
    }

    /// The header's first line: the photo's name and the level for one
    /// item, the level alone for several.
    static func headerTitle(plan: ShareBatchPlan, firstName: String, count: Int) -> String {
        let name = (firstName as NSString).deletingPathExtension
        return count == 1 ? "\(name) · \(plan.subtitle.text)" : plan.subtitle.text
    }

    /// The header's second line: what keeps its metadata, and HEIC as JPEG.
    static func headerNote(plan: ShareBatchPlan) -> String? {
        let keeps: String? = switch plan.keepsNote {
        case .videos: String(localized: "Videos keep their metadata")
        case .raw: plan.level == .noLocation
            ? String(localized: "RAW files keep their location")
            : String(localized: "RAW files keep their metadata")
        case .videosAndRAW: String(localized: "Videos and RAW files keep their metadata")
        case nil: nil
        }
        let converted = plan.notesHEICAsJPEG ? String(localized: "HEIC sent as JPEG") : nil
        let notes = [keeps, converted].compactMap { $0 }
        return notes.isEmpty ? nil : notes.joined(separator: " · ")
    }

    /// A small image already on the device, for the header — never a
    /// download: the sheet opens before anything comes from iCloud.
    @MainActor
    private static func localThumbnail(for asset: PHAsset?, isPhoto: Bool) async -> UIImage? {
        guard let asset, isPhoto else { return nil }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        let once = OSAllocatedUnfairLock(initialState: false)
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: 240, height: 240), contentMode: .aspectFill, options: options
            ) { image, _ in
                // PhotoKit may call twice; the first answer is enough.
                guard once.withLock({ let first = !$0; $0 = true; return first }) else { return }
                continuation.resume(returning: image)
            }
        }
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
        guard let presenter = topPresenter() else { return prepared.finish() }
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
            let keeps: String? = switch plan.keepsNote {
            case .videos: String(localized: "Videos keep their metadata")
            case .raw: plan.level == .noLocation
                ? String(localized: "RAW files keep their location")
                : String(localized: "RAW files keep their metadata")
            case .videosAndRAW: String(localized: "Videos and RAW files keep their metadata")
            case nil: nil
            }
            let converted = plan.notesHEICAsJPEG ? String(localized: "HEIC sent as JPEG") : nil
            let notes = [keeps, converted].compactMap { $0 }
            let note: String? = notes.isEmpty ? nil : notes.joined(separator: " · ")
            let isPhoto = prepared.folder.map { first.path.hasPrefix($0.path) } ?? false
            items[0] = ShareHeaderItem(file: first, title: title, note: note, showsImage: isPhoto)
        }
        let rows = prepared.regather == nil ? [] : plan.rows.map(ShareLevelRow.init(level:))
        present(items: items, activities: rows) { chosen in
            guard let chosen, let regather = prepared.regather,
                  let level = MetadataLevel.allCases.first(where: { ShareLevelRow.activityType(for: $0) == chosen })
            else { return prepared.finish() }
            // Reopening: this share's copies go, the caller's files stay.
            prepared.removeFiles()
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
    @discardableResult
    private static func present(
        items: [Any],
        activities: [UIActivity],
        onFinished: @escaping @MainActor (UIActivity.ActivityType?) -> Void
    ) -> UIActivityViewController? {
        guard !items.isEmpty, let presenter = topPresenter() else { onFinished(nil); return nil }
        let activity = UIActivityViewController(activityItems: items, applicationActivities: activities)
        // UIKit calls this on the main thread.
        activity.completionWithItemsHandler = { type, completed, _, _ in
            MainActor.assumeIsolated { onFinished(completed ? type : nil) }
        }
        anchor(activity, in: presenter)
        presenter.present(activity, animated: true)
        return activity
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
    static func topPresenter() -> UIViewController? {
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
