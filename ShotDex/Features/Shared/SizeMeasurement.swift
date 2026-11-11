import SwiftUI

extension View {
    /// Reports this view's width into `width` via a single background
    /// GeometryReader. Grids use this to size tiles from one measurement
    /// instead of hosting a GeometryReader in every cell (the scroll/pinch
    /// hitch at grid scale).
    func measureWidth(into width: Binding<CGFloat>) -> some View {
        background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { width.wrappedValue = geo.size.width }
                    .onChange(of: geo.size.width) { _, newValue in
                        width.wrappedValue = newValue
                    }
            }
        )
    }

    /// Reports this view's height into `height` via a background GeometryReader.
    /// The selection bar uses this so the grid can inset by the bar's measured
    /// height. (Avoids `onGeometryChange`, which is iOS 18+.)
    func measureHeight(into height: Binding<CGFloat>) -> some View {
        background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { height.wrappedValue = geo.size.height }
                    .onChange(of: geo.size.height) { _, newValue in
                        height.wrappedValue = newValue
                    }
            }
        )
    }
}

/// Where a sheet or tool stops being one column (`DESIGN.md` §10.1c).
///
/// Measured on the view itself, not taken from the size class: the inner
/// display of an iPhone Duo is regular width at 951pt, and so is a 704pt iPad
/// form sheet whose rows would be cut in two.
enum WideLayout {
    static let minimumWidth: CGFloat = 860
}

/// A form that turns into two columns of sections once it is wide enough
/// (`DESIGN.md` §10.1c: a wider screen gets more content, not longer rows).
///
/// Narrower than `WideLayout.minimumWidth` it is a single `Form`, the leading
/// sections above the trailing ones — the phone, and an iPad form sheet —
/// and `closing` last. Wider, each half is its own `Form` with its own
/// scroll, 20pt from the edges and 20pt apart, and `closing` ends the
/// leading one.
struct AdaptiveFormColumns<Leading: View, Trailing: View, Closing: View>: View {
    /// The leading column's width, margins excluded; nil splits in halves.
    var leadingWidth: CGFloat?
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing
    /// What acts on the fields — options, Test — so it follows them in one
    /// column and sits under the leading sections in two.
    @ViewBuilder var closing: () -> Closing

    @State private var width: CGFloat = 0

    var body: some View {
        Group {
            if width >= WideLayout.minimumWidth {
                HStack(alignment: .top, spacing: 0) {
                    Form {
                        leading()
                        closing()
                    }
                        .contentMargins(.leading, AppTheme.Spacing.xl, for: .scrollContent)
                        .contentMargins(.trailing, AppTheme.Spacing.xl / 2, for: .scrollContent)
                        .frame(width: leadingWidth.map { $0 + AppTheme.Spacing.xl * 1.5 })
                        .frame(maxWidth: leadingWidth == nil ? .infinity : nil)
                    Form { trailing() }
                        .contentMargins(.leading, AppTheme.Spacing.xl / 2, for: .scrollContent)
                        .contentMargins(.trailing, AppTheme.Spacing.xl, for: .scrollContent)
                        .frame(maxWidth: .infinity)
                }
                .background(Color(.systemGroupedBackground))
            } else {
                Form {
                    leading()
                    trailing()
                    closing()
                }
            }
        }
        .measureWidth(into: $width)
    }
}

extension AdaptiveFormColumns where Closing == EmptyView {
    init(leadingWidth: CGFloat? = nil,
         @ViewBuilder leading: @escaping () -> Leading,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.init(leadingWidth: leadingWidth, leading: leading, trailing: trailing, closing: { EmptyView() })
    }
}

/// How a long form opens (`DESIGN.md` §10.1c, DUO_LOOP 3b): as a sheet, except
/// on the Duo's inner display, where it covers the screen.
///
/// There a sheet is a 653pt form sheet on a 669pt-tall screen — `.page`
/// sizing measured the same — so `AdaptiveFormColumns` never reached its two
/// columns and the end of every long form sat below the edge. Full screen
/// gives it the 951pt it needs. The forms close with their own Cancel and
/// Done; nothing else changes on a phone, an iPad or the Duo's cover.
private struct FormPresentation<Item: Identifiable, Form: View>: ViewModifier {
    @Environment(\.isDuoInner) private var isDuoInner
    @Binding var item: Item?
    var onDismiss: (() -> Void)?
    @ViewBuilder var form: (Item) -> Form

    func body(content: Content) -> some View {
        content
            .sheet(item: isDuoInner ? .constant(nil) : $item, onDismiss: onDismiss, content: form)
            .fullScreenCover(item: isDuoInner ? $item : .constant(nil), onDismiss: onDismiss, content: form)
    }
}

private struct FormPresentationFlag<Form: View>: ViewModifier {
    @Environment(\.isDuoInner) private var isDuoInner
    @Binding var isPresented: Bool
    var onDismiss: (() -> Void)?
    @ViewBuilder var form: () -> Form

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: isDuoInner ? .constant(false) : $isPresented, onDismiss: onDismiss, content: form)
            .fullScreenCover(isPresented: isDuoInner ? $isPresented : .constant(false), onDismiss: onDismiss, content: form)
    }
}

extension View {
    /// A sheet that covers the screen on the Duo's inner display — see
    /// `FormPresentation`. For forms laid out with `AdaptiveFormColumns`.
    func formSheet<Item: Identifiable, Form: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Form
    ) -> some View {
        modifier(FormPresentation(item: item, onDismiss: onDismiss, form: content))
    }

    func formSheet<Form: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Form
    ) -> some View {
        modifier(FormPresentationFlag(isPresented: isPresented, onDismiss: onDismiss, form: content))
    }
}
