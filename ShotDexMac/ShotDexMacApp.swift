import SwiftUI

/// ShotDex for Mac (FS-18): one Library window — sidebar, toolbar, content.
@main
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
        .commands { MacBackupCommands() }
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
