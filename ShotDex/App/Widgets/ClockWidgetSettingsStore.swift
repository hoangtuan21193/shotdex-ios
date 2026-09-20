import Foundation
import Observation
import WidgetKit

/// The Clock widget's settings as the app edits them: one observable value
/// backed by the App Group file the widget reads.
///
/// `UserDefaults` is not an option here — the widget is a second process, and
/// the app's own defaults are not in its container — so this is a small JSON
/// file beside the pictures it describes, like every other widget payload.
@MainActor
@Observable
final class ClockWidgetSettingsStore {
    private(set) var settings: ClockWidgetSettings

    /// Set while the pictures are being re-rendered, so Settings can say so
    /// rather than looking as if nothing happened.
    private(set) var isRenderingPhotos = false

    private let photoLibrary: PhotoLibraryService
    /// Coalesces the writes a slider produces: a drag publishes on every
    /// frame, and each save is a file write plus a widget reload.
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var renderTask: Task<Void, Never>?

    init(photoLibrary: PhotoLibraryService) {
        self.photoLibrary = photoLibrary
        self.settings = ClockWidgetSettings.read()
    }

    /// Applies a change and schedules the write. `rendersPhotos` is for the
    /// edits that change *which* picture is shown, not how it is labelled.
    func update(rendersPhotos: Bool = false, _ change: (inout ClockWidgetSettings) -> Void) {
        var updated = settings
        change(&updated)
        updated.timeFormat = ClockWidgetFormat.sanitized(pattern: updated.timeFormat)
        updated.dateFormat = ClockWidgetFormat.sanitized(pattern: updated.dateFormat)
        updated.timeSize = updated.timeSize.clamped(to: ClockWidgetSettings.timeSizeRange)
        updated.dateSize = updated.dateSize.clamped(to: ClockWidgetSettings.dateSizeRange)
        if !WidgetTextColor.isValid(hex: updated.textColorHex) {
            updated.textColorHex = WidgetTextColor.fallbackHex
        }
        guard updated != settings else { return }
        let sourceChanged = updated.source != settings.source
        settings = updated
        scheduleSave()
        if rendersPhotos || sourceChanged { renderPhotos() }
    }

    /// Re-renders the pictures — after the source changed, and from the
    /// Settings row that offers it when an album has new photos in it.
    func renderPhotos() {
        renderTask?.cancel()
        isRenderingPhotos = true
        let settings = settings
        let writer = ClockWidgetSnapshotWriter(photoLibrary: photoLibrary)
        renderTask = Task { [weak self] in
            await writer.write(settings: settings)
            guard !Task.isCancelled else { return }
            self?.isRenderingPhotos = false
        }
    }

    /// Writes the file the widget reads. Called on a debounce by `update`, and
    /// directly when the app is about to lose the foreground.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard let container = WidgetSharedContainer.url else { return }
        try? WidgetSharedContainer.encode(
            settings,
            to: container.appendingPathComponent(ClockWidgetSettings.fileName)
        )
        WidgetCenter.shared.reloadTimelines(ofKind: ClockWidgetSettings.widgetKind)
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
