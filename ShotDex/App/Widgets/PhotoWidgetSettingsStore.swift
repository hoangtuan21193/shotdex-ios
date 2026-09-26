import Foundation
import Observation
import WidgetKit

/// The photo widgets' settings as the app edits them: one observable value
/// backed by the App Group file the widgets read.
///
/// `UserDefaults` is not an option here — a widget is a second process, and
/// the app's own defaults are not in its container — so this is a small JSON
/// file beside the pictures it describes, like every other widget payload.
@MainActor
@Observable
final class PhotoWidgetSettingsStore {
    private(set) var file: PhotoWidgetSettingsFile

    /// The widget whose pictures are being re-rendered, so Settings can say so
    /// rather than looking as if nothing happened.
    private(set) var renderingDesignId: String?

    private let photoLibrary: PhotoLibraryService
    /// Coalesces the writes a slider produces: a drag publishes on every
    /// frame, and each save is a file write plus a widget reload.
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var renderTasks: [String: Task<Void, Never>] = [:]

    init(photoLibrary: PhotoLibraryService) {
        self.photoLibrary = photoLibrary
        self.file = PhotoWidgetSettingsFile.read()
        adoptLegacyFilesIfNeeded()
    }

    /// Writes the migrated settings out and clears what the earlier versions
    /// left in the container: the clock-only settings file this one grew out
    /// of, and the Gear widget's digest and cover, which nothing reads now
    /// that the widget is gone.
    private func adoptLegacyFilesIfNeeded() {
        guard let container = WidgetSharedContainer.url else { return }
        let manager = FileManager.default
        let current = container.appendingPathComponent(PhotoWidgetSettingsFile.fileName)
        if !manager.fileExists(atPath: current.path) {
            saveNow()
        }
        for name in ["clock-settings.json", "gear-snapshot.json", "gear-cover.jpg"] {
            try? manager.removeItem(at: container.appendingPathComponent(name))
        }
        // The clock's pictures moved to a per-widget folder.
        try? manager.removeItem(at: container.appendingPathComponent("clock", isDirectory: true))
        // The four fixed kinds rendered into four folders. Designs render into
        // their own, and the loop below brings the pictures back.
        for name in PhotoWidgetSettingsFile.legacyDirectoryNames {
            try? manager.removeItem(at: container.appendingPathComponent(name, isDirectory: true))
        }

        // Anything with a source but no pictures — a migrated clock, or a
        // widget whose files were cleared — is rendered again rather than
        // showing black until the user happens to open its settings. So is
        // anything rendered at the old, softer size.
        let target = Int(WidgetImageRenderer.maxPixels)
        for design in file.designs where design.settings.source != .none {
            let snapshot = PhotoWidgetSnapshot.read(designId: design.id)
            if snapshot.frames.isEmpty
                || snapshot.isBelow(pixels: target, rendererVersion: WidgetImageRenderer.version) {
                renderPhotos(for: design.id)
            }
        }
    }

    var designs: [PhotoWidgetDesign] { file.designs }

    func settings(for designId: String) -> PhotoWidgetSettings { file[designId] }

    func design(id: String) -> PhotoWidgetDesign { file.design(id: id) }

    /// Picks up what the Home Screen's widget menu wrote while the app was
    /// away. The menu and this screen edit one set of settings, so the app has
    /// to re-read them rather than trust the copy it loaded at launch.
    ///
    /// Anything being edited here right now wins: a pending save is the newer
    /// word, and reloading over it would undo a slider mid-drag.
    func reloadFromDisk() {
        guard saveTask == nil else { return }
        let onDisk = PhotoWidgetSettingsFile.read()
        guard onDisk != file else { return }
        file = onDisk
    }

    func isRendering(_ designId: String) -> Bool { renderingDesignId == designId }

    /// Applies a change and schedules the write. `rendersPhotos` is for the
    /// edits that change *which* picture is shown, not how it is labelled.
    func update(
        _ designId: String,
        rendersPhotos: Bool = false,
        _ change: (inout PhotoWidgetSettings) -> Void
    ) {
        var updated = file[designId]
        change(&updated)
        updated.timeFormat = PhotoWidgetFormat.sanitized(pattern: updated.timeFormat)
        updated.dateFormat = PhotoWidgetFormat.sanitized(pattern: updated.dateFormat)
        updated.timeSize = updated.timeSize.clamped(to: PhotoWidgetSettings.timeSizeRange)
        updated.dateSize = updated.dateSize.clamped(to: PhotoWidgetSettings.dateSizeRange)
        updated.maximumEventCount = min(
            max(updated.maximumEventCount, PhotoWidgetSettings.eventCountRange.lowerBound),
            PhotoWidgetSettings.eventCountRange.upperBound
        )
        if !WidgetTextColor.isStorable(hex: updated.textColorHex) {
            updated.textColorHex = WidgetTextColor.fallbackHex
        }
        guard updated != file[designId] else { return }
        let sourceChanged = updated.source != file[designId].source
        file[designId] = updated
        scheduleSave()
        if rendersPhotos || sourceChanged { renderPhotos(for: designId) }
    }

    /// Re-renders one widget's pictures — after its source changed, and from
    /// the Settings row that offers it when an album has new photos in it.
    func renderPhotos(for designId: String) {
        renderTasks[designId]?.cancel()
        renderingDesignId = designId
        let settings = file[designId]
        let writer = PhotoWidgetSnapshotWriter(photoLibrary: photoLibrary)
        renderTasks[designId] = Task { [weak self] in
            await writer.write(designId: designId, settings: settings)
            guard !Task.isCancelled else { return }
            if self?.renderingDesignId == designId { self?.renderingDesignId = nil }
        }
    }

    // MARK: Designs

    /// Adds a design and returns it, so the caller can push straight into it.
    @discardableResult
    func addDesign(name: String? = nil) -> PhotoWidgetDesign {
        let design = PhotoWidgetDesign.makeDefault(name: name ?? nextUntitledName())
        file.designs.append(design)
        scheduleSave()
        return design
    }

    /// Copies a design, pictures and all — the copy points at the same source,
    /// so it renders its own frames rather than sharing a folder.
    @discardableResult
    func duplicateDesign(id: String) -> PhotoWidgetDesign? {
        guard let index = file.designs.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = file.designs[index]
        copy.id = UUID().uuidString
        copy.name = copiedName(of: copy.name)
        file.designs.insert(copy, at: index + 1)
        scheduleSave()
        if copy.settings.source != .none { renderPhotos(for: copy.id) }
        return copy
    }

    func renameDesign(id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = file.designs.firstIndex(where: { $0.id == id }),
              file.designs[index].name != trimmed
        else { return }
        file.designs[index].name = trimmed
        scheduleSave()
    }

    /// Removes a design and the pictures rendered for it. Refused for the last
    /// one: a placed widget has to have something to read, and an empty list
    /// would leave every widget on the Home Screen blank.
    func removeDesign(id: String) {
        guard file.designs.count > 1,
              let index = file.designs.firstIndex(where: { $0.id == id })
        else { return }
        let design = file.designs.remove(at: index)
        renderTasks[design.id]?.cancel()
        renderTasks[design.id] = nil
        if renderingDesignId == design.id { renderingDesignId = nil }
        if let container = WidgetSharedContainer.url {
            try? FileManager.default.removeItem(
                at: container.appendingPathComponent(design.directoryName, isDirectory: true)
            )
        }
        scheduleSave()
    }

    func moveDesigns(fromOffsets source: IndexSet, toOffset destination: Int) {
        file.designs.move(fromOffsets: source, toOffset: destination)
        scheduleSave()
    }

    /// "My Widget", then "My Widget 2" — the name is a starting point, not a
    /// question the user has to answer before they can see anything.
    private func nextUntitledName() -> String {
        let base = "My Widget"
        let taken = Set(file.designs.map(\.name))
        guard taken.contains(base) else { return base }
        var index = 2
        while taken.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }

    private func copiedName(of name: String) -> String {
        let taken = Set(file.designs.map(\.name))
        var candidate = "\(name) Copy"
        var index = 2
        while taken.contains(candidate) {
            candidate = "\(name) Copy \(index)"
            index += 1
        }
        return candidate
    }

    /// Writes the file the widgets read. Called on a debounce by `update`, and
    /// directly when a settings screen is left.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard let container = WidgetSharedContainer.url else { return }
        try? WidgetSharedContainer.encode(
            file,
            to: container.appendingPathComponent(PhotoWidgetSettingsFile.fileName)
        )
        WidgetCenter.shared.reloadTimelines(ofKind: PhotoWidgetIdentity.widgetKind)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
