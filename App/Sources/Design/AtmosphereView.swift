import SwiftUI
import AniliteKit

/// A living, procedurally rendered backdrop tuned to one title (or to the app's brand).
///
/// Runs a Metal colour shader through `TimelineView`. Under Reduce Motion, thermal pressure
/// or the "Minimal" preference it renders one still frame; when the shader is unavailable
/// it falls back to layered gradients in the same palette.
struct AtmosphereView: View {
    var atmosphere: Atmosphere
    /// Lets screens fade the effect down behind dense content.
    var intensity: Double = 1

    @Environment(EffectsBudget.self) private var budget
    @Environment(\.scenePhase) private var scenePhase
    @State private var start = Date()

    var body: some View {
        ZStack {
            if budget.level == .still {
                StaticAtmosphere(palette: atmosphere.palette)
            } else {
                TimelineView(.animation(minimumInterval: budget.frameInterval, paused: scenePhase != .active)) { context in
                    let t = context.date.timeIntervalSince(start)
                    ShaderBackdrop(atmosphere: atmosphere, time: t, densityScale: budget.particleScale)
                }
            }
            if intensity < 1 {
                atmosphere.palette.deepColor.opacity(1 - intensity)
            }
        }
        .animation(.easeInOut(duration: 0.8), value: atmosphere.palette)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The shader-driven layer, split out so `TimelineView` re-renders only this.
private struct ShaderBackdrop: View {
    var atmosphere: Atmosphere
    var time: Double
    var densityScale: Double

    var body: some View {
        GeometryReader { proxy in
            let p = atmosphere.palette
            Rectangle()
                .fill(p.deepColor)
                .colorEffect(
                    ShaderLibrary.atmosphere(
                        .float2(proxy.size),
                        .float(Float(time.truncatingRemainder(dividingBy: 3600))),
                        .float(Float(atmosphere.mode.rawValue)),
                        .color(p.accentColor),
                        .color(p.deepColor),
                        .color(p.glowColor),
                        .color(p.secondaryColor),
                        .float(Float(atmosphere.energy)),
                        .float(Float(atmosphere.density * densityScale))
                    )
                )
        }
    }
}

/// Still version of the atmosphere for Reduce Motion / Minimal effects.
struct StaticAtmosphere: View {
    var palette: ArtworkPalette

    var body: some View {
        ZStack {
            palette.deepColor
            RadialGradient(colors: [palette.glowColor.opacity(0.75), .clear], center: UnitPoint(x: 0.5, y: -0.1),
                           startRadius: 10, endRadius: 520)
            RadialGradient(colors: [palette.accentColor.opacity(0.28), .clear], center: UnitPoint(x: 0.9, y: 0.25),
                           startRadius: 0, endRadius: 360)
            RadialGradient(colors: [palette.secondaryColor.opacity(0.18), .clear], center: UnitPoint(x: 0.05, y: 0.75),
                           startRadius: 0, endRadius: 380)
        }
    }
}

extension Atmosphere {
    /// The app-wide atmosphere used on screens without a single title.
    static let brand = Atmosphere(mode: .aurora, palette: Theme.defaultPalette, energy: 0.45, density: 0.6)
    static let night = Atmosphere(mode: .stars, palette: Theme.defaultPalette, energy: 0.3, density: 0.7)
}

// MARK: - Ripple

/// Shader ripple that radiates from a tap point. Skipped under Reduce Motion.
struct RippleModifier: ViewModifier {
    var origin: CGPoint
    var trigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let duration: TimeInterval = 1.1

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, elapsed in
                view.modifier(RippleEffect(origin: origin, elapsed: elapsed))
            } keyframes: { _ in
                MoveKeyframe(0)
                LinearKeyframe(duration, duration: duration)
            }
        }
    }
}

private struct RippleEffect: ViewModifier {
    var origin: CGPoint
    var elapsed: TimeInterval

    func body(content: Content) -> some View {
        let shader = ShaderLibrary.ripple(
            .float2(origin),
            .float(Float(elapsed)),
            .float(10), .float(14), .float(7), .float(900)
        )
        content.layerEffect(shader, maxSampleOffset: CGSize(width: 10, height: 10), isEnabled: elapsed > 0 && elapsed < 1.1)
    }
}

extension View {
    func ripple(at origin: CGPoint, trigger: Int) -> some View {
        modifier(RippleModifier(origin: origin, trigger: trigger))
    }
}
