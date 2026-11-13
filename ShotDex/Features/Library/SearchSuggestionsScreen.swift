import Photos
import SwiftUI

/// The search screen, the way Photos does it (FS-01.03c): with an empty field,
/// the recent searches and what the library holds; while typing, suggestion
/// rows with a picture, a kind and a photo count, and the matching photos
/// right under them. Picking a suggestion makes it a token in the field;
/// typing more narrows inside it.
///
/// One screen for the iOS 26 search tab and the pre-26 sheet. The state lives
/// in `SearchSession`, which both surfaces bind the field to.
struct SearchSuggestionsScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(SettingsKeys.gridColumns) private var storedColumns = 3

    let session: SearchSession
    let model: LibraryModel
    /// Called once the search has been taken to Library (switch tab, dismiss).
    var onApplied: () -> Void
    /// Opens advanced search from the title row. Nil where the surface has a free
    /// navigation bar to put it in instead (the pre-26 sheet).
    var onAdvanced: (() -> Void)?

    /// Built on first appearance, because the dependencies come from the
    /// environment and are not available at init.
    @State private var recentsModel: SearchRecentsModel?
    @State private var results: SearchResultsModel?
    @State private var viewerTarget: PhotoViewerTarget?
    /// Zoom from and back to the tapped tile (FS-02 §8 D5).
    @State private var viewerLink = PhotoViewerLink()
    /// The Duo's inner display, or anything at least `WideLayout.minimumWidth`
    /// across: suggestions in a column beside the results instead of above.
    @State private var isWide = false
    /// Width of the Recents row, for how many cards it shows.
    @State private var recentsWidth: CGFloat = 0

    /// Field placeholder.
    static let prompt = "Search your library…"
    /// Suggestion rows above the results on a phone: the keyboard takes half
    /// the screen, and the photos are what the search is for (board PH_Search).
    private static let compactRowsWithResults = 3
    /// Width of the suggestion column on a wide screen (board DI_Search).
    private static let wideColumnWidth: CGFloat = 400

    var body: some View {
        content
        .onGeometryChange(for: Bool.self) { proxy in
            let insets = proxy.safeAreaInsets
            let window = VideoStudioWindowClass.windowSize(
                content: proxy.size,
                top: insets.top,
                bottom: insets.bottom,
                leading: insets.leading,
                trailing: insets.trailing
            )
            return proxy.size.width >= WideLayout.minimumWidth
                || VideoStudioWindowClass.resolve(window: window, trailingInset: insets.trailing) == .duoInner
        } action: { isWide = $0 }
        .onAppear {
            model.refreshFilterOptions()
            session.service.prepare()
            if recentsModel == nil {
                recentsModel = SearchRecentsModel(
                    store: session.service.recentSearches,
                    service: session.service,
                    libraryQueries: dependencies.libraryQueries
                )
            }
            if results == nil { results = SearchResultsModel(dependencies: dependencies) }
            recentsModel?.reload()
        }
        .task { await session.loadHighlights() }
        // The screen is not rebuilt between visits, so this is what picks up a query
        // that was just run — and drops one whose photos are gone.
        .onChange(of: session.service.recentSearches.queries) {
            recentsModel?.reload()
        }
        .onChange(of: session.results) { _, rows in
            results?.update(rows)
        }
        .photoViewerCover(item: $viewerTarget, link: viewerLink) { target in
            if let results {
                PhotoDetailScreen(
                    model: results,
                    currentIndex: results.index(of: target.id) ?? target.startIndex
                )
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if session.hasInput {
            typingContent
        } else {
            emptyContent
        }
    }

    // MARK: Empty field (FS-01.03c §5)

    private var emptyContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                indexingBanner
                recents
                libraryHighlights
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, isFieldAtTop ? 4 : AppTheme.Spacing.xs)
            .padding(.bottom, isFieldAtTop ? 16 : 72)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.never)
    }

    /// Drawn here rather than left to `navigationTitle` because both tiers hide the
    /// navigation bar's contents while the search field is active — iOS 26 drops the
    /// title, and before it the whole bar collapses into the field.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Search")
                .font(.largeTitle.bold())
            Spacer(minLength: 12)
            if let onAdvanced {
                AdvancedSearchButton(action: onAdvanced)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    /// iOS 26 puts the field at the bottom on a phone and draws it over the
    /// content; elsewhere it sits at the top.
    private var isFieldAtTop: Bool {
        if #available(iOS 26.0, *) { horizontalSizeClass == .regular } else { true }
    }

    /// While the library is still being read, results can be missing photos —
    /// say so rather than let the search look wrong (FS-01.03c §7, A7).
    @ViewBuilder
    private var indexingBanner: some View {
        if let remaining = Self.remainingToIndex(model.indexProgress), remaining > 0 {
            Label {
                Text("Reading \(remaining.formatted()) photos — results may be incomplete.")
            } icon: {
                ProgressView().controlSize(.small)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    static func remainingToIndex(_ progress: IndexProgress?) -> Int? {
        guard let progress, progress.total > 0 else { return nil }
        return max(0, progress.total - progress.processed)
    }

    /// Recent queries as picture cards, the way Photos does it: the query written
    /// over the newest photo it finds. A query that no longer finds anything is not
    /// shown at all — see SearchRecentsModel.
    @ViewBuilder
    private var recents: some View {
        if let recentsModel, !recentsModel.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Recents")
                        .font(.title3.weight(.semibold))
                    Spacer(minLength: 12)
                    Button("Clear") { recentsModel.clear() }
                        .font(.subheadline)
                }

                // A fixed-column grid rather than an `HStack`: with one or two
                // recents the cards keep their share of the row instead of
                // stretching to fill it.
                let columns = SearchRecentsModel.cardCount(width: recentsWidth, spacing: 12)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns),
                    spacing: 12
                ) {
                    ForEach(recentsModel.cards.prefix(columns)) { card in
                        RecentSearchCardView(
                            card: card,
                            photoLibrary: photoLibrary,
                            aspectRatio: columns > SearchRecentsModel.minimumCards ? 3.0 / 2.0 : 1
                        ) {
                            session.text = card.query
                        }
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { recentsWidth = $0 }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    /// The biggest cameras, lenses and places and the newest year, as rows
    /// (board PH_Search, state empty). An empty library gets the example line.
    @ViewBuilder
    private var libraryHighlights: some View {
        if session.highlights.isEmpty {
            if recentsModel?.isEmpty != false {
                Text("Try: Fukuoka · f > 1.2 · ISO trên 3200 · trước 2020 · 85mm")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("In Your Library")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 20)
                let columns = isWide ? 2 : 1
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 24, alignment: .leading), count: columns),
                    alignment: .leading,
                    spacing: 0
                ) {
                    ForEach(session.highlights) { group in
                        SearchSuggestionRow(suggestion: .group(group), typed: "", photoLibrary: photoLibrary) {
                            session.choose(group)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: Typing (FS-01.03c §2–§4)

    @ViewBuilder
    private var typingContent: some View {
        if isWide {
            HStack(alignment: .top, spacing: 24) {
                ScrollView {
                    suggestionRows(limit: SearchSession.suggestionLimit)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(width: Self.wideColumnWidth)
                resultsSection
            }
            .padding(.leading, 16)
            .padding(.trailing, 20)
            .padding(.top, 8)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                let limit = session.resultCount > 0 ? Self.compactRowsWithResults : SearchSession.suggestionLimit
                suggestionRows(limit: limit)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                resultsSection
            }
        }
    }

    private func suggestionRows(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(session.suggestions.prefix(limit)) { suggestion in
                SearchSuggestionRow(suggestion: suggestion, typed: session.trimmedText, photoLibrary: photoLibrary) {
                    session.choose(suggestion)
                }
            }
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if session.hasResults, session.resultCount > 0 {
                HStack(alignment: .firstTextBaseline) {
                    Text("Photos")
                        .font(.title3.weight(.semibold))
                    + Text(" · \(session.resultCount.formatted())")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Button("Open in Library") { openInLibrary() }
                        .font(.subheadline)
                }
                .padding(.horizontal, isWide ? 0 : 20)
                .padding(.top, 8)
                resultsGrid
            } else if session.hasResults {
                ContentUnavailableView.search(text: session.displayText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var resultsGrid: some View {
        if let results {
            PhotoGridCollectionView(
                photos: results.items,
                assetProvider: { _, item in results.asset(for: item.assetId) },
                sectionMode: .flat,
                anchorsBottom: false,
                contentVersion: results.contentGeneration,
                contentRefreshVersion: results.contentGeneration,
                jumpToNewestToken: 0,
                columnCount: Binding(
                    get: { GridDensity.clamped(storedColumns) + (isWide ? 1 : 0) },
                    set: { storedColumns = $0 - (isWide ? 1 : 0) }
                ),
                isSelecting: false,
                selectedIds: [],
                // Clears the floating field iOS 26 draws over a phone's content.
                bottomInset: isFieldAtTop ? 0 : 72,
                photoLibrary: photoLibrary,
                onTap: { flatIndex, item in
                    session.remember()
                    viewerTarget = PhotoViewerTarget(id: item.assetId, startIndex: flatIndex)
                },
                onLongPress: { _ in },
                onSwipeEvent: { _ in },
                onNearEnd: {},
                onUserScroll: { Self.dismissKeyboard() },
                removal: results.lastRemoval,
                viewerLink: viewerLink
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }

    /// Takes the search to Library, where the condition bar, sort and filter
    /// work on it as before (FS-01.03c §4).
    private func openInLibrary() {
        Task {
            let query = await session.currentQuery()
            model.applySearchQuery(query, remembering: session.displayText, using: session.service)
            onApplied()
        }
    }

    static func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// One suggestion: the value's newest photo (or a symbol), its name with the
/// typed part bold, its kind, and how many photos (FS-01.03c §2, board PH_Search).
struct SearchSuggestionRow: View {
    let suggestion: SearchSuggestion
    let typed: String
    let photoLibrary: PhotoLibraryService
    var onTap: () -> Void

    private static let thumbnailSide: CGFloat = 40
    private static let thumbnailPixels: CGFloat = 120

    @State private var image: UIImage?
    @State private var requestId: PHImageRequestID?

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                thumbnail
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.body)
                        .lineLimit(1)
                        .foregroundStyle(Color(.label))
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let count {
                    Text(count.formatted())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .task(id: keyAssetId) { await load() }
        .onDisappear(perform: cancel)
    }

    private var group: SearchGroup? {
        switch suggestion {
        case .group(let group), .didYouMean(let group): group
        case .interpretation: nil
        }
    }

    private var keyAssetId: String? { group?.keyAssetId }
    private var count: Int? { group?.count }

    private var title: AttributedString {
        switch suggestion {
        case .interpretation(let text, _):
            return AttributedString(text)
        case .didYouMean(let group):
            return AttributedString(String(localized: "Did you mean \u{201C}\(group.name)\u{201D}?",
                                           comment: "Search: the nearest library name when nothing matched"))
        case .group(let group):
            return Self.highlighted(group.name, typed: typed)
        }
    }

    private var subtitle: String {
        switch suggestion {
        case .interpretation: String(localized: "Search for these conditions", comment: "Search: the row that runs what the parser read")
        case .group(let group), .didYouMean(let group): group.category.label
        }
    }

    private var accessibilityText: String {
        let name = String(title.characters)
        guard let count else { return name }
        return "\(name), \(subtitle), \(count.formatted()) photos"
    }

    @ViewBuilder
    private var thumbnail: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(.secondarySystemFill))
            .frame(width: Self.thumbnailSide, height: Self.thumbnailSide)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var symbol: String {
        switch suggestion {
        case .interpretation: "text.magnifyingglass"
        case .group(let group), .didYouMean(let group): group.category.symbol
        }
    }

    /// Bolds the start of every word the typed words begin, the way Photos
    /// marks what matched.
    static func highlighted(_ name: String, typed: String) -> AttributedString {
        var result = AttributedString(name)
        let typedWords = SearchFolding.words(typed)
        guard !typedWords.isEmpty else { return result }
        var searchStart = name.startIndex
        while searchStart < name.endIndex {
            guard let wordStart = name[searchStart...].firstIndex(where: { $0.isLetter || $0.isNumber }) else { break }
            let wordEnd = name[wordStart...].firstIndex(where: { !($0.isLetter || $0.isNumber) }) ?? name.endIndex
            let word = SearchFolding.fold(String(name[wordStart..<wordEnd]))
            if let match = typedWords.first(where: { word.hasPrefix($0) }) {
                let boldEnd = name.index(wordStart, offsetBy: min(match.count, name.distance(from: wordStart, to: wordEnd)))
                if let lower = AttributedString.Index(wordStart, within: result),
                   let upper = AttributedString.Index(boldEnd, within: result) {
                    result[lower..<upper].font = .body.weight(.semibold)
                }
            }
            searchStart = wordEnd
        }
        return result
    }

    private func load() async {
        cancel()
        image = nil
        guard let keyAssetId else { return }
        let asset = await Task.detached(priority: .userInitiated) {
            PhotoLibraryService.fetchAssets(ids: [keyAssetId]).first
        }.value
        guard let asset, !Task.isCancelled else { return }
        requestId = photoLibrary.requestThumbnail(
            for: asset,
            targetSize: CGSize(width: Self.thumbnailPixels, height: Self.thumbnailPixels),
            allowNetwork: false
        ) { result in
            if let result { image = result }
        }
    }

    private func cancel() {
        if let requestId { photoLibrary.cancelThumbnailRequest(requestId) }
        requestId = nil
    }
}

/// One recent query as a picture card: the newest photo it finds, with the query
/// written over it.
private struct RecentSearchCardView: View {
    let card: RecentSearchCard
    let photoLibrary: PhotoLibraryService
    /// Width over height. Square on a phone; 3:2 once the row holds more
    /// than three — on the Duo's inner display the field rides the keyboard
    /// up to y 350, and square 156pt cards ran under it, captions and all.
    var aspectRatio: CGFloat = 1
    var onTap: () -> Void

    /// Square, and as wide as a third of the row allows — a fixed side would have
    /// overflowed the narrowest phones once margins and gaps were counted.
    private static let corner: CGFloat = 12
    /// Requested rendition, in pixels: a third of the widest phone at 2×, which is
    /// sharp everywhere and one cache entry rather than one per screen width.
    private static let thumbnailPixels: CGFloat = 320

    @State private var image: UIImage?
    @State private var requestId: PHImageRequestID?

    var body: some View {
        Button(action: onTap) {
            RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                .fill(Color(.secondarySystemFill))
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .aspectRatio(aspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    Text("\u{201C}\(card.query)\u{201D}")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        // The photo underneath can be any brightness, so the label
                        // carries its own shadow rather than trusting the picture.
                        .shadow(color: .black.opacity(0.7), radius: 3, y: 1)
                        .padding(8)
                }
                .contentShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search again for \(card.query)")
        .task(id: card.assetId) { await load() }
        .onDisappear(perform: cancel)
    }

    /// The PhotoKit fetch runs off the main actor (FS-01.03c §7, A4): eight
    /// cards each fetching on the main thread was a visible hitch on open.
    private func load() async {
        cancel()
        image = nil
        let assetId = card.assetId
        let asset = await Task.detached(priority: .userInitiated) {
            PhotoLibraryService.fetchAssets(ids: [assetId]).first
        }.value
        guard let asset, !Task.isCancelled else { return }
        requestId = photoLibrary.requestThumbnail(
            for: asset,
            targetSize: CGSize(width: Self.thumbnailPixels, height: Self.thumbnailPixels),
            allowNetwork: false
        ) { result in
            if let result { image = result }
        }
    }

    private func cancel() {
        if let requestId { photoLibrary.cancelThumbnailRequest(requestId) }
        requestId = nil
    }
}

/// The Advanced Search entry point.
///
/// Worded, not an icon: as a lone slider glyph it was both easy to miss and easy to
/// misread, and a bordered capsule is a bigger target than a bare glyph.
struct AdvancedSearchButton: View {
    var action: () -> Void

    var body: some View {
        Button("Advanced", action: action)
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .accessibilityLabel("Advanced Search")
    }
}
