import SwiftUI

/// Lists cameras whose sensor format couldn't be resolved and lets the
/// user map them manually. Mappings persist and rewrite indexed rows.
struct CameraDatabaseScreen: View {
    @Environment(AppDependencies.self) private var dependencies

    let libraryModel: LibraryModel?

    @State private var unknownModels: [String] = []

    var body: some View {
        List {
            if unknownModels.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Unknown Cameras",
                        systemImage: "checkmark.circle",
                        description: Text("Every camera in your library has a known sensor format.")
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(unknownModels, id: \.self) { model in
                        NavigationLink(model) {
                            SensorMappingScreen(cameraModel: model) {
                                refresh()
                                libraryModel?.reload()
                            }
                        }
                    }
                } footer: {
                    Text("Pick the sensor format for each camera to include it in statistics and equivalent focal length calculations.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Unknown Cameras")
        .navigationBarTitleDisplayMode(.inline)
        .task { refresh() }
    }

    private func refresh() {
        unknownModels = (try? dependencies.metadataStore.unknownCameraModels()) ?? []
    }
}

/// Sensor format picker for one unresolved camera model.
struct SensorMappingScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss

    let cameraModel: String
    var onSaved: () -> Void

    @State private var selectedFormat: SensorFormat = .unknown

    var body: some View {
        List {
            Section {
                ForEach(SensorFormat.allCases.filter { $0 != .unknown }) { format in
                    Button {
                        selectedFormat = format
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(format.displayName)
                                    .foregroundStyle(Color(.label))
                                if let crop = format.typicalCropFactor {
                                    Text(String(format: "%.2f× crop", crop))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if selectedFormat == format {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            } header: {
                Text("Sensor Format")
            } footer: {
                Text("The typical crop factor of the chosen format is used for full-frame equivalent focal lengths.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(cameraModel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    save()
                }
                .fontWeight(.semibold)
                .disabled(selectedFormat == .unknown)
            }
        }
    }

    private func save() {
        let mapping = CustomCameraMapping(
            normalizedCameraModel: cameraModel,
            sensorFormat: selectedFormat.rawValue,
            cropFactor: selectedFormat.typicalCropFactor
        )
        try? dependencies.metadataStore.applyCustomMapping(mapping)
        onSaved()
        dismiss()
    }
}
