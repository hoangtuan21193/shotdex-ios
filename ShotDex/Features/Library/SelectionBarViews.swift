import Photos
import SwiftUI

/// Full-screen floating selection chrome — the Liquid Glass layer the root tab
/// view overlays above every tab's content (and above the hidden native tab /
/// nav bars) while a screen is in multi-select. Nothing here paints a solid
/// background: the grid stays the root scroll view and shows through the gaps, so
/// only the glass clusters and the (menu-open) scrim intercept touches.
///
/// Layout (over a 393-wide frame):
/// - Top row: Share · selected-thumbnail tray · Close, one glass row near the top.
/// - Count caption just below it ("{n} Photos Selected").
/// - Bottom row: Create cluster (Collage / Video) · middle cluster (Compare /
///   Compress / ⋯) · standalone Delete.
/// - ⋯ opens a glass popover above it (Add to Collection / Export EXIF / Duplicate).
struct SelectionOverlay: View {
    let model: SelectionBarModel
    @State private var isMoreOpen = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                SelectionTopRow(model: model)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                if model.selectionCount > 0 {
                    SelectionCountCaption(model: model)
                        .padding(.top, 10)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
                SelectionBottomRow(model: model, isMoreOpen: $isMoreOpen)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }

            if isMoreOpen {
                // Tap-anywhere-to-close scrim; also the darkening the spec asks
                // for (the grid + the other clusters read as dimmed beneath it).
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { closeMore() }
                    .transition(.opacity)

                SelectionMoreMenu(model: model, close: closeMore)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 12)
                    .padding(.bottom, 78)
                    .transition(.scale(scale: 0.92, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: model.selectionCount)
        .animation(.easeOut(duration: 0.18), value: isMoreOpen)
    }

    private func closeMore() { isMoreOpen = false }
}

// MARK: - Top row

/// Share · thumbnail tray · Close. Share and Close are 48pt glass circles; the
/// tray takes the middle and scrolls horizontally.
private struct SelectionTopRow: View {
    let model: SelectionBarModel

    var body: some View {
        HStack(spacing: 10) {
            SelectionCircleButton(
                systemImage: "square.and.arrow.up",
                iconSize: 21,
                isEnabled: model.selectionCount > 0 && !model.isPreparingShare,
                showsSpinner: model.isPreparingShare,
                action: model.onShare
            )
            .accessibilityLabel("Share")

            SelectionTray(model: model)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .glassBackground(RoundedRectangle(cornerRadius: 24, style: .continuous))

            SelectionCircleButton(
                systemImage: "xmark",
                iconSize: 17,
                action: model.onClose
            )
            .accessibilityLabel("Done selecting")
        }
    }
}

/// The selected thumbnails in pick order — no placeholders. While they fit the
/// tray they stay centred; once they overflow it becomes a horizontal scroll
/// pinned to the newest pick on the right. Indicator hidden; each thumbnail
/// carries an inset × to deselect.
private struct SelectionTray: View {
    let model: SelectionBarModel

    private let slot: CGFloat = 36
    private let gap: CGFloat = 7
    private let pad: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let count = model.thumbnailIds.count
            let contentWidth = CGFloat(count) * slot
                + CGFloat(max(0, count - 1)) * gap
                + pad * 2
            if contentWidth <= geo.size.width {
                // Fits: lay them out centred, no scrolling.
                HStack(spacing: gap) { thumbnails }
                    .frame(width: geo.size.width, height: geo.size.height)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: gap) { thumbnails }
                        .padding(.horizontal, pad)
                        .frame(height: geo.size.height)
                }
                // Grows to the right and re-anchors to the newest (rightmost)
                // pick automatically on every add.
                .defaultScrollAnchor(.trailing)
            }
        }
    }

    @ViewBuilder
    private var thumbnails: some View {
        ForEach(model.thumbnailIds, id: \.self) { id in
            SelectionTrayThumbnail(
                assetId: id,
                photoLibrary: model.photoLibrary,
                onRemove: { model.onDeselect(id) }
            )
        }
    }
}

/// One 36pt tray thumbnail with an inset deselect ×. Loads a local (never
/// networked) rendition like the grid tile; reloads in place if its id changes.
private struct SelectionTrayThumbnail: View {
    let assetId: String
    let photoLibrary: PhotoLibraryService
    let onRemove: () -> Void

    private let side: CGFloat = 36

    @State private var image: UIImage?
    @State private var requestId: PHImageRequestID?

    var body: some View {
        thumbnail
            .overlay(alignment: .topTrailing) { deselectButton }
            .accessibilityElement()
            .accessibilityLabel("Selected photo")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Removes it from the selection")
            .accessibilityAction(.default, onRemove)
            .onAppear(perform: load)
            .onChange(of: assetId) { load() }
            .onDisappear(perform: cancel)
    }

    private var thumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        return shape
            .fill(Color.white.opacity(0.12))
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: side, height: side)
            .clipShape(shape)
            .overlay { shape.strokeBorder(Color.white.opacity(0.4), lineWidth: 1.5) }
    }

    // × lives *inside* the top-right corner so the tray never clips it.
    private var deselectButton: some View {
        Button(action: onRemove) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 14, height: 14)
                .background(Color(white: 0.12).opacity(0.82), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(1)
    }

    private func load() {
        cancel()
        image = nil
        guard let asset = PhotoLibraryService.fetchAssets(ids: [assetId]).first else { return }
        let pixels = side * min(UIScreen.main.scale, 2)
        requestId = photoLibrary.requestThumbnail(
            for: asset,
            targetSize: CGSize(width: pixels, height: pixels),
            allowNetwork: false
        ) { result in
            if let result { image = result }
        }
    }

    private func cancel() {
        if let requestId { photoLibrary.cancelThumbnailRequest(requestId) }
        requestId = nil
    }
}

// MARK: - Count caption

/// Selection count, centred under the top row on a blurred dark pill so white
/// text stays legible over any photo. When Compare is offered and still in range
/// it spells the cap out; past the max (or where Compare isn't offered) it shows
/// just the running count.
struct SelectionCountCaption: View {
    let model: SelectionBarModel

    private var canCompare: Bool { model.onCompare != nil }
    private var countText: String {
        let count = model.selectionCount
        if canCompare, count <= CompareScreen.maxPhotoCount {
            return "\(count) selected・select up to \(CompareScreen.maxPhotoCount) to compare"
        }
        return "\(count) selected"
    }

    var body: some View {
        Text(countText)
            .font(.footnote.weight(.medium))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(.black.opacity(0.28))
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
    }
}

// MARK: - Bottom row

/// Create cluster · middle cluster · standalone Delete, distributed across the
/// width. Clusters are `EmptyView` when the hosting screen offers none of their
/// actions, so Delete always keeps the trailing slot.
private struct SelectionBottomRow: View {
    let model: SelectionBarModel
    @Binding var isMoreOpen: Bool

    private var hasMoreMenu: Bool {
        model.onAddToCollection != nil || model.onExportEXIF != nil || model.onDuplicate != nil
    }
    private var hasCreateCluster: Bool {
        model.onCollage != nil || model.onVideo != nil
    }
    private var hasMiddleCluster: Bool {
        model.onCompare != nil || model.onCompress != nil || hasMoreMenu
    }

    var body: some View {
        HStack(spacing: 8) {
            createCluster
            Spacer(minLength: 8)
            middleCluster
            Spacer(minLength: 8)
            SelectionCircleButton(
                systemImage: "trash",
                iconSize: 20,
                isEnabled: model.selectionCount > 0 && !model.isDeleting,
                action: model.onDelete
            )
            .accessibilityLabel("Delete")
        }
    }

    @ViewBuilder
    private var createCluster: some View {
        if hasCreateCluster {
            SelectionCluster {
                if let onCollage = model.onCollage {
                    SelectionTileButton(
                        isEnabled: CollageTemplateCatalog.supportedCounts.contains(model.imageSelectionCount),
                        action: onCollage
                    ) { CollageGlyph() }
                    .accessibilityLabel("Create Collage")
                }
                if let onVideo = model.onVideo {
                    SelectionTileButton(
                        isEnabled: model.selectionCount >= 1,
                        action: onVideo
                    ) { VideoGlyph() }
                    .accessibilityLabel("Create Video")
                }
            }
        }
    }

    @ViewBuilder
    private var middleCluster: some View {
        if hasMiddleCluster {
            SelectionCluster {
                if let onCompare = model.onCompare {
                    SelectionTileButton(
                        isEnabled: (2...CompareScreen.maxPhotoCount).contains(model.selectionCount),
                        action: onCompare
                    ) { CompareGlyph() }
                    .accessibilityLabel("Compare")
                }
                if let onCompress = model.onCompress {
                    SelectionTileButton(
                        isEnabled: model.imageSelectionCount >= 1,
                        action: onCompress
                    ) { CompressGlyph() }
                    .accessibilityLabel("Resize and Compress")
                }
                if hasMoreMenu {
                    SelectionTileButton(
                        isActive: isMoreOpen,
                        action: { isMoreOpen.toggle() }
                    ) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 21, weight: .regular))
                    }
                    .accessibilityLabel("More selection actions")
                }
            }
        }
    }
}

// MARK: - Custom action glyphs

/// Collage: a rounded frame split into one tall left cell and two stacked right
/// cells (matches the reference — an uneven grid, not a 2×2).
private struct CollageGlyph: View {
    var body: some View {
        CollageShape()
            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .frame(width: 23, height: 21)
    }
}

private struct CollageShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let corner = rect.width * 0.16
        path.addRoundedRect(in: rect, cornerSize: CGSize(width: corner, height: corner))
        let splitX = rect.minX + rect.width * 0.46
        path.move(to: CGPoint(x: splitX, y: rect.minY))
        path.addLine(to: CGPoint(x: splitX, y: rect.maxY))
        path.move(to: CGPoint(x: splitX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// Create Video: a photo frame with a play triangle and a music note — an image
/// turned into a video with music.
private struct VideoGlyph: View {
    var body: some View {
        HStack(spacing: 2.5) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                .frame(width: 15, height: 17)
                .overlay {
                    Triangle()
                        .frame(width: 6, height: 7.5)
                        .offset(x: -0.5)
                }
            // Note beside the frame, matched to its height.
            Image(systemName: "music.note")
                .font(.system(size: 17, weight: .regular))
        }
        .frame(height: 23)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Compare: two side-by-side portrait frames.
private struct CompareGlyph: View {
    var body: some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                .frame(width: 9, height: 20)
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                .frame(width: 9, height: 20)
        }
        .frame(width: 23, height: 23)
    }
}

/// Resize/Compress: four arrows pointing inward from the corners.
private struct CompressGlyph: View {
    var body: some View {
        CompressShape()
            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .frame(width: 23, height: 23)
    }
}

private struct CompressShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Short arrows: heads pulled back toward the corners so the four don't
        // bunch up in the centre.
        let inset = rect.width * 0.06
        let tip = rect.width * 0.34
        let barb = rect.width * 0.15
        let corners: [(CGPoint, CGPoint)] = [
            (CGPoint(x: rect.minX + inset, y: rect.minY + inset), CGPoint(x: rect.minX + tip, y: rect.minY + tip)),
            (CGPoint(x: rect.maxX - inset, y: rect.minY + inset), CGPoint(x: rect.maxX - tip, y: rect.minY + tip)),
            (CGPoint(x: rect.minX + inset, y: rect.maxY - inset), CGPoint(x: rect.minX + tip, y: rect.maxY - tip)),
            (CGPoint(x: rect.maxX - inset, y: rect.maxY - inset), CGPoint(x: rect.maxX - tip, y: rect.maxY - tip)),
        ]
        for (tail, head) in corners {
            let dx = head.x - tail.x
            let dy = head.y - tail.y
            let length = max(0.0001, (dx * dx + dy * dy).squareRoot())
            let ux = dx / length
            let uy = dy / length
            path.move(to: tail)
            path.addLine(to: head)
            // Arrowhead: two barbs opening back toward the corner along each axis.
            path.move(to: head)
            path.addLine(to: CGPoint(x: head.x - ux * barb, y: head.y))
            path.move(to: head)
            path.addLine(to: CGPoint(x: head.x, y: head.y - uy * barb))
        }
        return path
    }
}

// MARK: - ⋯ menu

/// Glass popover above the ⋯ button. Only the rows whose closures are supplied
/// appear; a hairline separates them.
private struct SelectionMoreMenu: View {
    let model: SelectionBarModel
    let close: () -> Void

    private struct Row: Identifiable {
        let id = UUID()
        let title: String
        let systemImage: String
        let action: () -> Void
    }

    private var rows: [Row] {
        var rows: [Row] = []
        if let action = model.onAddToCollection {
            rows.append(Row(title: "Add to Collection", systemImage: "rectangle.stack.badge.plus", action: action))
        }
        if let action = model.onExportEXIF {
            rows.append(Row(title: "Export EXIF (CSV)", systemImage: "tablecells", action: action))
        }
        if let action = model.onDuplicate {
            rows.append(Row(title: "Duplicate", systemImage: "plus.square.on.square", action: action))
        }
        return rows
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                Button {
                    close()
                    row.action()
                } label: {
                    HStack {
                        Text(row.title)
                            .font(.system(size: 15.5))
                            .foregroundStyle(.white)
                        Spacer(minLength: 12)
                        Image(systemName: row.systemImage)
                            .font(.system(size: 19, weight: .regular))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < rows.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 0.5)
                        .padding(.leading, 16)
                }
            }
        }
        .frame(width: 246)
        .glassBackground(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// MARK: - Building blocks

/// A glass pill holding a run of icon tiles. Roomy horizontal padding + tile
/// spacing so the glyphs sit off the pill's rounded edge and apart from each
/// other; the tile height keeps the cluster level (48pt) with the top row.
private struct SelectionCluster<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) {
            content
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .glassBackground(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// A 40pt icon tile inside a cluster, generic over its glyph so it can host an
/// SF Symbol or a custom-drawn icon. `isActive` gives the ⋯ its lit background
/// while its menu is open; a disabled tile dims but keeps its slot. The glyph
/// inherits the tile's tint (enabled = white, disabled = faded).
private struct SelectionTileButton<Icon: View>: View {
    @Environment(\.appAccent) private var accent
    var isEnabled: Bool = true
    var isActive: Bool = false
    let action: () -> Void
    @ViewBuilder var icon: Icon

    var body: some View {
        Button(action: action) {
            icon
                .foregroundStyle(isEnabled ? accent : accent.opacity(0.3))
                .frame(width: 40, height: 40)
                .background {
                    if isActive {
                        Circle().fill(Color.white.opacity(0.24))
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

/// A 48pt glass circle button (Share / Close / Delete). Bare white glyph — no
/// destructive tint on Delete; the confirm sheet is the safety net.
private struct SelectionCircleButton: View {
    let systemImage: String
    var iconSize: CGFloat = 20
    var isEnabled: Bool = true
    var showsSpinner: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if showsSpinner {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: iconSize, weight: .medium))
                        .foregroundStyle(isEnabled ? Color.white : Color.white.opacity(0.32))
                }
            }
            .frame(width: 48, height: 48)
            .contentShape(Circle())
            .glassBackground(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private extension View {
    /// Liquid Glass on iOS 26; a blurred material with a hairline edge and drop
    /// shadow on earlier tiers. Shared by every cluster, tray and circle button
    /// so the whole selection layer reads as one glass system.
    @ViewBuilder
    func glassBackground(_ shape: some InsettableShape) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
        }
    }
}

/// A subtle darkening backdrop that fades in toward the bottom edge so overlaid
/// text/controls stay readable over photos. Just a black gradient (no blur) —
/// anchor it to the screen bottom (`ignoresSafeArea`) so it reaches the real edge.
struct BottomScrim: View {
    var height: CGFloat = 220

    var body: some View {
        LinearGradient(
            colors: [.clear, .black.opacity(0.48)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    func model(_ count: Int, _ ids: [String]) -> SelectionBarModel {
        SelectionBarModel(
            selectionCount: count,
            imageSelectionCount: count,
            thumbnailIds: ids,
            photoLibrary: dependencies.photoLibrary,
            isDeleting: false,
            isPreparingShare: false,
            onShare: {},
            onClose: {},
            onDeselect: { _ in },
            onCollage: {},
            onVideo: {},
            onCompare: {},
            onCompress: {},
            onDelete: {},
            onAddToCollection: {},
            onExportEXIF: {},
            onDuplicate: {}
        )
    }
    return ZStack {
        LinearGradient(colors: [.teal, .indigo], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        SelectionOverlay(model: model(3, ["a", "b", "c"]))
    }
    .environment(dependencies.photoLibrary)
}
