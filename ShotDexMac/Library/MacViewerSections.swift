import Accelerate
import MapKit
import Photos
import ShotDexKit
import SwiftUI

/// The open photo's histogram (board `MAC_Viewer`): red, green and blue as
/// soft overlapping areas, read from a 256px rendition off the main actor.
struct MacViewerHistogram: View {
    let photoId: String
    var picture: ((String) -> CGImage?)?
    @Environment(MacDependencies.self) private var dependencies
    @State private var bins: MacHistogramBins?

    var body: some View {
        Canvas { context, size in
            guard let bins else { return }
            // The system's red, green and blue at 0.40, and the luminance as a line (board).
            for (channel, color) in [(bins.blue, Color(nsColor: .systemBlue)),
                                     (bins.green, Color(nsColor: .systemGreen)),
                                     (bins.red, Color(nsColor: .systemRed))] {
                context.fill(Self.area(channel, peak: bins.peak, in: size), with: .color(color.opacity(0.40)))
            }
            let luma = zip(zip(bins.red, bins.green), bins.blue).map { ($0.0 + $0.1 + $1) / 3 }
            context.stroke(Self.area(luma, peak: bins.peak, in: size), with: .style(.secondary), lineWidth: 1)
        }
        .frame(height: 56)
        .background(MacTheme.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(String(localized: "Histogram", comment: "Mac viewer inspector section"))
        .accessibilityValue(bins.map(MacHistogramBins.spoken) ?? "")
        .task(id: photoId) { await load() }
    }

    private static func area(_ values: [Float], peak: Float, in size: CGSize) -> Path {
        var path = Path()
        guard values.count > 1, peak > 0 else { return path }
        path.move(to: CGPoint(x: 0, y: size.height))
        for (index, value) in values.enumerated() {
            let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
            path.addLine(to: CGPoint(x: x, y: size.height * (1 - CGFloat(min(value / peak, 1)) * 0.92)))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        return path
    }

    private func load() async {
        // Never the last photo's shape under this one.
        bins = nil
        let image: CGImage?
        if let picture {
            image = picture(photoId)
        } else {
            image = await MacViewerThumbnail.load(photoId, side: 256, dependencies: dependencies)
        }
        guard !Task.isCancelled, let image else { return }
        let computed = await Task.detached(priority: .utility) { MacHistogramBins(image) }.value
        guard !Task.isCancelled else { return }
        bins = computed
    }
}

/// 64 bins per channel, smoothed a little; the tallest bin of any channel
/// scales them all, so a channel's share stays visible.
struct MacHistogramBins: Sendable, Equatable {
    var red: [Float]
    var green: [Float]
    var blue: [Float]
    var peak: Float

    init?(_ image: CGImage) {
        let width = 128, height = max(1, image.height * 128 / max(image.width, 1))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        // The context draws through the buffer only inside this closure.
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var red = [Float](repeating: 0, count: 64), green = red, blue = red
        for index in stride(from: 0, to: pixels.count, by: 4) {
            red[Int(pixels[index]) >> 2] += 1
            green[Int(pixels[index + 1]) >> 2] += 1
            blue[Int(pixels[index + 2]) >> 2] += 1
        }
        func smooth(_ values: [Float]) -> [Float] {
            values.indices.map { index in
                let range = max(0, index - 1)...min(values.count - 1, index + 1)
                return range.reduce(0) { $0 + values[$1] } / Float(range.count)
            }
        }
        self.red = smooth(red)
        self.green = smooth(green)
        self.blue = smooth(blue)
        // The extremes (pure black, clipped white) would flatten everything else.
        peak = (self.red + self.green + self.blue).enumerated()
            .filter { $0.offset % 64 != 0 && $0.offset % 64 != 63 }.map(\.element).max() ?? 1
    }

    /// "Mostly dark", "Mostly bright" or "Even" — what a glance at it says.
    static func spoken(_ bins: MacHistogramBins) -> String {
        let luma = zip(zip(bins.red, bins.green), bins.blue).map { ($0.0 + $0.1 + $1) / 3 }
        let total = luma.reduce(0, +)
        guard total > 0 else { return "" }
        let dark = luma.prefix(21).reduce(0, +) / total, bright = luma.suffix(21).reduce(0, +) / total
        if dark > 0.5 { return String(localized: "Mostly dark", comment: "VoiceOver: the histogram's shape") }
        if bright > 0.5 { return String(localized: "Mostly bright", comment: "VoiceOver: the histogram's shape") }
        return String(localized: "Even", comment: "VoiceOver: the histogram's shape")
    }
}

/// The PhotoKit request a cancellation handler cancels, and the
/// continuation it must still resume: PhotoKit need not call back after a
/// cancel. Main actor only.
@MainActor
final class MacRequestBox {
    var id: PHImageRequestID?
    var continuation: CheckedContinuation<CGImage?, Never>?

    func resume(_ image: CGImage?) {
        continuation?.resume(returning: image)
        continuation = nil
    }
}

/// A small rendition of a photo: PhotoKit, else its file; nil when neither.
enum MacViewerThumbnail {
    @MainActor
    static func load(_ id: String, side: CGFloat, dependencies: MacDependencies) async -> CGImage? {
        if let asset = await Task.detached(priority: .utility, operation: { PhotoLibraryService.fetchAssets(ids: [id]).first }).value {
            guard !Task.isCancelled else { return nil }
            // A step away cancels the request and ends the wait, whether or not PhotoKit answers.
            let request = MacRequestBox()
            return await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    request.continuation = continuation
                    request.id = dependencies.photoLibrary.requestThumbnail(for: asset, targetSize: CGSize(width: side, height: side),
                                                                            contentMode: .aspectFit, allowNetwork: false) { result, delivery in
                        // The degraded preview first, then the real one: only the real one counts.
                        guard result == nil || !delivery.isDegraded else { return }
                        request.resume(result?.cgImage)
                    }
                }
            } onCancel: {
                Task { @MainActor in
                    if let id = request.id { dependencies.photoLibrary.cancelThumbnailRequest(id) }
                    request.resume(nil)
                }
            }
        }
        guard let path = try? await PhotoInfoQueries(database: dependencies.database).info(photoId: id).filePath else { return nil }
        let url = URL(fileURLWithPath: path)
        return await Task.detached(priority: .utility) { MacViewerPhoto.read(url, maxPixel: Int(side)) }.value
    }
}

/// Caption and Keywords (board): the caption saved as you type, a moment
/// after the last key and at once when the photo changes; keyword chips
/// with ×, and + Add Keyword turning into a field.
struct MacViewerCaptionKeywords: View {
    let photoId: String
    let info: PhotoInfoQueries.Info
    /// `info` is this photo's (not the last one's, still shown while it loads).
    var isCurrent = true
    /// A write landed: the inspector reads the photo again.
    var changed: () -> Void
    @Environment(MacDependencies.self) private var dependencies
    @State private var caption = ""
    @State private var savedCaption = ""
    @State private var loadedFor: String?
    @State private var pendingSave: Task<Void, Never>?
    @State private var keyword = ""
    @State private var addsKeyword = false
    @State private var failure: String?
    /// "Saved" for a moment after a write lands on the photo on screen.
    @State private var showsSaved = false
    /// Writes run one after another, so the last text typed is the one kept (as Get Info).
    @State private var lastWrite: Task<Void, Never>?
    @FocusState private var keywordFocused: Bool

    private var canWrite: Bool {
        #if DEBUG
        if MacDemoLibrary.isOn { return true }
        #endif
        return info.hasFileCopy || dependencies.captionKeywords != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(String(localized: "Add a Caption", comment: "Mac viewer: caption placeholder"), text: $caption, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(MacTheme.content, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(MacTheme.separator))
                .disabled(!canWrite || !isCurrent)
                .accessibilityLabel(String(localized: "Caption", comment: "Mac Get Info: field"))
                .onChange(of: caption) { _, text in scheduleSave(text) }
                .onSubmit { flush() }
                // Esc saves and hands ← → back to the viewer.
                .onExitCommand {
                    flush()
                    NotificationCenter.default.post(name: .macViewerTakeKeys, object: nil)
                }
            MacFlowLayout(spacing: 6) {
                ForEach(info.keywords, id: \.self) { name in
                    MacKeywordChip(name: name, count: 1, total: 1, removeFromAll: {
                        let id = photoId
                        if canWrite { run(id) { await $0.remove(name, from: [id]) } }
                    })
                }
                if addsKeyword {
                    TextField(String(localized: "Keyword", comment: "Mac viewer: new keyword field"), text: $keyword)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(.horizontal, 8)
                        .frame(width: 120, height: 22)
                        .background(MacTheme.content, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(MacTheme.separator))
                        .focused($keywordFocused)
                        .accessibilityLabel(String(localized: "Add Keyword", comment: "Mac Get Info: keyword field"))
                        .onSubmit { addKeyword() }
                        .onExitCommand { keyword = ""; addsKeyword = false }
                } else if canWrite {
                    Button { addsKeyword = true; keywordFocused = true } label: {
                        // 22 tall like the chips beside it; the plus in amber (board).
                        HStack(spacing: 4) {
                            Image(systemName: "plus").font(.system(size: 10, weight: .semibold)).foregroundStyle(MacTheme.accent)
                            Text("Add Keyword", comment: "Mac Get Info: keyword field").font(.system(size: 12))
                        }
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .overlay(Capsule().strokeBorder(MacTheme.separator, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                        .contentShape(Capsule())
                    }
                    .accessibilityLabel(String(localized: "Add Keyword", comment: "Mac Get Info: keyword field"))
                    .buttonStyle(.plain)
                }
            }
            if let failure {
                Text(failure).font(.system(size: 11)).foregroundStyle(MacTheme.redText)
            } else if showsSaved {
                Text("Saved", comment: "Mac viewer: the caption or keyword was written").font(.system(size: 11)).foregroundStyle(.secondary)
                    .transition(.opacity)
            } else if !canWrite {
                Text("Caption and keywords of photos in Photos can be changed from ShotDex on macOS 27 or later.",
                     comment: "Mac Get Info: Photos not writable here")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .onAppear { adopt() }
        .onChange(of: photoId) { old, _ in
            // Leaving a photo saves what was typed on it (a keyword too), then reads the next.
            flush(for: old)
            commitKeyword(for: old)
            loadedFor = nil
            adopt()
        }
        .onChange(of: isCurrent) { adopt() }
        .onChange(of: info.caption) { adopt(force: false) }
        .onDisappear { flush() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in flush() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in flush() }
    }

    /// A keyword typed but not returned goes in when the photo is left.
    private func commitKeyword(for id: String) {
        let text = keyword, wasAdding = addsKeyword
        keyword = ""
        addsKeyword = false
        guard wasAdding, !KeywordInput.split(text).isEmpty else { return }
        addKeyword(text, to: id)
    }

    private func adopt(force: Bool = true) {
        // Never the last photo's caption under this photo's id.
        guard isCurrent else { return }
        let text = info.caption ?? ""
        // A reload while typing keeps the typed words.
        guard force || loadedFor != photoId || caption == savedCaption else { return }
        loadedFor = photoId
        caption = text
        savedCaption = text
        keyword = ""
        addsKeyword = false
        failure = nil
    }

    private func scheduleSave(_ text: String) {
        guard loadedFor == photoId, text != savedCaption else { return }
        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            flush()
        }
    }

    private func flush(for id: String? = nil) {
        pendingSave?.cancel()
        pendingSave = nil
        let target = id ?? photoId
        guard loadedFor == target, caption != savedCaption else { return }
        let text = caption
        savedCaption = text
        run(target) { await $0.setCaption(text, for: target) }
    }

    private func addKeyword() {
        let text = keyword
        keyword = ""
        addsKeyword = false
        addKeyword(text, to: photoId)
    }

    private func addKeyword(_ text: String, to id: String) {
        guard !KeywordInput.split(text).isEmpty else { return }
        let suggestions = dependencies.filterSuggestions
        run(id) { editor in
            let catalog = await suggestions.load().keywords
            var outcome = MacKeywordEditor.Outcome.done
            for keyword in KeywordInput.keywords(from: text, existing: KeywordInput.spellings(catalog)) {
                outcome = outcome.combined(with: await editor.add(keyword, to: [id]))
            }
            return outcome
        }
    }

    private func run(_ id: String? = nil, _ write: @escaping @MainActor (MacKeywordEditor) async -> MacKeywordEditor.Outcome) {
        let editor = MacKeywordEditor(database: dependencies.database, captionKeywords: dependencies.captionKeywords,
                                      sidecarQueue: dependencies.sidecarQueue, filterSuggestions: dependencies.filterSuggestions)
        let target = id ?? photoId
        let previous = lastWrite
        lastWrite = Task {
            await previous?.value
            let outcome = await write(editor)
            // A write that failed after its photo was left still says so; the
            // rest is said and re-read only for the photo on screen (state read now).
            guard target == loadedFor else {
                if outcome != .done {
                    failure = String(localized: "The last photo’s caption or keyword couldn’t be saved.", comment: "Mac viewer: a write for the photo just left failed")
                }
                return
            }
            switch outcome {
            case .done:
                failure = nil
                withAnimation { showsSaved = true }
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    withAnimation { showsSaved = false }
                }
            case .skipped: failure = String(localized: "Photos didn’t take the change — it may not allow changes to this photo.", comment: "Mac Get Info: a Photos write skipped")
            case .failed: failure = String(localized: "The change couldn’t be saved.", comment: "Mac Get Info: a write failed")
            }
            changed()
        }
    }
}

/// Edits (board): a photo edited in ShotDex — "Edited in ShotDex · 7
/// adjustments", the original never touched — with Revert to Original
/// (asks first) and Copy Edits. Nothing for a photo without a ShotDex edit.
struct MacViewerEdits: View {
    let photoId: String
    /// Bumped by the inspector when the photo changed elsewhere: read again.
    var reloads = 0
    /// The recipe store holds edits of file copies; a Photos item keeps its own in Photos.
    let hasFileCopy: Bool
    @Environment(MacDependencies.self) private var dependencies
    @State private var recipe: PhotoEditRecipe?
    @State private var adjustments = 0
    @State private var loadedFor: String?
    @State private var revertFailed = false
    /// "Reverted to original" for a moment where the section was.
    @State private var reverted = false
    @State private var asksRevert = false
    @State private var copied = false

    var body: some View {
        // A VStack, not a Group: an empty Group is no view, and its .task never runs.
        VStack(spacing: 0) {
            if reverted, loadedFor == photoId {
                Text("Reverted to original", comment: "Mac viewer: Revert to Original finished")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let recipe, loadedFor == photoId, hasFileCopy || isDemo {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Edits", comment: "Mac viewer inspector section")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    HStack(spacing: 6) {
                        Circle().fill(MacTheme.accent).frame(width: 7, height: 7)
                        Text(String(AttributedString(localized: "Edited in ShotDex · ^[\(adjustments) adjustment](inflect: true)",
                                                     comment: "Mac viewer: a photo with a ShotDex edit").characters))
                            .font(.system(size: 13))
                    }
                    Text("Saved automatically · image file never edited", comment: "Mac viewer: ShotDex edits are a recipe beside the file")
                        .font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 14)
                    // Push buttons 28 on `fill` with label words (board, MAC_STYLE).
                    HStack(spacing: 8) {
                        Button(String(localized: "Revert to Original", comment: "Mac viewer: drop the ShotDex edit")) { asksRevert = true }
                        Button(copied ? String(localized: "Copied", comment: "Mac viewer: the edits are on the clipboard")
                                      : String(localized: "Copy Edits", comment: "Mac viewer: copy the look to paste on other photos")) {
                            dependencies.editClipboard.copy(from: recipe)
                            copied = true
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                copied = false
                            }
                        }
                    }
                    .buttonStyle(MacPushButtonStyle(isDefault: false))
                    if revertFailed {
                        Text("Couldn’t revert. Try again.", comment: "Mac viewer: Revert to Original failed")
                            .font(.system(size: 11)).foregroundStyle(MacTheme.redText)
                    }
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) { Divider() }
            } else if loadedFor == photoId, hasFileCopy || isDemo, dependencies.editClipboard.hasContent {
                // Copied from another photo: where the copy goes.
                Button(String(localized: "Paste Edits", comment: "Mac viewer: lay the copied look on this photo")) { paste() }
                    .buttonStyle(MacPushButtonStyle(isDefault: false))
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottom) { Divider() }
            }
        }
        .task(id: "\(photoId)-\(reloads)") {
            copied = false
            reverted = false
            let store = PhotoRecipeStore(database: dependencies.database), id = photoId
            revertFailed = false
            let read = await Task.detached(priority: .utility) { () -> (PhotoEditRecipe?, Int) in
                let recipe = try? store.recipe(photoId: id)
                return (recipe, recipe.map(MacEditCount.count) ?? 0)
            }.value
            guard !Task.isCancelled else { return }
            (recipe, adjustments) = read
            loadedFor = id
        }
        .confirmationDialog(String(localized: "Revert to the Original?", comment: "Mac viewer: Revert to Original confirmation title"),
                            isPresented: $asksRevert) {
            Button(String(localized: "Revert to Original", comment: "Mac viewer: drop the ShotDex edit"), role: .destructive) { revert() }
            Button(String(localized: "Cancel", comment: "Mac sheet: cancel"), role: .cancel) {}
        } message: {
            Text(String(AttributedString(localized: "^[\(adjustments) adjustment](inflect: true) will be removed. This can’t be undone. The image file itself was never changed.",
                                         comment: "Mac viewer: what Revert to Original does").characters))
        }
    }

    private var isDemo: Bool {
        #if DEBUG
        return MacDemoLibrary.isOn
        #else
        return false
        #endif
    }

    private func revert() {
        let store = PhotoRecipeStore(database: dependencies.database), sidecars = dependencies.sidecarQueue, id = photoId
        Task {
            // Off the main actor; an identity recipe removes the row, and the
            // sidecar is rewritten so the edit can't come back from it.
            let ok = await Task.detached(priority: .userInitiated) { (try? store.save(.identity, photoId: id)) != nil }.value
            if ok { await sidecars.schedule([id]) }
            guard id == loadedFor else { return }
            if ok {
                recipe = nil
                reverted = true
            } else {
                revertFailed = true
            }
        }
    }

    /// The copied look over this photo's recipe (its crop and layers kept), saved like an edit.
    private func paste() {
        let store = PhotoRecipeStore(database: dependencies.database), sidecars = dependencies.sidecarQueue, id = photoId
        let clipboard = dependencies.editClipboard
        Task {
            let current = await Task.detached(priority: .userInitiated) { (try? store.recipe(photoId: id)) ?? .identity }.value
            let pasted = clipboard.paste(onto: current)
            let ok = await Task.detached(priority: .userInitiated) { (try? store.save(pasted, photoId: id)) != nil }.value
            if ok { await sidecars.schedule([id]) }
            guard id == loadedFor else { return }
            if ok {
                recipe = pasted
                adjustments = MacEditCount.count(pasted)
                reverted = false
            } else {
                revertFailed = true
            }
        }
    }
}

/// How many things an edit changes: each adjustment moved off its default,
/// plus each other part of the recipe (crop, look, masks…) that is not
/// identity.
enum MacEditCount {
    static func count(_ recipe: PhotoEditRecipe) -> Int {
        // Each slider off zero…
        var count = PhotoAdjustmentKind.allCases.filter { abs(recipe.adjustments[$0] - PhotoAdjustments.zero[$0]) > 0.0001 }.count
        // …and one more for everything else (crop, masks, layers), provenance
        // (which source it was made from) never counted.
        var rest = recipe
        rest.adjustments = .zero
        rest.source = PhotoEditRecipe.identity.source
        rest.sourceFilename = nil
        rest.sourceAssetIdentifier = nil
        if rest != .identity { count += 1 }
        return max(count, 1)
    }
}

/// Location (board): a small map with the pin, the place's name and its
/// coordinates; ↗ opens Maps there.
struct MacViewerLocation: View {
    let coordinate: CLLocationCoordinate2D
    let place: MacInfoText.Place

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1_500, longitudinalMeters: 1_500)),
                interactionModes: []) {
                Marker("", coordinate: coordinate).tint(MacTheme.accent)
            }
            .frame(height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            // The map is the bigger target for the same thing as ↗.
            .contentShape(Rectangle())
            .onTapGesture { Self.showOnMap(coordinate, name: place.name) }
            .accessibilityHidden(true)
            if let name = place.name { Text(name).font(.system(size: 13)) }
            if let coordinates = place.coordinates {
                Text(coordinates).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit().textSelection(.enabled)
            }
        }
    }

    /// Maps at the pin, named after the place when it has one.
    static func showOnMap(_ coordinate: CLLocationCoordinate2D, name: String?) {
        var components = URLComponents(string: "maps://")
        components?.queryItems = [URLQueryItem(name: "ll", value: "\(coordinate.latitude),\(coordinate.longitude)"),
                                  URLQueryItem(name: "q", value: name ?? String(localized: "Photo", comment: "Mac viewer: Maps pin name for a photo"))]
        if let url = components?.url { NSWorkspace.shared.open(url) }
    }
}

extension Notification.Name {
    /// A field in the viewer's inspector let go of the keyboard: ← → and the
    /// mark keys belong to the viewer again.
    static let macViewerTakeKeys = Notification.Name("macViewerTakeKeys")
}
