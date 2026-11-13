import SwiftUI

/// Ties a photo grid to the viewer it opens, for the Photos-style zoom
/// (FS-02 §8 D5): the viewer grows out of the tapped tile and, closed,
/// shrinks back into the tile of the photo it ended on — scrolled into view
/// first if it is not on screen.
///
/// The grid registers how to find a tile and how to bring one into view; the
/// viewer reports the photo it is on. Nothing here holds photos.
@MainActor
@Observable
final class PhotoViewerLink {
    /// The photo the viewer is on now; nil while no viewer is open.
    private(set) var currentAssetId: String?
    /// Bumped when the grid moved (scroll, reload) so the source frame is read again.
    private(set) var layoutVersion = 0

    @ObservationIgnored var frameProvider: ((String) -> CGRect?)?
    @ObservationIgnored var revealer: ((String) -> Void)?

    /// The viewer moved to `assetId`: its tile is scrolled into view (hidden
    /// behind the viewer, so no one sees it move) and becomes the zoom target.
    func focus(on assetId: String) {
        guard assetId != currentAssetId else { return }
        revealer?(assetId)
        currentAssetId = assetId
        layoutVersion &+= 1
    }

    func clear() { currentAssetId = nil }

    /// The tile's frame in window coordinates, or nil when it has none.
    func sourceFrame(for assetId: String?) -> CGRect? {
        _ = layoutVersion
        guard let assetId else { return nil }
        return frameProvider?(assetId)
    }
}

private struct PhotoViewerLinkKey: EnvironmentKey {
    static let defaultValue: PhotoViewerLink? = nil
}

extension EnvironmentValues {
    /// The grid link of the screen that opened this viewer, if any.
    var photoViewerLink: PhotoViewerLink? {
        get { self[PhotoViewerLinkKey.self] }
        set { self[PhotoViewerLinkKey.self] = newValue }
    }
}

extension View {
    /// `fullScreenCover(item:)` for the photo viewer, zooming from and back
    /// to the grid tile on iOS 18 and later; iOS 17 keeps the plain cover.
    func photoViewerCover<Content: View>(
        item: Binding<PhotoViewerTarget?>,
        link: PhotoViewerLink,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (PhotoViewerTarget) -> Content
    ) -> some View {
        modifier(PhotoViewerCoverModifier(item: item, link: link, onDismiss: onDismiss, coverContent: content))
    }
}

private struct PhotoViewerCoverModifier<CoverContent: View>: ViewModifier {
    @Binding var item: PhotoViewerTarget?
    let link: PhotoViewerLink
    let onDismiss: (() -> Void)?
    let coverContent: (PhotoViewerTarget) -> CoverContent
    @Namespace private var zoom

    private static var sourceID: String { "photo-viewer-source" }

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .overlay { source }
                .fullScreenCover(item: $item, onDismiss: dismissed) { target in
                    coverContent(target)
                        .environment(\.photoViewerLink, link)
                        .navigationTransition(.zoom(sourceID: Self.sourceID, in: zoom))
                }
        } else {
            content
                .fullScreenCover(item: $item, onDismiss: dismissed) { target in
                    coverContent(target)
                        .environment(\.photoViewerLink, link)
                }
        }
    }

    private func dismissed() {
        link.clear()
        onDismiss?()
    }

    /// An empty view laid over the tile the zoom starts from or ends on.
    @available(iOS 18.0, *)
    @ViewBuilder private var source: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            if let frame = link.sourceFrame(for: link.currentAssetId ?? item?.id) {
                Color.clear
                    .frame(width: frame.width, height: frame.height)
                    .matchedTransitionSource(id: Self.sourceID, in: zoom)
                    .position(x: frame.midX - origin.x, y: frame.midY - origin.y)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
