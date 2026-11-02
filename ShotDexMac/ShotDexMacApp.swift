import SwiftUI

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
    @State private var dependencies: MacDependencies = {
        #if DEBUG
        if MacDemoLibrary.isOn { return MacDemoLibrary.dependencies() }
        #endif
        return MacDependencies.live()
    }()

    init() {
        #if DEBUG
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
        WindowGroup {
            MacRootWindow()
                .environment(dependencies)
                .frame(minWidth: MacWindowMetrics.minimumSize.width, minHeight: MacWindowMetrics.minimumSize.height)
        }
        .defaultSize(width: 1440, height: 900)
        .windowToolbarStyle(.unified)
        .commands {
            MacBackupCommands()
            MacCommonPhotosCommands()
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

/// File › New Backup… and Go › Backup ⌥⌘B (FS-22.06 §5.1, FS-18.01b).
struct MacBackupCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(String(localized: "New Smart Album…", comment: "Mac menu: File › New Smart Album…")) {
                NotificationCenter.default.post(name: .macNewSmartAlbum, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.option, .command])
            Button(String(localized: "New Backup…", comment: "Mac menu: File › New Backup…")) {
                NotificationCenter.default.post(name: .macNewBackup, object: nil)
            }
        }
        CommandMenu(String(localized: "Go", comment: "Mac menu bar: Go menu")) {
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
