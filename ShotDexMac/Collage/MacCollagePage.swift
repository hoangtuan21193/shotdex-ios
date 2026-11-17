import AppKit
import ShotDexKit
import SwiftUI
import UniformTypeIdentifiers

/// Image › Create › Collage… (board `MAC_Collage`, FS-18.04 §4c): Photos,
/// Presets, Layouts and Set Aside on the left, the collage in the middle,
/// the inspector of 300. Always dark (D10).
struct MacCollagePage: View {
    @Bindable var model: MacCollageModel
    let close: () -> Void
    @State private var exports = false
    @State private var namesPreset = false
    @State private var presetName = ""
    /// A text field has the keys: ⌘Z belongs to it, not to the collage.
    @State private var isTyping = false
    @State private var asksDiscard = false

    var body: some View {
        HStack(spacing: 0) {
            MacCollagePanel(model: model, namesPreset: $namesPreset)
                .frame(width: 228)
            Rectangle().fill(MacTheme.Editor.hairline).frame(width: 1)
            MacCollageStage(model: model)
            if model.showsInspector {
                Rectangle().fill(MacTheme.Editor.hairline).frame(width: 1)
                MacCollageInspector(model: model, isTyping: $isTyping)
                    .frame(width: 300)
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .tint(MacTheme.Editor.label)
        .navigationTitle(String(localized: "Collage", comment: "Mac Collage: the page title"))
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
        .sheet(isPresented: $exports) { MacCollageExportSheet(model: model) }
        .alert(String(localized: "Save Preset", comment: "Mac Collage: name a preset"), isPresented: $namesPreset) {
            TextField(String(localized: "Name", comment: "Mac Collage: preset name field"), text: $presetName)
            Button(String(localized: "Cancel", comment: "Mac Collage"), role: .cancel) { presetName = "" }
            Button(String(localized: "Save", comment: "Mac Collage: save the preset")) {
                model.savePreset(named: presetName)
                presetName = ""
            }
        } message: {
            Text("The layout, aspect ratio and style — not the photos or the title.", comment: "Mac Collage: what a preset keeps")
        }
        // Esc wherever the keys are: a selected cell is let go, else the page is left.
        .background {
            if !exports && !namesPreset && !asksDiscard && !isTyping {
                Button("") {
                    if model.selectedCell != nil { model.selectedCell = nil } else { leave() }
                }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
        }
        .onAppear {
            model.loadPictures()
            // Collages › Export…: the sheet comes up on the reopened collage.
            if model.exportsOnOpen {
                model.exportsOnOpen = false
                exports = true
            }
        }
        .confirmationDialog(String(localized: "Discard this collage?", comment: "Mac Collage: leaving with changes not exported"),
                            isPresented: $asksDiscard) {
            Button(String(localized: "Discard", comment: "Mac Collage: leave without exporting"), role: .destructive) {
                model.close()
                close()
            }
            Button(String(localized: "Keep Editing", comment: "Mac Collage: stay"), role: .cancel) {}
        } message: {
            Text("It hasn’t been exported since the last change. Collages are kept only once exported.",
                 comment: "Mac Collage: why leaving loses the work")
        }
    }

    /// "4 of 4 photos · 1:1 · Not saved yet".
    private var subtitle: String {
        let state: String
        switch model.saved {
        case .file(let url): state = String(localized: "Saved \(url.lastPathComponent)", comment: "Mac Collage subtitle: exported to a file")
        case .photos(let name): state = String(localized: "Saved \(name) to Photos", comment: "Mac Collage subtitle: exported into Photos")
        case .restored: state = String(localized: "Exported", comment: "Mac Collage subtitle: reopened from Collages, unchanged since its export")
        case nil: state = String(localized: "Not saved yet", comment: "Mac Collage subtitle: nothing exported since the last change")
        }
        return [MacInflect.string("\(model.placedCount) of ^[\(model.slotCount) photo](inflect: true)", comment: "Mac Collage subtitle: cells filled"),
                model.aspectLabel, state].joined(separator: " · ")
    }

    /// Back, Esc: a collage changed since its last export asks first.
    private func leave() {
        if model.hasEdits, model.saved == nil {
            asksDiscard = true
            return
        }
        model.close()
        close()
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: leave) {
                Label(String(localized: "Back", comment: "Mac toolbar"), systemImage: "chevron.left")
            }
            .keyboardShortcut("[", modifiers: .command)
            .help(String(localized: "Back (⌘[ or Esc)", comment: "Mac Collage toolbar"))
            .accessibilityIdentifier("collage.back")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            ControlGroup {
                Button(action: model.undo) { Label(String(localized: "Undo", comment: "Mac Collage toolbar"), systemImage: "arrow.uturn.backward") }
                    .keyboardShortcut(isTyping ? nil : KeyboardShortcut("z", modifiers: .command))
                    .disabled(!model.canUndo)
                    .accessibilityIdentifier("collage.undo")
                Button(action: model.redo) { Label(String(localized: "Redo", comment: "Mac Collage toolbar"), systemImage: "arrow.uturn.forward") }
                    .keyboardShortcut(isTyping ? nil : KeyboardShortcut("z", modifiers: [.command, .shift]))
                    .disabled(!model.canRedo)
                    .accessibilityIdentifier("collage.redo")
            }
            ControlGroup {
                Toggle(isOn: $model.isShowingOriginal) {
                    Label(String(localized: "Show Original", comment: "Mac Collage toolbar: the photos without border, spacing or text"),
                          systemImage: "square.split.2x1")
                }
                .help(String(localized: "Show the photos without border, spacing, corners or text", comment: "Mac Collage toolbar"))
                .accessibilityIdentifier("collage.original")
            }
            Toggle(isOn: $model.showsInspector) {
                Label(String(localized: "Inspector", comment: "Mac Collage toolbar"), systemImage: "sidebar.right")
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .help(String(localized: "Show or hide the options (⌥⌘I)", comment: "Mac Collage toolbar"))
            .accessibilityIdentifier("collage.inspector")
            if case .file(let url) = model.saved {
                Button(String(localized: "Show in Finder", comment: "Mac Collage toolbar: reveal the exported file")) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .accessibilityIdentifier("collage.reveal")
            }
            Button {
                // The sheet writes the styled collage: the canvas shows that too.
                model.isShowingOriginal = false
                exports = true
            } label: {
                Label(String(localized: "Export…", comment: "Mac Collage toolbar: write the collage out"), systemImage: "square.and.arrow.up.on.square")
                    .labelStyle(.titleAndIcon)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .buttonStyle(MacPushButtonStyle(isDefault: true, isToolbarCommand: true))
            .disabled(model.placedCount == 0 || model.isExporting)
            .accessibilityIdentifier("collage.export")
        }
    }
}

// MARK: - Left panel

private struct MacCollagePanel: View {
    @Bindable var model: MacCollageModel
    @Binding var namesPreset: Bool
    @State private var trayTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Photos", comment: "Mac Collage panel: how many cells").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(verbatim: String(model.slotCount))
                        .font(.system(size: 13)).monospacedDigit()
                        .frame(width: 34, height: 22)
                        .background(MacTheme.Editor.fill, in: RoundedRectangle(cornerRadius: MacTheme.Editor.controlRadius))
                        .accessibilityHidden(true)
                    // A value binding: one cell per click, whatever the arrow's autorepeat does.
                    Stepper("", value: Binding(get: { model.slotCount }, set: { count in
                        if count > model.slotCount { model.addSlot() } else if count < model.slotCount { model.removeSlot() }
                    }), in: MacCollageModel.slotRange)
                        .labelsHidden()
                        .accessibilityLabel(String(localized: "Photos", comment: "Mac Collage panel"))
                        .accessibilityValue(String(model.slotCount))
                        .accessibilityIdentifier("collage.count")
                }
                .padding(.bottom, 24)

                HStack {
                    section(String(localized: "Presets", comment: "Mac Collage panel"))
                    Spacer()
                    Button { namesPreset = true } label: { Image(systemName: "plus") }
                        .buttonStyle(.plain)
                        .foregroundStyle(MacTheme.Editor.secondaryText)
                        .help(String(localized: "Save this layout and style as a preset", comment: "Mac Collage panel"))
                        .accessibilityLabel(String(localized: "Save Preset…", comment: "Mac Collage panel"))
                        .accessibilityIdentifier("collage.savePreset")
                }
                Menu {
                    if model.presets.isEmpty {
                        Text("No presets yet — + saves this one.", comment: "Mac Collage: empty presets menu")
                    }
                    ForEach(model.presets) { preset in
                        Button(preset.name) { model.applyPreset(preset) }
                    }
                    if let current = model.currentPreset {
                        Divider()
                        Button(String(localized: "Delete “\(current.name)”", comment: "Mac Collage: remove the matching preset"), role: .destructive) {
                            model.deletePreset(current.id)
                        }
                    }
                } label: {
                    Label(model.currentPreset?.name ?? String(localized: "None", comment: "Mac Collage: no preset matches"), systemImage: "star")
                }
                .padding(.top, 8)
                .accessibilityIdentifier("collage.presets")

                section(MacInflect.string("Layouts for ^[\(model.slotCount) Photo](inflect: true)", comment: "Mac Collage panel: templates for the count"))
                    .padding(.top, 24)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(60), spacing: 8), count: 3), alignment: .leading, spacing: 8) {
                    ForEach(Array(model.availableTemplates.enumerated()), id: \.element.id) { index, template in
                        Button { model.selectTemplate(template.id) } label: {
                            MacCollageLayoutThumb(template: template, isSelected: template.id == model.recipe.templateID)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Layout \(index + 1)", comment: "Mac Collage: a template"))
                        .accessibilityAddTraits(template.id == model.recipe.templateID ? .isSelected : [])
                        .accessibilityIdentifier("collage.layout.\(index + 1)")
                    }
                }
                .padding(.top, 8)
                Text("\(CollageTemplateCatalog.all.count) layouts for 2–9 photos.", comment: "Mac Collage panel: how many templates exist")
                    .font(.system(size: 11)).foregroundStyle(MacTheme.Editor.secondaryText)
                    .padding(.top, 10)

                HStack {
                    section(String(localized: "Set Aside", comment: "Mac Collage panel: photos not in a cell"))
                    Spacer()
                    Text(verbatim: String(model.unplaced.count)).font(.system(size: 11)).foregroundStyle(MacTheme.Editor.secondaryText)
                }
                .padding(.top, 24)
                tray.padding(.top, 8)
                if let note = model.leftOutNote {
                    Text(note).font(.system(size: 11)).foregroundStyle(MacTheme.Editor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                        .accessibilityIdentifier("collage.leftOut")
                }
                Text(model.unplaced.isEmpty ? String(localized: "Drag a photo here to take it out of the layout.", comment: "Mac Collage: empty Set Aside")
                                            : String(localized: "Not in the layout yet. Drag one onto a cell.", comment: "Mac Collage: Set Aside note"))
                    .font(.system(size: 11)).foregroundStyle(MacTheme.Editor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            .padding(16)
        }
        .background(MacTheme.Editor.panelSolid)
    }

    private func section(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(MacTheme.Editor.secondaryText)
            .accessibilityAddTraits(.isHeader)
    }

    private var tray: some View {
        let columns = Array(repeating: GridItem(.fixed(56), spacing: 6), count: 3)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(model.unplaced, id: \.self) { id in
                Group {
                    if let image = model.images[id] {
                        Image(decorative: image, scale: 1).resizable().scaledToFill()
                    } else {
                        MacTheme.Editor.fill
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: MacTheme.Editor.controlRadius))
                .draggable("aside:\(id)") {
                    Text(model.name(of: id)).padding(6).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
                }
                .contextMenu {
                    let selected = model.selectedCell.flatMap { model.recipe.cells.indices.contains($0) ? $0 : nil }
                    let selectedIsEmpty = selected.map { model.recipe.cells[$0].isEmpty } ?? false
                    // The selected cell when it is empty, else the first empty one.
                    let empty = selectedIsEmpty ? selected : model.recipe.cells.firstIndex(where: \.isEmpty)
                    Button(String(localized: "Put in Empty Cell", comment: "Mac Collage: Set Aside photo into an empty cell")) {
                        if let empty { model.fill(empty, with: id) }
                    }
                    .disabled(empty == nil)
                    Button(String(localized: "Replace Selected Photo", comment: "Mac Collage: Set Aside photo into the selected cell")) {
                        if let selected { model.fill(selected, with: id) }
                    }
                    .disabled(selected == nil || selectedIsEmpty)
                }
                .accessibilityLabel(model.name(of: id))
                .accessibilityIdentifier("collage.aside.\(model.name(of: id))")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
        .padding(6)
        .overlay {
            RoundedRectangle(cornerRadius: MacTheme.Editor.buttonRadius)
                .strokeBorder(trayTargeted ? MacTheme.Editor.accent : MacTheme.Editor.secondaryText.opacity(0.5),
                              style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        // A cell's grip dropped here sets its photo aside.
        .dropDestination(for: String.self) { items, _ in
            guard let item = items.first, item.hasPrefix("cell:"), let index = Int(item.dropFirst(5)) else { return false }
            model.setAside(index)
            return true
        } isTargeted: { trayTargeted = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Set Aside", comment: "Mac Collage panel"))
        .accessibilityIdentifier("collage.tray")
    }
}

/// A template drawn as its cells, 60 × 60.
private struct MacCollageLayoutThumb: View {
    let template: CollageTemplate
    let isSelected: Bool

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 6, gap: CGFloat = 2
            let box = CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
            for cell in template.cells {
                let rect = CGRect(x: box.minX + cell.x * box.width + gap / 2, y: box.minY + cell.y * box.height + gap / 2,
                                  width: cell.width * box.width - gap, height: cell.height * box.height - gap)
                context.fill(Path(roundedRect: rect, cornerRadius: 2),
                             with: .color(isSelected ? .black.opacity(0.85) : Color.white.opacity(0.32)))
            }
        }
        .frame(width: 60, height: 60)
        .background(isSelected ? MacTheme.Editor.accent : MacTheme.Editor.fill, in: RoundedRectangle(cornerRadius: MacTheme.Editor.buttonRadius))
        .overlay(RoundedRectangle(cornerRadius: MacTheme.Editor.buttonRadius).strokeBorder(isSelected ? MacTheme.Editor.accent : MacTheme.Editor.hairline, lineWidth: isSelected ? 2 : 1))
        .contentShape(Rectangle())
    }
}

// MARK: - Stage

private struct MacCollageStage: View {
    @Bindable var model: MacCollageModel
    /// A pan, and separately a pinch, under way: the cell and the content it
    /// started from. One undo step each.
    @State private var pan: (cell: Int, scale: Double, offset: NormalizedPoint)?
    @State private var pinch: (cell: Int, scale: Double, offset: NormalizedPoint)?
    @State private var dividerStart: [Double]?
    @State private var hoveredCell: Int?
    @State private var dropTarget: Int?

    var body: some View {
        GeometryReader { geometry in
            let box = CGSize(width: max(1, geometry.size.width - 64), height: max(1, geometry.size.height - 64))
            let size = Self.fitted(ratio: model.recipe.aspectRatio, in: box)
            ZStack(alignment: .topLeading) {
                Group {
                    if let canvas = model.canvas {
                        Image(decorative: canvas, scale: 1).resizable().interpolation(.high)
                    } else {
                        MacTheme.Editor.fill.overlay { ProgressView().controlSize(.small) }
                    }
                }
                .frame(width: size.width, height: size.height)
                .accessibilityHidden(true)
                cells(in: size)
                dividers(in: size)
            }
            .frame(width: size.width, height: size.height)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .onChange(of: size.width, initial: true) { _, width in
                // Twice the points for a sharp Retina canvas, capped.
                model.scheduleRender(longEdge: min(2400, max(size.width, size.height) * 2))
            }
        }
        .background(Color.black)
        .contentShape(Rectangle())
        .onTapGesture { model.selectedCell = nil }
    }

    // MARK: Cells

    private func cells(in size: CGSize) -> some View {
        let frames = model.cellFrames(in: size)
        return ForEach(Array(frames.enumerated()), id: \.offset) { index, frame in
            let isSelected = model.selectedCell == index
            let cell = model.recipe.cells.indices.contains(index) ? model.recipe.cells[index] : nil
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.white.opacity(0.001))
                if cell?.isEmpty == true {
                    VStack(spacing: 6) {
                        Image(systemName: "photo.badge.plus").font(.system(size: 20))
                        Text(model.unplaced.isEmpty
                             ? String(localized: "Empty — Set Aside has no photos. Use fewer Photos, or select more before opening.", comment: "Mac Collage: an empty cell with nothing to fill it")
                             : String(localized: "Drag a photo from Set Aside", comment: "Mac Collage: an empty cell"))
                            .font(.system(size: 11)).multilineTextAlignment(.center).padding(.horizontal, 8)
                    }
                    .foregroundStyle(Color.black.opacity(0.45))
                    .frame(width: frame.width, height: frame.height)
                    .background(Color.black.opacity(0.06))
                }
                if isSelected, let cell, !cell.isEmpty, (pinch?.cell == index || pan?.cell == index || cell.contentScale > 1.001) {
                    Text(verbatim: (cell.contentScale).formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).frame(height: 20)
                        .background(MacTheme.hudFill, in: RoundedRectangle(cornerRadius: MacTheme.Editor.controlRadius))
                        .padding(10)
                        .accessibilityIdentifier("collage.zoom")
                }
            }
            .frame(width: frame.width, height: frame.height)
            .overlay {
                Rectangle().strokeBorder(dropTarget == index ? MacTheme.Editor.accent
                                         : (isSelected ? Color.white : .clear), lineWidth: 2)
            }
            .contentShape(Rectangle())
            .onHover { hoveredCell = $0 ? index : (hoveredCell == index ? nil : hoveredCell) }
            .onTapGesture { model.selectedCell = index }
            // Simultaneous: the grip's own drag (a system drag) must still start; the
            // pan ignores drags that begin on the grip.
            .simultaneousGesture(panGesture(index: index, frame: frame).simultaneously(with: zoomGesture(index: index, frame: frame)),
                                 including: cell?.isEmpty == false ? .all : .subviews)
            .overlay(alignment: .topTrailing) {
                // The grip: drag the photo to another cell (they swap) or to Set Aside.
                // Dragging anywhere else in the cell moves the photo inside it.
                if isSelected || hoveredCell == index, let cell, !cell.isEmpty {
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(MacTheme.hudFill, in: RoundedRectangle(cornerRadius: MacTheme.Editor.controlRadius))
                        .draggable("cell:\(index)") {
                            Text(cell.assetID.map(model.name(of:)) ?? "").padding(6).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .help(String(localized: "Drag to another cell to swap, or to Set Aside", comment: "Mac Collage: the move grip"))
                        .accessibilityLabel(String(localized: "Move Photo", comment: "Mac Collage: VoiceOver for the grip"))
                        .accessibilityIdentifier("collage.grip")
                        .padding(8)
                }
            }
            .dropDestination(for: String.self) { items, _ in
                guard let item = items.first else { return false }
                if item.hasPrefix("aside:") {
                    model.fill(index, with: String(item.dropFirst(6)))
                    return true
                }
                if item.hasPrefix("cell:"), let other = Int(item.dropFirst(5)) {
                    model.swap(other, index)
                    return true
                }
                return false
            } isTargeted: { dropTarget = $0 ? index : (dropTarget == index ? nil : dropTarget) }
            .contextMenu {
                if cell?.isEmpty == false {
                    Button(String(localized: "Move to Set Aside", comment: "Mac Collage: take a photo out of its cell")) { model.setAside(index) }
                    Button(String(localized: "Reset Crop", comment: "Mac Collage: fit the photo to its cell again")) { model.resetContent(cell: index) }
                        .disabled(cell.map { $0.contentScale <= 1.001 && $0.contentOffset == NormalizedPoint(x: 0, y: 0) } ?? true)
                    Button(String(localized: "Use as Blurred Background", comment: "Mac Collage: blur this photo behind the collage")) {
                        model.selectedCell = index
                        model.setFill(.blurredPhoto)
                    }
                }
            }
            .offset(x: frame.minX, y: frame.minY)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(cell?.assetID.map(model.name(of:))
                                ?? String(localized: "Empty cell", comment: "Mac Collage: VoiceOver for an empty cell"))
            .accessibilityValue(isSelected ? String(localized: "Selected", comment: "Mac Collage: VoiceOver") : "")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("collage.cell.\(index + 1)")
        }
    }

    /// Drag: the photo moves inside its cell (the cell keeps covering, FS-11 §7).
    private func panGesture(index: Int, frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard let cell = cellIfFilled(index) else { return }
                // The grip (top-right, when selected) drags the photo out instead.
                let grip = CGRect(x: frame.width - 42, y: 0, width: 42, height: 42)
                if pan?.cell != index {
                    guard !grip.contains(value.startLocation) else { return }
                    model.beginEdit()
                    pan = (index, cell.contentScale, cell.contentOffset)
                    model.selectedCell = index
                }
                guard let start = pan else { return }
                let offset = NormalizedPoint(x: start.offset.x + value.translation.width / frame.width,
                                             y: start.offset.y + value.translation.height / frame.height)
                model.setContent(cell: index, scale: start.scale, offset: offset, cellFrame: frame)
            }
            .onEnded { _ in
                if pan != nil { model.endEdit() }
                pan = nil
            }
    }

    /// Pinch on the trackpad zooms the photo in its cell, 100–400%.
    private func zoomGesture(index: Int, frame: CGRect) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard let cell = cellIfFilled(index) else { return }
                if pinch?.cell != index {
                    model.beginEdit()
                    pinch = (index, cell.contentScale, cell.contentOffset)
                    model.selectedCell = index
                }
                guard let start = pinch else { return }
                model.setContent(cell: index, scale: start.scale * value.magnification, offset: model.recipe.cells[index].contentOffset, cellFrame: frame)
            }
            .onEnded { _ in
                if pinch != nil { model.endEdit() }
                pinch = nil
            }
    }

    private func cellIfFilled(_ index: Int) -> CollageCell? {
        guard model.recipe.cells.indices.contains(index), !model.recipe.cells[index].isEmpty else { return nil }
        return model.recipe.cells[index]
    }

    // MARK: Dividers

    private func dividers(in size: CGSize) -> some View {
        ForEach(Array(model.dividers().enumerated()), id: \.offset) { _, divider in
            // A split into columns has an up-and-down seam.
            let vertical = divider.axis == .vertical
            let along = divider.position
            let mid = (divider.crossStart + divider.crossEnd) / 2
            let center = vertical ? CGPoint(x: along * size.width, y: mid * size.height)
                                  : CGPoint(x: mid * size.width, y: along * size.height)
            Capsule()
                .fill(MacTheme.Editor.accent)
                .frame(width: vertical ? 10 : 40, height: vertical ? 40 : 10)
                .overlay(Capsule().strokeBorder(.black.opacity(0.35)))
                .contentShape(Rectangle().inset(by: -6))
                .onHover { inside in
                    if inside { (vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set() } else { NSCursor.arrow.set() }
                }
                .onDisappear { NSCursor.arrow.set() }
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .named("collage.canvas"))
                        .onChanged { value in
                            if dividerStart == nil {
                                model.beginEdit()
                                dividerStart = divider.weights
                            }
                            guard let start = dividerStart else { return }
                            let point = vertical ? value.location.x / size.width : value.location.y / size.height
                            let fraction = (point - divider.nodeStart) / max(divider.nodeSpan, 0.0001)
                            model.setDivider(divider.nodeID, weights: CollageDividerMath.adjustedWeights(start, boundary: divider.index,
                                                                                                         toFraction: fraction, snap: true))
                        }
                        .onEnded { _ in
                            if dividerStart != nil { model.endEdit() }
                            dividerStart = nil
                        }
                )
                .onTapGesture(count: 2) { model.resetDivider(divider.nodeID) }
                .position(center)
                .help(String(localized: "Drag to resize; double-click to even it out", comment: "Mac Collage: a divider"))
                .accessibilityElement()
                .accessibilityLabel(String(localized: "Divider", comment: "Mac Collage: VoiceOver"))
                .accessibilityAdjustableAction { direction in
                    let step = direction == .increment ? 0.05 : -0.05
                    let total = divider.weights.reduce(0, +)
                    let before = divider.weights.prefix(divider.index + 1).reduce(0, +) / max(total, 0.0001)
                    model.beginEdit()
                    model.setDivider(divider.nodeID, weights: CollageDividerMath.adjustedWeights(divider.weights, boundary: divider.index,
                                                                                                 toFraction: before + step, snap: false))
                }
                .accessibilityIdentifier("collage.divider")
        }
        .coordinateSpace(name: "collage.canvas")
    }

    static func fitted(ratio: Double, in box: CGSize) -> CGSize {
        guard ratio > 0 else { return box }
        let width = min(box.width, box.height * ratio)
        return CGSize(width: width.rounded(), height: (width / ratio).rounded())
    }
}

// MARK: - Inspector

private struct MacCollageInspector: View {
    @Bindable var model: MacCollageModel
    @Binding var isTyping: Bool
    @FocusState private var focus: Field?

    private enum Field { case width, height, title, caption }
    @State private var width = ""
    @State private var height = ""
    @State private var titleText = ""
    @State private var caption = ""
    /// The cell the caption field was writing to when it got the keys.
    @State private var captionCell: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                group(String(localized: "Layout", comment: "Mac Collage inspector")) {
                    row(String(localized: "Aspect Ratio", comment: "Mac Collage inspector")) {
                        Menu {
                            ForEach(CollageAspect.allCases) { aspect in
                                Button(aspect.displayName) { model.selectAspect(aspect) }
                            }
                        } label: {
                            Label(model.aspectLabel, systemImage: "aspectratio")
                        }
                        .accessibilityIdentifier("collage.aspect")
                    }
                    row(String(localized: "Size", comment: "Mac Collage inspector")) {
                        HStack(spacing: 6) {
                            sizeField($width, id: "collage.width")
                            Text(verbatim: "×").foregroundStyle(MacTheme.Editor.secondaryText)
                            sizeField($height, id: "collage.height")
                        }
                    }
                }
                divider
                group(String(localized: "Style", comment: "Mac Collage inspector")) {
                    slider(String(localized: "Border", comment: "Mac Collage inspector"), value: model.recipe.borderWidth,
                           range: CollageRecipe.borderWidthRange, id: "collage.border", set: model.setBorder)
                    slider(String(localized: "Spacing", comment: "Mac Collage inspector"), value: model.recipe.gutter,
                           range: CollageRecipe.gutterRange, id: "collage.spacing", set: model.setSpacing)
                    slider(String(localized: "Corners", comment: "Mac Collage inspector"), value: model.recipe.cornerRadius,
                           range: CollageRecipe.cornerRadiusRange, id: "collage.corners", set: model.setCorners)
                }
                divider
                group(String(localized: "Background", comment: "Mac Collage inspector")) {
                    row(String(localized: "Fill", comment: "Mac Collage inspector")) {
                        HStack(spacing: 8) {
                            Picker("", selection: Binding(get: { model.recipe.backgroundMode }, set: model.setFill)) {
                                Text("Color", comment: "Mac Collage: flat background").tag(CollageBackgroundMode.color)
                                Text("Blurred Photo", comment: "Mac Collage: a photo blurred behind").tag(CollageBackgroundMode.blurredPhoto)
                            }
                            .labelsHidden()
                            .accessibilityLabel(String(localized: "Fill", comment: "Mac Collage inspector"))
                            .accessibilityIdentifier("collage.fill")
                            ColorPicker("", selection: Binding(
                                get: { Color(cgColor: TextOverlayLayout.cgColor(model.recipe.background)) },
                                set: { color in
                                    if let rgb = NSColor(color).usingColorSpace(.sRGB) {
                                        model.setBackground(OverlayColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent))
                                    }
                                }), supportsOpacity: false)
                                .labelsHidden()
                                .disabled(model.recipe.backgroundMode != .color)
                                .accessibilityLabel(String(localized: "Background Color", comment: "Mac Collage inspector"))
                                .accessibilityIdentifier("collage.color")
                        }
                    }
                    let blurred = model.recipe.backgroundMode == .blurredPhoto
                    slider(String(localized: "Blur", comment: "Mac Collage inspector"), value: model.recipe.backgroundBlur,
                           range: CollageRecipe.backgroundBlurRange, id: "collage.blur", whole: true, set: model.setBlur)
                        .disabled(!blurred).opacity(blurred ? 1 : 0.45)
                    slider(String(localized: "Dim", comment: "Mac Collage inspector"), value: model.recipe.backgroundDarken,
                           range: CollageRecipe.backgroundDarkenRange, id: "collage.dim", whole: true, set: model.setDim)
                        .disabled(!blurred).opacity(blurred ? 1 : 0.45)
                    Text("Blur and Dim apply to Blurred Photo.", comment: "Mac Collage inspector")
                        .font(.system(size: 11)).foregroundStyle(MacTheme.Editor.secondaryText)
                    // The board: the name on the left, the switch on the right edge.
                    HStack {
                        Text("Polaroid", comment: "Mac Collage inspector: white frames with a caption band").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Toggle(String(localized: "Polaroid", comment: "Mac Collage inspector"),
                               isOn: Binding(get: { model.recipe.isPolaroid }, set: model.setPolaroid))
                            .labelsHidden()
                            .toggleStyle(.switch).controlSize(.small).tint(MacTheme.Editor.accent)
                            .accessibilityIdentifier("collage.polaroid")
                    }
                    .padding(.top, 6)
                }
                divider
                group(String(localized: "Text", comment: "Mac Collage inspector")) {
                    TextField(String(localized: "Add a Title", comment: "Mac Collage inspector: the title field"), text: $titleText)
                        .textFieldStyle(.roundedBorder)
                        .focused($focus, equals: .title)
                        .onSubmit { model.setTitle(titleText) }
                        .accessibilityIdentifier("collage.title")
                    if model.recipe.isPolaroid, let selected = model.selectedCell, model.recipe.cells.indices.contains(selected) {
                        TextField(String(localized: "Caption for Photo \(selected + 1)", comment: "Mac Collage inspector: Polaroid caption"),
                                  text: $caption)
                            .textFieldStyle(.roundedBorder)
                            .focused($focus, equals: .caption)
                            .onSubmit { model.setCaption(selected, caption) }
                            .accessibilityIdentifier("collage.caption")
                    }
                    Text(model.recipe.isPolaroid ? String(localized: "Select a photo to write its caption.", comment: "Mac Collage inspector")
                                                 : String(localized: "Captions under each photo come with Polaroid.", comment: "Mac Collage inspector"))
                        .font(.system(size: 11)).foregroundStyle(MacTheme.Editor.secondaryText)
                }
                divider
                HStack {
                    Text("Export Size", comment: "Mac Collage inspector").foregroundStyle(MacTheme.Editor.secondaryText)
                    Spacer()
                    Text(verbatim: "\(String(Int(model.outputSize.width))) × \(String(Int(model.outputSize.height))) · ~"
                         + ByteCountFormatter.string(fromByteCount: Int64(model.estimatedBytes(CollageExportOptions())), countStyle: .file))
                        .monospacedDigit()
                        .accessibilityIdentifier("collage.exportSize")
                }
            }
            .font(.system(size: 13))
            .padding(16)
        }
        .background(MacTheme.Editor.panelSolid)
        .onAppear(perform: refresh)
        .onChange(of: model.outputSize) { refresh() }
        .onChange(of: model.title) { titleText = model.title }
        // Leaving a field keeps what was typed (Return is not the only way out).
        .onChange(of: focus) { old, new in
            isTyping = new != nil
            switch old {
            case .title: model.setTitle(titleText)
            case .caption: if let cell = captionCell { model.setCaption(cell, caption) }
            case .width, .height: commitSize()
            case nil: break
            }
            if new == .caption { captionCell = model.selectedCell }
        }
        .onChange(of: model.selectedCell) { old, _ in
            // The caption typed for the photo that was selected stays with it.
            if focus == .caption, let old { model.setCaption(old, caption) }
            caption = model.selectedCell.map { model.recipe.cells.indices.contains($0) ? model.recipe.cells[$0].caption : "" } ?? "" }
    }

    private func commitSize() {
        guard let w = Int(width), let h = Int(height) else { refresh(); return }
        model.setSize(width: w, height: h)
        refresh()
    }

    private func refresh() {
        width = String(Int(model.outputSize.width))
        height = String(Int(model.outputSize.height))
        titleText = model.title
    }

    private func sizeField(_ text: Binding<String>, id: String) -> some View {
        HStack(spacing: 2) {
            sizeText(text, id: id)
            // The arrows: ±100 px, the other side following the aspect ratio.
            Stepper("", onIncrement: { step(id, by: 100) }, onDecrement: { step(id, by: -100) })
                .labelsHidden()
                .accessibilityLabel(id == "collage.width" ? String(localized: "Width", comment: "Mac Collage inspector")
                                                          : String(localized: "Height", comment: "Mac Collage inspector"))
                .accessibilityIdentifier(id + ".stepper")
        }
    }

    private func step(_ id: String, by delta: Int) {
        let size = model.outputSize, ratio = model.recipe.aspectRatio
        if id == "collage.width" {
            let w = Int(size.width) + delta
            model.setSize(width: w, height: Int((Double(w) / ratio).rounded()))
        } else {
            let h = Int(size.height) + delta
            model.setSize(width: Int((Double(h) * ratio).rounded()), height: h)
        }
        refresh()
    }

    private func sizeText(_ text: Binding<String>, id: String) -> some View {
        TextField("", text: text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 64)
            .focused($focus, equals: id == "collage.width" ? .width : .height)
            .onSubmit(commitSize)
            .accessibilityLabel(id == "collage.width" ? String(localized: "Width", comment: "Mac Collage inspector")
                                                      : String(localized: "Height", comment: "Mac Collage inspector"))
            .accessibilityIdentifier(id)
    }

    /// A slider with its label and value; one undo step per drag. `whole`:
    /// 0…100 rather than a percentage of the canvas.
    private func slider(_ title: String, value: Double, range: ClosedRange<Double>, id: String, whole: Bool = false,
                        set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 10) {
            Text(title).foregroundStyle(MacTheme.Editor.secondaryText).frame(width: 64, alignment: .leading)
            Slider(value: Binding(get: { value }, set: set), in: range) { editing in
                if editing { model.beginEdit() } else { model.endEdit() }
            }
            .controlSize(.small)
            .accessibilityLabel(title)
            .accessibilityIdentifier(id)
            Text(verbatim: whole ? String(Int((value * 100).rounded()))
                                 : (value).formatted(.percent.precision(.fractionLength(0...1))))
                .font(.system(size: 12)).monospacedDigit().foregroundStyle(MacTheme.Editor.secondaryText)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).foregroundStyle(MacTheme.Editor.secondaryText)
            Spacer()
            content()
        }
    }

    private var divider: some View { Divider().padding(.vertical, 18) }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(MacTheme.Editor.secondaryText)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

// MARK: - Export sheet

/// Export… (⇧⌘E): format, quality, metadata and where; the size is the
/// inspector's. A collage whose first photo is from Photos goes into Photos.
private struct MacCollageExportSheet: View {
    @Bindable var model: MacCollageModel
    @Environment(\.dismiss) private var dismiss
    @State private var options = CollageExportOptions()
    @State private var folder: MacResizeFolder?
    @State private var choosesFolder = false
    @State private var exportTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export Collage", comment: "Mac Collage: the export sheet's title").font(.system(size: 15, weight: .semibold))
            Form {
                Picker(String(localized: "Format", comment: "Mac Collage export"), selection: $options.format) {
                    ForEach(CollageExportFormat.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("collage.export.format")
                LabeledContent(String(localized: "Quality", comment: "Mac Collage export")) {
                    HStack {
                        Slider(value: $options.quality, in: 50...100, step: 5)
                            .accessibilityLabel(String(localized: "Quality", comment: "Mac Collage export"))
                            .accessibilityIdentifier("collage.export.quality")
                        Text(verbatim: String(Int(options.quality))).monospacedDigit().frame(width: 30, alignment: .trailing)
                    }
                }
                Toggle(String(localized: "Keep the first photo’s camera details", comment: "Mac Collage export: EXIF of the first photo"),
                       isOn: $options.keepFirstPhotoEXIF)
                    .accessibilityIdentifier("collage.export.metadata")
                LabeledContent(String(localized: "Save To", comment: "Mac Collage export")) {
                    Menu {
                        Button(sameTitle) { folder = nil }
                        Button(String(localized: "Choose Folder…", comment: "Mac Collage export")) { choosesFolder = true }
                    } label: {
                        Text(folder?.name ?? sameTitle)
                    }
                    .fixedSize()
                    .accessibilityIdentifier("collage.export.saveTo")
                }
            }
            .formStyle(.columns)
            Text(whereWords).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(verbatim: "\(String(Int(model.outputSize.width))) × \(String(Int(model.outputSize.height))) px · ~"
                 + ByteCountFormatter.string(fromByteCount: Int64(model.estimatedBytes(options)), countStyle: .file))
                .font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                .accessibilityIdentifier("collage.export.estimate")
            if let error = model.errorMessage {
                Text(error).font(.system(size: 12)).foregroundStyle(MacTheme.redText).accessibilityIdentifier("collage.export.error")
            }
            HStack {
                if model.isExporting {
                    ProgressView().controlSize(.small)
                    if let progress = model.exportProgress {
                        Text("Reading photos — \(progress.done) of \(progress.total)", comment: "Mac Collage export: under way").font(.system(size: 12))
                    } else {
                        Text("Exporting…", comment: "Mac Collage export: under way").font(.system(size: 12))
                    }
                }
                Spacer()
                // Cancel stops an export under way (nothing is written), else closes.
                Button(String(localized: "Cancel", comment: "Mac Collage export")) {
                    if let exportTask { exportTask.cancel() } else { dismiss() }
                }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("collage.export.cancel")
                Button(String(localized: "Export", comment: "Mac Collage export: write it")) {
                    exportTask = Task {
                        let wrote = await model.export(options, folder: folder)
                        exportTask = nil
                        if wrote { dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isExporting)
                .accessibilityIdentifier("collage.export.go")
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(MacTheme.sheet)
        .fileImporter(isPresented: $choosesFolder, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            Task {
                // A folder that can't be kept is said, not swapped for another place.
                if let picked = await Task.detached(operation: { MacResizeFolder(picked: url) }).value {
                    folder = picked
                } else {
                    model.errorMessage = String(localized: "ShotDex can’t keep access to that folder. Choose another one.",
                                                comment: "Mac Collage export: bookmark failed")
                }
            }
        }
        .onAppear { model.errorMessage = nil }
    }

    private var sameTitle: String {
        model.savesToPhotos ? String(localized: "Photos Library", comment: "Mac Collage export: Save To, first photo from Photos")
                            : String(localized: "Same Folder as First Photo", comment: "Mac Collage export: Save To")
    }

    private var whereWords: String {
        let name = model.fileName(options.format)
        if let folder { return String(localized: "\(name) in “\(folder.name)”.", comment: "Mac Collage export: where, a chosen folder") }
        if model.savesToPhotos { return String(localized: "\(name), a new photo in Photos.", comment: "Mac Collage export: where, Photos") }
        let place = model.firstPlaced?.localFileURL?.deletingLastPathComponent().lastPathComponent ?? ""
        return String(localized: "\(name) beside the first photo, in “\(place)”.", comment: "Mac Collage export: where, beside the first photo")
    }
}
