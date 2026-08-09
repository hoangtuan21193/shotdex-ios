import SwiftUI

struct CompressionPresetsScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var editorPreset: ResizePreset?

    var body: some View {
        List {
            Section("Built-in") {
                ForEach(ResizePreset.builtIns) { preset in
                    presetRow(preset)
                }
            }
            Section {
                ForEach(dependencies.compressionPresets.customPresets) { preset in
                    Button {
                        editorPreset = preset
                    } label: {
                        presetRow(preset)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indexes in
                    let ids = indexes.map {
                        dependencies.compressionPresets.customPresets[$0].id
                    }
                    for id in ids {
                        dependencies.compressionPresets.delete(id: id)
                    }
                }

                Button {
                    editorPreset = ResizePreset(
                        name: "",
                        kind: .exact,
                        width: 1_080,
                        height: 1_350,
                        cropMode: .fill,
                        quality: 0.8,
                        format: .jpeg
                    )
                } label: {
                    Label("Add Preset", systemImage: "plus")
                }
            } header: {
                Text("Custom")
            } footer: {
                Text("Custom presets store a name, pixel dimensions, Fill or Fit behavior, quality and output format.")
            }
        }
        .navigationTitle("Compression Presets")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editorPreset) { preset in
            CompressionPresetEditor(
                preset: preset,
                onSave: {
                    dependencies.compressionPresets.upsert($0)
                    editorPreset = nil
                }
            )
        }
    }

    private func presetRow(_ preset: ResizePreset) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.name)
                    .foregroundStyle(.primary)
                Text(detail(for: preset))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !preset.isBuiltIn {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }

    private func detail(for preset: ResizePreset) -> String {
        switch preset.kind {
        case .original:
            return "Original pixels · 80% · Same as Original"
        case .longEdge:
            return "Long edge \(preset.longEdge ?? 0) px · 80% · Same as Original"
        case .exact:
            return "\(preset.width ?? 0) × \(preset.height ?? 0) · \(preset.cropMode.displayName) · \(Int((preset.quality * 100).rounded()))% · \(preset.format.displayName)"
        }
    }
}

private struct CompressionPresetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var preset: ResizePreset
    let onSave: (ResizePreset) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Preset") {
                    TextField("Name", text: $preset.name)
                    LabeledContent("Width") {
                        TextField(
                            "Width",
                            value: Binding(
                                get: { preset.width ?? 1_080 },
                                set: { preset.width = max(1, $0) }
                            ),
                            format: .number
                        )
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Height") {
                        TextField(
                            "Height",
                            value: Binding(
                                get: { preset.height ?? 1_350 },
                                set: { preset.height = max(1, $0) }
                            ),
                            format: .number
                        )
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                    }
                    Picker("Crop Mode", selection: $preset.cropMode) {
                        ForEach(ResizeCropMode.allCases) {
                            Text($0.displayName).tag($0)
                        }
                    }
                }

                Section("Output") {
                    Picker("Format", selection: $preset.format) {
                        Text("JPEG").tag(PhotoOutputFormat.jpeg)
                        Text("HEIC").tag(PhotoOutputFormat.heic)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent(
                            "Quality",
                            value: "\(Int((preset.quality * 100).rounded()))%"
                        )
                        Slider(value: $preset.quality, in: 0.1...1, step: 0.01)
                    }
                }
            }
            .navigationTitle(preset.name.isEmpty ? "New Preset" : "Edit Preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        preset.name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        preset.kind = .exact
                        preset.isBuiltIn = false
                        onSave(preset)
                    }
                    .disabled(
                        preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || (preset.width ?? 0) <= 0
                            || (preset.height ?? 0) <= 0
                    )
                }
            }
        }
    }
}
