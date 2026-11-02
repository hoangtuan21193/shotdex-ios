import ServiceManagement
import SwiftUI

/// ShotDex › Settings… ⌘, (board `MAC_SettingsGeneral`). The General pane
/// has its Indexing and Background groups so far (FS-22.06 §5.4); the board's
/// other panes and groups come with the features they set.
struct MacSettingsWindow: View {
    var body: some View {
        TabView {
            Tab(String(localized: "General", comment: "Mac Settings pane"), systemImage: "gearshape") {
                MacGeneralSettings()
            }
        }
        .frame(width: 720)
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
        Form {
            MacIndexingSettings()
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
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
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
