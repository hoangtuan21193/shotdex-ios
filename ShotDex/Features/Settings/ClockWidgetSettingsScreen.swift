import SwiftUI

/// Everything the Clock widget shows, set here and written to the App Group
/// the widget reads.
///
/// The preview at the top is the widget's own `ClockWidgetFace` over the
/// widget's own background, at the medium family's proportions — the size the
/// point values are measured against — so the typeface, colour, format and
/// placement are seen where they will land rather than described.
struct ClockWidgetSettingsScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(PhotoLibraryService.self) private var photoLibrary

    @State private var isPhotoPickerPresented = false
    @State private var isAlbumPickerPresented = false
    @State private var isFontPickerPresented = false
    @State private var isCustomTimeFormatPresented = false
    @State private var isCustomDateFormatPresented = false
    /// Ticks the preview so it reads like a clock rather than a frozen label.
    @State private var previewDate = Date.now

    private var store: ClockWidgetSettingsStore { dependencies.clockWidgetSettings }
    private var settings: ClockWidgetSettings { store.settings }

    var body: some View {
        List {
            previewSection
            photoSection
            contentSection
            typefaceSection
            colourSection
            placementSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Clock Widget")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPhotoPickerPresented) {
            ClockWidgetPhotoPicker { assetId in
                store.update { $0.source = .photo(assetId: assetId) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isAlbumPickerPresented) {
            NavigationStack {
                ClockWidgetAlbumPicker { collectionId, title in
                    store.update { $0.source = .album(collectionId: collectionId, title: title) }
                }
            }
            .environment(dependencies)
        }
        .sheet(isPresented: $isFontPickerPresented) {
            ClockWidgetFontPicker { choice in
                store.update {
                    $0.fontPostScriptName = choice.postScriptName
                    $0.fontDisplayName = choice.displayName
                }
            }
        }
        .alert("Time Format", isPresented: $isCustomTimeFormatPresented) {
            customFormatFields(isTime: true)
        } message: {
            Text("A date format pattern, like h:mm a. Seconds are removed — a widget is redrawn once a minute at best.")
        }
        .alert("Date Format", isPresented: $isCustomDateFormatPresented) {
            customFormatFields(isTime: false)
        } message: {
            Text("A date format pattern, like EEE d MMM.")
        }
        // The preview is a clock, so it ticks. One second is fast enough to
        // look alive and costs one view update.
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            previewDate = date
        }
        .onDisappear { store.saveNow() }
    }

    // MARK: Preview

    private var previewSection: some View {
        Section {
            // 329 × 155 is the medium widget on a 6.1" iPhone, the size
            // `ClockWidgetSettings.scaledTimeSize` measures against.
            ClockWidgetPreview(
                settings: settings,
                date: previewDate,
                // Flips when a re-render finishes, so the preview picks up the
                // new file instead of holding the one it loaded first.
                reloadToken: store.isRenderingPhotos
            )
                .frame(height: 155)
                .frame(maxWidth: .infinity)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .listRowBackground(Color.clear)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Preview of the Clock widget")
        }
    }

    // MARK: Photo

    private var photoSection: some View {
        Section {
            Button {
                isPhotoPickerPresented = true
            } label: {
                LabeledContent("Photo", value: isPhotoSource ? "Chosen" : "Choose")
            }
            Button {
                isAlbumPickerPresented = true
            } label: {
                LabeledContent("Album", value: albumTitle ?? "Choose")
            }
            if case .album = settings.source {
                Picker("Change Photo", selection: rotationBinding) {
                    ForEach(ClockWidgetSettings.Rotation.allCases) { rotation in
                        Text(rotation.title).tag(rotation)
                    }
                }
            }
            if !isNoneSource {
                Button {
                    store.renderPhotos()
                } label: {
                    LabeledContent("Refresh Now") {
                        if store.isRenderingPhotos {
                            ProgressView()
                        }
                    }
                }
                .disabled(store.isRenderingPhotos)
                Button("Remove Photo", role: .destructive) {
                    store.update { $0.source = .none }
                }
            }
            dimmingRow
        } header: {
            Text("Background")
        } footer: {
            Text("ShotDex copies the photos into the widget's own storage, because a widget cannot read your library. An album is copied up to \(ClockWidgetSnapshot.maxFrames) photos deep; use Refresh Now after adding to it.")
        }
    }

    private var dimmingRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("Dim Photo", value: "\(Int(settings.photoDimming * 100))%")
                .monospacedDigit()
            Slider(
                value: Binding(
                    get: { settings.photoDimming },
                    set: { value in store.update { $0.photoDimming = value } }
                ),
                in: 0...0.7
            )
            .accessibilityLabel("Dim photo")
        }
    }

    // MARK: Content

    private var contentSection: some View {
        Section {
            Toggle("Show Time", isOn: boolBinding(\.showsTime))
            if settings.showsTime {
                Picker("Time Format", selection: timeFormatBinding) {
                    ForEach(ClockWidgetFormat.timePresets, id: \.pattern) { preset in
                        Text(preset.title).tag(preset.pattern)
                    }
                    if isCustomTimePattern {
                        Text("Custom").tag(settings.timeFormat)
                    }
                }
                Button("Custom Time Format…") { isCustomTimeFormatPresented = true }
                sizeRow(
                    title: "Time Size",
                    value: settings.timeSize,
                    range: ClockWidgetSettings.timeSizeRange
                ) { value in
                    store.update { $0.timeSize = value }
                }
            }

            Toggle("Show Date", isOn: boolBinding(\.showsDate))
            if settings.showsDate {
                Picker("Date Format", selection: dateFormatBinding) {
                    ForEach(ClockWidgetFormat.datePresets, id: \.pattern) { preset in
                        Text(preset.title).tag(preset.pattern)
                    }
                    if isCustomDatePattern {
                        Text("Custom").tag(settings.dateFormat)
                    }
                }
                Button("Custom Date Format…") { isCustomDateFormatPresented = true }
                sizeRow(
                    title: "Date Size",
                    value: settings.dateSize,
                    range: ClockWidgetSettings.dateSizeRange
                ) { value in
                    store.update { $0.dateSize = value }
                }
            }
        } header: {
            Text("Time and Date")
        } footer: {
            Text("System follows the clock format in iOS Settings, including 24-hour time. Sizes are for the medium widget; the small and large ones scale from them.")
        }
    }

    private func sizeRow(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title, value: "\(Int(value)) pt")
                .monospacedDigit()
            Slider(
                value: Binding(get: { value }, set: onChange),
                in: range,
                step: 1
            )
            .accessibilityLabel(title)
        }
    }

    // MARK: Typeface

    private var typefaceSection: some View {
        Section {
            Button {
                isFontPickerPresented = true
            } label: {
                LabeledContent("Typeface", value: settings.fontDisplayName)
            }
            if !settings.fontPostScriptName.isEmpty {
                Button("Use the System Font") {
                    store.update {
                        $0.fontPostScriptName = ""
                        $0.fontDisplayName = "System"
                    }
                }
            }
            if settings.fontPostScriptName.isEmpty {
                Toggle("Bold", isOn: boolBinding(\.isBold))
            }
            Toggle("Monospaced Digits", isOn: boolBinding(\.usesMonospacedDigits))
        } header: {
            Text("Typeface")
        } footer: {
            Text("Monospaced digits keep the clock from shifting as the minutes change. A typeface another app installed may not be available to the widget; it falls back to the system font.")
        }
    }

    // MARK: Colour

    private var colourSection: some View {
        Section {
            // Swatches rather than a picker menu: with colour, the colour is
            // the whole answer, and a menu hides every option behind a tap
            // (DESIGN.md §7.5, the same reason the accent row is swatches).
            HStack(spacing: 12) {
                ForEach(WidgetTextColor.swatches, id: \.self) { hex in
                    swatch(hex: hex)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)

            Picker("Legibility", selection: legibilityBinding) {
                ForEach(ClockWidgetSettings.Legibility.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
        } header: {
            Text("Colour")
        } footer: {
            Text("Shadow suits most photos. Scrim darkens a band behind the clock, for photos with a busy sky or bright detail under the text.")
        }
    }

    private func swatch(hex: String) -> some View {
        let isSelected = settings.textColorHex.uppercased() == hex.uppercased()
        return Button {
            store.update { $0.textColorHex = hex }
        } label: {
            Circle()
                .fill(WidgetTextColor.color(hex: hex))
                .frame(width: 30, height: 30)
                .overlay(
                    Circle().strokeBorder(.secondary.opacity(0.35), lineWidth: 1)
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary, lineWidth: isSelected ? 2 : 0)
                        .padding(-4)
                )
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(hex)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Placement

    private var placementSection: some View {
        Section {
            Picker("Position", selection: placementBinding) {
                ForEach(ClockWidgetSettings.Placement.allCases) { placement in
                    Text(placement.title).tag(placement)
                }
            }
        } header: {
            Text("Position")
        }
    }

    // MARK: Bindings and helpers

    private var isPhotoSource: Bool {
        if case .photo = settings.source { return true }
        return false
    }

    private var isNoneSource: Bool {
        if case .none = settings.source { return true }
        return false
    }

    private var albumTitle: String? {
        if case .album(_, let title) = settings.source { return title }
        return nil
    }

    private var isCustomTimePattern: Bool {
        !settings.timeFormat.isEmpty
            && !ClockWidgetFormat.timePresets.contains { $0.pattern == settings.timeFormat }
    }

    private var isCustomDatePattern: Bool {
        !settings.dateFormat.isEmpty
            && !ClockWidgetFormat.datePresets.contains { $0.pattern == settings.dateFormat }
    }

    private func boolBinding(_ keyPath: WritableKeyPath<ClockWidgetSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in store.update { $0[keyPath: keyPath] = value } }
        )
    }

    private var timeFormatBinding: Binding<String> {
        Binding(
            get: { settings.timeFormat },
            set: { value in store.update { $0.timeFormat = value } }
        )
    }

    private var dateFormatBinding: Binding<String> {
        Binding(
            get: { settings.dateFormat },
            set: { value in store.update { $0.dateFormat = value } }
        )
    }

    private var rotationBinding: Binding<ClockWidgetSettings.Rotation> {
        Binding(
            get: { settings.rotation },
            set: { value in store.update { $0.rotation = value } }
        )
    }

    private var legibilityBinding: Binding<ClockWidgetSettings.Legibility> {
        Binding(
            get: { settings.legibility },
            set: { value in store.update { $0.legibility = value } }
        )
    }

    private var placementBinding: Binding<ClockWidgetSettings.Placement> {
        Binding(
            get: { settings.placement },
            set: { value in store.update { $0.placement = value } }
        )
    }

    /// The two custom-format alerts share their fields: a text field for the
    /// pattern, and the two buttons an alert needs.
    @ViewBuilder
    private func customFormatFields(isTime: Bool) -> some View {
        TextField(
            isTime ? "h:mm a" : "EEE d MMM",
            text: isTime ? timeFormatBinding : dateFormatBinding
        )
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        Button("Done") {}
        Button("Use the System Format", role: .destructive) {
            if isTime {
                store.update { $0.timeFormat = "" }
            } else {
                store.update { $0.dateFormat = "" }
            }
        }
    }
}

/// The widget's own face over the widget's own background, at the medium
/// family's proportions. Shares `ClockWidgetFace` with the widget, so a
/// change to one cannot leave the other behind.
struct ClockWidgetPreview: View {
    let settings: ClockWidgetSettings
    let date: Date
    let reloadToken: Bool

    /// The preview loads the same file the widget does.
    @State private var image: Image?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image {
                    image.resizable().scaledToFill()
                } else {
                    LinearGradient(
                        colors: [.gray.opacity(0.55), .gray.opacity(0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                if settings.photoDimming > 0 {
                    Color.black.opacity(settings.photoDimming)
                }
                if settings.legibility == .scrim {
                    ClockWidgetScrim(placement: settings.placement)
                }
                ClockWidgetFace(date: date, settings: settings, width: proxy.size.width)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xxl, style: .continuous))
        }
        .task(id: PreviewLoadKey(source: settings.source, reloadToken: reloadToken)) {
            await loadImage()
        }
    }

    private struct PreviewLoadKey: Equatable {
        let source: ClockWidgetSettings.Source
        let reloadToken: Bool
    }

    private var alignment: Alignment {
        switch settings.placement {
        case .topLeading: .topLeading
        case .top: .top
        case .center: .center
        case .bottom: .bottom
        case .bottomLeading: .bottomLeading
        }
    }

    private func loadImage() async {
        let snapshot = ClockWidgetSnapshot.read()
        let index = ClockWidgetSnapshot.frameIndex(
            at: .now, count: snapshot.frames.count, rotation: settings.rotation
        )
        guard let index, let url = snapshot.imageURL(at: index) else {
            image = nil
            return
        }
        let loaded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }.value
        image = loaded.map { Image(uiImage: $0) }
    }
}
