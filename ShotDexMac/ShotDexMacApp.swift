import SwiftUI
import UserNotifications

/// The executable's entry: the app, or with `--agent` the helper that runs
/// Backup after the app quits (FS-22.06 §2).
@main
enum ShotDexMacMain {
    static func main() {
        if CommandLine.arguments.contains(MacAgentLink.agentArgument) {
            MacAgent.run()
        }
        ShotDexMacApp.main()
    }
}

/// ShotDex for Mac (FS-18): one Library window — sidebar, toolbar, content.
struct ShotDexMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @State private var dependencies: MacDependencies = {
        #if DEBUG
        if MacDemoLibrary.isOn { return MacDemoLibrary.dependencies() }
        #endif
        return MacDependencies.live()
    }()

    init() {
        // Compare's downloads a crash left behind (FS-19.08 §6d). The app
        // only: the helper never shows Compare.
        CompareFileCache.sweepLeftovers()
        #if DEBUG
        MacHangWatchdog.start()
        MacSnapshot.scheduleIfAsked()
        // `-ShotDexAppearance dark|light`: the window's look for screenshots,
        // whatever System Settings says.
        if let index = CommandLine.arguments.firstIndex(of: "-ShotDexAppearance"), index + 1 < CommandLine.arguments.count {
            let name: NSAppearance.Name = CommandLine.arguments[index + 1] == "dark" ? .darkAqua : .aqua
            DispatchQueue.main.async { NSApplication.shared.appearance = NSAppearance(named: name) }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup(id: MacMainWindow.id) {
            MacRootWindow()
                .environment(dependencies)
                .onAppear {
                    appDelegate.runs = dependencies.commonPhotos
                    dependencies.startGatheringInApp()
                    // Which originals are on this Mac (FS-06.10 §4): a
                    // window on screen is the app in front.
                    dependencies.originalPresenceCheck.appBecameActive()
                }
                // The check runs in the app only — the helper never shows
                // this window — and keeps going behind other apps: it is off
                // the main thread and does not slow the UI (user 2026-11-04).
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    dependencies.originalPresenceCheck.appBecameActive()
                }
                .frame(minWidth: MacWindowMetrics.minimumSize.width, minHeight: MacWindowMetrics.minimumSize.height)
        }
        .defaultSize(width: 1440, height: 900)
        .windowToolbarStyle(.unified)
        .commands {
            MacBackupCommands()
            MacCommonPhotosCommands()
            MacActivityCommands()
            MacSupportCommands()
            MacFilterCommands()
            MacLibraryCommands()
            MacImageCommands()
            MacGoCommands()
        }
        Settings {
            MacSettingsWindow()
                .environment(dependencies)
        }
    }
}

/// The window's fixed numbers (FS-18 01 §1, `MAC_STYLE.md`).
enum MacWindowMetrics {
    static let minimumSize = CGSize(width: 1024, height: 700)
    static let sidebarWidth: CGFloat = 228
    static let inspectorWidth: CGFloat = 300
}

/// File › sources and New Backup…, View › as Grid/List, Edit › Search
/// (FS-22.06 §5.1, FS-18.01b); Image and Go are `MacLibraryCommands.swift`.
struct MacBackupCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            // File › sources (FS-18.01b §2): the keyboard's way to the sidebar's +.
            Divider()
            Button(String(localized: "Add Source…", comment: "Mac menu: File › Add Source… (the Add a Source sheet)")) {
                NotificationCenter.default.post(name: .macShowAddSource, object: nil)
            }
            Button(String(localized: "Add Folder…", comment: "Mac menu: File › Add Folder…")) {
                NotificationCenter.default.post(name: .macAddFolder, object: nil)
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            Button(String(localized: "Add Photos Library…", comment: "Mac menu: File › Add Photos Library…")) {
                NotificationCenter.default.post(name: .macAddPhotosLibrary, object: nil)
            }
            Button(String(localized: "Connect to Server…", comment: "Mac menu: File › Connect to Server…")) {
                NotificationCenter.default.post(name: .macAddServer, object: nil)
            }
            .keyboardShortcut("k", modifiers: .command)
            Divider()
            Button(String(localized: "New Smart Album…", comment: "Mac menu: File › New Smart Album…")) {
                NotificationCenter.default.post(name: .macNewSmartAlbum, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.option, .command])
            Button(String(localized: "New Backup…", comment: "Mac menu: File › New Backup…")) {
                NotificationCenter.default.post(name: .macNewBackup, object: nil)
            }
        }
        // View › as Grid ⌘1 · as List ⌘2 (FS-18.02 §3).
        CommandGroup(before: .toolbar) {
            Button(String(localized: "as Grid", comment: "Mac menu: View › as Grid")) {
                NotificationCenter.default.post(name: .macViewMode, object: "grid")
            }
            .keyboardShortcut("1", modifiers: .command)
            Button(String(localized: "as List", comment: "Mac menu: View › as List")) {
                NotificationCenter.default.post(name: .macViewMode, object: "list")
            }
            .keyboardShortcut("2", modifiers: .command)
            Divider()
        }
        // Edit › Search ⌘F (FS-18.01b §2): the toolbar's search field.
        CommandGroup(after: .pasteboard) {
            Divider()
            Button(String(localized: "Search", comment: "Mac menu: Edit › Search")) {
                NotificationCenter.default.post(name: .macFocusSearchRequest, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
        }
    }
}

/// File › Find Common Photos… ⇧⌘F (FS-19.08 §3): opens with the folders
/// picked in the front window's server browser, maybe none. Only a server
/// source has a browser, so a connection that is only an upload
/// destination has no way in.
struct MacCommonPhotosCommands: Commands {
    @FocusedValue(\.macServerBrowser) private var browser

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(String(localized: "Find Common Photos…", comment: "Mac: compare folders for the same photos (FS-19.08)")) {
                browser?.findCommonPhotosInSelection()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(browser == nil)
        }
    }
}

/// Quitting while a common-photos run goes (FS-19.08 §7): asks, then pauses
/// every run and quits once each has stopped between steps; Cancel keeps it going.
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    @MainActor weak var runs: MacCommonPhotosRuns? {
        didSet { notices.runs = runs }
    }
    /// Keep gathering's notice (FS-19.08 §6c): set before launch ends, so a
    /// click that launched the app still lands.
    @MainActor private let notices = MacCommonPhotosNotices()

    @MainActor
    func applicationWillFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = notices
        // A click the helper took (it posts the notices while ShotDex is
        // closed): the app opens on that run's window.
        MacAgentLink.observe(MacAgentLink.noticeClicked) { [notices] in
            if let runId = MacCommonPhotosNotices.takeHandedOver() { notices.received(runId: runId) }
        }
        if let runId = MacCommonPhotosNotices.takeHandedOver() { notices.received(runId: runId) }
    }

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let runs, runs.isAnyRunning else { return .terminateNow }
        #if DEBUG
        // `-ShotDexQuitPauses`: answer the question with Pause and Quit, as a test would.
        if ProcessInfo.processInfo.arguments.contains("-ShotDexQuitPauses") {
            runs.pauseAll { sender.reply(toApplicationShouldTerminate: true) }
            return .terminateLater
        }
        #endif
        let alert = NSAlert()
        alert.messageText = String(localized: "A common-photos run is going. Pause it and quit?",
                                   comment: "Mac quit with a common-photos run going")
        alert.informativeText = String(localized: "What is done stays done; Resume continues from there next time.",
                                       comment: "Mac quit with a common-photos run going: what Pause keeps")
        alert.addButton(withTitle: String(localized: "Pause and Quit", comment: "Mac quit: pause the run, then quit"))
        alert.addButton(withTitle: String(localized: "Cancel", comment: "Mac sheet: cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        runs.pauseAll { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}

/// Help › ShotDex Support… (FS-18.04 §6, FS-13).
struct MacSupportCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .help) {
            Button(String(localized: "ShotDex Support…", comment: "Mac menu: Help › ShotDex Support…")) {
                // A sheet on the Library window (no window of its own): that
                // window comes forward first, then the front one shows it.
                MacWindowRequest.showsSupport = true
                MacMainWindow.bringForward(openWindow)
                NotificationCenter.default.post(name: .macShowSupport, object: nil)
            }
        }
    }
}

/// Window › Activity ⌥⌘0 (FS-18.01b): the front window's Activity popover.
struct MacActivityCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(before: .windowArrangement) {
            Button(String(localized: "Activity", comment: "Mac menu: Window › Activity")) {
                // From Settings or another app's window too: the Library window comes forward
                // first, then its toolbar opens the popover (only the front one answers).
                MacWindowRequest.showsActivity = true
                MacMainWindow.bringForward(openWindow)
                NotificationCenter.default.post(name: .macShowActivity, object: nil)
            }
            .keyboardShortcut("0", modifiers: [.option, .command])
        }
    }
}
