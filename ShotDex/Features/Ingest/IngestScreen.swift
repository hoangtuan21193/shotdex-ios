import ImageIO
import SwiftUI
import UIKit

/// Import from Card (FS-20 §5–7; boards `PH_Ingest`, `PH_IngestProgress`,
/// `IP_Ingest`, `DI_Ingest`, `DC_Ingest`): the card's photos by day, new
/// ones ticked; where they go below on a phone, beside on a wide screen;
/// the run's progress in place of the options while it goes.
struct IngestScreen: View {
    @Bindable var model: IngestModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var isConfirmingStop = false

    /// Wide enough for the grid and a 360pt inspector side by side (FS-21:
    /// below 1100pt the inspector is a panel under the grid).
    private static let inspectorMinimumWidth: CGFloat = 1100

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let isWide = proxy.size.width >= Self.inspectorMinimumWidth
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        controls
                        grid
                        if !isWide { panel(isWide: false) }
                    }
                    if isWide {
                        Divider()
                        panel(isWide: true)
                            .frame(width: IngestMetrics.inspectorWidth)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Text("Import from Card", tableName: IngestCopy.table, comment: "Import from Card: screen title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .accessibilityLabel(Text("Back", tableName: IngestCopy.table, comment: "Import from Card: leave the screen"))
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("Import from Card", tableName: IngestCopy.table, comment: "Import from Card: screen title").font(.headline)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .task { if model.phase == .loading { await model.load() } }
            .confirmationDialog(
                Text("Stop importing? Photos already imported stay in “\(model.destination?.name ?? "")”.", tableName: IngestCopy.table,
                     comment: "Card import: confirm Stop"),
                isPresented: $isConfirmingStop, titleVisibility: .visible
            ) {
                Button(String(localized: "Stop", table: IngestCopy.table, comment: "Card import: confirm Stop"), role: .destructive) { model.stop() }
            }
        }
    }

    private var subtitle: String {
        guard let space = model.cardSpace else { return model.card.name }
        return model.card.name + " · " + IngestCopy.usedOf(used: space.used, total: space.total)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Picker(selection: $model.segment) {
                Text("All \(model.items.count.formatted())", tableName: IngestCopy.table, comment: "Import from Card segment: every photo")
                    .tag(IngestModel.Segment.all)
                Text("New \(model.newCount.formatted())", tableName: IngestCopy.table, comment: "Import from Card segment: not imported yet")
                    .tag(IngestModel.Segment.new)
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            HStack(spacing: AppTheme.Spacing.lg) {
                Button(String(localized: "Check All", table: IngestCopy.table, comment: "Import from Card: tick every new photo")) { model.checkAll() }
                Button(String(localized: "Uncheck All", table: IngestCopy.table, comment: "Import from Card: untick every photo")) { model.uncheckAll() }
                Spacer(minLength: 0)
                Text(model.isRunning
                     ? String(localized: "\(model.progress.done) of \(model.progress.total) imported", table: IngestCopy.table,
                              comment: "Import from Card: progress in the controls row")
                     : IngestCopy.checkedLine(count: model.checkedCount, bytes: model.checkedBytes))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.body)
            .disabled(model.isRunning)
        }
        .padding(.horizontal)
        .padding(.vertical, AppTheme.Spacing.sm)
    }

    // MARK: Grid

    @ViewBuilder
    private var grid: some View {
        switch model.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failedToRead:
            ContentUnavailableView(String(localized: "Couldn't read \(model.card.name).", table: IngestCopy.table,
                                          comment: "Import from Card: the card's file list could not be read"),
                                   systemImage: "sdcard")
        default:
            if model.days.isEmpty {
                VStack(spacing: AppTheme.Spacing.md) {
                    ContentUnavailableView(IngestCopy.everythingImported(card: model.card.name), systemImage: "checkmark.circle")
                    Button(String(localized: "Show All", table: IngestCopy.table, comment: "Import from Card: switch to All")) {
                        model.segment = .all
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.md, pinnedViews: []) {
                        ForEach(model.days) { day in
                            daySection(day)
                        }
                    }
                    .padding(.bottom, AppTheme.Spacing.lg)
                }
            }
        }
    }

    @ViewBuilder
    private func daySection(_ day: IngestStatus.Day) -> some View {
        if day.isFullyImported, model.segment == .all {
            HStack {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(day.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.headline).foregroundStyle(.secondary)
                Spacer()
                Text(IngestCopy.collapsedDay(day.importedCount)).font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(day.date.formatted(.dateTime.weekday(.wide).month(.wide).day())).font(.headline)
                    Spacer()
                    Text(IngestCopy.newOnDay(day.newCount)).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .accessibilityElement(children: .combine)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: IngestMetrics.tileMinimum), spacing: 2)], spacing: 2) {
                    ForEach(day.items) { item in
                        IngestTile(item: item, root: model.root,
                                   isImported: model.imported.contains(item.id),
                                   isChecked: model.selection.checked.contains(item.id))
                            .onTapGesture { if !model.isRunning { model.toggle(item) } }
                    }
                }
            }
        }
    }

    // MARK: Panel

    @ViewBuilder
    private func panel(isWide: Bool) -> some View {
        if model.isRunning {
            IngestProgressPanel(model: model, isConfirmingStop: $isConfirmingStop)
        } else {
            IngestOptionsPanel(model: model, isWide: isWide)
        }
    }
}

enum IngestMetrics {
    /// `IP_Ingest`: the inspector beside the grid.
    static let inspectorWidth: CGFloat = 360
    /// Four tiles on a 402pt phone (`PH_Ingest`), more as the window widens.
    static let tileMinimum: CGFloat = 96
}

/// One photo of the card (FS-20 §5): its embedded preview, its name, a tick
/// top-left when new, *Imported* when not.
struct IngestTile: View {
    let item: CardItem
    let root: URL
    let isImported: Bool
    let isChecked: Bool
    @State private var image: UIImage?

    var body: some View {
        Color(.secondarySystemFill)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if item.kind == .video {
                    Image(systemName: "video").foregroundStyle(.secondary)
                }
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                Text(item.primary.name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
            }
            .overlay(alignment: .bottomTrailing) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 4))
                        .padding(EdgeInsets(top: 0, leading: 0, bottom: 22, trailing: 4))
                }
            }
            .overlay(alignment: .topLeading) {
                if isImported {
                    Label(String(localized: "Imported", table: IngestCopy.table, comment: "Import from Card: tile already imported"),
                          systemImage: "checkmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.58), in: Capsule())
                        .padding(4)
                } else {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, isChecked ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.black.opacity(0.2)))
                        .padding(5)
                }
            }
            .opacity(isImported ? 0.75 : 1)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: item.primary.name))
            .accessibilityValue(isImported
                ? Text("Imported", tableName: IngestCopy.table, comment: "VoiceOver: card tile already imported")
                : (isChecked ? Text("checked", tableName: IngestCopy.table, comment: "VoiceOver: card tile ticked")
                             : Text("not checked", tableName: IngestCopy.table, comment: "VoiceOver: card tile not ticked")))
            .accessibilityAddTraits(isImported ? [] : .isButton)
            .task(id: item.id) {
                // A RAW with no preview of its own shows its JPEG's.
                for file in item.files where !CardCatalog.audioExtensions.contains(file.pathExtension) {
                    if let found = await IngestThumbnails.shared.image(for: root.appendingPathComponent(file.path)) {
                        image = found
                        return
                    }
                }
            }
    }

    /// `CR3+HIF` for a pair, the type for one file.
    private var badge: String? {
        let types = item.files.filter { !CardCatalog.audioExtensions.contains($0.pathExtension) }
            .map { $0.pathExtension.uppercased() }
        guard !types.isEmpty else { return nil }
        return types.joined(separator: "+")
    }
}

/// Card tiles from the preview each file carries (FS-20 §9: never a RAW
/// decode), at most two read at a time, kept within a bound.
actor IngestThumbnails {
    static let shared = IngestThumbnails()
    private let cache = NSCache<NSURL, UIImage>()
    private var reading = 0

    init() { cache.countLimit = 400 }

    func image(for url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        while reading >= 2 { try? await Task.sleep(for: .milliseconds(30)) }
        guard !Task.isCancelled else { return nil }
        reading += 1
        defer { reading -= 1 }
        let thumbnail = await Task.detached(priority: .utility) { Self.preview(of: url) }.value
        guard let thumbnail else { return nil }
        let image = UIImage(cgImage: thumbnail)
        cache.setObject(image, forKey: url as NSURL)
        return image
    }

    /// The preview the camera embedded; a JPEG or HEIF without one is
    /// small enough to decode, a RAW without one stays blank.
    nonisolated static func preview(of url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 300,
        ]
        if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) { return image }
        guard !PairingRule.isRaw(url.lastPathComponent) else { return nil }
        options[kCGImageSourceCreateThumbnailFromImageAlways] = true
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
