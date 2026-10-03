import SwiftUI

/// A *Caption & Keywords…* asked for from a selection's ⋯ (FS-02.07 §5);
/// the root presents it, so no grid hosts its own copy.
struct CaptionKeywordsRequest: Identifiable, Equatable {
    let id = UUID()
    let assetIds: [String]
}

/// `Caption & Keywords…` in a selection's ⋯, right after Add to Collection
/// (FS-02.07 §5). Offered by Library, album and smart album; never below
/// iOS 27 — hidden, not dimmed, because it could never be turned on there.
struct CaptionKeywordsSelectionRow: View {
    let ids: [String]
    @Environment(AppNavigation.self) private var navigation

    static func isOffered(screenOffers: Bool, extendedMetadata: Bool = ExtendedMetadataSupport.isAvailable) -> Bool {
        screenOffers && extendedMetadata
    }

    var body: some View {
        Button {
            navigation.captionKeywordsRequest = CaptionKeywordsRequest(assetIds: ids)
        } label: {
            PhotoCommand.captionKeywords.label
        }
        .disabled(ids.isEmpty)
    }
}

extension View {
    /// Hosts the bulk sheet for a request, and its banner once applied.
    func captionKeywordsPresenter(_ request: Binding<CaptionKeywordsRequest?>) -> some View {
        sheet(item: request) { CaptionKeywordSheetHost(request: $0) }
    }
}

private struct CaptionKeywordSheetHost: View {
    let request: CaptionKeywordsRequest
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        if let service = dependencies.captionKeywords {
            CaptionKeywordSheet(
                model: CaptionKeywordSheetModel(ids: request.assetIds, service: service),
                banner: dependencies.banner
            )
        }
    }
}

/// The bulk sheet (FS-02.07 §5): tier A, `[.medium, .large]`, Cancel and
/// Apply in the bar, three sections — Add Keywords, On These Photos,
/// Caption. Apply is one write; the sheet closes, a banner says what changed
/// and offers Undo for 4 s, and the selection stays as it was.
struct CaptionKeywordSheet: View {
    @State var model: CaptionKeywordSheetModel
    let banner: AppBannerModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isKeywordFocused: Bool
    @FocusState private var isCaptionFocused: Bool
    @State private var alert: AlertKind?

    private enum AlertKind: Identifiable {
        case allRefused, failed
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            List {
                addSection
                if !model.rows.isEmpty { onThesePhotosSection }
                captionSection
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("Caption & Keywords", tableName: KeywordCopy.table, comment: "Title of the bulk caption and keyword sheet")
                            .font(.headline)
                        Text(KeywordCopy.photoCount(model.photoCount))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel", tableName: KeywordCopy.table, comment: "Close the bulk sheet without writing")
                    }
                    .disabled(model.isApplying)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await apply() }
                    } label: {
                        Text("Apply", tableName: KeywordCopy.table, comment: "Write the bulk caption and keyword changes")
                    }
                    .disabled(!model.canApply && model.keywordText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(model.isApplying)
        .overlay {
            if model.showsProgress { UpdatingPhotosModal(count: model.photoCount) }
        }
        .task { await model.load() }
        .alert(item: $alert) { kind in
            switch kind {
            case .allRefused:
                Alert(
                    title: Text("Caption & Keywords", tableName: KeywordCopy.table, comment: "Alert title when Photos refused every selected photo"),
                    message: Text("Photos doesn't allow changes to these photos — they may be in a shared library or a shared album.", tableName: KeywordCopy.table, comment: "Alert message when every selected photo refuses property edits")
                )
            case .failed:
                Alert(
                    title: Text("Couldn't Update Photos", tableName: KeywordCopy.table, comment: "Alert title when the bulk write failed"),
                    message: Text("Nothing was changed.", tableName: KeywordCopy.table, comment: "Alert message when the bulk write failed"),
                    primaryButton: .default(Text("Try Again", tableName: KeywordCopy.table, comment: "Retry the bulk write")) {
                        Task { await apply() }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    // MARK: Sections

    private var addSection: some View {
        Section {
            ForEach(model.additions, id: \.self) { keyword in
                HStack {
                    Text(keyword)
                    Spacer()
                    Button {
                        model.removeAddition(keyword)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: AppTheme.Size.minTouch, height: AppTheme.Size.minTouch)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Remove \(keyword)", tableName: KeywordCopy.table, comment: "VoiceOver: drop a keyword waiting to be added"))
                }
            }
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                KeywordTokenField(
                    text: $model.keywordText,
                    onSubmit: {
                        model.commitKeywordText()
                        isKeywordFocused = true
                    },
                    isFocused: $isKeywordFocused
                )
                let suggestions = model.suggestions
                if isKeywordFocused, !suggestions.isEmpty {
                    KeywordSuggestionList(suggestions: suggestions) { model.add($0) }
                }
            }
            .padding(.vertical, AppTheme.Spacing.xs)
        } header: {
            Text("Add Keywords", tableName: KeywordCopy.table, comment: "Bulk sheet section: keywords to add")
        }
    }

    private var onThesePhotosSection: some View {
        Section {
            ForEach(model.rows) { row in
                let removing = model.isRemoving(row)
                HStack {
                    Text(row.keyword)
                        .strikethrough(removing)
                        .foregroundStyle(removing ? Color.red : Color.primary)
                    Spacer()
                    Text(KeywordCopy.share(row.count, of: model.photoCount))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button {
                        model.toggleRemoval(row)
                    } label: {
                        Image(systemName: removing ? "arrow.uturn.backward.circle" : "minus.circle")
                            .foregroundStyle(removing ? Color.secondary : Color.red)
                            .frame(width: AppTheme.Size.minTouch, height: AppTheme.Size.minTouch)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(rowAccessibility(row, removing: removing))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { model.toggleRemoval(row) }
            }
        } header: {
            Text("On These Photos", tableName: KeywordCopy.table, comment: "Bulk sheet section: keywords the selection already carries")
        }
    }

    private func rowAccessibility(_ row: CaptionKeywordBatchPlan.Row, removing: Bool) -> Text {
        removing
            ? Text("\(row.keyword), on \(row.count) of \(model.photoCount) photos, will be removed", tableName: KeywordCopy.table, comment: "VoiceOver: keyword row set to be removed")
            : Text("\(row.keyword), on \(row.count) of \(model.photoCount) photos, unchanged", tableName: KeywordCopy.table, comment: "VoiceOver: keyword row left as it is")
    }

    private var captionSection: some View {
        Section {
            TextField(
                text: $model.captionText,
                prompt: model.hasMultipleCaptions && !model.captionIsEdited
                    ? Text("Multiple Captions", tableName: KeywordCopy.table, comment: "Placeholder when the selected photos have different captions")
                    : Text("Add a Caption", tableName: KeywordCopy.table, comment: "Placeholder of the caption field"),
                axis: .vertical
            ) {
                Text("Caption", tableName: KeywordCopy.table, comment: "Accessibility label of the caption field")
            }
            .lineLimit(1...4)
            .focused($isCaptionFocused)
            .accessibilityLabel(Text("Caption", tableName: KeywordCopy.table, comment: "VoiceOver label of the caption field"))
            .onChange(of: model.captionText) { _, text in
                let limited = InfoCaptionKeywordModel.limitedCaption(text)
                if limited != text { model.captionText = limited }
            }
            Button(role: .destructive) {
                model.clearCaptions()
            } label: {
                Text("Clear Captions", tableName: KeywordCopy.table, comment: "Bulk sheet: clear the caption of every selected photo")
            }
        } header: {
            Text("Caption", tableName: KeywordCopy.table, comment: "Bulk sheet section: caption")
        }
    }

    // MARK: Apply

    private func apply() async {
        isKeywordFocused = false
        isCaptionFocused = false
        let outcome = await model.apply()
        switch outcome {
        case .nothing:
            dismiss()
        case .allRefused:
            alert = .allRefused
        case .failed:
            alert = .failed
        case .written(let text, _):
            let model = self.model
            let banner = self.banner
            dismiss()
            banner.show(text, actionTitle: KeywordCopy.undo) {
                Task {
                    do {
                        try await model.undo()
                    } catch {
                        banner.show(KeywordCopy.undoFailed)
                    }
                }
            }
        }
    }
}

/// *Updating 5,000 photos…* — a card in the middle of the sheet while a
/// write longer than a second runs, no Cancel: the write is one block
/// (FS-02.07 §5). The shape of `OriginalDownloadModal`'s card.
private struct UpdatingPhotosModal: View {
    let count: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .contentShape(Rectangle())
            VStack(spacing: AppTheme.Spacing.md) {
                ProgressView()
                Text(KeywordCopy.updating(count))
                    .font(.headline.monospacedDigit())
            }
            .padding(AppTheme.Spacing.xl)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            )
            .padding(AppTheme.Spacing.xl)
            .accessibilityElement(children: .combine)
        }
    }
}
