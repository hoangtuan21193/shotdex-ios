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
    private(set) var renderingKind: PhotoWidgetKind?

    private let photoLibrary: PhotoLibraryService
    /// Coalesces the writes a slider produces: a drag publishes on every
    /// frame, and each save is a file write plus a widget reload.
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var renderTasks: [PhotoWidgetKind: Task<Void, Never>] = [:]

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

        // Anything with a source but no pictures — a migrated clock, or a
        // widget whose files were cleared — is rendered again rather than
        // showing black until the user happens to open its settings.
        for kind in PhotoWidgetKind.allCases where file[kind].source != .none {
            if PhotoWidgetSnapshot.read(kind: kind).frames.isEmpty {
                renderPhotos(for: kind)
            }
        }
    }

    func settings(for kind: PhotoWidgetKind) -> PhotoWidgetSettings { file[kind] }

    func isRendering(_ kind: PhotoWidgetKind) -> Bool { renderingKind == kind }

    /// Applies a change and schedules the write. `rendersPhotos` is for the
    /// edits that change *which* picture is shown, not how it is labelled.
    func update(
        _ kind: PhotoWidgetKind,
        rendersPhotos: Bool = false,
        _ change: (inout PhotoWidgetSettings) -> Void
    ) {
        var updated = file[kind]
        change(&updated)
        updated.timeFormat = PhotoWidgetFormat.sanitized(pattern: updated.timeFormat)
        updated.dateFormat = PhotoWidgetFormat.sanitized(pattern: updated.dateFormat)
        updated.timeSize = updated.timeSize.clamped(to: PhotoWidgetSettings.timeSizeRange)
        updated.dateSize = updated.dateSize.clamped(to: PhotoWidgetSettings.dateSizeRange)
        updated.maximumEventCount = min(
            max(updated.maximumEventCount, PhotoWidgetSettings.eventCountRange.lowerBound),
            PhotoWidgetSettings.eventCountRange.upperBound
        )
        if !WidgetTextColor.isValid(hex: updated.textColorHex) {
            updated.textColorHex = WidgetTextColor.fallbackHex
        }
        guard updated != file[kind] else { return }
        let sourceChanged = updated.source != file[kind].source
        file[kind] = updated
        scheduleSave()
        if rendersPhotos || sourceChanged { renderPhotos(for: kind) }
    }

    /// Re-renders one widget's pictures — after its source changed, and from
    /// the Settings row that offers it when an album has new photos in it.
    func renderPhotos(for kind: PhotoWidgetKind) {
        renderTasks[kind]?.cancel()
        renderingKind = kind
        let settings = file[kind]
        let writer = PhotoWidgetSnapshotWriter(photoLibrary: photoLibrary)
        renderTasks[kind] = Task { [weak self] in
            await writer.write(kind: kind, settings: settings)
            guard !Task.isCancelled else { return }
            if self?.renderingKind == kind { self?.renderingKind = nil }
        }
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
        for kind in PhotoWidgetKind.allCases {
            WidgetCenter.shared.reloadTimelines(ofKind: kind.widgetKind)
        }
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
