import AppKit
import SwiftUI
import Observation

/// Memory cards on the Mac (FS-20 §4, board `MAC_Ingest`): the cards
/// ShotDex remembers, which of them are plugged in, and each card's import.
/// A card is picked once (File › Import from Card…); after that it shows in
/// the sidebar's Sources whenever its volume mounts — read on mount and
/// unmount, not on a timer.
@MainActor
@Observable
final class MacIngestCards {
    let store: CardStore
    let center = IngestCenter()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(defaults: UserDefaults = .standard) {
        store = CardStore(defaults: defaults)
        store.refresh()
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        // A card pulled out while ShotDex was in the back.
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
    }

    /// Plugged in, in the order they were picked (newest first).
    var connected: [RememberedCard] { store.connectedCards }

    func card(_ id: String) -> RememberedCard? { store.remembered.first { $0.id == id } }
    func root(_ id: String) -> URL? { store.connected[id] }

    /// The card's import, made the first time its page opens and kept while
    /// it runs (FS-20 §7: leaving the page never stops it).
    /// Called from the page's task, never from a view's body (it adds to
    /// observed state).
    @discardableResult
    func model(_ id: String, dependencies: MacDependencies) -> IngestModel? {
        guard let card = card(id), let root = root(id) else { return center.models[id] }
        let isNew = center.models[id] == nil
        let model = center.model(for: card, root: root, dependencies: dependencies)
        if isNew { model.onFinish = { [weak self] in self?.finished($0, $1) } }
        return model
    }

    /// A run ended (FS-20 §7–8), whether or not its page is open: After
    /// Import › Eject lets the card go once every copy is verified; a card
    /// pulled out mid-run takes its page with it, the ending said once.
    private func finished(_ model: IngestModel, _ summary: IngestSummary) {
        let id = model.card.id
        guard root(id) != nil, (try? model.root.checkResourceIsReachable()) == true else {
            if let line = model.endingMessage { NotificationCenter.default.post(name: .macToast, object: line) }
            refresh()
            return
        }
        // A run that ended short — stopped, a drive full or gone, photos that
        // failed — is said wherever the user is: Activity and the sidebar foot,
        // where they watched it, are gone with it.
        if summary.ending != .finished || !summary.failed.isEmpty || summary.backupIncomplete, let line = model.endingMessage {
            NotificationCenter.default.post(name: .macToast, object: line)
        }
        guard model.settings.ejectsAfterImport, summary.canEject(backupEnabled: model.settings.backsUp), canEject(id) else { return }
        Task {
            let ejected = await eject(id)
            let line = ejected
                ? IngestCopy.finishedBanner(count: summary.imported.count, card: model.card.name, ejected: true, canRemove: false)
                : String(localized: "\(model.card.name) couldn't be ejected. Close any app using it and try again.",
                         comment: "Mac Import from Card: Eject failed")
            NotificationCenter.default.post(name: .macToast, object: line)
        }
    }

    func refresh() {
        store.refresh()
        // A card that went with nothing running: its page and state go too.
        for id in center.models.keys where store.connected[id] == nil { center.forget(id) }
    }

    /// File › Import from Card…: the card's folder — the volume, or its DCIM.
    /// The panel runs on its own (`begin`), not modally: the window keeps
    /// drawing while it is up.
    func choose(_ chosen: @escaping @MainActor (RememberedCard) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        panel.prompt = String(localized: "Choose Card", comment: "Mac Import from Card: the open panel's button")
        panel.message = String(localized: "Choose the memory card, or its DCIM folder. ShotDex remembers it and lists it in Sources whenever it is plugged in.",
                               comment: "Mac Import from Card: the open panel's message")
        panel.begin { [weak self] response in
            MainActor.assumeIsolated {
                guard response == .OK, let url = panel.url, let self, let card = try? self.store.remember(url) else { return }
                // Another folder on the same volume is the same card id: its old page goes.
                self.center.forget(card.id)
                chosen(card)
            }
        }
    }

    /// A card on a volume of its own can be ejected; a folder on this Mac can't.
    func canEject(_ id: String) -> Bool {
        guard let root = root(id),
              let values = try? root.resourceValues(forKeys: [.volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey])
        else { return false }
        return values.volumeIsInternal == false && (values.volumeIsEjectable == true || values.volumeIsRemovable == true)
    }

    /// Eject (board `MAC_Ingest`'s header): the volume the card is on.
    /// Off the main actor — a busy disk can take seconds to let go.
    func eject(_ id: String) async -> Bool {
        // Never while any import reads: two cards can share a volume.
        guard canEject(id), center.running == nil, let root = root(id),
              let volume = (try? root.resourceValues(forKeys: [.volumeURLKey]))?.volume else { return false }
        // The background hash would hold the card open: it stops first.
        center.models[id]?.cancelHashPass()
        try? await Task.sleep(for: .milliseconds(200))
        let ejected = await Task.detached(priority: .userInitiated) {
            (try? NSWorkspace.shared.unmountAndEjectDevice(at: volume)) != nil
        }.value
        refresh()
        return ejected
    }
}

extension MacDependencies: IngestEnvironment {
    func readImportedSource(_ sourceId: String) async { await sourcesModel.read(sourceId: sourceId) }
    /// The Mac's banner is the window's toast.
    func announceImport(_ text: String) { NotificationCenter.default.post(name: .macToast, object: text) }
}

extension Notification.Name {
    /// File › Import from Card… (FS-20 §4).
    static let macImportFromCard = Notification.Name("ShotDexMacImportFromCard")
}

/// The window's side of cards (FS-20 §4): File › Import from Card… picks
/// one and opens its page; a card pulled out with nothing running takes
/// its page with it, back to All Photos.
struct MacIngestHost: ViewModifier {
    @Binding var selection: MacSidebarItem?
    @Environment(MacDependencies.self) private var dependencies

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .macImportFromCard)) { _ in
                dependencies.cards.choose { selection = .card($0.id) }
            }
            .onChange(of: dependencies.cards.store.connected) { leaveIfGone() }
            // A card pulled out mid-run: its page goes once the run has ended.
            .onChange(of: dependencies.cards.center.running == nil) { leaveIfGone() }
    }

    private func leaveIfGone() {
        guard case .card(let id) = selection, dependencies.cards.root(id) == nil,
              dependencies.cards.center.models[id]?.isRunning != true else { return }
        selection = .allPhotos
    }
}
