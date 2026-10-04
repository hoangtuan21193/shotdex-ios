import Foundation

/// Where Export… keeps the choices it remembers (FS-03.07b §3, §9): the
/// app's settings, never the database.
struct FileExportSettingsStore {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> FileExportSettings {
        guard let data = defaults.data(forKey: SettingsKeys.fileExportSettings),
              let settings = try? JSONDecoder().decode(FileExportSettings.self, from: data)
        else { return FileExportSettings() }
        return settings
    }

    func save(_ settings: FileExportSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: SettingsKeys.fileExportSettings)
    }
}
