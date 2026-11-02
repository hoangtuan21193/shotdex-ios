import SwiftUI

/// General › Indexing (board `MAC_SettingsGeneral`; intents
/// 2026-11-02-mac-local-only-index and -icloud-shared-index): read only the
/// originals on this Mac, index for the iPhone and iPad, share results over
/// iCloud.
struct MacIndexingSettings: View {
    @Environment(MacDependencies.self) private var dependencies
    @AppStorage(SettingsKeys.indexesOriginalsOnly) private var originalsOnly = false
    @AppStorage(SettingsKeys.macIndexesForAll) private var indexesForAll = false
    @AppStorage(SettingsKeys.sharesIndex) private var sharesIndex = true
    @AppStorage(SettingsKeys.sharedIndexLastSync) private var lastSync: Double = 0
    @State private var missingCount = 0

    var body: some View {
        Section {
            row(String(localized: "Index Only Photos Downloaded to This Mac", comment: "Mac Settings row"),
                sub: String(localized: "Photos stored only in iCloud are left for your other devices, or for Index Now", comment: "Mac Settings: originals-only row explanation"),
                isOn: $originalsOnly)
            LabeledContent {
                Button(String(localized: "Index Now", comment: "Mac Settings: read photos skipped by originals-only, downloading from iCloud")) {
                    NotificationCenter.default.post(name: .macIndexMissingNow, object: nil)
                }
                .disabled(missingCount == 0)
            } label: {
                Text("Not Indexed on This Mac", comment: "Mac Settings row")
                Text(missingCount == 0
                     ? String(localized: "Every photo has camera info", comment: "Mac Settings: nothing left to index")
                     : String(localized: "\(missingCount.formatted()) photos without camera info", comment: "Mac Settings: count of photos still without EXIF"))
                    .monospacedDigit()
            }
            row(String(localized: "Share Index Across Devices", comment: "Mac Settings row"),
                sub: String(localized: "Each photo is read once, by whichever device gets to it first", comment: "Mac Settings: share row explanation"),
                isOn: $sharesIndex)
            row(String(localized: "Index for iPhone and iPad", comment: "Mac Settings row"),
                sub: String(localized: "Your iPhone and iPad read only photos stored on them and take the rest from this Mac", comment: "Mac Settings: index-for-all row explanation"),
                isOn: $indexesForAll)
                .disabled(!sharesIndex)
        } header: {
            Text("Indexing", comment: "Mac Settings group")
        } footer: {
            Text(footer).foregroundStyle(.secondary)
        }
        .onAppear(perform: refreshCount)
        .onChange(of: originalsOnly) { _, _ in
            NotificationCenter.default.post(name: .macIndexSettingsChanged, object: nil)
        }
        .onChange(of: indexesForAll) { _, isOn in publishIndexesForAll(isOn) }
        .onChange(of: sharesIndex) { _, isOn in
            // The iPhone stops deferring only when it hears the switch went off.
            if !isOn, indexesForAll { indexesForAll = false }
        }
    }

    private func row(_ title: String, sub: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
            Text(sub)
        }
        .toggleStyle(.switch)
        .tint(MacTheme.accent)
    }

    private var footer: String {
        if originalsOnly && indexesForAll {
            return String(localized: "Photos stored only in iCloud stay without camera info on every device until you choose Index Now.", comment: "Mac Settings: both originals-only and index-for-all are on")
        }
        guard sharesIndex else {
            return String(localized: "Each device reads every photo itself.", comment: "Mac Settings: sharing is off")
        }
        guard lastSync > 0 else {
            return String(localized: "Results go to your own iCloud account only.", comment: "Mac Settings: sharing on, never synced")
        }
        let date = Date(timeIntervalSince1970: lastSync).formatted(.relative(presentation: .named))
        return String(localized: "Results go to your own iCloud account only. Last synced \(date).", comment: "Mac Settings: sharing footer with the last sync time")
    }

    private func refreshCount() {
        missingCount = (try? dependencies.metadataStore.pendingICloudReadCount()) ?? 0
    }

    private func publishIndexesForAll(_ isOn: Bool) {
        guard let indexShare = dependencies.indexShare else { return }
        let name = Host.current().localizedName ?? String(localized: "Your Mac", comment: "Settings: a Mac whose name is unknown")
        Task { await indexShare.publishMacIndexesForAll(isOn, deviceName: name) }
    }
}

extension Notification.Name {
    /// Settings › Indexing › Index Now.
    static let macIndexMissingNow = Notification.Name("ShotDexMacIndexMissingNow")
    /// Settings › Indexing: a switch that changes what a run reads.
    static let macIndexSettingsChanged = Notification.Name("ShotDexMacIndexSettingsChanged")
}
