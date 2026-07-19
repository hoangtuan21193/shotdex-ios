import Charts
import SwiftUI

/// Statistics tab: summary cards + usage charts, all computed in SQLite.
struct StatisticsScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppNavigation.self) private var navigation
    @Environment(PhotoLibraryService.self) private var photoLibrary

    @State private var controller: StatsController?
    @AppStorage("stats.focalEquivalent") private var focalEquivalent = false
    @State private var isRangePickerPresented = false
    /// Last applied custom range, so re-opening the picker restores it.
    @State private var customDays: ClosedRange<Date>?

    var body: some View {
        Group {
            if let controller {
                content(controller)
            } else {
                ProgressView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                SettingsDrawerButton()
            }
            // Separate ToolbarItem so it gets its own Liquid Glass circle
            // on iOS 26 instead of sharing a capsule with the drawer button.
            ToolbarItem(placement: .topBarTrailing) {
                if let controller {
                    scopeMenu(controller)
                }
            }
        }
        .sheet(isPresented: $isRangePickerPresented) {
            if let controller {
                DateRangePickerSheet(
                    earliestDate: controller.earliestDate,
                    initialRange: customDays
                ) { days in
                    customDays = days
                    controller.scope = .custom(days: days)
                }
            }
        }
        .task {
            if controller == nil {
                let newController = StatsController(dependencies: dependencies)
                controller = newController
            }
            controller?.load()
        }
    }

    @ViewBuilder
    private func content(_ controller: StatsController) -> some View {
        List {
            if controller.summary.totalPhotos == 0 {
                Section {
                    ContentUnavailableView(
                        "No Indexed Photos",
                        systemImage: "chart.bar.xaxis",
                        description: Text("Statistics appear after your library has been indexed.")
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                summarySection(controller)
                cameraSection(controller)
                lensSection(controller)
                focalSection(controller)
                sensorSection(controller)
                exposureSection(controller)
            }

            // Space for the floating chrome (custom bar, pre-iOS 26).
            if #unavailable(iOS 26.0) {
                Section {
                    Color.clear.frame(height: 60)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: Date scope menu

    /// Toolbar calendar button: presets plus the custom range picker. Shows
    /// the active scope's title beside the icon so the current selection is
    /// always visible.
    private func scopeMenu(_ controller: StatsController) -> some View {
        Menu {
            scopeMenuButton("All Time", scope: .allTime, controller: controller)
            scopeMenuButton("This Year", scope: .thisYear, controller: controller)
            scopeMenuButton("This Month", scope: .thisMonth, controller: controller)
            Divider()
            Button {
                isRangePickerPresented = true
            } label: {
                let isCustom = if case .custom = controller.scope { true } else { false }
                if isCustom {
                    Label(controller.scope.title, systemImage: "checkmark")
                } else {
                    Text("Custom Range…")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                Text(controller.scope.title)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
            }
        }
        .accessibilityLabel("Date range: \(controller.scope.title)")
    }

    private func scopeMenuButton(
        _ title: String,
        scope: StatsDateScope,
        controller: StatsController
    ) -> some View {
        Button {
            controller.scope = scope
        } label: {
            if controller.scope == scope {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    // MARK: Summary

    private func summarySection(_ controller: StatsController) -> some View {
        Section {
            summaryRows(controller)
        } header: {
            Text("Summary")
        } footer: {
            if controller.scope != .allTime && controller.undatedCount > 0 {
                Text("\(controller.undatedCount) photos without a capture date appear only in All Time.")
            }
        }
    }

    @ViewBuilder
    private func summaryRows(_ controller: StatsController) -> some View {
        LabeledContent("Total Photos", value: "\(controller.summary.totalPhotos)")
        if let camera = controller.summary.mostUsedCamera {
            LabeledContent("Most Used Camera", value: camera)
        }
        if let lens = controller.summary.mostUsedLens {
            LabeledContent("Most Used Lens", value: lens)
        }
        if let focal = controller.summary.mostUsedFocalLength.flatMap(FormatUtils.focalLength) {
            LabeledContent("Most Used Focal Length", value: focal)
        }
        if let equivalent = controller.summary.mostUsedEquivalentFocalLength.flatMap(FormatUtils.focalLength) {
            LabeledContent("Most Used FF Equivalent", value: equivalent)
        }
        if let format = controller.summary.mostUsedSensorFormat {
            LabeledContent("Most Used Sensor Format", value: format.displayName)
        }
    }

    // MARK: Camera

    @ViewBuilder
    private func cameraSection(_ controller: StatsController) -> some View {
        if !controller.cameraUsage.isEmpty {
            Section {
                ForEach(controller.cameraUsage.prefix(8)) { usage in
                    usageRow(usage) {
                        var criteria = FilterCriteria()
                        criteria.cameraBodies = [usage.name]
                        navigation.openLibrary(with: criteria)
                    }
                }
                if !controller.cameraTrend.isEmpty {
                    Chart(controller.cameraTrend) { point in
                        LineMark(
                            x: .value("Month", point.month),
                            y: .value("Photos", point.count)
                        )
                        .foregroundStyle(by: .value("Camera", point.name))
                    }
                    .chartForegroundStyleScale(range: ChartPalette.colors)
                    .frame(height: 180)
                    .padding(.vertical, 4)
                    .accessibilityLabel("Camera usage trend over time")
                }
            } header: {
                Text("Camera Body Usage")
            } footer: {
                unknownFootnote(count: controller.cameraUnknownCount, field: "camera")
            }
        }
    }

    // MARK: Lens

    @ViewBuilder
    private func lensSection(_ controller: StatsController) -> some View {
        if !controller.lensUsage.isEmpty {
            Section {
                ForEach(controller.lensUsage.prefix(8)) { usage in
                    usageRow(usage) {
                        var criteria = FilterCriteria()
                        criteria.lenses = [usage.name]
                        navigation.openLibrary(with: criteria)
                    }
                }
            } header: {
                Text("Lens Usage")
            } footer: {
                unknownFootnote(count: controller.lensUnknownCount, field: "lens")
            }
        }
    }

    // MARK: Focal length

    @ViewBuilder
    private func focalSection(_ controller: StatsController) -> some View {
        let histogram = focalEquivalent
            ? controller.focalHistogramEquivalent
            : controller.focalHistogramActual
        if histogram.contains(where: { $0.count > 0 }) {
            Section {
                Picker("Focal Measure", selection: $focalEquivalent) {
                    Text("Actual").tag(false)
                    Text("FF Equivalent").tag(true)
                }
                .pickerStyle(.segmented)

                horizontalBarChart(histogram, label: "Focal length histogram")
            } header: {
                Text("Focal Length Usage (mm)")
            }
        }
    }

    // MARK: Sensor format

    @ViewBuilder
    private func sensorSection(_ controller: StatsController) -> some View {
        if !controller.sensorFormatUsage.isEmpty {
            Section {
                Chart(controller.sensorFormatUsage) { usage in
                    SectorMark(
                        angle: .value("Photos", usage.count),
                        innerRadius: .ratio(0.6),
                        angularInset: 1.5
                    )
                    .foregroundStyle(by: .value("Format", usage.name))
                    .cornerRadius(3)
                }
                .chartForegroundStyleScale(range: ChartPalette.colors)
                .frame(height: 220)
                .padding(.vertical, 4)
                .accessibilityLabel("Sensor format distribution")

                ForEach(controller.sensorFormatUsage) { usage in
                    usageRow(usage) {
                        if let format = SensorFormat(rawValue: usage.name) {
                            var criteria = FilterCriteria()
                            criteria.sensorFormats = [format]
                            navigation.openLibrary(with: criteria)
                        }
                    }
                }
            } header: {
                Text("Sensor Format Usage")
            } footer: {
                unknownFootnote(count: controller.sensorUnknownCount, field: "sensor format")
            }
        }
    }

    // MARK: Exposure

    @ViewBuilder
    private func exposureSection(_ controller: StatsController) -> some View {
        if controller.isoHistogram.contains(where: { $0.count > 0 }) {
            Section("ISO Usage") {
                if let mostCommon = controller.isoStats.mostCommon {
                    LabeledContent("Most Common", value: "ISO \(Int(mostCommon))")
                }
                if let average = controller.isoStats.average {
                    LabeledContent("Average", value: "ISO \(Int(average))")
                }
                if let median = controller.isoStats.median {
                    LabeledContent("Median", value: "ISO \(Int(median))")
                }
                histogramChart(controller.isoHistogram, label: "ISO histogram")
            }
        }

        if controller.apertureHistogram.contains(where: { $0.count > 0 }) {
            Section("Aperture Usage") {
                if let mostCommon = controller.apertureMostCommon.flatMap(FormatUtils.aperture) {
                    LabeledContent("Most Common", value: mostCommon)
                }
                histogramChart(controller.apertureHistogram, label: "Aperture histogram")
            }
        }

        if controller.shutterHistogram.contains(where: { $0.count > 0 }) {
            Section("Shutter Speed Usage") {
                if let mostCommon = controller.shutterMostCommon.flatMap(FormatUtils.shutterSpeed) {
                    LabeledContent("Most Common", value: mostCommon)
                }
                if let slowShare = controller.slowShutterShare {
                    LabeledContent("Slower than 1/focal", value: String(format: "%.0f%%", slowShare))
                }
                histogramChart(controller.shutterHistogram, label: "Shutter speed histogram")
            }
        }
    }

    // MARK: Shared pieces

    private func histogramChart(_ histogram: [HistogramBucket], label: String) -> some View {
        horizontalBarChart(histogram, label: label)
    }

    /// Horizontal bars — one row per bucket, so the category labels sit on
    /// the leading edge with room to breathe instead of colliding on the
    /// X axis. Height scales with the bucket count.
    private func horizontalBarChart(_ histogram: [HistogramBucket], label: String) -> some View {
        Chart(histogram) { bucket in
            BarMark(
                x: .value("Photos", bucket.count),
                y: .value("Range", bucket.label)
            )
            .foregroundStyle(ChartPalette.bar)
            .cornerRadius(4)
        }
        .chartYAxis {
            AxisMarks(preset: .aligned) {
                AxisValueLabel()
            }
        }
        .frame(height: CGFloat(histogram.count) * 28 + 20)
        .padding(.vertical, 4)
        .accessibilityLabel(label)
    }

    /// Photos missing the field are excluded from the lists/charts above;
    /// this footnote keeps the count visible without an "Unknown" row.
    @ViewBuilder
    private func unknownFootnote(count: Int, field: String) -> some View {
        if count > 0 {
            Text("\(count) photos without \(field) info.")
        }
    }

    private func usageRow(_ usage: UsageCount, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            usageRowContent(usage, labelStyle: Color(.label))
        }
        .accessibilityLabel("\(usage.name), \(usage.count) photos, \(Int(usage.percentage)) percent. Opens Library filtered.")
    }

    private func usageRowContent(_ usage: UsageCount, labelStyle: some ShapeStyle) -> some View {
        HStack {
            Text(usage.name)
                .foregroundStyle(labelStyle)
                .lineLimit(1)
            Spacer()
            Text("\(usage.count)")
                .foregroundStyle(.secondary)
            Text(String(format: "%.0f%%", usage.percentage))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    return NavigationStack {
        StatisticsScreen()
    }
    .environment(dependencies)
    .environment(dependencies.photoLibrary)
    .environment(AppNavigation())
}
