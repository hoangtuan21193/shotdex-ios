import GRDB
import Photos
import SwiftUI

/// What the On Server place shows, read off the main actor in one go
/// (FS-15.02 §8, FS-19.07 §11).
struct MacOnServerSnapshot: Sendable {
    /// Where uploads went, newest first, photos still in the library only.
    var destinations: [UploadDestination] = []
    /// Photos items on any server: uploaded from here, or found on a server source.
    var everyPhotoIds: [String] = []
    /// Photos whose every original is verified on a server: Free Up Space.
    var deletable: [String] = []
    var deletableBytes: Int64 = 0
    /// Each destination's newest upload, for Last Upload.
    var lastUpload: [String: Date] = [:]
    var serverCount = 0
    /// Each photo's format as the grid labels it (HEIC, RAW, JPG).
    var formats: [String: String] = [:]
}

/// The On Server place (board `MAC_ServerUpload`): what can leave this Mac,
/// where every upload went, and the photos of the place picked in the table.
struct MacOnServerScreen: View {
    let menu: MacPhotoMenu?
    var picture: ((String) -> CGImage?)?

    @Environment(MacDependencies.self) private var dependencies
    @State private var snapshot: MacOnServerSnapshot?
    /// The row picked in Where They Are: a destination's id, or nil for every photo on any server.
    @State private var picked: String?
    @State private var isConfirmingFreeUp = false
    @State private var keepingSources: [String] = []
    /// The photos the question was asked about: what Continue checks again.
    @State private var askedIds: [String] = []
    /// Free Up Space is reading or re-checking: one at a time, the button off.
    @State private var isPreparing = false
    /// Why Free Up Space did nothing, said rather than beeped.
    @State private var notice: String?
    /// Each uploaded photo's files as PhotoKit lists them, kept between
    /// reads: a new upload batch asks PhotoKit about its own photos only.
    @State private var entryCache: [String: AssetUploadEntry] = [:]

    static let everyPhotoRow = "every"
    static let gridLimit = 600
    /// The table's row and header height (board).
    static let tableRow: CGFloat = 32

    var body: some View {
        Group {
            if let snapshot {
                if snapshot.destinations.isEmpty && snapshot.everyPhotoIds.isEmpty {
                    ContentUnavailableView(String(localized: "Nothing on a Server Yet", comment: "Mac On Server: empty"),
                                           systemImage: "externaldrive.connected.to.line.below",
                                           description: Text("Select photos and choose File › Upload to Server… to copy their originals to a NAS or a computer.",
                                                             comment: "Mac On Server: how to fill it"))
                } else {
                    content(snapshot)
                }
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(MacTheme.content)
        .navigationTitle(String(localized: "On Server", comment: "Mac On Server title"))
        .navigationSubtitle(subtitle)
        // Again after an upload or a deletion: the history and the library both move.
        // Again after an upload (the index's version) or a deletion, Free Up Space's too (the library's last removal).
        .task(id: "\(dependencies.serverUploadIndex.version)-\(dependencies.library?.lastRemoval?.token ?? 0)") {
            // An upload bumps the index once per batch: one read after the batches settle.
            try? await Task.sleep(for: .milliseconds(snapshot == nil ? 0 : 1_500))
            guard !Task.isCancelled else { return }
            await load()
        }
        .alert(String(AttributedString(localized: "Remove ^[\(askedIds.count) photo](inflect: true) from This Mac?",
                                       comment: "Mac On Server: confirm Free Up Space").characters),
               isPresented: $isConfirmingFreeUp) {
            Button(String(localized: "Continue", comment: "Mac On Server: go on to the deletion"), role: .destructive) {
                freeUpSpace(askedIds)
            }
            Button(String(localized: "Cancel", comment: "Mac On Server: keep the photos"), role: .cancel) {}
        } message: {
            Text(FreeUpSpaceNote.message(
                String(localized: "Each one has every original verified on a server, and the copies on your servers are not changed. Photos items move to Recently Deleted (and leave your other devices if iCloud Photos is on); files in folders on this Mac go to the Trash.",
                       comment: "Mac On Server: what Free Up Space deletes"),
                keepingSources: keepingSources))
        }
        .alert(String(localized: "Nothing Was Removed", comment: "Mac On Server: Free Up Space did nothing"),
               isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button(String(localized: "OK", comment: "Mac On Server: dismiss"), role: .cancel) {}
        } message: {
            Text(notice ?? "")
        }
    }

    private var subtitle: String {
        guard let snapshot else { return "" }
        let photos = AttributedString(localized: "^[\(snapshot.everyPhotoIds.count) photo](inflect: true)", comment: "Mac On Server subtitle: photos on any server")
        let servers = AttributedString(localized: "^[\(snapshot.serverCount) server](inflect: true)", comment: "Mac On Server subtitle: servers they went to")
        return String(photos.characters) + " · " + String(servers.characters)
    }

    @ViewBuilder
    private func content(_ snapshot: MacOnServerSnapshot) -> some View {
        let all = photos(in: snapshot)
        // A page of the newest: the whole set can be 55k, and the library grid has the rest.
        let ids = Array(all.prefix(Self.gridLimit))
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                freeUpSpace(snapshot)
                whereTheyAre(snapshot)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(pickedTitle(snapshot)).font(.system(size: 15, weight: .semibold))
                        if let server = pickedServer(snapshot) { Text(server).font(.system(size: 13)).foregroundStyle(.secondary) }
                    }
                    if all.count > ids.count {
                        Text("The newest \(ids.count.formatted()) of \(all.count.formatted()). The library's On Server filter shows them all.",
                             comment: "Mac On Server: the grid shows a page")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    // Edge to edge, 2 apart, as the library grid (board).
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 2)], spacing: 2) {
                        ForEach(ids, id: \.self) { id in
                            MacOnServerTile(id: id, format: snapshot.formats[id], picture: picture)
                        }
                    }

                }
            }
            .padding(16)
        }
    }

    // MARK: Free Up Space

    private func freeUpSpace(_ snapshot: MacOnServerSnapshot) -> some View {
        HStack(spacing: 12) {
            // Red: the card's one command deletes from Photos (board).
            Image(systemName: "trash").font(.system(size: 16)).foregroundStyle(MacTheme.redText)
            VStack(alignment: .leading, spacing: 2) {
                Text("Free Up Space", comment: "Mac On Server: the header card's title").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MacTheme.redText)
                Text(snapshot.deletable.isEmpty
                     ? String(localized: "Nothing to remove: a photo can leave this Mac once every original of it is verified on a server.",
                              comment: "Mac On Server: nothing can leave this Mac")
                     : String(AttributedString(localized: "^[\(snapshot.deletable.count) photo](inflect: true) · ~\(ByteCountFormatter.string(fromByteCount: snapshot.deletableBytes, countStyle: .file)) safely on a server, can leave this Mac",
                                               comment: "Mac On Server: what Free Up Space would remove").characters))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                // Why the card's count is below the table's: the rest are not safe to remove (yet).
                let rest = snapshot.everyPhotoIds.count - snapshot.deletable.count
                if rest > 0, !snapshot.deletable.isEmpty {
                    Text(String(AttributedString(localized: "^[\(rest) more photo](inflect: true) on a server can't leave yet — not every original was uploaded from here. Applies to every server.",
                                                 comment: "Mac On Server: photos on a server that Free Up Space leaves").characters))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            // Not the prominent style: it starts a deletion (01 §3).
            Button {
                let store = dependencies.serverUploads
                let ids = snapshot.deletable
                isPreparing = true
                Task {
                    keepingSources = await Task.detached(priority: .userInitiated) { (try? store.keepingSources(assetIds: ids)) ?? [] }.value
                    isPreparing = false
                    askedIds = ids
                    isConfirmingFreeUp = true
                }
            } label: {
                Text("Free Up Space…", comment: "Mac On Server: delete the photos that are safe on a server")
                    .foregroundStyle(snapshot.deletable.isEmpty ? Color.secondary : MacTheme.redText)
            }
            .buttonStyle(MacPushButtonStyle(isDefault: false))
            .disabled(snapshot.deletable.isEmpty || menu == nil || isPreparing)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .background(MacTheme.fill, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(MacTheme.separator))
    }

    // MARK: Where They Are

    private func whereTheyAre(_ snapshot: MacOnServerSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where They Are", comment: "Mac On Server: the table of destinations").font(.system(size: 15, weight: .semibold))
            Table(rows(snapshot), selection: Binding(get: { picked ?? Self.everyPhotoRow },
                                                     set: { picked = $0 == Self.everyPhotoRow ? nil : $0 })) {
                TableColumn(String(localized: "Server", comment: "Mac On Server column")) { row in
                    Text(row.server).fontWeight(row.id == Self.everyPhotoRow ? .semibold : .regular)
                }
                    .width(min: 120, ideal: 180)
                TableColumn(String(localized: "Folder", comment: "Mac On Server column")) { row in
                    Text(row.folder).foregroundStyle(row.id == Self.everyPhotoRow ? .secondary : .primary)
                        .lineLimit(1).truncationMode(.head)
                }
                .width(min: 160, ideal: 420)
                TableColumn(String(localized: "Photos", comment: "Mac On Server column")) { row in
                    Text(row.count, format: .number).monospacedDigit()
                }
                .width(min: 60, ideal: 80)
                TableColumn(String(localized: "Last Upload", comment: "Mac On Server column")) { row in
                    Text(row.last.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "").foregroundStyle(.secondary)
                }
                .width(min: 100, ideal: 140)
            }
            .font(.system(size: 13))
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .frame(height: CGFloat(min(rows(snapshot).count, 6) + 1) * Self.tableRow + 8)
        }
    }

    private struct Row: Identifiable, Hashable {
        let id: String
        let server: String
        let folder: String
        let count: Int
        let last: Date?
    }

    private func rows(_ snapshot: MacOnServerSnapshot) -> [Row] {
        snapshot.destinations.map {
            Row(id: $0.id, server: $0.connectionName, folder: $0.folder.isEmpty ? "/" : $0.folder,
                count: $0.assetIds.count, last: snapshot.lastUpload[$0.id])
        } + [Row(id: Self.everyPhotoRow, server: String(localized: "All Uploaded Photos", comment: "Mac On Server: the table's last row"),
                 folder: String(localized: "Every photo on any server", comment: "Mac On Server: the table's last row"),
                 count: snapshot.everyPhotoIds.count, last: nil)]
    }

    private func photos(in snapshot: MacOnServerSnapshot) -> [String] {
        guard let picked, let destination = snapshot.destinations.first(where: { $0.id == picked }) else { return snapshot.everyPhotoIds }
        return destination.assetIds
    }

    private func pickedTitle(_ snapshot: MacOnServerSnapshot) -> String {
        guard let picked, let destination = snapshot.destinations.first(where: { $0.id == picked }) else {
            return String(localized: "All Uploaded Photos", comment: "Mac On Server: grid title, as the table's last row")
        }
        return destination.folder.isEmpty ? "/" : destination.folder
    }

    private func pickedServer(_ snapshot: MacOnServerSnapshot) -> String? {
        guard let picked else { return nil }
        return snapshot.destinations.first { $0.id == picked }?.connectionName
    }

    // MARK: Free Up Space

    /// Each photo's files as an upload lists them: out of Photos, or the demo's drawn JPEGs.
    @MainActor
    private static func entries(_ dependencies: MacDependencies) -> @Sendable ([String]) async -> [AssetUploadEntry] {
        #if DEBUG
        if MacDemoLibrary.isOn { return MacDemoUpload.entries(dependencies: dependencies) }
        #endif
        return { ids in await Task.detached(priority: .utility) { PhotoKitOriginalExporter.entries(for: ids) }.value }
    }

    /// Continue: the photos asked about, checked again now — a RAW added
    /// or a history row gone since the place was read drops a photo — and
    /// only those go to the window's delete flow (FS-19.04).
    private func freeUpSpace(_ ids: [String]) {
        #if DEBUG
        // The demo's photos are rows, not Photos assets: nothing is deleted.
        if MacDemoLibrary.isOn { NSSound.beep(); return }
        #endif
        guard let menu, !ids.isEmpty else { return }
        isPreparing = true
        let store = dependencies.serverUploads
        let listEntries = Self.entries(dependencies)
        Task {
            let entries = await listEntries(ids)
            let safe = await Task.detached(priority: .userInitiated) { () -> [String] in
                let keys = (try? store.uploadedFileKeys(assetIds: entries.map(\.assetId))) ?? [:]
                return ServerUploadEligibility.evaluate(assets: entries.map { ($0.assetId, $0.files) }, uploadedKeys: keys).deletable
            }.value
            isPreparing = false
            guard !safe.isEmpty else {
                notice = String(localized: "None of these photos is still verified on a server. Upload them again, then free up space.",
                                comment: "Mac On Server: the re-check found nothing safe")
                return
            }
            // The window's delete flow asks the last question; the place reads again when photos leave the library.
            menu.moveToTrash(safe)
        }
    }

    // MARK: Loading

    private func load() async {
        let store = dependencies.serverUploads
        let presence = OnServerProgressQueries(database: dependencies.database)
        let database = dependencies.database
        let listEntries = Self.entries(dependencies)
        let read = await Task.detached(priority: .userInitiated) { () -> (MacOnServerSnapshot, [String]) in
            // The whole library, newest first — not the grid the window last showed, which may be filtered.
            let rows = (try? database.reader.read { db in
                try GRDB.Row.fetchAll(db, sql: "SELECT assetId, originalFilename FROM photo_metadata ORDER BY creationDate DESC")
                    .map { (assetId: $0["assetId"] as String, originalFilename: $0["originalFilename"] as String?) }
            }) ?? []
            let library = Set(rows.map(\.assetId))
            let uploadRows = ((try? store.destinationRows()) ?? []).filter { library.contains($0.assetId) }
            var snapshot = MacOnServerSnapshot()
            snapshot.destinations = UploadDestinations.group(uploadRows)
            for row in uploadRows {
                // The same key `UploadDestination.id` is made of.
                let key = "\(row.connectionName)\u{1F}\(ServerUploadPath.parent(of: ServerUploadPath.normalizedFolder(row.remotePath)))"
                let date = Date(timeIntervalSince1970: TimeInterval(row.uploadedAt))
                if date > snapshot.lastUpload[key] ?? .distantPast { snapshot.lastUpload[key] = date }
            }
            let uploaded = Set(uploadRows.map(\.assetId))
            let present = ((try? presence.presentAnywhere()) ?? []).intersection(library)
            let every = uploaded.union(present)
            snapshot.everyPhotoIds = rows.map(\.assetId).filter { every.contains($0) }
            snapshot.serverCount = Set(uploadRows.map(\.connectionName)).count
            for row in rows where every.contains(row.assetId) {
                snapshot.formats[row.assetId] = MacOnServerTile.format(of: row.originalFilename)
            }
            return (snapshot, Array(uploaded))
        }.value
        guard !Task.isCancelled else { return }
        var snapshot = read.0
        let missing = read.1.filter { entryCache[$0] == nil }
        if !missing.isEmpty {
            for entry in await listEntries(missing) { entryCache[entry.assetId] = entry }
            guard !Task.isCancelled else { return }
        }
        let entries = read.1.compactMap { entryCache[$0] }
        let verdict = await Task.detached(priority: .utility) { () -> (ServerUploadEligibility.Verdict, Int64) in
            let keys = (try? store.uploadedFileKeys(assetIds: entries.map(\.assetId))) ?? [:]
            let verdict = ServerUploadEligibility.evaluate(assets: entries.map { ($0.assetId, $0.files) }, uploadedKeys: keys)
            let safe = Set(verdict.deletable)
            let bytes = entries.filter { safe.contains($0.assetId) }.flatMap(\.files).reduce(Int64(0)) { $0 + $1.estimatedBytes }
            return (verdict, bytes)
        }.value
        guard !Task.isCancelled else { return }
        snapshot.deletable = verdict.0.deletable
        snapshot.deletableBytes = verdict.1
        self.snapshot = snapshot
        if let picked, !snapshot.destinations.contains(where: { $0.id == picked }) { self.picked = nil }
    }
}

/// One photo in the On Server grid: its picture, its format, "On Server".
struct MacOnServerTile: View {
    let id: String
    let format: String?
    var picture: ((String) -> CGImage?)?
    @Environment(MacDependencies.self) private var dependencies
    @State private var image: CGImage?
    @State private var isCloud = false

    var body: some View {
        Rectangle().fill(MacTheme.fill2)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image { Image(decorative: image, scale: 2).resizable().scaledToFill() }
                else if isCloud { Image(systemName: "icloud.and.arrow.down").foregroundStyle(.secondary) }
            }
            .clipped()
            .overlay(alignment: .topLeading) {
                if let format {
                    Text(format).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 5).frame(height: 16)
                        .background(MacTheme.hudFill, in: RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomLeading) {
                Label(String(localized: "On Server", comment: "Mac On Server tile: the photo's state"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).frame(height: 18)
                    .background(MacTheme.hudFill, in: Capsule())
                    .padding(6)
            }
            .task(id: id) {
                // The asset off the main actor; a tile only scrolled past asks for nothing.
                try? await Task.sleep(for: .milliseconds(60))
                guard !Task.isCancelled else { return }
                let found = picture == nil
                    ? await Task.detached(priority: .utility) { PhotoLibraryService.fetchAssets(ids: [id]).first }.value
                    : nil
                await MacThumbnail.load(id, side: 180, picture: picture, asset: { _ in found }, dependencies: dependencies,
                                        received: { image = $0 }, inCloud: { isCloud = true })
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "Photo, On Server", comment: "Mac On Server tile"))
    }

    /// `RAW`, `HEIC`, `JPG`, `MOV` from the file name, as the library grid labels it.
    nonisolated static func format(of filename: String?) -> String? {
        guard let ext = filename.map({ ($0 as NSString).pathExtension.uppercased() }), !ext.isEmpty else { return nil }
        switch ext {
        case "ARW", "CR2", "CR3", "NEF", "RAF", "DNG", "ORF", "RW2": return "RAW"
        case "JPEG": return "JPG"
        default: return ext
        }
    }
}
