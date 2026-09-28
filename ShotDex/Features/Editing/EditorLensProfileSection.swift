import SwiftUI
import ShotDexKit

/// Optics › Lens Correction (FS-03.16b §1–2): one switch for every source,
/// then what corrects the photo and how it was found, with Change / Choose
/// Lens. The three strengths follow under LENS PROFILE in the generic rows.
/// No "Lensfun" anywhere on screen — the credit lives in Settings.
struct EditorLensProfileSection: View {
    @Bindable var controller: PhotoEditorController
    @State private var isPickerPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorToggleRow(
                title: "Lens Correction",
                isOn: controller.isLensCorrectionOn
            ) { isOn in
                if isOn, !controller.isRAWSource, controller.recipe.lensProfile == nil,
                   controller.lensProfileMatch == nil {
                    isPickerPresented = true
                } else {
                    controller.setLensCorrectionEnabled(isOn)
                }
            }
            statusRow
        }
        .sheet(isPresented: $isPickerPresented) {
            EditorLensPickerSheet(
                selectedID: controller.recipe.lensProfile?.lensID ?? controller.lensProfileMatch?.lens.id,
                cameraMount: controller.lensCameraMount,
                offersEmbeddedData: controller.hasEmbeddedLensData,
                useEmbeddedData: { controller.useEmbeddedLensData() }
            ) { lens in
                controller.chooseLensProfile(lens)
            }
        }
    }

    private var statusRow: some View {
        let panel = controller.lensCorrectionResolution.panel
        let isOn = controller.isLensCorrectionOn
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                statusText(panel)
                    .font(EditorTheme.maskSubtitle)
                    .foregroundStyle(isOn ? EditorTheme.secondaryText : EditorTheme.dimText)
                if panel == .builtIn {
                    Text("Strength controls need a lens profile")
                        .font(EditorTheme.maskSubtitle)
                        .foregroundStyle(EditorTheme.dimText)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button(Self.buttonTitle(panel)) {
                isPickerPresented = true
            }
            .buttonStyle(EditorTextButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
        .frame(minHeight: 40)
    }

    /// The lens name cut in the middle, the way it was found kept whole.
    @ViewBuilder
    private func statusText(_ panel: LensCorrectionPanelState) -> some View {
        switch panel {
        case .found(let name), .chosen(let name):
            HStack(spacing: 0) {
                Text(name).lineLimit(1).truncationMode(.middle)
                Text(Self.how(panel)).lineLimit(1).fixedSize()
            }
        default:
            Text(Self.statusLine(panel)).fixedSize(horizontal: false, vertical: true)
        }
    }

    static func how(_ panel: LensCorrectionPanelState) -> String {
        if case .chosen = panel { return " · Chosen by you" }
        return " · Found from photo info"
    }

    /// The whole status line, for the states with no lens name and for tests.
    static func statusLine(_ panel: LensCorrectionPanelState) -> String {
        switch panel {
        case .found(let name): "\(name) · Found from photo info"
        case .chosen(let name): "\(name) · Chosen by you"
        case .correctedInCamera: "Already corrected in camera"
        case .builtIn: "Using the camera's built-in correction"
        case .noProfile: "No profile for this lens yet"
        }
    }

    static func buttonTitle(_ panel: LensCorrectionPanelState) -> String {
        switch panel {
        case .found, .chosen: "Change"
        case .correctedInCamera, .builtIn, .noProfile: "Choose Lens"
        }
    }
}

/// Every lens in the embedded table, searchable, the ones that fit the body's
/// mount first. The data's credit is in Settings › Acknowledgements
/// (FS-03.16b §3), not here.
struct EditorLensPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let selectedID: String?
    let cameraMount: String?
    /// The file has the maker's own data: offer the way back to it first.
    var offersEmbeddedData = false
    var useEmbeddedData: () -> Void = {}
    let onSelect: (LensfunLens) -> Void

    @State private var query = ""

    private var matching: [LensfunLens] {
        let lenses = LensProfileLibrary.shared.lenses
        guard !query.isEmpty else { return lenses }
        let words = query.lowercased().split(separator: " ")
        return lenses.filter { lens in
            let name = lens.displayName.lowercased()
            return words.allSatisfy { name.contains($0) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                let lenses = matching
                if offersEmbeddedData, query.isEmpty {
                    Section {
                        Button {
                            useEmbeddedData()
                            dismiss()
                        } label: {
                            Label("Use Lens Data Found in Photo", systemImage: "camera.metering.center.weighted")
                                .foregroundStyle(.white)
                        }
                    }
                }
                if let cameraMount {
                    let fitting = lenses.filter { $0.mounts.contains(cameraMount) }
                    if !fitting.isEmpty {
                        Section("Fits \(cameraMount)") {
                            ForEach(fitting) { row($0) }
                        }
                    }
                }
                let others = cameraMount.map { mount in lenses.filter { !$0.mounts.contains(mount) } } ?? lenses
                ForEach(Self.grouped(others), id: \.maker) { group in
                    Section(group.maker) {
                        ForEach(group.lenses) { row($0) }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search lenses")
            .navigationTitle("Choose Lens")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ lens: LensfunLens) -> some View {
        Button {
            onSelect(lens)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lens.displayName)
                        .foregroundStyle(.white)
                    Text(Self.detail(lens, cameraMount: cameraMount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if lens.id == selectedID {
                    Image(systemName: "checkmark")
                        .foregroundStyle(EditorTheme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(lens.id == selectedID ? .isSelected : [])
    }

    /// Mount and the crop the profile was measured at — what tells two rows
    /// with the same name apart. A lens made for several mounts shows the
    /// body's when it has it: under "Fits Fujifilm X" a row saying "Sony E"
    /// reads as a mistake.
    private static func detail(_ lens: LensfunLens, cameraMount: String?) -> String {
        let crop = lens.cropFactor == 1 ? "full frame" : String(format: "crop %.2g×", lens.cropFactor)
        let mount = cameraMount.flatMap { lens.mounts.contains($0) ? $0 : nil } ?? lens.mounts.first
        let more = lens.mounts.count > 1 ? " +\(lens.mounts.count - 1)" : ""
        return ([mount.map { $0 + more }].compactMap { $0 } + [crop]).joined(separator: " · ")
    }

    private static func grouped(_ lenses: [LensfunLens]) -> [(maker: String, lenses: [LensfunLens])] {
        Dictionary(grouping: lenses, by: \.maker)
            .map { (maker: $0.key, lenses: $0.value) }
            .sorted { $0.maker.localizedCaseInsensitiveCompare($1.maker) == .orderedAscending }
    }
}
