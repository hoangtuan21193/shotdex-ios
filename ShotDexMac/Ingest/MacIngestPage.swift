import AppKit
import SwiftUI

/// Import from Card (board `MAC_Ingest`, FS-20 §5–7): a card's photos in
/// place of the grid, oldest day first — new ones ticked, imported ones
/// marked and their days folded — and where they go in the inspector.
/// Opened from the card's row in Sources; the import keeps running when
/// the user goes elsewhere.
struct MacIngestPage: View {
    let cardId: String
    @Environment(MacDependencies.self) private var dependencies
    @State private var showsInspector = true

    var body: some View {
        Group {
            if let model = dependencies.cards.center.models[cardId] {
                MacIngestContent(model: model, showsInspector: $showsInspector)
                    .id(cardId)
            } else if dependencies.cards.root(cardId) != nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                notConnected
            }
        }
        // Made here, not in `body`: it adds to observed state.
        .task(id: cardId) { dependencies.cards.model(cardId, dependencies: dependencies) }
    }

    private var notConnected: some View {
        Group {
            ContentUnavailableView(String(localized: "Card Not Connected", comment: "Mac Import from Card: the card was pulled out"),
                                   systemImage: "sdcard",
                                   description: Text("Plug the card in again to import from it.",
                                                     comment: "Mac Import from Card: the card was pulled out"))
                .navigationTitle(String(localized: "Import from Card", comment: "Mac Import from Card: window title"))
        }
    }
}

private struct MacIngestContent: View {
    @Bindable var model: IngestModel
    @Binding var showsInspector: Bool
    @Environment(MacDependencies.self) private var dependencies
    /// Days the user opened although every photo on them is imported.
    @State private var openedDays: Set<Date> = []
    /// Worked out when what it reads changes, not on every frame: it asks
    /// the destination's drive for its free space.
    @State private var readiness: IngestReadiness?
    @State private var isEjecting = false
    @State private var asksStop = false
    /// The scroll view's width, measured: tiles get a fixed side from it.
    @State private var rowWidth: CGFloat = 0
    /// Grid or List (board `MAC_Ingest`'s toolbar), kept for next time.
    @AppStorage("macIngestShowsList") private var showsList = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MacTheme.content)
            .navigationTitle(String(localized: "Import from Card", comment: "Mac Import from Card: window title"))
            .navigationSubtitle(subtitle)
            .toolbar { toolbar }
            .inspector(isPresented: $showsInspector) {
                MacIngestInspector(model: model, readiness: readiness)
                    .inspectorColumnWidth(MacIngestPage.inspectorWidth)
            }
            .task {
                // The Mac opens on All, as the board does: imported days show, folded.
                if model.phase == .loading {
                    model.segment = .all
                    await model.load()
                }
            }
            .task(id: ReadinessKey(model: model)) {
                readiness = model.readiness
            }
            // A source added from the inspector's Add Folder… is a destination at once.
            .onChange(of: dependencies.sourcesModel.rows) { model.loadDestinations() }
            .confirmationDialog(String(localized: "Stop importing?", comment: "Mac Import from Card: confirm Stop Import"),
                                // A run that ends while the question is up: nothing left to stop.
                                isPresented: Binding(get: { asksStop && model.isRunning }, set: { asksStop = $0 })) {
                Button(String(localized: "Stop Import", comment: "Mac Import from Card: stop the running import"), role: .destructive, action: model.stop)
                Button(String(localized: "Keep Importing", comment: "Mac Import from Card: cancel Stop Import"), role: .cancel) {}
            } message: {
                Text("Photos already imported stay in \(model.destination?.name ?? ""). Import Remaining picks up the rest.",
                     comment: "Mac Import from Card: what Stop leaves")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failedToRead:
            ContentUnavailableView {
                Label(String(localized: "Can't Read \(model.card.name)", comment: "Mac Import from Card: the card's files could not be listed"),
                      systemImage: "sdcard")
            } description: {
                Text("Check that the card is plugged in, then try again.", comment: "Mac Import from Card: the card's files could not be listed")
            } actions: {
                Button(String(localized: "Try Again", comment: "Mac Import from Card: list the card again")) {
                    Task { await model.load() }
                }
            }
        case .ready, .running, .finished:
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    MacIngestHeader(model: model, canEject: dependencies.cards.canEject(model.card.id),
                                    isEjecting: isEjecting, eject: eject, stop: { asksStop = true })
                    if case .finished(let summary) = model.phase, let line = model.endingMessage {
                        MacIngestEnding(model: model, summary: summary, line: line).padding(.top, 10)
                    }
                    bar.padding(.top, 12)
                    days
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            // Tiles are as tall as they are wide: a scroller that came and went
            // as the content crossed the window's height (a day folding)
            // changed the width, so the height, so the scroller — a layout loop
            // AppKit ends by crashing. So the tiles' side comes from the scroll
            // view's own width less room for a legacy scroller, whether or not
            // one shows.
            .scrollIndicators(.visible)
            // Measured outside the scroll view: its width never moves with the scroller.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
        }
    }

    // MARK: Bar

    private var bar: some View {
        HStack(spacing: 8) {
            MacFittedSegments(title: String(localized: "Show", comment: "Mac Import from Card: All / New"),
                              options: [(String(localized: "All \(model.items.count)", comment: "Mac Import from Card: every photo on the card"), IngestModel.Segment.all),
                                        (String(localized: "New \(model.newCount)", comment: "Mac Import from Card: photos not imported yet"), .new)],
                              selection: model.segment) { model.segment = $0 }
            Button(String(localized: "Check All", comment: "Mac Import from Card: tick every new photo")) { model.checkAll() }
                .buttonStyle(MacPushButtonStyle(isDefault: false))
                .disabled(model.isRunning || model.newCount == 0)
            Button(String(localized: "Uncheck All", comment: "Mac Import from Card: untick every photo")) { model.uncheckAll() }
                .buttonStyle(MacPushButtonStyle(isDefault: false))
                .disabled(model.isRunning || model.checkedCount == 0)
            Spacer(minLength: 8)
            Text(IngestCopy.checkedLine(count: model.checkedCount, bytes: model.checkedBytes))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    // MARK: Days

    @ViewBuilder
    private var days: some View {
        let days = model.days
        if days.isEmpty {
            Text(model.items.isEmpty
                 ? String(localized: "No photos or videos on \(model.card.name).", comment: "Mac Import from Card: an empty card")
                 : IngestCopy.everythingImported(card: model.card.name))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        } else {
            // One flat lazy list of fixed rows — a day's header, a folded day,
            // six tiles — not a grid per day: grids nested in a lazy stack
            // that grow and shrink as days fold sent the scroll view's
            // layout round in a loop.
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(MacIngestRow.rows(days, opened: openedDays, asList: showsList)) { row in
                    switch row {
                    case .folded(let day):
                        MacIngestFoldedDay(day: day) { openedDays.insert(day.date) }
                    case .header(let day):
                        MacIngestDayHeader(day: day, isFolded: day.isFullyImported ? false : nil) {
                            openedDays.remove(day.date)
                        }
                    case .tiles(_, let items):
                        MacIngestTileRow(model: model, items: items, side: tileSide)
                    case .line(let item):
                        MacIngestListRow(item: item, root: model.root,
                                         isImported: model.imported.contains(item.id),
                                         isChecked: model.selection.checked.contains(item.id),
                                         isLocked: model.isRunning) { model.toggle(item) }
                    }
                }
            }
        }
    }

    /// Six tiles and five 1pt gaps across; every row has a known height, so
    /// the lazy list never guesses one — a guess that changed as a day folded
    /// under the pointer sent AppKit's layout round until it crashed.
    private var tileSide: CGFloat {
        // 20 a side of padding, 16 kept for a legacy scroller.
        let usable = rowWidth - 40 - 16 - CGFloat(MacIngestRow.columns - 1)
        return max(40, (usable / CGFloat(MacIngestRow.columns)).rounded(.down))
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // Two icon buttons in one capsule, the shown one pressed (board `MAC_Ingest`).
        ToolbarItemGroup(placement: .primaryAction) {
            viewButton(String(localized: "Grid", comment: "Mac Import from Card: show the card's photos as tiles"),
                       symbol: "square.grid.2x2", isList: false)
            viewButton(String(localized: "List", comment: "Mac Import from Card: show the card's photos as rows"),
                       symbol: "list.bullet", isList: true)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { showsInspector.toggle() } label: {
                Label(showsInspector ? String(localized: "Hide Inspector", comment: "Mac toolbar")
                                     : String(localized: "Show Inspector", comment: "Mac toolbar"),
                      systemImage: "sidebar.right")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                // A keyword typed but not yet added goes with this run.
                NotificationCenter.default.post(name: .macIngestCommitFields, object: nil)
                model.startImport()
            } label: {
                Label(IngestCopy.importButton(count: model.checkedCount), systemImage: "square.and.arrow.down")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(MacPushButtonStyle(isDefault: true, isToolbarCommand: true))
            .help(readiness?.footer ?? IngestCopy.importButton(count: model.checkedCount))
            .disabled(model.isRunning || isEjecting || readiness?.canImport != true)
            .accessibilityIdentifier("ingest.import")
        }
    }

    private func viewButton(_ title: String, symbol: String, isList: Bool) -> some View {
        Button { showsList = isList } label: {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(width: 36, height: 28)
                .background(showsList == isList ? MacTheme.pressed : Color.clear, in: RoundedRectangle(cornerRadius: 14))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier(isList ? "ingest.list" : "ingest.grid")
        .accessibilityAddTraits(showsList == isList ? .isSelected : [])
    }

    private var subtitle: String {
        var parts = [model.card.name]
        parts.append(String(localized: "\(model.items.count) items", comment: "Mac Import from Card subtitle: photos and videos on the card"))
        // With the inspector closed, why Import is off is said here.
        if !showsInspector, !model.isRunning, let reason = readiness?.footer { parts.append(reason) }
        return parts.joined(separator: " · ")
    }

    private func eject() {
        isEjecting = true
        Task {
            let ejected = await dependencies.cards.eject(model.card.id)
            isEjecting = false
            if !ejected {
                NotificationCenter.default.post(name: .macToast, object: String(localized: "\(model.card.name) couldn't be ejected. Close any app using it and try again.",
                                                                                 comment: "Mac Import from Card: Eject failed"))
            }
        }
    }

    /// What the readiness reads: a change to any of these works it out again.
    private struct ReadinessKey: Hashable {
        let checked: Int
        let bytes: Int64
        let destination: String?
        let backsUp: Bool
        /// The backup folder chosen after the box was ticked: Import may now go.
        let backupFolder: UUID?
        let phase: Bool
        let isDestinationConnected: Bool

        @MainActor
        init(model: IngestModel) {
            isDestinationConnected = model.destinationRoot != nil
            checked = model.checkedCount
            bytes = model.checkedBytes
            destination = model.settings.destinationSourceId
            backsUp = model.settings.backsUp
            backupFolder = model.settings.backupFolder?.id
            phase = model.isRunning
        }
    }
}

extension Notification.Name {
    /// Import is about to start: fields typed but not committed are taken.
    static let macIngestCommitFields = Notification.Name("ShotDexMacIngestCommitFields")
}

extension MacIngestPage {
    /// FS-20 §5: the inspector is 300pt on the Mac (board `MAC_Ingest`).
    static let inspectorWidth: CGFloat = 300
}

// MARK: - Header

/// The card (board `MAC_Ingest`): its name and space, what is new, Eject.
private struct MacIngestHeader: View {
    let model: IngestModel
    let canEject: Bool
    let isEjecting: Bool
    let eject: () -> Void
    let stop: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sdcard")
                .font(.system(size: 18))
                .foregroundStyle(MacTheme.accent)
                .frame(width: 40, height: 40)
                .background(MacTheme.accentSoft, in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.card.name).font(.system(size: 15, weight: .semibold))
                Text(details).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                if model.isRunning {
                    Text(IngestCopy.progressLine(model.liveProgress))
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                    Button(String(localized: "Stop Import…", comment: "Mac Import from Card: stop the running import, asks first"), action: stop)
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                } else {
                    Text(String(localized: "\(model.newCount) new photos", comment: "Mac Import from Card header: photos not imported yet"))
                        .font(.system(size: 13, weight: .semibold))
                    if model.imported.count > 0 {
                        Text(String(localized: "\(model.imported.count) already imported · skipped",
                                    comment: "Mac Import from Card header: photos the history says are imported"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .multilineTextAlignment(.trailing)
            Button(action: eject) {
                Label(String(localized: "Eject", comment: "Mac Import from Card: eject the card"), systemImage: "eject")
            }
            .buttonStyle(MacPushButtonStyle(isDefault: false))
            .disabled(!canEject || model.isRunning || isEjecting)
            .help(canEject ? String(localized: "Eject \(model.card.name)", comment: "Mac Import from Card: Eject's tooltip")
                           : String(localized: "This card is a folder on this Mac", comment: "Mac Import from Card: Eject off for a folder"))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 64)
        .background(MacTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(MacTheme.separator))
        .accessibilityElement(children: .contain)
    }

    /// `Memory card · 41.2 GB of 64 GB used`.
    private var details: String {
        var parts = [String(localized: "Memory card", comment: "Mac Import from Card header: what the source is")]
        // A folder standing in for a card would show this Mac's disk: only a card's own volume says.
        if canEject, let space = model.cardSpace { parts.append(IngestCopy.usedOf(used: space.used, total: space.total)) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Days

private struct MacIngestDayHeader: View {
    let day: IngestStatus.Day
    /// False on an imported day the user opened (it folds again); nil otherwise.
    let isFolded: Bool?
    let fold: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if isFolded != nil {
                Button(action: fold) {
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Fold \(MacIngestFormat.day(day.date))", comment: "Mac Import from Card: fold an imported day"))
            }
            Text(MacIngestFormat.day(day.date))
                .font(.system(size: 15, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Text(trailing).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
        }
        .frame(height: MacIngestRow.headerHeight, alignment: .bottom)
        .padding(.bottom, 8)
    }

    /// `12 items · 6 already imported`, or `400 new` on a day with nothing imported.
    private var trailing: String {
        let imported = day.importedCount
        guard imported > 0 else { return IngestCopy.newOnDay(day.items.count) }
        return String(localized: "\(day.items.count) items · \(imported) already imported",
                      comment: "Mac Import from Card: a day with some photos imported")
    }
}

/// A day whose every photo is imported: one row, opened with a click.
private struct MacIngestFoldedDay: View {
    let day: IngestStatus.Day
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).frame(width: 16, height: 16)
                Text(MacIngestFormat.day(day.date)).font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 8)
                Text(IngestCopy.collapsedDay(day.items.count)).font(.system(size: 12)).monospacedDigit()
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: MacIngestRow.headerHeight, alignment: .bottom)
        .padding(.bottom, 4)
        .accessibilityLabel(String(localized: "\(MacIngestFormat.day(day.date)), \(IngestCopy.collapsedDay(day.items.count))",
                                   comment: "Mac Import from Card: a folded day, for VoiceOver"))
        .accessibilityHint(String(localized: "Shows the day's photos", comment: "Mac Import from Card: open a folded day"))
    }
}

/// The page's lines, worked out from the days and which imported days are open.
enum MacIngestRow: Identifiable {
    case folded(IngestStatus.Day)
    case header(IngestStatus.Day)
    case tiles(id: String, [CardItem])
    /// One photo in List.
    case line(CardItem)

    static let columns = 6
    /// A List row's height: fixed, like every row here.
    static let lineHeight: CGFloat = 40
    /// A day's title line, from the row above to its baseline area.
    static let headerHeight: CGFloat = 40

    var id: String {
        switch self {
        case .folded(let day): "folded-\(day.date.timeIntervalSince1970)"
        case .header(let day): "header-\(day.date.timeIntervalSince1970)"
        case .tiles(let id, _): id
        case .line(let item): "line-" + item.id
        }
    }

    static func rows(_ days: [IngestStatus.Day], opened: Set<Date>, asList: Bool = false) -> [MacIngestRow] {
        var rows: [MacIngestRow] = []
        for day in days {
            if day.isFullyImported, !opened.contains(day.date) {
                rows.append(.folded(day))
                continue
            }
            rows.append(.header(day))
            if asList {
                rows += day.items.map(MacIngestRow.line)
                continue
            }
            var start = 0
            while start < day.items.count {
                let slice = Array(day.items[start..<min(start + columns, day.items.count)])
                rows.append(.tiles(id: "row-" + slice[0].id, slice))
                start += columns
            }
        }
        return rows
    }
}

private struct MacIngestTileRow: View {
    let model: IngestModel
    let items: [CardItem]
    let side: CGFloat

    var body: some View {
        HStack(spacing: 1) {
            ForEach(items) { item in
                MacIngestTile(item: item, root: model.root,
                              isImported: model.imported.contains(item.id),
                              isChecked: model.selection.checked.contains(item.id),
                              isLocked: model.isRunning) { model.toggle(item) }
                    .frame(width: side, height: side)
            }
            // A short last row keeps its tiles the width of the others.
            ForEach(items.count..<MacIngestRow.columns, id: \.self) { _ in
                Color.clear.frame(width: side, height: side)
            }
        }
    }
}

/// A photo in List: tick, preview, name (and its RAW+JPEG or WAV
/// partner), time, type and size — or Imported.
private struct MacIngestListRow: View {
    let item: CardItem
    let root: URL
    let isImported: Bool
    let isChecked: Bool
    let isLocked: Bool
    let toggle: () -> Void
    @State private var image: CGImage?

    var body: some View {
        Button { if !isImported && !isLocked { toggle() } } label: {
            HStack(spacing: 10) {
                Group {
                    if isImported {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    } else {
                        MacIngestCheckbox(isChecked: isChecked, onPhoto: false)
                    }
                }
                .frame(width: 18)
                Color.clear
                    .frame(width: 32, height: 32)
                    .overlay {
                        if let image { Image(decorative: image, scale: 2).resizable().scaledToFill() } else { MacTheme.fill }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text(names)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(item.date.map { $0.formatted(date: .omitted, time: .shortened) } ?? "")
                    .frame(width: 70, alignment: .trailing)
                Text(item.primary.pathExtension.uppercased())
                    .frame(width: 44, alignment: .leading)
                Text(isImported ? String(localized: "Imported", comment: "Mac Import from Card: a tile already imported")
                                : IngestCopy.bytes(item.byteCount))
                    .frame(width: 80, alignment: .trailing)
            }
            .font(.system(size: 12))
            .foregroundStyle(isImported ? Color.secondary : Color.primary)
            .monospacedDigit()
            .padding(.horizontal, 8)
            .frame(height: MacIngestRow.lineHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Divider().padding(.leading, 70) }
        .accessibilityLabel(item.primary.name)
        .accessibilityValue(isImported ? String(localized: "Imported", comment: "Mac Import from Card: a tile already imported")
                            : isChecked ? String(localized: "Checked", comment: "Mac Import from Card: a ticked tile")
                            : String(localized: "Not checked", comment: "Mac Import from Card: an unticked tile"))
        .task(id: item.id) {
            image = await MacCardThumbnails.shared.image(for: item.primary.path, on: root)
        }
    }

    /// `IMG_5884.CR3 + JPG`.
    private var names: String {
        let partners = item.files.dropFirst().map { $0.pathExtension.uppercased() }
        return partners.isEmpty ? item.primary.name : item.primary.name + " + " + partners.joined(separator: ", ")
    }
}

/// The tick on a tile and on a List row: the accent box when checked; on
/// a photo an outlined box over a scrim, on a row a plain outline.
private struct MacIngestCheckbox: View {
    let isChecked: Bool
    let onPhoto: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(isChecked ? MacTheme.accent : (onPhoto ? Color.black.opacity(0.2) : Color.clear))
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(isChecked ? Color.clear : (onPhoto ? Color.white : MacTheme.checkboxStroke), lineWidth: onPhoto ? 1.5 : 1)
            if isChecked {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
            }
        }
        .frame(width: onPhoto ? 18 : 14, height: onPhoto ? 18 : 14)
        .accessibilityHidden(true)
    }
}

// MARK: - Tile

private struct MacIngestTile: View {
    let item: CardItem
    let root: URL
    let isImported: Bool
    let isChecked: Bool
    let isLocked: Bool
    let toggle: () -> Void
    @State private var image: CGImage?

    var body: some View {
        // Not `.disabled`: that greys the picture, and an imported photo is
        // shown as it is (board `MAC_Ingest`). A click on it does nothing.
        Button { if !isImported && !isLocked { toggle() } } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let image {
                        Image(decorative: image, scale: 2).resizable().scaledToFill()
                    } else {
                        MacTheme.fill
                    }
                }
                .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom).frame(height: 40)
                }
                .overlay(alignment: .topLeading) { mark.padding(8) }
                .overlay(alignment: .topTrailing) { badge.padding(8) }
                .overlay(alignment: .bottomTrailing) {
                    if !isImported {
                        Text(item.primary.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(8)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if isImported { importedPill.padding(8) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isImported ? String(localized: "\(item.primary.name) is already imported", comment: "Mac Import from Card: tooltip on an imported tile")
                         : item.primary.name)
        .accessibilityLabel(item.primary.name)
        .accessibilityValue(isImported ? String(localized: "Imported", comment: "Mac Import from Card: a tile already imported")
                            : isChecked ? String(localized: "Checked", comment: "Mac Import from Card: a ticked tile")
                            : String(localized: "Not checked", comment: "Mac Import from Card: an unticked tile"))
        .task(id: item.id) {
            image = await MacCardThumbnails.shared.image(for: item.primary.path, on: root)
        }
    }

    @ViewBuilder
    private var mark: some View {
        if !isImported { MacIngestCheckbox(isChecked: isChecked, onPhoto: true) }
    }

    /// `CR3`, `HIF`: the primary file's type; a RAW + JPEG pair says the RAW.
    private var badge: some View {
        Text(item.primary.pathExtension.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
            .accessibilityHidden(true)
    }

    private var importedPill: some View {
        Label(String(localized: "Imported", comment: "Mac Import from Card: a tile already imported"), systemImage: "checkmark")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(Color.black.opacity(0.55), in: Capsule())
            .accessibilityHidden(true)
    }
}

/// The card's own previews (FS-20 §5): the one the camera embedded, read
/// off the main actor two at a time; never a full RAW decode.
actor MacCardThumbnails {
    static let shared = MacCardThumbnails()
    private let cache = NSCache<NSURL, CGImageBox>()
    private var reading = 0

    init() { cache.countLimit = 600 }

    /// The sandbox lets the card be read only inside its security scope:
    /// opened around each read.
    func image(for path: String, on root: URL) async -> CGImage? {
        let url = root.appendingPathComponent(path)
        if let cached = cache.object(forKey: url as NSURL) { return cached.image }
        while reading >= 2 {
            try? await Task.sleep(for: .milliseconds(30))
            if Task.isCancelled { return nil }
        }
        guard !Task.isCancelled else { return nil }
        reading += 1
        defer { reading -= 1 }
        let image = await Task.detached(priority: .utility) { () -> CGImage? in
            let isAccessing = root.startAccessingSecurityScopedResource()
            defer { if isAccessing { root.stopAccessingSecurityScopedResource() } }
            return Self.preview(of: url)
        }.value
        guard let image else { return nil }
        cache.setObject(CGImageBox(image), forKey: url as NSURL)
        return image
    }

    nonisolated static func preview(of url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 300,
        ]
        if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) { return image }
        guard !PairingRule.isRaw(url.lastPathComponent) else { return nil }
        options[kCGImageSourceCreateThumbnailFromImageAlways] = true
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    final class CGImageBox {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }
}

enum MacIngestFormat {
    /// `Monday, September 28`.
    static func day(_ date: Date) -> String {
        guard date != Calendar.current.startOfDay(for: .distantPast) else {
            return String(localized: "No Date", comment: "Mac Import from Card: files with no date")
        }
        return date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}

/// A run that did not end cleanly (FS-20 §8): what happened, and the way
/// to finish the job — the rest of the batch, or the files that failed.
private struct MacIngestEnding: View {
    let model: IngestModel
    let summary: IngestSummary
    let line: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(line).font(.system(size: 13, weight: .medium))
                if !summary.failed.isEmpty {
                    Text(String(localized: "\(summary.failed.count) files couldn't be copied.", comment: "Mac Import from Card: files that failed in the last run"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if !summary.failed.isEmpty {
                Button(String(localized: "Retry Failed", comment: "Mac Import from Card: copy the failed files again"), action: model.retryFailed)
                    .buttonStyle(MacPushButtonStyle(isDefault: false))
            }
            if !summary.remaining.isEmpty {
                Button(String(localized: "Import Remaining", comment: "Mac Import from Card: copy what the last run did not reach"), action: model.importRemaining)
                    .buttonStyle(MacPushButtonStyle(isDefault: true))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }
}
