import CryptoKit
import Foundation
import ImageIO
import Photos
import ShotDexKit
import UIKit
import UniformTypeIdentifiers

/// The order a multi-photo run preloads its photos in: the one on screen,
/// then outward one step at a time, next before previous — the way a
/// filmstrip walk goes.
enum EditorPreloadOrder {
    static func indices(count: Int, around current: Int) -> [Int] {
        guard count > 0 else { return [] }
        let start = min(max(current, 0), count - 1)
        var order = [start]
        var step = 1
        while order.count < count {
            if start + step < count { order.append(start + step) }
            if start - step >= 0 { order.append(start - step) }
            step += 1
        }
        return order
    }
}

/// What a cached preview was drawn from. Two recipes that encode the same
/// draw the same picture, so the encoding is the key.
enum EditorPreviewFingerprint {
    static func of(_ recipe: PhotoEditRecipe) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(recipe) else { return UUID().uuidString }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// The cache's bookkeeping, apart from the files: which preview file belongs
/// to which photo, and which recipe it was drawn with. Pure, so what counts
/// as a hit is tested without a disk or a photo library.
///
/// `stamp` is the photo's modification date. A photo changed in the library
/// since it was cached is a different photo, and its whole entry goes.
struct EditorPreviewIndex {
    enum EditedLookup: Equatable {
        /// Drawn with exactly the recipe the photo will open with.
        case hit(file: String, fingerprint: String)
        /// This photo, but an older edit of it: a placeholder, not the answer.
        case stale(file: String)
        case miss
    }

    private struct Entry {
        var stamp: Double
        /// The photo's own saved recipe, which is what it opens with when the
        /// run holds no draft for it.
        var baselineFingerprint: String?
        var edited: (fingerprint: String, file: String)?
        var original: (optionID: String, file: String)?
        /// A recipe the preloader could not draw on its own (text tokens,
        /// Upright still to solve) — it is not tried again.
        var skippedFingerprint: String?

        var files: [String] {
            Array(Set([edited?.file, original?.file].compactMap { $0 }))
        }
    }

    private var entries: [String: Entry] = [:]

    var files: Set<String> {
        Set(entries.values.flatMap(\.files))
    }

    /// The entry for this photo at this stamp, starting over — and handing
    /// back the old files — when the stamp moved.
    private mutating func entry(_ assetID: String, stamp: Double, obsolete: inout [String]) -> Entry {
        if let existing = entries[assetID] {
            if existing.stamp == stamp { return existing }
            obsolete += existing.files
        }
        return Entry(stamp: stamp)
    }

    private func unreferenced(_ candidates: [String?], by entry: Entry) -> [String] {
        let live = Set(entry.files)
        return Array(Set(candidates.compactMap { $0 }).subtracting(live))
    }

    mutating func recordEdited(
        assetID: String,
        stamp: Double,
        baselineFingerprint: String,
        fingerprint: String,
        file: String
    ) -> [String] {
        var obsolete: [String] = []
        var current = entry(assetID, stamp: stamp, obsolete: &obsolete)
        let previous = current.edited?.file
        current.baselineFingerprint = baselineFingerprint
        current.edited = (fingerprint, file)
        entries[assetID] = current
        return obsolete + unreferenced([previous], by: current)
    }

    mutating func recordOriginal(assetID: String, stamp: Double, optionID: String, file: String) -> [String] {
        var obsolete: [String] = []
        var current = entry(assetID, stamp: stamp, obsolete: &obsolete)
        let previous = current.original?.file
        current.original = (optionID, file)
        entries[assetID] = current
        return obsolete + unreferenced([previous], by: current)
    }

    /// What the photo opens with when there is no draft, learned by whoever
    /// last opened its session.
    mutating func recordBaseline(assetID: String, stamp: Double, fingerprint: String) {
        var obsolete: [String] = []
        var current = entry(assetID, stamp: stamp, obsolete: &obsolete)
        current.baselineFingerprint = fingerprint
        entries[assetID] = current
    }

    mutating func markSkipped(assetID: String, stamp: Double, fingerprint: String) {
        guard var current = entries[assetID], current.stamp == stamp else { return }
        current.skippedFingerprint = fingerprint
        entries[assetID] = current
    }

    /// `draftFingerprint` is the run's draft for this photo, nil when it has
    /// none — then the photo opens on its saved recipe.
    func editedLookup(assetID: String, stamp: Double, draftFingerprint: String?) -> EditedLookup {
        guard let current = entries[assetID], current.stamp == stamp, let edited = current.edited else {
            return .miss
        }
        let expected = draftFingerprint ?? current.baselineFingerprint
        return edited.fingerprint == expected
            ? .hit(file: edited.file, fingerprint: edited.fingerprint)
            : .stale(file: edited.file)
    }

    func originalFile(assetID: String, stamp: Double, optionID: String) -> String? {
        guard let current = entries[assetID], current.stamp == stamp,
              let original = current.original, original.optionID == optionID
        else { return nil }
        return original.file
    }

    /// Whether the preloader still has work on this photo: an original, and
    /// an edited preview for the recipe it will open with (or a recorded
    /// reason it cannot draw one).
    func needsPreload(assetID: String, stamp: Double, draftFingerprint: String?) -> Bool {
        guard let current = entries[assetID], current.stamp == stamp, current.original != nil else {
            return true
        }
        let expected = draftFingerprint ?? current.baselineFingerprint
        guard let expected else { return true }
        if current.edited?.fingerprint == expected { return false }
        return current.skippedFingerprint != expected
    }

    mutating func remove(assetID: String) -> [String] {
        entries.removeValue(forKey: assetID)?.files ?? []
    }

    mutating func removeAll() {
        entries.removeAll()
    }
}

/// Keys in use order, oldest first, never more than `capacity`.
struct EditorRecentList<Key: Hashable> {
    let capacity: Int
    private(set) var keys: [Key] = []

    init(capacity: Int) {
        self.capacity = max(0, capacity)
    }

    /// Marks `key` as just used. Returns what fell off the far end.
    mutating func touch(_ key: Key) -> [Key] {
        keys.removeAll { $0 == key }
        keys.append(key)
        var evicted: [Key] = []
        while keys.count > capacity {
            evicted.append(keys.removeFirst())
        }
        return evicted
    }

    mutating func remove(_ key: Key) {
        keys.removeAll { $0 == key }
    }

    mutating func removeAll() {
        keys.removeAll()
    }
}

/// A cached preview and whether it is the answer or only a stand-in.
struct EditorCachedPreview {
    let image: UIImage
    let fingerprint: String?
    /// Drawn with the recipe the photo opens with. False: an older edit of the
    /// same photo, good enough to look at while the real one renders.
    let isCurrent: Bool
}

/// Full-quality previews of every photo in a multi-photo run, on disk for the
/// length of the run (FS-03.09b §2).
///
/// A photo's preview used to exist only while it was on the canvas, so every
/// tap on the filmstrip — including a tap back to the photo the user was on a
/// second earlier — opened the original again and sat behind "Loading
/// full-quality preview…". Here each photo keeps its 2400px edited preview
/// and its unedited one as files (~1 MB each) in one temporary directory;
/// memory holds only the last few decoded, around the photo on screen. The
/// directory goes when the editor closes.
@MainActor
final class EditorPreviewCache {
    private let directory: URL
    private var index = EditorPreviewIndex()
    private var memory: [String: UIImage] = [:]
    private var recent: EditorRecentList<String>
    /// Bumped by `clear()` and `invalidate`: a write that was in flight when
    /// it ran must not put an entry back.
    private var generation = 0
    private var invalidations: [String: Int] = [:]
    /// Photos whose previews are being written right now: the preloader must
    /// not draw them again while the files are still on their way.
    private var pendingStores: [String: Int] = [:]

    init(directory: URL? = nil, memoryCapacity: Int = 3) {
        self.directory = directory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("ShotDexPhoto-Previews-\(UUID().uuidString)", isDirectory: true)
        recent = EditorRecentList(capacity: memoryCapacity)
    }

    static func stamp(of asset: PHAsset) -> Double {
        asset.modificationDate?.timeIntervalSince1970 ?? 0
    }

    // MARK: Reads

    /// A preview already decoded — the same-frame path for a tap back to a
    /// photo the user has just left.
    func memoryEditedPreview(assetID: String, stamp: Double, draft: PhotoEditRecipe?) -> EditorCachedPreview? {
        let lookup = index.editedLookup(
            assetID: assetID,
            stamp: stamp,
            draftFingerprint: draft.map(EditorPreviewFingerprint.of)
        )
        switch lookup {
        case let .hit(file, fingerprint):
            guard let image = memoryImage(file) else { return nil }
            return EditorCachedPreview(image: image, fingerprint: fingerprint, isCurrent: true)
        case let .stale(file):
            guard let image = memoryImage(file) else { return nil }
            return EditorCachedPreview(image: image, fingerprint: nil, isCurrent: false)
        case .miss:
            return nil
        }
    }

    /// The preview from memory or, failing that, from disk (decoded off the
    /// main actor).
    func editedPreview(assetID: String, stamp: Double, draft: PhotoEditRecipe?) async -> EditorCachedPreview? {
        if let inMemory = memoryEditedPreview(assetID: assetID, stamp: stamp, draft: draft) {
            return inMemory
        }
        let lookup = index.editedLookup(
            assetID: assetID,
            stamp: stamp,
            draftFingerprint: draft.map(EditorPreviewFingerprint.of)
        )
        switch lookup {
        case let .hit(file, fingerprint):
            guard let image = await image(file) else { return nil }
            return EditorCachedPreview(image: image, fingerprint: fingerprint, isCurrent: true)
        case let .stale(file):
            guard let image = await image(file) else { return nil }
            return EditorCachedPreview(image: image, fingerprint: nil, isCurrent: false)
        case .miss:
            return nil
        }
    }

    func originalPreview(assetID: String, stamp: Double, optionID: String) async -> UIImage? {
        guard let file = index.originalFile(assetID: assetID, stamp: stamp, optionID: optionID) else { return nil }
        return await image(file)
    }

    func hasOriginal(assetID: String, stamp: Double, optionID: String) -> Bool {
        index.originalFile(assetID: assetID, stamp: stamp, optionID: optionID) != nil
    }

    func needsPreload(assetID: String, stamp: Double, draft: PhotoEditRecipe?) -> Bool {
        guard pendingStores[assetID] == nil else { return false }
        return index.needsPreload(
            assetID: assetID,
            stamp: stamp,
            draftFingerprint: draft.map(EditorPreviewFingerprint.of)
        )
    }

    // MARK: Writes

    /// Keeps a photo's previews. `edited` and `original` may be the same
    /// image — an unedited photo — and are then one file. `baseline` is the
    /// photo's saved recipe, what it opens with when the run has no draft.
    /// `keepsInMemory` false for photos far from the one on screen: the disk
    /// is the cache, memory only the neighbourhood. False when nothing could
    /// be kept — a write failed, or the run closed meanwhile.
    @discardableResult
    func store(
        assetID: String,
        stamp: Double,
        baseline: PhotoEditRecipe,
        edited: (image: UIImage, recipe: PhotoEditRecipe)?,
        original: (image: UIImage, optionID: String)?,
        skipped: PhotoEditRecipe? = nil,
        keepsInMemory: Bool = true
    ) async -> Bool {
        let startGeneration = generation
        let startInvalidation = invalidations[assetID]
        pendingStores[assetID, default: 0] += 1
        defer {
            pendingStores[assetID, default: 1] -= 1
            if pendingStores[assetID] == 0 { pendingStores.removeValue(forKey: assetID) }
        }
        let shared = edited != nil && edited?.image === original?.image
        var editedFile: String?
        var originalFile: String?
        if let edited, let cgImage = edited.image.cgImage {
            editedFile = await write(cgImage)
        }
        if shared {
            originalFile = editedFile
        } else if let original, let cgImage = original.image.cgImage {
            originalFile = await write(cgImage)
        }
        let wroteAll = (edited == nil || editedFile != nil) && (original == nil || originalFile != nil)
        guard generation == startGeneration, invalidations[assetID] == startInvalidation, wroteAll else {
            deleteFiles([editedFile, originalFile].compactMap { $0 })
            return false
        }
        var obsolete: [String] = []
        let baselineFingerprint = EditorPreviewFingerprint.of(baseline)
        index.recordBaseline(assetID: assetID, stamp: stamp, fingerprint: baselineFingerprint)
        if let original, let originalFile {
            obsolete += index.recordOriginal(assetID: assetID, stamp: stamp, optionID: original.optionID, file: originalFile)
            if keepsInMemory { remember(original.image, as: originalFile) }
        }
        if let edited, let editedFile {
            obsolete += index.recordEdited(
                assetID: assetID,
                stamp: stamp,
                baselineFingerprint: baselineFingerprint,
                fingerprint: EditorPreviewFingerprint.of(edited.recipe),
                file: editedFile
            )
            if keepsInMemory { remember(edited.image, as: editedFile) }
        }
        if let skipped {
            index.markSkipped(assetID: assetID, stamp: stamp, fingerprint: EditorPreviewFingerprint.of(skipped))
        }
        deleteFiles(obsolete)
        return true
    }

    /// Drops one photo — it was saved, and the library's version is now the
    /// one to show.
    func invalidate(assetID: String) {
        invalidations[assetID, default: 0] += 1
        deleteFiles(index.remove(assetID: assetID))
    }

    /// Short of memory: the decoded previews go, the files stay.
    func handleMemoryWarning() {
        memory.removeAll()
        recent.removeAll()
    }

    /// The editor closed: every file goes.
    func clear() {
        generation += 1
        index.removeAll()
        memory.removeAll()
        recent.removeAll()
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Files

    private func memoryImage(_ file: String) -> UIImage? {
        guard let image = memory[file] else { return nil }
        _ = recent.touch(file)
        return image
    }

    private func remember(_ image: UIImage, as file: String) {
        memory[file] = image
        for evicted in recent.touch(file) {
            memory.removeValue(forKey: evicted)
        }
    }

    private func image(_ file: String) async -> UIImage? {
        if let inMemory = memoryImage(file) { return inMemory }
        let url = directory.appendingPathComponent(file)
        let startGeneration = generation
        let decoded = await Task.detached(priority: .userInitiated) {
            Self.decode(url)
        }.value
        guard let decoded, generation == startGeneration,
              index.files.contains(file)
        else { return nil }
        let image = UIImage(cgImage: decoded)
        remember(image, as: file)
        return image
    }

    private func write(_ image: CGImage) async -> String? {
        let directory = directory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        return await Task.detached(priority: .utility) {
            Self.encode(image, into: directory)
        }.value
    }

    private func deleteFiles(_ files: [String]) {
        let live = index.files
        for file in Set(files) where !live.contains(file) {
            memory.removeValue(forKey: file)
            recent.remove(file)
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    /// HEIC at 0.9: a 2400px frame is about 1 MB, and the difference from the
    /// render is below what the eye finds on a phone. JPEG where the encoder
    /// is missing.
    nonisolated private static func encode(_ image: CGImage, into directory: URL) -> String? {
        for type in [UTType.heic, UTType.jpeg] {
            let name = "\(UUID().uuidString).\(type.preferredFilenameExtension ?? "img")"
            let url = directory.appendingPathComponent(name)
            guard let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                type.identifier as CFString,
                1,
                nil
            ) else { continue }
            let options = [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
            CGImageDestinationAddImage(destination, image, options)
            if CGImageDestinationFinalize(destination) { return name }
            try? FileManager.default.removeItem(at: url)
        }
        return nil
    }

    nonisolated private static func decode(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        // Decoded here, off the main actor, not lazily on the first draw.
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        return CGImageSourceCreateImageAtIndex(source, 0, options)
    }
}
