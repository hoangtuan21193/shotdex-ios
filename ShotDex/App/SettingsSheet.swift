import SwiftUI

/// Top-leading toolbar button shared by the tab root screens; opens Settings.
struct SettingsButton: View {
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Button {
            navigation.isSettingsSheetPresented = true
        } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("Settings")
    }
}

extension View {
    /// Presents Settings as a bottom sheet (slides up, medium/large detents),
    /// mirroring the photo-detail metadata panel. Keeps its own NavigationStack
    /// so Camera Database (Unknown Cameras) can push.
    func settingsSheet(isPresented: Binding<Bool>, libraryModel: LibraryModel?) -> some View {
        sheet(isPresented: isPresented) {
            NavigationStack {
                SettingsScreen(libraryModel: libraryModel)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}
