import Metal
import MetalKit
import QuartzCore
import simd
import AniliteKit

/// How the ambient ink moves for one kind of title. Tuned against an offline render of
/// the same simulation; values are in velocity-grid texels per second.
struct FluidForcing: Equatable {
    var drift: SIMD2<Float>
    var wind: Float
    var windScale: Float
    var vorticity: Float
    /// Vertical band (0 top … 1 bottom) the wandering emitters stay in.
    var band: SIMD2<Float>
    var emission: Float
    var wander: Float
    var dyeDissipation: Float
    var velocityDissipation: Float

    static func forMode(_ mode: AtmosphereMode) -> FluidForcing {
        switch mode {
        case .aurora:
            return FluidForcing(drift: [0.5, -0.4], wind: 8, windScale: 1.1, vorticity: 5, band: [0.05, 0.5], emission: 1.0, wander: 0.11, dyeDissipation: 0.22, velocityDissipation: 0.3)
        case .petals:
            return FluidForcing(drift: [0.6, 0.6], wind: 7, windScale: 1.3, vorticity: 7, band: [0.0, 0.6], emission: 1.0, wander: 0.10, dyeDissipation: 0.22, velocityDissipation: 0.3)
        case .embers:
            return FluidForcing(drift: [0, -2.2], wind: 7, windScale: 1.4, vorticity: 8, band: [0.6, 0.98], emission: 1.1, wander: 0.13, dyeDissipation: 0.24, velocityDissipation: 0.3)
        case .rain:
            return FluidForcing(drift: [0.2, 1.8], wind: 5, windScale: 1.8, vorticity: 4, band: [0.0, 0.45], emission: 1.0, wander: 0.09, dyeDissipation: 0.24, velocityDissipation: 0.35)
        case .motes:
            return FluidForcing(drift: [0.3, -0.3], wind: 5, windScale: 1.0, vorticity: 4, band: [0.15, 0.85], emission: 0.8, wander: 0.06, dyeDissipation: 0.2, velocityDissipation: 0.35)
        case .speed:
            return FluidForcing(drift: [3.5, 0], wind: 5, windScale: 1.2, vorticity: 6, band: [0.15, 0.85], emission: 1.0, wander: 0.12, dyeDissipation: 0.28, velocityDissipation: 0.35)
        case .stars:
            return FluidForcing(drift: [0, 0], wind: 6, windScale: 0.9, vorticity: 5, band: [0.1, 0.9], emission: 0.8, wander: 0.06, dyeDissipation: 0.18, velocityDissipation: 0.3)
        case .abyss:
            return FluidForcing(drift: [0, 0.8], wind: 6, windScale: 1.0, vorticity: 9, band: [0.0, 0.5], emission: 0.85, wander: 0.08, dyeDissipation: 0.2, velocityDissipation: 0.25)
        }
    }

    /// Scales motion by the title's energy without changing its character.
    func scaled(energy: Double, density: Double) -> FluidForcing {
        var f = self
        let e = Float(0.7 + 0.6 * clamp01(energy))
        f.drift *= e
        f.wind *= e
        f.emission *= Float(0.75 + 0.5 * clamp01(density))
        return f
    }
}

/// Layout must match `FluidUniforms` in Fluid.metal.
struct FluidUniforms {
    var velTexel: SIMD2<Float> = .zero
    var dyeTexel: SIMD2<Float> = .zero
    var dt: Float = 0
    var time: Float = 0
    var velDissipation: Float = 0
    var dyeDissipation: Float = 0
    var wind: SIMD4<Float> = .zero
    var aspect: Float = 1
    var vorticity: Float = 0
    var splatCount: UInt32 = 0
    var pressureDecay: Float = 0.8
}

/// Layout must match `FluidSplat` in Fluid.metal.
struct FluidSplat {
    var point: SIMD2<Float>
    var force: SIMD2<Float>
    var dye: SIMD4<Float>
    var radius: Float
    var pad0: Float = 0
    var pad1: Float = 0
    var pad2: Float = 0
}

/// Layout must match `FluidDisplayUniforms` in Fluid.metal.
struct FluidDisplayUniforms {
    var ground: SIMD4<Float>
    var pigmentA: SIMD4<Float>
    var pigmentB: SIMD4<Float>
    var pigmentC: SIMD4<Float>
    var rect: SIMD4<Float>
    var dyeTexel: SIMD2<Float>
    var intensity: Float
    var time: Float
    var contour: Float
    var sheen: Float
    var pad: SIMD2<Float> = .zero
}

/// One shared ink simulation for the whole app.
///
/// Every backdrop is a window onto the same sheet of ink, mapped by its position in the
/// window, so the ink carries on across navigation and touches anywhere stir it. The
/// simulation steps at most once per display frame, driven by whichever backdrop draws
/// first; when no backdrop is on screen it stops.
@MainActor
final class FluidEngine {
    static let shared = FluidEngine()

    let device: MTLDevice?
    let queue: MTLCommandQueue?
    private(set) var isAvailable = false
    private(set) var displayPipeline: MTLRenderPipelineState?

    private var kernels: [String: MTLComputePipelineState] = [:]
    private var velocity: [MTLTexture] = []
    private var dye: [MTLTexture] = []
    private var pressure: [MTLTexture] = []
    private var divergence: MTLTexture?
    private var curl: MTLTexture?
    private var velocityIndex = 0
    private var dyeIndex = 0
    private var pressureIndex = 0

    private(set) var domain: CGSize = .zero
    private var velocitySize = SIMD2<Int>(0, 0)
    private var dyeSize = SIMD2<Int>(0, 0)
    private var lastStep: CFTimeInterval = 0
    private(set) var time: Float = 0
    private var pendingSplats: [FluidSplat] = []

    /// The forcing of the backdrop that drew most recently.
    var forcing = FluidForcing.forMode(.aurora)

    private static let velocityWidth = 64
    private static let dyeScale = 3
    private static let jacobiIterations = 20
    private static let emitterAnchors: [Float] = [0.22, 0.5, 0.78]
    private static let emitterPhase: [Float] = [0, 2.1, 4.2]
    private static let emitterF1: [Float] = [1.0, 1.31, 0.77]
    private static let emitterF2: [Float] = [0.63, 0.91, 1.17]

    private init() {
        device = MTLCreateSystemDefaultDevice()
        queue = device?.makeCommandQueue()
        buildPipelines()
    }

    private func buildPipelines() {
        guard let device, queue != nil, let library = device.makeDefaultLibrary() else { return }
        let names = ["fluid_splat_velocity", "fluid_splat_dye", "fluid_wind", "fluid_curl", "fluid_vorticity",
                     "fluid_divergence", "fluid_pressure_decay", "fluid_jacobi", "fluid_gradient", "fluid_advect"]
        do {
            for name in names {
                guard let function = library.makeFunction(name: name) else { return }
                kernels[name] = try device.makeComputePipelineState(function: function)
            }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "fluid_display_vertex")
            descriptor.fragmentFunction = library.makeFunction(name: "fluid_display_fragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            guard descriptor.vertexFunction != nil, descriptor.fragmentFunction != nil else { return }
            displayPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            isAvailable = true
        } catch {
            isAvailable = false
        }
    }

    // MARK: - Domain

    /// Sizes the grids to the window's shape. Called by each backdrop before drawing;
    /// does nothing unless the shape really changed (rotation, iPad resize).
    func prepare(domain newDomain: CGSize) {
        guard isAvailable, newDomain.width > 1, newDomain.height > 1 else { return }
        if domain != .zero {
            let oldAspect = domain.width / domain.height
            let newAspect = newDomain.width / newDomain.height
            if abs(oldAspect - newAspect) / oldAspect < 0.08 { return }
        }
        domain = newDomain
        let aspect = newDomain.width / newDomain.height
        let vw = Self.velocityWidth
        let vh = max(16, Int((CGFloat(vw) / aspect).rounded()))
        velocitySize = [vw, vh]
        dyeSize = [vw * Self.dyeScale, vh * Self.dyeScale]
        velocity = (0..<2).compactMap { _ in makeTexture(.rg16Float, velocitySize) }
        dye = (0..<2).compactMap { _ in makeTexture(.rgba16Float, dyeSize) }
        pressure = (0..<2).compactMap { _ in makeTexture(.r16Float, velocitySize) }
        divergence = makeTexture(.r16Float, velocitySize)
        curl = makeTexture(.r16Float, velocitySize)
        guard velocity.count == 2, dye.count == 2, pressure.count == 2, divergence != nil, curl != nil else {
            isAvailable = false
            return
        }
        clearAll()
        prewarm(steps: 150)
    }

    private func makeTexture(_ format: MTLPixelFormat, _ size: SIMD2<Int>) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: size.x, height: size.y, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        return device?.makeTexture(descriptor: descriptor)
    }

    private func clearAll() {
        guard let queue, let buffer = queue.makeCommandBuffer(), let blit = buffer.makeBlitCommandEncoder() else { return }
        // Private textures start undefined; zero them through a scratch buffer.
        let largest = dyeSize.x * dyeSize.y * 8
        if let zeros = device?.makeBuffer(length: largest, options: .storageModePrivate) {
            blit.fill(buffer: zeros, range: 0..<largest, value: 0)
            for texture in velocity + dye + pressure + [divergence, curl].compactMap({ $0 }) {
                let bytesPerPixel = texture.pixelFormat == .rgba16Float ? 8 : (texture.pixelFormat == .rg16Float ? 4 : 2)
                blit.copy(from: zeros, sourceOffset: 0, sourceBytesPerRow: texture.width * bytesPerPixel,
                          sourceBytesPerImage: texture.width * bytesPerPixel * texture.height,
                          sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
                          to: texture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
            }
        }
        blit.endEncoding()
        buffer.commit()
    }

    /// Runs the simulation ahead so the first frame already shows settled ink.
    private func prewarm(steps: Int) {
        guard let queue, let buffer = queue.makeCommandBuffer() else { return }
        for _ in 0..<steps {
            encodeStep(into: buffer, dt: 1.0 / 60.0)
        }
        buffer.commit()
        lastStep = CACurrentMediaTime()
    }

    // MARK: - Input

    /// Stirs the ink. `point` is in window points, `velocity` in points per second.
    func touch(at point: CGPoint, velocity: CGVector) {
        guard isAvailable, domain.width > 0, pendingSplats.count < 24 else { return }
        let uv = SIMD2<Float>(Float(point.x / domain.width), Float(point.y / domain.height))
        // Points per second → velocity-grid texels per second, softened.
        let scale = Float(velocitySize.x) / Float(domain.width)
        var force = SIMD2<Float>(Float(velocity.dx), Float(velocity.dy)) * scale * 0.35
        let length = simd_length(force)
        if length > 60 { force *= 60 / length }
        pendingSplats.append(FluidSplat(point: uv, force: force, dye: .zero, radius: 0.0016))
    }

    // MARK: - Stepping

    /// Steps the simulation if no other backdrop has done so this frame.
    func advance(into buffer: MTLCommandBuffer, now: CFTimeInterval) {
        guard isAvailable, !velocity.isEmpty else { return }
        let elapsed = now - lastStep
        guard elapsed > 0.010 else { return }
        lastStep = now
        encodeStep(into: buffer, dt: Float(min(elapsed, 1.0 / 30.0)))
    }

    var dyeTexture: MTLTexture? { dye.isEmpty ? nil : dye[dyeIndex] }
    var dyeTexel: SIMD2<Float> { dyeSize.x > 0 ? SIMD2<Float>(1 / Float(dyeSize.x), 1 / Float(dyeSize.y)) : .zero }

    private func emitterSplats(dt: Float) -> [FluidSplat] {
        let f = forcing
        var splats: [FluidSplat] = []
        for i in 0..<3 {
            let p = emitterPosition(i, time, f)
            let ahead = emitterPosition(i, time + 0.1, f)
            let gridScale = SIMD2<Float>(Float(velocitySize.x), Float(velocitySize.y))
            let motion = (ahead - p) / 0.1 * gridScale * 0.6
            let mix = 0.5 + 0.5 * sin(time * 0.13 + Float(i) * 2.1)
            var pigment = SIMD4<Float>(repeating: 0)
            pigment[i] = f.emission * dt * (0.6 + 0.4 * mix)
            pigment[(i + 1) % 3] += f.emission * dt * 0.4 * (1 - mix)
            splats.append(FluidSplat(point: p, force: motion * dt * 6, dye: pigment, radius: 0.006))
        }
        return splats
    }

    private func emitterPosition(_ i: Int, _ t: Float, _ f: FluidForcing) -> SIMD2<Float> {
        let s = f.wander
        let ph = Self.emitterPhase[i], f1 = Self.emitterF1[i], f2 = Self.emitterF2[i]
        let x = Self.emitterAnchors[i] + 0.2 * sin(t * s * f1 * 2 + ph) * cos(t * s * f2 + ph * 0.5)
        let y = f.band.x + (f.band.y - f.band.x) * (0.5 + 0.5 * sin(t * s * f2 * 1.7 + ph * 1.3))
        return [x, y]
    }

    private func encodeStep(into buffer: MTLCommandBuffer, dt: Float) {
        guard let encoder = buffer.makeComputeCommandEncoder(), let divergence, let curl else { return }
        time += dt
        let f = forcing
        var splats = emitterSplats(dt: dt) + pendingSplats
        pendingSplats.removeAll(keepingCapacity: true)
        if splats.count > 32 { splats = Array(splats.prefix(32)) }

        var u = FluidUniforms()
        u.velTexel = [1 / Float(velocitySize.x), 1 / Float(velocitySize.y)]
        u.dyeTexel = dyeTexel
        u.dt = dt
        u.time = time
        u.velDissipation = f.velocityDissipation
        u.dyeDissipation = f.dyeDissipation
        u.wind = [f.drift.x, f.drift.y, f.wind, f.windScale]
        u.aspect = Float(domain.width / domain.height)
        u.vorticity = f.vorticity
        u.splatCount = UInt32(splats.count)
        u.pressureDecay = 0.8

        encoder.setBytes(&u, length: MemoryLayout<FluidUniforms>.stride, index: 0)
        splats.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                encoder.setBytes(base, length: max(raw.count, MemoryLayout<FluidSplat>.stride), index: 1)
            }
        }

        if !splats.isEmpty {
            dispatch(encoder, "fluid_splat_velocity", [velocity[velocityIndex], velocity[1 - velocityIndex]], size: velocitySize)
            velocityIndex = 1 - velocityIndex
            dispatch(encoder, "fluid_splat_dye", [dye[dyeIndex], dye[1 - dyeIndex]], size: dyeSize)
            dyeIndex = 1 - dyeIndex
        }

        dispatch(encoder, "fluid_wind", [velocity[velocityIndex], velocity[1 - velocityIndex]], size: velocitySize)
        velocityIndex = 1 - velocityIndex

        dispatch(encoder, "fluid_curl", [velocity[velocityIndex], curl], size: velocitySize)
        dispatch(encoder, "fluid_vorticity", [velocity[velocityIndex], curl, velocity[1 - velocityIndex]], size: velocitySize)
        velocityIndex = 1 - velocityIndex

        dispatch(encoder, "fluid_divergence", [velocity[velocityIndex], divergence], size: velocitySize)
        dispatch(encoder, "fluid_pressure_decay", [pressure[pressureIndex], pressure[1 - pressureIndex]], size: velocitySize)
        pressureIndex = 1 - pressureIndex
        for _ in 0..<Self.jacobiIterations {
            dispatch(encoder, "fluid_jacobi", [pressure[pressureIndex], divergence, pressure[1 - pressureIndex]], size: velocitySize)
            pressureIndex = 1 - pressureIndex
        }
        dispatch(encoder, "fluid_gradient", [pressure[pressureIndex], velocity[velocityIndex], velocity[1 - velocityIndex]], size: velocitySize)
        velocityIndex = 1 - velocityIndex

        var velocityFade = SIMD2<Float>(f.velocityDissipation, 0)
        encoder.setBytes(&velocityFade, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
        dispatch(encoder, "fluid_advect", [velocity[velocityIndex], velocity[velocityIndex], velocity[1 - velocityIndex]], size: velocitySize)
        velocityIndex = 1 - velocityIndex

        var dyeFade = SIMD2<Float>(f.dyeDissipation, 1)
        encoder.setBytes(&dyeFade, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
        dispatch(encoder, "fluid_advect", [velocity[velocityIndex], dye[dyeIndex], dye[1 - dyeIndex]], size: dyeSize)
        dyeIndex = 1 - dyeIndex

        encoder.endEncoding()
    }

    private func dispatch(_ encoder: MTLComputeCommandEncoder, _ name: String, _ textures: [MTLTexture], size: SIMD2<Int>) {
        guard let pipeline = kernels[name] else { return }
        encoder.setComputePipelineState(pipeline)
        for (index, texture) in textures.enumerated() {
            encoder.setTexture(texture, index: index)
        }
        let group = MTLSize(width: 8, height: 8, depth: 1)
        let groups = MTLSize(width: (size.x + 7) / 8, height: (size.y + 7) / 8, depth: 1)
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: group)
    }
}
