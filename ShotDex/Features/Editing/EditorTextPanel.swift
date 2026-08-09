import SwiftUI
import UIKit

/// The Markup tab's list level: what is stacked on the photo, and how to add more.
///
/// Deliberately the same shape as `EditorMaskListPanel` — a plain `List` of card
/// rows — so the two layer lists in the editor read identically. Overlays reorder
/// by touch-and-hold drag (`.onMove`), the drag-handle glyph on the left saying so;
/// the drawing is fixed at the back and has no handle.
struct EditorTextPanel: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel
    let addText: () -> Void
    let addImage: () -> Void
    let startDrawing: () -> Void
    let openPresets: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            addBar
            header
            if controller.recipe.overlays.isEmpty, !controller.hasDrawing {
                emptyState
            } else {
                list
            }
        }
    }

    /// The three ways to add a layer. Three separate "add" buttons rather than one
    /// joined segmented control: the joined control read as a mode *picker* — "which
    /// of these is selected" — when every tap actually *creates* a layer. A leading
    /// accent `+` on each button says so outright.
    private var addBar: some View {
        HStack(spacing: 8) {
            addButton("Text", icon: "textformat", action: addText)
            addButton("Image", icon: "photo", action: addImage)
            addButton("Draw", icon: "scribble.variable", action: startDrawing)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    /// Matches the shared chip language of every other tab (`EditorChipButtonStyle`):
    /// RoundedRectangle bo 7, cao 28, chữ 12, nền `control` — not the old 44pt
    /// bo-12 pill. A leading accent `+` still marks it as "create", not "pick".
    private func addButton(
        _ title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(EditorTheme.accent)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(EditorTheme.control, in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(title)")
    }

    private var header: some View {
        HStack {
            Text(sectionTitle.uppercased())
                .font(EditorTheme.groupLabel)
                .tracking(1.1)
                .foregroundStyle(EditorTheme.secondaryText)
            Spacer(minLength: 0)
            Button("Presets", action: openPresets)
                .buttonStyle(EditorTextButtonStyle())
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
    }

    private var sectionTitle: String {
        let count = controller.recipe.overlays.count + (controller.hasDrawing ? 1 : 0)
        return count == 0 ? "Layers" : "Layers \u{00B7} \(count)"
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "textformat")
                .font(.system(size: 26))
                .foregroundStyle(EditorTheme.dimText)
            Text("No layers yet")
                .font(EditorTheme.rowLabel)
                .foregroundStyle(EditorTheme.secondaryText)
            Text("Add a caption, draw on the photo, or stamp a saved preset. "
                + "Text can carry the photo's own camera and exposure.")
                .font(EditorTheme.maskSubtitle)
                .foregroundStyle(EditorTheme.dimText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ZStack {
            // A tap on empty list space (below or between the cards) drops the
            // selection, the same as a tap on empty photo does — "tap off a layer to
            // deselect it" has to hold on the list too, not only on the picture.
            // Behind the List, which is transparent, so the rows still take their
            // own taps.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if controller.selectedOverlayID != nil {
                        controller.selectOverlay(nil)
                    }
                }
            layerList
        }
    }

    private var layerList: some View {
        List {
            // Reversed: the array is back-to-front for the renderer, and a layer
            // list reads front-to-back, the way every other layer list does.
            ForEach(controller.recipe.overlays.reversed()) { overlay in
                EditorLayerRow(
                    icon: overlay.kind.systemImage,
                    title: overlayTitle(overlay),
                    subtitle: overlaySubtitle(overlay),
                    isVisible: overlay.isVisible,
                    isSelected: controller.selectedOverlayID == overlay.id,
                    showsHandle: true,
                    onOpen: { controller.openOverlayDetail(overlay.id) },
                    onDetail: { controller.openOverlayDetail(overlay.id) },
                    onToggleVisibility: { controller.toggleOverlayVisibility(id: overlay.id) },
                    onDelete: { controller.deleteOverlay(id: overlay.id) }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 3, leading: 14, bottom: 3, trailing: 14))
            }
            .onMove { controller.moveOverlays(fromDisplay: $0, toDisplay: $1) }

            if controller.hasDrawing {
                EditorLayerRow(
                    icon: "scribble",
                    title: "Drawing",
                    subtitle: "Freehand",
                    isVisible: controller.drawingIsVisible,
                    isSelected: false,
                    showsHandle: false,
                    onOpen: startDrawing,
                    onDetail: startDrawing,
                    onToggleVisibility: { controller.toggleDrawingVisibility() },
                    onDelete: { controller.clearDrawing() }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 3, leading: 14, bottom: 3, trailing: 14))
                .moveDisabled(true)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 56)
    }

    /// A text layer is named by what it says, resolved — a row reading
    /// "{camera} · {focal}" tells the user nothing about which caption it is.
    private func overlayTitle(_ overlay: PhotoOverlay) -> String {
        switch overlay.kind {
        case .text:
            let resolved = controller.resolvedText(for: overlay)
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            return resolved.isEmpty ? "Empty text" : resolved
        case .image:
            return "Image"
        }
    }

    private func overlaySubtitle(_ overlay: PhotoOverlay) -> String {
        switch overlay.kind {
        case .text:
            return "Text"
        case .image:
            let missing = overlay.imageID.map { !OverlayImageStore().imageExists(id: $0) } ?? true
            return missing ? "Missing file" : "Photo layer"
        }
    }
}

/// One card row in a layer list, matching `EditorMaskRow`: an icon tile, a name and
/// subtitle, an eye toggle and a chevron. A tap opens the layer's detail; a trailing
/// swipe deletes it; a touch-and-hold drags it to reorder (when the enclosing list
/// enables `.onMove`), which the left-hand handle glyph advertises.
struct EditorLayerRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let isVisible: Bool
    let isSelected: Bool
    let showsHandle: Bool
    let onOpen: () -> Void
    let onDetail: () -> Void
    let onToggleVisibility: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(EditorTheme.dimText)
                .frame(width: 22)
                .opacity(showsHandle ? 1 : 0)
                .accessibilityHidden(true)

            iconTile
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(EditorTheme.maskTitle)
                    .foregroundStyle(rowTint)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(EditorTheme.maskSubtitle)
                    .foregroundStyle(EditorTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: onToggleVisibility) {
                Image(systemName: isVisible ? "eye" : "eye.slash")
                    .font(.system(size: 15))
                    .foregroundStyle(isVisible ? EditorTheme.accent : EditorTheme.dimText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isVisible ? "Hide \(title)" : "Show \(title)")

            Button(action: onDetail) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EditorTheme.secondaryText)
                    .frame(width: 30, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title) settings")
        }
        .padding(.leading, 10)
        .padding(.trailing, 2)
        .frame(height: 56)
        .background(
            isSelected ? EditorTheme.accent.opacity(0.13) : EditorTheme.maskRow,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .stroke(EditorTheme.accent.opacity(0.4), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var rowTint: Color {
        if isSelected { return EditorTheme.accent }
        return isVisible ? .white : EditorTheme.dimText
    }

    private var iconTile: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .frame(width: 42, height: 42)
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(EditorTheme.secondaryText)
            }
    }
}
