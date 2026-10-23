import SwiftUI

/// Liquid-glass surface. Uses the system glass material on iOS 26 and a layered material
/// with a specular rim on earlier versions. Falls back to solid ink when the user has
/// Reduce Transparency or Increase Contrast enabled.
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color?
    var interactive: Bool

    @Environment(EffectsBudget.self) private var budget

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if budget.prefersSolidSurfaces {
            content
                .background(Theme.ink2, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(glass, in: shape)
        } else {
            content
                .background {
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        if let tint { shape.fill(tint.opacity(0.14)) }
                        shape.fill(
                            LinearGradient(colors: [Color.white.opacity(0.10), .clear], startPoint: .top, endPoint: .center)
                        )
                    }
                }
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.32), Color.white.opacity(0.04), Color.white.opacity(0.12)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 0.8
                    )
                )
                .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
        }
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint.opacity(0.35)) }
        if interactive { g = g.interactive() }
        return g
    }
}

extension View {
    func glassSurface(cornerRadius: CGFloat = Theme.corner, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }

    /// Capsule glass for chips and the dock.
    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassSurface(cornerRadius: 999, tint: tint, interactive: interactive))
    }
}
