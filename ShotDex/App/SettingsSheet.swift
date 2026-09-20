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
        // Monochrome like every other chrome glyph — the accent is reserved for
        // active/selected state (DESIGN §10.6).
        .tint(.primary)
        .accessibilityLabel("Settings")
    }
}

extension View {
    /// Presents Settings as a full screen.
    ///
    /// It used to be a bottom sheet at medium/large detents, matching the
    /// photo-detail metadata panel. It outgrew that: the screen now carries
    /// ten sections and four widget editors, and a widget editor is a preview
    /// that has to be dragged and pinched — a sheet that can be dragged away
    /// by the same finger is the wrong container for it. It keeps its own
    /// `NavigationStack` so Camera Database and the widget editors push.
    func settingsSheet(isPresented: Binding<Bool>, libraryModel: LibraryModel?) -> some View {
        fullScreenCover(isPresented: isPresented) {
            NavigationStack {
                SettingsScreen(libraryModel: libraryModel)
            }
        }
    }
}
