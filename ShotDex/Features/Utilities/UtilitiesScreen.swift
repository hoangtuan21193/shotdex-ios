import Photos
import SwiftUI

/// Utilities tab: the tools, one tap from the tab bar. They used to be the
/// last group of Collections, under every album row, where a tool reached
/// now and then took a long scroll to find (user 2026-10-20). Collections
/// keeps what is browsed — albums, media types, sources.
///
/// Grouped by what the tool is for, each group one inset-grouped card of
/// rows on the grouped background (DESIGN.md §10.1). It was a grid of grey
/// pills two wide until 2026-10-23: ten identical buttons read as a wall,
/// the bold group titles shouted louder than the tools, and an odd group
/// left a hole (user: the layout is ugly). Rows also carry what is waiting —
/// duplicate groups, hidden photos, the utility albums' counts — which a pill
/// had no room for. On regular width (iPad, the Duo's inner screen) the
/// cards go into independent columns, like the Statistics dashboard, so the
/// set fills the width instead of stretching one row across it.
///
/// Statistics sits above the groups as a card with the library's numbers and
/// the last year by month (2026-10-24); the Explore group went with it, and
/// Places and Trips left the app.
struct UtilitiesScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(AppNavigation.self) private var navigation

    /// The Collections model, for the system utility albums (Recently
    /// Deleted, Unable to Upload) it already enumerates.
    private let injectedModel: AlbumsModel?
    @State private var fallbackModel = AlbumsModel()
    private var model: AlbumsModel { injectedModel ?? fallbackModel }
    private let isLibraryIndexing: Bool

    /// Photos ShotDex has hidden; the Hidden row shows only above zero.
    @State private var hiddenCount = 0
    @State private var contentWidth: CGFloat = 0

    /// The Statistics card's numbers; nil until the first load.
    @State private var overview: StatsOverview?

    /// The Combine Photos tool whose photo picker is up.
    @State private var combinePicking: CombinePurpose?
    @State private var stackPresentation: PhotoStackPresentation?
    @State private var panoramaPresentation: PanoramaMergePresentation?
    /// The tool the user picked too few photos for, to say so.
    @State private var combineTooFew: CombinePurpose?

    init(model: AlbumsModel? = nil, isLibraryIndexing: Bool = false) {
        self.injectedModel = model
        self.isLibraryIndexing = isLibraryIndexing
    }

    /// Narrowest a card may be: "Recently Deleted" plus its count and
    /// chevron, at the phone's content width.
    private static let minimumCardWidth: CGFloat = 300
    private static let columnSpacing = AppTheme.Spacing.lg

    /// Columns of `minimumCardWidth` that fit, one per group at most. A phone
    /// gets one.
    private var columnCount: Int {
        let usable = contentWidth - 2 * AppTheme.Size.screenMargin
        let fits = Int((usable + Self.columnSpacing) / (Self.minimumCardWidth + Self.columnSpacing))
        return min(UtilityGroup.allCases.count, max(1, fits))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Statistics leads, as a card of its own: the one tool here
                // with something to say before it is opened.
                NavigationLink(value: StatisticsDestination()) {
                    StatisticsOverviewCard(overview: overview, isWide: columnCount > 1)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, AppTheme.Size.screenMargin)
                .padding(.bottom, AppTheme.Spacing.xxl)
                // Independent columns, not a grid: a grid would give Create
                // the height of Library beside it.
                let columns = groupColumns(count: columnCount)
                HStack(alignment: .top, spacing: Self.columnSpacing) {
                    ForEach(columns.indices, id: \.self) { column in
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
                            ForEach(columns[column], id: \.self) { group in
                                card(group)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
                .padding(.horizontal, AppTheme.Size.screenMargin)
                if #unavailable(iOS 26.0) {
                    Color.clear.frame(height: 90)
                }
            }
            .padding(.top, AppTheme.Spacing.sm)
            .padding(.bottom, AppTheme.Spacing.xxl * 2)
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { contentWidth = $0 }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(String(localized: "Utilities", comment: "Title of the Utilities tab"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                SettingsButton()
            }
        }
        .task(id: photoLibrary.collectionsTabTokens) {
            guard photoLibrary.authorizationState.canReadLibrary else { return }
            if model.dependencies == nil { model.dependencies = dependencies }
            if model.albums.isEmpty { model.load(forChangeTokens: photoLibrary.collectionsTabTokens) }
        }
        .task(id: dependencies.sources.readCount) { refreshHiddenCount() }
        .task(id: photoLibrary.assetChangeToken) { await loadOverview() }
        .onAppear { refreshHiddenCount() }
        .collectionsDestinations(model: model, isLibraryIndexing: isLibraryIndexing)
        .sheet(item: $combinePicking) { purpose in
            VideoMediaPicker(filter: .images) { picks in
                startCombine(purpose, with: picks.map(\.assetID))
            }
            .ignoresSafeArea()
        }
        // The saved photo opens in Library, as from an album: the tool's
        // result is a photo like any other, and Library is where it lives.
        .photoStackCover($stackPresentation, onSaved: { navigation.openPhoto(assetId: $0) })
        .panoramaMergeCover($panoramaPresentation, onSaved: { navigation.openPhoto(assetId: $0) })
        .alert(
            String(localized: "Choose at least 2 photos", comment: "Alert title: a Combine Photos tool opened from Utilities got fewer than two photos"),
            isPresented: Binding(get: { combineTooFew != nil }, set: { if !$0 { combineTooFew = nil } }),
            presenting: combineTooFew
        ) { purpose in
            Button(String(localized: "Choose Photos", comment: "Alert button: pick the photos for a Combine Photos tool again")) {
                combinePicking = purpose
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: { purpose in
            Text(String(
                localized: "\(purpose.title) combines two or more photos into one.",
                comment: "Alert message: why a Combine Photos tool needs at least two photos; the argument is the tool name"
            ))
        }
    }

    /// Opens the tool on the picked photos, in the order they were picked.
    private func startCombine(_ purpose: CombinePurpose, with ids: [String]) {
        combinePicking = nil
        guard !ids.isEmpty else { return }
        let fetched = PhotoLibraryService.fetchAssets(ids: ids)
        let byID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.localIdentifier, $0) })
        let assets: [PHAsset] = ids.compactMap { byID[$0] }
        guard assets.count >= CombinePurpose.minimumPhotoCount else {
            combineTooFew = purpose
            return
        }
        switch purpose {
        case .focusStack, .hdr, .stackExposures:
            stackPresentation = PhotoStackPresentation(assets: assets, purpose: purpose)
        case .panorama:
            panoramaPresentation = PanoramaMergePresentation(assets: assets)
        }
    }

    /// Each group, in reading order, goes to the column with the fewest rows
    /// so far. Round-robin left Library and the six-row Create stacked in one
    /// column and three rows in the other — on the Duo's 669pt the last tools
    /// ended below the fold while half the screen stood empty.
    private func groupColumns(count: Int) -> [[UtilityGroup]] {
        var columns = Array(repeating: [UtilityGroup](), count: count)
        var heights = Array(repeating: 0, count: count)
        for group in UtilityGroup.allCases {
            let column = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            columns[column].append(group)
            // The header weighs about a row.
            heights[column] += items(in: group).count + 1
        }
        return columns
    }

    private func card(_ group: UtilityGroup) -> some View {
        let items = items(in: group)
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text(group.title)
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(items) { item in
                    row(item)
                    if item.id != items.last?.id {
                        // Inset to the title, as a grouped list draws it.
                        Divider().padding(.leading, UtilityRowLabel.titleInset)
                    }
                }
            }
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
            )
        }
    }

    private func items(in group: UtilityGroup) -> [UtilityItem] {
        switch group {
        case .library:
            var items: [UtilityItem] = [.tool(.backup), .tool(.onThisIPhone), .tool(.duplicates)]
            if hiddenCount > 0 { items.append(.hidden) }
            items += model.utilityAlbums.map(UtilityItem.album)
            return items
        // The Combine Photos tools, in the selection menu's order, so the
        // merges can start from here and not only from a selection.
        case .create: return [.tool(.collages), .tool(.videoProjects)] + CombinePurpose.menuRows.map(UtilityItem.combine)
        case .elsewhere: return [.tool(.localNetwork), .tool(.cloud)]
        }
    }

    @ViewBuilder
    private func row(_ item: UtilityItem) -> some View {
        switch item {
        case .tool(let tool):
            row(tool)
        case .combine(let purpose):
            Button {
                combinePicking = purpose
            } label: {
                UtilityRowLabel(title: purpose.title, systemImage: purpose.systemImage)
            }
            .buttonStyle(.plain)
        case .hidden:
            NavigationLink(value: HiddenPhotosDestination()) {
                UtilityRowLabel(
                    title: String(localized: "Hidden", comment: "Utilities row: photos ShotDex has hidden"),
                    systemImage: "eye.slash",
                    count: hiddenCount,
                    spokenDetail: String(
                        localized: "\(hiddenCount) photos",
                        comment: "VoiceOver detail on the Hidden row: how many photos ShotDex has hidden"
                    )
                )
            }
            .buttonStyle(.plain)
        case .album(let album):
            NavigationLink(value: album.id) {
                UtilityRowLabel(
                    title: album.title,
                    systemImage: album.symbolName ?? "wrench.and.screwdriver",
                    count: album.count,
                    spokenDetail: String(
                        localized: "\(album.count) photos",
                        comment: "VoiceOver detail on a Utilities album row: how many photos it holds"
                    )
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func row(_ row: UtilityRow) -> some View {
        switch row {
        case .backup:
            link(BackupScreenDestination(), String(localized: "Backup", comment: "Utilities row: back a whole library up to a network drive (FS-22)"), "clock.arrow.circlepath")
        case .onThisIPhone:
            link(
                OnThisIPhoneDestination(),
                String(localized: "On This \(KeepDevice.name)", comment: "Utilities row: photos and videos kept on the device for offline use"),
                "arrow.down.circle",
                spokenDetail: String(localized: "Photos and videos kept on this device to open without a connection", comment: "VoiceOver detail on the On This iPhone row")
            )
        case .duplicates:
            link(DuplicatesDestination(), String(localized: "Duplicates"), "square.on.square", count: duplicatesCount, spokenDetail: duplicatesCount.map {
                String(localized: "\($0) groups", comment: "VoiceOver detail on the Duplicates row: how many duplicate groups the last scan found")
            })
                .contextMenu { pinButton(.duplicates) }
        // "Video Projects", because Media Types already has a Videos album
        // and that one means the footage the user shot.
        case .collages:
            link(CreationsDestination(kind: .collage), String(localized: "Collages"), "square.grid.2x2")
        case .videoProjects:
            link(CreationsDestination(kind: .video), String(localized: "Video Projects", comment: "Utilities row: videos made in the Video Studio"), "film")
        case .localNetwork:
            link(
                OnServerDestination(),
                String(localized: "Local Network", comment: "Utilities row: browse NAS drives and computers on this network"),
                "server.rack",
                spokenDetail: String(localized: "Browse and download from NAS drives and computers on this network", comment: "VoiceOver detail on the On Local Network utilities row")
            )
        case .cloud:
            link(
                OnCloudDestination(),
                String(localized: "Cloud", comment: "Utilities row: browse Dropbox, Google Drive and other cloud folders"),
                "icloud",
                spokenDetail: String(localized: "Browse and download from Dropbox, Google Drive and other cloud folders", comment: "VoiceOver detail on the On Cloud utilities row")
            )
        }
    }

    private func link(_ value: some Hashable, _ title: String, _ systemImage: String, count: Int? = nil, spokenDetail: String? = nil) -> some View {
        NavigationLink(value: value) {
            UtilityRowLabel(title: title, systemImage: systemImage, count: count, spokenDetail: spokenDetail)
        }
        .buttonStyle(.plain)
    }

    /// Pinning still puts the tool at the top of Collections.
    private func pinButton(_ target: CollectionPinStore.Target) -> some View {
        let isPinned = dependencies.collectionPins.isPinned(target)
        return Button {
            dependencies.collectionPins.toggle(target)
        } label: {
            Label(
                isPinned ? "Unpin from Collections" : "Pin to Collections",
                systemImage: isPinned ? "pin.slash" : "pin"
            )
        }
    }

    /// Off the main thread: three aggregates over the whole index.
    private func loadOverview() async {
        let queries = dependencies.statisticsQueries
        let loaded = await Task.detached(priority: .userInitiated) { try? queries.overview() }.value
        if let loaded { overview = loaded }
    }

    private func refreshHiddenCount() {
        hiddenCount = (try? HiddenCopyStore(database: dependencies.database).hiddenCount()) ?? 0
    }

    /// How many duplicate groups the last scan found, as a bare number.
    private var duplicatesCount: Int? {
        guard let count = UserDefaults.standard.object(forKey: SettingsKeys.duplicateGroupCount) as? Int,
              count > 0
        else { return nil }
        return count
    }
}

/// The groups, in reading order.
private enum UtilityGroup: Int, CaseIterable {
    case library, create, elsewhere

    var title: String {
        switch self {
        case .library: String(localized: "Library", comment: "Utilities tab group: tools that look after the photo library")
        case .create: String(localized: "Create", comment: "Utilities tab group: things made in ShotDex")
        case .elsewhere: String(localized: "Elsewhere", comment: "Utilities tab group: photos kept on other devices and services")
        }
    }
}

/// The tools drawn every time. Hidden and the system utility albums join the
/// Library group only while they have something in them.
private enum UtilityRow {
    case backup, onThisIPhone, duplicates, collages, videoProjects, localNetwork, cloud
}

private enum UtilityItem: Identifiable {
    case tool(UtilityRow)
    /// Opens a photo picker, then the tool — these make a photo rather than
    /// keep a list, so there is no screen to push first.
    case combine(CombinePurpose)
    case hidden
    case album(AlbumItem)

    var id: String {
        switch self {
        case .tool(let tool): "tool.\(tool)"
        case .combine(let purpose): "combine.\(purpose)"
        case .hidden: "hidden"
        case .album(let album): "album.\(album.id)"
        }
    }
}

/// One row of a Utilities card: glyph, name, what is waiting, chevron.
private struct UtilityRowLabel: View {
    let title: String
    let systemImage: String
    /// Drawn trailing, unlike the Collections cards: here a number says
    /// whether a tool has work waiting, which is the reason to open it.
    var count: Int?
    /// What VoiceOver says after the title — the count with its unit, or
    /// what a tool with no count is for.
    var spokenDetail: String?

    /// Glyph column plus the gap after it, from the card's leading edge —
    /// where the title starts and the hairline between rows begins.
    static let titleInset = AppTheme.Spacing.lg + glyphWidth + AppTheme.Spacing.md
    private static let glyphWidth: CGFloat = 28

    @ScaledMetric(relativeTo: .body) private var scaledGlyphWidth = glyphWidth

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.body)
                // Not accent: DESIGN.md §10.6 keeps accent for active and
                // selected state, and a row's identifying glyph is neither.
                .foregroundStyle(.secondary)
                .frame(width: scaledGlyphWidth)
            Text(title)
                .font(.body)
                .foregroundStyle(Color(.label))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: AppTheme.Spacing.sm)
            if let count {
                Text(count, format: .number)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.md)
        .frame(minHeight: AppTheme.Size.minTouch)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityText: String {
        spokenDetail.map { "\(title), \($0)" } ?? title
    }
}
