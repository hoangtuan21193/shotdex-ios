import SwiftUI

/// What a grid shows when its filters leave nothing — one wording for Library
/// and the album screens (FS-06.09 §3), with the way back on the same screen.
struct FilterEmptyState: View {
    var onClearFilters: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No photos match these filters.", systemImage: "camera.filters")
        } actions: {
            Button("Clear Filters", action: onClearFilters)
                .buttonStyle(.borderedProminent)
        }
    }
}
