import Photos
import SwiftUI

/// What the search screen shows, the way Photos does it: the screen title and the
/// recent searches at the top, and a short stack of tappable suggestion capsules
/// sitting directly above the search field.
///
/// Deliberately not a `List`. A full-width table of rows filled the screen and
/// read as the primary interface, so the search field looked like a secondary way
/// in. Here the field is the interface; the capsules hug it from above, at most
/// five, and each is a complete query. Tapping one searches immediately — so does
/// the keyboard's Search key, and so does a recent row — and none of them is a step
/// the others can skip.
struct SearchSuggestionsScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(PhotoLibraryService.self) private var photoLibrary

    @Binding var query: String
    let model: LibraryModel
    let service: SearchService
    /// Called once a query has been handed to the grid (dismiss, switch tab).
    var onApplied: () -> Void
    /// Opens advanced search from the title row. Nil where the surface has a free
    /// navigation bar to put it in instead (the pre-26 sheet).
    var onAdvanced: (() -> Void)?

    /// How the parser reads what is typed, as one capsule, together with the query
    /// it was computed for. Nil when the parser made nothing of it.
    ///
    /// The query is kept alongside because the capsule outlives it otherwise: a
    /// cancelled preview never assigns, and leaving the tab clears the field without
    /// the screen being rebuilt, so the last query's capsule was still sitting over
    /// an empty field. Comparing before use makes a stale value harmless.
    @State private var interpretation: (query: String, capsule: String)?

    /// Built on first appearance, because the dependencies come from the
    /// environment and are not available at init.
    @State private var recentsModel: SearchRecentsModel?

    /// Field placeholder.
    static let prompt = "Search your library…"

    /// Photos shows a handful and stops. More than this and the stack starts
    /// competing with the keyboard for the screen.
    private static let maximumSuggestions = 5

    var body: some View {
        content
        .task(id: query) {
            interpretation = await interpretationCapsule()
        }
        .onAppear {
            query = model.criteria.searchText ?? ""
            model.refreshFilterOptions()
            service.prepare()
            if recentsModel == nil {
                recentsModel = SearchRecentsModel(
                    store: service.recentSearches,
                    service: service,
                    libraryQueries: dependencies.libraryQueries
                )
            }
            recentsModel?.reload()
        }
        // The screen is not rebuilt between visits, so this is what picks up a query
        // that was just run — and drops one whose photos are gone.
        .onChange(of: service.recentSearches.queries) {
            recentsModel?.reload()
        }
    }

    /// Where the capsules go relative to the rest: they belong against the field,
    /// which is at the bottom on iOS 26 and at the top before it.
    @ViewBuilder
    private var content: some View {
        if isFieldAtTop {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    capsuleStack
                    recents
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.never)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // Scrolls only when it has to: with the keyboard up on a small
                // screen the title plus the recents strip can outgrow the space left
                // over, and clipped content is worse than content that moves.
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        recents
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.never)
                .frame(maxHeight: .infinity, alignment: .top)

                capsuleStack
            }
        }
    }

    /// Drawn here rather than left to `navigationTitle` because both tiers hide the
    /// navigation bar's contents while the search field is active — iOS 26 drops the
    /// title, and before it the whole bar collapses into the field. The screen lost
    /// its name, and Advanced Search became unreachable, the moment the user tapped
    /// in.
    ///
    /// Advanced Search rides on this row for the same reason: on iOS 26 the slot
    /// left of the field belongs to the system (see SearchTab), and before 26 the bar
    /// it used to live in is gone while searching.
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

    /// Pre-iOS 26 the field lives in the navigation bar, so the capsules belong
    /// right under it; on iOS 26 the `.search`-role tab anchors it to the bottom
    /// edge and the capsules hug it from above.
    private var isFieldAtTop: Bool {
        if #available(iOS 26.0, *) { false } else { true }
    }

    // MARK: Recents

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

                // A three-column grid rather than an `HStack`: with one or two
                // recents the cards keep their third of the row instead of
                // stretching to fill it.
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: 12),
                        count: SearchRecentsModel.maximumCards
                    ),
                    spacing: 12
                ) {
                    ForEach(recentsModel.cards) { card in
                        RecentSearchCardView(card: card, photoLibrary: photoLibrary) {
                            apply(card.query)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 4)
        }
    }

    // MARK: Suggestions

    private var capsuleStack: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(suggestions, id: \.self) { suggestion in
                capsule(suggestion) { apply(suggestion) }
            }
            if suggestions.isEmpty, query.isEmpty, recentsModel?.isEmpty != false {
                // Nothing indexed yet, so there is no real vocabulary to offer;
                // examples at least say what the field accepts.
                Text("Try: Fukuoka · f > 1.2 · ISO trên 3200 · trước 2020 · 85mm")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        // Clears the floating search field, which is drawn *over* the content on
        // iOS 26 rather than inside the safe area — without this the last capsule
        // sits behind it. The keyboard is already handled: its own safe area lifts
        // this whole stack, so the capsules ride up with the field like Photos'.
        .padding(.bottom, isFieldAtTop ? 16 : 64)
    }

    /// Up to five complete queries.
    ///
    /// While typing: what the parser understood first — that is the one the user is
    /// about to run — then names from the library that match. With an empty field:
    /// the places and cameras the library actually contains, because a suggestion
    /// that returns nothing is worse than no suggestion.
    private var suggestions: [String] {
        var result: [String] = []
        if let interpretationCapsuleText { result.append(interpretationCapsuleText) }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            result.append(contentsOf: model.availablePlaces.prefix(3))
            result.append(contentsOf: model.availableBodies.prefix(2))
        } else {
            result.append(contentsOf: model.suggestions(for: trimmed))
        }
        var seen = Set<String>()
        return result
            .filter { seen.insert($0.lowercased()).inserted }
            .prefix(Self.maximumSuggestions)
            .map { $0 }
    }

    private func capsule(_ label: String, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            Text(label)
                .font(.body)
                .lineLimit(1)
                .foregroundStyle(Color(.label))
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Color(.secondarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// The interpretation capsule, but only while it still belongs to what is in the
    /// field.
    private var interpretationCapsuleText: String? {
        guard let interpretation, interpretation.query == query else { return nil }
        return interpretation.capsule
    }

    private func interpretationCapsule() async -> (query: String, capsule: String)? {
        let asked = query
        let fragments = await service.preview(asked)
        guard !fragments.isEmpty else { return nil }
        // One capsule, not one per fragment: the whole query is what a tap runs, so
        // several capsules that all do the same thing would only be confusing.
        return (asked, fragments.joined(separator: " · "))
    }

    private func apply(_ text: String) {
        // A tapped interpretation capsule reads back as "f > 1.2", which is not
        // what the user typed — run the query itself.
        let queryToRun = text == interpretationCapsuleText ? query : text
        query = queryToRun
        model.applySearch(queryToRun, using: service)
        onApplied()
    }
}

/// One recent query as a picture card: the newest photo it finds, with the query
/// written over it.
private struct RecentSearchCardView: View {
    let card: RecentSearchCard
    let photoLibrary: PhotoLibraryService
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
                .aspectRatio(1, contentMode: .fit)
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
        .onAppear(perform: load)
        .onChange(of: card.assetId) { load() }
        .onDisappear(perform: cancel)
    }

    private func load() {
        cancel()
        image = nil
        guard let asset = PhotoLibraryService.fetchAssets(ids: [card.assetId]).first else { return }
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
