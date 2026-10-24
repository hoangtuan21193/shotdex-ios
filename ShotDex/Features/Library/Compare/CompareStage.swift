import Photos
import SwiftUI

/// Compare inside the viewer (FS-01.08c): the stage that replaces the pager
/// when the mode is not Single. 2-Up side by side on a wide window, stacked
/// (Select above, Candidate below) on a compact one, Survey on a wide one.
///
/// Same background, same light/dark and the same Close as the viewer —
/// semantic colours only, no tier-D black (§1, DESIGN.md §2).
struct CompareStage: View {
    @Bindable var model: CompareModel
    let windowClass: VideoStudioWindowClass
    /// Leaves the viewer — Close, `Esc`, or nothing left after a delete.
    let onClose: () -> Void
    /// The segmented control picked Single, or a delete left one photo:
    /// the viewer goes back to its pager on this photo.
    let onSingle: (String) -> Void

    @Environment(AppDependencies.self) private var dependencies
    @Environment(UnsupportedRAWIndex.self) private var unsupportedRAWIndex: UnsupportedRAWIndex?
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Rejected photos that reach a folder, a drive or a server, waiting on
    /// the ShotDex confirmation (FS-19.04 §2, 08c AC-13 AC-23 AC-24).
    @State private var sourceDeletion: DeletionTargetQueries.Request?

    private var isCompact: Bool { windowClass.isCompact }
    /// iPad: the commands sit in the top bar. Everywhere else they sit in a
    /// bottom bar where the viewer keeps its own.
    private var hasToolbarOnTop: Bool { windowClass == .iPadLandscape || windowClass == .iPadPortrait }
    /// The cover keeps no status bar above the app, so its top bar would sit
    /// in the display's ~37pt corner curve: it starts 28pt down, as
    /// `DC_Compare` draws it.
    private var topInset: CGFloat {
        switch windowClass {
        case .duoCover: 28
        case .duoInner: CompareLayout.duoInnerTopInset
        default: AppTheme.Spacing.sm
        }
    }

    private var modes: [ViewerMode] { ViewerMode.available(for: windowClass, isComparing: true) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, CompareLayout.margin)
                .padding(.top, topInset)
                .padding(.bottom, AppTheme.Spacing.md)
            stage
            if !hasToolbarOnTop {
                bottomArea
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .background { keyButtons }
        .overlay(alignment: .top) { blockedBanner }
        .sensoryFeedback(.warning, trigger: model.blockedToken)
        .animation(reduceMotion ? nil : AppTheme.Motion.standard, value: model.session)
        .sourceDeletion($sourceDeletion) { removed, _ in
            if !removed.isEmpty { dependencies.sources.photosDeleted() }
            go(model.removedThroughSources(removed))
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            GlassIconButton(systemImage: "xmark", accessibilityLabel: String(localized: "Close")) {
                onClose()
            }
            .keyboardShortcut(.escape, modifiers: [])
            titleBlock
            Spacer(minLength: 0)
            modePicker
            if hasToolbarOnTop {
                zoomMenu
                makeSelectButton(labelled: false)
                    .disabled(model.session.mode == .survey)
                shareButton
                deleteButton
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.session.title)
                .font(.headline)
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .layoutPriority(1)
    }

    private var subtitle: String? {
        if hasToolbarOnTop, model.session.mode == .twoUp {
            return [model.flagSummary, model.session.candidateLabel].compactMap { $0 }.joined(separator: " · ")
        }
        return model.flagSummary
    }

    private var modePicker: some View {
        Picker(selection: Binding(
            get: { model.session.mode },
            set: { select(mode: $0) }
        )) {
            ForEach(modes, id: \.self) { mode in
                Text(mode.title(isCompact: isCompact)).tag(mode)
            }
        } label: {
            Text("Viewer Mode", comment: "VoiceOver: the Single / 2-Up / Survey control")
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .fixedSize()
    }

    private func select(mode: ViewerMode) {
        guard mode != model.session.mode else { return }
        if mode == .single {
            onSingle(model.session.workingId)
        } else {
            model.session.mode = mode
        }
    }

    /// Fit · 100% (§3). The checkmark follows the zoom the frames are at.
    private var zoomMenu: some View {
        Menu {
            Picker(selection: Binding(
                get: { CompareZoom.level(zoomScale: model.zoomScale) },
                set: { zoom(to: $0) }
            )) {
                Text("Fit", comment: "Compare zoom: the whole photo in its frame").tag(CompareZoom.fit)
                Text("100%", comment: "Compare zoom: one original pixel per screen pixel").tag(CompareZoom.actualPixels)
            } label: {
                EmptyView()
            }
        } label: {
            Text(zoomTitle)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .padding(.horizontal, AppTheme.Spacing.md)
                .frame(height: AppTheme.Size.minTouch)
                .glassBackground(Capsule())
        }
        .disabled(model.session.mode == .survey)
        .accessibilityLabel(Text("Zoom", comment: "VoiceOver: Compare's Fit / 100% menu"))
    }

    private var zoomTitle: String {
        CompareZoom.level(zoomScale: model.zoomScale) == .fit
            ? String(localized: "Fit", comment: "Compare zoom: the whole photo in its frame")
            : "100%"
    }

    /// Zooms the working frame (Select when it is not on screen) and lets
    /// the synchronizer carry the others.
    private func zoom(to level: CompareZoom) {
        let id = model.session.visibleIds.contains(model.session.workingId)
            ? model.session.workingId
            : model.session.selectId
        guard let index = model.session.visibleIds.firstIndex(of: id) else { return }
        let scale: CGFloat = switch level {
        case .fit: 1
        case .actualPixels:
            CompareZoom.actualPixelsScale(
                pixelSize: model.pixelSize(for: id),
                box: lastPhotoBox,
                screenScale: displayScale
            )
        }
        model.sync.zoom(frameAt: paneIndex(for: id, fallback: index), to: scale)
    }

    /// The photo box the stage last laid out, for 100%.
    @State private var lastPhotoBox: CGSize = .zero

    // MARK: Stage

    private var stage: some View {
        GeometryReader { proxy in
            let area = proxy.size
            Group {
                switch model.session.mode {
                case .survey:
                    surveyGrid(area: area)
                default:
                    if isCompact {
                        stacked(area: area)
                    } else {
                        sideBySide(area: area)
                    }
                }
            }
            .frame(width: area.width, height: area.height, alignment: .top)
        }
    }

    private func stacked(area: CGSize) -> some View {
        let metrics = CompareLayout.twoUpMetrics(for: windowClass)
        let frame = CompareLayout.stacked(area: area, metrics: metrics)
        return VStack(spacing: metrics.gap) {
            pane(model.session.selectId, role: .select, frame: frame)
            pane(model.session.candidateId, role: .candidate, frame: frame)
        }
        .frame(maxWidth: .infinity)
        .onAppear { lastPhotoBox = frame.photo }
        .onChange(of: frame) { _, new in lastPhotoBox = new.photo }
    }

    private func sideBySide(area: CGSize) -> some View {
        let metrics = CompareLayout.twoUpMetrics(for: windowClass)
        let frame = CompareLayout.twoUp(area: area, metrics: metrics)
        return HStack(alignment: .top, spacing: CompareLayout.sideBySideGap) {
            pane(model.session.selectId, role: .select, frame: frame)
            pane(model.session.candidateId, role: .candidate, frame: frame)
        }
        .frame(maxWidth: .infinity)
        .onAppear { lastPhotoBox = frame.photo }
        .onChange(of: frame) { _, new in lastPhotoBox = new.photo }
    }

    private func surveyGrid(area: CGSize) -> some View {
        let metrics: CompareLayout.SurveyMetrics = windowClass == .duoInner ? .duoInner : .wide
        let layout = CompareLayout.survey(count: model.session.count, area: area, metrics: metrics)
        let columns = Array(
            repeating: GridItem(.fixed(layout.cell.width), spacing: metrics.columnGap, alignment: .top),
            count: layout.columns
        )
        return ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: metrics.rowGap) {
                ForEach(model.session.ids, id: \.self) { id in
                    pane(
                        id,
                        role: .survey,
                        frame: CompareLayout.Frame(size: layout.cell, photo: layout.photo),
                        surveyMetrics: metrics
                    )
                }
            }
            .padding(.horizontal, CompareLayout.margin)
        }
        .scrollDisabled(!layout.scrolls)
        .scrollIndicators(layout.scrolls ? .automatic : .hidden)
    }

    /// Stable synchronizer slots: Select is 0, Candidate 1, Survey cells
    /// by their place in the comparison — so swapping roles re-registers
    /// rather than mirroring into a frame that left.
    private func paneIndex(for id: String, fallback: Int) -> Int {
        switch model.session.mode {
        case .survey: model.session.ids.firstIndex(of: id) ?? fallback
        default: id == model.session.selectId ? 0 : 1
        }
    }

    private func pane(
        _ id: String,
        role: ComparePane.Role,
        frame: CompareLayout.Frame,
        surveyMetrics: CompareLayout.SurveyMetrics? = nil
    ) -> some View {
        ComparePane(
            model: model,
            id: id,
            role: role,
            frame: frame,
            style: paneStyle(surveyMetrics: surveyMetrics),
            paneIndex: paneIndex(for: id, fallback: 0),
            onShare: { share(id) },
            onSingle: onSingle
        )
        .id(role == .survey ? id : "\(role)-\(id)")
    }

    private func paneStyle(surveyMetrics: CompareLayout.SurveyMetrics?) -> ComparePane.Style {
        if surveyMetrics != nil { return windowClass == .duoInner ? .surveyCompact : .surveyWide }
        switch windowClass {
        case .duoCover: return .cover
        case .phone, .duoInner: return .cullRow
        case .iPadLandscape, .iPadPortrait: return .wide
        }
    }

    // MARK: Bottom bar

    private var bottomArea: some View {
        VStack(alignment: .trailing, spacing: 14) {
            Text("Touch and hold to keep only this one", comment: "Compare: hint above Delete once a photo is Rejected")
                .font(.caption)
                .foregroundStyle(.secondary)
                .opacity(model.rejectedIds.isEmpty ? 0 : 1)
                .accessibilityHidden(model.rejectedIds.isEmpty)
            HStack(spacing: AppTheme.Spacing.sm) {
                shareButton
                Spacer(minLength: AppTheme.Spacing.sm)
                GlassPanel(cornerRadius: AppTheme.Radius.xl) {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        makeSelectButton(labelled: true)
                            .disabled(model.session.mode == .survey)
                        moreMenu
                    }
                    .padding(.horizontal, AppTheme.Spacing.xs)
                }
                Spacer(minLength: AppTheme.Spacing.sm)
                deleteButton
            }
        }
        .padding(.horizontal, CompareLayout.margin)
        .padding(.top, 12)
        .padding(.bottom, AppTheme.Spacing.md)
    }

    private var shareButton: some View {
        GlassIconButton(systemImage: "square.and.arrow.up", accessibilityLabel: String(localized: "Share")) {
            share(model.session.workingId)
        }
    }

    /// Candidate becomes Select (§3); `↑` on a keyboard.
    private func makeSelectButton(labelled: Bool) -> some View {
        Button {
            model.session.makeSelect()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: labelled ? 17 : 18, weight: .medium))
                if labelled {
                    Text("Make Select", comment: "Compare: swap Candidate and Select")
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(.primary)
            .frame(minWidth: AppTheme.Size.minTouch, minHeight: AppTheme.Size.minTouch)
            .padding(.horizontal, labelled ? AppTheme.Spacing.xs : 0)
            .modifier(TopBarGlass(isActive: !labelled))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.upArrow, modifiers: [])
        .accessibilityLabel(Text("Make Select", comment: "Compare: swap Candidate and Select"))
    }

    private struct TopBarGlass: ViewModifier {
        let isActive: Bool
        func body(content: Content) -> some View {
            if isActive { content.glassBackground(Circle()) } else { content }
        }
    }

    private var moreMenu: some View {
        Menu {
            workingFrameActions
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: AppTheme.Size.minTouch, height: AppTheme.Size.minTouch)
                .contentShape(Rectangle())
        }
        .tint(.primary)
        .accessibilityLabel(Text("More actions", comment: "VoiceOver: Compare's overflow menu"))
    }

    @ViewBuilder private var workingFrameActions: some View {
        let id = model.session.workingId
        if model.session.canRemove {
            Button {
                model.session.remove(id)
            } label: {
                Label(ComparePane.removeTitle, systemImage: "minus.circle")
            }
        }
        Button(role: .destructive) {
            Task { await model.keepOnly(id) }
        } label: {
            Label(ComparePane.keepOnlyTitle, systemImage: "checkmark.circle")
        }
    }

    /// Red text, not a red fill: it acts on flags already set, so it does
    /// not shout (§5). Dimmed, not hidden, at none (AC-22).
    private var deleteButton: some View {
        Button {
            Task { await deleteRejected() }
        } label: {
            Label(model.deleteTitle, systemImage: "trash")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(.red)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .frame(height: hasToolbarOnTop ? AppTheme.Size.minTouch : 52)
                .glassBackground(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!model.canDelete)
        .opacity(model.canDelete ? 1 : 0.4)
        .keyboardShortcut(.delete, modifiers: .command)
    }

    private func deleteRejected() async {
        let result = await model.deleteRejected()
        if let request = result.sourceRequest {
            sourceDeletion = request
            return
        }
        go(result.next)
    }

    private func go(_ next: CompareSession.AfterDeletion?) {
        switch next {
        case .single(let id):
            onSingle(id)
        case .grid:
            onClose()
        case .stay, nil:
            break
        }
    }

    private func share(_ id: String) {
        guard let asset = model.asset(for: id) else { return }
        let downloads = dependencies.originalDownloads
        let unreadable = unsupportedRAWIndex?.assetIds ?? []
        Task { await PhotoShareSheet.share(assets: [asset], downloads: downloads, unreadableRAW: unreadable) }
    }

    // MARK: Keys

    /// `0–5 P X U` on the working frame, `←`/`→` through the candidates,
    /// `Z` Fit ↔ 100% (§1, §3). Hidden buttons, so a key and a tap run the
    /// same code.
    private var keyButtons: some View {
        ZStack {
            ForEach(MarkKeyCommand.bindings, id: \.key) { binding in
                Button(binding.action.shortcutTitle) {
                    Task { await model.apply(binding.action) }
                }
                .keyboardShortcut(KeyEquivalent(binding.key), modifiers: [])
            }
            Button(MarkCopy.nextPhoto) { model.session.nextCandidate() }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button(MarkCopy.previousPhoto) { model.session.previousCandidate() }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button(MarkCopy.zoom) { zoom(to: CompareZoom.level(zoomScale: model.zoomScale).toggled()) }
                .keyboardShortcut("z", modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    // MARK: Gate

    @ViewBuilder private var blockedBanner: some View {
        if let message = model.blockedMessage {
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.md)
                .glassBackground(Capsule())
                .padding(.top, 72)
                .transition(.opacity)
                .accessibilityAddTraits(.isStaticText)
        }
    }
}
