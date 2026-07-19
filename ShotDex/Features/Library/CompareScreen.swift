import Photos
import SwiftUI
import UIKit

/// One photo entering the compare screen.
struct ComparePhoto {
    let metadata: PhotoMetadata
    let asset: PHAsset?
}

/// Mirrors zoom and pan across the compare panes' scroll views (2–4 panes).
/// Zoom sync and pan sync toggle independently (Lightroom-style).
@MainActor
final class CompareScrollSync {
    var isZoomSyncEnabled = true
    var isPanSyncEnabled = true

    private var scrollViews: [Int: UIScrollView] = [:]
    private var isPropagating = false

    func register(_ scrollView: UIScrollView, at index: Int) {
        scrollViews[index] = scrollView
    }

    /// Called from scroll-view delegate callbacks; copies the source pane's
    /// zoom and/or normalized offset to the other panes.
    func mirror(from source: UIScrollView) {
        guard !isPropagating, isZoomSyncEnabled || isPanSyncEnabled else { return }
        isPropagating = true
        defer { isPropagating = false }
        for (_, target) in scrollViews where target !== source {
            if isZoomSyncEnabled, target.zoomScale != source.zoomScale {
                target.zoomScale = source.zoomScale
            }
            if isPanSyncEnabled {
                target.contentOffset = Self.normalizedOffset(from: source, to: target)
            }
        }
    }

    /// Snaps every other pane to pane `index`'s zoom scale.
    func resyncZoom(to index: Int) {
        guard let source = scrollViews[index] else { return }
        isPropagating = true
        defer { isPropagating = false }
        for (_, target) in scrollViews where target !== source {
            target.zoomScale = source.zoomScale
        }
    }

    /// Snaps every other pane to pane `index`'s relative position.
    func resyncPan(to index: Int) {
        guard let source = scrollViews[index] else { return }
        isPropagating = true
        defer { isPropagating = false }
        for (_, target) in scrollViews where target !== source {
            target.contentOffset = Self.normalizedOffset(from: source, to: target)
        }
    }

    /// Maps an offset between panes proportionally to their content sizes,
    /// so photos with different aspect ratios stay on the same relative spot.
    private static func normalizedOffset(from source: UIScrollView, to target: UIScrollView) -> CGPoint {
        let sw = source.contentSize.width
        let sh = source.contentSize.height
        guard sw > 0, sh > 0 else { return target.contentOffset }
        return CGPoint(
            x: source.contentOffset.x / sw * target.contentSize.width,
            y: source.contentOffset.y / sh * target.contentSize.height
        )
    }
}

/// Lightroom-style compare: 2–3 photos stacked vertically, 4 photos in a
/// 2x2 grid, with synchronized zoom and pan toggled independently.
struct CompareScreen: View {
    /// Upper bound for the compare selection (grid layout tops out at 2x2).
    static let maxPhotoCount = 4

    @Environment(\.dismiss) private var dismiss

    /// 2–4 photos, in selection order.
    let photos: [ComparePhoto]

    @State private var sync = CompareScrollSync()
    @State private var isZoomSynced = true
    @State private var isPanSynced = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            paneLayout

            VStack {
                topBar
                Spacer()
            }
        }
        .statusBarHidden()
    }

    @ViewBuilder
    private var paneLayout: some View {
        if photos.count == 4 {
            VStack(spacing: 1) {
                HStack(spacing: 1) {
                    pane(0)
                    pane(1)
                }
                HStack(spacing: 1) {
                    pane(2)
                    pane(3)
                }
            }
        } else {
            VStack(spacing: 1) {
                ForEach(photos.indices, id: \.self) { index in
                    pane(index)
                }
            }
        }
    }

    private func pane(_ index: Int) -> some View {
        ComparePane(
            photo: photos[index],
            sync: sync,
            paneIndex: index,
            isCompact: photos.count == 4
        )
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            GlassIconButton(systemImage: "xmark", accessibilityLabel: "Close") {
                dismiss()
            }
            Spacer()
            syncToggle(
                isOn: $isZoomSynced,
                systemImage: "plus.magnifyingglass",
                label: "Sync zoom"
            ) {
                sync.isZoomSyncEnabled = isZoomSynced
                if isZoomSynced { sync.resyncZoom(to: 0) }
            }
            syncToggle(
                isOn: $isPanSynced,
                systemImage: "arrow.up.and.down.and.arrow.left.and.right",
                label: "Sync position"
            ) {
                sync.isPanSyncEnabled = isPanSynced
                if isPanSynced { sync.resyncPan(to: 0) }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    /// Glass toggle button: accent-tinted when the sync is active.
    private func syncToggle(
        isOn: Binding<Bool>,
        systemImage: String,
        label: String,
        onChange: @escaping () -> Void
    ) -> some View {
        Button {
            isOn.wrappedValue.toggle()
            onChange()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isOn.wrappedValue ? Color.accentColor : Color(.label))
                .frame(width: 52, height: 52)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .strokeBorder(
                            isOn.wrappedValue
                                ? Color.accentColor.opacity(0.6)
                                : Color(.separator).opacity(0.3),
                            lineWidth: isOn.wrappedValue ? 1.5 : 0.5
                        )
                )
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }
}

/// One compare pane: loads its image, then shows the synced zoomable view
/// with a small metadata caption.
private struct ComparePane: View {
    @Environment(PhotoLibraryService.self) private var photoLibrary

    let photo: ComparePhoto
    let sync: CompareScrollSync
    let paneIndex: Int
    /// Quarter-screen panes (2x2 grid) drop the camera model from the caption.
    let isCompact: Bool

    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image {
                ZoomableImageView(image: image, sync: sync, paneIndex: paneIndex)
            } else {
                ProgressView()
                    .tint(.white)
            }
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear(perform: loadImage)
    }

    private var caption: String? {
        FormatUtils.metadataLine([
            isCompact ? nil : photo.metadata.normalizedCameraModel,
            photo.metadata.focalLength.flatMap(FormatUtils.focalLength),
            photo.metadata.aperture.flatMap(FormatUtils.aperture),
            photo.metadata.iso.flatMap(FormatUtils.iso),
        ])
    }

    private func loadImage() {
        guard image == nil, let asset = photo.asset else { return }
        let scale = UIScreen.main.scale
        let targetSize = CGSize(
            width: UIScreen.main.bounds.width * scale,
            height: UIScreen.main.bounds.height * scale
        )
        _ = photoLibrary.requestThumbnail(for: asset, targetSize: targetSize) { result in
            if let result {
                image = result
            }
        }
    }
}
