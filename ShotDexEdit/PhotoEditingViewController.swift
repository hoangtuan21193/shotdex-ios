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
        adjustmentData.formatIdentifier == PhotoEditRecipe.formatIdentifier
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
