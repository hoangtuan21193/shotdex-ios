import Photos
import SwiftUI

/// Multi-select bottom controls, composed from small pieces so both platform
/// tiers can host them: the iOS 26 system `.tabViewBottomAccessory`
/// (`SelectionAccessory`, placement-aware) and the pre-26 `.safeAreaInset`
/// (`SelectionBottomBar`). The row mirrors the reference layout —
/// `[ Compare | thumbnails | Delete ]` — with the selection count above it.
///
/// Compare is a leading pill, greyed outside its usable range
/// (`2...CompareScreen.maxPhotoCount`); the centre holds up to
/// `CompareScreen.maxPhotoCount` thumbnail slots (dashed placeholders when
/// unfilled, a trailing-anchored horizontal scroll past the max); Delete is a
/// destructive round button. Share lives in the top-bar leading slot.

/// Shared Compare-enablement rule. Selection itself is uncapped; Compare is only
/// *enabled* in `2...CompareScreen.maxPhotoCount` and greys out otherwise (below
/// 2 or above the max) so the requirement stays legible.
private func compareEnabled(for count: Int) -> Bool {
    (2...CompareScreen.maxPhotoCount).contains(count)
}

/// Leading Compare label. `model.onCompare == nil` hides it entirely (e.g. On
/// This Day is delete-only). Bare text — no token; it rides the shared accessory
/// glass. Label pinned to its intrinsic size with a high layout priority so it
/// never clips behind the centre thumbnails.
struct SelectionCompareControl: View {
    let model: SelectionBarModel

    var body: some View {
        if let onCompare = model.onCompare {
            Button(action: onCompare) {
                Text("Compare")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(compareEnabled(for: model.selectionCount) ? Color.accentColor : Color(.tertiaryLabel))
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!compareEnabled(for: model.selectionCount))
            .accessibilityLabel("Compare")
            .layoutPriority(1)
        }
    }
}

/// The centre thumbnail slots. `styled` wraps them in the `GlassPanel` pill for
/// the pre-26 bar; the iOS 26 accessory passes `styled: false` and lets the
/// system supply the glass.
struct SelectionSlots: View {
    let model: SelectionBarModel
    var styled: Bool

    var body: some View {
        let strip = SelectionThumbnailStrip(
            ids: model.thumbnailIds,
            photoLibrary: model.photoLibrary,
            onDeselect: model.onDeselect
        )
        if styled {
            GlassPanel(cornerRadius: selectionPanelCorner) {
                strip
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        } else {
            strip
        }
    }
}

/// Trailing destructive Delete button (replaces Search during selection). Bare
/// trash glyph — no token; it rides the shared accessory glass.
struct SelectionDeleteControl: View {
    let model: SelectionBarModel

    private var isEnabled: Bool { model.selectionCount > 0 && !model.isDeleting }

    var body: some View {
        Button(action: model.onDelete) {
            Image(systemName: "trash")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isEnabled ? Color.red : Color(.tertiaryLabel))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("Delete")
        .layoutPriority(1)
    }
}

/// The selection count caption. Empty when nothing is selected (the bar stays,
/// only the caption drops). When Compare is available and still in range it
/// spells out the cap; past the max it shows just the running count.
struct SelectionCountCaption: View {
    let model: SelectionBarModel

    private var canCompare: Bool { model.onCompare != nil }
    private var isOverflowing: Bool { model.selectionCount > CompareScreen.maxPhotoCount }
    private var countText: String {
        let n = model.selectionCount
        guard canCompare, !isOverflowing else { return "\(n) selected" }
        return "\(n) selected · up to \(CompareScreen.maxPhotoCount) to compare"
    }

    var body: some View {
        if model.selectionCount > 0 {
            // Colour is set by the host (secondary in the iOS 26 accessory, white
            // over the pre-26 scrim) — don't pin it here or it would win over the
            // host's tint.
            Text(countText)
                .font(.footnote.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

/// The controls row shared by both tiers: `[ Compare | thumbnails | Delete ]`.
/// `slotsStyled: true` for the custom pre-26 bar; `false` inside the system
/// accessory. The centre slots take the remaining width; Compare and Delete keep
/// their intrinsic size via `layoutPriority` so neither clips on narrow devices.
struct SelectionBarRow: View {
    let model: SelectionBarModel
    var slotsStyled: Bool

    init(_ model: SelectionBarModel, slotsStyled: Bool) {
        self.model = model
        self.slotsStyled = slotsStyled
    }

    var body: some View {
        HStack(spacing: 12) {
            SelectionCompareControl(model: model)
            SelectionSlots(model: model, styled: slotsStyled)
            SelectionDeleteControl(model: model)
        }
    }
}

/// iOS 26 bottom-accessory content: just the `[ Compare | thumbnails | Delete ]`
/// controls row (bare controls on the system glass). The count caption is NOT
/// here — the root tab view floats it above the accessory band (see
/// `SelectionCountBanner`). Takes a non-optional model (the root tab view unwraps
/// `navigation.selectionBar`).
@available(iOS 26.0, *)
struct SelectionAccessory: View {
    let model: SelectionBarModel

    init(_ model: SelectionBarModel) { self.model = model }

    var body: some View {
        SelectionBarRow(model, slotsStyled: false)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
    }
}

/// Pre-iOS 26 selection bar (hosted via the root tab view's `.safeAreaInset`): the
/// count caption floats above a single glass band holding the bare
/// `[ Compare | thumbnails | Delete ]` row — mirroring the iOS 26 accessory
/// (one glass surface, no per-control tokens; count sits outside/above it).
struct SelectionBottomBar: View {
    let model: SelectionBarModel

    init(_ model: SelectionBarModel) { self.model = model }

    var body: some View {
        VStack(spacing: 6) {
            SelectionCountCaption(model: model)
                .foregroundStyle(.white)
            GlassPanel(cornerRadius: 30) {
                SelectionBarRow(model, slotsStyled: false)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .animation(.snappy(duration: 0.2), value: model.selectionCount)
    }
}

/// The count caption as a free-floating label the root tab view overlays *above* the
/// iOS 26 tab-bar accessory band (over the grid, no token). The system exposes no
/// frame for the accessory, so its clearance is a tuned constant
/// (`accessoryClearance`) — nudge it if the tab bar / accessory metrics change.
/// A soft shadow keeps the plain text legible over bright photos.
@available(iOS 26.0, *)
struct SelectionCountBanner: View {
    let model: SelectionBarModel

    /// Height of the tab bar + selection accessory + a small gap, measured from
    /// the bottom safe-area edge (where a `.bottom` overlay anchors).
    private let accessoryClearance: CGFloat = 118

    var body: some View {
        SelectionCountCaption(model: model)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background {
                Capsule()
                    .fill(.black.opacity(0.28))
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
            .padding(.bottom, accessoryClearance)
            .allowsHitTesting(false)
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

/// The photo panel is a pill: its corner is half its height (a 36pt thumbnail
/// plus 8pt vertical padding top and bottom = 52pt tall → 26pt corner).
private let selectionPanelCorner: CGFloat = 26
/// Slots (filled thumbnail + empty placeholder) read as near-square rounded
/// rectangles — a small corner on the 36pt slot, not the half-side that would
/// round them into circles. The panel stays a pill (`selectionPanelCorner`).
private let selectionSlotCorner: CGFloat = 6

/// The thumbnail preview inside the photo panel: four fixed slots for a
/// selection of up to four, or a horizontal scroll of every selected thumbnail
/// beyond that.
struct SelectionThumbnailStrip: View {
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

#Preview {
    let dependencies = AppDependencies.preview()
    func model(_ count: Int, _ ids: [String], compare: Bool) -> SelectionBarModel {
        SelectionBarModel(
            selectionCount: count,
            thumbnailIds: ids,
            photoLibrary: dependencies.photoLibrary,
            onCompare: compare ? {} : nil,
            onDelete: {},
            onDeselect: { _ in },
            isDeleting: false
        )
    }
    return ZStack(alignment: .bottom) {
        LinearGradient(colors: [.teal, .indigo], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        VStack(spacing: 24) {
            SelectionBottomBar(model(0, [], compare: true))
            SelectionBottomBar(model(3, ["a", "b", "c"], compare: true))
            SelectionBottomBar(model(7, ["a", "b", "c", "d", "e", "f", "g"], compare: false))
        }
    }
    .environment(dependencies.photoLibrary)
}
