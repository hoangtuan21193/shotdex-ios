import Photos
import ShotDexKit
import SwiftUI

// MARK: - Photos library editing (FS-18.03 §2, board `MAC_EditPhotos`)

/// A Photos library picture opened for editing: the file the editor renders
/// and the edit Photos holds for it (ShotDex's adjustment data), if any.
struct MacPhotosOpened: Sendable {
    let url: URL
    let committed: PhotoEditRecipe?
    /// When Photos last changed the picture: a draft written after it is
    /// work the user did here and never got into Photos (a crash, a failed
    /// close); one written before it is older than Photos.
    var modified: Date?
}

/// How a Photos library picture is read and written back. Done writes the
/// edit into the asset (FS-03.06 §2 Save Changes): Photos and the iPhone see
/// it, Photos' own Revert still works. The demo has its own, which never
/// reaches PhotoKit.
@MainActor
protocol MacPhotosEditing: AnyObject {
    func open(_ assetId: String) async throws -> MacPhotosOpened
    /// Writes `recipe` into the asset. Once Photos took it, it does not
    /// throw: the picture is opened again for the next Done, best effort —
    /// the new file when that went, nil when it did not (the next Done opens it).
    func done(_ assetId: String, recipe: PhotoEditRecipe) async throws -> URL?
    func close(_ assetId: String)
    /// The editor went: every session and its temporary original goes too.
    func releaseAll()
}

/// The real one: `PhotoEditingService`, the iPhone's Save Changes.
@MainActor
final class MacPhotosLibraryEditor: MacPhotosEditing {
    private let service: PhotoEditingService
    private var sessions: [String: (session: PhotoEditingSession, source: LoadedPhotoEditSource)] = [:]

    init(renderer: PhotoRenderService) {
        service = PhotoEditingService(renderer: renderer)
    }

    func open(_ assetId: String) async throws -> MacPhotosOpened {
        // The fetch reads the library: off the main actor.
        let box = await Task.detached(priority: .userInitiated) {
            MacAssetBox(asset: PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject)
        }.value
        guard let asset = box.asset else { throw PhotoEditingError.unavailable }
        let session = try await service.beginSession(for: asset, isOnCanvas: true)
        guard let option = session.preferredSource(for: session.recalledRecipe) else { throw PhotoEditingError.missingSource }
        let source = try await service.loadSource(option, in: session)
        sessions[assetId] = (session, source)
        return MacPhotosOpened(url: source.info.url, committed: session.recalledRecipe, modified: asset.modificationDate)
    }

    func done(_ assetId: String, recipe: PhotoEditRecipe) async throws -> URL? {
        // A Done whose reopen failed left no session: open it now.
        if sessions[assetId] == nil { _ = try await open(assetId) }
        guard let open = sessions[assetId] else { throw PhotoEditingError.unavailable }
        _ = try await service.saveChanges(session: open.session, source: open.source, recipe: recipe, requestedFormat: .preserve)
        // The write retired that session; the canvas still reads its file
        // until the new one is in, so it is not released here.
        sessions[assetId] = nil
        return try? await self.open(assetId).url
    }

    func close(_ assetId: String) {
        sessions[assetId] = nil
    }

    func releaseAll() {
        sessions = [:]
        service.releaseCachedSessions()
    }
}

/// A fetched asset carried out of the detached fetch. PHAsset is immutable
/// once fetched; it is only read on the main actor after this.
private struct MacAssetBox: @unchecked Sendable {
    let asset: PHAsset?
}

#if DEBUG
/// The demo's Photos library: the demo picture as the original, and what
/// Done wrote kept for this launch. Never PhotoKit — the user's library is
/// never touched by a test (user 2026-11-06). `-ShotDexDemoDoneFails`
/// makes Done fail, to see the error and that the edit stays.
@MainActor
final class MacDemoPhotosEditor: MacPhotosEditing {
    private(set) static var committed: [String: PhotoEditRecipe] = [:]

    func open(_ assetId: String) async throws -> MacPhotosOpened {
        guard let url = await Task.detached(operation: { MacDemoLibrary.pictureFiles(for: [assetId]).first }).value else {
            throw PhotoEditingError.missingSource
        }
        return MacPhotosOpened(url: url, committed: Self.committed[assetId])
    }

    func done(_ assetId: String, recipe: PhotoEditRecipe) async throws -> URL? {
        // About what a Photos write takes, so the spinner on Done is seen.
        try await Task.sleep(for: .milliseconds(600))
        if ProcessInfo.processInfo.arguments.contains("-ShotDexDemoDoneFails") { throw PhotoEditingError.cannotEncode }
        Self.committed[assetId] = recipe
        return try? await open(assetId).url
    }

    func close(_ assetId: String) {}
    func releaseAll() {}
}
#endif

// MARK: - Model

extension MacEditorModel {
    enum DoneState: Equatable {
        case idle
        case writing
        /// Written a moment ago: "✓ Saved to Photos" for a few seconds — the
        /// file photo's "Saved", which a Photos picture otherwise lacks.
        case saved
        case failed(String)
    }

    /// The photo open is a Photos library picture with an edit Photos does
    /// not have yet: Done is lit, and leaving writes it first.
    var needsDone: Bool {
        isPhotosLibrary && load == .ready && recipe != (committedRecipe ?? .identity)
    }

    /// Done (⌘↩): the edit into Photos. Stays in the editor and says why
    /// when Photos refuses; the edit is kept either way. True when there was
    /// nothing to write or it was written. A second call while one writes
    /// waits for that one instead of starting another (⌘Q, ◀ during a Done).
    /// Edits made while it wrote are written too before the user is taken
    /// where they asked to go.
    @discardableResult
    func done() async -> Bool {
        if let doneTask { return await doneTask.value }
        var wrote = true
        var wroteSomething = false
        var passes = 0
        let id = currentId
        while needsDone, currentId == id, passes < 3 {
            passes += 1
            guard await writeOnce() else { wrote = false; break }
            wroteSomething = true
        }
        if wrote, wroteSomething, currentId == id {
            doneState = .saved
            Task {
                try? await Task.sleep(for: .seconds(3))
                if doneState == .saved { doneState = .idle }
            }
        }
        runPendingTarget(wrote: wrote)
        return wrote
    }

    private func writeOnce() async -> Bool {
        let id = currentId
        let recipe = recipe
        let generation = generationForDone
        flushSave()
        doneState = .writing
        let task = Task { () -> Bool in
            do {
                let url = try await photosEditor.done(id, recipe: recipe)
                guard currentId == id else { return true }
                committedRecipe = recipe
                doneState = .idle
                if let url, let info = try? await exportRenderer.inspectSource(at: url), generationForDone == generation {
                    replaceSource(info)
                }
                return true
            } catch {
                if currentId == id { doneState = .failed(Self.doneFailure(error)) }
                return false
            }
        }
        doneTask = task
        let wrote = await task.value
        doneTask = nil
        return wrote
    }

    /// Where the user asked to go while it wrote: there now. A refusal keeps
    /// them here, and says why at once rather than behind a click.
    private func runPendingTarget(wrote: Bool) {
        let target = pendingTarget
        pendingTarget = nil
        guard let target else { return }
        guard wrote else {
            showsDoneFailure = true
            NSSound.beep()
            return
        }
        switch target {
        case .photo(let index): openWithoutDone(at: index)
        case .leave(let leave): leave()
        }
    }

    /// ◀, Esc: a Photos picture is written first (FS-18.03 §2 "leaving is
    /// Done"); `leave` runs only once that went, or there was nothing to write.
    func leaveAfterDone(_ leave: @escaping () -> Void) {
        guard needsDone || doneTask != nil else {
            flushSave()
            leave()
            return
        }
        pendingTarget = .leave(leave)
        if doneTask == nil { Task { await done() } }
    }

    /// The window closes under the editor: Done runs on its own, then the
    /// temporary originals go. A failure has no editor left to show it in;
    /// the draft stays in the database.
    func doneOnClose() {
        // An opening still under way stores nothing after this.
        cancelOpening()
        Task {
            await done()
            photosEditor.releaseAll()
        }
    }

    nonisolated static func doneFailure(_ error: Error) -> String {
        if (error as? CocoaError)?.code == .fileWriteOutOfSpace {
            return String(localized: "The disk is full, so Photos couldn't take the edit. Free some space, then click Done again.",
                          comment: "Mac editor: Done failed, no space")
        }
        return String(localized: "Photos didn't take the edit. Your changes are still here — click Done to try again.",
                      comment: "Mac editor: Done failed; the edit is kept")
    }
}

// MARK: - Toolbar

/// Revert to Original… and Done for a Photos library picture (board
/// `MAC_EditPhotos`): no "Edited · Saved" — nothing is in Photos until Done.
struct MacEditorDoneButton: View {
    @Bindable var model: MacEditorModel

    var body: some View {
        Button {
            Task { await model.done() }
        } label: {
            // One width whether or not it is writing: Revert does not move.
            HStack(spacing: 6) {
                if model.doneState == .writing { ProgressView().controlSize(.mini) }
                Text("Done", comment: "Mac editor toolbar: write the edit into the Photos library")
            }
        }
        .keyboardShortcut(.return, modifiers: .command)
        // The board's commit pill: black on the accent fill, a 36 capsule.
        .buttonStyle(MacPushButtonStyle(isDefault: true, isToolbarCommand: true))
        .accessibilityValue(model.doneState == .writing
                            ? String(localized: "Saving to Photos", comment: "VoiceOver: Done is writing the edit into Photos") : "")
        .disabled(!model.needsDone || model.doneState == .writing)
        .help(model.needsDone
              ? String(localized: "Save the edit to the Photos library (⌘↩)", comment: "Mac editor toolbar: Done")
              : String(localized: "Photos has this edit — nothing new to save", comment: "Mac editor toolbar: Done is off"))
        .accessibilityIdentifier("editor.done")
    }
}

/// Why Done did not go, beside it.
struct MacEditorDoneFailure: View {
    @Bindable var model: MacEditorModel

    var body: some View {
        if model.doneState == .saved {
            Label(String(localized: "Saved to Photos", comment: "Mac editor toolbar: Done wrote the edit a moment ago"), systemImage: "checkmark")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("editor.doneSaved")
        } else if case .failed(let words) = model.doneState, model.needsDone {
            Button { model.showsDoneFailure = true } label: {
                Label(String(localized: "Not Saved to Photos", comment: "Mac editor toolbar: Done failed; a click says why"),
                      systemImage: "exclamationmark.triangle")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 12))
                    .foregroundStyle(MacTheme.redText)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("editor.doneFailed")
            .popover(isPresented: $model.showsDoneFailure, arrowEdge: .bottom) {
                Text(words)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 260, alignment: .leading)
                    .padding(12)
            }
        }
    }
}
