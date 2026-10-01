import Foundation

/// The counts the Insights card is chosen from (FS-07.02), already grouped in
/// SQL by `StatisticsQueries.insightInputs()`. Still photos only — a video
/// never enters a denominator. Plain values, so `InsightSelector` can be fed
/// by hand in a test.
struct InsightInputs: Equatable, Sendable {
    /// Still photos with a camera name — the shared threshold (≥ 50) and the
    /// base the 90% denominator rule compares against.
    var photosWithCamera = 0

    /// Still photos per full-frame equivalent focal length rounded to the mm.
    var equivalentFocalCounts: [Int: Int] = [:]
    /// Still photos per angle-of-view group, counted with the very bounds the
    /// Library filter uses (`FocalAngleBucket.range`).
    var focalAngleCounts: [FocalAngleBucket: Int] = [:]
    /// Still photos with a real focal length.
    var actualFocalCount = 0
    /// Of those, the ones whose equivalent could not be worked out — a
    /// camera the sensor database does not know.
    var unknownSensorCount = 0

    /// The most-used body + lens pairs, most photos first (ties by body then
    /// lens, a→z). Two are enough to judge; more do no harm.
    var topPairs: [PairCount] = []
    /// Still photos with both a camera and a lens name.
    var photosWithCameraAndLens = 0

    /// Still photos slower than 1/equivalent focal length, out of those
    /// carrying both a shutter speed and an equivalent focal length.
    var slowShutterCount = 0
    var shutterAndFocalCount = 0

    /// Still photos per calendar month of the capture date (local time).
    var monthCounts: [MonthCount] = []

    struct PairCount: Equatable, Sendable {
        var body: String
        var lens: String
        var count: Int
    }

    struct MonthCount: Equatable, Sendable {
        var year: Int
        var month: Int
        var count: Int
    }

    /// Equivalent-focal denominator: every still photo with an equivalent.
    var equivalentFocalTotal: Int { equivalentFocalCounts.values.reduce(0, +) }
}
