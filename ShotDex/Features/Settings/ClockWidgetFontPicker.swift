import ShotDexKit
import SwiftUI

/// The Clock widget's typeface, picked from everything installed on the
/// device.
///
/// Wraps the same `FontPickerRepresentable` the editor's font sheet uses —
/// one font list in the app, not two — in Settings' own light chrome rather
/// than the editor's dark panel.
struct ClockWidgetFontPicker: View {
    let onPick: (OverlayFontChoice) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            FontPickerRepresentable { choice in
                onPick(choice)
                dismiss()
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Typeface")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
