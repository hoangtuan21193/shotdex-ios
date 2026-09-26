import SwiftUI

/// Everything one photo widget shows — its picture, what is written over it,
/// and how — written to the App Group the widget reads.
///
/// One screen for one design. Every row is offered to every design — the
/// weather and the calendar are toggles, not a property of which widget this
/// is. The preview at the top is the widget's own `PhotoWidgetFace` over the
/// widget's own background, at the medium family's proportions — the size the
/// point values are measured against.
struct PhotoWidgetSettingsScreen: View {
    let designId: String

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
    @State private var isRefreshingWeather = false
    @State private var previewFamily: PhotoWidgetPreviewFamily = .medium
    @State private var calendarAccess: CalendarSnapshotWriter.Access = .notDetermined
    @State private var locationAccess: WidgetLocationProvider.Access = .notDetermined
    @State private var previewImage: Image?
    @State private var previewImageAspect: Double = 1
    @State private var previewLuma: PhotoWidgetLumaGrid?
    @State private var selectedComponent: PhotoWidgetComponent?

    private var store: PhotoWidgetSettingsStore { dependencies.photoWidgetSettings }
    private var designName: String { store.design(id: designId).name }
    private var settings: PhotoWidgetSettings { store.settings(for: designId) }

    /// The preview is pinned above the options rather than scrolling with
    /// them: it is what every row below is editing, and it is where the text
    /// is dragged and the photo pinched — a control that scrolls out from
    /// under the finger is not a control.
    var body: some View {
        VStack(spacing: 0) {
            previewHeader
            Divider()
            optionsList
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(designName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPhotoPickerPresented) {
            PhotoWidgetPhotoPicker { assetId in
                store.update(designId) { $0.source = .photo(assetId: assetId) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isAlbumPickerPresented) {
            NavigationStack {
                PhotoWidgetAlbumPicker { collectionId, title in
                    store.update(designId) { $0.source = .album(collectionId: collectionId, title: title) }
                }
            }
            .environment(dependencies)
        }
        .sheet(isPresented: $isFontPickerPresented) {
            PhotoWidgetFontPicker { choice in
                store.update(designId) {
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
            // The Home Screen's own menu writes the same settings, so the
            // screen re-reads them on the way in rather than showing a copy
            // from launch.
            store.reloadFromDisk()
            weather = WeatherSnapshot.read()
            calendarAccess = dependencies.calendarWidgetWriter.access
            locationAccess = dependencies.widgetLocation.access
            // The preview shows today's events, so the events are read while
            // it is on screen — a widget that is not placed yet has never had
            // them read for it.
            if settings.showsCalendar, calendarAccess == .granted {
                await dependencies.calendarWidgetWriter.write(force: true)
            }
            calendarSnapshot = CalendarSnapshot.read()
        }
        .task(id: PreviewLoadKey(source: settings.source, isRendering: store.isRendering(designId))) {
            await loadPreviewImage()
        }
        .onDisappear { store.saveNow() }
    }

    private struct PreviewLoadKey: Equatable {
        let source: PhotoWidgetSettings.Source
        let isRendering: Bool
    }

    /// Loads the same file the widget reads, so the preview is framed against
    /// the picture the widget will actually show.
    private func loadPreviewImage() async {
        // The same rule the widget uses to find its frames, so the preview
        // cannot show one picture while the Home Screen shows another.
        let resolved = PhotoWidgetResolvedConfiguration.resolve(
            designId: designId,
            source: settings.source,
            snapshot: { PhotoWidgetSnapshot.read(directoryName: $0) }
        )
        let snapshot = PhotoWidgetSnapshot.read(directoryName: resolved.frameDirectoryName)
        let index = PhotoWidgetSnapshot.frameIndex(
            at: .now, count: snapshot.frames.count, rotation: settings.rotation
        )
        guard let index,
              let url = snapshot.imageURL(at: index, directoryName: resolved.frameDirectoryName)
        else {
            previewImage = nil
            previewLuma = nil
            return
        }
        // Decoded and measured off the main actor: the brightness grid is one
        // 16×16 draw, but the decode that feeds it is not.
        let loaded = await Task.detached(priority: .userInitiated) {
            () -> (image: UIImage, luma: PhotoWidgetLumaGrid?)? in
            guard let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data)
            else { return nil }
            return (image, image.cgImage.flatMap(PhotoWidgetLumaGrid.make(from:)))
        }.value
        previewImage = loaded.map { Image(uiImage: $0.image) }
        previewImageAspect = loaded.map {
            $0.image.size.height > 0 ? Double($0.image.size.width / $0.image.size.height) : 1
        } ?? 1
        previewLuma = loaded?.luma
    }

    // MARK: Preview header

    private var previewHeader: some View {
        VStack(spacing: 10) {
            PhotoWidgetPreview(
                designName: designName,
                settings: settings,
                date: previewDate,
                weather: weather,
                calendarSnapshot: calendarSnapshot,
                family: previewFamily,
                image: previewImage,
                imageAspectRatio: previewImageAspect,
                lumaGrid: previewLuma,
                selection: $selectedComponent,
                onMove: { component, anchor in
                    store.update(designId) {
                        $0.setAnchor(
                            anchor,
                            for: component,
                            in: PhotoWidgetComponent.components(settings: $0)
                        )
                    }
                },
                onResize: { component, scale in
                    store.update(designId) { $0.setScale(scale, for: component) }
                },
                onPhotoTransformChange: { scale, offsetX, offsetY in
                    store.update(designId) {
                        $0.photoScale = scale
                        $0.photoOffsetX = offsetX
                        $0.photoOffsetY = offsetY
                    }
                }
            )
            .frame(height: previewFamily == .large ? 280 : 158)

            Picker("Widget Size", selection: $previewFamily) {
                ForEach(PhotoWidgetPreviewFamily.allCases) { family in
                    Text(family.title).tag(family)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 329)

            // Aiming at a line of text on a 158pt preview is a poor way to
            // choose one. These chips select the same thing without aiming,
            // and they double as the list of what a widget is made of.
            elementChips

            Text(hintText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.top, AppTheme.Spacing.md)
        .padding(.bottom, AppTheme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    /// Says what the finger under it can do, and changes as the user selects
    /// something — a preview with no instructions reads as a picture.
    ///
    /// The **Photo** chip is the background itself. It is a chip rather than a
    /// hidden rule because "drag moves the photo when nothing is selected" is
    /// true but invisible, and because it is how the user gets back to the
    /// picture without hunting for a gap between two lines of text.
    private var elementChips: some View {
        // Five chips at an accessibility text size do not fit a phone's width,
        // and a clipped chip row hides the piece the user came to select.
        ViewThatFits(in: .horizontal) {
            chipRow.frame(maxWidth: .infinity)
            ScrollView(.horizontal, showsIndicators: false) {
                chipRow.padding(.horizontal, AppTheme.Spacing.xs)
            }
        }
    }

    private var chipRow: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            chip(title: "Photo", isSelected: selectedComponent == nil) {
                selectedComponent = nil
            }
            ForEach(PhotoWidgetComponent.components(settings: settings)) { component in
                chip(
                    title: component.title,
                    isSelected: selectedComponent == component
                ) {
                    selectedComponent = selectedComponent == component ? nil : component
                }
            }
        }
    }

    /// The capsule reads at 32pt; the button is 44pt so it can be hit.
    private func chip(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .frame(height: AppTheme.Size.pillHeightLight)
                .background(
                    isSelected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemFill),
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? Color.accentColor : .clear, lineWidth: 1
                    )
                )
                .frame(height: AppTheme.Size.minTouch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var hintText: String {
        if let selectedComponent {
            return "\(selectedComponent.title) selected. Drag it on the preview, pinch to resize, or use the controls below."
        }
        return isNoneSource
            ? "Photo selected — choose one below to place it behind. Tap a line on the preview to move or resize it instead."
            : "Photo selected. Drag the preview to reframe it, pinch to zoom. Tap a line to move or resize that line instead."
    }

    /// Picking a line is also a request to go where that line is edited.
    ///
    /// Arrangement is the last of seven sections, so selecting the weather
    /// block on the preview used to leave its nudge pad and size slider five
    /// sections below the fold, with nothing saying they were there. Widgy
    /// names the same move "Quick Assignment: assign directly from Preview";
    /// the History panel in the photo editor already does it here.
    private var optionsList: some View {
        ScrollViewReader { proxy in
            List {
                photoSection
                timeSection
                calendarSection
                weatherSection
                typefaceSection
                colourSection
                arrangementSection
                    .id(Self.arrangementAnchor)
            }
            .listStyle(.insetGrouped)
            .onChange(of: selectedComponent) { previous, current in
                // Only on the way *into* a selection. Deselecting — which a
                // tap on the photo does — must not yank the list anywhere.
                guard previous == nil, current != nil else { return }
                withAnimation(AppTheme.Motion.standard) {
                    proxy.scrollTo(Self.arrangementAnchor, anchor: .top)
                }
            }
        }
    }

    private static let arrangementAnchor = "arrangement"

    // MARK: Preview

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
                    store.renderPhotos(for: designId)
                } label: {
                    LabeledContent("Refresh Now") {
                        if store.isRendering(designId) {
                            ProgressView()
                        }
                    }
                }
                .disabled(store.isRendering(designId))
                Button("Remove Photo", role: .destructive) {
                    store.update(designId) { $0.source = .none }
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
                    set: { value in store.update(designId) { $0.photoDimming = value } }
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
                    store.update(designId) { $0.timeSize = value }
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
                store.update(designId) { $0.dateSize = value }
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
            Toggle("Show Calendar", isOn: boolBinding(\.showsCalendar))
            if settings.showsCalendar {
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
                        set: { value in store.update(designId) { $0.maximumEventCount = value } }
                    ),
                    in: PhotoWidgetSettings.eventCountRange
                )
                .monospacedDigit()
                LabeledContent("Calendar Access", value: calendarAccessLabel)
                if calendarAccess != .granted {
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
                    accessExplanation(
                        "Listing today's events needs permission to read your calendars. ShotDex asks only when you tap this, and reads nothing until you allow it."
                    )
                }
            }
            }
        } header: {
            Text("Calendar")
        } footer: {
            Text("The month is worked out on this iPhone and needs no permission. Listing today's events reads your calendars — only their titles, times and colours are copied for the widget, and only for today. Nothing is read until you allow it here.")
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
            Toggle("Show Weather", isOn: boolBinding(\.showsWeather))
            if settings.showsWeather {
            Picker("Units", selection: temperatureUnitBinding) {
                ForEach(PhotoWidgetSettings.TemperatureUnit.allCases) { unit in
                    Text(unit.title).tag(unit)
                }
            }
            Toggle("Show High and Low", isOn: boolBinding(\.showsHighLow))
            Toggle("Show Place", isOn: boolBinding(\.showsWeatherPlace))
            LabeledContent("Location Access", value: locationAccessLabel)
            if locationAccess != .granted {
                Button(locationAccess == .denied ? "Open Settings" : "Allow Location Access") {
                    if locationAccess == .denied {
                        openAppSettings()
                    } else {
                        Task {
                            await dependencies.widgetLocation.requestAuthorization()
                            locationAccess = dependencies.widgetLocation.access
                            guard locationAccess == .granted else { return }
                            await refreshWeather()
                        }
                    }
                }
                accessExplanation(
                    "The weather is for wherever you are, so fetching it needs your location. ShotDex asks only when you tap this, rounds the coordinate to about a kilometre, and never stores it."
                )
            }
            LabeledContent("Last Reading", value: weatherAgeLabel)
            Button {
                Task { await refreshWeather() }
            } label: {
                LabeledContent("Update Now") {
                    if isRefreshingWeather { ProgressView() }
                }
            }
            .disabled(isRefreshingWeather || locationAccess != .granted)
            }
        } header: {
            Text("Weather")
        } footer: {
            Text("ShotDex asks for your location only when you allow it here, rounds it to about a kilometre, and fetches the current conditions from Open-Meteo. It does this only while a weather widget is on your Home Screen, and it sends nothing else.")
        }
    }

    private var weatherAgeLabel: String {
        guard let weather else { return "None yet" }
        return weather.updatedAt.formatted(date: .omitted, time: .shortened)
    }

    private var locationAccessLabel: String {
        switch locationAccess {
        case .granted: "Allowed"
        case .denied: "Denied"
        case .notDetermined: "Not Requested"
        }
    }

    private func refreshWeather() async {
        isRefreshingWeather = true
        await WeatherSnapshotWriter(location: dependencies.widgetLocation).write(force: true)
        weather = WeatherSnapshot.read()
        isRefreshingWeather = false
    }

    /// The sentence that sits above an Allow button, so the permission is
    /// explained where it is granted rather than only in a section footer.
    private func accessExplanation(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
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
                    store.update(designId) {
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
            // Three rows of three: nine 44pt targets do not fit one grouped
            // row, and four columns left Purple alone on a row of its own.
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                spacing: 12
            ) {
                // Smart first, because it is the one answer that is right on
                // more than one photo, and an album rotates its photos.
                swatch(hex: WidgetTextColor.smartHex)
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
            Text("Smart measures the part of the photo under each line and paints it white or black to suit — worth having on an album, where the photo changes under the same text. Shadow suits most photos; Scrim darkens a band behind the text, for photos with a busy sky or bright detail under it.")
        }
    }

    private func swatch(hex: String) -> some View {
        let isSelected = settings.textColorHex.caseInsensitiveCompare(hex) == .orderedSame
        return Button {
            store.update(designId) { $0.textColorHex = hex }
        } label: {
            swatchFill(hex: hex)
                .frame(width: 30, height: 30)
                .overlay(
                    Circle().strokeBorder(.secondary.opacity(0.35), lineWidth: 1)
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary, lineWidth: isSelected ? 2 : 0)
                        .padding(-4)
                )
                // Inside the label, not around the button: a plain button is
                // only hittable where its label draws, so a 30pt disc in a
                // 44pt slot was a 38pt target (measured).
                .frame(maxWidth: .infinity, minHeight: AppTheme.Size.minTouch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(colourName(hex: hex))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// A colour needs a name a screen reader can say; a hex code read out
    /// digit by digit is not one.
    /// Smart is drawn as a disc split white over black: it is not one colour,
    /// it is the choice between the two, and a grey circle would read as a
    /// colour in its own right.
    @ViewBuilder
    private func swatchFill(hex: String) -> some View {
        if WidgetTextColor.isSmart(hex: hex) {
            Circle()
                .fill(
                    // Two hard stops, not a blend: the swatch stands for a
                    // choice between two colours, and a grey middle would read
                    // as a third one.
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0.5),
                            .init(color: .black, location: 0.5),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        } else {
            Circle().fill(WidgetTextColor.color(hex: hex))
        }
    }

    private func colourName(hex: String) -> String {
        if WidgetTextColor.isSmart(hex: hex) { return "Smart" }
        return switch hex.uppercased() {
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

    // MARK: Arrangement

    /// The two things the preview does by touch, with a way back when a drag
    /// or a pinch went somewhere the user did not want.
    private var arrangementSection: some View {
        Section {
            if let selectedComponent {
                LabeledContent("Selected", value: selectedComponent.title)
                LabeledContent("Position", value: anchorLabel(for: selectedComponent))
                nudgePad(for: selectedComponent)
                sizeRow(for: selectedComponent)
                Button("Centre \(selectedComponent.title)") {
                    move(selectedComponent, to: .center)
                }
                Button("Deselect") { self.selectedComponent = nil }
            } else {
                LabeledContent("Text Position", value: anchorLabel(for: nil))
                Text("Pick a line above to move or resize it on its own.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !settings.componentAnchors.isEmpty || !settings.componentScales.isEmpty {
                Button("Stack Everything Together", role: .destructive) {
                    store.update(designId) { $0.resetComponentAnchors() }
                    selectedComponent = nil
                }
            }
            if !isNoneSource {
                LabeledContent("Photo Zoom", value: "\(String(format: "%.1f", settings.photoScale))×")
                    .monospacedDigit()
                Button("Reset Photo Framing", role: .destructive) {
                    store.update(designId) {
                        $0.photoScale = 1
                        $0.photoOffsetX = 0
                        $0.photoOffsetY = 0
                    }
                }
                .disabled(settings.photoScale == 1 && settings.photoOffsetX == 0 && settings.photoOffsetY == 0)
            }
        } header: {
            Text("Arrangement")
        } footer: {
            Text("Drag a line on the preview to move it, and pinch it to resize. Guides appear when it lines up with the middle, an edge, or another line. The arrows below move it a step at a time, for when a finger is not precise enough. Drag the photo itself — or tap the Photo chip first — to reframe it.")
        }
    }

    /// Four arrows and a centre. A drag is faster; this is what makes the last
    /// two percent reachable, and the only way to place a line with the
    /// keyboard or with VoiceOver.
    private func nudgePad(for component: PhotoWidgetComponent) -> some View {
        let anchor = settings.anchor(for: component)
        return VStack(spacing: 6) {
            nudgeButton("chevron.up", "Move up") {
                move(component, to: .init(x: anchor.x, y: anchor.y - Self.nudge))
            }
            HStack(spacing: 6) {
                nudgeButton("chevron.left", "Move left") {
                    move(component, to: .init(x: anchor.x - Self.nudge, y: anchor.y))
                }
                nudgeButton("scope", "Centre") { move(component, to: .center) }
                nudgeButton("chevron.right", "Move right") {
                    move(component, to: .init(x: anchor.x + Self.nudge, y: anchor.y))
                }
            }
            nudgeButton("chevron.down", "Move down") {
                move(component, to: .init(x: anchor.x, y: anchor.y + Self.nudge))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    /// A twentieth of the free space: small enough to be a correction, big
    /// enough that reaching the far side does not take fifty taps.
    private static let nudge: Double = 0.05

    private func nudgeButton(
        _ systemImage: String,
        _ label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 44, height: 36)
                .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func sizeRow(for component: PhotoWidgetComponent) -> some View {
        let scale = settings.scale(for: component)
        return VStack(alignment: .leading, spacing: 4) {
            LabeledContent("\(component.title) Size", value: "\(Int(scale * 100))%")
                .monospacedDigit()
            Slider(
                value: Binding(
                    get: { scale },
                    set: { value in store.update(designId) { $0.setScale(value, for: component) } }
                ),
                in: PhotoWidgetSettings.componentScaleRange
            )
            .accessibilityLabel("\(component.title) size")
        }
    }

    private func move(_ component: PhotoWidgetComponent, to anchor: PhotoWidgetSettings.Anchor) {
        store.update(designId) {
            $0.setAnchor(
                anchor,
                for: component,
                in: PhotoWidgetComponent.components(settings: $0)
            )
        }
    }

    /// Where a piece sits, in words: a fraction means nothing read aloud.
    private func anchorLabel(for component: PhotoWidgetComponent?) -> String {
        let anchor = component.map { settings.anchor(for: $0) } ?? settings.anchor
        let horizontal = anchor.isLeading ? "Left" : (anchor.isTrailing ? "Right" : "Centre")
        let vertical = anchor.y < 0.34 ? "Top" : (anchor.y > 0.66 ? "Bottom" : "Middle")
        return "\(vertical) \(horizontal)"
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
            set: { value in store.update(designId) { $0[keyPath: keyPath] = value } }
        )
    }

    private var timeFormatBinding: Binding<String> {
        Binding(
            get: { settings.timeFormat },
            set: { value in store.update(designId) { $0.timeFormat = value } }
        )
    }

    private var dateFormatBinding: Binding<String> {
        Binding(
            get: { settings.dateFormat },
            set: { value in store.update(designId) { $0.dateFormat = value } }
        )
    }

    private var rotationBinding: Binding<PhotoWidgetSettings.Rotation> {
        Binding(
            get: { settings.rotation },
            set: { value in store.update(designId) { $0.rotation = value } }
        )
    }

    private var legibilityBinding: Binding<PhotoWidgetSettings.Legibility> {
        Binding(
            get: { settings.legibility },
            set: { value in store.update(designId) { $0.legibility = value } }
        )
    }

    private var calendarStyleBinding: Binding<PhotoWidgetSettings.CalendarStyle> {
        Binding(
            get: { settings.calendarStyle },
            set: { value in store.update(designId) { $0.calendarStyle = value } }
        )
    }

    private var temperatureUnitBinding: Binding<PhotoWidgetSettings.TemperatureUnit> {
        Binding(
            get: { settings.temperatureUnit },
            set: { value in store.update(designId) { $0.temperatureUnit = value } }
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
                store.update(designId) { $0.timeFormat = "" }
            } else {
                store.update(designId) { $0.dateFormat = "" }
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
