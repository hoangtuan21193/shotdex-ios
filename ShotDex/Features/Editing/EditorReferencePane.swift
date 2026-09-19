import Photos
import SwiftUI

/// The pinned frame beside the canvas — Lightroom's Reference View.
///
/// Shows the reference **as it stands in the library**, edits and all, not as a
/// live render: the point is "make this one look like that one", and that one
/// is finished. Rendering it through a second `PhotoEditorController` would
/// double the editor's memory for a picture nobody is changing.
struct EditorReferencePane: View {
    let asset: PHAsset
    let photoLibrary: PhotoLibraryService
    /// The canvas's zoom and pan, mirrored here while the two are linked. Both
    /// panes are the same size and both frames are aspect-fit inside them, so
    /// the same scale and offset land on the same part of each picture — which
    /// is the whole point of comparing them.
    var zoomScale: CGFloat = 1
    var zoomOffset: CGSize = .zero
    var isLocked: Bool = true
    var toggleLock: () -> Void = {}
    var clear: () -> Void

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        ZStack {
            Color.black
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(isLocked ? zoomScale : 1)
                    .offset(isLocked ? zoomOffset : .zero)
                    // Clipped, not letting the zoomed frame spill over the
                    // divider into the photo being edited.
                    .clipped()
            } else {
                ProgressView().tint(EditorTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The label floats over the frame instead of taking a row of its own:
        // stacked above it, the reference sat 44pt lower than the photo it is
        // being matched to, and the whole job of this pane is comparing the two
        // at a glance.
        .overlay(alignment: .top) { header }
        .task(id: asset.localIdentifier) { load() }
        .onDisappear(perform: cancel)
    }

    private var header: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text("Reference")
                .font(EditorTheme.groupLabel)
                .tracking(1.1)
                .foregroundStyle(EditorTheme.secondaryText)
            Spacer(minLength: 0)
            Button(action: toggleLock) {
                Image(systemName: isLocked ? "link" : "link.badge.plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isLocked ? EditorTheme.accent : EditorTheme.secondaryText)
                    .frame(width: AppTheme.Size.minTouch, height: AppTheme.Size.minTouch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .accessibilityLabel(isLocked ? "Unlink Zoom" : "Link Zoom")
            .accessibilityValue(isLocked ? "Linked" : "Not linked")

            Button(action: clear) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(EditorTheme.secondaryText)
                    .frame(width: AppTheme.Size.minTouch, height: AppTheme.Size.minTouch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .accessibilityLabel("Clear Reference")
        }
        .padding(.leading, AppTheme.Spacing.lg)
        .frame(height: EditorLayoutMetrics.sidebarHeaderHeight)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.65), .black.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func load() {
        cancel()
        image = nil
        requestID = photoLibrary.requestDetailImage(
            for: asset,
            targetSize: CGSize(width: 1400, height: 1400),
            allowNetwork: true,
            progress: { _ in }
        ) { result, isDegraded in
            // Degraded frames are welcome here — a reference is looked at, not
            // pixel-peeped, and showing something immediately beats a spinner.
            if let result { image = result }
            if !isDegraded { requestID = nil }
        }
    }

    private func cancel() {
        if let requestID { photoLibrary.cancelThumbnailRequest(requestID) }
        requestID = nil
    }
}
