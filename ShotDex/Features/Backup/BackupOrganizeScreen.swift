import SwiftUI

/// Organize (FS-22.01 §3–§5, board `PH_BackupOrganize` 3/5): folder levels,
/// a name style per level, where videos go, file names.
struct BackupOrganizeScreen: View {
    @Binding var settings: BackupSettings
    let previewRoot: String
    /// Opens Custom… for the Month or the Day level.
    var openCustom: (BackupCustomDate.Part) -> Void

    private var organize: BackupOrganize { settings.organize }
    private var names: BackupDateName { BackupOrganizeText.names }
    private let sample = BackupOrganizeText.sampleDate

    var body: some View {
        Form {
            Section {
                BackupFolderPreview(root: previewRoot, organize: organize)
            } header: {
                Text(String(localized: "Preview", comment: "Organize section: the folder tree"))
            }

            Section {
                Picker(String(localized: "Levels", comment: "Organize row: how deep the folders go"), selection: $settings.organize.levels) {
                    ForEach(BackupOrganize.Levels.allCases, id: \.self) { Text(BackupOrganizeText.levels($0)).tag($0) }
                }
                if usesYear {
                    Picker(String(localized: "Year", comment: "Organize row: year folder name"), selection: $settings.organize.yearStyle) {
                        ForEach(BackupOrganize.YearStyle.allCases, id: \.self) { style in
                            Text(names.year(sample, style: style)).tag(style)
                        }
                    }
                }
                if usesMonth { monthMenu }
                if usesDay { dayMenu }
            } header: {
                Text(String(localized: "Folders", comment: "Organize section"))
            } footer: {
                Text(String(localized: "From the date each item was taken. Each menu lists its names as examples; Custom… at the end of Month and Day sets your own order and separator.", comment: "Organize footer"))
            }

            Section {
                Picker(String(localized: "Videos", comment: "Organize row: where videos go"), selection: $settings.organize.videoPlacement) {
                    ForEach(BackupPathPlanner.videoPlacements(for: organize.levels), id: \.self) {
                        Text(BackupOrganizeText.videos($0)).tag($0)
                    }
                }
                Picker(String(localized: "RAW Files", comment: "Organize row: where RAW files go"), selection: $settings.organize.rawPlacement) {
                    ForEach(BackupPathPlanner.videoPlacements(for: organize.levels), id: \.self) {
                        Text(BackupOrganizeText.videos($0)).tag($0)
                    }
                }
            } header: {
                Text(String(localized: "Photos, RAW and Videos", comment: "Organize section: where videos and RAW files go"))
            } footer: {
                Text(String(localized: "Apart in Each Day puts the RAW folder inside the photos' own day folder.", comment: "Organize footer: what the RAW placement means"))
            }

            Section(String(localized: "File Names", comment: "Organize section")) {
                Picker(String(localized: "File Names", comment: "Organize row"), selection: $settings.organize.fileNames) {
                    ForEach(BackupOrganize.FileNames.allCases, id: \.self) { Text(BackupOrganizeText.fileNames($0)).tag($0) }
                }
                LabeledContent(String(localized: "Same Name, Different File", comment: "Organize row: what happens on a name clash")) {
                    Text(String(localized: "Keep Both", comment: "Organize: a clash keeps both files"))
                }
            }
        }
        .navigationTitle(String(localized: "Organize", comment: "Organize screen title"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: organize.levels) { _, levels in
            let offered = BackupPathPlanner.videoPlacements(for: levels)
            if !offered.contains(organize.videoPlacement) { settings.organize.videoPlacement = .apartAtTop }
            if !offered.contains(organize.rawPlacement) { settings.organize.rawPlacement = .apartAtTop }
        }
    }

    private var usesYear: Bool { [.yearMonthDay, .yearMonth, .yearDate].contains(organize.levels) || organize.monthStyle == .yearMonth }
    private var usesMonth: Bool { [.yearMonthDay, .yearMonth].contains(organize.levels) }
    private var usesDay: Bool { [.yearMonthDay, .yearDate, .dateOnly].contains(organize.levels) }

    private var monthMenu: some View {
        Menu {
            Picker(selection: $settings.organize.monthStyle) {
                ForEach(BackupOrganize.MonthStyle.allCases.filter { $0 != .custom }, id: \.self) { style in
                    Text(names.month(sample, organize: with { $0.monthStyle = style })).tag(style)
                }
            } label: { EmptyView() }
            Button(String(localized: "Custom…", comment: "Organize: build your own date folder name")) {
                settings.organize.monthStyle = .custom
                openCustom(.month)
            }
        } label: {
            LabeledContent(String(localized: "Month", comment: "Organize row: month folder name")) {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Text(names.month(sample, organize: organize))
                    Image(systemName: "chevron.up.chevron.down").font(.footnote.weight(.medium))
                }
                .foregroundStyle(.secondary)
            }
        }
        .tint(.primary)
    }

    private var dayMenu: some View {
        Menu {
            Picker(selection: $settings.organize.dayStyle) {
                ForEach(BackupOrganize.DayStyle.allCases.filter { $0 != .custom }, id: \.self) { style in
                    Text(names.day(sample, organize: with { $0.dayStyle = style })).tag(style)
                }
            } label: { EmptyView() }
            Button(String(localized: "Custom…", comment: "Organize: build your own date folder name")) {
                settings.organize.dayStyle = .custom
                openCustom(.day)
            }
        } label: {
            LabeledContent(String(localized: "Day", comment: "Organize row: day folder name")) {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Text(names.day(sample, organize: organize))
                    Image(systemName: "chevron.up.chevron.down").font(.footnote.weight(.medium))
                }
                .foregroundStyle(.secondary)
            }
        }
        .tint(.primary)
    }

    private func with(_ change: (inout BackupOrganize) -> Void) -> BackupOrganize {
        var copy = organize
        change(&copy)
        return copy
    }
}

/// Where a sample photo, its RAW and a video land, merged into one folder
/// tree — every rule of Organize visible at once (FS-22.01 §3–§4).
struct BackupFolderPreview: View {
    let root: String
    let organize: BackupOrganize

    var body: some View {
        let rows = BackupPreviewTree.rows(organize: organize)
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(root)
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: row.symbol)
                        .foregroundStyle(row.isFolder ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    Text(row.name)
                        .foregroundStyle(row.isFolder ? .primary : .secondary)
                }
                .padding(.leading, CGFloat(row.depth) * AppTheme.Spacing.lg)
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

/// The merged tree behind the preview: folders first, then files, in the
/// order the paths reach them.
enum BackupPreviewTree {
    struct Row: Equatable {
        var name: String
        var depth: Int
        var isFolder: Bool
        var symbol: String
    }

    static let samples: [(BackupPlacementInput, String)] = [
        (BackupPlacementInput(date: BackupOrganizeText.sampleDate, isVideo: false, originalFilename: "IMG_8812.HEIC",
                              album: String(localized: "Trip", comment: "Organize preview: sample album name")), "photo"),
        (BackupPlacementInput(date: BackupOrganizeText.sampleDate, isVideo: false, originalFilename: "IMG_8812.CR3", isRAW: true,
                              album: String(localized: "Trip", comment: "Organize preview: sample album name")), "camera.aperture"),
        (BackupPlacementInput(date: BackupOrganizeText.sampleDate, isVideo: true, originalFilename: BackupOrganizeText.sampleVideo,
                              album: String(localized: "Trip", comment: "Organize preview: sample album name")), "video"),
    ]

    static func rows(organize: BackupOrganize) -> [Row] {
        let planner = BackupPathPlanner(organize: organize, names: BackupOrganizeText.names)
        final class Node {
            var children: [(String, Node)] = []
            var files: [(String, String)] = []
            func child(_ name: String) -> Node {
                if let found = children.first(where: { $0.0 == name }) { return found.1 }
                let node = Node()
                children.append((name, node))
                return node
            }
        }
        let root = Node()
        for (input, symbol) in samples {
            var node = root
            for folder in planner.folders(for: input) { node = node.child(folder) }
            node.files.append((planner.fileName(for: input), symbol))
        }
        var rows: [Row] = []
        func walk(_ node: Node, depth: Int) {
            for (name, symbol) in node.files { rows.append(Row(name: name, depth: depth, isFolder: false, symbol: symbol)) }
            for (name, child) in node.children {
                rows.append(Row(name: name, depth: depth, isFolder: true, symbol: "folder"))
                walk(child, depth: depth + 1)
            }
        }
        walk(root, depth: 0)
        return rows
    }
}

/// Custom… date name (FS-22.01 §4, board `PH_BackupCustomDate` 4/5).
struct BackupCustomDateScreen: View {
    @Binding var organize: BackupOrganize
    let part: BackupCustomDate.Part
    let previewRoot: String

    @State private var typedSeparator = ""
    private var names: BackupDateName { BackupOrganizeText.names }
    private let sample = BackupOrganizeText.sampleDate
    private let quickSeparators: [(String, String)] = [
        (String(localized: "None", comment: "Custom date: no separator"), ""),
        ("-", "-"), (".", "."), ("_", "_"),
        (String(localized: "Space", comment: "Custom date: a space separator"), " "),
    ]

    private var format: Binding<BackupCustomDate> {
        part == .month ? $organize.customMonth : $organize.customDay
    }

    var body: some View {
        Form {
            Section(String(localized: "Preview", comment: "Custom date section")) {
                BackupFolderPreview(root: previewRoot, organize: organize)
            }
            Section(part == .month
                ? String(localized: "Month Folder", comment: "Custom date section")
                : String(localized: "Day Folder", comment: "Custom date section")) {
                if part == .day {
                    Picker(String(localized: "Order", comment: "Custom date row"), selection: format.order) {
                        Text(String(localized: "Year Month Day", comment: "Custom date order")).tag(BackupCustomDate.Order.yearMonthDay)
                        Text(String(localized: "Day Month Year", comment: "Custom date order")).tag(BackupCustomDate.Order.dayMonthYear)
                        Text(String(localized: "Month Day Year", comment: "Custom date order")).tag(BackupCustomDate.Order.monthDayYear)
                    }
                }
                LabeledContent(String(localized: "Year", comment: "Custom date row")) {
                    Picker(String(localized: "Year", comment: "Custom date row"), selection: format.yearStyle) {
                        ForEach(BackupOrganize.YearStyle.allCases, id: \.self) { Text(names.year(sample, style: $0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                LabeledContent(String(localized: "Month", comment: "Custom date row")) {
                    Picker(String(localized: "Month", comment: "Custom date row"), selection: format.monthForm) {
                        ForEach(BackupCustomDate.MonthForm.allCases, id: \.self) { form in
                            Text(names.custom(sample, monthOnly(form))).tag(form)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                if part == .day {
                    LabeledContent(String(localized: "Day", comment: "Custom date row"), value: names.custom(sample, dayOnly))
                }
            }
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(quickSeparators, id: \.1) { label, value in
                            Button(label) {
                                format.wrappedValue.separator = value
                                typedSeparator = value
                            }
                            .buttonStyle(.bordered)
                            .tint(format.wrappedValue.separator == value ? .accentColor : .secondary)
                        }
                    }
                }
                TextField(String(localized: "Separator", comment: "Custom date: type any separator"), text: $typedSeparator)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel(String(localized: "Separator", comment: "Custom date: type any separator"))
                    .onChange(of: typedSeparator) { _, typed in
                        let clean = BackupDateName.cleanSeparator(typed)
                        if clean != typed { typedSeparator = clean }
                        format.wrappedValue.separator = clean
                    }
            } header: {
                Text(String(localized: "Separator", comment: "Custom date section"))
            } footer: {
                Text(String(localized: "Type any separator, such as \" - \" or 年. / \\ : * ? \" < > | are refused — a NAS folder can't hold them.", comment: "Custom date footer"))
            }
        }
        .navigationTitle(part == .month
            ? String(localized: "Month Folder Name", comment: "Custom date title")
            : String(localized: "Day Folder Name", comment: "Custom date title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { typedSeparator = format.wrappedValue.separator }
    }

    private func monthOnly(_ form: BackupCustomDate.MonthForm) -> BackupCustomDate {
        var only = BackupCustomDate(parts: [.month])
        only.monthForm = form
        return only
    }

    private var dayOnly: BackupCustomDate { BackupCustomDate(parts: [.day]) }
}
