import SwiftUI

/// Settings › General › Thumbnails (board `MAC_SettingsGeneral`, AC-67,
/// AC-68): the file-type badge, what the info line carries, and focal lengths
/// as shot or as full-frame equivalents. Same keys as the iOS grid.
struct MacThumbnailSettings: View {
    @AppStorage(ThumbnailInfoFields.fileTypeBadgeKey) private var showsFileTypeBadge = true
    @AppStorage(ThumbnailInfoFields.equivalentFocalLengthKey) private var showsEquivalentFocalLength = false

    var body: some View {
        Section {
            Toggle(isOn: $showsFileTypeBadge) {
                Text("File Type Badge", comment: "Mac Settings › Thumbnails row")
                Text("RAW, HEIC, JPG in the corner of each thumbnail", comment: "Mac Settings › Thumbnails row explanation")
            }
            .toggleStyle(.switch)
            .tint(MacTheme.accent)
            LabeledContent(String(localized: "Info on Thumbnails", comment: "Mac Settings › Thumbnails row")) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    ForEach(Array(stride(from: 0, to: ThumbnailInfoFields.Field.allCases.count, by: 3)), id: \.self) { start in
                        GridRow {
                            ForEach(ThumbnailInfoFields.Field.allCases[start..<min(start + 3, ThumbnailInfoFields.Field.allCases.count)]) {
                                MacThumbnailFieldToggle(field: $0)
                            }
                        }
                    }
                }
            }
            Picker(String(localized: "Focal Length", comment: "Mac Settings › Thumbnails row"), selection: $showsEquivalentFocalLength) {
                Text("Actual", comment: "Mac Settings › Thumbnails: focal length as shot").tag(false)
                Text("Full-Frame Equivalent", comment: "Mac Settings › Thumbnails: focal length on a 35 mm sensor").tag(true)
            }
            .pickerStyle(.segmented)
            .fixedSize()
        } header: {
            Text("Thumbnails", comment: "Mac Settings group")
        }
    }
}

/// One field of the info line, as a checkbox.
private struct MacThumbnailFieldToggle: View {
    let field: ThumbnailInfoFields.Field
    @AppStorage private var isShown: Bool

    init(field: ThumbnailInfoFields.Field) {
        self.field = field
        _isShown = AppStorage(wrappedValue: field.isShownByDefault, field.key)
    }

    var body: some View {
        Toggle(field.title, isOn: $isShown)
            .toggleStyle(.checkbox)
            .tint(MacTheme.accent)
    }
}
