import ShotDexKit
import SwiftUI

/// "Sync to 6 Photos" (board `MAC_EditBatch`, FS-18.03 §3): the open photo's
/// edit, group by group, onto the photos ⌘-clicked in the filmstrip. The Look
/// column is ticked, This Frame Only is not; photos that cannot take it are
/// named with the reason before anything is written.
struct MacEditorSyncSheet: View {
    @Bindable var model: MacEditorModel
    @Binding var isPresented: Bool
    @State private var ticks = MacSyncTicks.remembered()
    @State private var showsAllSkips = false

    private enum Preset: Hashable { case look, everything, custom }

    private var preset: Preset {
        ticks == .look ? .look : ticks == .everything ? .everything : .custom
    }

    private var syncCount: Int { model.writableSyncTargets.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync to ^[\(model.orderedSyncTargets.count) Photo](inflect: true)", comment: "Mac editor sync sheet title")
                        .font(.system(size: 15, weight: .semibold))
                    Text("From \(model.details.fileName) to the other selected photos", comment: "Mac editor sync sheet: where from")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Picker(String(localized: "Sync", comment: "Mac editor sync: preset"), selection: Binding(
                    get: { preset },
                    set: { choice in
                        switch choice {
                        case .look: ticks = .look
                        case .everything: ticks = .everything
                        case .custom: break
                        }
                    })) {
                    Text("Sync Look", comment: "Mac editor sync: the look column only").tag(Preset.look)
                    Text("Sync Everything", comment: "Mac editor sync: every group").tag(Preset.everything)
                    if preset == .custom { Text("Custom", comment: "Mac editor sync: hand-picked groups").tag(Preset.custom) }
                }
                .labelsHidden()
                .frame(width: 150)
                .accessibilityIdentifier("editor.sync.preset")
            }
            .padding(.bottom, 18)
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    columnHead(String(localized: "The Look", comment: "Mac editor sync: left column"))
                    ForEach(EditorSyncGroup.lookColumn) { row($0) }
                }
                .frame(maxWidth: .infinity)
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    columnHead(String(localized: "This Frame Only", comment: "Mac editor sync: right column"))
                    ForEach(EditorSyncGroup.frameColumn) { row($0) }
                    Text("These belong to one frame, so Sync Look leaves them out. Check them to copy them anyway — they land at the same place in each photo.",
                         comment: "Mac editor sync: why the frame column is off")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                    skips.padding(.top, 10)
                }
                .frame(maxWidth: .infinity)
            }
            Divider().padding(.vertical, 14)
            Text("Replaces the checked groups on ^[\(syncCount) photo](inflect: true) with this photo's settings — a group that reads “off” clears it there. ⌘Z in each photo undoes it.",
                 comment: "Mac editor sync: what Sync writes")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
            HStack(spacing: 8) {
                Button(String(localized: "Check All", comment: "Mac editor sync")) { ticks = .everything }
                    .accessibilityIdentifier("editor.sync.checkAll")
                Button(String(localized: "Check None", comment: "Mac editor sync")) { ticks = EditorSyncGroups(groups: []) }
                    .accessibilityIdentifier("editor.sync.checkNone")
                Spacer()
                if !model.isCheckingSync, ticks.groups.isEmpty || syncCount == 0 {
                    Text(ticks.groups.isEmpty ? String(localized: "Check at least one group", comment: "Mac editor sync: why Sync is off")
                                              : String(localized: "None of these photos can take the edit", comment: "Mac editor sync: why Sync is off"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Button(String(localized: "Cancel", comment: "Mac editor sync")) { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("editor.sync.cancel")
                Button {
                    MacSyncTicks.remember(ticks)
                    model.sync(ticks)
                    isPresented = false
                } label: {
                    Text(model.isCheckingSync ? String(localized: "Checking…", comment: "Mac editor sync: reading the photos")
                                              : MacInflect.string("Sync ^[\(syncCount) Photo](inflect: true)", comment: "Mac editor sync: the commit button"))
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(MacTheme.Editor.accent)
                .disabled(model.isCheckingSync || syncCount == 0 || ticks.groups.isEmpty)
                .accessibilityIdentifier("editor.sync.go")
            }
        }
        .padding(24)
        .frame(width: 640)
        .preferredColorScheme(.dark)
        // Neutral controls; the accent only on the ticks and the button that commits (board).
        .tint(MacTheme.Editor.label)
        .onAppear { model.checkSyncTargets() }
    }

    private func columnHead(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.bottom, 4)
    }

    private func row(_ group: EditorSyncGroup) -> some View {
        HStack(spacing: 8) {
            Toggle(group.title, isOn: Binding(
                get: { ticks.groups.contains(group) },
                set: { on in if on { ticks.groups.insert(group) } else { ticks.groups.remove(group) } }))
                .toggleStyle(.checkbox)
                .tint(MacTheme.Editor.accent)
                .font(.system(size: 13))
                .lineLimit(1)
                .accessibilityIdentifier("editor.sync.group.\(group.rawValue)")
            Spacer(minLength: 6)
            Text(MacSyncWords.detail(group, model.recipe))
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(height: 20)
    }

    @ViewBuilder
    private var skips: some View {
        if model.isCheckingSync {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking the photos…", comment: "Mac editor sync: reading the targets").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        ForEach(showsAllSkips ? model.syncSkips : Array(model.syncSkips.prefix(3))) { skip in
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(MacTheme.Editor.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(skip.name) will be skipped", comment: "Mac editor sync: a photo that cannot take the edit")
                        .font(.system(size: 12, weight: .semibold))
                    Text(skip.reason).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MacTheme.Editor.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: MacTheme.Editor.buttonRadius))
            .overlay(RoundedRectangle(cornerRadius: MacTheme.Editor.buttonRadius).strokeBorder(MacTheme.Editor.accent.opacity(0.35)))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("editor.sync.skip")
        }
        if model.syncSkips.count > 3, !showsAllSkips {
            Button(String(localized: "and \(model.syncSkips.count - 3) more", comment: "Mac editor sync: show the other skipped photos")) { showsAllSkips = true }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

/// The ticks the last sync used, kept for the next one.
enum MacSyncTicks {
    private static let key = "mac.editor.syncTicks"

    static func remembered() -> EditorSyncGroups {
        guard let data = UserDefaults.standard.data(forKey: key),
              let ticks = try? JSONDecoder().decode(EditorSyncGroups.self, from: data), !ticks.groups.isEmpty else { return .look }
        return ticks
    }

    static func remember(_ ticks: EditorSyncGroups) {
        if let data = try? JSONEncoder().encode(ticks) { UserDefaults.standard.set(data, forKey: key) }
    }
}

/// What each group would carry from this photo: "6 sliders", "3:2 · +2.4°", "off".
enum MacSyncWords {
    static func detail(_ group: EditorSyncGroup, _ recipe: PhotoEditRecipe) -> String {
        let off = String(localized: "off", comment: "Mac editor sync: a group with nothing set")
        // "off" exactly when the sync copies nothing of it: the group laid on an empty recipe changes nothing.
        if EditorSyncGroups(groups: [group]).apply(recipe, onto: .identity) == .identity { return off }
        switch group {
        case .look:
            let amount = Int((recipe.filterIntensity * 100).rounded())
            if recipe.lutID != nil, recipe.filter == .original {
                return String(localized: "LUT · \(amount)", comment: "Mac editor sync: a LUT look")
            }
            return "\(recipe.filter.displayName) · \(amount)"
        case .toneCurve:
            return recipe.curve.isIdentity ? off : String(localized: "edited", comment: "Mac editor sync: a curve that is not straight")
        case .colorMixer:
            let bands = ColorMixerBand.allCases.filter { !recipe.color.mixer[$0].isIdentity }.count
            return bands == 0 ? String(localized: "edited", comment: "Mac editor sync") : MacInflect.string("^[\(bands) band](inflect: true)", comment: "Mac editor sync: mixer bands set")
        case .pointColor:
            return MacInflect.string("^[\(recipe.color.points.count) color](inflect: true)", comment: "Mac editor sync")
        case .grading:
            return recipe.color.grading.isIdentity ? off : String(localized: "edited", comment: "Mac editor sync")
        case .blackAndWhite:
            return String(localized: "on", comment: "Mac editor sync")
        case .calibration:
            return recipe.color.calibration.isIdentity ? off : String(localized: "edited", comment: "Mac editor sync")
        case .uprightMode:
            return recipe.upright.mode == .off ? off : String(localized: "solved per photo", comment: "Mac editor sync: Upright reads each photo")
        case .cropAndStraighten:
            let crop = recipe.crop
            if crop == .identity { return off }
            let angle = crop.straightenDegrees == 0 ? "" : " · \(crop.straightenDegrees > 0 ? "+" : "")\(crop.straightenDegrees.formatted(.number.precision(.fractionLength(1))))°"
            return crop.aspect.displayName + angle
        case .masks: return MacInflect.string("^[\(recipe.masks.count) mask](inflect: true)", comment: "Mac editor sync")
        case .healAndClone: return MacInflect.string("^[\(recipe.healing.count) spot](inflect: true)", comment: "Mac editor sync")
        case .redEye: return MacInflect.string("^[\(recipe.redEyes.count) eye](inflect: true)", comment: "Mac editor sync")
        case .markupLayers: return MacInflect.string("^[\(recipe.overlays.count) layer](inflect: true)", comment: "Mac editor sync")
        case .uprightGuides: return MacInflect.string("^[\(recipe.upright.guides.count) guide](inflect: true)", comment: "Mac editor sync")
        case .lensBlur:
            return String(localized: "on", comment: "Mac editor sync")
        case .light, .whiteBalanceAndPresence, .effects, .detail, .optics, .geometry:
            let set = group.adjustmentFields.filter { recipe.adjustments[keyPath: $0] != PhotoAdjustments.zero[keyPath: $0] }.count
            return set == 0 ? String(localized: "edited", comment: "Mac editor sync")
                : MacInflect.string("^[\(set) slider](inflect: true)", comment: "Mac editor sync: sliders set in a group")
        }
    }
}

/// A localized string with its "^[3 photo](inflect: true)" made singular or plural —
/// `String(localized:)` leaves that markup as typed, `AttributedString` applies it.
enum MacInflect {
    static func string(_ value: String.LocalizationValue, comment: StaticString) -> String {
        String(AttributedString(localized: value, comment: comment).characters)
    }
}
