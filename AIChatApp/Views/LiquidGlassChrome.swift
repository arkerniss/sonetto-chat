import SwiftUI

enum LiquidGlassTint {
    case none
    case accent
    case custom(Color)
}

private struct LiquidGlassBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    var tint: LiquidGlassTint
    var interactive: Bool
    var fallbackFill: Color
    var fallbackStroke: Color
    var shadowRadius: CGFloat
    var shadowY: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(glass, in: shape)
                // The glass is rendered in a separate backdrop layer and does
                // NOT contribute to hit testing. With `.buttonStyle(.plain)`
                // the tappable area would collapse to the label's opaque
                // glyphs only (taps on the rest of the glass shape fall
                // through). Make the full glass shape the hit area, matching
                // the pre-iOS-26 fallback whose background fill is tappable.
                .contentShape(shape)
                .shadow(color: ChatChrome.glassShadow, radius: shadowRadius, y: shadowY)
        } else {
            content
                .background {
                    shape
                        .fill(reduceTransparency ? AnyShapeStyle(fallbackFill) : AnyShapeStyle(.ultraThinMaterial))
                        .overlay(shape.fill(fallbackTint))
                }
                .overlay {
                    shape.strokeBorder(fallbackStroke, lineWidth: 1)
                }
                .clipShape(shape)
                .shadow(color: ChatChrome.glassShadow, radius: shadowRadius, y: shadowY)
        }
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        var effect = Glass.regular

        switch tint {
        case .none:
            break
        case .accent:
            effect = effect.tint(Color.accentColor.opacity(0.34))
        case .custom(let color):
            effect = effect.tint(color)
        }

        // NOTE: The real tap-reliability fix lives in `body` above: the glass
        // backdrop layer is not hit-testable, so `.contentShape(shape)` is
        // applied to make the full glass shape tappable. With that in place,
        // `.interactive()` is safe to use and provides the press bounce/morph.
        return interactive ? effect.interactive() : effect
    }

    private var fallbackTint: Color {
        switch tint {
        case .none:
            return .clear
        case .accent:
            return Color.accentColor.opacity(0.14)
        case .custom(let color):
            return color
        }
    }
}

private struct LiquidGlassContainer<Content: View>: View {
    let spacing: CGFloat?
    let content: Content

    init(spacing: CGFloat?, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

extension View {
    func liquidGlass<S: InsettableShape>(
        shape: S,
        tint: LiquidGlassTint = .none,
        interactive: Bool = false,
        fallbackFill: Color = ChatChrome.surface,
        fallbackStroke: Color = ChatChrome.line,
        shadowRadius: CGFloat = 18,
        shadowY: CGFloat = 8
    ) -> some View {
        modifier(
            LiquidGlassBackground(
                shape: shape,
                tint: tint,
                interactive: interactive,
                fallbackFill: fallbackFill,
                fallbackStroke: fallbackStroke,
                shadowRadius: shadowRadius,
                shadowY: shadowY
            )
        )
    }

    func liquidGlass(
        cornerRadius: CGFloat,
        tint: LiquidGlassTint = .none,
        interactive: Bool = false,
        fallbackFill: Color = ChatChrome.surface,
        fallbackStroke: Color = ChatChrome.line,
        shadowRadius: CGFloat = 18,
        shadowY: CGFloat = 8
    ) -> some View {
        liquidGlass(
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            tint: tint,
            interactive: interactive,
            fallbackFill: fallbackFill,
            fallbackStroke: fallbackStroke,
            shadowRadius: shadowRadius,
            shadowY: shadowY
        )
    }

    @ViewBuilder
    func liquidGlassContainer(spacing: CGFloat? = nil) -> some View {
        LiquidGlassContainer(spacing: spacing) {
            self
        }
    }

    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else {
            buttonStyle(.plain)
        }
    }
}
