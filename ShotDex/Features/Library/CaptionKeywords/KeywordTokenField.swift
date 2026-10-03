import SwiftUI

/// One Photos keyword as a 32pt capsule with a remove button
/// (FS-02.07 §4). VoiceOver reads *Sunset, keyword* with the action Remove.
struct KeywordCapsule: View {
    let keyword: String
    var isDisabled = false
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Text(keyword)
                .font(.subheadline)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color(.tertiarySystemFill)))
                    .frame(width: 28, height: AppTheme.Size.pillHeightLight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .accessibilityHidden(true)
        }
        .padding(.leading, AppTheme.Spacing.md)
        .frame(height: AppTheme.Size.pillHeightLight)
        .background(Capsule().fill(Color(.secondarySystemFill)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(keyword), keyword", tableName: KeywordCopy.table, comment: "VoiceOver: a Photos keyword capsule"))
        .accessibilityAction(named: Text("Remove", tableName: KeywordCopy.table, comment: "VoiceOver action: remove this keyword from the photo")) {
            onRemove()
        }
    }
}

/// The Add Keyword control shared by Info and the bulk sheet (FS-02.07 §4,
/// §5): a dashed capsule that turns into a field; typing lists up to 8
/// library keywords with their photo counts underneath, Return adds what was
/// typed (commas separate keywords), a tapped suggestion adds itself.
struct KeywordTokenField: View {
    @Binding var text: String
    let onSubmit: () -> Void
    @FocusState.Binding var isFocused: Bool
    @Environment(\.appAccent) private var accent
    /// The capsule was tapped: the field exists first, focus follows once
    /// it is on screen (focus cannot land on a field not yet drawn).
    @State private var isEditing = false

    var body: some View {
        if isEditing || isFocused || !text.isEmpty {
            TextField(
                text: $text,
                prompt: Text("Keyword", tableName: KeywordCopy.table, comment: "Placeholder of the Add Keyword field")
            ) {
                Text("Add Keyword", tableName: KeywordCopy.table, comment: "Accessibility label of the keyword field")
            }
            .font(.subheadline)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($isFocused)
            .onSubmit(onSubmit)
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(minWidth: 120)
            .frame(height: AppTheme.Size.pillHeightLight)
            .overlay(Capsule().stroke(accent, lineWidth: 1.5))
            .accessibilityIdentifier("keyword.field")
            .onAppear { if isEditing { isFocused = true } }
            .onChange(of: isFocused) { _, focused in
                if !focused, text.isEmpty { isEditing = false }
            }
        } else {
            Button {
                isEditing = true
            } label: {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                    Text("Add Keyword", tableName: KeywordCopy.table, comment: "Capsule that opens the keyword field")
                }
                .font(.subheadline)
                .foregroundStyle(accent)
                .padding(.horizontal, AppTheme.Spacing.md)
                .frame(height: AppTheme.Size.pillHeightLight)
                .overlay(Capsule().strokeBorder(accent.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

/// The suggestions under a keyword field: keyword and photo count, most
/// photos first. Rows, not a popover, so on the Duo's 669pt inner screen
/// they scroll with the sheet instead of hiding under the keyboard.
struct KeywordSuggestionList: View {
    let suggestions: [KeywordCount]
    let onPick: (KeywordCount) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(suggestions, id: \.keyword) { suggestion in
                if suggestion != suggestions.first { Divider() }
                Button {
                    onPick(suggestion)
                } label: {
                    HStack {
                        Text(suggestion.keyword)
                            .foregroundStyle(.primary)
                        Spacer(minLength: AppTheme.Spacing.sm)
                        Text(suggestion.count, format: .number)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: AppTheme.Size.minTouch)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(suggestion.keyword), \(suggestion.count) photos", tableName: KeywordCopy.table, comment: "VoiceOver: a keyword suggestion and how many photos carry it"))
            }
        }
    }
}
