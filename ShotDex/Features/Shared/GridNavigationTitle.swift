import SwiftUI

/// A grid screen's name with the date of what is on screen under it, for the
/// navigation bar's principal slot. The grid draws no date headers, so this
/// is where "when am I" lives.
///
/// Leading-aligned and stretched across the slot: centred, the block's width
/// followed the date's ("May 3" vs "September 23"), so both lines slid left
/// and right on every scroll.
struct GridNavigationTitle: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.18), value: subtitle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
