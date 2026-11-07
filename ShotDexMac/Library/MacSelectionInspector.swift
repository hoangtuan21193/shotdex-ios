import AppKit
import Photos
import SwiftUI

/// The photos selected in the grid or the list, and what they hold
/// (`SelectionSummaryQueries`), read off the main actor a moment after the
/// selection settles — a drag across the grid reads once, at its end.
@MainActor
@Observable
final class MacSelectionModel {
    private(set) var ids: [String] = []
    /// The same ids as a set, as the grid and list report them.
    @ObservationIgnored private(set) var idSet: Set<String> = []
    private(set) var summary: SelectionSummaryQueries.Summary?
    /// The read failed: the inspector says so instead of spinning.
    private(set) var loadFailed = false
    @ObservationIgnored private let database: AppDatabase
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(database: AppDatabase) {
        self.database = database
    }

    /// The summary shown is for an earlier selection; the new one is read.
    private(set) var isStale = false
    /// A star, flag or favorite is being written to the selection.
    var isApplying = false

    func set(_ selected: Set<String>) {
        guard selected != idSet else { return }
        idSet = selected
        ids = Array(selected)
        // The last summary stays (dimmed) until the new one lands: no
        // flicker while a selection is extended photo by photo.
        isStale = summary != nil
        loadFailed = false
        reload()
    }

    /// Marks changed (a menu, a key): the summary reads again.
    func reload() {
        loadTask?.cancel()
        let ids = ids, queries = SelectionSummaryQueries(database: database)
        loadFailed = false
        guard !ids.isEmpty else { summary = nil; isStale = false; return }
        loadTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            do {
                let read = try await queries.summary(ids: ids)
                guard !Task.isCancelled else { return }
                summary = read
                isStale = false
                loadFailed = false
            } catch {
                guard !Task.isCancelled else { return }
                loadFailed = true
            }
        }
    }
}

/// The inspector for a selection (board `MAC_LibrarySelected`, FS-18.02
/// §8): a summary of what is selected and the marks that apply to all of
/// it. Edit, Compare, Sync Edits… and Export… come with their screens;
/// adding and removing keywords comes with row 8b of the Mac loop.
struct MacSelectionInspector: View {
    let selection: MacSelectionModel
    let menu: MacPhotoMenu
    /// The demo's pictures (no Photos assets).
    var picture: ((String) -> CGImage?)?

    @Environment(MacDependencies.self) private var dependencies
    @State private var keywordText = ""
    @State private var isEditingKeywords = false
    @State private var showsAllKeywords = false

    var body: some View {
        if selection.ids.isEmpty {
            ContentUnavailableView(String(localized: "No Selection", comment: "Mac inspector: nothing selected"),
                                   systemImage: "photo.on.rectangle",
                                   description: Text("Select photos to see what they have in common.", comment: "Mac inspector: nothing selected, hint"))
        } else if selection.loadFailed {
            ContentUnavailableView {
                Label(String(localized: "Couldn’t Read the Selection", comment: "Mac inspector: the summary read failed"),
                      systemImage: "exclamationmark.triangle")
            } actions: {
                Button(String(localized: "Try Again", comment: "Mac inspector: read the selection again")) { selection.reload() }
            }
        } else if let summary = selection.summary {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(summary)
                    actions
                    Divider()
                    selectionSection(summary)
                    gearSection(summary)
                    exposureSection(summary)
                    keywordsSection(summary)
                    marksSection(summary)
                }
                .padding(16)
                .opacity(selection.isStale ? 0.5 : 1)
            }
        } else {
            // The count is known at once; the rest follows.
            VStack(spacing: 8) {
                Text(String(localized: "\(selection.ids.count) selected", comment: "Mac inspector: selection count while its summary is read (plural)"))
                    .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                ProgressView().controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Header

    private func header(_ summary: SelectionSummaryQueries.Summary) -> some View {
        HStack(spacing: 12) {
            MacStackedThumbnails(ids: Array(selection.ids.prefix(3)), picture: picture, photoLibrary: dependencies.photoLibrary)
            VStack(alignment: .leading, spacing: 2) {
                Text(MacSelectionText.title(summary)).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(MacSelectionText.subtitle(summary)).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Menu {
                Button(String(localized: "New Album with Selection", comment: "Mac inspector: Add to Album")) { menu.requestAlbum(for: selection.ids) }
                if !menu.albums.isEmpty {
                    Divider()
                    Section(String(localized: "Albums", comment: "Mac inspector: Add to Album, the list")) {
                        ForEach(menu.albums, id: \.id) { album in
                            Button(album.title) { menu.add(ids: selection.ids, toAlbum: album.id) }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Add to Album", comment: "Mac inspector: add the selection to an album")
                    Image(systemName: "chevron.up.down").font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 13))
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(MacTheme.fill))
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .disabled(!menu.canAddToAlbums)
            .accessibilityLabel(String(localized: "Add to Album", comment: "Mac inspector: add the selection to an album"))
            Menu {
                ForEach(MacPhotoMenu.shareServices, id: \.title) { service in
                    Button { menu.share(selection.ids, with: service) } label: {
                        Label { Text(service.menuItemTitle) } icon: { Image(nsImage: service.image) }
                    }
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.primary)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8).fill(MacTheme.fill))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(selection.ids.count > MacPhotoMenu.readLimit
                  ? String(localized: "Share up to \(MacPhotoMenu.readLimit) photos at a time.", comment: "Mac inspector: Share is off for a large selection")
                  : String(localized: "Share", comment: "Mac inspector: share the selection"))
            .accessibilityLabel(String(localized: "Share", comment: "Mac inspector: share the selection"))
            .disabled(selection.ids.count > MacPhotoMenu.readLimit)
        }
    }

    // MARK: Sections

    private func selectionSection(_ summary: SelectionSummaryQueries.Summary) -> some View {
        section(String(localized: "Selection", comment: "Mac inspector: section")) {
            if let taken = MacSelectionText.taken(summary) {
                row(String(localized: "Taken", comment: "Mac inspector: date range of the selection"), taken)
            }
            if !summary.formats.isEmpty {
                row(String(localized: "Formats", comment: "Mac inspector: file formats of the selection"),
                    summary.formats.map { "\($0.name) \($0.count.formatted())" }.joined(separator: " · "))
            }
            ForEach(Array(summary.sources.enumerated()), id: \.offset) { _, source in
                HStack(spacing: 8) {
                    Image(systemName: MacTableColumn.sourceSymbol(source.kind) ?? "folder")
                        .font(.system(size: 14)).foregroundStyle(.secondary).frame(width: 16)
                        .accessibilityHidden(true)
                    Text(source.name).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(source.count.formatted()).monospacedDigit()
                }
                .font(.system(size: 13))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func gearSection(_ summary: SelectionSummaryQueries.Summary) -> some View {
        let gear = summary.cameras.map { ($0, "camera") } + summary.lenses.map { ($0, "camera.aperture") }
        return Group {
            if !gear.isEmpty {
                section(String(localized: "Gear", comment: "Mac inspector: section")) {
                    ForEach(Array(gear.prefix(8).enumerated()), id: \.offset) { _, entry in
                        HStack(spacing: 8) {
                            Image(systemName: entry.1).font(.system(size: 14)).foregroundStyle(.secondary).frame(width: 16)
                                .accessibilityHidden(true)
                            Text(entry.0.name).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 8)
                            MacShareBar(fraction: Double(entry.0.count) / Double(max(1, summary.count)))
                                .frame(width: 32)
                                .accessibilityHidden(true)
                            Text(entry.0.count.formatted()).monospacedDigit().foregroundStyle(.secondary).frame(width: 20, alignment: .trailing)
                        }
                        .font(.system(size: 13))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func exposureSection(_ summary: SelectionSummaryQueries.Summary) -> some View {
        let cells = MacSelectionText.exposure(summary)
        return Group {
            if !cells.isEmpty {
                section(String(localized: "Exposure Range", comment: "Mac inspector: section")) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                        ForEach(cells, id: \.title) { cell in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cell.title).font(.system(size: 11)).foregroundStyle(.secondary)
                                Text(cell.value).font(.system(size: 13, weight: .medium)).monospacedDigit().lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 8).fill(MacTheme.fill))
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }

    private func keywordsSection(_ summary: SelectionSummaryQueries.Summary) -> some View {
        let shared = summary.keywords.filter { $0.count == summary.count }
        let shown = showsAllKeywords ? summary.keywords : Array(summary.keywords.prefix(24))
        let ids = selection.ids
        // Photos keywords need Photos' own write (macOS 27); without it the
        // field says so before anything is typed.
        let cannotWritePhotos = !canWritePhotosKeywords && summary.sources.contains { $0.kind == "photos" }
        return section(String(localized: "Keywords", comment: "Mac inspector: section"),
                       trailing: isEditingKeywords
                           ? String(localized: "Updating \(summary.count) photos…", comment: "Mac inspector: a keyword write in progress (plural)")
                           : shared.isEmpty ? nil : String(localized: "Shared by all \(summary.count)", comment: "Mac inspector: keywords every selected photo has")) {
            if !summary.keywords.isEmpty {
                MacFlowLayout(spacing: 6) {
                    ForEach(shown, id: \.name) { keyword in
                        MacKeywordChip(name: keyword.name, count: keyword.count, total: summary.count,
                                       addToAll: { editKeywords(.add) { await $0.add(keyword.name, to: ids) } },
                                       removeFromAll: { editKeywords(.remove) { await $0.remove(keyword.name, from: ids) } })
                    }
                    if summary.keywords.count > 24 {
                        Button(showsAllKeywords ? String(localized: "Show Fewer", comment: "Mac inspector: collapse the keyword chips")
                                                : String(localized: "+\(summary.keywords.count - 24) More", comment: "Mac inspector: keyword chips not shown")) {
                            showsAllKeywords.toggle()
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                    }
                }
                .disabled(isEditingKeywords)
            }
            TextField(summary.count == 1
                      ? String(localized: "Add keyword", comment: "Mac inspector: keyword field, one photo")
                      : String(localized: "Add keyword to all \(summary.count)", comment: "Mac inspector: keyword field (plural)"), text: $keywordText)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(summary.count == 1
                                    ? String(localized: "Add keyword to this photo", comment: "Mac inspector: keyword field, VoiceOver, one photo")
                                    : String(localized: "Add keyword to \(summary.count) photos", comment: "Mac inspector: keyword field, VoiceOver (plural)"))
                .onSubmit { addTypedKeywords() }
                .disabled(cannotWritePhotos)
                .help(cannotWritePhotos
                      ? String(localized: "Keywords of photos in Photos can be changed from ShotDex on macOS 27 or later.", comment: "Mac inspector: keyword field off")
                      : "")
        }
        .onChange(of: selection.idSet) { keywordText = "" }
    }

    private var canWritePhotosKeywords: Bool {
        #if DEBUG
        if MacDemoLibrary.isOn { return true }
        #endif
        return dependencies.captionKeywords != nil
    }

    /// "Kyoto, autumn": each keyword added to all, spelled as the library
    /// already spells it. An empty field (or only commas) does nothing.
    private func addTypedKeywords() {
        let text = keywordText
        guard !KeywordInput.split(text).isEmpty else { return }
        guard !isEditingKeywords else { NSSound.beep(); return }
        keywordText = ""
        let ids = selection.ids, suggestions = dependencies.filterSuggestions
        editKeywords(.add, restoring: text) { editor in
            // The library's own spelling of a word it already has (FS-02.07 §4).
            let catalog = await suggestions.load().keywords
            let typed = KeywordInput.keywords(from: text, existing: KeywordInput.spellings(catalog))
            var outcome = MacKeywordEditor.Outcome.done
            for keyword in typed {
                outcome = outcome.combined(with: await editor.add(keyword, to: ids))
            }
            return outcome
        }
    }

    enum KeywordEdit { case add, remove }

    /// One keyword edit at a time; the selection is read again after it, and
    /// what could not be written is said, not dropped. A typed text that did
    /// not go in comes back to the field.
    private func editKeywords(_ kind: KeywordEdit, restoring text: String? = nil,
                              _ work: @escaping @MainActor (MacKeywordEditor) async -> MacKeywordEditor.Outcome) {
        guard !isEditingKeywords else { NSSound.beep(); return }
        isEditingKeywords = true
        let editor = MacKeywordEditor(database: dependencies.database, captionKeywords: dependencies.captionKeywords,
                                      sidecarQueue: dependencies.sidecarQueue, filterSuggestions: dependencies.filterSuggestions)
        let ids = selection.ids
        Task {
            let outcome = await work(editor)
            isEditingKeywords = false
            menu.marksChanged(ids)
            switch outcome {
            case .done: break
            case .skipped(let count):
                menu.failure = kind == .add
                    ? String(localized: "\(count) of these photos are in Photos and didn’t take the keyword — Photos may not allow changes to them, or no longer has them.",
                             comment: "Mac inspector: keyword not added to some Photos photos (plural)")
                    : String(localized: "\(count) of these photos are in Photos and kept the keyword — Photos may not allow changes to them, or no longer has them.",
                             comment: "Mac inspector: keyword not removed from some Photos photos (plural)")
            case .failed:
                if let text, keywordText.isEmpty { keywordText = text }
                menu.failure = String(localized: "Some photos couldn’t be updated.", comment: "Mac inspector: a keyword write failed")
            }
        }
    }

    private func marksSection(_ summary: SelectionSummaryQueries.Summary) -> some View {
        let ids = selection.ids
        let marks = dependencies.photoMarks
        let lower = summary.ratings?.lowerBound ?? 0, upper = summary.ratings?.upperBound ?? 0
        return section(String(localized: "Rating and Flags", comment: "Mac inspector: section"),
                       busy: selection.isApplying) {
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { stars in
                        Button {
                            // The same stars again clears them, as in Photos.
                            let value = lower == upper && upper == stars ? 0 : stars
                            apply { await marks.apply(.rate(value), to: ids); menu.marksChanged(ids) }
                        } label: {
                            Image(systemName: lower == upper && stars <= upper ? "star.fill" : "star")
                                .font(.system(size: 16))
                                .foregroundStyle(lower == upper && stars <= upper ? AnyShapeStyle(MacTheme.accent) : AnyShapeStyle(.secondary))
                                .frame(width: 18, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(MarkCopy.starsAccessibility(stars))
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(MarkCopy.rating)
                Text(MacSelectionText.ratingLine(summary)).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            MacSegments(choices: [(MacFlagChoice.pick, MarkCopy.pick), (.reject, MarkCopy.reject), (.none, MarkCopy.clearFlag)],
                        selected: MacSelectionText.commonFlag(summary), label: MarkCopy.flag) { flag in
                apply { await marks.apply(.flag(flag.photoFlag), to: ids); menu.marksChanged(ids) }
            }
            HStack {
                MacMixedCheckbox(title: String(localized: "Favorite", comment: "Mac inspector: favorite toggle"),
                                 count: summary.favorites, total: summary.count) { menu.setFavorite($0, ids: ids) }
                Spacer(minLength: 8)
                Text(MacSelectionText.marksLine(summary)).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    // MARK: Pieces

    private func section(_ title: String, trailing: String? = nil, busy: Bool = false,
                         @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                if busy { ProgressView().controlSize(.mini) }
                Spacer(minLength: 8)
                if let trailing { Text(trailing).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            content()
                .disabled(busy)
        }
    }

    /// One write at a time: the controls rest until it and its re-read end.
    private func apply(_ work: @escaping @MainActor () async -> Void) {
        guard !selection.isApplying else { return }
        selection.isApplying = true
        Task {
            await work()
            selection.isApplying = false
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).monospacedDigit().multilineTextAlignment(.trailing)
        }
        .font(.system(size: 13))
        .accessibilityElement(children: .combine)
    }
}

/// Pick, Reject, or neither: the segmented control's three states. A
/// selection with mixed flags shows none of them chosen.
enum MacFlagChoice: Hashable {
    case pick, reject, none, mixed

    var photoFlag: PhotoFlag? {
        switch self {
        case .pick: .pick
        case .reject: .reject
        case .none, .mixed: nil
        }
    }
}

/// The inspector's words and numbers, kept out of the view.
enum MacSelectionText {
    static func title(_ summary: SelectionSummaryQueries.Summary) -> String {
        let photos = summary.count - summary.videoCount
        if summary.videoCount == 0 {
            return String(localized: "\(photos) Photos", comment: "Mac inspector: selection title (plural)")
        }
        if photos == 0 { return String(localized: "\(summary.videoCount) Videos", comment: "Mac inspector: selection title, videos only (plural)") }
        return String(localized: "\(summary.count) Items", comment: "Mac inspector: selection title, photos and videos (plural)")
    }

    /// "Sep 27 – 28, 2026 · 214.8 MB".
    static func subtitle(_ summary: SelectionSummaryQueries.Summary) -> String {
        let size = ByteCountFormatter.string(fromByteCount: summary.totalBytes, countStyle: .file)
        guard let first = summary.firstDate, let last = summary.lastDate else { return size }
        let dates = first == last ? first.formatted(date: .abbreviated, time: .omitted)
                                  : (first..<max(last, first.addingTimeInterval(1))).formatted(.interval.month(.abbreviated).day().year())
        return dates + " · " + size
    }

    /// "Sep 27 10:14 AM – Sep 28 5:42 PM".
    static func taken(_ summary: SelectionSummaryQueries.Summary) -> String? {
        guard let first = summary.firstDate, let last = summary.lastDate else { return nil }
        // "Sep 27 10:14 AM – Sep 28 5:42 PM" (board): date and time, no comma.
        func text(_ date: Date) -> String {
            date.formatted(.dateTime.month(.abbreviated).day()) + " " + date.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)).minute())
        }
        return first == last ? text(first) : text(first) + " – " + text(last)
    }

    struct Cell { let title: String; let value: String }

    static func exposure(_ summary: SelectionSummaryQueries.Summary) -> [Cell] {
        var cells: [Cell] = []
        func range<T: Equatable>(_ range: ClosedRange<T>?, _ text: (T) -> String) -> String? {
            range.map { $0.lowerBound == $0.upperBound ? text($0.lowerBound) : text($0.lowerBound) + " – " + text($0.upperBound) }
        }
        if let iso = range(summary.iso, { "\($0)" }) {
            cells.append(Cell(title: String(localized: "ISO", comment: "Mac inspector: exposure cell"), value: iso))
        }
        if let focal = summary.focalLength, focal.lowerBound.isFinite, focal.upperBound.isFinite {
            let value = focal.lowerBound == focal.upperBound ? "\(Int(focal.lowerBound)) mm" : "\(Int(focal.lowerBound)) – \(Int(focal.upperBound)) mm"
            cells.append(Cell(title: String(localized: "Focal Length", comment: "Mac inspector: exposure cell"), value: value))
        }
        if let aperture = range(summary.aperture, { "f/" + $0.formatted(.number.precision(.fractionLength(0...1))) }) {
            cells.append(Cell(title: String(localized: "Aperture", comment: "Mac inspector: exposure cell"), value: aperture))
        }
        // Shortest first, as "1/1000 – 1/60 s".
        if let shutter = summary.shutter {
            let value = shutter.lowerBound == shutter.upperBound ? shutterText(shutter.lowerBound) + " s"
                                                                 : shutterText(shutter.lowerBound) + " – " + shutterText(shutter.upperBound) + " s"
            cells.append(Cell(title: String(localized: "Shutter", comment: "Mac inspector: exposure cell"), value: value))
        }
        return cells
    }

    static func shutterText(_ seconds: Double) -> String {
        guard seconds > 0 else { return "0" }
        // 1/n only where it is one: 0.6 s is not "1/2".
        if seconds >= 0.3 { return seconds.formatted(.number.precision(.fractionLength(0...1))) }
        return "1/\(Int((1 / seconds).rounded()))"
    }

    static func ratingLine(_ summary: SelectionSummaryQueries.Summary) -> String {
        guard let ratings = summary.ratings else { return "" }
        if ratings.lowerBound == ratings.upperBound {
            return ratings.upperBound == 0 ? MarkCopy.unrated : MarkCopy.starsAccessibility(ratings.upperBound)
        }
        return String(localized: "Mixed · \(ratings.lowerBound) to \(ratings.upperBound) stars", comment: "Mac inspector: the selection's ratings differ")
    }

    static func commonFlag(_ summary: SelectionSummaryQueries.Summary) -> MacFlagChoice {
        guard summary.count > 0 else { return .mixed }
        if summary.picks == summary.count { return .pick }
        if summary.rejects == summary.count { return .reject }
        // Neither, or a mix: no segment is chosen — Clear Flag is an action,
        // not a state.
        return .mixed
    }

    /// "2 of 6 · 4 picked".
    static func marksLine(_ summary: SelectionSummaryQueries.Summary) -> String {
        var parts = [String(localized: "\(summary.favorites) of \(summary.count)", comment: "Mac inspector: favorites among the selection")]
        if summary.picks > 0 { parts.append(String(localized: "\(summary.picks) picked", comment: "Mac inspector: picked photos in the selection")) }
        if summary.rejects > 0 { parts.append(String(localized: "\(summary.rejects) rejected", comment: "Mac inspector: rejected photos in the selection")) }
        return parts.joined(separator: " · ")
    }
}

/// A keyword chip: solid when every selected photo has it, dashed with
/// "4 of 6" when only some do.
struct MacKeywordChip: View {
    let name: String
    let count: Int
    let total: Int
    /// A partial chip: give it to every photo.
    var addToAll: () -> Void = {}
    var removeFromAll: () -> Void = {}

    var body: some View {
        let isShared = count == total
        HStack(spacing: 4) {
            if isShared {
                Text(name)
                Button(action: removeFromAll) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .padding(-4)
                .buttonStyle(.plain)
                .help(String(localized: "Remove “\(name)” from all \(total)", comment: "Mac inspector: remove a keyword from the selection (plural)"))
                .accessibilityLabel(String(localized: "Remove keyword \(name)", comment: "Mac inspector: chip remove, VoiceOver"))
            } else {
                Button(action: addToAll) {
                    HStack(spacing: 4) {
                        Text(name)
                        Text("\(count) of \(total)", comment: "Mac inspector: a keyword some of the selection has").foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help(String(localized: "Add “\(name)” to all \(total)", comment: "Mac inspector: give a partial keyword to the whole selection (plural)"))
                .accessibilityLabel(String(localized: "\(name), on \(count) of \(total)", comment: "Mac inspector: partial keyword chip, VoiceOver"))
                .accessibilityHint(String(localized: "Adds it to all \(total)", comment: "Mac inspector: partial keyword chip, VoiceOver hint (plural)"))
            }
        }
        .font(.system(size: 12))
        .padding(.leading, 8)
        .padding(.trailing, isShared ? 4 : 8)
        .frame(height: 22)
        .background(Capsule().fill(isShared ? MacTheme.fill : Color.clear))
        .overlay(Capsule().strokeBorder(MacTheme.separator, style: StrokeStyle(lineWidth: 1, dash: isShared ? [] : [3, 2])))
        .accessibilityElement(children: .contain)
    }
}

/// The share of the selection a camera or lens has: amber on the track.
struct MacShareBar: View {
    let fraction: Double

    var body: some View {
        Capsule().fill(MacTheme.separator)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(MacTheme.accent).frame(width: max(3, proxy.size.width * min(1, fraction)))
                }
            }
            .frame(height: 4)
    }
}

/// Up to three thumbnails fanned behind each other, as Photos shows a
/// selection.
struct MacStackedThumbnails: View {
    let ids: [String]
    var picture: ((String) -> CGImage?)?
    let photoLibrary: PhotoLibraryService
    @State private var images: [String: CGImage] = [:]

    var body: some View {
        ZStack {
            ForEach(Array(ids.enumerated().reversed()), id: \.element) { index, id in
                RoundedRectangle(cornerRadius: 6)
                    .fill(MacTheme.fill2)
                    .overlay {
                        if let image = images[id] { Image(decorative: image, scale: 2).resizable().scaledToFill() }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(MacTheme.content, lineWidth: 2))
                    .frame(width: 42, height: 42)
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .rotationEffect(.degrees([0, -9, 8][min(index, 2)]))
                    .offset(x: [0, -8, 8][min(index, 2)])
            }
        }
        .frame(width: 64, height: 52)
        .accessibilityHidden(true)
        .task(id: ids) { await load() }
    }

    private func load() async {
        if let picture {
            images = ids.reduce(into: [:]) { $0[$1] = picture($1) }
            return
        }
        let wanted = ids
        let assets = await Task.detached(priority: .userInitiated) { PhotoLibraryService.fetchAssets(ids: wanted) }.value
        for asset in assets {
            let id = asset.localIdentifier
            _ = photoLibrary.requestThumbnail(for: asset, targetSize: CGSize(width: 104, height: 104), allowNetwork: false) { image, _ in
                if let image = image?.cgImage { images[id] = image }
            }
        }
    }
}

/// Chips that wrap onto the next line.
struct MacFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing
            line = max(line, size.height)
        }
        return CGSize(width: width, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

/// A segmented control in the board's look (`MAC_STYLE`): a `fill` track,
/// the chosen segment raised on `content` — never the amber tint. A value
/// not among the choices (a mixed selection) raises none.
struct MacSegments<Value: Hashable>: View {
    let choices: [(Value, String)]
    let selected: Value
    let label: String
    let choose: (Value) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                let isOn = choice.0 == selected
                Button { choose(choice.0) } label: {
                    Text(choice.1)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .background(RoundedRectangle(cornerRadius: 6).fill(isOn ? MacTheme.content : Color.clear)
                            .shadow(color: .black.opacity(isOn ? 0.12 : 0), radius: 1, y: 0.5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(2)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 8).fill(MacTheme.fill))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// A checkbox with a third, mixed state (a dash) for a selection where some
/// photos have it: 14pt, radius 4, `accentFill` when on or mixed. A click
/// on mixed or off turns it on for all.
struct MacMixedCheckbox: View {
    let title: String
    let count: Int
    let total: Int
    let set: (Bool) -> Void

    var body: some View {
        let isOn = count == total && total > 0, isMixed = count > 0 && count < total
        Button { set(!isOn) } label: {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isOn || isMixed ? MacTheme.accentFill : MacTheme.content)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(isOn || isMixed ? Color.clear : MacTheme.checkboxStroke))
                    .overlay {
                        Image(systemName: isOn ? "checkmark" : "minus")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(MacTheme.onAccentFill)
                            .opacity(isOn || isMixed ? 1 : 0)
                    }
                    .frame(width: 14, height: 14)
                Text(title).font(.system(size: 13))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isMixed ? String(localized: "\(count) of \(total)", comment: "Mac inspector: favorite, some of the selection") : isOn ? "1" : "0")
        .accessibilityAddTraits(.isToggle)
    }
}
