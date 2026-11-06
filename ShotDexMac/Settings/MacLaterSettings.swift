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

/// Settings › Editing (board `MAC_SettingsEditing`): what opens and how
/// exports come out. The Mac has no editor or Export yet.
struct MacEditingSettings: View {
    var body: some View {
        MacLaterPane(note: String(localized: "Editing and Export come to the Mac in a later version.",
                                  comment: "Mac Settings › Editing: the whole pane is not on the Mac yet")) {
            Section {
                Picker(selection: .constant(-1)) {
                    Text("Edit the RAW", comment: "Mac Settings › Editing: RAW + JPEG pair choice").tag(0)
                } label: {
                    Text("RAW + JPEG Pairs", comment: "Mac Settings › Editing row")
                    Text("Shown as one photo in the library. Choose which file the editor opens.", comment: "Mac Settings › Editing row explanation")
                }
            } header: {
                Text("RAW", comment: "Mac Settings › Editing group")
            } footer: {
                Text("Exports keep the original’s color profile unless you pick sRGB, Display P3 or Adobe RGB in the Export sheet.",
                     comment: "Mac Settings › Editing footer")
            }
            Section {
                Picker(String(localized: "Size", comment: "Mac Settings › Export Defaults row"), selection: .constant(-1)) {
                    Text("2048 px", comment: "Mac Settings › Export Defaults: long edge").tag(0)
                }
                Picker(String(localized: "Format and Quality", comment: "Mac Settings › Export Defaults row"), selection: .constant(-1)) {
                    Text("Same as Original · 80%", comment: "Mac Settings › Export Defaults: format").tag(0)
                }
                LabeledContent(String(localized: "File Names", comment: "Mac Settings › Export Defaults row")) { EmptyView() }
                Picker(String(localized: "If a File Exists", comment: "Mac Settings › Export Defaults row"), selection: .constant(-1)) {
                    Text("Keep Both", comment: "Mac Settings › Export Defaults: name clash").tag(0)
                    Text("Replace", comment: "Mac Settings › Export Defaults: name clash").tag(1)
                    Text("Skip", comment: "Mac Settings › Export Defaults: name clash").tag(2)
                }
                .pickerStyle(.segmented)
                Picker(selection: .constant(-1)) {
                    Text("All Metadata", comment: "Mac Settings › Export Defaults: metadata level").tag(0)
                } label: {
                    Text("Metadata When Sharing", comment: "Mac Settings › Export Defaults row")
                    Text("Each share and export can change it", comment: "Mac Settings › Export Defaults row explanation")
                }
                Picker(String(localized: "Watermark When Sharing", comment: "Mac Settings › Export Defaults row"), selection: .constant(-1)) {
                    Text("Off", comment: "Mac Settings › Export Defaults: no watermark").tag(0)
                }
            } header: {
                Text("Export Defaults", comment: "Mac Settings › Editing group")
            } footer: {
                Text("Used the first time you export. The Export sheet then remembers your last choices, except Metadata.",
                     comment: "Mac Settings › Editing footer")
            }
            Section {
                Text("No presets", comment: "Mac Settings › Editing: the presets table is empty")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Presets", comment: "Mac Settings › Editing group")
            }
        }
    }
}
