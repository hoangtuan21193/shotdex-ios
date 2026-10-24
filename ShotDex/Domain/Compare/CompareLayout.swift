import CoreGraphics

/// Geometry shared by the full-screen photo surfaces (viewer, Compare, Cull).
enum CompareLayout {
    /// How far a full-screen surface's top row (Close and what sits beside
    /// it) sits below the top of the Duo's inner display. In landscape the
    /// status bar is in the side rail, so the safe area starts at 0 and the
    /// usual 8pt left the Close circle tangent to the ~66pt corner curve; 32
    /// clears it by ~15pt, as `DI_Viewer` draws it.
    static let duoInnerTopInset: CGFloat = 32
}
