import SwiftUI

/// ChatGPT-style left slide-in drawer hosting the Settings content.
/// Overlays the whole scaffold (including tab chrome) with a dimmed scrim;
/// dismissed by tapping the scrim or dragging the panel left.
struct SettingsDrawer: View {
    @Binding var isOpen: Bool
    let libraryController: LibraryController?

    /// Panel drag offset while dragging closed; always in -panelWidth...0.
    @State private var dragTranslation: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let panelWidth = min(proxy.size.width * 0.8, 360)
            let progress = isOpen ? 1 + dragTranslation / panelWidth : 0

            ZStack(alignment: .leading) {
                Color.black.opacity(0.35 * progress)
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                    .accessibilityLabel("Close settings")
                    .accessibilityAddTraits(.isButton)

                NavigationStack {
                    SettingsScreen(libraryController: libraryController)
                }
                .frame(width: panelWidth)
                .background(Color(.systemBackground))
                .shadow(color: .black.opacity(0.2), radius: 12, x: 4, y: 0)
                .offset(x: isOpen ? dragTranslation : -panelWidth - 20)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            dragTranslation = min(0, max(-panelWidth, value.translation.width))
                        }
                        .onEnded { value in
                            let predicted = value.predictedEndTranslation.width
                            if dragTranslation < -panelWidth * 0.3 || predicted < -panelWidth * 0.5 {
                                close()
                            } else {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                    dragTranslation = 0
                                }
                            }
                        }
                )
                .accessibilityAction(.escape) { close() }
            }
            .ignoresSafeArea()
            .allowsHitTesting(isOpen)
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: isOpen)
            .onChange(of: isOpen) { _, _ in
                dragTranslation = 0
            }
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            isOpen = false
        }
        dragTranslation = 0
    }
}

/// Top-leading toolbar button shared by the tab root screens; opens the drawer.
struct SettingsDrawerButton: View {
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Button {
            navigation.isSettingsDrawerOpen = true
        } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("Settings")
    }
}

extension View {
    /// Attaches the settings drawer overlay above all content, incl. tab bars.
    func settingsDrawer(isOpen: Binding<Bool>, libraryController: LibraryController?) -> some View {
        overlay {
            SettingsDrawer(isOpen: isOpen, libraryController: libraryController)
        }
    }
}
