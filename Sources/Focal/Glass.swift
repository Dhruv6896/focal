import SwiftUI

// Liquid Glass on macOS 26 and later, with a quiet solid fallback on older systems.

/// View-local UI state. (Plain `@State` is a macro in newer SDKs whose plugin
/// ships only with full Xcode, so this keeps the project buildable with the
/// Command Line Tools alone.)
final class LocalState<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}

/// Groups glass shapes so they blend and morph into each other.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

struct GlassBackground<S: Shape>: ViewModifier {
    var shape: S
    var tint: Color? = nil
    var clear = false
    var interactive = false
    var id: String? = nil
    var namespace: Namespace.ID? = nil

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            let glass = (clear ? Glass.clear : Glass.regular).tint(tint).interactive(interactive)
            if let id, let namespace {
                content.glassEffect(glass, in: shape).glassEffectID(id, in: namespace)
            } else {
                content.glassEffect(glass, in: shape)
            }
        } else {
            content.background(shape.fill(tint ?? Color.primary.opacity(0.08)))
        }
    }
}

extension View {
    func glassBackground<S: Shape>(
        _ shape: S, tint: Color? = nil, clear: Bool = false, interactive: Bool = false,
        id: String? = nil, namespace: Namespace.ID? = nil
    ) -> some View {
        modifier(GlassBackground(shape: shape, tint: tint, clear: clear, interactive: interactive, id: id, namespace: namespace))
    }
}

/// A capsule (or circle) button made of glass. Prominent buttons are tinted with white text.
struct GlassButton<Label: View>: View {
    var tint: Color? = nil
    var prominent = false
    var circle = false
    var glassID: String? = nil
    var namespace: Namespace.ID? = nil
    let action: () -> Void
    @ViewBuilder var label: Label

    var body: some View {
        Button(action: action) {
            label.contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .focusable(false)
        .foregroundStyle(prominent && tint != nil ? Color.white : Color.primary)
        // Prominent buttons are tinted glass. (macOS mutes tinted glass while the window
        // isn't key; the panel is key whenever start/resume is on screen.)
        .modifier(GlassBackground(shape: Capsule(), tint: prominent ? tint : nil, interactive: true,
                                  id: glassID, namespace: namespace))
    }
}

/// Text (+ optional symbol) glass chip.
struct GlassChip: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color? = nil
    var prominent = false
    var large = false
    var glassID: String? = nil
    var namespace: Namespace.ID? = nil
    let action: () -> Void

    var body: some View {
        GlassButton(tint: tint, prominent: prominent, glassID: glassID, namespace: namespace, action: action) {
            HStack(spacing: large ? 7 : 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: large ? 13 : 11, weight: .bold))
                        .foregroundStyle(!prominent && tint != nil ? AnyShapeStyle(tint!) : AnyShapeStyle(.foreground))
                }
                Text(title)
                    .font(.system(size: large ? 17 : 15, weight: large ? .semibold : .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, large ? 20 : 14)
            .padding(.vertical, large ? 10 : 7)
            .fixedSize()
        }
    }
}

private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
