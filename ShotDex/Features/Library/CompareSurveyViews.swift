import AVKit
import Photos
import SwiftUI

/// How the compare screen lays its photos out. Lightroom's three culling views,
/// under the names it uses for them.
enum CompareViewMode: String, CaseIterable, Identifiable {
    /// One scrolling column of whole frames. The original ShotDex compare, and
    /// the only one that works on a phone with more than three photos.
    case column
    /// Everything on screen at once, nothing scrolling — the view a cull
    /// actually happens in. Lightroom's N.
    case survey
    /// Two frames: the one winning so far, and the one being tried against it.
    /// Lightroom's C.
    case compare

    var id: String { rawValue }

    var title: String {
        switch self {
        case .column: "Column"
        case .survey: "Survey"
        case .compare: "Compare"
        }
    }

    var systemImage: String {
        switch self {
        case .column: "rectangle.grid.1x2"
        case .survey: "square.grid.2x2"
        case .compare: "rectangle.split.2x1"
        }
    }
}

// MARK: - Survey

/// Every photo on screen at once, sized so the biggest possible tile fits.
///
/// Nothing scrolls on purpose: the question a survey answers is "which of these
/// is the keeper", and a photo that has to be scrolled to is a photo that is
/// not in the comparison.
struct SurveyGridView: View {
    let photos: [ComparePhoto]
    let activeIndex: Int
    let cullStates: [String: PhotoCullState]
    let setActive: (Int) -> Void
    let remove: (ComparePhoto) -> Void
    let setFlag: (ComparePhoto, PhotoFlag) -> Void
    let setRating: (ComparePhoto, Int) -> Void

    private let spacing: CGFloat = AppTheme.Spacing.sm

    var body: some View {
        GeometryReader { proxy in
            let columns = SurveyLayout.columns(
                count: photos.count,
                canvas: proxy.size,
                aspectRatio: averageAspect,
                spacing: spacing
            )
            let rows = SurveyLayout.rows(count: photos.count, columns: columns)
            let cellWidth = (proxy.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let cellHeight = (proxy.size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)

            VStack(spacing: spacing) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(rowIndices(row: row, columns: columns), id: \.self) { index in
                            tile(index)
                                .frame(width: cellWidth, height: cellHeight)
                        }
                        // A short last row stays left-aligned under the rows
                        // above it rather than centring and knocking the
                        // columns out of line.
                        if rowIndices(row: row, columns: columns).count < columns {
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var averageAspect: CGFloat {
        SurveyLayout.averageAspectRatio(photos.map(\.aspectRatio))
    }

    private func rowIndices(row: Int, columns: Int) -> [Int] {
        let start = row * columns
        let end = min(start + columns, photos.count)
        return start < end ? Array(start..<end) : []
    }

    private func tile(_ index: Int) -> some View {
        let photo = photos[index]
        let state = cullStates[photo.assetId ?? ""] ?? PhotoCullState(assetId: photo.assetId ?? "")
        return SurveyTile(
            photo: photo,
            isActive: index == activeIndex,
            cullState: state,
            remove: { remove(photo) }
        )
        .onTapGesture { setActive(index) }
        .cullContextMenu(
            state: state,
            setFlag: { setFlag(photo, $0) },
            setRating: { setRating(photo, $0) }
        )
    }
}

/// One frame in the survey: the photo whole, its cull badges, and an ✕ that
/// takes it out of the comparison (not out of the library).
private struct SurveyTile: View {
    @Environment(PhotoLibraryService.self) private var photoLibrary

    let photo: ComparePhoto
    let isActive: Bool
    let cullState: PhotoCullState
    let remove: () -> Void

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(EditorTheme.panelSolid)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(AppTheme.Spacing.xs)
            } else {
                ProgressView().tint(EditorTheme.secondaryText)
            }
        }
        .overlay(alignment: .topTrailing) { removeButton }
        .overlay(alignment: .bottomLeading) {
            CullBadgeRow(state: cullState)
                .padding(AppTheme.Spacing.sm)
        }
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .strokeBorder(isActive ? EditorTheme.accent : .clear, lineWidth: 2)
        }
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
        .task(id: photo.assetId) { load() }
        .onDisappear(perform: cancel)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    private var removeButton: some View {
        Button(action: remove) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: AppTheme.Size.minTouch, height: AppTheme.Size.minTouch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove from comparison")
    }

    private func load() {
        cancel()
        guard let asset = photo.asset else { return }
        // A tile is a few hundred points at most, so a thumbnail request is the
        // right size — a survey of twelve full-screen renditions is the one way
        // to make this screen slower than scrolling the grid.
        let side = ActiveDisplay.pixelSize().width / 2
        requestID = photoLibrary.requestThumbnail(
            for: asset,
            targetSize: CGSize(width: side, height: side),
            allowNetwork: true
        ) { result in
            if let result { image = result }
            requestID = nil
        }
    }

    private func cancel() {
        if let requestID { photoLibrary.cancelThumbnailRequest(requestID) }
        requestID = nil
    }
}

// MARK: - Compare

/// One half of Compare: a frame, what it is (Select or Candidate), and the cull
/// controls for it.
///
/// Zoom and pan come from the shared `CompareScrollSynchronizer` the column
/// mode already uses, so the two panes stay on the same detail of two different
/// photos — the entire reason to put them side by side.
struct ComparePaneView: View {
    @Environment(PhotoLibraryService.self) private var photoLibrary

    let photo: ComparePhoto
    let role: String
    let sync: CompareScrollSynchronizer
    let paneIndex: Int
    let cullState: PhotoCullState
    let setFlag: (PhotoFlag) -> Void
    let setRating: (Int) -> Void

    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if let image {
                    ZoomableImageView(image: image, sync: sync, paneIndex: paneIndex)
                } else {
                    ProgressView().tint(EditorTheme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) { roleLabel }

            footer
        }
        .background(EditorTheme.panelSolid)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        .task(id: photo.assetId) { load() }
    }

    private var roleLabel: some View {
        Text(role.uppercased())
            .font(EditorTheme.groupLabel)
            .tracking(1.1)
            .foregroundStyle(EditorTheme.secondaryText)
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(height: 32)
            .background(Capsule().fill(.black.opacity(0.55)))
            .padding(AppTheme.Spacing.sm)
    }

    private var footer: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            CullControlBar(state: cullState, setFlag: setFlag, setRating: setRating)
            Spacer(minLength: 0)
            if let caption = photo.exposureCaption {
                Text(caption)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(EditorTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
    }

    private func load() {
        // Cleared first: the pane is reused when Promote or Swap puts another
        // photo in the same slot, and a load that returns early on "already
        // have an image" leaves the previous photo on screen under the new
        // one's caption — two photos claiming to be one.
        image = nil
        guard let asset = photo.asset else { return }
        let targetSize = ActiveDisplay.pixelSize()
        let requested = asset.localIdentifier
        _ = photoLibrary.requestBestLocalImage(for: asset, targetSize: targetSize) { result in
            // The slower request for the photo that *was* here can land after
            // the swap; it must not paint over the new one.
            guard let result, requested == photo.assetId else { return }
            let currentPixels = (image?.size.width ?? 0) * (image?.scale ?? 1)
            if result.size.width * result.scale > currentPixels { image = result }
        }
        _ = photoLibrary.requestDetailImage(
            for: asset,
            targetSize: targetSize,
            allowNetwork: true,
            progress: { _ in }
        ) { result, isDegraded in
            if let result, !isDegraded, requested == photo.assetId { image = result }
        }
    }
}

extension ComparePhoto {
    var assetId: String? { asset?.localIdentifier }

    /// Width ÷ height with PhotoKit's orientation applied; square when the
    /// asset is missing, so a tile never collapses to nothing.
    var aspectRatio: CGFloat {
        guard let asset, asset.pixelWidth > 0, asset.pixelHeight > 0 else { return 1 }
        return CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
    }

    /// Camera and exposure on one line — the numbers a comparison turns on.
    var exposureCaption: String? {
        guard let metadata else { return nil }
        return MetadataFormatter.metadataLine([
            metadata.normalizedCameraModel,
            metadata.focalLength.flatMap(MetadataFormatter.focalLength),
            metadata.aperture.flatMap(MetadataFormatter.aperture),
            metadata.shutterSpeedDisplay,
            metadata.iso.flatMap(MetadataFormatter.iso),
        ])
    }
}
