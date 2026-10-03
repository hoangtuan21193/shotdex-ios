import SwiftUI

/// Info's first section on iOS 27 (FS-02.07 §4): Photos' caption — a field
/// that grows from one line to four — and the photo's keywords as capsules
/// with an Add Keyword capsule at the end. Every change is written to Photos
/// at once; there is no Save.
struct CaptionKeywordSection: View {
    @State private var model: InfoCaptionKeywordModel
    @FocusState private var isCaptionFocused: Bool
    @FocusState private var isKeywordFocused: Bool

    init(assetId: String, service: CaptionKeywordService) {
        _model = State(initialValue: InfoCaptionKeywordModel(assetId: assetId, service: service))
    }

    var body: some View {
        Section {
            captionField
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                KeywordFlowLayout {
                    ForEach(model.keywords, id: \.self) { keyword in
                        KeywordCapsule(keyword: keyword, isDisabled: model.isWriting) {
                            Task { await model.remove(keyword) }
                        }
                    }
                    KeywordTokenField(
                        text: $model.keywordText,
                        onSubmit: {
                            Task { await model.commitKeywords() }
                            isKeywordFocused = true
                        },
                        isFocused: $isKeywordFocused
                    )
                }
                let suggestions = model.suggestions
                if isKeywordFocused, !suggestions.isEmpty {
                    KeywordSuggestionList(suggestions: suggestions) { suggestion in
                        Task { await model.add(suggestion) }
                    }
                }
            }
            .padding(.vertical, AppTheme.Spacing.xs)
        } footer: {
            Text(
                "Saved to Photos as you type. Keywords stay with the photo on every device.",
                tableName: KeywordCopy.table,
                comment: "Footer under the caption and keywords section of Photo Info"
            )
        }
        .task { await model.load() }
        .onChange(of: isCaptionFocused) { _, focused in
            if !focused { Task { await model.commitCaption() } }
        }
        .alert(
            Text("Couldn't Save to Photos", tableName: KeywordCopy.table, comment: "Alert title when a caption or keyword write failed"),
            isPresented: Binding(get: { model.failedChange != nil }, set: { if !$0 { model.dismissFailure() } })
        ) {
            Button {
                Task { await model.retry() }
            } label: {
                Text("Try Again", tableName: KeywordCopy.table, comment: "Retry a caption or keyword write")
            }
            Button(role: .cancel) {
                model.dismissFailure()
            } label: {
                Text("Cancel", tableName: KeywordCopy.table, comment: "Dismiss the failed-write alert")
            }
        } message: {
            Text("The caption and keywords are unchanged.", tableName: KeywordCopy.table, comment: "Alert message when a caption or keyword write failed")
        }
    }

    private var captionField: some View {
        TextField(
            text: $model.captionText,
            prompt: Text("Add a Caption", tableName: KeywordCopy.table, comment: "Placeholder of the caption field in Photo Info"),
            axis: .vertical
        ) {
            Text("Caption", tableName: KeywordCopy.table, comment: "Accessibility label of the caption field")
        }
        .lineLimit(1...4)
        .accessibilityLabel(Text("Caption", tableName: KeywordCopy.table, comment: "VoiceOver label of the caption field"))
        .submitLabel(.done)
        .focused($isCaptionFocused)
        .disabled(!model.isLoaded)
        .accessibilityIdentifier("caption.field")
        // A vertical field takes Return as a new line; Done on the keyboard
        // is how a caption is finished (FS-02.07 §4).
        .onChange(of: model.captionText) { _, text in
            let limited = InfoCaptionKeywordModel.limitedCaption(text.replacingOccurrences(of: "\n", with: ""))
            if limited != text { model.captionText = limited }
            if text.contains("\n") { isCaptionFocused = false }
        }
    }
}
