import SwiftUI
import ShotDexKit

/// Optics › Lens Profile: Lensfun distortion correction for JPEG and HEIC.
///
/// Three states, and each says what it is (FS-03.11 AC-15): a matched lens
/// shown by name with a way to change it, no match said plainly with a way to
/// pick one, and RAW — where the RAW decoder already corrects — said so rather
/// than offering a second correction on top.
struct EditorLensProfileSection: View {
    @Bindable var controller: PhotoEditorController
    @State private var isPickerPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if controller.isRAWSource {
                note("RAW photos are corrected by the RAW decoder — Lens Correction under Detail.")
            } else {
                EditorToggleRow(
                    title: "Lens Profile",
                    isOn: controller.recipe.lensProfile != nil
                ) { isOn in
                    if isOn, controller.lensProfileMatch == nil {
                        isPickerPresented = true
                    } else {
                        controller.setLensProfileEnabled(isOn)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(statusText)
                        .font(EditorTheme.maskSubtitle)
                        .foregroundStyle(
                            controller.recipe.lensProfile == nil ? EditorTheme.dimText : EditorTheme.secondaryText
                        )
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button(controller.lensProfileLens == nil && controller.lensProfileMatch == nil ? "Choose Lens" : "Change") {
                        isPickerPresented = true
                    }
                    .buttonStyle(EditorTextButtonStyle())
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
            }
        }
        .sheet(isPresented: $isPickerPresented) {
            EditorLensPickerSheet(
                selectedID: controller.recipe.lensProfile?.lensID ?? controller.lensProfileMatch?.lens.id,
                cameraMount: controller.lensCameraMount
            ) { lens in
                controller.chooseLensProfile(lens)
            }
        }
    }

    private var statusText: String {
        if let lens = controller.lensProfileLens {
            let how = controller.recipe.lensProfile?.isAutomatic == true ? "Found from EXIF" : "Chosen by you"
            return "\(lens.displayName) · \(how)"
        }
        if let match = controller.lensProfileMatch {
            return match.lens.displayName
        }
        return "No profile for this lens yet. Choose yours from the list."
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(EditorTheme.maskSubtitle)
            .foregroundStyle(EditorTheme.dimText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
    }
}

/// Every lens in the embedded Lensfun table, searchable, the ones that fit the
/// body's mount first. Lensfun credit at the foot, as its licence asks.
struct EditorLensPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let selectedID: String?
    let cameraMount: String?
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
                Section {
                    Text("Lens profiles from the Lensfun database, CC-BY-SA 3.0.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
