import AppKit
import Photos
import ShotDexKit
import SwiftUI
import UniformTypeIdentifiers

/// Image › Combine Photos › Panorama… (board `MAC_Merge`, FS-18.04 §4b,
/// behaviour of FS-14): the frames on the left, the stage, the inspector of
/// 300. Always dark (D10). The stitch is `MacPanoramaModel`; this page adds
/// where the picture is saved and how the Mac names it (FS-18.03 §5).
@MainActor
@Observable
final class MacCombineSession: Identifiable {
    enum Destination: Equatable {
        /// Beside the first frame, `‹name› (Panorama).jpg`; a Photos frame's
        /// panorama goes into Photos.
        case sameFolder
        case folder(MacResizeFolder)
    }

    struct Frame: Identifiable, Equatable {
        let id: Int
        let photoId: String
        let name: String
        let exposure: String
    }

    let id = UUID()
    let model: MacPanoramaModel
    let frames: [Frame]
    /// Videos and photos with no original here, left out (said in the panel).
    let leftOut: Int
    /// Usable photos past `frameLimit`, not used.
    var overLimit = 0
    let subtitle: String
    var destination = Destination.sameFolder
    var showsInspector = true
    /// Stop pressed while the frames were read and aligned.
    var isStopped = false
    /// The saved file (or "Photos"), said after Save; nil before.
    private(set) var saved: URL?
    private(set) var savedToPhotos = false
    /// The new picture's file name, said after Save.
    private(set) var savedName = ""
    private(set) var saveError: String?
    /// The stitched file when it could not be moved where Save To says:
    /// Try Again moves it again instead of stitching it again.
    private(set) var unplaced: URL?
    private let photoLibrary: PhotoLibraryService
    private let firstFrame: PhotoEditOrigin?

    init(origins: [PhotoEditOrigin], frames: [Frame], leftOut: Int, subtitle: String, photoLibrary: PhotoLibraryService) {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("ShotDexCombine", isDirectory: true)
        model = MacPanoramaModel(photos: origins, photoLibrary: photoLibrary,
                                 stitch: .composing(into: work), serverWorkDirectory: work)
        self.frames = frames
        self.leftOut = leftOut
        self.subtitle = subtitle
        self.photoLibrary = photoLibrary
        firstFrame = origins.first
    }

    /// The first frame's file name, `DSC09412.ARW`.
    var firstName: String { frames.first?.name ?? "" }

    /// "A JPEG beside DSC09412.ARW on T7 RAW Archive."
    var destinationWords: String {
        switch destination {
        case .sameFolder:
            if case .asset = firstFrame {
                return String(localized: "A new photo in your Photos library, beside \(firstName).", comment: "Mac Combine: Save To, frames from Photos")
            }
            let place = firstFrame?.localFileURL.map { $0.deletingLastPathComponent().lastPathComponent } ?? ""
            return String(localized: "A JPEG beside \(firstName) in “\(place)”.", comment: "Mac Combine: Save To, beside the first frame")
        case .folder(let folder):
            return String(localized: "A JPEG in “\(folder.name)”.", comment: "Mac Combine: Save To, a chosen folder")
        }
    }

    /// The stitched file is here (the model composed it into a work folder):
    /// it goes where Save To says, under the Mac's name.
    func place(_ composed: URL) {
        let stem = ((firstName as NSString).deletingPathExtension)
        let name = String(localized: "\(stem) (Panorama)", comment: "Mac Combine: the saved panorama's name, after the first frame") + ".jpg"
        let destination = destination
        let first = firstFrame
        let photoLibrary = photoLibrary
        saveError = nil
        unplaced = nil
        Task {
            do {
                if destination == .sameFolder, case .asset = first {
                    _ = try await photoLibrary.saveImageFile(at: composed, filename: name)
                    try? FileManager.default.removeItem(at: composed.deletingLastPathComponent())
                    savedName = name
                    savedToPhotos = true
                    return
                }
                saved = try await Task.detached(priority: .userInitiated) { () -> URL in
                    let target: URL
                    switch destination {
                    case .sameFolder:
                        guard let url = first?.localFileURL else { throw CocoaError(.fileNoSuchFile) }
                        target = url.deletingLastPathComponent()
                    case .folder(let folder):
                        guard let url = folder.resolved() else { throw CocoaError(.fileNoSuchFile) }
                        target = url
                    }
                    let isAccessing = target.startAccessingSecurityScopedResource()
                    defer { if isAccessing { target.stopAccessingSecurityScopedResource() } }
                    let manager = FileManager.default
                    let existing = Set(((try? manager.contentsOfDirectory(atPath: target.path)) ?? []).map { $0.lowercased() })
                    var final = name
                    if existing.contains(name.lowercased()) {
                        let base = (name as NSString).deletingPathExtension
                        let number = FileExportPlan.firstFreeNumber { existing.contains("\(base) (\($0)).jpg".lowercased()) }
                        final = "\(base) (\(number)).jpg"
                    }
                    let url = target.appendingPathComponent(final)
                    try manager.moveItem(at: composed, to: url)
                    try? manager.removeItem(at: composed.deletingLastPathComponent())
                    return url
                }.value
            } catch {
                unplaced = composed
                saveError = String(localized: "ShotDex couldn’t put the panorama there. Choose another folder, then Try Again.",
                                   comment: "Mac Combine: moving the saved panorama failed")
            }
        }
    }

    /// Whether the frames are Photos library pictures (Same Folder means Photos).
    var isFromPhotos: Bool {
        if case .asset = firstFrame { return true }
        return false
    }

    /// The page goes from under it (another place in the sidebar): the
    /// alignment and a save under way stop, no file is left behind.
    func stop() {
        model.stopLoading()
        model.cancelSave()
    }

    func choose(_ url: URL) {
        Task {
            guard let folder = await Task.detached(operation: { MacResizeFolder(picked: url) }).value else { return }
            destination = .folder(folder)
        }
    }
}

struct MacCombinePage: View {
    @Bindable var session: MacCombineSession
    let close: () -> Void
    @State private var choosesFolder = false
    @State private var loadTask: Task<Void, Never>?

    private var model: MacPanoramaModel { session.model }

    var body: some View {
        HStack(spacing: 0) {
            MacCombineFrames(session: session)
                .frame(width: 228)
            Rectangle().fill(MacTheme.Editor.hairline).frame(width: 1)
            MacCombineStage(session: session, retry: start, stop: stop)
            if session.showsInspector {
                Rectangle().fill(MacTheme.Editor.hairline).frame(width: 1)
                MacCombineInspector(session: session, choosesFolder: $choosesFolder)
                    .frame(width: 300)
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .tint(MacTheme.Editor.label)
        .navigationTitle(String(localized: "Panorama", comment: "Mac Combine: the page title, the mode's name"))
        .navigationSubtitle(session.subtitle)
        .toolbar { toolbar }
        .fileImporter(isPresented: $choosesFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { session.choose(url) }
        }
        // Esc wherever the keys are (no field needs focus first): Arrange ends,
        // else the page is left. The folder picker takes its own Esc.
        .background {
            if !choosesFolder {
                Button("") {
                    if model.isArranging { model.toggleArrange() } else { leave() }
                }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
        }
        .onAppear {
            // Once per page: the inspector or full screen re-firing onAppear must not start over.
            if loadTask == nil, !model.hasPicture, !session.isStopped { start() }
        }
        // Leaving goes through `leave()` (Back, Cancel, Esc, another place),
        // which stops the work; a re-fired onDisappear must not strand the load.
        .onChange(of: model.composedFile) { _, file in if let file { session.place(file) } }
    }

    private func start() {
        loadTask?.cancel()
        session.isStopped = false
        loadTask = Task { await model.load() }
    }

    /// Stop while it aligns: the work ends, Try Again starts it over.
    private func stop() {
        loadTask?.cancel()
        loadTask = nil
        model.stopLoading()
        session.isStopped = true
    }

    /// Back, Cancel, Esc: nothing is saved; a save under way is stopped
    /// (no file is left behind, FS-14.01 §6).
    private func leave() {
        loadTask?.cancel()
        session.stop()
        close()
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: leave) {
                Label(String(localized: "Back", comment: "Mac toolbar"), systemImage: "chevron.left")
            }
            .keyboardShortcut("[", modifiers: .command)
            .help(String(localized: "Back (⌘[ or Esc)", comment: "Mac Combine toolbar"))
            .accessibilityIdentifier("combine.back")
        }
        ToolbarItem(placement: .primaryAction) {
            Button { session.showsInspector.toggle() } label: {
                Label(String(localized: "Inspector", comment: "Mac Combine toolbar"), systemImage: "sidebar.right")
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .help(String(localized: "Show or hide the options (⌥⌘I)", comment: "Mac Combine toolbar"))
            .accessibilityIdentifier("combine.inspector")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if session.saved != nil || session.savedToPhotos {
                if let saved = session.saved {
                    Button(String(localized: "Show in Finder", comment: "Mac Combine toolbar: reveal the saved panorama")) {
                        NSWorkspace.shared.activateFileViewerSelecting([saved])
                    }
                    .accessibilityIdentifier("combine.reveal")
                }
                Button(String(localized: "Done", comment: "Mac Combine toolbar: leave after saving"), action: close)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(MacPushButtonStyle(isDefault: true, isToolbarCommand: true))
                    .accessibilityIdentifier("combine.done")
            } else if let progress = model.saveProgress {
                HStack(spacing: 6) {
                    ProgressView(value: progress).frame(width: 80)
                    Text("Saving…", comment: "Mac Combine toolbar: the panorama is being written").font(.system(size: 12))
                }
                Button(String(localized: "Stop", comment: "Mac Combine toolbar: stop saving"), action: model.cancelSave)
                    .accessibilityIdentifier("combine.stopSave")
            } else {
                Button(String(localized: "Cancel", comment: "Mac Combine toolbar: leave without saving"), action: leave)
                    .accessibilityIdentifier("combine.cancel")
                Button(String(localized: "Save", comment: "Mac Combine toolbar: save the panorama"), action: model.save)
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(MacPushButtonStyle(isDefault: true, isToolbarCommand: true))
                    .disabled(!model.canSave)
                    .accessibilityIdentifier("combine.save")
            }
        }
    }
}

// MARK: - Frames

/// The frames, placed first, then Not Placed (N). In Arrange a Not Placed
/// frame is dragged onto the stage; a placed one has Remove.
private struct MacCombineFrames: View {
    @Bindable var session: MacCombineSession

    private var model: MacPanoramaModel { session.model }

    var body: some View {
        let arranged = model.hasPicture ? model.arrangedFrames : []
        let placed = session.frames.filter { frame in arranged.first { $0.id == frame.id }?.isPlaced ?? true }
        let notPlaced = session.frames.filter { frame in arranged.first { $0.id == frame.id }?.isPlaced == false }
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Frames", comment: "Mac Combine: the frames panel").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(MacInflect.string("^[\(session.frames.count) photo](inflect: true)", comment: "Mac Combine: how many frames"))
                        .font(.system(size: 11)).foregroundStyle(MacTheme.Editor.secondaryText)
                }
                if session.overLimit > 0 {
                    Text(MacInflect.string("Only the first \(MacCombineSession.frameLimit) photos are used; ^[\(session.overLimit) more](inflect: true) left out.",
                                           comment: "Mac Combine: more photos than a panorama takes"))
                        .font(.system(size: 11)).foregroundStyle(MacTheme.Editor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if session.leftOut > 0 {
                    Text(MacInflect.string("^[\(session.leftOut) item](inflect: true) in the selection left out — videos, or photos whose original isn’t on this Mac.",
                                           comment: "Mac Combine: what was not used"))
                        .font(.system(size: 11)).foregroundStyle(MacTheme.Editor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(placed) { row($0, placed: true) }
                    .padding(.top, 2)
                if !notPlaced.isEmpty {
                    Text("Not Placed (\(notPlaced.count))", comment: "Mac Combine: frames the stitch could not join")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(MacTheme.Editor.secondaryText)
                        .padding(.top, 14)
                    ForEach(notPlaced) { row($0, placed: false) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
        }
        .background(MacTheme.Editor.panelSolid)
    }

    private func row(_ frame: MacCombineSession.Frame, placed: Bool) -> some View {
        HStack(spacing: 10) {
            Group {
                if let image = model.hasPicture ? model.thumbnail(for: frame.id) : nil {
                    Image(decorative: image, scale: 2).resizable().scaledToFill()
                } else {
                    MacTheme.Editor.fill
                }
            }
            .frame(width: 48, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: MacTheme.Editor.thumbnailRadius))
            VStack(alignment: .leading, spacing: 1) {
                Text(frame.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text(frame.exposure).font(.system(size: 11)).foregroundStyle(MacTheme.Editor.secondaryText).lineLimit(1)
            }
            Spacer(minLength: 4)
            status(frame, placed: placed)
        }
        .padding(.horizontal, 4)
        .frame(height: 48)
        .contentShape(Rectangle())
        .draggable("frame:\(frame.id)") {
            Text(frame.name).padding(6).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
        }
        .contextMenu {
            if placed {
                Button(String(localized: "Remove from Panorama", comment: "Mac Combine: take a frame out")) {
                    model.removeFromPanorama(frame: frame.id)
                }
                .disabled(!model.hasPicture || model.isSaving)
            }
        }
        // `.contain`: the − in Arrange stays its own button.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(frame.name)
        .accessibilityValue(model.arrangedFrames.first { $0.id == frame.id }?.accessibilityLabel(of: session.frames.count) ?? "")
        .accessibilityIdentifier("combine.frame.\(frame.name)")
    }

    @ViewBuilder
    private func status(_ frame: MacCombineSession.Frame, placed: Bool) -> some View {
        switch session.isStopped && !model.hasPicture ? .stitching("") : model.state {
        case .loading(let done, _):
            if frame.id < done {
                Image(systemName: "checkmark").foregroundStyle(MacTheme.Editor.channelGreen)
            } else if frame.id == done {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: "clock").foregroundStyle(MacTheme.Editor.secondaryText)
            }
        case .stitching, .confirming:
            Image(systemName: "clock").foregroundStyle(MacTheme.Editor.secondaryText)
        default:
            if placed {
                if model.isArranging, model.hasPicture {
                    Button { model.removeFromPanorama(frame: frame.id) } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Remove from Panorama", comment: "Mac Combine: take a frame out"))
                    .accessibilityIdentifier("combine.remove.\(frame.name)")
                } else {
                    Image(systemName: "checkmark").foregroundStyle(MacTheme.Editor.channelGreen)
                }
            } else {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.yellow)
                    .help(String(localized: "Not joined to the panorama. Arrange Frames… and drag it where it overlaps.", comment: "Mac Combine: a frame not placed"))
            }
        }
    }
}

// MARK: - Stage

private struct MacCombineStage: View {
    @Bindable var session: MacCombineSession
    let retry: () -> Void
    let stop: () -> Void

    private var model: MacPanoramaModel { session.model }

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            stage
                .padding(.horizontal, 28)
            if let caption {
                Text(caption).font(.system(size: 12)).foregroundStyle(MacTheme.Editor.secondaryText)
                    .accessibilityIdentifier("combine.caption")
            }
            status.padding(.horizontal, 28)
            if let message = model.arrangeMessage {
                Text(message).font(.system(size: 12)).foregroundStyle(MacTheme.redText)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var stage: some View {
        if let preview = model.preview {
            GeometryReader { geometry in
                let size = Self.fitted(CGSize(width: preview.width, height: preview.height), in: geometry.size)
                ZStack(alignment: .topLeading) {
                    Image(decorative: preview, scale: 1).resizable().frame(width: size.width, height: size.height)
                    if model.isArranging {
                        ForEach(model.arrangedFrames.filter(\.isPlaced)) { frame in
                            Path { path in
                                let points = frame.outline.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
                                guard let first = points.first else { return }
                                path.move(to: first)
                                points.dropFirst().forEach { path.addLine(to: $0) }
                                path.closeSubpath()
                            }
                            .stroke(Color.white.opacity(0.55), lineWidth: 1)
                        }
                    }
                    if model.autoCrop {
                        Text("Auto Crop", comment: "Mac Combine: the stage shows the cropped picture")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 6).frame(height: 20)
                            .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 4))
                            .padding(8)
                    }
                    if model.isArrangingFrame {
                        ProgressView().controlSize(.small).frame(width: size.width, height: size.height)
                    }
                }
                .frame(width: size.width, height: size.height)
                .overlay {
                    if model.isArranging {
                        RoundedRectangle(cornerRadius: 2).strokeBorder(MacTheme.Editor.accent, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    }
                }
                // Arrange: a Not Placed frame dropped where it overlaps is matched there (FS-14.01 §5).
                .dropDestination(for: String.self) { items, location in
                    guard model.isArranging, let item = items.first, item.hasPrefix("frame:"),
                          let frame = Int(item.dropFirst(6)) else { return false }
                    model.place(frame: frame, at: CGPoint(x: location.x / size.width, y: location.y / size.height))
                    return true
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "Panorama preview", comment: "Mac Combine: the stage"))
                .accessibilityIdentifier("combine.stage")
            }
            .frame(maxHeight: 420)
        } else {
            RoundedRectangle(cornerRadius: 12).fill(MacTheme.Editor.panel)
                .frame(maxWidth: .infinity).frame(height: 280)
                .overlay { placeholder }
        }
    }

    /// Before a picture: what is happening, or why there won't be one.
    @ViewBuilder
    private var placeholder: some View {
        if session.isStopped && !model.hasPicture {
            VStack(spacing: 10) {
                Text("Stopped. Nothing was saved.", comment: "Mac Combine: aligning stopped")
                Button(String(localized: "Try Again", comment: "Mac Combine: load the frames again"), action: retry)
                    .accessibilityIdentifier("combine.retry")
            }
            .font(.system(size: 13)).foregroundStyle(MacTheme.Editor.secondaryText)
        } else {
            placeholderForState
        }
    }

    @ViewBuilder
    private var placeholderForState: some View {
        switch model.state {
        case .noOverlap:
            VStack(spacing: 10) {
                Text("Those photos don’t overlap enough to join. Shoot with about a third of each frame shared with the next.",
                     comment: "Mac Combine: no overlap")
                    .multilineTextAlignment(.center).frame(maxWidth: 380)
            }
            .font(.system(size: 13)).foregroundStyle(MacTheme.Editor.secondaryText)
            .accessibilityIdentifier("combine.noOverlap")
        case .unavailable(let count):
            VStack(spacing: 10) {
                Text("^[\(count) photo](inflect: true) couldn’t be read.", comment: "Mac Combine: frames could not be loaded")
                Button(String(localized: "Try Again", comment: "Mac Combine: load the frames again"), action: retry)
                    .accessibilityIdentifier("combine.retry")
            }
            .font(.system(size: 13)).foregroundStyle(MacTheme.Editor.secondaryText)
        case .confirming(let words):
            VStack(spacing: 10) {
                Text(words).multilineTextAlignment(.center).frame(maxWidth: 380)
                Button(String(localized: "Continue", comment: "Mac Combine: start a long stitch")) {
                    model.confirmLongStitch()
                    retry()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("combine.continue")
            }
            .font(.system(size: 13)).foregroundStyle(MacTheme.Editor.secondaryText)
        default:
            ProgressView().controlSize(.small)
        }
    }

    /// "Spherical · 16,384 × 3,904 px".
    private var caption: String? {
        guard model.hasPicture, let estimate = model.sizeEstimate else { return nil }
        return "\(MacCombineWords.projection(model.projection)) · \(estimate.width.formatted()) × \(estimate.height.formatted()) px"
    }

    /// "Aligning frames…" with Stop; "Saving 40%"; an error from Save.
    @ViewBuilder
    private var status: some View {
        if session.isStopped && !model.hasPicture {
            EmptyView()
        } else {
            statusForState
        }
    }

    @ViewBuilder
    private var statusForState: some View {
        switch model.state {
        case .loading(let done, let total):
            progressRow(String(localized: "Loading frames — \(min(done + 1, total)) of \(total)", comment: "Mac Combine: reading the frames"),
                        fraction: total > 0 ? Double(done) / Double(total) : 0)
        case .stitching(let words):
            progressRow(words, fraction: nil)
        default:
            if let error = model.errorMessage ?? session.saveError {
                HStack(spacing: 10) {
                    Text(error).font(.system(size: 12)).foregroundStyle(MacTheme.redText).accessibilityIdentifier("combine.error")
                    if let file = session.unplaced {
                        Button(String(localized: "Try Again", comment: "Mac Combine: move the stitched panorama again")) { session.place(file) }
                            .accessibilityIdentifier("combine.placeAgain")
                    }
                }
            } else if session.savedToPhotos {
                Label(String(localized: "Saved \(session.savedName) to Photos", comment: "Mac Combine: the panorama went into Photos"), systemImage: "checkmark.circle")
                    .font(.system(size: 12)).accessibilityIdentifier("combine.saved")
            } else if let saved = session.saved {
                Label(String(localized: "Saved \(saved.lastPathComponent)", comment: "Mac Combine: the panorama's file"), systemImage: "checkmark.circle")
                    .font(.system(size: 12)).accessibilityIdentifier("combine.saved")
            } else if model.isRefining {
                Text("Sharpening the preview…", comment: "Mac Combine: the sharp preview is being made")
                    .font(.system(size: 11)).foregroundStyle(MacTheme.Editor.secondaryText)
            }
        }
    }

    private func progressRow(_ words: String, fraction: Double?) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(words).font(.system(size: 13, weight: .semibold)).accessibilityIdentifier("combine.status")
            if let fraction {
                ProgressView(value: fraction).frame(maxWidth: .infinity)
                Text(fraction.formatted(.percent.precision(.fractionLength(0)))).font(.system(size: 12)).monospacedDigit()
                    .foregroundStyle(MacTheme.Editor.secondaryText)
            } else {
                Spacer()
            }
            Button(String(localized: "Stop", comment: "Mac Combine: stop reading and aligning the frames"), action: stop)
                .accessibilityIdentifier("combine.stop")
        }
    }

    static func fitted(_ size: CGSize, in box: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0, box.width > 0, box.height > 0 else { return .zero }
        let scale = min(box.width / size.width, box.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

// MARK: - Inspector

private struct MacCombineInspector: View {
    @Bindable var session: MacCombineSession
    @Binding var choosesFolder: Bool

    private var model: MacPanoramaModel { session.model }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                group(String(localized: "Projection", comment: "Mac Combine inspector")) {
                    MacEditorSegments(options: PanoramaProjectionKind.allCases, selection: $model.projection,
                                      id: "combine.projection", isUnavailable: { !isAvailable($0) }) { MacCombineWords.projection($0) }
                    Text(MacCombineWords.projectionNote(model.projection))
                        .font(.system(size: 11)).foregroundStyle(MacTheme.Editor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(model.availability.filter { !$0.isAvailable }, id: \.kind) { item in
                        Label(MacCombineWords.unavailable(item), systemImage: "info.circle")
                            .font(.system(size: 11)).foregroundStyle(MacTheme.Editor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                divider
                group(String(localized: "Edges", comment: "Mac Combine inspector")) {
                    HStack(spacing: 10) {
                        Text("Boundary Warp", comment: "Mac Combine inspector").foregroundStyle(MacTheme.Editor.secondaryText)
                        Slider(value: $model.boundaryWarp, in: 0...1, step: 0.05)
                            .controlSize(.small)
                            .accessibilityLabel(String(localized: "Boundary Warp", comment: "Mac Combine inspector"))
                            .accessibilityIdentifier("combine.warp")
                        Text("\(Int((model.boundaryWarp * 100).rounded()))").font(.system(size: 12)).monospacedDigit()
                            .foregroundStyle(MacTheme.Editor.secondaryText).frame(width: 28, alignment: .trailing)
                    }
                    Text("Stretches the curved edges out to the frame instead of cropping them off.", comment: "Mac Combine inspector")
                        .font(.system(size: 11)).foregroundStyle(MacTheme.Editor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle(String(localized: "Auto Crop", comment: "Mac Combine inspector"), isOn: $model.autoCrop)
                        .toggleStyle(.checkbox).tint(MacTheme.Editor.accent)
                        .accessibilityIdentifier("combine.autoCrop")
                }
                divider
                group(String(localized: "Output", comment: "Mac Combine inspector")) {
                    HStack(spacing: 10) {
                        Text("Size", comment: "Mac Combine inspector").foregroundStyle(MacTheme.Editor.secondaryText)
                        Slider(value: $model.sizeScale, in: 0.25...1, step: 0.05)
                            .controlSize(.small)
                            .accessibilityLabel(String(localized: "Size", comment: "Mac Combine inspector"))
                            .accessibilityIdentifier("combine.size")
                        Text(model.sizeScale.formatted(.percent.precision(.fractionLength(0)))).font(.system(size: 12)).monospacedDigit()
                            .foregroundStyle(MacTheme.Editor.secondaryText).frame(width: 40, alignment: .trailing)
                    }
                    if let words = model.estimateText {
                        Text(words).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("combine.estimate")
                    }
                    Text("Save To", comment: "Mac Combine inspector").foregroundStyle(MacTheme.Editor.secondaryText).padding(.top, 6)
                    Menu {
                        Button(sameTitle) { session.destination = .sameFolder }
                        Button(String(localized: "Choose Folder…", comment: "Mac Combine: Save To")) { choosesFolder = true }
                    } label: {
                        Label(destinationTitle, systemImage: "folder")
                    }
                    .accessibilityIdentifier("combine.saveTo")
                    Text(session.destinationWords).font(.system(size: 11)).foregroundStyle(MacTheme.Editor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                divider
                group(String(localized: "Arrange", comment: "Mac Combine inspector")) {
                    Button(action: model.toggleArrange) {
                        Label(model.isArranging ? String(localized: "Done Arranging", comment: "Mac Combine: leave Arrange")
                                                : String(localized: "Arrange Frames…", comment: "Mac Combine: move frames by hand"),
                              systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!model.canArrange)
                    .accessibilityIdentifier("combine.arrange")
                    Text(model.isArranging
                         ? String(localized: "Drag a Not Placed frame onto the picture where it overlaps, or remove a frame from the list.", comment: "Mac Combine: how Arrange works")
                         : String(localized: "Move a frame the automatic placement got wrong.", comment: "Mac Combine inspector"))
                        .font(.system(size: 11)).foregroundStyle(MacTheme.Editor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                divider
                Text("A new photo is saved. The originals are never changed.", comment: "Mac Combine inspector")
                    .font(.system(size: 11)).foregroundStyle(MacTheme.Editor.secondaryText)
            }
            .font(.system(size: 13))
            .padding(16)
            .disabled(model.isSaving)
        }
        .background(MacTheme.Editor.panelSolid)
    }

    private var destinationTitle: String {
        switch session.destination {
        case .sameFolder: sameTitle
        case .folder(let folder): folder.name
        }
    }

    private var sameTitle: String {
        session.isFromPhotos ? String(localized: "Photos Library", comment: "Mac Combine: Save To, frames from Photos")
                             : String(localized: "Same Folder as Frames", comment: "Mac Combine: Save To")
    }

    private func isAvailable(_ kind: PanoramaProjectionKind) -> Bool {
        model.availability.first { $0.kind == kind }?.isAvailable ?? true
    }

    // The board's rhythm: about 24 between groups.
    private var divider: some View { Divider().padding(.vertical, 18) }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(MacTheme.Editor.secondaryText)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

enum MacCombineWords {
    static func projection(_ kind: PanoramaProjectionKind) -> String {
        switch kind {
        case .spherical: String(localized: "Spherical", comment: "Panorama projection")
        case .cylindrical: String(localized: "Cylindrical", comment: "Panorama projection")
        case .perspective: String(localized: "Perspective", comment: "Panorama projection")
        }
    }

    static func projectionNote(_ kind: PanoramaProjectionKind) -> String {
        switch kind {
        case .spherical:
            String(localized: "Works for any sweep, including a full circle. Straight lines bend near the edges.", comment: "Mac Combine: Spherical")
        case .cylindrical:
            String(localized: "Keeps vertical lines straight. Best for a wide sweep that doesn’t go far up or down.", comment: "Mac Combine: Cylindrical")
        case .perspective:
            String(localized: "Keeps every straight line straight. Only for a narrow sweep; the edges stretch.", comment: "Mac Combine: Perspective")
        }
    }

    /// "Perspective works up to about 78° from the centre — this sweep is 107°."
    static func unavailable(_ item: PanoramaProjectionAvailability) -> String {
        let name = projection(item.kind)
        switch item.reason {
        case .horizontalSweepTooWide(let degrees)?:
            return String(localized: "\(name) can’t take a sweep this wide (\(Int(degrees.rounded()))°).", comment: "Mac Combine: a projection unavailable")
        case .verticalSweepTooWide(let degrees)?:
            return String(localized: "\(name) can’t take this much sky and ground (\(Int(degrees.rounded()))°).", comment: "Mac Combine: a projection unavailable")
        case nil:
            return name
        }
    }
}
