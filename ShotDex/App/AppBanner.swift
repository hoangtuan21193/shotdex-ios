import Observation
import SwiftUI

extension View {
    /// Shows the app banner above `bottomInset`. Every full-screen surface
    /// hosts it; a cover keeps the hosts below it alive, so only the host
    /// that appeared last — the one on top — draws it. `dark` is tier D, the
    /// editor.
    func appBannerHost(_ model: AppBannerModel, bottomInset: CGFloat, dark: Bool = false) -> some View {
        modifier(AppBannerHost(model: model, bottomInset: bottomInset, dark: dark))
    }
}

private struct AppBannerHost: ViewModifier {
    @Bindable var model: AppBannerModel
    let bottomInset: CGFloat
    let dark: Bool
    @State private var id = UUID()

    func body(content: Content) -> some View {
        let isTop = model.isTop(id)
        content
            .overlay(alignment: .bottom) {
                if isTop, let banner = model.current {
                    ActionToast(text: banner.text, actionTitle: banner.actionTitle, dark: dark) {
                        model.performAction()
                    }
                    .padding(.bottom, bottomInset)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: banner.id) {
                        // A host that stops drawing (another surface came
                        // up over it) cancels this; the banner moves to the
                        // new top host and starts its time again there.
                        do { try await Task.sleep(for: banner.duration) } catch { return }
                        withAnimation(AppTheme.Motion.standard) { model.expire(banner.id) }
                    }
                }
            }
            .animation(AppTheme.Motion.standard, value: model.current)
            .sheet(isPresented: Binding(
                get: { isTop && model.presentedReport != nil },
                set: { if !$0 { model.presentedReport = nil } }
            )) {
                if let report = model.presentedReport {
                    ReceivedReportSheet(report: report) { model.presentedReport = nil }
                }
            }
            .onAppear { model.appear(id) }
            .onDisappear { model.disappear(id) }
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
                // Four: a delete's banner says what went, what it freed and
                // where it is (FS-06.06b §3) without cutting a word.
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
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
