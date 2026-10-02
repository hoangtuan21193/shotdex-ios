import CoreGraphics

/// The culling pass's geometry per screen (FS-01.12b §5), in points. One
/// layout from iPhone to iPad; what changes is decided from the size the
/// screen actually got, so Split View and the Duo pick the right one.
struct CullLayout: Equatable {
    /// Top bar: ✕ · counter · Undo.
    static let topBarHeight: CGFloat = 52
    /// iPad's EXIF line under the top bar.
    static let exifLineHeight: CGFloat = 22
    /// `[Reject 44] 16 [★×5 at 44] 16 [Pick 44]` = 340pt.
    static let controlRowHeight: CGFloat = 60
    static let control: CGFloat = 44
    static let controlGap: CGFloat = 16
    static let starGlyph: CGFloat = 22
    static let controlRowWidth: CGFloat = control * 7 + controlGap * 2
    static let edgeInset: CGFloat = 16

    /// Filmstrip strip height and its square cell.
    let filmstripHeight: CGFloat
    let filmstripCell: CGFloat
    /// Whether the EXIF line shows under the top bar.
    let showsEXIFLine: Bool

    /// iPad (wide **and** tall): a 72pt strip of 60pt cells and the EXIF
    /// line. Everything else — iPhone, the Duo's 669pt-tall inner screen, its
    /// cover — the phone's 56 / 44 and no EXIF line: height is what those
    /// screens lack.
    static func forSize(_ size: CGSize) -> CullLayout {
        let isTablet = size.width >= 700 && size.height >= 800
        return isTablet
            ? CullLayout(filmstripHeight: 72, filmstripCell: 60, showsEXIFLine: true)
            : CullLayout(filmstripHeight: 56, filmstripCell: 44, showsEXIFLine: false)
    }
}
