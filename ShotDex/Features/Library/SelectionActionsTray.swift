import Photos
import SwiftUI

/// Floating bottom controls shown during multi-select, in place of the tab bar
/// (which the screen hides while selecting). Three Liquid-Glass pieces plus the
/// count: a Compare chip always pinned left (greyed outside its 2–4 range), the
/// photo panel beside it, and a round Delete button (right), the selection count
/// on its own line below. Share lives in the top-bar leading slot.
///
/// Thumbnails: up to `CompareScreen.maxPhotoCount` (4) fixed slots — filled in
/// pick order, dashed empty slot otherwise. Past 4 the panel keeps the same
/// four-slot-wide window (Compare gone — it only ever applies to 2–4 photos)
/// but becomes a horizontal scroll of every selection, so the 5th photo already
/// overflows and it scrolls to the newest pick on each add. The panel is a pill
/// with circular slots nested concentrically inside. Tap a filled slot to
/// deselect it.
struct SelectionBottomBar: View {
    let selectionCount: Int
    /// Selected asset ids in pick order (drives the thumbnail preview).
    let thumbnailIds: [String]
    let photoLibrary: PhotoLibraryService
    /// nil hides Compare entirely (e.g. On This Day is delete-only).
    let onCompare: (() -> Void)?
    let onDelete: () -> Void
    /// Tapping a thumbnail slot removes that id from the selection.
    let onDeselect: (String) -> Void
    let isDeleting: Bool

    private var compareRange: ClosedRange<Int> { 2...CompareScreen.maxPhotoCount }
    /// Compare is always visible on the left (when the feature exists at all);
    /// it's only *enabled* in its usable range (2–4). Outside that it stays put
    /// but greys out, so the 2–4 requirement is legible rather than a chip that
    /// appears and disappears.
    private var compareEnabled: Bool { compareRange.contains(selectionCount) }
    private var isOverflowing: Bool { selectionCount > CompareScreen.maxPhotoCount }
    private var canCompare: Bool { onCompare != nil }
    /// Count line under the panel. When Compare is available and we're still in
    /// its range, spell out the 4-photo cap so the limit is discoverable; once
    /// the selection has passed 4 (Compare is gone) just show the running count.
    private var countText: String {
        guard canCompare else {
            return selectionCount == 0 ? "Select Photos" : "\(selectionCount) selected"
        }
        if selectionCount == 0 {
            return "Select up to 4 to compare"
        }
        if isOverflowing {
            return "\(selectionCount) selected"
        }
        return "\(selectionCount) selected · up to 4 to compare"
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                if let onCompare {
                    // Compare pinned at the leading edge, always present: its gap
                    // to the screen edge (the bar's 16pt padding) equals its 16pt
                    // spacing to the panel, so its margins read symmetric. It
                    // greys out outside 2–4 rather than moving.
                    compareChip(onCompare)
                } else {
                    // No Compare feature (e.g. On This Day) → center the panel.
                    Spacer(minLength: 0)
                }
                // Panel keeps its intrinsic width (a fixed 4-slot window even
                // when overflowing) so adding a 5th photo overflows the strip
                // immediately and it scrolls on every pick.
                photoPanel
                Spacer(minLength: 0)
                deleteButton
            }
            Text(countText)
                .font(.footnote.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .animation(.snappy(duration: 0.2), value: selectionCount)
    }

    private var deleteButton: some View {
        GlassIconButton(
            systemImage: "trash",
            accessibilityLabel: "Delete",
            tint: .red,
            isEnabled: selectionCount > 0 && !isDeleting,
            action: onDelete
        )
    }

    /// Standalone Liquid-Glass "Compare" pill, left of the photo panel. Fully
    /// rounded (capsule), matching the toolbar indexing chip. Always visible;
    /// disabled (greyed) outside its 2–4 range so the requirement stays legible.
    private func compareChip(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            GlassPanel(cornerRadius: 100) {
                Text("Compare")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(compareEnabled ? .primary : .tertiary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
            }
        }
        .buttonStyle(.plain)
        .disabled(!compareEnabled)
        .accessibilityLabel("Compare")
    }

    private var photoPanel: some View {
        // Fully-rounded pill; the slots inside share a concentric corner.
        GlassPanel(cornerRadius: selectionPanelCorner) {
            SelectionThumbnailStrip(
                ids: thumbnailIds,
                photoLibrary: photoLibrary,
                onDeselect: onDeselect
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

/// The photo panel is a pill: its corner is half its height (a 36pt thumbnail
/// plus 8pt vertical padding top and bottom = 52pt tall → 26pt corner).
private let selectionPanelCorner: CGFloat = 26
/// Slots (filled thumbnail + empty placeholder) are inset from the pill by its
/// 8pt vertical padding, so a corner of 26 − 8 = 18 keeps them concentric with
/// the pill — and since a 36pt slot's half-side is also 18, they read as circles
/// nested inside the capsule.
private let selectionSlotCorner: CGFloat = 18

/// The thumbnail preview inside the photo panel: four fixed slots for a
/// selection of up to four, or a horizontal scroll of every selected thumbnail
/// beyond that.
private struct SelectionThumbnailStrip: View {
    let ids: [String]
    let photoLibrary: PhotoLibraryService
    let onDeselect: (String) -> Void

    private let side: CGFloat = 36
    private let spacing: CGFloat = 6
    private var maxSlots: Int { CompareScreen.maxPhotoCount }
    /// Visible width of the strip: exactly the four fixed slots. Beyond four the
    /// scroll keeps this same window, so the 5th photo already overflows and the
    /// strip scrolls on every pick (no waiting to accumulate width).
    private var windowWidth: CGFloat {
        side * CGFloat(maxSlots) + spacing * CGFloat(maxSlots - 1)
    }

    var body: some View {
        if ids.count > maxSlots {
            // Show all selected, horizontally scrollable — no stacking. A
            // trailing default anchor keeps the strip pinned to its right edge:
            // every added photo grows the content and the scroll re-anchors to
            // the newest (rightmost) pick automatically — no manual scrollTo
            // that lags a frame behind the insertion.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) {
                    ForEach(ids, id: \.self) { id in
                        SelectionThumbnail(assetId: id, photoLibrary: photoLibrary, side: side)
                            .onTapGesture { onDeselect(id) }
                    }
                }
            }
            .frame(width: windowWidth)
            .defaultScrollAnchor(.trailing)
        } else {
            HStack(spacing: spacing) {
                ForEach(0..<maxSlots, id: \.self) { index in
                    if index < ids.count {
                        let id = ids[index]
                        SelectionThumbnail(assetId: id, photoLibrary: photoLibrary, side: side)
                            .onTapGesture { onDeselect(id) }
                    } else {
                        emptySlot
                    }
                }
            }
        }
    }

    private func scrollToNewest(_ proxy: ScrollViewProxy) {
        guard let last = ids.last else { return }
        withAnimation(.snappy(duration: 0.25)) {
            proxy.scrollTo(last, anchor: .trailing)
        }
    }

    /// Empty slot: a faint filled rounded square with a dashed border and a photo
    /// glyph — same shape as the filled thumbnail, so the capacity reads as
    /// "photo goes here" without looking like a foreign element.
    private var emptySlot: some View {
        RoundedRectangle(cornerRadius: selectionSlotCorner, style: .continuous)
            .fill(Color(.tertiarySystemFill))
            .frame(width: side, height: side)
            .overlay {
                RoundedRectangle(cornerRadius: selectionSlotCorner, style: .continuous)
                    .strokeBorder(
                        Color(.tertiaryLabel),
                        style: StrokeStyle(lineWidth: 1, dash: [3])
                    )
            }
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
    }
}

/// One thumbnail slot. Loads a local (never networked) thumbnail for the asset,
/// mirroring the grid tile's request. Reloads in place when its id changes (the
/// collapsed single-slot view reuses one instance as the last selection moves).
private struct SelectionThumbnail: View {
    let assetId: String
    let photoLibrary: PhotoLibraryService
    var side: CGFloat = 34

    @State private var image: UIImage?
    @State private var requestId: PHImageRequestID?

    var body: some View {
        RoundedRectangle(cornerRadius: selectionSlotCorner, style: .continuous)
            .fill(Color(.secondarySystemBackground))
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: selectionSlotCorner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: selectionSlotCorner, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
            )
            // Small deselect hint: tapping the thumbnail removes it, and the "x"
            // makes that discoverable. It straddles the top-right corner —
            // mostly outside the image so it hides only a sliver.
            .overlay(alignment: .topTrailing) {
                deselectBadge
                    .offset(x: 6, y: -6)
            }
            .contentShape(RoundedRectangle(cornerRadius: selectionSlotCorner, style: .continuous))
            .onAppear(perform: load)
            .onChange(of: assetId) { load() }
            .onDisappear(perform: cancel)
    }

    private var deselectBadge: some View {
        Image(systemName: "xmark.circle.fill")
            .font(.system(size: 14, weight: .bold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, .black.opacity(0.5))
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

/// Checkmark badge on a grid tile during multi-select.
struct SelectionBadge: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22))
            .foregroundStyle(isSelected ? Color.accentColor : .white)
            .background(Circle().fill(isSelected ? .white : .black.opacity(0.35)))
            .padding(6)
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    return ZStack(alignment: .bottom) {
        LinearGradient(colors: [.teal, .indigo], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        VStack(spacing: 24) {
            SelectionBottomBar(selectionCount: 0, thumbnailIds: [], photoLibrary: dependencies.photoLibrary, onCompare: {}, onDelete: {}, onDeselect: { _ in }, isDeleting: false)
            SelectionBottomBar(selectionCount: 3, thumbnailIds: ["a", "b", "c"], photoLibrary: dependencies.photoLibrary, onCompare: {}, onDelete: {}, onDeselect: { _ in }, isDeleting: false)
            SelectionBottomBar(selectionCount: 7, thumbnailIds: ["a", "b", "c", "d", "e", "f", "g"], photoLibrary: dependencies.photoLibrary, onCompare: nil, onDelete: {}, onDeselect: { _ in }, isDeleting: false)
        }
    }
    .environment(dependencies.photoLibrary)
}
