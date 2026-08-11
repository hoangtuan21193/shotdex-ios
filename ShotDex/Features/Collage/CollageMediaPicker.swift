import Photos
import SwiftUI

/// The empty-slot photo picker (§6). Slides up over the dimmed collage as a
/// large sheet with tier-D chrome: a tab row (Recents / Favorites / Selected /
/// Screenshots), a 3-column grid whose picks carry a numbered accent ring, and a
/// footer that counts the selection against the slots still open. The selection
/// is capped at the number of empty slots, so Add photo can only ever fill what
/// there is room for.
struct CollageMediaPicker: View {
    @Bindable var model: CollageEditorModel
    let photoLibrary: PhotoLibraryService
    /// How many photos may be picked — the empty slots left to fill.
    let slotCapacity: Int
    let onAdd: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var tab: CollagePickerTab = .recents
    @State private var assets: [PHAsset] = []
    /// Picked ids, in tap order — the order they fill the slots and the number
    /// shown on each ring.
    @State private var selection: [String] = []

    private var slotsLeft: Int { max(0, slotCapacity - selection.count) }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            tabRow
            grid
            footer
        }
        .background(EditorTheme.panelSolid)
        .preferredColorScheme(.dark)
        .task(id: tab) { await loadAssets() }
    }

    // MARK: Tabs

    private var tabRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.sm) {
                ForEach(CollagePickerTab.allCases) { item in
                    Button {
                        tab = item
                    } label: {
                        Text(item.title(selectedCount: model.assets.count))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tab == item ? .black : .white)
                            .padding(.horizontal, AppTheme.Spacing.md)
                            .frame(height: AppTheme.Size.pillHeightLight)
                            .background(
                                Capsule().fill(tab == item ? EditorTheme.accent : Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppTheme.Size.screenMargin)
        }
        .padding(.top, AppTheme.Spacing.md)
        .padding(.bottom, AppTheme.Spacing.sm)
    }

    // MARK: Grid

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(assets, id: \.localIdentifier) { asset in
                    let index = selection.firstIndex(of: asset.localIdentifier)
                    CollagePickerCell(
                        asset: asset,
                        photoLibrary: photoLibrary,
                        selectionNumber: index.map { $0 + 1 }
                    )
                    .onTapGesture { toggle(asset.localIdentifier) }
                }
            }
            .padding(.horizontal, 3)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Text(footerText)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(EditorTheme.secondaryText)
            Spacer()
            Button {
                onAdd(selection)
                dismiss()
            } label: {
                Text("Add photo")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, AppTheme.Spacing.xl)
                    .frame(height: AppTheme.Size.primaryActionHeight - 8)
                    .background(EditorTheme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(selection.isEmpty)
            .opacity(selection.isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, AppTheme.Size.screenMargin)
        .padding(.vertical, AppTheme.Spacing.md)
        .background(EditorTheme.panelSolid)
        .overlay(alignment: .top) {
            Rectangle().fill(EditorTheme.panelDivider).frame(height: 1)
        }
    }

    private var footerText: String {
        let selectedCount = selection.count
        let left = slotsLeft
        let leftWord = left == 1 ? "slot" : "slots"
        return "\(selectedCount) selected · \(left) \(leftWord) left"
    }

    // MARK: Behaviour

    private func toggle(_ id: String) {
        if let index = selection.firstIndex(of: id) {
            selection.remove(at: index)
        } else if selection.count < slotCapacity {
            selection.append(id)
        }
        // Silently ignore taps beyond capacity — the footer already reads 0 left.
    }

    private func loadAssets() async {
        let tab = tab
        let fetched: [PHAsset]
        switch tab {
        case .selected:
            let ids = orderedSelectedIDs()
            fetched = ids.compactMap { model.asset(id: $0) }
        case .recents:
            fetched = CollagePickerFetch.recents()
        case .favorites:
            fetched = CollagePickerFetch.smartAlbum(.smartAlbumFavorites)
        case .screenshots:
            fetched = CollagePickerFetch.smartAlbum(.smartAlbumScreenshots)
        }
        assets = fetched
    }

    /// The photos already in this collage session: the tray plus the pool, deduped.
    private func orderedSelectedIDs() -> [String] {
        var seen = Set<String>()
        var ids: [String] = []
        for id in model.unplaced + model.assets.map(\.localIdentifier) where seen.insert(id).inserted {
            ids.append(id)
        }
        return ids
    }
}

enum CollagePickerTab: String, CaseIterable, Identifiable {
    case recents, favorites, selected, screenshots
    var id: String { rawValue }

    func title(selectedCount: Int) -> String {
        switch self {
        case .recents: String(localized: "Recents")
        case .favorites: String(localized: "Favorites")
        case .selected: String(localized: "Selected \(selectedCount)")
        case .screenshots: String(localized: "Screenshots")
        }
    }
}

/// PhotoKit fetches for the picker tabs. Images only — a collage is photos.
enum CollagePickerFetch {
    static func recents(limit: Int = 400) -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.fetchLimit = limit
        return collect(PHAsset.fetchAssets(with: .image, options: options))
    }

    static func smartAlbum(_ subtype: PHAssetCollectionSubtype, limit: Int = 400) -> [PHAsset] {
        let collections = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum, subtype: subtype, options: nil
        )
        guard let collection = collections.firstObject else { return [] }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.fetchLimit = limit
        return collect(PHAsset.fetchAssets(in: collection, options: options))
    }

    private static func collect(_ result: PHFetchResult<PHAsset>) -> [PHAsset] {
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }
}

/// One grid cell: a square thumbnail with a numbered accent ring when picked.
/// The 3pt gutter squares are below the 44pt minimum, but the whole cell is the
/// tap target, so the effective area is a full grid third — well over 44.
private struct CollagePickerCell: View {
    let asset: PHAsset
    let photoLibrary: PhotoLibraryService
    let selectionNumber: Int?

    @State private var image: UIImage?

    var body: some View {
        EditorTheme.control
            .aspectRatio(1, contentMode: .fill)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .overlay {
                if selectionNumber != nil {
                    Rectangle().strokeBorder(EditorTheme.accent, lineWidth: 2.5)
                }
            }
            .overlay(alignment: .topTrailing) { ring }
            .contentShape(Rectangle())
            .onAppear {
                guard image == nil else { return }
                _ = photoLibrary.requestThumbnail(
                    for: asset,
                    targetSize: CGSize(width: 300, height: 300),
                    allowNetwork: false
                ) { result in
                    if let result { image = result }
                }
            }
    }

    @ViewBuilder
    private var ring: some View {
        if let number = selectionNumber {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundStyle(.black)
                .frame(width: 22, height: 22)
                .background(Circle().fill(EditorTheme.accent))
                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                .padding(AppTheme.Spacing.xs)
        }
    }
}
