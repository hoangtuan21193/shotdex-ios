import Observation
import SwiftUI

/// The app-level banner (FS-03.14c §4, E9): "Golden added to My Looks" ·
/// Undo, over whatever screen is up — Library, the viewer or the editor —
/// because a file sent by AirDrop arrives wherever the user happens to be.
/// Not the editor's own 3 s undo toast, which only knows the editor.
@MainActor
@Observable
final class AppBannerModel {
    struct Banner: Identifiable, Equatable {
        let id = UUID()
        let text: String
        /// "Undo", "Details"; nil for a banner that only says something.
        let actionTitle: String?

        /// Long enough to read a line and reach the button; a plain line
        /// goes as quickly as the action toast.
        var duration: Duration {
            #if DEBUG
            if AppBannerModel.isSticky { return .seconds(3600) }
            #endif
            return actionTitle == nil ? .milliseconds(1600) : .seconds(4)
        }
    }

    private(set) var current: Banner?
    private var action: (() -> Void)?

    #if DEBUG
    /// `-ShotDexStickyBanner`: a UI script photographs the banner on each
    /// screen, which a four-second banner does not survive.
    nonisolated static let isSticky = ProcessInfo.processInfo.arguments.contains("-ShotDexStickyBanner")

    init() {
        if Self.isSticky { show("Golden added to My Looks", actionTitle: "Undo") {} }
    }
    #endif

    /// A new banner replaces the one showing; its button runs `action`.
    func show(_ text: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        current = Banner(text: text, actionTitle: action == nil ? nil : actionTitle)
        self.action = action
    }

    func performAction() {
        let action = action
        dismiss()
        action?()
    }

    func dismiss() {
        current = nil
        action = nil
    }

    /// The timer's end: only the banner it was started for goes.
    func expire(_ id: Banner.ID) {
        guard current?.id == id else { return }
        dismiss()
    }
}

extension View {
    /// Shows the app banner above `bottomInset`. Every full-screen surface
    /// hosts it — a cover hides the hosts below it, so the topmost one is
    /// the one seen. `dark` is tier D, the editor.
    func appBannerHost(_ model: AppBannerModel, bottomInset: CGFloat, dark: Bool = false) -> some View {
        overlay(alignment: .bottom) {
            if let banner = model.current {
                ActionToast(text: banner.text, actionTitle: banner.actionTitle, dark: dark) {
                    model.performAction()
                }
                .padding(.bottom, bottomInset)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: banner.id) {
                    try? await Task.sleep(for: banner.duration)
                    withAnimation(AppTheme.Motion.standard) { model.expire(banner.id) }
                }
            }
        }
        .animation(AppTheme.Motion.standard, value: model.current)
    }
}

/// A brief capsule confirming something that leaves no visible trace, with
/// an optional button — Undo, Details.
struct ActionToast: View {
    let text: String
    var actionTitle: String?
    var dark = false
    var action: () -> Void = {}

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text(text)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            if let actionTitle {
                Divider()
                    .frame(height: 18)
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: AppTheme.Size.minTouch)
                    .contentShape(Rectangle())
            }
        }
        .foregroundStyle(dark ? Color.white : Color.primary)
        .padding(.horizontal, AppTheme.Spacing.xl)
        .frame(minHeight: AppTheme.Size.minTouch)
        .modifier(ActionToastBackground(dark: dark))
        .padding(.horizontal, AppTheme.Size.screenMargin)
        .allowsHitTesting(actionTitle != nil)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: actionTitle ?? "") { action() }
    }
}

private struct ActionToastBackground: ViewModifier {
    let dark: Bool

    func body(content: Content) -> some View {
        if dark {
            content.editorGlass(Capsule())
        } else {
            content.glassBackground(Capsule())
        }
    }
}
