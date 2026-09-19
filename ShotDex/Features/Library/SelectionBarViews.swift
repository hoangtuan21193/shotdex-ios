import Photos
import SwiftUI

private extension View {
    /// Native Liquid Glass for the selection chrome — the same material iOS
    /// Photos uses for its floating bars. On iOS 26 this is real `glassEffect`
    /// (translucent, with vibrancy so monochrome glyphs stay legible); a blurred
    /// material fallback earlier. No dark tint: keep it clean like Photos.
    func selectionGlass(_ shape: some InsettableShape) -> some View {
        glassBackground(shape)
    }
}

/// The floating half of the multi-select chrome, modelled on the iOS Photos
/// app: one bottom bar over the grid — `Share · caption · Delete`. Everything
/// else (the × that leaves selection, and the create/compare/⋯ actions) lives in
/// the hosting screen's own navigation bar via `SelectionToolbarItems`, so the
/// screen title and the grid's pinned date header keep the exact position they
/// have while browsing.
///
/// Nothing here paints a solid background: the grid stays the root scroll view
/// and shows through the gaps, so only the glass controls intercept touches.
struct SelectionOverlay: View {
    let model: SelectionBarModel
    @State private var isSelectedItemsPresented = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            SelectionBottomBar(
                model: model,
                showSelected: { isSelectedItemsPresented = true }
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .animation(.snappy(duration: 0.2), value: model.selectionCount)
        .sheet(isPresented: $isSelectedItemsPresented) {
            SelectedItemsSheet(model: model)
        }
    }
}

// MARK: - Bottom bar

/// Share (leading) · count/size caption (centre) · Delete (trailing) — the
/// Photos arrangement. Share and Delete are 48pt glass circles and keep their
/// slots while nothing is picked; the caption then reads "Select Items".
private struct SelectionBottomBar: View {
    let model: SelectionBarModel
    let showSelected: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            SelectionCircleButton(
                systemImage: "square.and.arrow.up",
                iconSize: 21,
                isEnabled: model.selectionCount > 0 && !model.isPreparingShare,
                showsSpinner: model.isPreparingShare,
                action: model.onShare
            )
            .accessibilityLabel("Share")

            SelectionCountCaption(model: model, action: showSelected)
                .frame(maxWidth: .infinity)

            SelectionCircleButton(
                systemImage: "trash",
                iconSize: 20,
                isEnabled: model.selectionCount > 0 && !model.isDeleting,
                action: model.onDelete
            )
            .accessibilityLabel("Delete")
        }
    }
}

// MARK: - Count caption

/// Selection count and total file size on a glass pill between Share and
/// Delete, where Photos labels its own selection bar. It is a button: tapping it
/// opens `SelectedItemsSheet`, the way Photos opens the list of what's picked.
/// An empty selection reads "Select Items" and does nothing.
struct SelectionCountCaption: View {
    let model: SelectionBarModel
    let action: () -> Void

    /// Summed indexed bytes and how many of the selected ids had a known size —
    /// `knownCount < selectionCount` prints the total as an estimate (`~`).
    @State private var totalBytes: Int64 = 0
    @State private var knownCount = 0

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        // "0 KB", not "Zero KB", while a selection is still un-indexed.
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    /// e.g. "24.5MB" when every pick is indexed, "~24.5MB" while some size is
    /// still missing (or nothing indexed yet). Space-free so the whole label
    /// stays on one line on a 393pt frame.
    private var sizeText: String {
        let formatted = Self.byteFormatter.string(fromByteCount: totalBytes)
            .replacingOccurrences(of: " ", with: "")
        return knownCount < model.selectionCount ? "~\(formatted)" : formatted
    }

    private var captionText: String {
        guard model.selectionCount > 0 else { return "Select Items" }
        return "Show Selected (\(model.selectionCount)・\(sizeText))"
    }

    var body: some View {
        Button(action: action) {
            Text(captionText)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(model.selectionCount > 0 ? Color.primary : Color.primary.opacity(0.3))
                .padding(.horizontal, 18)
                // Same 48pt height and glass as the Share/Delete circles, so
                // the three read as one bar.
                .frame(height: 48)
                .contentShape(Capsule())
                .selectionGlass(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.selectionCount == 0)
        .task(id: model.selectedIds) { await recomputeSize() }
    }

    private func recomputeSize() async {
        let ids = model.selectedIds
        guard !ids.isEmpty else {
            totalBytes = 0
            knownCount = 0
            return
        }
        if let result = try? await model.libraryQueries.fileSizeTotal(assetIds: ids) {
            totalBytes = result.bytes
            knownCount = result.knownCount
        }
    }
}

// MARK: - Navigation bar items

/// The navigation-bar half of the selection chrome: a ⋯ menu carrying every
/// action that isn't Share or Delete, plus the × that leaves selection mode.
/// Screens add it to their existing `.toolbar` while selecting — the bar itself
/// never hides, so the title, the date under it and the grid's pinned headers
/// stay put when selection starts.
struct SelectionToolbarItems: ToolbarContent {
    let model: SelectionBarModel

    private var hasMenu: Bool {
        model.onCollage != nil || model.onVideo != nil || model.onCompress != nil
            || model.onAddToCollection != nil || model.onExportEXIF != nil
            || model.onDuplicate != nil || model.assetActions != nil
            || model.onSelectAll != nil || model.onRemoveFromAlbum != nil
    }

    var body: some ToolbarContent {
        // Compare is the one action with its own button: it takes the leading
        // slot the Settings gear vacates when selection starts, spelled out.
        ToolbarItem(placement: .topBarLeading) {
            if let onCompare = model.onCompare {
                Button("Compare", action: onCompare)
                    .tint(.primary)
                    .disabled(model.selectionCount < CompareScreen.minPhotoCount)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if hasMenu {
                Menu {
                    if let onEdit = model.onEdit {
                        Button(action: onEdit) {
                            Label("Edit", systemImage: "slider.horizontal.3")
                        }
                        .disabled(model.imageSelectionCount < 1)
                    }
                    if let onCollage = model.onCollage {
                        Button(action: onCollage) {
                            Label("Create Collage", systemImage: "square.grid.2x2")
                        }
                        .disabled(!CollageTemplateCatalog.supportedCounts.contains(model.imageSelectionCount))
                    }
                    if let onVideo = model.onVideo {
                        Button(action: onVideo) {
                            Label("Create Video", systemImage: "film")
                        }
                        .disabled(model.selectionCount < 1)
                    }
                    if let onCompress = model.onCompress {
                        Button(action: onCompress) {
                            Label("Resize", systemImage: "arrow.down.right.and.arrow.up.left")
                        }
                        .disabled(model.imageSelectionCount < 1)
                    }
                    if let onAddToCollection = model.onAddToCollection {
                        Button(action: onAddToCollection) {
                            Label("Add to Collection", systemImage: "rectangle.stack.badge.plus")
                        }
                        .disabled(model.selectionCount < 1)
                    }
                    if let onExportEXIF = model.onExportEXIF {
                        Button(action: onExportEXIF) {
                            Label("Export EXIF (CSV)", systemImage: "tablecells")
                        }
                        .disabled(model.imageSelectionCount < 1)
                    }
                    if let onDuplicate = model.onDuplicate {
                        Button(action: onDuplicate) {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        .disabled(model.selectionCount < 1)
                    }
                    libraryActions
                    destructiveActions
                } label: {
                    Image(systemName: "ellipsis")
                }
                .tint(.primary)
                .accessibilityLabel("More selection actions")
            }
        }
        // Break the shared Liquid Glass container: × gets its own circle beside
        // the filter/⋯ capsule, the way Photos separates it.
        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: model.onClose) {
                Image(systemName: "xmark")
            }
            .tint(.primary)
            .accessibilityLabel("Done selecting")
        }
    }
}

// MARK: - Selection menu sections

private extension SelectionToolbarItems {
    /// Favorite / Hide / Adjust Date & Time / Adjust Location / Copy, plus
    /// Select All — the block Photos keeps in its own ⋯ menu. Grouped into a
    /// `Section` so the system draws a divider between these and the
    /// ShotDex-specific rows above.
    @ViewBuilder
    var libraryActions: some View {
        Section {
            if let onSelectAll = model.onSelectAll {
                Button(action: onSelectAll) {
                    Label("Select All", systemImage: "checkmark.circle")
                }
            }
            if let actions = model.assetActions {
                let ids = model.selectedIds
                let allFavorites = model.isSelectionAllFavorites
                Button {
                    actions.toggleFavorite(ids: ids)
                } label: {
                    Label(
                        allFavorites ? "Unfavorite" : "Favorite",
                        systemImage: allFavorites ? "heart.slash" : "heart"
                    )
                }
                .disabled(model.selectionCount < 1)

                Button {
                    actions.presentAdjustDate(ids: ids)
                } label: {
                    Label("Adjust Date & Time", systemImage: "calendar")
                }
                .disabled(model.selectionCount < 1)

                Button {
                    actions.presentAdjustLocation(ids: ids)
                } label: {
                    Label("Adjust Location", systemImage: "mappin.and.ellipse")
                }
                .disabled(model.selectionCount < 1)

                if model.selectionCount == 1, let id = ids.first {
                    Button {
                        actions.copyToPasteboard(id: id)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            }
        }
    }

    /// Rows that take photos out of something. Kept in their own section, below
    /// everything else, so a mis-tap on the additive rows can't land here.
    @ViewBuilder
    var destructiveActions: some View {
        Section {
            if let actions = model.assetActions {
                let allHidden = model.isSelectionAllHidden
                Button(role: allHidden ? nil : .destructive) {
                    actions.toggleHidden(ids: model.selectedIds)
                } label: {
                    Label(
                        allHidden ? "Unhide" : "Hide",
                        systemImage: allHidden ? "eye" : "eye.slash"
                    )
                }
                .disabled(model.selectionCount < 1)
            }
            if let onRemoveFromAlbum = model.onRemoveFromAlbum {
                Button(role: .destructive, action: onRemoveFromAlbum) {
                    Label("Remove from Album", systemImage: "minus.circle")
                }
                .disabled(model.selectionCount < 1)
            }
        }
    }
}

// MARK: - Building blocks

/// A 48pt glass circle button (Share / Delete). Bare monochrome glyph — no
/// destructive tint on Delete; PhotoKit's own confirmation is the safety net.
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
                    ProgressView().tint(.primary)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: iconSize, weight: .medium))
                        .foregroundStyle(isEnabled ? Color.primary : Color.primary.opacity(0.3))
                }
            }
            .frame(width: 48, height: 48)
            .contentShape(Circle())
            .selectionGlass(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
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
            selectedIds: ids,
            photoLibrary: dependencies.photoLibrary,
            libraryQueries: dependencies.libraryQueries,
            isDeleting: false,
            isPreparingShare: false,
            onShare: {},
            onClose: {},
            onDeselect: { _ in },
            onDeselectAll: {},
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
