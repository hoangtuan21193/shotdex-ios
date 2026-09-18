import Photos
import SwiftUI

/// The sheet behind the selection bar's count button — Photos' "N Photos
/// Selected" view: every pick in a grid, each tap deselecting it, plus Deselect
/// All. Purely a view onto the hosting screen's selection: it holds no state of
/// its own, so a deselect here lands in the same place a tap on the grid does.
struct SelectedItemsSheet: View {
    let model: SelectionBarModel

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 2)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(model.selectedIds, id: \.self) { assetId in
                        SelectedItemTile(
                            assetId: assetId,
                            photoLibrary: model.photoLibrary,
                            onTap: { model.onDeselect(assetId) }
                        )
                    }
                }
                .padding(.horizontal, 2)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .tint(.primary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Deselect All") {
                    model.onDeselectAll()
                    dismiss()
                }
                .font(.body.weight(.medium))
                .tint(.primary)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .glassBackground(Capsule())
                .padding(.bottom, 12)
            }
            // Deselecting the last pick leaves nothing to show — Photos closes
            // the view with it.
            .onChange(of: model.selectionCount) { _, count in
                if count == 0 { dismiss() }
            }
        }
    }

    private var title: String {
        let count = model.selectionCount
        return "\(count) \(count == 1 ? "Photo" : "Photos") Selected"
    }
}

/// One square tile with the same accent check badge the grid uses, so a pick
/// reads identically in both places. Tapping anywhere on it deselects.
private struct SelectedItemTile: View {
    let assetId: String
    let photoLibrary: PhotoLibraryService
    let onTap: () -> Void

    @State private var image: UIImage?
    @State private var requestId: PHImageRequestID?

    var body: some View {
        Button(action: onTap) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .opacity(0.82)
                    } else {
                        Rectangle().fill(Color.primary.opacity(0.08))
                    }
                }
                .clipped()
                .overlay(alignment: .bottomTrailing) { badge }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Selected photo")
        .accessibilityHint("Removes it from the selection")
        .onAppear(perform: load)
        .onChange(of: assetId) { load() }
        .onDisappear(perform: cancel)
    }

    private var badge: some View {
        Image(systemName: "checkmark.circle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, AppAccent.color)
            .font(.system(size: 22))
            .padding(6)
    }

    private func load() {
        cancel()
        image = nil
        guard let asset = PhotoLibraryService.fetchAssets(ids: [assetId]).first else { return }
        let pixels = 120 * min(ActiveDisplay.scale, 2)
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
