import Photos
import SwiftUI

/// The library window's full-screen state, and the way to leave it.
@MainActor
final class MacFullScreenControl {
    weak var window: NSWindow?
    var isFullScreen: Bool { window?.styleMask.contains(.fullScreen) ?? false }
    func toggle() { window?.toggleFullScreen(nil) }
}

/// Reports this view's window entering and leaving full screen.
struct MacFullScreenObserver: NSViewRepresentable {
    let control: MacFullScreenControl
    let changed: (Bool) -> Void

    func makeNSView(context: Context) -> NSView { Probe(control: control, changed: changed) }
    func updateNSView(_ nsView: NSView, context: Context) { (nsView as? Probe)?.changed = changed }

    final class Probe: NSView {
        let control: MacFullScreenControl
        var changed: (Bool) -> Void
        private var tokens: [NSObjectProtocol] = []

        init(control: MacFullScreenControl, changed: @escaping (Bool) -> Void) {
            self.control = control
            self.changed = changed
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        deinit { tokens.forEach(NotificationCenter.default.removeObserver) }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens = []
            control.window = window
            guard let window else { return }
            // A window macOS restored in full screen sends no notification: read it.
            let isFull = window.styleMask.contains(.fullScreen)
            DispatchQueue.main.async { [weak self] in self?.changed(isFull) }
            for (name, isFull) in [(NSWindow.didEnterFullScreenNotification, true), (NSWindow.didExitFullScreenNotification, false)] {
                tokens.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.changed(isFull) }
                })
            }
        }
    }
}

/// The last pointer move, kept off `body` so a move does not re-render the viewer.
@MainActor
final class MacViewerMoveClock {
    var date = Date.now
    /// The pointer rests on the HUD (picking a star, a zoom): it stays.
    var isOverHUD = false
}

/// The part of the photo on screen, normalized to 0…1; only the Navigator observes it.
@MainActor @Observable
final class MacViewerViewport {
    var rect: CGRect?

    /// Shown while the photo is bigger than the screen (board), not before the first scroll geometry.
    var zoomedRect: CGRect? {
        guard let rect, !rect.isEmpty, rect.width < 0.999 || rect.height < 0.999 else { return nil }
        return rect
    }
}

/// The viewer's zoom steps in full screen: Fit, then the percentages −/+ walk.
enum MacViewerZoomSteps {
    static let percents = [25, 50, 100, 200, 400]

    static func title(_ percent: Int?) -> String {
        percent.map { "\($0)%" } ?? String(localized: "Fit", comment: "Mac viewer zoom: the whole photo in the window")
    }

    /// − and + walk the steps in order of size with Fit (nil) in its place
    /// among them: `fit` is the percentage Fit shows this photo at, so a small
    /// photo Fit already blows up past 100% gets bigger on +, not smaller.
    /// Unknown, Fit sits just under 100%.
    static func zoomIn(_ percent: Int?, fit: Double?) -> Int? {
        let fit = fit ?? 99
        let current = percent.map(Double.init) ?? fit
        let next = percents.first { Double($0) > current }
        if percent != nil, current < fit, next.map({ Double($0) >= fit }) ?? true { return nil }
        return next ?? percent
    }

    static func zoomOut(_ percent: Int?, fit: Double?) -> Int? {
        let fit = fit ?? 99
        let current = percent.map(Double.init) ?? fit
        let previous = percents.last { Double($0) < current }
        if percent != nil, current > fit, previous.map({ Double($0) <= fit }) ?? true { return nil }
        return previous ?? percent
    }
}

/// One photo on the whole screen (board `MAC_ViewerFullScreen`): the
/// picture edge to edge on black, a HUD at the bottom — ‹ name and place ›,
/// zoom − / level / +, stars, inspector — shown while the pointer moves and
/// hidden after 2 s still, and a Navigator top right while zoomed in.
/// Esc or ⌃⌘F leaves full screen; the viewer stays open in the window.
struct MacViewerFullScreen: View {
    @Binding var photoId: String?
    let ids: [String]
    let positions: [String: Int]
    let title: String
    let menu: MacPhotoMenu?
    let marks: LibraryTableQueries.Details?
    var picture: ((String) -> CGImage?)?
    var asset: (String) -> PHAsset?
    @Binding var showsInspector: Bool
    let exit: () -> Void

    @State private var percent: Int?
    @State private var showsHUD = true
    @State private var hideTask: Task<Void, Never>?
    /// When the pointer last moved: read by the hide timer, never by `body`.
    @State private var lastMove = MacViewerMoveClock()
    /// Written per scroll frame while panning: only the Navigator reads it.
    @State private var viewport = MacViewerViewport()
    /// The screen and the photo, for the percentage Fit shows the photo at.
    @State private var screen = CGSize.zero
    @State private var pixelSize: CGSize?
    @Environment(\.displayScale) private var displayScale
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let photoId {
                MacViewerPhoto(id: photoId, zoom: percent == nil ? .fit : .actual, picture: picture, asset: asset,
                               percent: percent, insets: false, onViewport: { [viewport] in viewport.rect = $0 })
                    .ignoresSafeArea()
                    // A click on the photo takes the keys back from a field in the inspector.
                    .simultaneousGesture(TapGesture().onEnded { isFocused = true })
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { screen = $0 }
        .overlay(alignment: .topTrailing) {
            if percent != nil, let photoId {
                MacViewerNavigator(photoId: photoId, viewport: viewport, percent: percent, picture: picture)
                    .padding(24)
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            hud
                .onHover { [lastMove] over in
                    lastMove.isOverHUD = over
                    if !over { poke() }
                }
                .padding(.bottom, 72)
                .opacity(showsHUD ? 1 : 0)
                .allowsHitTesting(showsHUD)
        }
        .animation(.easeOut(duration: 0.2), value: showsHUD)
        .onContinuousHover { _ in poke() }
        .onAppear { isFocused = true; poke() }
        .onDisappear { hideTask?.cancel(); hideTask = nil }
        .task(id: photoId) { await loadPixelSize() }
        // Each photo starts whole, as Photos: a cull lands on the frame, not mid-crop.
        .onChange(of: photoId) { percent = nil; viewport.rect = nil; isFocused = true }
        // Back to Fit: the next zoom starts a new scroll view, so no old rect.
        .onChange(of: percent) { if percent == nil { viewport.rect = nil } }
        .onReceive(NotificationCenter.default.publisher(for: .macViewerTakeKeys)) { _ in isFocused = true }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(keys: [.leftArrow, .rightArrow], phases: [.down, .repeat]) { press in
            step(press.key == .leftArrow ? -1 : 1, beeps: press.phase == .down)
            poke()
            return .handled
        }
        // Esc leaves full screen; the viewer stays, as Photos.
        .onKeyPress(.escape) { exit(); return .handled }
        .onKeyPress(phases: .down) { press in
            guard press.modifiers.isEmpty, let key = press.characters.first else { return .ignored }
            poke()
            switch key {
            case "z": percent = percent == nil ? 100 : nil
            case ".": if let id = photoId { menu?.toggleFavorite([id]) }
            default:
                guard let id = photoId, let action = MarkKeyCommand.action(for: key) else { return .ignored }
                menu?.apply(action, to: [id])
            }
            return .handled
        }
    }

    /// The HUD shows on any movement and goes after 2 s without one. Called
    /// per pointer event, so it only stamps the time; one timer runs at a time.
    private func poke() {
        lastMove.date = .now
        if !showsHUD { showsHUD = true }
        guard hideTask == nil else { return }
        hideTask = Task { [lastMove] in
            while !Task.isCancelled {
                let left = lastMove.isOverHUD ? 2 : 2 - Date.now.timeIntervalSince(lastMove.date)
                if left <= 0 { break }
                try? await Task.sleep(for: .seconds(left))
            }
            guard !Task.isCancelled else { return }
            hideTask = nil
            showsHUD = false
        }
    }

    /// The percentage Fit shows this photo at (100 = one photo pixel per screen pixel).
    private var fitPercent: Double? {
        guard let pixels = pixelSize, pixels.width > 0, pixels.height > 0, screen.width > 0, screen.height > 0 else { return nil }
        return min(screen.width / pixels.width, screen.height / pixels.height) * displayScale * 100
    }

    /// The photo's pixel size, read once per photo off the main thread (a PhotoKit fetch).
    private func loadPixelSize() async {
        pixelSize = nil
        guard let id = photoId else { return }
        if let picture {
            pixelSize = picture(id).map { CGSize(width: $0.width, height: $0.height) }
            return
        }
        let size = await Task.detached(priority: .userInitiated) {
            PhotoLibraryService.fetchAssets(ids: [id]).first.map { CGSize(width: $0.pixelWidth, height: $0.pixelHeight) }
        }.value
        guard !Task.isCancelled else { return }
        pixelSize = size
    }

    private func step(_ delta: Int, beeps: Bool) {
        guard let id = photoId, let index = positions[id] else { return }
        let next = index + delta
        guard ids.indices.contains(next) else { if beeps { NSSound.beep() }; return }
        photoId = ids[next]
    }

    private var position: String {
        guard let id = photoId, let index = positions[id] else { return "" }
        return String(localized: "\(index + 1) of \(ids.count)", comment: "Mac viewer: the photo's place in the grid")
    }

    private var hud: some View {
        let rating = marks?.rating ?? 0
        let fit = fitPercent
        let zoomedOut = MacViewerZoomSteps.zoomOut(percent, fit: fit)
        let zoomedIn = MacViewerZoomSteps.zoomIn(percent, fit: fit)
        return HStack(spacing: 4) {
            hudButton("chevron.left", String(localized: "Previous Photo", comment: "Mac full-screen viewer"),
                      help: String(localized: "Previous (←)", comment: "Mac full-screen viewer tooltip")) { step(-1, beeps: true) }
            VStack(spacing: 0) {
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(position).font(.system(size: 11)).foregroundStyle(MacTheme.hudSecondary).monospacedDigit()
            }
            .frame(minWidth: 112)
            .padding(.horizontal, 6)
            .help(String(localized: "Exit Full Screen (Esc)", comment: "Mac full-screen viewer tooltip on the photo's name"))
            hudButton("chevron.right", String(localized: "Next Photo", comment: "Mac full-screen viewer"),
                      help: String(localized: "Next (→)", comment: "Mac full-screen viewer tooltip")) { step(1, beeps: true) }
            divider
            hudButton("minus.magnifyingglass", String(localized: "Zoom Out", comment: "Mac full-screen viewer"),
                      help: String(localized: "Zoom Out", comment: "Mac full-screen viewer tooltip")) {
                percent = zoomedOut
            }
            .disabled(zoomedOut == percent)
            Menu {
                Button(MacViewerZoomSteps.title(nil)) { percent = nil }
                ForEach(MacViewerZoomSteps.percents, id: \.self) { step in
                    Button(MacViewerZoomSteps.title(step)) { percent = step }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(MacViewerZoomSteps.title(percent)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(MacTheme.hudSecondary)
                }
                .padding(.horizontal, 8)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .frame(minWidth: 68, minHeight: 28)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .help(String(localized: "Zoom (Z toggles Fit and 100%)", comment: "Mac full-screen viewer tooltip"))
            .accessibilityLabel(String(localized: "Zoom Level", comment: "Mac full-screen viewer"))
            .accessibilityValue(MacViewerZoomSteps.title(percent))
            hudButton("plus.magnifyingglass", String(localized: "Zoom In", comment: "Mac full-screen viewer"),
                      help: String(localized: "Zoom In", comment: "Mac full-screen viewer tooltip")) {
                percent = zoomedIn
            }
            .disabled(zoomedIn == percent)
            divider
            ForEach(1...5, id: \.self) { star in
                Button {
                    if let id = photoId { menu?.apply(.rate(rating == star ? 0 : star), to: [id]) }
                } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star").font(.system(size: 12))
                        .frame(width: 22, height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(AttributedString(localized: "Rate ^[\(star) Star](inflect: true)", comment: "Mac full-screen viewer: a star button").characters))
                .help(String(AttributedString(localized: "^[\(star) Star](inflect: true) (\(star))", comment: "Mac full-screen viewer tooltip: a star button and its key").characters))
                .accessibilityAddTraits(star <= rating ? [.isSelected] : [])
            }
            divider
            hudButton("sidebar.right", showsInspector ? String(localized: "Hide Inspector", comment: "Mac toolbar")
                                                      : String(localized: "Show Inspector", comment: "Mac toolbar"),
                      help: showsInspector ? String(localized: "Hide Inspector (⌥⌘I)", comment: "Mac full-screen viewer tooltip")
                                           : String(localized: "Show Inspector (⌥⌘I)", comment: "Mac full-screen viewer tooltip")) {
                showsInspector.toggle()
            }
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 6)
        .frame(height: 44)
        .background(.ultraThinMaterial, in: Capsule())
        .background(MacTheme.hudFill, in: Capsule())
        .overlay(Capsule().strokeBorder(MacTheme.hudStroke))
        .shadow(color: .black.opacity(0.45), radius: 9, y: 4)
        .environment(\.colorScheme, .dark)
    }

    private var divider: some View {
        Rectangle().fill(MacTheme.hudSeparator).frame(width: 1, height: 20).padding(.horizontal, 4)
    }

    private func hudButton(_ symbol: String, _ label: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: { action(); poke() }) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                .frame(width: 36, height: 32).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(help)
    }
}

/// While zoomed in (board): the whole photo small, the part on screen
/// framed, the zoom level under it.
struct MacViewerNavigator: View {
    let photoId: String
    /// The part on screen, in the photo's unit square.
    let viewport: MacViewerViewport
    let percent: Int?
    var picture: ((String) -> CGImage?)?
    @Environment(MacDependencies.self) private var dependencies
    @State private var image: CGImage?

    var body: some View {
        if let rect = viewport.zoomedRect { panel(rect) }
    }

    private func panel(_ viewport: CGRect) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // A fixed 200×133 box (board): a portrait or a pano fits inside it.
            ZStack {
                if let image {
                    Image(decorative: image, scale: 2).resizable().scaledToFit()
                        .overlay {
                            GeometryReader { proxy in
                                    let frame = CGRect(x: viewport.minX * proxy.size.width, y: viewport.minY * proxy.size.height,
                                                       width: max(6, viewport.width * proxy.size.width), height: max(6, viewport.height * proxy.size.height))
                                    // Outside the part on screen dims; the frame reads on a bright sky too.
                                    Path { path in
                                        path.addRect(CGRect(origin: .zero, size: proxy.size))
                                        path.addRect(frame)
                                    }
                                    .fill(.black.opacity(0.35), style: FillStyle(eoFill: true))
                                    RoundedRectangle(cornerRadius: 2).strokeBorder(.white, lineWidth: 1.5)
                                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.black.opacity(0.35), lineWidth: 1).padding(-1))
                                        .frame(width: frame.width, height: frame.height)
                                        .offset(x: frame.minX, y: frame.minY)
                            }
                        }
                } else {
                    Color.white.opacity(0.08)
                }
            }
            .frame(width: 200, height: 133)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            HStack {
                Text("Zoom", comment: "Mac full-screen viewer: the navigator's label").font(.system(size: 11)).foregroundStyle(MacTheme.hudSecondary)
                Spacer()
                Text(MacViewerZoomSteps.title(percent)).font(.system(size: 11, weight: .semibold)).monospacedDigit()
            }
            .frame(height: 22)
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(8)
        .frame(width: 216)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(MacTheme.hudFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(MacTheme.hudStroke))
        .shadow(color: .black.opacity(0.45), radius: 9, y: 4)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Navigator", comment: "Mac full-screen viewer: the zoomed photo's overview"))
        .accessibilityValue(MacViewerZoomSteps.title(percent))
        .task(id: photoId) {
            if let picture { image = picture(photoId); return }
            image = await MacViewerThumbnail.load(photoId, side: 400, dependencies: dependencies)
        }
    }
}
