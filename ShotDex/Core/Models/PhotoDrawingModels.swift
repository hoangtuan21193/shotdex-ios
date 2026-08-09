import Foundation

/// A freehand Markup drawing, stored as PencilKit's own vector data.
///
/// Foundation only — the model layer never imports PencilKit. The `data` blob is
/// `PKDrawing.dataRepresentation()`, opaque here; only the editor's canvas and the
/// renderer decode it. Keeping the vector (rather than a flattened PNG) is what
/// lets reopening the edit reload the strokes for more drawing, and lets the
/// renderer rasterize crisply at export resolution instead of upscaling a bitmap.
///
/// Geometry is the canvas the strokes were drawn on, in points — the fitted photo
/// rect at draw time. The renderer scales the drawing by `extent.width /
/// canvasWidth`, so one capture serves the 1024pt preview, the settle pass and the
/// full-resolution export alike. The canvas aspect matches the cropped image's, so
/// height follows width.
struct PhotoDrawing: Codable, Equatable, Sendable {
    /// `PKDrawing.dataRepresentation()`.
    var data: Data
    /// Canvas size in points at capture time, so the vector can be scaled to any
    /// render extent.
    var canvasWidth: Double
    var canvasHeight: Double
    /// The layer's eye toggle. A hidden drawing stays in the recipe (so the strokes
    /// are not lost) but is not composited.
    var isVisible = true

    /// No strokes to composite. An empty drawing is treated as no drawing at all,
    /// so it adds no key to a recipe and reads as identity.
    var isEmpty: Bool { data.isEmpty || canvasWidth <= 0 || canvasHeight <= 0 }

    /// Actually drawn on the photo: has strokes and its eye is on.
    var hasVisibleEffect: Bool { !isEmpty && isVisible }
}
