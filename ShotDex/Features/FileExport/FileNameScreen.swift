import SwiftUI

/// The File Name screen (FS-03.07b §5), pushed from the Name row: the three
/// built-in templates with a checkmark, then Custom — a 44pt field, two rows
/// of token chips, and the first photo's name, which changes as you type.
struct FileNameScreen: View {
    @Bindable var model: FileExportModel
    @FocusState private var isCustomFocused: Bool

    /// The Text chip's word, to select in the custom field (iOS 18 and
    /// later) so it can be typed over (FS-20 AC-25).
    @State private var wordToSelect: Range<String.Index>?

    var body: some View {
        Form {
            Section {
                ForEach(FileNameTemplate.builtIns, id: \.self) { template in
                    Button {
                        model.chooseTemplate(template)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ExportCopy.templateTitle(template)).foregroundStyle(.primary)
                                Text(verbatim: template.pattern)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.template == template {
                                Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.template == template ? .isSelected : [])
                }
            }

            Section {
                HStack {
                    CustomTemplateField(text: $model.customTemplate, wordToSelect: $wordToSelect)
                        .focused($isCustomFocused)
                    if model.usesCustomTemplate {
                        Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityAddTraits(model.usesCustomTemplate ? .isSelected : [])

                FileNameTokenGrid { chip in
                    if let typed = model.insert(chip) {
                        isCustomFocused = true
                        wordToSelect = typed
                    }
                }
                .padding(.vertical, AppTheme.Spacing.xs)

                if let example = model.exampleName {
                    HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.md) {
                        Text(ExportCopy.exampleLabel).foregroundStyle(.secondary)
                        Text(verbatim: example)
                            .font(.subheadline.monospaced())
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text(ExportCopy.custom)
            } footer: {
                Text(ExportCopy.missingTokenFooter(model.missingTokenExample))
            }
        }
        .navigationTitle(ExportCopy.fileNameTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

/// The custom template field. From iOS 18 it can select a range, which is how
/// the Text chip's word arrives ready to type over; before that the word is
/// appended unselected.
private struct CustomTemplateField: View {
    @Binding var text: String
    @Binding var wordToSelect: Range<String.Index>?

    var body: some View {
        if #available(iOS 18.0, *) {
            SelectableTemplateField(text: $text, wordToSelect: $wordToSelect)
        } else {
            TextField(ExportCopy.custom, text: $text)
                .templateFieldStyle()
        }
    }
}

@available(iOS 18.0, *)
private struct SelectableTemplateField: View {
    @Binding var text: String
    @Binding var wordToSelect: Range<String.Index>?
    @State private var selection: TextSelection?

    var body: some View {
        TextField(ExportCopy.custom, text: $text, selection: $selection)
            .templateFieldStyle()
            .onChange(of: wordToSelect) { _, range in
                guard let range else { return }
                wordToSelect = nil
                // After the field has taken focus: a selection set in the
                // same pass is replaced by the caret focus puts at the end.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    guard range.upperBound <= text.endIndex else { return }
                    selection = TextSelection(range: range)
                }
            }
    }
}

private extension View {
    func templateFieldStyle() -> some View {
        font(.body.monospaced())
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
    }
}
