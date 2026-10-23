import SwiftUI

/// Solid panel: the default surface for anything that sits in the page (cards, rows,
/// banners). An optional tint marks a semantic state, such as a warning.
struct SolidSurface: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color?

    @Environment(EffectsBudget.self) private var budget

    func body(content: Content) -> some View {
        // Card radii share one scale, whatever a call site asks for.
        let radius = cornerRadius >= 999 ? cornerRadius : min(cornerRadius, Theme.corner)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                shape.fill(Theme.ink1)
                    .overlay {
                        if let tint { shape.fill(tint.opacity(0.09)) }
                    }
            }
            .overlay {
                shape.strokeBorder(borderColor, lineWidth: budget.prefersSolidSurfaces ? 1 : 0.75)
            }
    }

    private var borderColor: Color {
        if budget.prefersSolidSurfaces { return Theme.textSecondary.opacity(0.6) }
        if let tint { return tint.opacity(0.35) }
        return Theme.hairline
    }
}

/// Glass for controls that float over moving content: the dock and buttons laid over
/// artwork. System Liquid Glass on iOS 26, a thick material before that, and solid ink
/// when Reduce Transparency or Increase Contrast is on.
struct FloatingGlass: ViewModifier {
    var cornerRadius: CGFloat
    var interactive: Bool

    @Environment(EffectsBudget.self) private var budget

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if budget.prefersSolidSurfaces {
            content
                .background(Theme.ink2, in: shape)
                .overlay(shape.strokeBorder(Theme.textSecondary.opacity(0.6), lineWidth: 1))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(interactive ? Glass.regular.interactive() : Glass.regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 0.75))
        }
    }
}

extension View {
    /// Solid in-page panel. `interactive` is accepted for older call sites and ignored:
    /// solid panels don't react to touch on their own.
    func surface(cornerRadius: CGFloat = Theme.corner, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(SolidSurface(cornerRadius: cornerRadius, tint: tint))
    }

    /// Solid capsule for chips and pill buttons in the page.
    func capsuleSurface(tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(SolidSurface(cornerRadius: 999, tint: tint))
    }

    /// Real glass, only for controls floating above moving content.
    func floatingGlass(cornerRadius: CGFloat = 999, interactive: Bool = true) -> some View {
        modifier(FloatingGlass(cornerRadius: cornerRadius, interactive: interactive))
    }
}
