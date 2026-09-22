import Photos
import UIKit
import UniformTypeIdentifiers

/// "Edit in ShotDex" in the share sheet's action row.
///
/// It edits nothing. Its whole job is to work out **which photo in the library**
/// the user is looking at and hand that identifier to the app, which has the
/// full editor, the render pipeline and no extension memory ceiling. The
/// in-place photo-editing extension this replaces had the identifier for free
/// and a four-slider editor to use it with; this has the whole editor and has to
/// find the identifier.
final class ActionViewController: UIViewController {
    /// How the extension reports back. Kept separate from the view so the
    /// resolution logic reads as a sequence of attempts rather than UI code.
    private enum Outcome {
        case opened
        case notFound
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        Task { await run() }
    }

    private func run() async {
        guard let provider = firstImageProvider() else {
            finish(.notFound)
            return
        }
        let identifier = await resolveAssetIdentifier(from: provider)
        guard let identifier else {
            finish(.notFound)
            return
        }
        open(assetIdentifier: identifier)
    }

    private func firstImageProvider() -> NSItemProvider? {
        for item in extensionContext?.inputItems.compactMap({ $0 as? NSExtensionItem }) ?? [] {
            for provider in item.attachments ?? [] where provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                return provider
            }
        }
        return nil
    }

    /// Photos hands an extension a *file*, not a library identifier, so the
    /// identifier has to be found again: match the original filename the asset's
    /// resource carries. Filenames repeat across a library often enough that the
    /// creation date breaks the tie.
    private func resolveAssetIdentifier(from provider: NSItemProvider) async -> String? {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else { return nil }
        guard let url = await loadFileURL(from: provider) else { return nil }
        let filename = url.lastPathComponent

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(with: .image, options: options)

        var match: String?
        assets.enumerateObjects { asset, _, stop in
            let resources = PHAssetResource.assetResources(for: asset)
            if resources.contains(where: { $0.originalFilename == filename }) {
                match = asset.localIdentifier
                stop.pointee = true
            }
        }
        return match
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    /// The same deep link the widget uses — one route into the editor, not two.
    private func open(assetIdentifier: String) {
        var components = URLComponents()
        components.scheme = "shotdex"
        components.host = "photo"
        components.queryItems = [
            URLQueryItem(name: "id", value: assetIdentifier),
            URLQueryItem(name: "edit", value: "1"),
        ]
        guard let url = components.url else {
            finish(.notFound)
            return
        }
        extensionContext?.open(url) { [weak self] opened in
            self?.finish(opened ? .opened : .notFound)
        }
    }

    private func finish(_ outcome: Outcome) {
        switch outcome {
        case .opened:
            extensionContext?.completeRequest(returningItems: nil)
        case .notFound:
            // Never a silent nothing: the one thing worse than "we could not
            // find this photo in your library" is a sheet that closes and
            // leaves the person wondering whether anything happened.
            let alert = UIAlertController(
                title: "Can't open this photo",
                message: "ShotDex edits photos in your library. Open it from the ShotDex app instead.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                self?.extensionContext?.completeRequest(returningItems: nil)
            })
            present(alert, animated: true)
        }
    }
}
