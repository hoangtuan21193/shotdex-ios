import SwiftUI

/// A `List` section that edits a list of free-typed string tokens with
/// autocomplete. Existing tokens show as removable rows; a text field adds
/// new ones (Return or the Add button), and up to 8 suggestions filtered
/// from `suggestions` (indexed values) appear as tappable rows while typing.
/// Any text is allowed — suggestions only assist; they don't constrain.
struct AutocompleteTokenField: View {
    let title: String
    @Binding var tokens: [String]
    let suggestions: [String]
    let prompt: String

    @State private var draft: String = ""

    init(
        title: String,
        tokens: Binding<[String]>,
        suggestions: [String],
        prompt: String = "Type to add…"
    ) {
        self.title = title
        _tokens = tokens
        self.suggestions = suggestions
        self.prompt = prompt
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Indexed values matching the current draft, excluding already-added
    /// tokens (mirrors `LibraryModel.suggestions(for:)`).
    private var filteredSuggestions: [String] {
        guard !trimmedDraft.isEmpty else { return [] }
        let tokenSet = Set(tokens)
        var result: [String] = []
        result.reserveCapacity(8)
        for value in suggestions
        where value.localizedCaseInsensitiveContains(trimmedDraft) && !tokenSet.contains(value) {
            result.append(value)
            if result.count == 8 { break }
        }
        return result
    }

    var body: some View {
        Section(title) {
            ForEach(tokens, id: \.self) { token in
                HStack {
                    Text(token)
                        .foregroundStyle(Color(.label))
                    Spacer()
                    Button {
                        tokens.removeAll { $0 == token }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                TextField(prompt, text: $draft)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { addToken(draft) }
                if !trimmedDraft.isEmpty {
                    Button("Add") { addToken(draft) }
                        .buttonStyle(.borderless)
                }
            }

            ForEach(filteredSuggestions, id: \.self) { suggestion in
                Button {
                    addToken(suggestion)
                } label: {
                    HStack {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(Color.accentColor)
                        Text(suggestion)
                            .foregroundStyle(Color(.label))
                        Spacer()
                    }
                }
            }
        }
    }

    private func addToken(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { draft = "" }
        guard !trimmed.isEmpty, !tokens.contains(trimmed) else { return }
        tokens.append(trimmed)
    }
}
