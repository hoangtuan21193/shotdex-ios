import SwiftUI

/// Makes the viewer a comparison host (FS-01.08c §1): over the pager it
/// draws the Compare stage while the mode is 2-Up or Survey, and in Single
/// it adds the mode control to the top bar where a mode can be picked —
/// any wide window, and a compact one only in a viewer opened as a
/// comparison (§7).
///
/// A modifier rather than code in `PhotoDetailScreen`, so the viewer keeps
/// one branch: is a comparison on screen or not.
struct CompareHost: ViewModifier {
    let source: any PhotoBrowsingSource
    /// Set by an entry point (a selection, Duplicates): the viewer opens in
    /// Compare.
    let request: CompareRequest?
    @Binding var currentIndex: Int
    /// Pages the viewer to a photo by id and rebuilds the page.
    let reveal: (String) -> Void
    /// True while the stage covers the pager — the viewer hides its chrome
    /// and its keys so a key never means two things.
    @Binding var isComparing: Bool
    /// Width the mode control takes at the top bar's trailing edge, so the
    /// viewer's info panel stops short of it (0 when there is none).
    @Binding var modePickerWidth: CGFloat
    /// The viewer's chrome is showing (not zoomed, not playing full screen).
    let showsChrome: Bool

    @Environment(AppDependencies.self) private var dependencies
    @Environment(PhotoMarks.self) private var photoMarks: PhotoMarks?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var compare: CompareModel?
    @State private var windowClass: VideoStudioWindowClass?
    @State private var hasStarted = false
    /// The photo Single went to after a delete. The source drops the deleted
    /// photos a moment later, which shifts positions, so the viewer is
    /// re-seated on it by id when the count changes.
    @State private var pendingSingleId: String?

    func body(content: Content) -> some View {
        content
            .overlay {
                if let compare, let windowClass, compare.session.mode != .single {
                    CompareStage(
                        model: compare,
                        windowClass: windowClass,
                        onClose: { dismiss() },
                        onSingle: showSingle(on:)
                    )
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .topTrailing) {
                if showsChrome, !isComparing, let windowClass {
                    singleModePicker(windowClass)
                        .padding(.trailing, CompareLayout.margin)
                        .padding(.top, windowClass == .duoInner ? CompareLayout.duoInnerTopInset : AppTheme.Spacing.sm)
                }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { measure(proxy) }
                        .onChange(of: proxy.size) { _, _ in measure(proxy) }
                }
            }
            .onChange(of: source.photoCount) { _, _ in
                guard let pendingSingleId else { return }
                self.pendingSingleId = nil
                reveal(pendingSingleId)
            }
            .onChange(of: compare?.session.mode) { _, mode in
                isComparing = mode != nil && mode != .single
            }
            .onChange(of: windowClass) { old, new in
                // The Duo closing mid-comparison: Survey and side-by-side
                // become the stacked Compare on the cover (§2, AC-14).
                guard let old, let new, !old.isCompact, new.isCompact else { return }
                compare?.session.fold()
            }
    }

    private func measure(_ proxy: GeometryProxy) {
        let insets = proxy.safeAreaInsets
        let window = VideoStudioWindowClass.windowSize(
            content: proxy.size,
            top: insets.top,
            bottom: insets.bottom,
            leading: insets.leading,
            trailing: insets.trailing
        )
        windowClass = VideoStudioWindowClass.resolve(window: window, trailingInset: insets.trailing)
        startIfRequested()
    }

    /// Opens straight into Compare when an entry point asked for it. Once:
    /// going back to Single is the user's choice and must stay.
    private func startIfRequested() {
        guard !hasStarted, let request else { return }
        hasStarted = true
        compare = .live(request: request, dependencies: dependencies, marks: photoMarks)
        compare?.onDeleted = request.onDeleted
        isComparing = compare != nil
    }

    // MARK: Single ↔ Compare

    @ViewBuilder
    private func singleModePicker(_ windowClass: VideoStudioWindowClass) -> some View {
        let modes = ViewerMode.available(for: windowClass, isComparing: compare != nil)
        if !modes.isEmpty {
            Picker(selection: Binding(get: { ViewerMode.single }, set: { enter($0) })) {
                ForEach(modes, id: \.self) { mode in
                    Text(mode.title(isCompact: windowClass.isCompact)).tag(mode)
                }
            } label: {
                Text("Viewer Mode", comment: "VoiceOver: the Single / 2-Up / Survey control")
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .fixedSize()
            .padding(4)
            .glassBackground(Capsule())
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                modePickerWidth = width + AppTheme.Spacing.sm
            }
            .onDisappear { modePickerWidth = 0 }
        }
    }

    /// From Single into 2-Up or Survey. A comparison already open picks up
    /// where it was; otherwise a wide window starts one on the photo on
    /// screen and the next cell of the grid (§7, AC-26).
    private func enter(_ mode: ViewerMode) {
        guard mode != .single else { return }
        if let compare {
            compare.session.mode = mode
        } else {
            let viewing = source.photoId(at: currentIndex)
            let session = viewing.flatMap {
                CompareSession(
                    viewing: $0,
                    next: source.photoId(at: currentIndex + 1),
                    previous: currentIndex > 0 ? source.photoId(at: currentIndex - 1) : nil,
                    mode: mode
                )
            }
            compare = .live(session: session, dependencies: dependencies, marks: photoMarks)
        }
        isComparing = compare != nil
    }

    /// Back to the pager on `id` — the segmented Single, or one photo left
    /// after a delete (§6).
    private func showSingle(on id: String) {
        compare?.session.mode = .single
        isComparing = false
        // After a delete the source still holds the deleted photos for a
        // moment; look again once it has dropped them.
        pendingSingleId = compare?.takeLastDeletion() != nil ? id : nil
        reveal(id)
    }
}

extension View {
    func compareHost(
        source: any PhotoBrowsingSource,
        request: CompareRequest?,
        currentIndex: Binding<Int>,
        reveal: @escaping (String) -> Void,
        isComparing: Binding<Bool>,
        modePickerWidth: Binding<CGFloat>,
        showsChrome: Bool
    ) -> some View {
        modifier(CompareHost(
            source: source,
            request: request,
            currentIndex: currentIndex,
            reveal: reveal,
            isComparing: isComparing,
            modePickerWidth: modePickerWidth,
            showsChrome: showsChrome
        ))
    }
}
