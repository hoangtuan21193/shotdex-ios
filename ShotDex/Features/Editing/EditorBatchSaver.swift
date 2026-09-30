import CoreImage
import Photos
import ShotDexKit
import SwiftUI

/// Writes a whole multi-photo run to Photos in one go.
///
/// Deliberately headless: it drives `PhotoEditingService` directly rather than
/// standing up a `PhotoEditorController` per photo. The controller exists to
/// keep an interactive preview alive — a render ladder, a histogram, mask
/// thumbnails — and forty of those in a loop would spend most of the run drawing
/// pictures nobody looks at. The service's own session is all a save needs:
/// `beginSession` → `loadSource` → `saveChanges`/`saveCopy` → `endSession`.
///
/// One photo failing never stops the run. An unsupported RAW at frame 7 must not
/// cost frames 8 through 40, so failures are collected and reported at the end,
/// and those photos keep their drafts so the user can retry them.
@MainActor
@Observable
final class EditorBatchSaver {
    struct Failure: Identifiable {
        let id: String
        let filename: String
        let message: String
    }

    private(set) var isRunning = false
    private(set) var completed = 0
    private(set) var total = 0
    private(set) var failures: [Failure] = []
    /// Set when the run is over and something went wrong; the caller shows it and
    /// clears it.
    private(set) var hasFinishedWithFailures = false
    /// Set while a cancelled run finishes the photo it was mid-write on.
    private(set) var isCancelling = false

    private var task: Task<Void, Never>?

    var progressFraction: Double {
        total > 0 ? Double(completed) / Double(total) : 0
    }

    func run(
        items: [(asset: PHAsset, recipe: PhotoEditRecipe)],
        service: PhotoEditingService,
        libraryQueries: LibraryQueries,
        format: PhotoOutputFormat,
        includeMetadata: Bool,
        savesCopy: Bool,
        album: PHAssetCollection?,
        onSaved: @escaping (String) -> Void,
        onFinished: @escaping () -> Void
    ) {
        guard !isRunning, !items.isEmpty else { return }
        isRunning = true
        completed = 0
        total = items.count
        failures = []
        hasFinishedWithFailures = false

        task = Task { @MainActor in
            for item in items {
                if Task.isCancelled { break }
                do {
                    let assetID = try await save(
                        item,
                        service: service,
                        libraryQueries: libraryQueries,
                        format: format,
                        includeMetadata: includeMetadata,
                        savesCopy: savesCopy,
                        album: album
                    )
                    onSaved(assetID)
                } catch {
                    failures.append(
                        Failure(
                            id: item.asset.localIdentifier,
                            filename: Self.name(of: item.asset),
                            message: error.localizedDescription
                        )
                    )
                }
                completed += 1
            }
            isRunning = false
            isCancelling = false
            hasFinishedWithFailures = !failures.isEmpty
            task = nil
            onFinished()
        }
    }

    /// Stops after the photo currently being written.
    ///
    /// The overlay stays up — as "Finishing…" — until that write lands, and
    /// `isRunning` is cleared by the loop itself. Dropping the scrim here
    /// instead put the editor back in the user's hands while a save was still
    /// writing to their library, with nothing on screen to say so and no way
    /// to hear about it if it failed.
    func cancel() {
        guard isRunning else { return }
        isCancelling = true
        task?.cancel()
    }

    func clearFailures() {
        failures = []
        hasFinishedWithFailures = false
    }

    private func save(
        _ item: (asset: PHAsset, recipe: PhotoEditRecipe),
        service: PhotoEditingService,
        libraryQueries: LibraryQueries,
        format: PhotoOutputFormat,
        includeMetadata: Bool,
        savesCopy: Bool,
        album: PHAssetCollection?
    ) async throws -> String {
        let session = try await service.beginSession(for: item.asset)
        defer { service.endSession(session) }

        guard let option = session.preferredSource(for: item.recipe) else {
            throw PhotoEditingError.missingSource
        }
        let source = try await service.loadSource(option, in: session)

        var recipe = item.recipe
        recipe.source = option.source
        recipe.sourceFilename = option.filename
        recipe = try await Self.resolvingUpright(recipe, source: source, service: service)

        let result: PhotoSaveResult
        if savesCopy {
            result = try await service.saveCopy(
                session: session,
                source: source,
                recipe: recipe,
                renderRecipe: renderReady(recipe, for: item.asset, libraryQueries: libraryQueries),
                requestedFormat: format,
                includeMetadata: includeMetadata,
                album: album
            )
        } else {
            result = try await service.saveChanges(
                session: session,
                source: source,
                recipe: recipe,
                renderRecipe: renderReady(recipe, for: item.asset, libraryQueries: libraryQueries),
                requestedFormat: format,
                includeMetadata: includeMetadata
            )
        }
        return result.assetID
    }

    /// A pasted Upright mode solved on this photo's own pixels, once, before
    /// the save — so the saved recipe carries the transform and reopening it
    /// solves nothing (FS-03.15b AC-28).
    static func resolvingUpright(
        _ recipe: PhotoEditRecipe,
        source: LoadedPhotoEditSource,
        service: PhotoEditingService
    ) async throws -> PhotoEditRecipe {
        guard recipe.upright.needsSolving else { return recipe }
        var identity = PhotoEditRecipe.identity
        identity.source = recipe.source
        identity.sourceFilename = recipe.sourceFilename
        let original = try await service.renderer.renderPreview(
            source: source.info,
            recipe: identity,
            maximumDimension: CGFloat(UprightAnalyzer.analysisSide * 2)
        )
        return UprightResolver.resolve(recipe, on: CIImage(cgImage: original), context: Self.uprightContext)
    }

    private static let uprightContext = CIContext(options: [.cacheIntermediates: false])

    /// A server photo's edit rendered to a file for export (FS-17.06 §6): the
    /// steps of a save, with a file in `folder` at the end instead of Photos.
    /// The file is named the way it lands — `<name>_edited.<ext>` — so a
    /// share carries a real name too.
    static func renderToFile(
        _ photo: FetchedServerPhoto,
        recipe: PhotoEditRecipe,
        service: PhotoEditingService,
        format: PhotoOutputFormat,
        includeMetadata: Bool,
        into folder: URL
    ) async throws -> URL {
        let session = try await service.beginSession(for: .serverFile(photo))
        defer { service.endSession(session) }
        guard let option = session.preferredSource(for: recipe) else {
            throw PhotoEditingError.missingSource
        }
        let source = try await service.loadSource(option, in: session)
        var recipe = recipe
        recipe.source = option.source
        recipe.sourceFilename = option.filename
        recipe = try await resolvingUpright(recipe, source: source, service: service)
        let written = format == .heic && !PhotoEditingService.supportsHEICEncoding ? .jpeg : format
        let name = ServerUploadPath.editedFilename(original: photo.photo.primary.name, rendered: "x.\(written.fileExtension)")
        let url = folder.appendingPathComponent(name)
        try await service.writeRender(
            source: source,
            recipe: tokensExpanded(recipe, values: OverlayTokenValues(metadata: nil)),
            format: written,
            includeMetadata: includeMetadata,
            to: url
        )
        return url
    }

    /// Expands `{camera}`-style tokens **per photo**, not once for the run: a
    /// look synced across a shoot may carry a text overlay, and every frame has
    /// to stamp its own camera and exposure, not the first frame's.
    private func renderReady(
        _ recipe: PhotoEditRecipe,
        for asset: PHAsset,
        libraryQueries: LibraryQueries
    ) -> PhotoEditRecipe {
        guard recipe.overlays.contains(where: { $0.kind == .text }) else { return recipe }
        let metadata = try? libraryQueries.metadata(assetId: asset.localIdentifier)
        return Self.tokensExpanded(recipe, values: OverlayTokenValues(metadata: metadata))
    }

    private static func tokensExpanded(_ recipe: PhotoEditRecipe, values: OverlayTokenValues) -> PhotoEditRecipe {
        guard recipe.overlays.contains(where: { $0.kind == .text }) else { return recipe }
        var resolved = recipe
        resolved.overlays = recipe.overlays.map { overlay in
            guard overlay.kind == .text else { return overlay }
            var copy = overlay
            copy.text = OverlayTokenResolver.resolve(overlay.text, values: values)
            return copy
        }
        return resolved
    }

    private static func name(of asset: PHAsset) -> String {
        PHAssetResource.assetResources(for: asset).first?.originalFilename
            ?? asset.localIdentifier
    }
}

/// The full-screen progress shown while a run is being written.
///
/// A centred modal over a scrim, per DESIGN.md §10.3: a batch that writes to the
/// user's photo library must not be interruptible by a stray tap on the tools
/// behind it.
struct EditorBatchSaveOverlay: View {
    let saver: EditorBatchSaver

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}

            VStack(spacing: AppTheme.Spacing.lg) {
                ProgressView()
                    .tint(.white)
                Text(
                    saver.isCancelling
                        ? "Finishing this photo…"
                        : "Saving \(min(saver.completed + 1, saver.total)) of \(saver.total)"
                )
                    .font(EditorTheme.panelTitle)
                    .foregroundStyle(.white)
                    .monospacedDigit()
                ProgressView(value: saver.progressFraction)
                    .tint(EditorTheme.accent)
                    .frame(width: 220)
                Button("Cancel", role: .destructive) {
                    saver.cancel()
                }
                .foregroundStyle(.red)
                // The write in flight cannot be pulled back, so the scrim
                // stays until it lands rather than handing the editor back
                // while the library is still being written to.
                .disabled(saver.isCancelling)
            }
            .padding(AppTheme.Spacing.xxl)
            .background(EditorTheme.panelSolid, in: RoundedRectangle.app(AppTheme.Radius.lg))
        }
    }
}

/// A paste of the clipboard's look onto a picked set of photos.
struct PasteEditsPresentation: Identifiable {
    let assets: [PHAsset]
    let recipe: PhotoEditRecipe

    var id: String { assets.first?.localIdentifier ?? UUID().uuidString }
}

/// Confirms the paste, then runs it — a write to this many photos in the user's
/// library is not something a menu row should start on its own.
struct PasteEditsSheet: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss

    let presentation: PasteEditsPresentation

    @State private var saver = EditorBatchSaver()
    @State private var format: PhotoOutputFormat = .jpeg
    @State private var includeMetadata = true
    @State private var savesCopy = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Format", selection: $format) {
                        Text("JPEG").tag(PhotoOutputFormat.jpeg)
                        Text("HEIC").tag(PhotoOutputFormat.heic)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Include Metadata", isOn: $includeMetadata)
                    Toggle("Save as Copies", isOn: $savesCopy)
                } footer: {
                    Text("Applies the copied look — tone, colour, curve and film look. The crop, masks and markup of each photo are left alone.")
                }

                Section {
                    Button {
                        run()
                    } label: {
                        Label(
                            "Paste onto \(presentation.assets.count) Photos",
                            systemImage: "doc.on.clipboard"
                        )
                    }
                    .disabled(saver.isRunning)
                }
            }
            .navigationTitle("Paste Edits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if saver.isRunning {
                    EditorBatchSaveOverlay(saver: saver)
                }
            }
        }
    }

    private func run() {
        let items = presentation.assets.map { asset in
            (asset: asset, recipe: presentation.recipe)
        }
        saver.run(
            items: items,
            service: dependencies.photoEditing,
            libraryQueries: dependencies.libraryQueries,
            format: format,
            includeMetadata: includeMetadata,
            savesCopy: savesCopy,
            album: nil,
            onSaved: { _ in },
            onFinished: { dismiss() }
        )
    }
}

extension View {
    func pasteEditsSheet(
        _ presentation: Binding<PasteEditsPresentation?>,
        onDismiss: @escaping () -> Void
    ) -> some View {
        sheet(item: presentation, onDismiss: onDismiss) { presentation in
            PasteEditsSheet(presentation: presentation)
                .presentationDetents([.medium])
        }
    }
}
