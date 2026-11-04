import IOKit.ps
import SwiftUI

/// Settings › Sources › Drives and Indexing (board `MAC_SettingsSources`,
/// AC-75): what an unplugged drive's photos do, when indexing waits for
/// power, whether it keeps the Mac awake, and place-name lookups.
struct MacDrivesIndexingSection: View {
    @Environment(MacDependencies.self) private var dependencies
    @AppStorage(SettingsKeys.pausesIndexingOnBattery) private var pausesOnBattery = true
    @AppStorage(SettingsKeys.preventsSleepWhileIndexing) private var preventsSleep = true
    @AppStorage(SettingsKeys.lookUpPlaces) private var looksUpPlaces = true
    @State private var whenUnplugged = SourceStore.WhenUnplugged.keepPhotos

    private let hasBattery = MacDrivesIndexingSection.macHasBattery

    var body: some View {
        Section {
            Picker(selection: $whenUnplugged) {
                Text("Keep Photos, Marked Offline", comment: "Mac Settings › Sources: an unplugged drive's photos stay").tag(SourceStore.WhenUnplugged.keepPhotos)
                Text("Hide Photos Until the Drive Is Back", comment: "Mac Settings › Sources: an unplugged drive's photos are hidden").tag(SourceStore.WhenUnplugged.hidePhotos)
            } label: {
                Text("When a Drive Is Disconnected", comment: "Mac Settings › Sources row")
                Text("Applies to every drive, including ones you add later", comment: "Mac Settings › Sources row explanation")
            }
            // Index always reads new and changed files; there is no switch for it yet.
            MacLaterSettingsRow(title: String(localized: "Index New and Changed Files", comment: "Mac Settings › Sources row")) {
                Picker(String(localized: "Index New and Changed Files", comment: "Mac Settings › Sources row"), selection: .constant(0)) {
                    Text("Automatically", comment: "Mac Settings › Sources: index new files on its own").tag(0)
                }
                .labelsHidden()
            }
            Toggle(isOn: hasBattery ? $pausesOnBattery : .constant(false)) {
                Text("Pause Indexing on Battery Power", comment: "Mac Settings › Sources row")
                Text(hasBattery ? String(localized: "Indexing always pauses in Low Power Mode", comment: "Mac Settings › Sources row explanation")
                                : String(localized: "This Mac has no battery", comment: "Mac Settings › Sources: a desktop Mac"))
            }
            .disabled(!hasBattery)
            .tint(MacTheme.accent)
            Toggle(isOn: $preventsSleep) {
                Text("Prevent Sleep While Indexing", comment: "Mac Settings › Sources row")
                Text("Off, indexing waits while this Mac sleeps", comment: "Mac Settings › Sources row explanation")
            }
            .tint(MacTheme.accent)
            Toggle(isOn: $looksUpPlaces) {
                Text("Look Up Place Names", comment: "Mac Settings › Sources row")
                Text("Looked up once per place, then remembered", comment: "Mac Settings › Sources row explanation")
            }
            .tint(MacTheme.accent)
        } header: {
            Text("Drives and Indexing", comment: "Mac Settings › Sources group")
        }
        .toggleStyle(.switch)
        .onAppear { whenUnplugged = dependencies.sourcesModel.drivesWhenUnplugged }
        .onChange(of: whenUnplugged) { _, choice in
            guard choice != dependencies.sourcesModel.drivesWhenUnplugged else { return }
            dependencies.sourcesModel.setDrivesWhenUnplugged(choice)
        }
        .onChange(of: pausesOnBattery) { _, _ in dependencies.library?.powerSettingsChanged() }
    }

    /// A MacBook, not a desktop: only then is there a battery to pause on.
    static var macHasBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        return list.contains { source in
            let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
            return description?[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
        }
    }
}
