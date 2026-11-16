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

/// A whole pane the Mac has no feature for yet (AI, Editing): drawn as it
/// will be, dimmed and inert, under one line that says why.
struct MacLaterPane<Content: View>: View {
    let note: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(note)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 30)
                .padding(.top, 14)
            // Controls dim as disabled, labels and footers stay readable at
            // secondary contrast; nothing in it is a saved value, so VoiceOver
            // reads only the note above.
            Form { content }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .foregroundStyle(.secondary)
                .disabled(true)
                .accessibilityHidden(true)
        }
    }
}

/// Settings › AI (board `MAC_SettingsAI`): AI Search on this Mac or a
/// computer at home. Nothing on the Mac searches with AI yet.
struct MacAISettings: View {
    var body: some View {
        MacLaterPane(note: String(localized: "AI Search comes to the Mac in a later version.",
                                  comment: "Mac Settings › AI: the whole pane is not on the Mac yet")) {
            Section {
                Picker(String(localized: "AI Search", comment: "Mac Settings › AI row"), selection: .constant(-1)) {
                    Text("Apple Intelligence", comment: "Mac Settings › AI: the built-in model").tag(0)
                }
            } header: {
                Text("Use For", comment: "Mac Settings › AI group")
            } footer: {
                Text("AI Search uses only this Mac or a computer on your home network.", comment: "Mac Settings › AI footer")
            }
            Section {
                LabeledContent(String(localized: "Apple Intelligence", comment: "Mac Settings › AI: the built-in model")) { EmptyView() }
            } header: {
                Text("On This Mac", comment: "Mac Settings › AI group")
            }
            Section {
                Text("No providers", comment: "Mac Settings › AI: the providers table is empty")
                    .foregroundStyle(.secondary)
                HStack {
                    Button(String(localized: "Add Provider", comment: "Mac Settings › AI"), systemImage: "plus") {}
                        .labelStyle(.iconOnly)
                    Button(String(localized: "Delete Provider", comment: "Mac Settings › AI"), systemImage: "minus") {}
                        .labelStyle(.iconOnly)
                    Spacer()
                    Button(String(localized: "Test", comment: "Mac Settings › AI: test a provider")) {}
                    Button(String(localized: "Edit…", comment: "Mac Settings › AI: edit a provider")) {}
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Providers", comment: "Mac Settings › AI group")
            } footer: {
                Text("Ollama or LM Studio on a computer at home. Searches go straight from this Mac to it; ShotDex has no server in between.",
                     comment: "Mac Settings › AI footer")
            }
        }
    }
}
