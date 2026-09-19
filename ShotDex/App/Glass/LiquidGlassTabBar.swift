import SwiftUI

/// The app's main tabs.
enum AppTab: String, CaseIterable, Identifiable {
    case library
    case albums
    case statistics
    case search

    var id: String { rawValue }

    /// Tabs shown in the legacy (pre-iOS 26) pill bar; search has its own button.
    static let barTabs: [AppTab] = [.library, .albums, .statistics]

    var title: String {
        switch self {
        case .library: "Library"
        case .albums: "Collections"
        case .statistics: "Statistics"
        case .search: "Search"
        }
    }

    var systemImage: String {
        switch self {
        case .library: "photo.on.rectangle"
        case .albums: "square.stack"
        case .statistics: "chart.bar.xaxis"
        case .search: "magnifyingglass"
        }
    }

    var selectedSystemImage: String {
        switch self {
        case .library: "photo.on.rectangle.fill" // no fill variant renders same
        case .albums: "square.stack.fill"
        case .statistics: "chart.bar.xaxis"
        case .search: "magnifyingglass"
        }
    }
}

/// Floating "Liquid Glass" pill tab bar inspired by the iOS 26 Music app:
/// a material-blurred pill holding the four tabs, with a separate round
/// search button beside it.
struct LiquidGlassTabBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The bar draws its own chrome, so the two sizes it hardcodes have to
    /// scale by hand. Capped: past these the pill is taller than the gap it
    /// floats in.
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 17
    @ScaledMetric(relativeTo: .caption2) private var labelSize: CGFloat = 10

    @Environment(\.appAccent) private var accent
    @Binding var selection: AppTab
    /// Called when the already-selected tab is tapped again.
    var onReselect: (AppTab) -> Void = { _ in }
    var onSearchTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            tabPill
            GlassIconButton(
                systemImage: "magnifyingglass",
                accessibilityLabel: "Search",
                action: onSearchTap
            )
        }
        .padding(.horizontal, 20)
    }

    private var tabPill: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.barTabs) { tab in
                tabButton(for: tab)
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tab bar")
    }

    private func tabButton(for tab: AppTab) -> some View {
        let isSelected = selection == tab
        return Button {
            if selection == tab {
                onReselect(tab)
            } else {
                selection = tab
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: isSelected ? tab.selectedSystemImage : tab.systemImage)
                    .font(.system(size: min(iconSize, 24), weight: .medium))
                // Dropped at accessibility sizes, the way the system tab bar
                // drops its own: three labels at that size do not fit across
                // a phone, and squeezing them is worse than the icon alone —
                // which still carries the tab's name to VoiceOver through the
                // button's accessibility label below.
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(tab.title)
                        .font(.system(size: min(labelSize, 15), weight: .medium))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isSelected ? accent : Color(.secondaryLabel))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color(.systemFill))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

#Preview {
    ZStack(alignment: .bottom) {
        LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        LiquidGlassTabBar(selection: .constant(.library), onSearchTap: {})
            .padding(.bottom, 20)
    }
}
