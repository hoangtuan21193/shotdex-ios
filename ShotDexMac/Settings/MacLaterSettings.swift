import SwiftUI

/// A row the board draws whose feature the Mac does not have yet
/// (FS-18.04 §3): it keeps its place, its label and control are dimmed and
/// switched off, and the reason stays at full contrast.
struct MacLaterSettingsRow<Control: View>: View {
    let title: String
    @ViewBuilder var control: Control

    var body: some View {
        LabeledContent {
            control.disabled(true)
        } label: {
            Text(title).foregroundStyle(.secondary)
            Text(MacLaterSettings.reason).font(.caption).foregroundStyle(.secondary)
        }
    }
}

extension MacLaterSettingsRow where Control == AnyView {
    /// The common case: a switch, drawn off.
    init(switchTitle title: String) {
        self.title = title
        control = AnyView(Toggle(title, isOn: .constant(false)).toggleStyle(.switch).labelsHidden())
    }
}

enum MacLaterSettings {
    static let reason = String(localized: "Available in a later version",
                               comment: "Mac Settings: a row whose feature the Mac does not have yet")
}
