import SwiftUI

/// Settings › Playback › Audio Languages / Subtitle Languages (FS-23.02
/// §3b, 03 §2): the chosen languages in order — first match wins — over the
/// languages to add. Audio with none chosen plays the file's default track
/// (`Original`); subtitles with none chosen start Off.
struct MovieLanguagesScreen: View {
    enum Kind {
        case audio, subtitles

        var key: String {
            switch self {
            case .audio: SettingsKeys.movieAudioLanguages
            case .subtitles: SettingsKeys.movieSubtitleLanguages
            }
        }
    }

    let kind: Kind
    @State private var chosen: [String] = []

    var body: some View {
        List {
            Section {
                if chosen.isEmpty {
                    Text(emptyTitle)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(chosen, id: \.self) { code in
                        Text(MovieLanguage.endonym(code) ?? code)
                    }
                    .onMove { chosen.move(fromOffsets: $0, toOffset: $1); save() }
                    .onDelete { chosen.remove(atOffsets: $0); save() }
                }
            } header: {
                Text("In Order", comment: "Settings → Movie languages: header over the chosen languages")
            } footer: {
                Text(footer)
            }

            if kind == .audio {
                Section {
                    Button {
                        chosen = []
                        save()
                    } label: {
                        row(String(localized: "Original", comment: "Settings → Audio Languages: play the file's default track"), isChecked: chosen.isEmpty)
                    }
                    .tint(.primary)
                } footer: {
                    Text("Clears the list: every movie starts with the track its file marks as default.", comment: "Settings → Audio Languages: footer under Original")
                }
            }

            Section {
                ForEach(MovieLanguagePreferences.offered.filter { !chosen.contains($0) }, id: \.self) { code in
                    Button {
                        chosen.append(code)
                        save()
                    } label: {
                        Label {
                            Text(MovieLanguage.endonym(code) ?? code)
                        } icon: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.white, .green)
                        }
                    }
                    .tint(.primary)
                    .accessibilityLabel(String(localized: "Add \(MovieLanguage.endonym(code) ?? code)", comment: "Settings → Movie languages: add a language to the list"))
                }
            } header: {
                Text("Add", comment: "Settings → Movie languages: header over languages not chosen yet")
            }
        }
        .navigationTitle(kind == .audio
            ? String(localized: "Audio Languages", comment: "Settings → Playback row and screen title")
            : String(localized: "Subtitle Languages", comment: "Settings → Playback row and screen title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !chosen.isEmpty { EditButton() }
        }
        .onAppear { chosen = Self.current(kind) }
    }

    /// The list as it stands, with the defaults filled in.
    static func current(_ kind: Kind) -> [String] {
        let stored = UserDefaults.standard.string(forKey: kind.key)
        switch kind {
        case .audio: return MovieLanguagePreferences.audio(stored)
        case .subtitles: return MovieLanguagePreferences.subtitles(stored, deviceLanguage: Locale.current.language.languageCode?.identifier)
        }
    }

    private var emptyTitle: String {
        kind == .audio
            ? String(localized: "Original — the track the file marks as default", comment: "Settings → Audio Languages with none chosen")
            : String(localized: "None — subtitles start off", comment: "Settings → Subtitle Languages with none chosen")
    }

    private var footer: String {
        kind == .audio
            ? String(localized: "A movie opened for the first time plays the first of these languages it has. A track you pick in the player is remembered for that movie.", comment: "Settings → Audio Languages footer")
            : String(localized: "A movie opened for the first time shows the first of these languages it has a subtitle in. Subtitles you pick in the player are remembered for that movie.", comment: "Settings → Subtitle Languages footer")
    }

    private func row(_ title: String, isChecked: Bool) -> some View {
        HStack {
            Text(title).foregroundStyle(.primary)
            Spacer()
            if isChecked {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }

    private func save() {
        UserDefaults.standard.set(MovieLanguagePreferences.encode(chosen), forKey: kind.key)
    }
}
