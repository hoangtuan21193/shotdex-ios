import SwiftUI

/// Organize, page 2 of the Backup sheet (board `MAC_BackupOrganize`,
/// FS-22.01 §3–§5, FS-22.06 §5.3): the preview tree on top, then Levels,
/// a folder name per level (Month and Day end in Custom…, which opens
/// `MacBackupCustomDatePopover` beside its popup), Videos, RAW Files and
/// File Names. Find Common Photos opens the same page (FS-19.08 §6e).
struct MacBackupOrganizePage: View {
    @Binding var organize: BackupOrganize
    var back: () -> Void
    /// Find Common Photos opens this page too (FS-19.08 §6e), naming its
    /// first folder: Same as Source joins the levels, Album leaves them.
    var commonPhotosFirstFolder: String? = nil
    /// What the sheet behind is doing, shown beside Done.
    var status: String? = nil
    /// "Photos Library → NAS Home" under the title.
    var subtitle: String? = nil
    /// The preview's top row: "Backup folder on NAS Home".
    var previewRoot: String? = nil
    /// Editing a backup that has copied before: a change files new photos
    /// only (FS-22.01 §2), said where the change is made.
    var affectsNewOnly = false

    /// The level whose Custom… popover is open.
    @State private var customPart: BackupCustomDate.Part?

    private var names: BackupDateName { BackupOrganizeText.names }
    private let sample = BackupOrganizeText.sampleDate

    private var levels: [BackupOrganize.Levels] {
        commonPhotosFirstFolder == nil ? BackupOrganize.Levels.backup : BackupOrganize.Levels.commonPhotos
    }

    /// Year where a level carries it: its own level, a Month named
    /// "2025-10", or Date Only's day names that hold the year — not a
    /// Custom name, whose year is set in Custom….
    private var usesYear: Bool {
        [.yearMonthDay, .yearMonth, .yearDate].contains(organize.levels)
            || (organize.levels == .dateOnly && ![.dayOnly, .custom].contains(organize.dayStyle))
            || (usesMonth && organize.monthStyle == .yearMonth)
    }
    private var usesMonth: Bool { [.yearMonthDay, .yearMonth].contains(organize.levels) }
    private var usesDay: Bool { [.yearMonthDay, .yearDate, .dateOnly].contains(organize.levels) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button(action: back) {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .medium)).frame(width: 28, height: 28)
                        .background(MacTheme.fill, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MacTheme.separator, lineWidth: 0.5))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("[", modifiers: .command)
                .accessibilityLabel(String(localized: "Back", comment: "Mac toolbar"))
                .help(String(localized: "Back", comment: "Mac toolbar"))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Organize", comment: "Mac Backup: Organize page title").font(.system(size: 15, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .padding(.bottom, 15)
            Text("Preview", comment: "Organize: the example tree")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .frame(height: 20, alignment: .top)
            preview
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    label(String(localized: "Levels:", comment: "Organize: folder levels"))
                    VStack(alignment: .leading, spacing: 4) {
                        Picker(String(localized: "Levels", comment: "Organize: folder levels"), selection: $organize.levels) {
                            ForEach(levels, id: \.self) { Text(BackupOrganizeText.levels($0)).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                        if let first = commonPhotosFirstFolder, !first.isEmpty, organize.levels == .sameAsSource {
                            note(String(localized: "Each photo keeps the folder it has in \(first), the first folder listed in Find Common Photos.",
                                        comment: "Organize, Find Common Photos: what Same as Source does"))
                        }
                    }
                }
                if usesYear || usesMonth || usesDay {
                    // The label sits at the middle of popups + note (board).
                    GridRow(alignment: .center) {
                        label(String(localized: "Folder Names:", comment: "Organize: the name of each folder level"))
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                if usesYear { yearPopup }
                                if usesMonth { monthPopup }
                                if usesDay { dayPopup }
                            }
                            note(String(localized: "From the date each item was taken. Each menu lists its names as examples; Custom… at the end of Month and Day sets your own order and separator.",
                                        comment: "Organize footer"))
                        }
                    }
                }
                GridRow { Divider().gridCellColumns(2).padding(.vertical, 2) }
                GridRow {
                    label(String(localized: "Videos:", comment: "Organize: where videos go"))
                    Picker(String(localized: "Videos", comment: "Organize: where videos go"), selection: $organize.videoPlacement) {
                        ForEach(BackupPathPlanner.videoPlacements(for: organize.levels), id: \.self) { Text(BackupOrganizeText.videos($0)).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
                GridRow {
                    label(String(localized: "RAW Files:", comment: "Organize: where RAW files go"))
                    Picker(String(localized: "RAW Files", comment: "Organize: where RAW files go"), selection: $organize.rawPlacement) {
                        ForEach(BackupPathPlanner.videoPlacements(for: organize.levels), id: \.self) { Text(BackupOrganizeText.videos($0)).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
                GridRow { Divider().gridCellColumns(2).padding(.vertical, 2) }
                GridRow {
                    label(String(localized: "File Names:", comment: "Organize: how files are named"))
                    HStack(spacing: 8) {
                        Picker(String(localized: "File Names", comment: "Organize: how files are named"), selection: $organize.fileNames) {
                            ForEach(BackupOrganize.FileNames.allCases, id: \.self) { Text(BackupOrganizeText.fileNames($0)).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                        Text(sampleFileName).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            .padding(.top, 14)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                note(affectsNewOnly
                     ? String(localized: "Changing this affects new photos only. Photos already copied stay where they are.",
                              comment: "Organize, Edit Backup: a change does not move what was copied (FS-22.01 §2)")
                     : commonPhotosFirstFolder != nil
                     ? String(localized: "A name already taken in that folder gets a number, like IMG_0001 (2).JPG.",
                              comment: "Organize, Find Common Photos: the next free name rule")
                     : String(localized: "A file with the same name but different size is kept as a second copy.", comment: "Organize: Keep Both rule"))
                Spacer(minLength: 8)
                if let status {
                    Text(status).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                }
                // Black on the dark amber (`onAccentFill`), white on the light one.
                Button(action: back) { Text("Done", comment: "Mac sheet: done").frame(minWidth: 68).foregroundStyle(MacTheme.onAccentFill) }
                    .keyboardShortcut(.defaultAction)
                    .tint(MacTheme.accentFill)
                    .controlSize(.large)
            }
        }
        .padding(.horizontal, 25)
        .padding(.top, 24)
        .padding(.bottom, 21)
        // Popups read in the label colour (board); the segments and Done set amber themselves.
        .tint(.primary)
        // Escape goes back to page 1 rather than closing the whole sheet.
        .background {
            Button(String(localized: "Back", comment: "Mac toolbar"), action: back)
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0).opacity(0)
                .accessibilityHidden(true)
        }
        .onChange(of: organize.levels) { _, levels in
            // A placement the new levels do not offer falls back to its own default
            // (videos apart at the top, RAW together).
            let offered = BackupPathPlanner.videoPlacements(for: levels)
            if !offered.contains(organize.videoPlacement) { organize.videoPlacement = .apartAtTop }
            if !offered.contains(organize.rawPlacement) { organize.rawPlacement = BackupOrganize().rawPlacement }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).frame(width: 128, alignment: .trailing).gridColumnAlignment(.trailing)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private var sampleFileName: String {
        let planner = BackupPathPlanner(organize: organize, names: names)
        return planner.fileName(for: BackupPlacementInput(date: sample, isVideo: false, originalFilename: "IMG_8812.HEIC"))
    }

    // MARK: Preview

    /// The sample photo, its RAW and a video as one tree; a run of single
    /// folders reads as one line, "2025 › Oct › 2025.10.12" (board).
    private var preview: some View {
        VStack(alignment: .leading, spacing: 0) {
            if commonPhotosFirstFolder != nil {
                previewRow(previewRoot ?? String(localized: "Backup folder", comment: "Organize preview: the backup's root folder"),
                           symbol: "folder", depth: 0, isFolder: true)
                previewRow(BackupOrganizeText.commonPhotosTree(organize), symbol: "photo", depth: 1, isFolder: false)
            } else {
                previewRow(previewRoot ?? String(localized: "Backup folder", comment: "Organize preview: the backup's root folder"),
                           symbol: "folder", depth: 0, isFolder: true)
                ForEach(Array(MacOrganizePreview.lines(organize).enumerated()), id: \.offset) { _, line in
                    previewRow(line.name, symbol: line.symbol, depth: line.depth + 1, isFolder: line.isFolder)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
        .background(MacTheme.content, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(MacTheme.separator))
        // One element that reads the whole tree, not just its heading.
        .accessibilityElement(children: .combine)
    }

    private func previewRow(_ name: String, symbol: String, depth: Int, isFolder: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 13))
                .foregroundStyle(isFolder ? AnyShapeStyle(MacTheme.accent) : AnyShapeStyle(.secondary))
                .frame(width: 14)
            Text(name).font(.system(size: 12)).monospacedDigit().lineLimit(1).truncationMode(.middle)
                .foregroundStyle(depth == 0 ? .secondary : .primary)
        }
        .frame(height: 18)
        .padding(.leading, CGFloat(depth) * 18)
    }

    // MARK: Folder name popups

    private var yearPopup: some View {
        Picker(String(localized: "Year", comment: "Organize row: year folder name"), selection: $organize.yearStyle) {
            ForEach(BackupOrganize.YearStyle.allCases, id: \.self) { Text(names.year(sample, style: $0)).tag($0) }
        }
        .labelsHidden()
        .frame(width: 80)
    }

    private var monthPopup: some View {
        Menu {
            Picker(selection: $organize.monthStyle) {
                ForEach(BackupOrganize.MonthStyle.allCases.filter { $0 != .custom }, id: \.self) { style in
                    Text(names.month(sample, organize: with { $0.monthStyle = style })).tag(style)
                }
            } label: { EmptyView() }
            .pickerStyle(.inline)
            Divider()
            // Ticked while the name is the custom one, like the listed styles.
            Toggle(String(localized: "Custom…", comment: "Organize: build your own date folder name"),
                   isOn: Binding(get: { organize.monthStyle == .custom }, set: { _ in openCustom(.month) }))
        } label: {
            Text(names.month(sample, organize: organize))
        }
        .frame(width: 96)
        .accessibilityLabel(String(localized: "Month", comment: "Organize row: month folder name"))
        .accessibilityValue(names.month(sample, organize: organize))
        .popover(isPresented: customBinding(.month), arrowEdge: .trailing) {
            MacBackupCustomDatePopover(organize: $organize, part: .month) { customPart = nil }
        }
    }

    private var dayPopup: some View {
        Menu {
            Picker(selection: $organize.dayStyle) {
                ForEach(BackupOrganize.DayStyle.allCases.filter { $0 != .custom }, id: \.self) { style in
                    Text(names.day(sample, organize: with { $0.dayStyle = style })).tag(style)
                }
            } label: { EmptyView() }
            .pickerStyle(.inline)
            Divider()
            // Ticked while the name is the custom one, like the listed styles.
            Toggle(String(localized: "Custom…", comment: "Organize: build your own date folder name"),
                   isOn: Binding(get: { organize.dayStyle == .custom }, set: { _ in openCustom(.day) }))
        } label: {
            Text(names.day(sample, organize: organize))
        }
        .frame(width: 132)
        .accessibilityLabel(String(localized: "Day", comment: "Organize row: day folder name"))
        .accessibilityValue(names.day(sample, organize: organize))
        .popover(isPresented: customBinding(.day), arrowEdge: .trailing) {
            MacBackupCustomDatePopover(organize: $organize, part: .day) { customPart = nil }
        }
    }

    /// Custom… makes the level's name the custom one and opens its popover.
    private func openCustom(_ part: BackupCustomDate.Part) {
        if part == .month { organize.monthStyle = .custom } else { organize.dayStyle = .custom }
        customPart = part
    }

    private func customBinding(_ part: BackupCustomDate.Part) -> Binding<Bool> {
        Binding(get: { customPart == part }, set: { if !$0, customPart == part { customPart = nil } })
    }

    private func with(_ change: (inout BackupOrganize) -> Void) -> BackupOrganize {
        var copy = organize
        change(&copy)
        return copy
    }
}

/// Custom… for the Month or Day folder (board `MAC_BackupOrganize`,
/// FS-22.01 §4): order, year, month and separator, the name live in the
/// header. Every change lands in the backup's settings at once; Done closes.
struct MacBackupCustomDatePopover: View {
    @Binding var organize: BackupOrganize
    let part: BackupCustomDate.Part
    var done: () -> Void

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

    private var currentName: String {
        part == .month ? names.month(sample, organize: organize) : names.day(sample, organize: organize)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(part == .month ? String(localized: "Month Folder Name", comment: "Custom date title")
                                    : String(localized: "Day Folder Name", comment: "Custom date title"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                Text(currentName).font(.system(size: 13)).foregroundStyle(.secondary).monospacedDigit()
                    .accessibilityLabel(String(localized: "Preview, \(currentName)", comment: "VoiceOver: the custom folder name as it will read"))
            }
            .frame(height: 20)
            .padding(.bottom, 8)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 8) {
                if part == .day {
                    GridRow {
                        label(String(localized: "Order:", comment: "Custom date row"))
                        Picker(String(localized: "Order", comment: "Custom date row"), selection: format.order) {
                            Text("Year Month Day", comment: "Custom date order").tag(BackupCustomDate.Order.yearMonthDay)
                            Text("Day Month Year", comment: "Custom date order").tag(BackupCustomDate.Order.dayMonthYear)
                            Text("Month Day Year", comment: "Custom date order").tag(BackupCustomDate.Order.monthDayYear)
                        }
                        .labelsHidden()
                        .frame(width: 160)
                    }
                }
                GridRow {
                    label(String(localized: "Year:", comment: "Custom date row"))
                    MacFittedSegments(title: String(localized: "Year", comment: "Custom date row"),
                                      options: BackupOrganize.YearStyle.allCases.map { (names.year(sample, style: $0), $0) },
                                      selection: format.wrappedValue.yearStyle) { format.wrappedValue.yearStyle = $0 }
                }
                GridRow {
                    label(String(localized: "Month:", comment: "Custom date row"))
                    MacFittedSegments(title: String(localized: "Month", comment: "Custom date row"),
                                      options: BackupCustomDate.MonthForm.allCases.map { (names.custom(sample, monthOnly($0)), $0) },
                                      selection: format.wrappedValue.monthForm) { format.wrappedValue.monthForm = $0 }
                }
                if part == .day {
                    GridRow {
                        label(String(localized: "Day:", comment: "Custom date row"))
                        Text(names.custom(sample, BackupCustomDate(parts: [.day]))).monospacedDigit().frame(height: 28)
                    }
                }
                GridRow {
                    label(String(localized: "Separator:", comment: "Custom date row"))
                    HStack(spacing: 8) {
                        // A typed separator that is not one of these selects no segment.
                        MacFittedSegments(title: String(localized: "Quick Separators", comment: "Custom date: segmented picks for common separators"),
                                          options: quickSeparators, selection: format.wrappedValue.separator) { value in
                            format.wrappedValue.separator = value
                            typedSeparator = value
                        }
                        TextField(String(localized: "Separator", comment: "Custom date: type any separator"), text: $typedSeparator)
                            .labelsHidden()
                            .accessibilityLabel(String(localized: "Custom separator", comment: "VoiceOver: type your own separator"))
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.center)
                            .frame(width: 34)
                            .onChange(of: typedSeparator) { _, typed in
                                let clean = BackupDateName.cleanSeparator(typed)
                                if clean != typed { typedSeparator = clean }
                                format.wrappedValue.separator = clean
                            }
                    }
                }
            }
            Text("Type any separator, such as \" - \" or 年. A NAS folder can't hold / \\ : * ? \" < > |, so they are left out.",
                 comment: "Mac custom date footer: what can be typed as a separator")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            HStack {
                Spacer()
                Button(action: done) { Text("Done", comment: "Mac sheet: done").frame(minWidth: 56).foregroundStyle(MacTheme.onAccentFill) }
                    .keyboardShortcut(.defaultAction)
                    .tint(MacTheme.accentFill)
                    .accessibilityLabel(part == .month ? String(localized: "Done with Month Folder Name", comment: "VoiceOver: close the custom month popover")
                                                       : String(localized: "Done with Day Folder Name", comment: "VoiceOver: close the custom day popover"))
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(width: 320)
        .onAppear { typedSeparator = format.wrappedValue.separator }
    }

    private func label(_ text: String) -> some View {
        Text(text).frame(width: 68, alignment: .trailing).gridColumnAlignment(.trailing)
    }

    private func monthOnly(_ form: BackupCustomDate.MonthForm) -> BackupCustomDate {
        var only = BackupCustomDate(parts: [.month])
        only.monthForm = form
        return only
    }
}

/// A segmented row whose segments fit their words ("-" narrow, "Space"
/// wide), which the system control cannot do: it gives every segment the
/// widest one's width, 300pt for the five separators. Selected segment
/// raised on `segOn`; none selected for a typed value.
struct MacFittedSegments<Value: Hashable>: View {
    let title: String
    let options: [(String, Value)]
    let selection: Value
    let choose: (Value) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.1) { label, value in
                let isOn = value == selection
                Button { choose(value) } label: {
                    Text(label).font(.system(size: 12, weight: isOn ? .medium : .regular))
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 7)
                        .frame(minWidth: 21, minHeight: 24)
                        .background {
                            if isOn {
                                RoundedRectangle(cornerRadius: 6).fill(MacTheme.segmentOn)
                                    .shadow(color: MacTheme.segmentShadow, radius: 1, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(MacTheme.fill, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// The preview tree with runs of single folders joined: the sample photo
/// and RAW under "2025 › Oct › 2025.10.12", the video under its own run.
enum MacOrganizePreview {
    struct Line: Equatable {
        var name: String
        var depth: Int
        var isFolder: Bool
        var symbol: String
    }

    private final class Node {
        let row: BackupPreviewTree.Row
        var children: [Node] = []
        init(_ row: BackupPreviewTree.Row) { self.row = row }
    }

    static func lines(_ organize: BackupOrganize) -> [Line] {
        // Rows come depth-first: a stack of open folders rebuilds the tree.
        var top: [Node] = []
        var open: [Node] = []
        for row in BackupPreviewTree.rows(organize: organize) {
            let node = Node(row)
            while let last = open.last, last.row.depth >= row.depth { open.removeLast() }
            if let parent = open.last { parent.children.append(node) } else { top.append(node) }
            if row.isFolder { open.append(node) }
        }
        var lines: [Line] = []
        func emit(_ node: Node, depth: Int) {
            guard node.row.isFolder else {
                lines.append(Line(name: node.row.name, depth: depth, isFolder: false, symbol: node.row.symbol))
                return
            }
            var names = [node.row.name]
            var tail = node
            while tail.children.count == 1, let only = tail.children.first, only.row.isFolder {
                names.append(only.row.name)
                tail = only
            }
            lines.append(Line(name: names.joined(separator: " › "), depth: depth, isFolder: true, symbol: "folder"))
            for child in tail.children { emit(child, depth: depth + 1) }
        }
        for node in top { emit(node, depth: 0) }
        return lines
    }
}
