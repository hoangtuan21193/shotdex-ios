import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Receives images shared from other apps and saves them to the photo library,
/// so ShotDex can index them like anything else the user shot.
///
/// A plain view controller rather than `SLComposeServiceViewController`: there
/// is nothing to compose. The sheet states what will happen, does it, and
/// closes.
final class ShareViewController: UIViewController {
    private var hosting: UIHostingController<ShareSheetView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareImportModel(
            extensionContext: extensionContext,
            attachments: attachments()
        )
        let hosting = UIHostingController(rootView: ShareSheetView(model: model))
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        self.hosting = hosting
    }

    /// Every image attachment across every extension item — a share can carry
    /// several items, each with several representations.
    private func attachments() -> [NSItemProvider] {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        return items
            .flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
    }
}

/// Saving state for the share sheet.
@MainActor
@Observable
final class ShareImportModel {
    enum Phase: Equatable {
        case ready(count: Int)
        case saving(done: Int, total: Int)
        case finished(saved: Int, failed: Int)
        case nothingToSave
        case denied
    }

    private(set) var phase: Phase
    private let extensionContext: NSExtensionContext?
    private let attachments: [NSItemProvider]

    init(extensionContext: NSExtensionContext?, attachments: [NSItemProvider]) {
        self.extensionContext = extensionContext
        self.attachments = attachments
        phase = attachments.isEmpty ? .nothingToSave : .ready(count: attachments.count)
    }

    func save() async {
        guard !attachments.isEmpty else { return }
        // Add-only is all this needs, and it is the least the user can grant.
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            phase = .denied
            return
        }

        var saved = 0
        var failed = 0
        for (index, provider) in attachments.enumerated() {
            phase = .saving(done: index, total: attachments.count)
            if await save(provider) { saved += 1 } else { failed += 1 }
        }
        phase = .finished(saved: saved, failed: failed)
    }

    func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func save(_ provider: NSItemProvider) async -> Bool {
        guard let url = await loadFileURL(from: provider) else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = url.lastPathComponent
                // The provider owns the file it handed over; copy, never move.
                options.shouldMoveFile = false
                request.addResource(with: .photo, fileURL: url, options: options)
            }
            return true
        } catch {
            return false
        }
    }

    /// Resolves an attachment to a file on disk. `loadFileRepresentation`
    /// deletes its temporary file as soon as the completion returns, so the
    /// bytes are copied somewhere this process owns first.
    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(
                forTypeIdentifier: UTType.image.identifier
            ) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent("shotdex-share-\(UUID().uuidString)-\(url.lastPathComponent)")
                do {
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

struct ShareSheetView: View {
    @Bindable var model: ShareImportModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if case .saving = model.phase {
                    ProgressView()
                }
                Spacer()
                actionButton
            }
            .padding(24)
            .navigationTitle("ShotDex")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.close() }
                }
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch model.phase {
        case .ready:
            Button {
                Task { await model.save() }
            } label: {
                Text("Save to Photos").frame(maxWidth: .infinity).frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
        case .finished, .nothingToSave, .denied:
            Button {
                model.close()
            } label: {
                Text("Done").frame(maxWidth: .infinity).frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
        case .saving:
            EmptyView()
        }
    }

    private var icon: String {
        switch model.phase {
        case .denied: "lock"
        case .nothingToSave: "photo.badge.exclamationmark"
        case .finished(_, let failed) where failed > 0: "exclamationmark.triangle"
        case .finished: "checkmark.circle"
        default: "square.and.arrow.down"
        }
    }

    private var title: String {
        switch model.phase {
        case .ready(let count):
            count == 1 ? "Save 1 photo to your library?" : "Save \(count) photos to your library?"
        case .saving(let done, let total):
            "Saving \(done + 1) of \(total)…"
        case .finished(let saved, let failed):
            failed == 0
                ? (saved == 1 ? "1 photo saved" : "\(saved) photos saved")
                : "\(saved) saved, \(failed) couldn't be read"
        case .nothingToSave:
            "Nothing here to save"
        case .denied:
            "ShotDex needs permission to add photos"
        }
    }

    private var detail: String? {
        switch model.phase {
        case .ready:
            "They join your library, and ShotDex indexes their metadata the next time you open it."
        case .nothingToSave:
            "This share carried no images."
        case .denied:
            "Allow adding photos in Settings, then try again."
        default:
            nil
        }
    }
}
