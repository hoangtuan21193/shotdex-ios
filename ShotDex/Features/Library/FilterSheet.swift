import SwiftUI

/// Native filter sheet (medium/large detents). Edits a draft criteria and
/// applies on dismiss so cancel is cheap.
struct FilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var criteria: FilterCriteria
    let availableBrands: [String]
    let availableBodies: [String]
    let availableLenses: [String]

    @State private var draft: FilterCriteria = .empty

    var body: some View {
        NavigationStack {
            List {
                multiSelectSection("Camera Brand", options: availableBrands, selection: $draft.cameraBrands)
                multiSelectSection("Camera Body", options: availableBodies, selection: $draft.cameraBodies)
                multiSelectSection("Lens", options: availableLenses, selection: $draft.lenses)
                sensorFormatSection
                quickGroupSection(
                    "ISO",
                    groups: ISOQuickGroup.allCases.map { ($0.rawValue, $0.range) },
                    range: $draft.isoRange
                )
                quickGroupSection(
                    "Shutter Speed",
                    groups: ShutterQuickGroup.allCases.map { ($0.rawValue, $0.range) },
                    range: $draft.shutterRange
                )
                quickGroupSection(
                    "Aperture",
                    groups: ApertureQuickGroup.allCases.map { ($0.rawValue, $0.range) },
                    range: $draft.apertureRange
                )
                focalSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear All") { draft = .empty }
                        .disabled(draft.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") {
                        criteria = draft
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear { draft = criteria }
    }

    // MARK: Sections

    private func multiSelectSection(
        _ title: String,
        options: [String],
        selection: Binding<Set<String>>
    ) -> some View {
        Section(title) {
            if options.isEmpty {
                Text("No values indexed yet")
                    .foregroundStyle(.secondary)
            }
            ForEach(options, id: \.self) { option in
                Button {
                    if selection.wrappedValue.contains(option) {
                        selection.wrappedValue.remove(option)
                    } else {
                        selection.wrappedValue.insert(option)
                    }
                } label: {
                    HStack {
                        Text(option)
                            .foregroundStyle(Color(.label))
                        Spacer()
                        if selection.wrappedValue.contains(option) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
    }

    private var sensorFormatSection: some View {
        Section("Sensor Format") {
            ForEach(SensorFormat.allCases) { format in
                Button {
                    if draft.sensorFormats.contains(format) {
                        draft.sensorFormats.remove(format)
                    } else {
                        draft.sensorFormats.insert(format)
                    }
                } label: {
                    HStack {
                        Text(format.displayName)
                            .foregroundStyle(Color(.label))
                        Spacer()
                        if draft.sensorFormats.contains(format) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
    }

    private func quickGroupSection(
        _ title: String,
        groups: [(label: String, range: NumericRangeFilter)],
        range: Binding<NumericRangeFilter>
    ) -> some View {
        Section(title) {
            ForEach(groups, id: \.label) { group in
                Button {
                    range.wrappedValue = range.wrappedValue == group.range
                        ? NumericRangeFilter()
                        : group.range
                } label: {
                    HStack {
                        Text(group.label)
                            .foregroundStyle(Color(.label))
                        Spacer()
                        if range.wrappedValue == group.range {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
    }

    private var focalSection: some View {
        Section {
            Picker("Measure", selection: $draft.focalLengthMode) {
                Text("Actual").tag(FocalLengthMode.actual)
                Text("FF Equivalent").tag(FocalLengthMode.equivalent)
            }
            .pickerStyle(.segmented)

            ForEach(FocalAngleBucket.allCases) { bucket in
                Button {
                    draft.focalRange = draft.focalRange == bucket.range
                        ? NumericRangeFilter()
                        : bucket.range
                } label: {
                    HStack {
                        Text(bucket.rawValue)
                            .foregroundStyle(Color(.label))
                        Spacer()
                        if draft.focalRange == bucket.range {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        } header: {
            Text("Focal Length")
        } footer: {
            Text("Angle-of-view groups use full-frame equivalent focal lengths.")
        }
    }
}
