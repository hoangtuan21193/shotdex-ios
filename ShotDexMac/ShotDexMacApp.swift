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
            MacFilterCommands()
        }
        // One window per common-photos run (FS-19.08 §7): not modal, and
        // closing it leaves the run going.
        WindowGroup(String(localized: "Common Photos", comment: "Mac window: a common-photos run"),
                    id: MacCommonPhotosRunWindow.id, for: String.self) { $runId in
            MacCommonPhotosRunWindow(runId: runId)
                .environment(dependencies)
                .onAppear { appDelegate.runs = dependencies.commonPhotos }
        }
        .defaultSize(width: MacCommonPhotosRunWindow.size.width, height: MacCommonPhotosRunWindow.size.height)
        .windowToolbarStyle(.unified)
        // Compare two copies of a Same photo (FS-19.08 §6d): one window, not
        // modal, tier D.
        Window(String(localized: "Compare", comment: "Mac window: two copies of a common photo"), id: MacCommonPhotosCompareWindow.id) {
            MacCommonPhotosCompareWindow()
                .environment(dependencies)
        }
        .defaultSize(width: MacCommonPhotosCompareWindow.size.width, height: MacCommonPhotosCompareWindow.size.height)
        // Window › Activity ⌥⌘0 (FS-18.01 §4): one window, never a sheet.
        Window(String(localized: "Activity", comment: "Mac window: long-running jobs"), id: MacActivityWindow.id) {
            MacActivityWindow()
                .environment(dependencies)
        }
        .defaultSize(width: MacActivityWindow.size.width, height: MacActivityWindow.size.height)
        // The scene's own Window-menu item carries no shortcut; MacActivityCommands
        // puts Activity ⌥⌘0 there instead (FS-18.01b).
        .commandsRemoved()
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

/// File › New Backup… and Go › Backup ⌥⌘B (FS-22.06 §5.1, FS-18.01b).
struct MacBackupCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            // File › sources (FS-18.01b §2): the keyboard's way to the sidebar's +.
            Divider()
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
        // Edit › Search ⌘F (FS-18.01b §2): the toolbar's search field.
        CommandGroup(after: .pasteboard) {
            Divider()
            Button(String(localized: "Search", comment: "Mac menu: Edit › Search")) {
                NotificationCenter.default.post(name: .macFocusSearchRequest, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
        }
        CommandMenu(String(localized: "Go", comment: "Mac menu bar: Go menu")) {
            // Go › All Photos ⌥⌘1 … Recently Added ⌥⌘5 (FS-18.01b §2).
            ForEach(Array(MacSidebarItem.library.enumerated()), id: \.offset) { index, item in
                Button(item.title) { NotificationCenter.default.post(name: .macGoTo, object: item) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.option, .command])
            }
            Divider()
            Button(String(localized: "Backup", comment: "Mac menu: Go › Backup")) {
                NotificationCenter.default.post(name: .macShowBackup, object: nil)
            }
            .keyboardShortcut("b", modifiers: [.option, .command])
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

/// Window › Activity ⌥⌘0 (FS-18.01b).
struct MacActivityCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(before: .windowArrangement) {
            Button(String(localized: "Activity", comment: "Mac menu: Window › Activity")) {
                openWindow(id: MacActivityWindow.id)
            }
            .keyboardShortcut("0", modifiers: [.option, .command])
        }
    }
}
