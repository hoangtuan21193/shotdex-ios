import CoreLocation
import AppKit
import Photos
import SwiftUI

/// Get Info (board `MAC_GetInfoSingle`, FS-18.02 §8, ⌘I): a 420pt utility
/// panel, not modal, that follows the photo selected in the library window.
/// Fields save as they are typed.
@MainActor
enum MacInfoPanel {
    private static var panel: NSPanel?
    private static var hosting: NSHostingView<AnyView>?
    private static weak var lastSelection: MacSelectionModel?

    /// `selection` and `menu` are the asking window's: the panel follows the
    /// window it was last called from, and lets go of a closed one.
    static func toggle(dependencies: MacDependencies, selection: MacSelectionModel, menu: MacPhotoMenu,
                       picture: ((String) -> CGImage?)?, onlyShows: Bool = false) {
        if let panel, panel.isVisible, !onlyShows {
            panel.orderOut(nil)
            return
        }
        let panel = panel ?? make(dependencies: dependencies, selection: selection, menu: menu, picture: picture)
        let root = AnyView(MacInfoView(selection: selection, menu: menu, picture: picture).environment(dependencies))
        // The same view while it serves the same window: a field being
        // edited keeps its text and its pending save.
        if hosting == nil || lastSelection !== selection {
            let hosting = NSHostingView(rootView: root)
            panel.contentView = hosting
            self.hosting = hosting
        }
        lastSelection = selection
        self.panel = panel
        // Shown without taking the keyboard: arrows and ⌘A stay with the grid
        // until a field is clicked (as Photos' Info).
        panel.orderFront(nil)
    }

    private static func make(dependencies: MacDependencies, selection: MacSelectionModel, menu: MacPhotoMenu,
                             picture: ((String) -> CGImage?)?) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 640),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = String(localized: "Info", comment: "Mac Get Info panel title")
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.contentMinSize = NSSize(width: 420, height: 360)
        panel.contentMaxSize = NSSize(width: 420, height: 2000)
        // No zoom, no minimize: a utility panel (FS-18.02 §8).
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.setFrameAutosaveName("MacInfoPanel")
        if !panel.setFrameUsingName("MacInfoPanel") { panel.center() }
        return panel
    }
}

/// The panel's content: one photo's info and fields, or a word on why there
/// is none.
struct MacInfoView: View {
    let selection: MacSelectionModel
    let menu: MacPhotoMenu
    var picture: ((String) -> CGImage?)?

    @Environment(MacDependencies.self) private var dependencies
    @State private var info: PhotoInfoQueries.Info?
    @State private var loadedId: String?
    @State private var titleText = ""
    @State private var captionText = ""
    @State private var keywordText = ""
    @State private var creatorText = ""
    @State private var copyrightText = ""
    /// Metering and White Balance, read from the file itself (the index has neither).
    @State private var fileExif: [(String, String)] = []
    @State private var rawEntries: [MacRawMetadata.Entry]?
    @State private var showsRaw = false
    @State private var rawUnavailable: String?
    @State private var adjustsDate = false
    @State private var adjustsLocation = false
    /// An Adjust… write is running: its button waits.
    @State private var adjusting = false
    @State private var pendingSave: Task<Void, Never>?
    /// Writes waiting for typing to pause, one per field; all run at once
    /// when the photo changes, the panel closes or the app quits.
    @State private var pendingWrites: [Field: @MainActor () async -> Void] = [:]
    /// The text each field last saved (not the reloaded info, which lags).
    @State private var lastSaved: [Field: String] = [:]
    /// Writes run one after another, so the last text typed is the one kept.
    @State private var lastWrite: Task<Void, Never>?
    @State private var saveState: SaveState = .idle

    enum Field: Hashable { case title, caption, creator, copyright }
    enum SaveState: Equatable { case idle, saving, saved, failed }
    @State private var showsExif = true
    @State private var showsServers = true
    @State private var loadFailed = false


    private var photoId: String? { selection.ids.count == 1 ? selection.ids.first : nil }

    var body: some View {
        Group {
            if let photoId {
                if loadFailed {
                    ContentUnavailableView(String(localized: "Couldn’t Read This Photo’s Info", comment: "Mac Get Info: read failed"),
                                           systemImage: "exclamationmark.triangle")
                } else if let info, loadedId == photoId {
                    content(photoId, info)
                } else {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if selection.ids.isEmpty {
                ContentUnavailableView(String(localized: "No Selection", comment: "Mac Get Info: nothing selected"), systemImage: "info.circle",
                                       description: Text("Select a photo to see its info.", comment: "Mac Get Info: hint"))
            } else {
                ContentUnavailableView(String(localized: "\(selection.ids.count) Photos", comment: "Mac Get Info: several selected (plural)"),
                                       systemImage: "photo.stack",
                                       description: Text("Select one photo to edit its info.", comment: "Mac Get Info: several selected, hint"))
            }
        }
        .frame(minWidth: 420, maxWidth: 420, minHeight: 360)
        .background(MacTheme.sheet)
        .task(id: "\(photoId ?? "")-\(menu.marksGeneration)") { await load() }
        // Typing in one photo and moving to the next saves the first at once,
        // a keyword not yet returned included.
        .onChange(of: photoId) { old, _ in
            if let old { commitKeyword(for: old) }
            flushSave()
            fileExif = []
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in flushSave() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in flushSave() }
    }

    private func load() async {
        guard let photoId else { info = nil; loadedId = nil; return }
        let isNewPhoto = loadedId != photoId
        let read: PhotoInfoQueries.Info
        do {
            read = try await PhotoInfoQueries(database: dependencies.database).info(photoId: photoId)
        } catch {
            if !Task.isCancelled { loadFailed = true }
            return
        }
        guard !Task.isCancelled else { return }
        loadFailed = false
        info = read
        if isNewPhoto {
            loadedId = photoId
            titleText = read.title ?? ""
            captionText = read.caption ?? ""
            creatorText = read.creator ?? ""
            copyrightText = read.copyright ?? ""
            lastSaved = [.title: titleText, .caption: captionText, .creator: creatorText, .copyright: copyrightText]
            fileExif = []
            rawEntries = nil
            keywordText = ""
            saveState = .idle
            if let url = fileURL(read) {
                let properties = await MacRawMetadata.properties(of: url)
                guard !Task.isCancelled, loadedId == photoId, let properties else { return }
                fileExif = [(String(localized: "Metering", comment: "Mac Get Info: EXIF"), MacRawMetadata.metering(properties)),
                            (String(localized: "White Balance", comment: "Mac Get Info: EXIF"), MacRawMetadata.whiteBalance(properties))]
                    .compactMap { label, value in value.map { (label, $0) } }
            }
            keywordText = ""
            saveState = .idle
        }
    }

    // MARK: Content

    private func content(_ id: String, _ info: PhotoInfoQueries.Info) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(id, info).padding(16)
                Divider()
                fields(id, info).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 12)
                Divider()
                exif(info).padding(.horizontal, 16).padding(.vertical, 10)
                if !info.serverCopies.isEmpty {
                    Divider()
                    servers(info).padding(.horizontal, 16).padding(.vertical, 10)
                }
            }
        }
    }

    private func header(_ id: String, _ info: PhotoInfoQueries.Info) -> some View {
        let metadata = info.metadata
        return HStack(alignment: .top, spacing: 12) {
            MacInfoThumbnail(id: id, picture: picture, photoLibrary: dependencies.photoLibrary)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(metadata?.originalFilename ?? String(localized: "Photo", comment: "Mac Get Info: a photo with no file name"))
                        .font(.system(size: 15, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    if let format = MacPhotoTile.format(of: metadata?.originalFilename) {
                        Text(format).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(MacTheme.fill))
                    }
                }
                if let gear = MacInfoText.gear(metadata) {
                    Text(gear).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                if let exposure = MacInfoText.exposure(metadata) {
                    Text(exposure).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Fields

    private func fields(_ id: String, _ info: PhotoInfoQueries.Info) -> some View {
        let summary = selection.summary
        let marks = dependencies.photoMarks
        let rating = summary?.ratings?.upperBound ?? 0
        let canWriteCaption = info.hasFileCopy || canWritePhotos
        return VStack(alignment: .leading, spacing: 10) {
            MacInfoRow {
                label(String(localized: "Title", comment: "Mac Get Info: field"))
                TextField(info.hasFileCopy ? "" : String(localized: "Kept by Photos", comment: "Mac Get Info: title placeholder, photo only in Photos"),
                          text: $titleText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .disabled(!info.hasFileCopy)
                    .accessibilityHint(info.hasFileCopy ? "" : String(localized: "Photos keeps the titles of its photos; ShotDex can’t change them.",
                                                                      comment: "Mac Get Info: title off for a photo only in Photos"))
                    .onChange(of: titleText) { _, text in
                        guard loadedId == id else { return }
                        scheduleSave(.title, text: text, id) { await $0.setTitle(text, for: id) }
                    }
                    .accessibilityLabel(String(localized: "Title", comment: "Mac Get Info: field"))
            }
            MacInfoRow {
                label(String(localized: "Caption", comment: "Mac Get Info: field"))
                TextField("", text: $captionText, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .disabled(!canWriteCaption)
                    .onChange(of: captionText) { _, text in
                        guard loadedId == id else { return }
                        scheduleSave(.caption, text: text, id) { await $0.setCaption(text, for: id) }
                    }
                    .onSubmit { flushSave() }
                    .accessibilityLabel(String(localized: "Caption", comment: "Mac Get Info: field"))
            }
            MacInfoRow(alignment: .top) {
                label(String(localized: "Keywords", comment: "Mac Get Info: field")).padding(.top, 3)
                keywords(id, info)
            }
            MacInfoRow(alignment: .center) {
                label(String(localized: "Rating", comment: "Mac Get Info: field"))
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { stars in
                        Button {
                            let value = rating == stars ? 0 : stars
                            Task { await marks.apply(.rate(value), to: [id]); menu.marksChanged([id]) }
                        } label: {
                            Image(systemName: stars <= rating ? "star.fill" : "star")
                                .font(.system(size: 14))
                                .foregroundStyle(stars <= rating ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.secondary))
                                .frame(width: 20, height: 22).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(stars == 1 ? String(localized: "1 Star (1)", comment: "Mac Get Info: star tooltip")
                                         : String(localized: "\(stars) Stars (\(stars))", comment: "Mac Get Info: star tooltip (plural)"))
                        .accessibilityLabel(MarkCopy.starsAccessibility(stars))
                        .accessibilityAddTraits(stars <= rating ? .isSelected : [])
                    }
                    Spacer(minLength: 12)
                    // Favorite is Photos' own (FS-18.01b §4): shown for every photo,
                    // off for one that is not in Photos.
                    MacMixedCheckbox(title: String(localized: "Favorite", comment: "Mac Get Info: favorite"),
                                     count: summary?.favorites ?? 0, total: 1) { menu.setFavorite($0, ids: [id]) }
                        .fixedSize()
                        .disabled(!info.isInPhotos)
                        .help(info.isInPhotos ? "" : String(localized: "Favorites are kept by Photos; this photo isn’t in Photos.",
                                                            comment: "Mac Get Info: favorite off for a folder photo"))
                }
            }
            MacInfoRow(alignment: .center) {
                label(String(localized: "Flag", comment: "Mac Get Info: field"))
                MacSegments(choices: [(MacFlagChoice.none, String(localized: "None", comment: "Mac Get Info: no flag")),
                                      (.pick, MarkCopy.pick), (.reject, MarkCopy.reject)],
                            selected: summary.map { $0.picks == 1 ? .pick : $0.rejects == 1 ? .reject : .none } ?? .mixed,
                            label: MarkCopy.flag) { choice in
                    Task { await marks.apply(.flag(choice.photoFlag), to: [id]); menu.marksChanged([id]) }
                }
                .frame(width: 168)
                Spacer(minLength: 0)
            }
            if info.metadata?.creationDate != nil || info.isInPhotos {
                let taken = info.metadata?.creationDate.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                MacInfoRow(alignment: .center) {
                    label(String(localized: "Date", comment: "Mac Get Info: field"))
                    Text(info.metadata?.creationDate == nil ? String(localized: "None", comment: "Mac Get Info: no date")
                                                              : (taken ?? Date()).formatted(date: .abbreviated, time: .standard))
                        .font(.system(size: 13)).monospacedDigit().textSelection(.enabled)
                        .help(info.isInPhotos ? "" : String(localized: "The date comes from the file; only photos in Photos can be adjusted.",
                                                            comment: "Mac Get Info: no Adjust… for a folder photo"))
                    Spacer(minLength: 8)
                    if info.isInPhotos {
                        Button(String(localized: "Adjust…", comment: "Mac Get Info: change the capture date")) { adjustsDate = true }
                            .disabled(adjusting)
                            .accessibilityLabel(String(localized: "Adjust Date", comment: "Mac Get Info: Adjust… on Date, VoiceOver"))
                    }
                }
                .sheet(isPresented: $adjustsDate) {
                    MacAdjustDateSheet(original: taken) { newDate in
                        adjusting = true
                        Task { await adjusted(id, MacAdjustWriter(dependencies: dependencies).setDate(newDate, id: id), reloadsLibrary: true) }
                    }
                }
            }
            if let place = MacInfoText.place(info) ?? (info.isInPhotos ? MacInfoText.Place(name: nil, coordinates: nil) : nil) {
                MacInfoRow(alignment: .center) {
                    label(String(localized: "Location", comment: "Mac Get Info: field"))
                    VStack(alignment: .leading, spacing: 1) {
                        if let name = place.name { Text(name).font(.system(size: 13)) }
                        if let coordinates = place.coordinates {
                            Text(coordinates).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                        }
                        if place.name == nil, place.coordinates == nil {
                            Text("None", comment: "Mac Get Info: no location").font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                    }
                    .textSelection(.enabled)
                    .help(info.isInPhotos ? "" : String(localized: "The place comes from the file; only photos in Photos can be adjusted.",
                                                        comment: "Mac Get Info: no Adjust… for a folder photo"))
                    Spacer(minLength: 8)
                    if adjusting { ProgressView().controlSize(.small) }
                    if info.isInPhotos {
                        Button(String(localized: "Adjust…", comment: "Mac Get Info: change the location")) { adjustsLocation = true }
                            .disabled(adjusting)
                            .accessibilityLabel(String(localized: "Adjust Location", comment: "Mac Get Info: Adjust… on Location, VoiceOver"))
                    }
                }
                .sheet(isPresented: $adjustsLocation) {
                    MacAdjustLocationSheet(original: MacInfoText.coordinate(info)) { coordinate in
                        adjusting = true
                        Task { await adjusted(id, MacAdjustWriter(dependencies: dependencies).setLocation(coordinate, id: id), reloadsLibrary: true) }
                    }
                }
            }
            MacInfoRow {
                label(String(localized: "Creator", comment: "Mac Get Info: field"))
                TextField("", text: $creatorText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .onChange(of: creatorText) { _, text in
                        guard loadedId == id else { return }
                        scheduleSave(.creator, text: text, id) { await $0.setCreator(text, for: id) }
                    }
                    .accessibilityLabel(String(localized: "Creator", comment: "Mac Get Info: field"))
            }
            MacInfoRow {
                label(String(localized: "Copyright", comment: "Mac Get Info: field"))
                TextField("", text: $copyrightText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .onChange(of: copyrightText) { _, text in
                        guard loadedId == id else { return }
                        scheduleSave(.copyright, text: text, id) { await $0.setCopyright(text, for: id) }
                    }
                    .accessibilityLabel(String(localized: "Copyright", comment: "Mac Get Info: field"))
            }
            MacInfoRow {
                Color.clear.frame(width: 80, height: 1)
                VStack(alignment: .leading, spacing: 2) {
                    if !info.hasFileCopy && !canWritePhotos {
                        Text("Caption and keywords of photos in Photos can be changed from ShotDex on macOS 27 or later.",
                             comment: "Mac Get Info: Photos not writable here")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Text(MacInfoText.saveNote(info)).font(.system(size: 11)).foregroundStyle(.secondary)
                    switch saveState {
                    case .idle: EmptyView()
                    case .saving: Text("Saving…", comment: "Mac Get Info: a save in progress").font(.system(size: 11)).foregroundStyle(.secondary)
                    case .saved: Text("Saved", comment: "Mac Get Info: the last change is saved").font(.system(size: 11)).foregroundStyle(.secondary)
                    case .failed:
                        Text("Couldn’t save the last change.", comment: "Mac Get Info: the last save failed")
                            .font(.system(size: 11)).foregroundStyle(.red)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func keywords(_ id: String, _ info: PhotoInfoQueries.Info) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MacFlowLayout(spacing: 6) {
                ForEach(info.keywords, id: \.self) { keyword in
                    MacKeywordChip(name: keyword, count: 1, total: 1,
                                   removeFromAll: { edit { await $0.remove(keyword, from: [id]) } })
                }
            }
            TextField(String(localized: "Add Keyword", comment: "Mac Get Info: keyword field"), text: $keywordText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(String(localized: "Add Keyword", comment: "Mac Get Info: keyword field"))
                .disabled(!info.hasFileCopy && !canWritePhotos)
                .onSubmit {
                    let text = keywordText
                    guard !KeywordInput.split(text).isEmpty else { return }
                    keywordText = ""
                    let suggestions = dependencies.filterSuggestions
                    edit { editor in
                        let catalog = await suggestions.load().keywords
                        var outcome = MacKeywordEditor.Outcome.done
                        for keyword in KeywordInput.keywords(from: text, existing: KeywordInput.spellings(catalog)) {
                            outcome = outcome.combined(with: await editor.add(keyword, to: [id]))
                        }
                        return outcome
                    }
                }
        }
    }

    private func exif(_ info: PhotoInfoQueries.Info) -> some View {
        DisclosureGroup(isExpanded: $showsExif) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
                let rows = MacInfoText.exifRows(info.metadata) + fileExif
                ForEach(Array(stride(from: 0, to: rows.count, by: 2)), id: \.self) { index in
                    GridRow {
                        exifCell(rows[index])
                        if index + 1 < rows.count { exifCell(rows[index + 1]) }
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            HStack {
                Text("EXIF", comment: "Mac Get Info: section").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "Show All Raw Metadata", comment: "Mac Get Info: every metadata field of the file")) {
                    showRaw(info)
                }
                .controlSize(.small)
            }
        }
        .sheet(isPresented: $showsRaw) {
            MacRawMetadataSheet(name: info.metadata?.originalFilename ?? "", entries: rawEntries, unavailable: rawUnavailable)
        }
    }

    private func fileURL(_ info: PhotoInfoQueries.Info) -> URL? {
        guard let source = info.fileSourceId, let path = info.filePath else { return nil }
        return dependencies.folderRoots.fileURL(sourceId: source, relativePath: path)
    }

    /// Every field the file carries, read when asked (a Photos original is
    /// read only if it is on this Mac).
    private func showRaw(_ info: PhotoInfoQueries.Info) {
        guard let id = loadedId else { return }
        rawEntries = nil
        showsRaw = true
        let url = fileURL(info)
        // A folder photo whose drive is not connected: no file to read, and
        // it is not in Photos either.
        if url == nil, info.fileSourceId != nil, !info.isInPhotos {
            rawUnavailable = String(localized: "The drive this photo is on isn’t connected.", comment: "Mac raw metadata: source offline")
            rawEntries = []
            return
        }
        rawUnavailable = nil
        Task {
            var properties: [String: Any]?
            if let url {
                properties = await MacRawMetadata.properties(of: url)
            } else {
                #if DEBUG
                if MacDemoLibrary.isOn, let demo = await Task.detached(operation: { MacDemoLibrary.pictureFiles(for: [id]).first }).value {
                    properties = await MacRawMetadata.properties(of: demo)
                }
                #endif
                if properties == nil { properties = await MacRawMetadata.properties(ofAsset: id) }
            }
            guard loadedId == id else { return }
            rawEntries = properties.map(MacRawMetadata.entries) ?? []
        }
    }

    private func exifCell(_ row: (String, String)) -> some View {
        Group {
            Text(row.0).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(row.1).font(.system(size: 12)).monospacedDigit().textSelection(.enabled)
        }
    }

    private func servers(_ info: PhotoInfoQueries.Info) -> some View {
        DisclosureGroup(isExpanded: $showsServers) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(info.serverCopies.enumerated()), id: \.offset) { _, copy in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(copy.serverName).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 74, alignment: .leading)
                        Text(copy.path).font(.system(size: 12)).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Text("On Server", comment: "Mac Get Info: section").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).frame(width: 80, alignment: .trailing)
    }

    // MARK: Saving

    private var canWritePhotos: Bool {
        #if DEBUG
        if MacDemoLibrary.isOn { return true }
        #endif
        return dependencies.captionKeywords != nil
    }

    private var editor: MacKeywordEditor {
        MacKeywordEditor(database: dependencies.database, captionKeywords: dependencies.captionKeywords,
                         sidecarQueue: dependencies.sidecarQueue, filterSuggestions: dependencies.filterSuggestions)
    }

    /// Saves as you type: each field's last keystroke wins, a moment after
    /// it; a field back at its saved text has nothing to save.
    private func scheduleSave(_ field: Field, text: String, _ id: String,
                              _ write: @escaping @MainActor (MacKeywordEditor) async -> MacKeywordEditor.Outcome) {
        if text == lastSaved[field] {
            pendingWrites[field] = nil
        } else {
            let editor = editor
            pendingWrites[field] = {
                lastSaved[field] = text
                report(await write(editor), id: id, quiet: true)
            }
        }
        pendingSave?.cancel()
        guard !pendingWrites.isEmpty else { return }
        pendingSave = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            flushSave()
        }
    }

    /// Every waiting write, now and in order after the ones already running.
    private func flushSave() {
        pendingSave?.cancel()
        pendingSave = nil
        let writes = Array(pendingWrites.values)
        pendingWrites = [:]
        guard !writes.isEmpty else { return }
        saveState = .saving
        let previous = lastWrite
        lastWrite = Task {
            await previous?.value
            for write in writes { await write() }
        }
    }

    /// A keyword typed but not returned goes in when the photo is left.
    private func commitKeyword(for id: String) {
        let text = keywordText
        guard !KeywordInput.split(text).isEmpty else { return }
        keywordText = ""
        let suggestions = dependencies.filterSuggestions, editor = editor
        Task {
            let catalog = await suggestions.load().keywords
            var outcome = MacKeywordEditor.Outcome.done
            for keyword in KeywordInput.keywords(from: text, existing: KeywordInput.spellings(catalog)) {
                outcome = outcome.combined(with: await editor.add(keyword, to: [id]))
            }
            report(outcome, id: id)
        }
    }

    /// After an Adjust…: the panel reads again, and a new date re-sorts the
    /// library.
    private func adjusted(_ id: String, _ outcome: MacAdjustWriter.Outcome, reloadsLibrary: Bool) {
        adjusting = false
        switch outcome {
        case .done:
            menu.marksChanged([id])
            if reloadsLibrary { dependencies.library?.reload() }
        case .failed(let reason):
            menu.failure = reason
        }
    }

    private func edit(_ write: @escaping @MainActor (MacKeywordEditor) async -> MacKeywordEditor.Outcome) {
        guard let photoId else { return }
        let editor = editor
        Task { report(await write(editor), id: photoId) }
    }

    /// `quiet`: a save while typing says a problem once, not per pause.
    private func report(_ outcome: MacKeywordEditor.Outcome, id: String, quiet: Bool = false) {
        menu.marksChanged([id])
        if id == loadedId { saveState = outcome == .done ? .saved : .failed }
        if quiet, menu.failure != nil { return }
        switch outcome {
        case .done: break
        case .skipped:
            menu.failure = String(localized: "Photos didn’t take the change — it may not allow changes to this photo.", comment: "Mac Get Info: a Photos write skipped")
        case .failed:
            menu.failure = String(localized: "The change couldn’t be saved.", comment: "Mac Get Info: a write failed")
        }
    }
}

/// A label column of 80 and the field taking the rest (board).
struct MacInfoRow<Content: View>: View {
    var alignment: VerticalAlignment = .firstTextBaseline
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: alignment, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The 56pt picture at the top of Get Info.
struct MacInfoThumbnail: View {
    let id: String
    var picture: ((String) -> CGImage?)?
    let photoLibrary: PhotoLibraryService
    @State private var image: CGImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 6).fill(MacTheme.fill2)
            .overlay { if let image { Image(decorative: image, scale: 2).resizable().scaledToFill() } }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(width: 56, height: 56)
            .accessibilityHidden(true)
            .task(id: id) {
                image = nil
                if let picture { image = picture(id); return }
                let wanted = id
                guard let asset = await Task.detached(priority: .userInitiated, operation: { PhotoLibraryService.fetchAssets(ids: [wanted]).first }).value
                else { return }
                _ = photoLibrary.requestThumbnail(for: asset, targetSize: CGSize(width: 112, height: 112), allowNetwork: false) { result, _ in
                    if wanted == id, let cg = result?.cgImage { image = cg }
                }
            }
    }
}

/// Get Info's words, out of the view.
enum MacInfoText {
    /// "Sony A7 IV · FE 24-70mm F2.8 GM II".
    static func gear(_ metadata: PhotoMetadata?) -> String? {
        let parts = [metadata?.normalizedCameraModel ?? metadata?.cameraModel, metadata?.normalizedLensModel ?? metadata?.lensModel]
            .compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "35 mm · f/2.8 · 1/250 s · ISO 400 · 48.2 MB".
    static func exposure(_ metadata: PhotoMetadata?) -> String? {
        guard let metadata else { return nil }
        var parts: [String] = []
        if let focal = metadata.focalLength, focal.isFinite { parts.append("\(Int(focal.rounded())) mm") }
        if let aperture = metadata.aperture { parts.append("f/" + aperture.formatted(.number.precision(.fractionLength(0...1)))) }
        if let shutter = metadata.shutterSpeedDisplay { parts.append("\(shutter) s") }
        if let iso = metadata.iso { parts.append("ISO \(iso)") }
        if let size = metadata.fileSize { parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func exifRows(_ metadata: PhotoMetadata?) -> [(String, String)] {
        guard let metadata else { return [] }
        var rows: [(String, String)] = []
        if let make = metadata.cameraManufacturer { rows.append((String(localized: "Make", comment: "Mac Get Info: EXIF"), make)) }
        if let model = metadata.cameraModel { rows.append((String(localized: "Model", comment: "Mac Get Info: EXIF"), model)) }
        if let shutter = metadata.shutterSpeedDisplay { rows.append((String(localized: "Exposure", comment: "Mac Get Info: EXIF"), "\(shutter) s")) }
        if let aperture = metadata.aperture {
            rows.append((String(localized: "Aperture", comment: "Mac Get Info: EXIF"), "f/" + aperture.formatted(.number.precision(.fractionLength(0...1)))))
        }
        if let iso = metadata.iso { rows.append((String(localized: "ISO", comment: "Mac Get Info: EXIF"), "\(iso)")) }
        if let focal = metadata.focalLength, focal.isFinite {
            let equivalent = metadata.equivalentFocalLength.flatMap { $0.isFinite ? " (\(Int($0.rounded())) mm)" : nil } ?? ""
            rows.append((String(localized: "Focal Length", comment: "Mac Get Info: EXIF"), "\(Int(focal.rounded())) mm" + equivalent))
        }
        if let lens = metadata.lensModel { rows.append((String(localized: "Lens", comment: "Mac Get Info: EXIF"), lens)) }
        if let width = metadata.width, let height = metadata.height {
            rows.append((String(localized: "Size", comment: "Mac Get Info: EXIF, pixel dimensions"), "\(width) × \(height)"))
        }
        return rows
    }

    struct Place { let name: String?; let coordinates: String? }

    static func coordinate(_ info: PhotoInfoQueries.Info) -> CLLocationCoordinate2D? {
        guard let latitude = info.metadata?.latitude, let longitude = info.metadata?.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func place(_ info: PhotoInfoQueries.Info) -> Place? {
        let name = info.place?.address ?? [info.place?.name, info.place?.locality, info.place?.country]
            .compactMap { $0 }.joined(separator: ", ").nilIfEmpty
        var coordinates: String?
        if let latitude = info.metadata?.latitude, let longitude = info.metadata?.longitude {
            coordinates = String(format: "%.4f° %@, %.4f° %@", abs(latitude), latitude >= 0 ? "N" : "S", abs(longitude), longitude >= 0 ? "E" : "W")
        }
        guard name != nil || coordinates != nil else { return nil }
        return Place(name: name, coordinates: coordinates)
    }

    /// Where a change goes (FS-18.02 §8).
    static func saveNote(_ info: PhotoInfoQueries.Info) -> String {
        if let file = info.fileName {
            let sidecar = ((file as NSString).deletingPathExtension as NSString).appendingPathExtension("xmp") ?? file
            return String(localized: "Saved as you type to \(sidecar) next to the file. The image file itself is never edited.",
                          comment: "Mac Get Info: where a folder photo's changes go")
        }
        return String(localized: "Saved as you type: caption and keywords to Photos, creator and copyright in ShotDex.",
                      comment: "Mac Get Info: where a Photos photo's changes go")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Show All Raw Metadata: every field ImageIO reads from the file.
struct MacRawMetadataSheet: View {
    let name: String
    let entries: [MacRawMetadata.Entry]?
    var unavailable: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(name).font(.headline).lineLimit(1).truncationMode(.middle)
            Group {
                if let entries, entries.isEmpty {
                    Text(unavailable ?? String(localized: "This file’s metadata can’t be read here — it may be in iCloud only.",
                                               comment: "Mac raw metadata: nothing to show"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let entries {
                    Table(entries) {
                        TableColumn(String(localized: "Field", comment: "Mac raw metadata: column")) { Text($0.key).textSelection(.enabled) }
                        TableColumn(String(localized: "Value", comment: "Mac raw metadata: column")) { Text($0.value).textSelection(.enabled) }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minHeight: 300)
            HStack {
                Spacer()
                Button(String(localized: "Done", comment: "Mac raw metadata: close")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 520, height: 460)
    }
}

extension MacRawMetadata.Entry: Identifiable {
    var id: String { key }
}
