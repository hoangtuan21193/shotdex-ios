import SwiftUI

/// Everything one photo widget shows — its picture, what is written over it,
/// and how — written to the App Group the widget reads.
///
/// One screen for all four kinds. The sections that do not apply are simply
/// not built: a Clock has no weather section, a Weather widget has no month
/// grid. The preview at the top is the widget's own `PhotoWidgetFace` over the
/// widget's own background, at the medium family's proportions — the size the
/// point values are measured against.
struct PhotoWidgetSettingsScreen: View {
    let kind: PhotoWidgetKind

    @Environment(AppDependencies.self) private var dependencies

    @State private var isPhotoPickerPresented = false
    @State private var isAlbumPickerPresented = false
    @State private var isFontPickerPresented = false
    @State private var isCustomTimeFormatPresented = false
    @State private var isCustomDateFormatPresented = false
    /// Ticks the preview so a clock reads like a clock rather than a frozen
    /// label.
    @State private var previewDate = Date.now
    @State private var weather: WeatherSnapshot?
    @State private var calendarSnapshot: CalendarSnapshot?
    @State private var calendarAccess: CalendarSnapshotWriter.Access = .notDetermined
    @State private var isRefreshingWeather = false

    private var store: PhotoWidgetSettingsStore { dependencies.photoWidgetSettings }
    private var settings: PhotoWidgetSettings { store.settings(for: kind) }

    var body: some View {
        List {
            previewSection
            photoSection
            timeSection
            if kind.needsCalendarEvents { calendarSection }
            if kind.needsWeather { weatherSection }
            typefaceSection
            colourSection
            placementSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPhotoPickerPresented) {
            PhotoWidgetPhotoPicker { assetId in
                store.update(kind) { $0.source = .photo(assetId: assetId) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isAlbumPickerPresented) {
            NavigationStack {
                PhotoWidgetAlbumPicker { collectionId, title in
                    store.update(kind) { $0.source = .album(collectionId: collectionId, title: title) }
                }
            }
            .environment(dependencies)
        }
        .sheet(isPresented: $isFontPickerPresented) {
            PhotoWidgetFontPicker { choice in
                store.update(kind) {
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
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            previewDate = date
        }
        .task {
            weather = WeatherSnapshot.read()
            calendarAccess = dependencies.calendarWidgetWriter.access
            // The preview shows today's events, so the events are read while
            // it is on screen — a widget that is not placed yet has never had
            // them read for it.
            if kind.needsCalendarEvents, calendarAccess == .granted {
                await dependencies.calendarWidgetWriter.write(force: true)
            }
            calendarSnapshot = CalendarSnapshot.read()
        }
        .onDisappear { store.saveNow() }
    }

    // MARK: Preview

    private var previewSection: some View {
        Section {
            // 329 × 155 is the medium widget on a 6.1" iPhone, the size
            // `PhotoWidgetSettings.scaledHeadlineSize` measures against.
            PhotoWidgetPreview(
                kind: kind,
                settings: settings,
                date: previewDate,
                weather: weather,
                calendarSnapshot: calendarSnapshot,
                // Flips when a re-render finishes, so the preview picks up the
                // new file instead of holding the one it loaded first.
                reloadToken: store.isRendering(kind)
            )
            .frame(height: previewHeight)
            .frame(maxWidth: .infinity)
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            .listRowBackground(Color.clear)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preview of the \(kind.title) widget")
        }
    }

    /// A month grid needs the height a tall family would give it; the others
    /// are shown at the medium family's shape.
    private var previewHeight: CGFloat {
        kind.needsCalendarEvents && settings.calendarStyle.showsGrid ? 260 : 155
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
                    ForEach(PhotoWidgetSettings.Rotation.allCases) { rotation in
                        Text(rotation.title).tag(rotation)
                    }
                }
            }
            if !isNoneSource {
                Button {
                    store.renderPhotos(for: kind)
                } label: {
                    LabeledContent("Refresh Now") {
                        if store.isRendering(kind) {
                            ProgressView()
                        }
                    }
                }
                .disabled(store.isRendering(kind))
                Button("Remove Photo", role: .destructive) {
                    store.update(kind) { $0.source = .none }
                }
            }
            dimmingRow
        } header: {
            Text("Background")
        } footer: {
            Text("ShotDex copies the photos into the widget's own storage, because a widget cannot read your library. An album is copied up to \(PhotoWidgetSnapshot.maxFrames) photos deep; use Refresh Now after adding to it.")
        }
    }

    private var dimmingRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("Dim Photo", value: "\(Int(settings.photoDimming * 100))%")
                .monospacedDigit()
            Slider(
                value: Binding(
                    get: { settings.photoDimming },
                    set: { value in store.update(kind) { $0.photoDimming = value } }
                ),
                in: 0...0.7
            )
            .accessibilityLabel("Dim photo")
        }
    }

    // MARK: Time and date

    private var timeSection: some View {
        Section {
            Toggle("Show Time", isOn: boolBinding(\.showsTime))
            if settings.showsTime {
                Picker("Time Format", selection: timeFormatBinding) {
                    ForEach(PhotoWidgetFormat.timePresets, id: \.pattern) { preset in
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
                    range: PhotoWidgetSettings.timeSizeRange
                ) { value in
                    store.update(kind) { $0.timeSize = value }
                }
            }

            Toggle("Show Date", isOn: boolBinding(\.showsDate))
            if settings.showsDate {
                Picker("Date Format", selection: dateFormatBinding) {
                    ForEach(PhotoWidgetFormat.datePresets, id: \.pattern) { preset in
                        Text(preset.title).tag(preset.pattern)
                    }
                    if isCustomDatePattern {
                        Text("Custom").tag(settings.dateFormat)
                    }
                }
                Button("Custom Date Format…") { isCustomDateFormatPresented = true }
            }
            sizeRow(
                title: "Text Size",
                value: settings.dateSize,
                range: PhotoWidgetSettings.dateSizeRange
            ) { value in
                store.update(kind) { $0.dateSize = value }
            }
        } header: {
            Text("Time and Date")
        } footer: {
            Text("System follows the clock format in iOS Settings, including 24-hour time. Text Size sets every line under the headline — the month grid, the events and the weather with it. Sizes are for the medium widget; the small and large ones scale from them.")
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

    // MARK: Calendar

    private var calendarSection: some View {
        Section {
            Picker("Show", selection: calendarStyleBinding) {
                ForEach(PhotoWidgetSettings.CalendarStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            if settings.calendarStyle.showsGrid {
                Toggle("Start Weeks on Monday", isOn: boolBinding(\.weekStartsOnMonday))
            }
            if settings.calendarStyle.showsEvents {
                Stepper(
                    "Events Listed: \(settings.maximumEventCount)",
                    value: Binding(
                        get: { settings.maximumEventCount },
                        set: { value in store.update(kind) { $0.maximumEventCount = value } }
                    ),
                    in: PhotoWidgetSettings.eventCountRange
                )
                .monospacedDigit()
                if calendarAccess != .granted {
                    LabeledContent("Calendar Access", value: calendarAccessLabel)
                    Button(calendarAccess == .denied ? "Open Settings" : "Allow Calendar Access") {
                        if calendarAccess == .denied {
                            openAppSettings()
                        } else {
                            Task {
                                _ = await dependencies.calendarWidgetWriter.requestAccess()
                                calendarAccess = dependencies.calendarWidgetWriter.access
                                await dependencies.calendarWidgetWriter.write(force: true)
                                calendarSnapshot = CalendarSnapshot.read()
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Calendar")
        } footer: {
            Text("The month is worked out on this iPhone and needs no permission. Listing today's events reads your calendars — only their titles, times and colours are copied for the widget, and only for today.")
        }
    }

    private var calendarAccessLabel: String {
        switch calendarAccess {
        case .granted: "Allowed"
        case .denied: "Denied"
        case .notDetermined: "Not Requested"
        }
    }

    // MARK: Weather

    private var weatherSection: some View {
        Section {
            Picker("Units", selection: temperatureUnitBinding) {
                ForEach(PhotoWidgetSettings.TemperatureUnit.allCases) { unit in
                    Text(unit.title).tag(unit)
                }
            }
            Toggle("Show High and Low", isOn: boolBinding(\.showsHighLow))
            Toggle("Show Place", isOn: boolBinding(\.showsWeatherPlace))
            LabeledContent("Last Reading", value: weatherAgeLabel)
            Button {
                Task {
                    isRefreshingWeather = true
                    await WeatherSnapshotWriter(location: dependencies.widgetLocation)
                        .write(force: true)
                    weather = WeatherSnapshot.read()
                    isRefreshingWeather = false
                }
            } label: {
                LabeledContent("Update Now") {
                    if isRefreshingWeather { ProgressView() }
                }
            }
            .disabled(isRefreshingWeather)
        } header: {
            Text("Weather")
        } footer: {
            Text("ShotDex asks for your location once, rounds it to about a kilometre, and fetches the current conditions from Open-Meteo. It does this only while a weather widget is on your Home Screen, and it sends nothing else.")
        }
    }

    private var weatherAgeLabel: String {
        guard let weather else { return "None yet" }
        return weather.updatedAt.formatted(date: .omitted, time: .shortened)
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
                    store.update(kind) {
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
            Text("Monospaced digits keep the numbers from shifting as they change. A typeface another app installed may not be available to the widget; it falls back to the system font.")
        }
    }

    // MARK: Colour

    private var colourSection: some View {
        Section {
            // Swatches rather than a picker menu: with colour, the colour is
            // the whole answer, and a menu hides every option behind a tap
            // (DESIGN.md §7.5, the same reason the accent row is swatches).
            // Two rows of four: eight 44pt targets do not fit one grouped row.
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                spacing: 12
            ) {
                ForEach(WidgetTextColor.swatches, id: \.self) { hex in
                    swatch(hex: hex)
                }
            }
            .padding(.vertical, 6)

            Picker("Legibility", selection: legibilityBinding) {
                ForEach(PhotoWidgetSettings.Legibility.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
        } header: {
            Text("Colour")
        } footer: {
            Text("Shadow suits most photos. Scrim darkens a band behind the text, for photos with a busy sky or bright detail under it.")
        }
    }

    private func swatch(hex: String) -> some View {
        let isSelected = settings.textColorHex.uppercased() == hex.uppercased()
        return Button {
            store.update(kind) { $0.textColorHex = hex }
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
        .frame(maxWidth: .infinity, minHeight: 44)
        .accessibilityLabel(colourName(hex: hex))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// A colour needs a name a screen reader can say; a hex code read out
    /// digit by digit is not one.
    private func colourName(hex: String) -> String {
        switch hex.uppercased() {
        case "#FFFFFF": "White"
        case "#000000": "Black"
        case "#EB9526": "Amber"
        case "#F2E8D5": "Sand"
        case "#7FD1AE": "Green"
        case "#8FC7E8": "Blue"
        case "#E88FA8": "Pink"
        case "#C7A8F0": "Purple"
        default: hex
        }
    }

    // MARK: Placement

    private var placementSection: some View {
        Section {
            Picker("Position", selection: placementBinding) {
                ForEach(PhotoWidgetSettings.Placement.allCases) { placement in
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
            && !PhotoWidgetFormat.timePresets.contains { $0.pattern == settings.timeFormat }
    }

    private var isCustomDatePattern: Bool {
        !settings.dateFormat.isEmpty
            && !PhotoWidgetFormat.datePresets.contains { $0.pattern == settings.dateFormat }
    }

    private func boolBinding(_ keyPath: WritableKeyPath<PhotoWidgetSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in store.update(kind) { $0[keyPath: keyPath] = value } }
        )
    }

    private var timeFormatBinding: Binding<String> {
        Binding(
            get: { settings.timeFormat },
            set: { value in store.update(kind) { $0.timeFormat = value } }
        )
    }

    private var dateFormatBinding: Binding<String> {
        Binding(
            get: { settings.dateFormat },
            set: { value in store.update(kind) { $0.dateFormat = value } }
        )
    }

    private var rotationBinding: Binding<PhotoWidgetSettings.Rotation> {
        Binding(
            get: { settings.rotation },
            set: { value in store.update(kind) { $0.rotation = value } }
        )
    }

    private var legibilityBinding: Binding<PhotoWidgetSettings.Legibility> {
        Binding(
            get: { settings.legibility },
            set: { value in store.update(kind) { $0.legibility = value } }
        )
    }

    private var placementBinding: Binding<PhotoWidgetSettings.Placement> {
        Binding(
            get: { settings.placement },
            set: { value in store.update(kind) { $0.placement = value } }
        )
    }

    private var calendarStyleBinding: Binding<PhotoWidgetSettings.CalendarStyle> {
        Binding(
            get: { settings.calendarStyle },
            set: { value in store.update(kind) { $0.calendarStyle = value } }
        )
    }

    private var temperatureUnitBinding: Binding<PhotoWidgetSettings.TemperatureUnit> {
        Binding(
            get: { settings.temperatureUnit },
            set: { value in store.update(kind) { $0.temperatureUnit = value } }
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
                store.update(kind) { $0.timeFormat = "" }
            } else {
                store.update(kind) { $0.dateFormat = "" }
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// The widget's own face over the widget's own background, at the medium
/// family's proportions. Shares `PhotoWidgetFace` with the widget, so a change
/// to one cannot leave the other behind.
struct PhotoWidgetPreview: View {
    let kind: PhotoWidgetKind
    let settings: PhotoWidgetSettings
    let date: Date
    let weather: WeatherSnapshot?
    let calendarSnapshot: CalendarSnapshot?
    let reloadToken: Bool

    /// The preview loads the same file the widget does.
    @State private var image: Image?

    var body: some View {
        GeometryReader { proxy in
            // The image is clipped to the preview's own size before anything
            // is stacked on it: a `scaledToFill` image is larger than its
            // frame, and a ZStack sized by it pushes the bottom-aligned text
            // out through the bottom edge.
            ZStack {
                if let image {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
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
                    PhotoWidgetScrim(placement: settings.placement)
                }
                PhotoWidgetFace(
                    date: date,
                    settings: settings,
                    kind: kind,
                    width: proxy.size.width,
                    weather: weather,
                    calendarSnapshot: calendarSnapshot
                )
                .padding(16)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: settings.placement.alignment
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xxl, style: .continuous))
        }
        .task(id: PreviewLoadKey(source: settings.source, reloadToken: reloadToken)) {
            await loadImage()
        }
    }

    private struct PreviewLoadKey: Equatable {
        let source: PhotoWidgetSettings.Source
        let reloadToken: Bool
    }

    private func loadImage() async {
        let snapshot = PhotoWidgetSnapshot.read(kind: kind)
        let index = PhotoWidgetSnapshot.frameIndex(
            at: .now, count: snapshot.frames.count, rotation: settings.rotation
        )
        guard let index, let url = snapshot.imageURL(at: index, kind: kind) else {
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
