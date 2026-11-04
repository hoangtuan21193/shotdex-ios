import SwiftUI

/// Settings › Sources › Previews (board `MAC_SettingsSourcesCache`, AC-76):
/// the one cache every source shares — how big it is, Clear Cache, and the
/// limit it is held to.
struct MacPreviewsSection: View {
    @AppStorage(SettingsKeys.previewCacheLimitGB) private var limit = PreviewCachePolicy.defaultLimit
    @State private var usage: Int64?
    @State private var volume: String?
    @State private var isConfirmingClear = false
    /// A lower limit that would delete now, waiting for Reduce or Cancel.
    @State private var pendingLimit: Int?
    /// What runs: `Clearing…` or `Trimming…`; nil when idle.
    @State private var working: String?

    var body: some View {
        Section {
            LabeledContent {
                HStack(spacing: 8) {
                    Button(String(localized: "Clear Cache…", comment: "Mac Settings › Previews: empty the preview cache")) {
                        isConfirmingClear = true
                    }
                    .disabled(working != nil || usage == nil || usage == 0)
                    Button(String(localized: "Change Location…", comment: "Mac Settings › Previews: move the cache")) {}
                        .disabled(true)
                        .help(MacLaterSettings.reason)
                }
            } label: {
                Text("Preview Cache", comment: "Mac Settings › Previews row")
                HStack(spacing: 6) {
                    if working != nil || usage == nil { ProgressView().controlSize(.small) }
                    Text(working ?? summary).monospacedDigit()
                }
            }
            Picker(selection: Binding(get: { PreviewCachePolicy.limitChoices.contains(limit) ? limit : PreviewCachePolicy.defaultLimit },
                                      set: choose)) {
                ForEach(PreviewCachePolicy.limitChoices, id: \.self) { gigabytes in
                    Text(Int64(PreviewCachePolicy.bytes(gigabytes: gigabytes)).formatted(.byteCount(style: .file))).tag(gigabytes)
                }
            } label: {
                Text("Cache Size Limit", comment: "Mac Settings › Previews row")
                Text("Over the limit, the oldest full-size previews go first, then thumbnails", comment: "Mac Settings › Previews row explanation")
            }
            .disabled(working != nil)
            MacLaterSettingsRow(title: String(localized: "Keep Full-Size Previews", comment: "Mac Settings › Previews row")) {
                Picker(String(localized: "Keep Full-Size Previews", comment: "Mac Settings › Previews row"), selection: .constant(-1)) {
                    Text("For 30 Days", comment: "Mac Settings › Previews: how long previews are kept").tag(0)
                }
                .labelsHidden()
            }
            MacLaterSettingsRow(switchTitle: String(localized: "Keep Previews of Disconnected Drives", comment: "Mac Settings › Previews row"))
        } header: {
            Text("Previews", comment: "Mac Settings › Sources group")
        } footer: {
            Text("One cache for every source: folders, drives and servers. It lives in Application Support and is left out of Time Machine backups.",
                 comment: "Mac Settings › Previews footer")
                .foregroundStyle(.secondary)
        }
        .task { await measure() }
        .confirmationDialog(clearTitle, isPresented: $isConfirmingClear) {
            Button(String(localized: "Clear Cache", comment: "Mac Settings › Previews: confirm Clear Cache"), role: .destructive) {
                Task { await work(String(localized: "Clearing…", comment: "Mac Settings › Previews: Clear Cache running")) { $0.clear() } }
            }
            Button(String(localized: "Cancel", comment: "Mac Settings › Previews: keep the cache"), role: .cancel) {}
        } message: {
            Text("Previews are made again as you browse. Thumbnails of a disconnected drive come back when it is connected again. Your photos and files are not affected.",
                 comment: "Mac Settings › Previews: Clear Cache dialog message")
        }
        .confirmationDialog(reduceTitle, isPresented: Binding(get: { pendingLimit != nil }, set: { if !$0 { pendingLimit = nil } }),
                            presenting: pendingLimit) { gigabytes in
            Button(String(localized: "Reduce", comment: "Mac Settings › Previews: confirm a lower limit"), role: .destructive) {
                limit = gigabytes
                trim(to: gigabytes)
            }
            Button(String(localized: "Cancel", comment: "Mac Settings › Previews: keep the limit"), role: .cancel) {}
        } message: { gigabytes in
            Text(reduceMessage(gigabytes))
        }
    }

    /// `18.4 GB on Macintosh HD · thumbnails and full-size previews`.
    private var summary: String {
        guard let usage else { return String(localized: "Measuring…", comment: "Mac Settings › Previews: size not known yet") }
        let size = usage.formatted(.byteCount(style: .file))
        if let volume {
            return String(localized: "\(size) on \(volume) · thumbnails and full-size previews",
                          comment: "Mac Settings › Previews: cache size and the disk it is on")
        }
        return String(localized: "\(size) · thumbnails and full-size previews", comment: "Mac Settings › Previews: cache size")
    }

    private func measure() async {
        let (bytes, name) = await Task.detached {
            let store = PreviewCacheStore.standard
            return (store.usage(), try? store.directory.resourceValues(forKeys: [.volumeLocalizedNameKey]).volumeLocalizedName)
        }.value
        usage = bytes
        volume = name
    }

    /// A higher limit, or one the cache already fits: set. A lower one that
    /// would delete now: asked first.
    private func choose(_ gigabytes: Int) {
        guard gigabytes != limit else { return }
        if let usage, usage > PreviewCachePolicy.bytes(gigabytes: gigabytes) {
            pendingLimit = gigabytes
        } else {
            limit = gigabytes
        }
    }

    private func trim(to gigabytes: Int) {
        Task { await work(String(localized: "Trimming…", comment: "Mac Settings › Previews: trimming to a lower limit")) {
            $0.trim(to: PreviewCachePolicy.bytes(gigabytes: gigabytes))
        } }
    }

    private var clearTitle: String {
        guard let usage, usage > 0 else { return String(localized: "Clear the Preview Cache?", comment: "Mac Settings › Previews: Clear Cache dialog title") }
        return String(localized: "Clear \(usage.formatted(.byteCount(style: .file))) of Previews?",
                      comment: "Mac Settings › Previews: Clear Cache dialog title with the size")
    }

    private var reduceTitle: String {
        guard let pendingLimit else { return "" }
        return String(localized: "Reduce the Limit to \(PreviewCachePolicy.bytes(gigabytes: pendingLimit).formatted(.byteCount(style: .file)))?",
                      comment: "Mac Settings › Previews: lower-limit dialog title")
    }

    private func reduceMessage(_ gigabytes: Int) -> String {
        let over = max(0, (usage ?? 0) - PreviewCachePolicy.bytes(gigabytes: gigabytes))
        return String(localized: "About \(over.formatted(.byteCount(style: .file))) of the oldest previews will be removed now, full-size previews first. Your photos and files are not affected.",
                      comment: "Mac Settings › Previews: lower-limit dialog message")
    }

    /// Off the main actor: a 25 GB cache is tens of thousands of files. One at a time.
    private func work(_ label: String, _ body: @escaping @Sendable (PreviewCacheStore) -> Void) async {
        guard working == nil else { return }
        working = label
        await Task.detached { body(PreviewCacheStore.standard) }.value
        working = nil
        await measure()
    }
}
