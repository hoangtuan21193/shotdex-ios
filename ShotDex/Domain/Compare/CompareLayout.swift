import CoreGraphics

/// Frame sizes for Compare's two stages (FS-01.08c §2–§4), in points, from
/// the area the stage is given. Pure and tested (`CompareLayoutTests`): the
/// numbers are the boards' (`PH_Compare`, `IP_Compare`, `IP_CompareSurvey`,
/// `DI_Compare`, `DI_CompareSurvey`, `DC_Compare`).
///
/// A frame is the box the photo is fitted into, plus its caption. The photo
/// is drawn at its own aspect ratio inside the box — never cropped to a
/// common height.
enum CompareLayout {
    /// The stage's side margin.
    static let margin: CGFloat = 16
    /// Between the two frames of a side-by-side 2-Up, on every display.
    static let sideBySideGap: CGFloat = 16

    /// What sits under the photo box, and how far apart frames are.
    struct Metrics: Equatable, Sendable {
        /// Caption height under the photo box.
        var caption: CGFloat
        /// Between two frames.
        var gap: CGFloat

        /// iPhone and the Duo's inner 2-Up: a name-and-EXIF line, then the
        /// Cull row `[Reject 44] [★×5] [Pick 44]` — 4 + 16 + 4 + 44.
        static let cullRow = Metrics(caption: 68, gap: 12)
        /// The Duo's cover: the name rides on the photo, the Cull row
        /// follows 4pt under it.
        static let cover = Metrics(caption: 48, gap: 8)
        /// iPad and Mac: name and EXIF on two lines at the left, five stars
        /// and the None · Pick · Reject segmented control at the right.
        static let wide = Metrics(caption: 64, gap: 16)
    }

    struct Frame: Equatable, Sendable {
        /// The whole frame, caption included.
        var size: CGSize
        /// The box the photo is fitted into.
        var photo: CGSize
    }

    /// The metrics for a window class's 2-Up (§2).
    static func twoUpMetrics(for windowClass: VideoStudioWindowClass) -> Metrics {
        switch windowClass {
        case .phone, .duoInner: .cullRow
        case .duoCover: .cover
        case .iPadLandscape, .iPadPortrait: .wide
        }
    }

    /// 2-Up side by side: two frames filling the stage's height (§2).
    /// iPad 1376 wide → 664 × 832; the Duo's inner display → 451 × 453.
    static func twoUp(area: CGSize, metrics: Metrics) -> Frame {
        let width = ((area.width - margin * 2 - sideBySideGap) / 2).rounded(.down)
        return Frame(
            size: CGSize(width: width, height: area.height),
            photo: CGSize(width: width, height: max(0, area.height - metrics.caption))
        )
    }

    /// Compare on a compact window: Select above, Candidate below, the
    /// stage's height shared between them (§2). iPhone 402 × 600 →
    /// 370 × 294; the cover, 382 wide beside its rail → 350 × 224.
    static func stacked(area: CGSize, metrics: Metrics) -> Frame {
        let width = area.width - margin * 2
        let height = ((area.height - metrics.gap) / 2).rounded(.down)
        return Frame(
            size: CGSize(width: width, height: height),
            photo: CGSize(width: width, height: max(0, height - metrics.caption))
        )
    }

    // MARK: Survey

    /// Survey's cell metrics. The photo box is 3:2 and fitted into the cell.
    struct SurveyMetrics: Equatable, Sendable {
        var caption: CGFloat
        var columnGap: CGFloat
        var rowGap: CGFloat
        /// Room around the photo box for the working frame's amber ring.
        var inset: CGFloat

        /// iPad and Mac: two caption lines with stars and the flag control.
        static let wide = SurveyMetrics(caption: 114, columnGap: 16, rowGap: 16, inset: 3)
        /// The Duo's inner display: the name rides on the photo, the Cull
        /// row with 32pt stars right under it.
        static let duoInner = SurveyMetrics(caption: 44, columnGap: 16, rowGap: 12, inset: 0)
    }

    struct Survey: Equatable, Sendable {
        var columns: Int
        var cell: CGSize
        var photo: CGSize
        /// The cells did not fit at their smallest: the grid scrolls.
        var scrolls: Bool
    }

    static let surveyColumns = 3
    static let surveyAspect: CGFloat = 3.0 / 2.0

    /// Survey (§4): three columns; up to six photos the cells are the
    /// six-photo size, past that they shrink so the whole comparison fits —
    /// down to half that size, after which the grid scrolls. iPad: 432 × 288
    /// for six, 216 × 144 at the floor. Duo inner: 264 × 176 → 132 × 88.
    static func survey(count: Int, area: CGSize, metrics: SurveyMetrics) -> Survey {
        let columns = surveyColumns
        let width = area.width - margin * 2
        let cellWidth = (width - CGFloat(columns - 1) * metrics.columnGap) / CGFloat(columns)
        let full = surveyPhoto(rows: 2, cellWidth: cellWidth, area: area, metrics: metrics)
        let floor = CGSize(width: full.width / 2, height: full.height / 2)
        let rows = max(1, (count + columns - 1) / columns)
        var photo = rows <= 2 ? full : surveyPhoto(rows: rows, cellWidth: cellWidth, area: area, metrics: metrics)
        let scrolls = photo.height < floor.height - 0.5
        if scrolls { photo = floor }
        return Survey(
            columns: columns,
            cell: CGSize(width: cellWidth, height: photo.height + metrics.inset * 2 + metrics.caption),
            photo: photo,
            scrolls: scrolls
        )
    }

    /// The largest 3:2 box that lets `rows` rows of cells fit the height.
    private static func surveyPhoto(rows: Int, cellWidth: CGFloat, area: CGSize, metrics: SurveyMetrics) -> CGSize {
        let rowHeight = (area.height - CGFloat(rows - 1) * metrics.rowGap) / CGFloat(rows)
        let maxHeight = max(0, rowHeight - metrics.caption - metrics.inset * 2)
        let maxWidth = max(0, cellWidth - metrics.inset * 2)
        let height = min(maxHeight, maxWidth / surveyAspect)
        return CGSize(width: height * surveyAspect, height: height)
    }
}
