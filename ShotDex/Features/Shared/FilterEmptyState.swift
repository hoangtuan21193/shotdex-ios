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

/// "12 of 40 Items" — how much of an album a filter left. One wording for the
/// album grid's footer and the smart album's conditions bar (FS-06.09 §3);
/// "Items" because an album holds videos too.
enum FilteredCountLabel {
    static func text(shown: Int, of total: Int) -> String {
        "\(shown.formatted()) of \(total.formatted()) \(total == 1 ? "Item" : "Items")"
    }
}
