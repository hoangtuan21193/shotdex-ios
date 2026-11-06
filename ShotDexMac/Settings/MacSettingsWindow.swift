import ServiceManagement
import SwiftUI

/// ShotDex › Settings… ⌘, (FS-18.04 §3, boards `MAC_Settings*`): six panes,
/// 720 wide and at most 640 tall, the body scrolling; changes apply at once.
struct MacSettingsWindow: View {
    @State private var pane = MacSettingsPane.initial

    var body: some View {
        TabView(selection: $pane) {
            ForEach(MacSettingsPane.allCases) { pane in
                Tab(pane.title, systemImage: pane.systemImage, value: pane) {
                    pane.content
                        .frame(width: MacSettingsPane.size.width, height: MacSettingsPane.size.height)
                }
            }
        }
        // Review Unknown Cameras in Sources › Index opens Cameras.
        .onReceive(NotificationCenter.default.publisher(for: .macSettingsShowPane)) { note in
            if let pane = (note.object as? String).flatMap(MacSettingsPane.init(rawValue:)) { self.pane = pane }
        }
    }
}

enum MacSettingsPane: String, CaseIterable, Identifiable {
    case general, ai, sources, editing, servers, cameras

    static let size = CGSize(width: 720, height: 640)

    var id: Self { self }

    var title: String {
        switch self {
        case .general: String(localized: "General", comment: "Mac Settings pane")
        case .ai: String(localized: "AI", comment: "Mac Settings pane")
        case .sources: String(localized: "Sources", comment: "Mac Settings pane")
        case .editing: String(localized: "Editing", comment: "Mac Settings pane")
        case .servers: String(localized: "Servers", comment: "Mac Settings pane")
        case .cameras: String(localized: "Cameras", comment: "Mac Settings pane")
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .ai: "sparkles"
        case .sources: "rectangle.on.rectangle"
        case .editing: "slider.horizontal.3"
        case .servers: "server.rack"
        case .cameras: "camera"
        }
    }

    @MainActor @ViewBuilder
    var content: some View {
        switch self {
        case .general: MacGeneralSettings()
        case .ai: MacAISettings()
        case .editing: MacEditingSettings()
        case .sources: MacSourcesSettings()
        case .servers: MacServersSettings()
        case .cameras: MacCamerasSettings()
        }
    }

    /// General, or `-ShotDexSettingsPane <name>` in a Debug build, for screenshots.
    static var initial: MacSettingsPane {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-ShotDexSettingsPane"), index + 1 < arguments.count,
           let pane = MacSettingsPane(rawValue: arguments[index + 1]) {
            return pane
        }
        #endif
        return .general
    }
}

/// General › Background: who runs Backup and On Server checks after Quit,
/// and when the Mac stays awake for them.
struct MacGeneralSettings: View {
    @Environment(MacDependencies.self) private var dependencies
    @State private var keepsWorking = MacAgentLink.keepsWorkingAfterQuit
    @State private var keepAwake = MacKeepAwake.current

    private var control: MacBackupControl { dependencies.backupControl }
    /// The user wants the helper but macOS has it switched off in Login Items.
    private var needsApproval: Bool { keepsWorking && control.agentStatus == .requiresApproval }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                MacThumbnailSettings()
                // The Mac has no viewer, Statistics screen or reminder yet (FS-18.04 §3).
                Section {
                    MacLaterSettingsRow(switchTitle: String(localized: "View Full HDR", comment: "Mac Settings row"))
                    MacLaterSettingsRow(switchTitle: String(localized: "Autoplay Videos", comment: "Mac Settings row"))
                    MacLaterSettingsRow(switchTitle: String(localized: "Show Insights in Statistics", comment: "Mac Settings row"))
                    MacLaterSettingsRow(switchTitle: String(localized: "On This Day Reminder", comment: "Mac Settings row"))
                } header: {
                    Text("Viewing and Reminders", comment: "Mac Settings group")
                }
                MacIndexingSettings().id("indexing")
                Section {
                    LabeledContent {
                        HStack(spacing: 12) {
                            if needsApproval {
                                Button(String(localized: "Open Login Items Settings", comment: "Mac Settings: open System Settings › Login Items")) {
                                    SMAppService.openSystemSettingsLoginItems()
                                }
                            }
                            Toggle(String(localized: "Keep Working After Quit", comment: "Mac Settings row"), isOn: $keepsWorking)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .tint(MacTheme.accent)
                        }
                    } label: {
                        Text("Keep Working After Quit", comment: "Mac Settings row")
                        if needsApproval {
                            Label(String(localized: "Needs Approval", comment: "Mac Settings: the helper is off in Login Items"),
                                  systemImage: "circle.fill")
                                .labelStyle(MacStatusDotLabelStyle(color: .orange))
                        }
                    }
                    Picker(String(localized: "Keep Mac Awake While Copying", comment: "Mac Settings row"), selection: $keepAwake) {
                        ForEach(MacKeepAwake.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("Background", comment: "Mac Settings group")
                } footer: {
                    Text(control.usesAgent
                         ? String(localized: "Backups and On Server checks continue in the background.", comment: "Mac Settings: the helper runs after Quit")
                         : String(localized: "Backups stop when you quit ShotDex.", comment: "Mac Backup: the jobs run only while the app is open"))
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .settingsDebugScroll(proxy)
        }
        .onChange(of: keepsWorking) { _, on in control.setKeepsWorkingAfterQuit(on) }
        .onChange(of: keepAwake) { _, value in MacKeepAwake.current = value }
        // The user may have flipped the switch in System Settings meanwhile.
        .onAppear { control.refreshAgentStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            control.refreshAgentStatus()
        }
    }
}

/// A small coloured dot before a status word, as System Settings draws it.
private struct MacStatusDotLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            configuration.title
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

extension MacKeepAwake {
    var title: String {
        switch self {
        case .never: String(localized: "Never", comment: "Mac Settings: Keep Mac Awake While Copying")
        case .onPowerAdapter: String(localized: "On Power Adapter", comment: "Mac Settings: Keep Mac Awake While Copying")
        case .always: String(localized: "Always", comment: "Mac Settings: Keep Mac Awake While Copying")
        }
    }
}

extension Notification.Name {
    /// A pane of Settings to show, by `MacSettingsPane` raw value.
    static let macSettingsShowPane = Notification.Name("ShotDexMacSettingsShowPane")
}

extension View {
    /// DEBUG `-ShotDexSettingsScroll <id>`: brings a group below the fold
    /// into view, for screenshots. Nothing in a release build.
    func settingsDebugScroll(_ proxy: ScrollViewProxy) -> some View {
        #if DEBUG
        task {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "-ShotDexSettingsScroll"), index + 1 < arguments.count else { return }
            try? await Task.sleep(for: .seconds(2))
            proxy.scrollTo(arguments[index + 1], anchor: .top)
        }
        #else
        self
        #endif
    }
}
