import SwiftUI
import MetalKit
import UIKit
import UIKit.UIGestureRecognizerSubclass
import AniliteKit

/// The marbled-ink backdrop, tinted for one title (or the app's own pigments).
///
/// Every instance is a window onto the shared `FluidEngine` simulation. It pauses when it
/// leaves the screen, drops to 30 fps under the Balanced preference or Low Power Mode,
/// and shows a single settled frame under Reduce Motion or Minimal effects. Without Metal
/// it falls back to a still gradient in the same palette.
struct AtmosphereView: View {
    var atmosphere: Atmosphere
    /// Fades the ink towards the ground colour behind dense content.
    var intensity: Double = 1

    @Environment(EffectsBudget.self) private var budget
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    var body: some View {
        Group {
            if FluidEngine.shared.isAvailable {
                FluidBackdrop(
                    atmosphere: atmosphere,
                    intensity: intensity,
                    animating: budget.animatesBackgrounds && isVisible && scenePhase == .active,
                    framesPerSecond: budget.level == .full ? 60 : 30
                )
            } else {
                StaticAtmosphere(palette: atmosphere.palette)
                    .overlay(atmosphere.palette.deepColor.opacity(1 - intensity))
            }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Still version of the backdrop for when Metal is unavailable.
struct StaticAtmosphere: View {
    var palette: ArtworkPalette

    var body: some View {
        ZStack {
            palette.deepColor
            EllipticalGradient(colors: [palette.accentColor.opacity(0.35), .clear], center: UnitPoint(x: 0.25, y: 0.15),
                               startRadiusFraction: 0, endRadiusFraction: 0.6)
            EllipticalGradient(colors: [palette.glowColor.opacity(0.25), .clear], center: UnitPoint(x: 0.85, y: 0.55),
                               startRadiusFraction: 0, endRadiusFraction: 0.55)
        }
    }
}

extension Atmosphere {
    /// Screens without a single title: slow ink in the app's own pigments.
    static let brand = Atmosphere(mode: .aurora, palette: Theme.inkPalette, energy: 0.4, density: 0.6)
    /// Quieter variant for list-heavy screens.
    static let night = Atmosphere(mode: .stars, palette: Theme.inkPalette, energy: 0.3, density: 0.5)
}

// MARK: - Metal view

private struct FluidBackdrop: UIViewRepresentable {
    var atmosphere: Atmosphere
    var intensity: Double
    var animating: Bool
    var framesPerSecond: Int

    func makeCoordinator() -> FluidRenderer { FluidRenderer() }

    func makeUIView(context: Context) -> FluidMTKView {
        let view = FluidMTKView(frame: .zero, device: FluidEngine.shared.device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.isOpaque = true
        view.clearColor = MTLClearColor(red: 0.067, green: 0.063, blue: 0.059, alpha: 1)
        view.contentScaleFactor = min(2, UIScreen.main.scale)
        view.autoResizeDrawable = true
        view.delegate = context.coordinator
        view.isUserInteractionEnabled = false
        context.coordinator.configure(atmosphere: atmosphere, intensity: intensity, immediate: true)
        apply(to: view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ view: FluidMTKView, context: Context) {
        context.coordinator.configure(atmosphere: atmosphere, intensity: intensity, immediate: false)
        apply(to: view, coordinator: context.coordinator)
    }

    static func dismantleUIView(_ view: FluidMTKView, coordinator: FluidRenderer) {
        view.isPaused = true
        view.delegate = nil
    }

    private func apply(to view: FluidMTKView, coordinator: FluidRenderer) {
        coordinator.animating = animating
        view.preferredFramesPerSecond = framesPerSecond
        if animating {
            view.enableSetNeedsDisplay = false
            view.isPaused = false
        } else {
            // Draw one settled frame and hold it.
            view.isPaused = true
            view.enableSetNeedsDisplay = true
            view.setNeedsDisplay()
        }
    }
}

final class FluidMTKView: MTKView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let window { FluidTouchRecognizer.install(on: window) }
    }
}

/// Draws one backdrop. Palette changes ease in over about half a second.
@MainActor
final class FluidRenderer: NSObject, MTKViewDelegate {
    var animating = false
    private var forcing = FluidForcing.forMode(.aurora)
    private var target = PaletteVectors(Theme.inkPalette)
    private var current = PaletteVectors(Theme.inkPalette)
    private var targetIntensity: Float = 1
    private var currentIntensity: Float = 1
    private var lastDraw: CFTimeInterval = 0

    func configure(atmosphere: Atmosphere, intensity: Double, immediate: Bool) {
        forcing = FluidForcing.forMode(atmosphere.mode).scaled(energy: atmosphere.energy, density: atmosphere.density)
        target = PaletteVectors(atmosphere.palette)
        targetIntensity = Float(intensity)
        if immediate {
            current = target
            currentIntensity = targetIntensity
        }
    }

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated { render(view) }
    }

    private func render(_ view: MTKView) {
        let engine = FluidEngine.shared
        guard engine.isAvailable, let window = view.window, let pipeline = engine.displayPipeline,
              let queue = engine.queue, let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable, let buffer = queue.makeCommandBuffer() else { return }

        engine.prepare(domain: window.bounds.size)
        let now = CACurrentMediaTime()
        let dt = lastDraw == 0 ? 1.0 / 60.0 : min(now - lastDraw, 0.1)
        lastDraw = now
        let ease = Float(animating ? 1 - exp(-dt * 2.8) : 1)
        current.blend(towards: target, amount: ease)
        currentIntensity += (targetIntensity - currentIntensity) * ease

        if animating {
            engine.forcing = forcing
            engine.advance(into: buffer, now: now)
        }
        guard let dye = engine.dyeTexture else { return }

        let frame = view.convert(view.bounds, to: nil)
        let domain = engine.domain
        var uniforms = FluidDisplayUniforms(
            ground: current.ground, pigmentA: current.a, pigmentB: current.b, pigmentC: current.c,
            rect: [Float(frame.minX / domain.width), Float(frame.minY / domain.height),
                   Float(frame.width / domain.width), Float(frame.height / domain.height)],
            dyeTexel: engine.dyeTexel,
            intensity: currentIntensity,
            time: engine.time,
            contour: 0.5,
            sheen: 0.25
        )
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(dye, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FluidDisplayUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

/// A palette as shader-ready vectors.
private struct PaletteVectors {
    var ground: SIMD4<Float>
    var a: SIMD4<Float>
    var b: SIMD4<Float>
    var c: SIMD4<Float>

    init(_ palette: ArtworkPalette) {
        func v(_ rgb: RGB) -> SIMD4<Float> { [Float(rgb.r), Float(rgb.g), Float(rgb.b), 1] }
        ground = v(palette.deep)
        a = v(palette.accent)
        b = v(palette.glow)
        c = v(palette.secondary)
    }

    mutating func blend(towards other: PaletteVectors, amount t: Float) {
        ground += (other.ground - ground) * t
        a += (other.a - a) * t
        b += (other.b - b) * t
        c += (other.c - c) * t
    }
}

// MARK: - Touch

/// Watches touches anywhere in the window and stirs the ink with them. It never
/// recognises, never delays or cancels touches, and can't be blocked by other gestures,
/// so scrolling and buttons behave exactly as before.
final class FluidTouchRecognizer: UIGestureRecognizer {
    private var last: [ObjectIdentifier: (point: CGPoint, time: TimeInterval)] = [:]

    static func install(on window: UIWindow) {
        if window.gestureRecognizers?.contains(where: { $0 is FluidTouchRecognizer }) == true { return }
        let recognizer = FluidTouchRecognizer(target: nil, action: nil)
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        window.addGestureRecognizer(recognizer)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            last[ObjectIdentifier(touch)] = (touch.location(in: view), touch.timestamp)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            let point = touch.location(in: view)
            if let previous = last[id] {
                let dt = max(touch.timestamp - previous.time, 1.0 / 240.0)
                let velocity = CGVector(dx: (point.x - previous.point.x) / dt, dy: (point.y - previous.point.y) / dt)
                FluidEngine.shared.touch(at: point, velocity: velocity)
            }
            last[id] = (point, touch.timestamp)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { finish(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { finish(touches) }

    private func finish(_ touches: Set<UITouch>) {
        for touch in touches { last[ObjectIdentifier(touch)] = nil }
        if last.isEmpty { state = .failed }
    }

    override func reset() {
        super.reset()
        last.removeAll()
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}
