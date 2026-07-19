import SwiftUI

/// Round material-blurred icon button used in the floating chrome
/// (e.g. the search button next to the tab pill).
struct GlassIconButton: View {
    var systemImage: String
    var accessibilityLabel: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color(.label))
                .frame(width: 52, height: 52)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview {
    ZStack {
        LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        GlassIconButton(systemImage: "magnifyingglass", accessibilityLabel: "Search", action: {})
    }
}
