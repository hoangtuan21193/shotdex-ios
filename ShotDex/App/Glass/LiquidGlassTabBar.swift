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
        case .albums: "Albums"
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
                    .font(.system(size: 17, weight: .medium))
                Text(tab.title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color(.secondaryLabel))
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
