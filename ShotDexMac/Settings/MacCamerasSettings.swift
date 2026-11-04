import SwiftUI

/// Settings › Cameras (board `MAC_CameraDatabase`, AC-79): every camera the
/// index has seen, its sensor format picked in place, so focal lengths read
/// as full-frame equivalents. Sources › Index › Review… opens it on Needs Format.
struct MacCamerasSettings: View {
    /// Set by Review… right before it switches to this pane; read once when the pane shows.
    @MainActor static var opensOnNeedsFormat = false

    @Environment(MacDependencies.self) private var dependencies
    @State private var cameras: [CameraDatabaseQueries.Camera] = []
    @State private var filter = CameraDatabaseQueries.Filter.all
    @State private var search = ""
    /// Picked while this filter shows: kept in view, so a pick can be seen and corrected.
    @State private var recentlyEdited: Set<String> = []
    @State private var isWorking = false
    @State private var isConfirmingReset = false
    @State private var failure: String?

    private var unknown: [CameraDatabaseQueries.Camera] { cameras.filter { $0.origin == .unknown } }
    private var customCount: Int { cameras.filter { $0.origin == .custom }.count }

    private var shown: [CameraDatabaseQueries.Camera] {
        let matching = Set(CameraDatabaseQueries.filtered(cameras, filter: filter, search: search).map(\.id))
        return cameras.filter { matching.contains($0.id) || recentlyEdited.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Camera Database", comment: "Mac Settings › Cameras title").font(.title3.weight(.semibold))
                    Text("Sensor formats turn focal lengths into full-frame equivalents. Pick one for each unknown camera.",
                         comment: "Mac Settings › Cameras explanation")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(String(localized: "Reset Custom Mappings…", comment: "Mac Settings › Cameras: forget the formats picked by hand"), role: .destructive) {
                    isConfirmingReset = true
                }
                .disabled(customCount == 0 || isWorking)
            }
            HStack {
                Picker(String(localized: "Show", comment: "Mac Settings › Cameras: filter"), selection: $filter) {
                    Text("All Cameras (\(cameras.count, format: .number))", comment: "Mac Settings › Cameras filter").tag(CameraDatabaseQueries.Filter.all)
                    Text("Needs Format (\(unknown.count, format: .number))", comment: "Mac Settings › Cameras filter").tag(CameraDatabaseQueries.Filter.needsFormat)
                    Text("Custom (\(customCount, format: .number))", comment: "Mac Settings › Cameras filter").tag(CameraDatabaseQueries.Filter.custom)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                TextField(String(localized: "Search Cameras", comment: "Mac Settings › Cameras: search field"), text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
            }
            table
                .overlay { if shown.isEmpty && !cameras.isEmpty || cameras.isEmpty && !isWorking { emptyState } }
            Text(footer).font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(20)
        .task { await reload() }
        .onAppear(perform: takeReviewRequest)
        .onReceive(NotificationCenter.default.publisher(for: .macSettingsShowPane)) { _ in takeReviewRequest() }
        .onChange(of: filter) { _, _ in recentlyEdited = [] }
        .confirmationDialog(resetTitle, isPresented: $isConfirmingReset) {
            Button(String(localized: "Reset", comment: "Mac Settings › Cameras: confirm reset"), role: .destructive) { reset() }
            Button(String(localized: "Cancel", comment: "Mac Settings › Cameras: keep the mappings"), role: .cancel) {}
        } message: {
            Text("Those cameras go back to the format the built-in database gives them, or to Unknown; their photos' full-frame equivalents change with them.",
                 comment: "Mac Settings › Cameras: reset dialog message")
        }
        .alert(String(localized: "The Format Was Not Saved", comment: "Mac Settings › Cameras: a write failed"),
               isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button(String(localized: "OK", comment: "Mac Settings › Cameras: dismiss an error")) {}
        } message: {
            Text(failure ?? "")
        }
    }

    private var table: some View {
        Table(shown) {
            TableColumn(String(localized: "Camera", comment: "Mac Settings › Cameras column")) { camera in
                Label {
                    Text(camera.model).lineLimit(1)
                } icon: {
                    Image(systemName: camera.origin == .unknown ? "exclamationmark.triangle" : "camera")
                        .foregroundStyle(camera.origin == .unknown ? Color.orange : .secondary)
                }
            }
            TableColumn(String(localized: "Photos", comment: "Mac Settings › Cameras column")) { camera in
                Text(camera.photoCount, format: .number).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(70)
            TableColumn(String(localized: "Sensor Format", comment: "Mac Settings › Cameras column")) { camera in
                Picker(String(localized: "Sensor Format", comment: "Mac Settings › Cameras column"),
                       selection: Binding(get: { camera.format }, set: { set($0, for: camera) })) {
                    if camera.format == .unknown {
                        Text("Choose…", comment: "Mac Settings › Cameras: no format yet").tag(SensorFormat.unknown)
                    }
                    ForEach(SensorFormat.allCases.filter { $0 != .unknown }) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .labelsHidden()
                .disabled(isWorking)
                .accessibilityLabel(String(localized: "Sensor format of \(camera.model)", comment: "Mac Settings › Cameras: VoiceOver"))
            }
            .width(150)
            TableColumn(String(localized: "Crop Factor", comment: "Mac Settings › Cameras column")) { camera in
                Text(camera.cropFactor.map { $0.formatted(.number.precision(.fractionLength(1...2))) + "×" } ?? "—")
                    .monospacedDigit().foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(80)
            TableColumn(String(localized: "Source", comment: "Mac Settings › Cameras column")) { camera in
                Text(origin(camera.origin)).foregroundStyle(.secondary)
            }
            .width(80)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if cameras.isEmpty {
            ContentUnavailableView(String(localized: "No Cameras Yet", comment: "Mac Settings › Cameras: nothing indexed"),
                                   systemImage: "camera",
                                   description: Text("Cameras appear here as the library is indexed.", comment: "Mac Settings › Cameras: empty"))
        } else if !search.isEmpty {
            ContentUnavailableView.search(text: search)
        } else if filter == .needsFormat {
            ContentUnavailableView(String(localized: "Every Camera Has a Sensor Format", comment: "Mac Settings › Cameras: nothing to fix"),
                                   systemImage: "checkmark.circle")
        } else {
            ContentUnavailableView(String(localized: "No Custom Formats", comment: "Mac Settings › Cameras: none picked by hand"),
                                   systemImage: "camera",
                                   description: Text("Pick a format for an unknown camera to add one.", comment: "Mac Settings › Cameras: empty Custom"))
        }
    }

    private var footer: String {
        let photos = unknown.reduce(0) { $0 + $1.photoCount }
        switch unknown.count {
        case 0: return String(localized: "Every camera has a sensor format.", comment: "Mac Settings › Cameras footer: nothing to fix")
        case 1: return String(localized: "1 camera needs a format · \(photos, format: .number) photos have no full-frame equivalent",
                              comment: "Mac Settings › Cameras footer: one camera")
        default: return String(localized: "\(unknown.count, format: .number) cameras need a format · \(photos, format: .number) photos have no full-frame equivalent",
                               comment: "Mac Settings › Cameras footer")
        }
    }

    private var resetTitle: String {
        customCount == 1
            ? String(localized: "Forget 1 Custom Format?", comment: "Mac Settings › Cameras: reset dialog title, one")
            : String(localized: "Forget \(customCount, format: .number) Custom Formats?", comment: "Mac Settings › Cameras: reset dialog title")
    }

    private func origin(_ origin: CameraDatabaseQueries.Camera.Origin) -> String {
        switch origin {
        case .builtIn: String(localized: "Built-in", comment: "Mac Settings › Cameras: format from the bundled database")
        case .custom: String(localized: "Custom", comment: "Mac Settings › Cameras: format picked by hand")
        case .unknown: String(localized: "Unknown", comment: "Mac Settings › Cameras: no format yet")
        }
    }

    /// Review… asked for Needs Format; any other visit starts on All Cameras.
    private func takeReviewRequest() {
        guard Self.opensOnNeedsFormat else { return }
        Self.opensOnNeedsFormat = false
        filter = .needsFormat
        search = ""
        Task { await reload() }
    }

    /// Off the main actor: 18,000 rows grouped by camera.
    private func reload() async {
        let queries = CameraDatabaseQueries(database: dependencies.database)
        cameras = await Task.detached { (try? queries.cameras()) ?? [] }.value
    }

    /// A format picked: kept as the camera's mapping and written to its photos now.
    private func set(_ format: SensorFormat, for camera: CameraDatabaseQueries.Camera) {
        guard format != .unknown, format != camera.format else { return }
        let store = dependencies.metadataStore
        let mapping = CustomCameraMapping(normalizedCameraModel: camera.model, sensorFormat: format.rawValue, cropFactor: format.typicalCropFactor)
        recentlyEdited.insert(camera.id)
        work { try store.applyCustomMapping(mapping) }
    }

    private func reset() {
        let store = dependencies.metadataStore
        work { try store.resetCustomMappings(to: SensorLookup(records: (try? SensorDatabaseLoader().loadRecords()) ?? [])) }
    }

    private func work(_ write: @escaping @Sendable () throws -> Void) {
        isWorking = true
        Task {
            let error = await Task.detached { () -> String? in
                do { try write(); return nil } catch { return error.localizedDescription }
            }.value
            failure = error
            dependencies.library?.reload()
            await reload()
            isWorking = false
        }
    }
}
