import Photos
import SwiftUI

/// Full raw-metadata sheet for one photo or video: every property read live
/// from the asset (ImageIO for photos, AVFoundation for videos) plus PHAsset
/// and resource facts — grouped by source block. Not the curated index; this
/// is the exhaustive dump behind the "i" button.
struct MetadataPanel: View {
    let asset: PHAsset?

    @State private var sections: [MetadataDumpSection] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Reading metadata…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if sections.isEmpty {
                    ContentUnavailableView(
                        "No Metadata",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Couldn't read metadata for this item.")
                    )
                } else {
                    List {
                        ForEach(sections) { section in
                            Section(section.title) {
                                ForEach(section.rows) { row in
                                    LabeledContent(row.key) {
                                        Text(row.value)
                                            .multilineTextAlignment(.trailing)
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Metadata")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task(id: asset?.localIdentifier) {
            isLoading = true
            sections = []
            guard let asset else {
                isLoading = false
                return
            }
            let loaded = await AssetMetadataDump.load(for: asset)
            guard !Task.isCancelled else { return }
            sections = loaded
            isLoading = false
        }
    }
}
