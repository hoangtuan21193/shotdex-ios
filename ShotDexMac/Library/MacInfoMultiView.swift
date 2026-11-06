import CoreLocation
import SwiftUI

/// Get Info on several photos (board `MAC_GetInfo`, FS-18.02 §8): every
/// field shows the value they share or "Mixed"; what is typed or picked is
/// written to all of them, and a field left alone keeps each photo's own.
struct MacInfoMultiView: View {
    let selection: MacSelectionModel
    let menu: MacPhotoMenu
    var picture: ((String) -> CGImage?)?

    /// Get Info edits a selection this large at most; past it, the panel says so.
    static let limit = MacPhotoMenu.readLimit

    @Environment(MacDependencies.self) private var dependencies
    @State private var infos: [String: PhotoInfoQueries.Info] = [:]
    /// What the photos share, worked out once a load, not on every keystroke.
    @State private var shared: MacInfoShared?
    @State private var loadFailed = false
    @State private var loadedIds: Set<String> = []
    @State private var titleText = ""
    @State private var captionText = ""
    @State private var creatorText = ""
    @State private var copyrightText = ""
    @State private var keywordText = ""
    /// The text each field showed when it was loaded or last saved: back
    /// to it is "untouched", and each photo keeps its own value.
    @State private var shown: [Field: String] = [:]
    @State private var pendingSave: Task<Void, Never>?
    /// Each field's text waiting to be written, with its write.
    @State private var pendingWrites: [Field: (text: String, write: @MainActor () async -> Void)] = [:]
    @State private var lastWrite: Task<Void, Never>?
    @State private var showsExif = true
    @State private var adjustsDate = false
    @State private var adjustsLocation = false
    @State private var adjusting = false
    @FocusState private var focused: Field?
    /// The photos a sheet was opened for: a selection that moves while it is
    /// up does not change what it applies to.
    @State private var sheetIds: [String] = []

    enum Field: Hashable { case title, caption, creator, copyright }

    private var ids: [String] { selection.ids }

    var body: some View {
        Group {
            if ids.count > Self.limit {
                ContentUnavailableView(String(localized: "\(ids.count) Photos", comment: "Mac Get Info: a large selection (plural)"),
                                       systemImage: "photo.stack",
                                       description: Text("Get Info edits up to \(Self.limit) photos at a time.", comment: "Mac Get Info: selection too large"))
            } else if loadFailed || selection.loadFailed {
                ContentUnavailableView {
                    Label(String(localized: "Couldn’t Read These Photos’ Info", comment: "Mac Get Info: several, read failed"),
                          systemImage: "exclamationmark.triangle")
                } actions: {
                    Button(String(localized: "Try Again", comment: "Mac Get Info: read again")) {
                        loadFailed = false
                        selection.reload()
                        Task { await load() }
                    }
                }
            } else if loadedIds == selection.idSet, let shared, let summary = selection.summary {
                content(shared, summary)
                    // The summary of the photos before is shown dimmed until theirs lands.
                    .opacity(selection.isStale ? 0.5 : 1)
                    .disabled(selection.isStale)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: selection.idSet) { await load() }
        .task(id: menu.marksGeneration) { await load() }
        .onChange(of: selection.idSet) { old, _ in
            commitKeyword(to: Array(old))
            flushSave()
        }
        // Down to one photo, this view goes before the change above is seen.
        .onDisappear { leave() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in leave() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in leave() }
        // Leaving a field is the end of typing in it.
        .onChange(of: focused) { old, _ in if old != nil { flushSave() } }
    }

    private func load() async {
        let wanted = selection.idSet
        guard wanted.count <= Self.limit else { return }
        let isNew = loadedIds != wanted
        let read: [String: PhotoInfoQueries.Info]
        do {
            read = try await PhotoInfoQueries(database: dependencies.database).infos(photoIds: Array(wanted))
        } catch {
            if !Task.isCancelled { loadFailed = true }
            return
        }
        guard !Task.isCancelled, selection.idSet == wanted else { return }
        infos = read
        let shared = MacInfoShared(infos: Array(read.values))
        self.shared = shared
        if isNew {
            loadedIds = wanted
            titleText = shared.title ?? ""
            captionText = shared.caption ?? ""
            creatorText = shared.creator ?? ""
            copyrightText = shared.copyright ?? ""
            keywordText = ""
            shown = [.title: titleText, .caption: captionText, .creator: creatorText, .copyright: copyrightText]
        }
    }

    // MARK: Content

    private func content(_ shared: MacInfoShared, _ summary: SelectionSummaryQueries.Summary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(shared, summary).padding(16)
                Divider()
                fields(shared, summary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 12)
                Divider()
                exif(shared).padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
    }

    private func header(_ shared: MacInfoShared, _ summary: SelectionSummaryQueries.Summary) -> some View {
        HStack(alignment: .top, spacing: 12) {
            MacStackedThumbnails(ids: Array(ids.prefix(3)), picture: picture, photoLibrary: dependencies.photoLibrary)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(MacSelectionText.title(summary)).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    if summary.formats.count == 1, let format = summary.formats.first?.name {
                        Text(format).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(MacTheme.fill))
                    }
                }
                Text(MacSelectionText.subtitle(summary)).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                if let gear = shared.gear {
                    Text(gear).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func fields(_ shared: MacInfoShared, _ summary: SelectionSummaryQueries.Summary) -> some View {
        let marks = dependencies.photoMarks
        let ids = ids
        let lower = summary.ratings?.lowerBound ?? 0, upper = summary.ratings?.upperBound ?? 0
        let mixed = String(localized: "Mixed", comment: "Mac Get Info: the photos differ")
        let fileIds = ids.filter { infos[$0]?.hasFileCopy == true }
        let canWrite = !fileIds.isEmpty || canWritePhotos
        return VStack(alignment: .leading, spacing: 10) {
            MacInfoRow {
                label(String(localized: "Title", comment: "Mac Get Info: field"))
                TextField(shared.title == nil ? mixed : "", text: $titleText)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
                    // Photos keeps its own titles: only the folder photos take one.
                    .disabled(fileIds.isEmpty)
                    .help(fileIds.isEmpty ? String(localized: "Photos keeps the titles of its photos; ShotDex can’t change them.", comment: "Mac Get Info: title off")
                          : fileIds.count < ids.count ? String(localized: "Goes to the \(fileIds.count) folder photos; Photos keeps its own titles.",
                                                              comment: "Mac Get Info: title on part of a selection (plural)") : "")
                    .focused($focused, equals: .title)
                    .onChange(of: titleText) { _, text in schedule(.title, text) { await $0.setTitle(text, for: fileIds) } }
                    .onSubmit { flushSave() }
                    .accessibilityLabel(String(localized: "Title", comment: "Mac Get Info: field"))
                clearButton(.title, mixed: shared.title == nil) { await $0.setTitle("", for: fileIds) }
            }
            MacInfoRow {
                label(String(localized: "Caption", comment: "Mac Get Info: field"))
                TextField(shared.caption == nil ? mixed : "", text: $captionText, axis: .vertical)
                    .lineLimit(2...5).textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
                    .disabled(!canWrite)
                    .focused($focused, equals: .caption)
                    .onChange(of: captionText) { _, text in schedule(.caption, text) { await $0.setCaption(text, for: ids) } }
                    .onSubmit { flushSave() }
                    .accessibilityLabel(String(localized: "Caption", comment: "Mac Get Info: field"))
                clearButton(.caption, mixed: shared.caption == nil) { await $0.setCaption("", for: ids) }
            }
            MacInfoRow(alignment: .top) {
                label(String(localized: "Keywords", comment: "Mac Get Info: field")).padding(.top, 3)
                VStack(alignment: .leading, spacing: 6) {
                    MacFlowLayout(spacing: 6) {
                        ForEach(summary.keywords, id: \.name) { keyword in
                            MacInfoKeywordChip(name: keyword.name, count: keyword.count, total: summary.count) {
                                edit { await $0.remove(keyword.name, from: ids) }
                            }
                        }
                    }
                    TextField(String(localized: "Add Keyword", comment: "Mac Get Info: keyword field"), text: $keywordText)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
                        .accessibilityLabel(String(localized: "Add Keyword", comment: "Mac Get Info: keyword field"))
                        .disabled(!canWrite)
                        .onSubmit { addKeywords(ids) }
                }
            }
            MacInfoRow(alignment: .center) {
                label(String(localized: "Rating", comment: "Mac Get Info: field"))
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { stars in
                        Button {
                            let value = lower == upper && upper == stars ? 0 : stars
                            Task { await marks.apply(.rate(value), to: ids); menu.marksChanged(ids) }
                        } label: {
                            Image(systemName: lower == upper && stars <= upper ? "star.fill" : "star")
                                .font(.system(size: 14))
                                .foregroundStyle(lower == upper && stars <= upper ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.secondary))
                                .frame(width: 20, height: 22).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "\(stars) Stars for all \(ids.count) photos", comment: "Mac Get Info: star tooltip, several photos (plural)"))
                        .accessibilityLabel(MarkCopy.starsAccessibility(stars))
                    }
                }
                if lower != upper { Text(mixed).font(.system(size: 12)).foregroundStyle(.secondary) }
                Spacer(minLength: 12)
                MacMixedCheckbox(title: String(localized: "Favorite", comment: "Mac Get Info: favorite"),
                                 count: summary.favorites, total: summary.count) { menu.setFavorite($0, ids: ids) }
                    .fixedSize()
                    // Favorite is Photos' own: only when every photo is there.
                    .disabled(!shared.allInPhotos)
            }
            MacInfoRow(alignment: .center) {
                label(String(localized: "Flag", comment: "Mac Get Info: field"))
                MacSegments(choices: [(MacFlagChoice.none, String(localized: "None", comment: "Mac Get Info: no flag")),
                                      (.pick, MarkCopy.pick), (.reject, MarkCopy.reject)],
                            selected: summary.picks == summary.count ? .pick : summary.rejects == summary.count ? .reject
                                : summary.picks == 0 && summary.rejects == 0 ? .none : .mixed,
                            label: MarkCopy.flag) { choice in
                    Task { await marks.apply(.flag(choice.photoFlag), to: ids); menu.marksChanged(ids) }
                }
                .frame(width: 168)
                if summary.picks + summary.rejects > 0, summary.picks < summary.count, summary.rejects < summary.count {
                    Text(mixed).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            MacInfoRow(alignment: .center) {
                label(String(localized: "Date", comment: "Mac Get Info: field"))
                Text(MacInfoShared.dateLine(summary)).font(.system(size: 13)).monospacedDigit().lineLimit(1)
                Spacer(minLength: 8)
                if adjusting { ProgressView().controlSize(.small) }
                if shared.anyInPhotos {
                    Button(String(localized: "Adjust…", comment: "Mac Get Info: change the capture date")) { sheetIds = ids; adjustsDate = true }
                        .disabled(adjusting || !shared.allInPhotos || shared.earliest == nil)
                        .help(shared.allInPhotos ? "" : String(localized: "Only photos in Photos can be adjusted; this selection has folder photos too.",
                                                               comment: "Mac Get Info: Adjust off for a mixed selection"))
                        .accessibilityLabel(String(localized: "Adjust Date", comment: "Mac Get Info: Adjust… on Date, VoiceOver"))
                }
            }
            MacInfoRow(alignment: .center) {
                label(String(localized: "Location", comment: "Mac Get Info: field"))
                VStack(alignment: .leading, spacing: 1) {
                    Text(shared.placeName
                         ?? (shared.coordinate.flatMap(MacAdjustText.coordinates)
                             ?? (shared.hasAnyPlace ? mixed : String(localized: "None", comment: "Mac Get Info: no location"))))
                        .font(.system(size: 13))
                    if shared.hasAnyPlace, shared.coordinate == nil {
                        Text("Coordinates: Mixed", comment: "Mac Get Info: several places").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if adjusting { ProgressView().controlSize(.small) }
                if shared.anyInPhotos {
                    Button(String(localized: "Adjust…", comment: "Mac Get Info: change the location")) { sheetIds = ids; adjustsLocation = true }
                        .disabled(adjusting || !shared.allInPhotos)
                        .help(shared.allInPhotos ? "" : String(localized: "Only photos in Photos can be adjusted; this selection has folder photos too.",
                                                               comment: "Mac Get Info: Adjust off for a mixed selection"))
                        .accessibilityLabel(String(localized: "Adjust Location", comment: "Mac Get Info: Adjust… on Location, VoiceOver"))
                }
            }
            MacInfoRow {
                label(String(localized: "Creator", comment: "Mac Get Info: field"))
                TextField(shared.creator == nil ? mixed : "", text: $creatorText)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
                    .focused($focused, equals: .creator)
                    .onChange(of: creatorText) { _, text in schedule(.creator, text) { await $0.setCreator(text, for: ids) } }
                    .onSubmit { flushSave() }
                    .accessibilityLabel(String(localized: "Creator", comment: "Mac Get Info: field"))
                clearButton(.creator, mixed: shared.creator == nil) { await $0.setCreator("", for: ids) }
            }
            MacInfoRow {
                label(String(localized: "Copyright", comment: "Mac Get Info: field"))
                TextField(shared.copyright == nil ? mixed : "", text: $copyrightText)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
                    .focused($focused, equals: .copyright)
                    .onChange(of: copyrightText) { _, text in schedule(.copyright, text) { await $0.setCopyright(text, for: ids) } }
                    .onSubmit { flushSave() }
                    .accessibilityLabel(String(localized: "Copyright", comment: "Mac Get Info: field"))
                clearButton(.copyright, mixed: shared.copyright == nil) { await $0.setCopyright("", for: ids) }
            }
            MacInfoRow {
                Color.clear.frame(width: 80, height: 1)
                Text(MacInfoShared.note(count: ids.count, anyFile: !fileIds.isEmpty))
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: $adjustsDate) {
            if let first = shared.earliest {
                // The earliest moves to the new date; the rest keep their spacing.
                MacAdjustDateSheet(original: first, count: sheetIds.count) { newDate in shiftDates(by: newDate.timeIntervalSince(first)) }
            }
        }
        .sheet(isPresented: $adjustsLocation) {
            MacAdjustLocationSheet(original: shared.coordinate, count: sheetIds.count) { coordinate in setLocation(coordinate) }
        }
    }

    private func exif(_ shared: MacInfoShared) -> some View {
        DisclosureGroup(isExpanded: $showsExif) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
                let rows = shared.exifRows
                ForEach(Array(stride(from: 0, to: rows.count, by: 2)), id: \.self) { index in
                    GridRow {
                        cell(rows[index])
                        if index + 1 < rows.count { cell(rows[index + 1]) }
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            HStack {
                Text("EXIF", comment: "Mac Get Info: section").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                // One file's fields: not for a selection.
                Button(String(localized: "Show All Raw Metadata", comment: "Mac Get Info: every metadata field of the file")) {}
                    .controlSize(.small).disabled(true)
            }
        }
    }

    private func cell(_ row: (String, String)) -> some View {
        Group {
            Text(row.0).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(row.1).font(.system(size: 12)).monospacedDigit()
                .foregroundStyle(row.1 == String(localized: "Mixed", comment: "Mac Get Info: the photos differ") ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).frame(width: 80, alignment: .trailing)
    }

    // MARK: Writing

    private var editor: MacKeywordEditor {
        MacKeywordEditor(database: dependencies.database, captionKeywords: dependencies.captionKeywords,
                         sidecarQueue: dependencies.sidecarQueue, filterSuggestions: dependencies.filterSuggestions)
    }

    /// A field back at what it showed is untouched (each photo keeps its own);
    /// anything else goes to all of them a moment after typing stops.
    /// A selection's text fields write when typing is done — Return, or
    /// leaving the field — never mid-word: a pause in "Ven…" must not
    /// replace 500 different captions. Back at what it showed is untouched.
    private func schedule(_ field: Field, _ text: String, _ write: @escaping @MainActor (MacKeywordEditor) async -> MacKeywordEditor.Outcome) {
        guard loadedIds == selection.idSet else { return }
        if text == shown[field] {
            pendingWrites[field] = nil
        } else {
            let editor = editor, ids = ids
            pendingWrites[field] = (text, { report(await write(editor), ids: ids) })
        }
    }

    /// The × beside a field: "" for all of them — the one way to empty a
    /// "Mixed" field, whose own empty text means "leave each as it is".
    @ViewBuilder
    private func clearButton(_ field: Field, mixed: Bool, _ write: @escaping @MainActor (MacKeywordEditor) async -> MacKeywordEditor.Outcome) -> some View {
        if mixed {
            Button {
                let editor = editor, ids = ids
                pendingWrites[field] = nil
                switch field {
                case .title: titleText = ""
                case .caption: captionText = ""
                case .creator: creatorText = ""
                case .copyright: copyrightText = ""
                }
                let previous = lastWrite
                lastWrite = Task {
                    await previous?.value
                    report(await write(editor), ids: ids)
                }
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Clear on all \(ids.count) photos", comment: "Mac Get Info: empty a Mixed field everywhere (plural)"))
            .accessibilityLabel(String(localized: "Clear on all \(ids.count) photos", comment: "Mac Get Info: empty a Mixed field everywhere (plural)"))
        }
    }

    /// Writes go in order; what each field shows counts as saved the moment
    /// its write is queued, so typing back to it is "untouched" again.
    private func flushSave() {
        pendingSave?.cancel()
        pendingSave = nil
        let writes = pendingWrites
        pendingWrites = [:]
        guard !writes.isEmpty else { return }
        for (field, pending) in writes { shown[field] = pending.text }
        let previous = lastWrite
        lastWrite = Task {
            await previous?.value
            for pending in writes.values { await pending.write() }
        }
    }

    private var canWritePhotos: Bool {
        #if DEBUG
        if MacDemoLibrary.isOn { return true }
        #endif
        return dependencies.captionKeywords != nil
    }

    /// Going away: what was typed goes on the photos it was typed for.
    private func leave() {
        commitKeyword(to: Array(loadedIds))
        flushSave()
    }

    /// A keyword typed but not returned goes on the photos it was typed for.
    private func commitKeyword(to ids: [String]) {
        guard !ids.isEmpty, !KeywordInput.split(keywordText).isEmpty else { return }
        addKeywords(ids)
    }

    private func addKeywords(_ ids: [String]) {
        let text = keywordText
        guard !KeywordInput.split(text).isEmpty else { return }
        keywordText = ""
        let suggestions = dependencies.filterSuggestions
        edit { editor in
            let catalog = await suggestions.load().keywords
            var outcome = MacKeywordEditor.Outcome.done
            for keyword in KeywordInput.keywords(from: text, existing: KeywordInput.spellings(catalog)) {
                outcome = outcome.combined(with: await editor.add(keyword, to: ids))
            }
            return outcome
        }
    }

    private func edit(_ write: @escaping @MainActor (MacKeywordEditor) async -> MacKeywordEditor.Outcome) {
        let editor = editor, ids = ids
        Task { report(await write(editor), ids: ids) }
    }

    private func report(_ outcome: MacKeywordEditor.Outcome, ids: [String]) {
        menu.marksChanged(ids)
        switch outcome {
        case .done: break
        case .skipped(let count):
            if menu.failure == nil {
                menu.failure = String(localized: "\(count) of these photos are in Photos and didn’t take the change — Photos may not allow changes to them.",
                                      comment: "Mac Get Info: several, some Photos photos skipped (plural)")
            }
        case .failed:
            menu.failure = String(localized: "Some photos couldn’t be updated.", comment: "Mac Get Info: several, a write failed")
        }
    }

    /// Every photo moves by the same amount; the order and spacing stay.
    /// A photo with no date has nothing to move from, and is counted.
    private func shiftDates(by delta: TimeInterval) {
        guard abs(delta) >= 1 else { return }
        let writer = MacAdjustWriter(dependencies: dependencies), ids = sheetIds
        var dates: [String: Date] = [:]
        for id in ids {
            if let date = infos[id]?.metadata?.creationDate { dates[id] = Date(timeIntervalSince1970: TimeInterval(date)).addingTimeInterval(delta) }
        }
        let undated = ids.count - dates.count
        adjusting = true
        Task {
            let (outcome, skipped) = await writer.setDates(dates)
            adjusted(outcome, skipped: skipped, undated: undated, ids: ids)
        }
    }

    private func setLocation(_ coordinate: CLLocationCoordinate2D?) {
        let writer = MacAdjustWriter(dependencies: dependencies), ids = sheetIds
        adjusting = true
        Task {
            let (outcome, skipped) = await writer.setLocation(coordinate, ids: ids)
            adjusted(outcome, skipped: skipped, undated: 0, ids: ids)
        }
    }

    private func adjusted(_ outcome: MacAdjustWriter.Outcome, skipped: Int, undated: Int, ids: [String]) {
        adjusting = false
        menu.marksChanged(ids)
        dependencies.library?.reload()
        if case .failed(let reason) = outcome {
            menu.failure = reason
            return
        }
        var lines: [String] = []
        if skipped > 0 {
            lines.append(String(localized: "\(skipped) of \(ids.count) photos didn’t change yet — Photos may not allow it, or may take a moment to show it.",
                                comment: "Mac Get Info: several, some not adjusted (plural)"))
        }
        if undated > 0 {
            lines.append(String(localized: "\(undated) photos have no date to move.", comment: "Mac Get Info: several, some without a date (plural)"))
        }
        if !lines.isEmpty { menu.failure = lines.joined(separator: " ") }
    }
}

/// A keyword chip in Get Info on several photos: solid on all, dashed with
/// "2/3" on some; × takes it off all of them (board).
struct MacInfoKeywordChip: View {
    let name: String
    let count: Int
    let total: Int
    let remove: () -> Void

    var body: some View {
        let isShared = count == total
        HStack(spacing: 4) {
            Text(name)
            if !isShared { Text("\(count)/\(total)").foregroundStyle(.secondary).monospacedDigit() }
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                    .frame(width: 14, height: 14).padding(4).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(-4)
            .help(String(localized: "Remove “\(name)” from all \(total)", comment: "Mac Get Info: remove a keyword from the selection (plural)"))
            .accessibilityLabel(String(localized: "Remove keyword \(name)", comment: "Mac inspector: chip remove, VoiceOver"))
        }
        .font(.system(size: 12))
        .padding(.leading, 8).padding(.trailing, 4)
        .frame(height: 22)
        .background(Capsule().fill(isShared ? MacTheme.fill : Color.clear))
        .overlay(Capsule().strokeBorder(MacTheme.separator, style: StrokeStyle(lineWidth: 1, dash: isShared ? [] : [3, 2])))
        .help(isShared ? String(localized: "On all \(total) photos", comment: "Mac Get Info: keyword chip, all (plural)")
                       : String(localized: "On \(count) of \(total) photos", comment: "Mac Get Info: keyword chip, some (plural)"))
        .accessibilityElement(children: .contain)
    }
}

/// What several photos share: a value when every one has it, nil ("Mixed")
/// when they differ.
struct MacInfoShared {
    let infos: [PhotoInfoQueries.Info]

    private func common<T: Equatable>(_ value: (PhotoInfoQueries.Info) -> T?) -> T? {
        guard let first = infos.first.map(value) ?? nil else { return nil }
        return infos.allSatisfy { value($0) == first } ? first : nil
    }

    /// "" when none of them has one (an empty field, not "Mixed").
    private func commonText(_ value: (PhotoInfoQueries.Info) -> String?) -> String? {
        let values = infos.map { value($0) ?? "" }
        guard let first = values.first else { return nil }
        return values.allSatisfy { $0 == first } ? first : nil
    }

    var title: String? { commonText(\.title) }
    var caption: String? { commonText(\.caption) }
    var creator: String? { commonText(\.creator) }
    var copyright: String? { commonText(\.copyright) }
    var anyInPhotos: Bool { infos.contains(where: \.isInPhotos) }
    /// The earliest capture date among them: what Adjust Date moves.
    var earliest: Date? { infos.compactMap { $0.metadata?.creationDate }.min().map { Date(timeIntervalSince1970: TimeInterval($0)) } }
    var allInPhotos: Bool { !infos.isEmpty && infos.allSatisfy(\.isInPhotos) }

    var gear: String? { common { MacInfoText.gear($0.metadata) } }

    var placeName: String? { common { $0.place?.address ?? $0.place?.name } }
    var hasAnyPlace: Bool { infos.contains { $0.metadata?.latitude != nil || $0.place != nil } }
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude = common({ $0.metadata?.latitude }), let longitude = common({ $0.metadata?.longitude }) else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var exifRows: [(String, String)] {
        let mixed = String(localized: "Mixed", comment: "Mac Get Info: the photos differ")
        func row(_ label: String, _ value: (PhotoInfoQueries.Info) -> String?) -> (String, String)? {
            let values = infos.map(value)
            guard values.contains(where: { $0 != nil }) else { return nil }
            return (label, values.allSatisfy { $0 == values.first! } ? (values.first! ?? mixed) : mixed)
        }
        return [
            row(String(localized: "Make", comment: "Mac Get Info: EXIF")) { $0.metadata?.cameraManufacturer },
            row(String(localized: "Model", comment: "Mac Get Info: EXIF")) { $0.metadata?.cameraModel },
            row(String(localized: "Exposure", comment: "Mac Get Info: EXIF")) { $0.metadata?.shutterSpeedDisplay.map { "\($0) s" } },
            row(String(localized: "Aperture", comment: "Mac Get Info: EXIF")) {
                $0.metadata?.aperture.map { "f/" + $0.formatted(.number.precision(.fractionLength(0...1))) }
            },
            row(String(localized: "ISO", comment: "Mac Get Info: EXIF")) { $0.metadata?.iso.map { "\($0)" } },
            row(String(localized: "Focal Length", comment: "Mac Get Info: EXIF")) {
                $0.metadata?.focalLength.flatMap { $0.isFinite ? "\(Int($0.rounded())) mm" : nil }
            },
            row(String(localized: "Lens", comment: "Mac Get Info: EXIF")) { $0.metadata?.lensModel },
        ].compactMap { $0 }
    }

    /// "Mixed · 5:42 – 5:44 PM" on one day; the range across days.
    static func dateLine(_ summary: SelectionSummaryQueries.Summary) -> String {
        guard let first = summary.firstDate, let last = summary.lastDate else {
            return String(localized: "None", comment: "Mac Get Info: no date")
        }
        if first == last { return first.formatted(date: .abbreviated, time: .standard) }
        let range = Calendar.current.isDate(first, inSameDayAs: last)
            ? (first..<last).formatted(.interval.hour().minute())
            : (first..<last).formatted(.interval.month(.abbreviated).day().year())
        return String(localized: "Mixed · \(range)", comment: "Mac Get Info: several dates")
    }

    static func note(count: Int, anyFile: Bool) -> String {
        anyFile
            ? String(localized: "Changes apply to all \(count) photos and save to their .xmp sidecars. Untouched fields keep their own values.",
                     comment: "Mac Get Info: several, with folder photos (plural)")
            : String(localized: "Changes apply to all \(count) photos. Untouched fields keep their own values.",
                     comment: "Mac Get Info: several, Photos photos only (plural)")
    }
}
