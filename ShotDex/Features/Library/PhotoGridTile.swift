import Photos
import SwiftUI

/// One square cell in the photo grid: thumbnail + optional metadata line
/// over a subtle bottom gradient.
struct PhotoGridTile<Item: PhotoGridDisplayable>: View {
    @Environment(PhotoLibraryService.self) private var photoLibrary

    let item: Item
    let asset: PHAsset?
    /// Approximate on-screen cell width in points (from the column count).
    /// Not a layout constraint — the LazyVGrid's flexible column sets the real
    /// frame; this only sizes the thumbnail request and gates the metadata
    /// line. Passing it in replaces a per-cell `GeometryReader`, which at grid
    /// scale (dozens of live cells) was the scroll/pinch hitch.
    let cellWidth: CGFloat

    @AppStorage("display.showISO") private var showISO = true
    @AppStorage("display.showAperture") private var showAperture = true
    @AppStorage("display.showShutter") private var showShutter = false
    @AppStorage("display.showFocal") private var showFocal = true
    @AppStorage("display.focalStyleEquivalent") private var focalStyleEquivalent = false

    /// Cells narrower than this hide the metadata line (dense column counts).
    /// Computed — generic types can't hold static stored properties.
    static var metadataMinCellWidth: CGFloat { 90 }

    @State private var image: UIImage?
    @State private var requestId: PHImageRequestID?
    @State private var lastRequestedPixelWidth: CGFloat = 0

    var body: some View {
        // `Color.clear` + aspectRatio is the sizer: the LazyVGrid column sets
        // the width, this fixes height = width (always a square), and the
        // thumbnail lives in an overlay so its intrinsic size can never
        // stretch the cell (a `scaledToFill` Image inside the layout pass
        // inflated rows and broke scroll positions).
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { thumbnail }
            .overlay(alignment: .bottomLeading) {
                if cellWidth >= Self.metadataMinCellWidth, let line = metadataLine {
                    metadataOverlay(line)
                }
            }
            .overlay(alignment: .topTrailing) {
                if asset?.mediaType == .video {
                    videoBadge
                }
            }
            .clipped()
            .onAppear { requestImage() }
            .onChange(of: cellWidth) { requestImage() }
            .onDisappear { cancelRequest() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityDescription)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle()
                .fill(Color(.secondarySystemBackground))
        }
    }

    /// Play glyph + duration, bottom-trailing, marking a video tile.
    private var videoBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "play.fill")
                .font(.system(size: 8, weight: .bold))
            if let asset, asset.duration > 0 {
                Text(FormatUtils.duration(asset.duration))
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(.black.opacity(0.45), in: Capsule())
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .shadow(radius: 1)
    }

    private func metadataOverlay(_ line: String) -> some View {
        Text(line)
            .font(.system(size: 10, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    /// Only real values — never placeholders like `ISO -- · --mm`.
    private var metadataLine: String? {
        let focalValue = focalStyleEquivalent
            ? (item.equivalentFocalLength ?? item.focalLength)
            : item.focalLength
        return FormatUtils.metadataLine([
            showISO ? item.iso.flatMap(FormatUtils.iso) : nil,
            showFocal ? focalValue.flatMap(FormatUtils.focalLength) : nil,
            showAperture ? item.aperture.flatMap(FormatUtils.aperture) : nil,
            showShutter ? item.shutterSpeedDisplay : nil,
        ])
    }

    private var accessibilityDescription: String {
        var parts = ["Photo"]
        if let line = metadataLine { parts.append(line) }
        return parts.joined(separator: ", ")
    }

    /// Requests the thumbnail sized to the cell. Re-requests when the cell
    /// has grown materially (pinch to fewer columns) so a tile first shown
    /// small doesn't stay low-res; the old image stays visible until the
    /// sharper one arrives.
    private func requestImage() {
        guard let asset, cellWidth > 0 else { return }
        // 2x is indistinguishable at grid-cell size; 3x devices would pay
        // 2.25x the decode/memory cost for nothing.
        let scale = min(UIScreen.main.scale, 2)
        let pixelWidth = cellWidth * scale
        let needsUpgrade = pixelWidth > lastRequestedPixelWidth * 1.4
        guard image == nil || needsUpgrade else { return }
        cancelRequest()
        lastRequestedPixelWidth = pixelWidth
        let targetSize = CGSize(width: pixelWidth, height: pixelWidth)
        // Local-only: scrolling the grid must never trigger iCloud downloads.
        // The detail view is where full-quality (networked) loads happen.
        requestId = photoLibrary.requestThumbnail(
            for: asset, targetSize: targetSize, allowNetwork: false
        ) { result in
            if let result {
                image = result
            }
        }
    }

    private func cancelRequest() {
        if let requestId {
            photoLibrary.cancelThumbnailRequest(requestId)
        }
        requestId = nil
    }
}
