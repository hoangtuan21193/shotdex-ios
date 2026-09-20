import Photos
import PhotosUI
import ShotDexKit
import SwiftUI
import UIKit

/// ShotDex's looks, inside the Photos app.
///
/// Photos hands the extension the photo and takes back a rendered result plus
/// **adjustment data**. The adjustment data here is a `PhotoEditRecipe` under
/// ShotDex's own format identifier, which is what makes the round trip work:
/// re-opening this photo in this extension restores the sliders, and opening it
/// in ShotDex proper shows the same edit in the full editor.
///
/// Deliberately a small subset of that editor — the film looks, their strength,
/// and the four tone controls people reach for first. A photo editing extension
/// runs in a memory-tight process next to Photos, and porting the whole editor
/// into it would be a second app to maintain, not a shortcut.
final class PhotoEditingViewController: UIViewController, PHContentEditingController {
    private var input: PHContentEditingInput?
    private let model = EditExtensionModel()
    private var host: UIHostingController<EditExtensionView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: EditExtensionView(model: model))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        self.host = host
    }

    // MARK: PHContentEditingController

    /// Whether an edit already on the photo can be continued rather than
    /// discarded. Only ShotDex's own recipes can: another app's adjustment data
    /// says nothing this extension can read, and claiming otherwise would throw
    /// that app's edit away on save.
    func canHandle(_ adjustmentData: PHAdjustmentData) -> Bool {
        guard adjustmentData.formatIdentifier == PhotoEditRecipe.formatIdentifier else { return false }
        // Ours, but not necessarily ours to *finish*. A recipe with a mask, a
        // drawing or a text overlay rasterizes a bitmap the size of the whole
        // image for each one — ~195MB of RGBA at 48MP for a single layer,
        // before the source is even decoded. An extension has a fraction of
        // an app's memory, so continuing that edit here would be a kill
        // rather than a save, and a kill loses the user's work.
        //
        // Saying no means Photos offers "Revert" instead of "Edit in
        // ShotDex", and the photo opens in the full app with the edit intact.
        // That is the honest answer: this surface is four sliders and a film
        // look, and it should only claim the edits it can actually render.
        guard let recipe = try? JSONDecoder().decode(PhotoEditRecipe.self, from: adjustmentData.data) else {
            return false
        }
        return !recipe.needsFullExtentLayers
    }

    func startContentEditing(with contentEditingInput: PHContentEditingInput, placeholderImage: UIImage) {
        input = contentEditingInput
        model.begin(with: contentEditingInput, placeholder: placeholderImage)
    }

    func finishContentEditing(completionHandler: @escaping ((PHContentEditingOutput?) -> Void)) {
        guard let input else {
            completionHandler(nil)
            return
        }
        // Off the main thread, as Photos requires: this renders the photo at
        // full size and writes it out.
        Task.detached(priority: .userInitiated) { [model] in
            let output = await model.renderOutput(for: input)
            completionHandler(output)
        }
    }

    /// Photos asks before discarding; the answer is yes, because everything
    /// this extension holds is one recipe that costs nothing to rebuild.
    var shouldShowCancelConfirmation: Bool { false }

    func cancelContentEditing() {}
}
