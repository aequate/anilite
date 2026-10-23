#include <metal_stdlib>
using namespace metal;

// Stable-fluids simulation (Stam 1999, in the GPU form popularised by Pavel Dobryakov)
// behind Anilite's marbled-ink backdrop.
//
// Velocity lives on a coarse grid in texels-per-second of that grid, with y pointing
// down. Dye has three pigment channels on a finer grid; the display pass maps them to
// the palette of whatever screen is showing.

constexpr sampler fluidSampler(coord::normalized, address::clamp_to_edge, filter::linear);

struct FluidUniforms {
    float2 velTexel;       // 1 / velocity grid size
    float2 dyeTexel;       // 1 / dye grid size
    float dt;
    float time;
    float velDissipation;
    float dyeDissipation;
    float4 wind;           // xy: steady drift force, z: curl-noise strength, w: noise scale
    float aspect;          // domain width / height
    float vorticity;
    uint splatCount;
    float pressureDecay;
};

struct FluidSplat {
    float2 point;          // domain uv, y down
    float2 force;          // velocity texels per second
    float4 dye;            // pigment added at the centre
    float radius;          // gaussian falloff in aspect-corrected uv^2
    float pad0;
    float pad1;
    float pad2;
};

static inline bool outside(uint2 gid, uint w, uint h) { return gid.x >= w || gid.y >= h; }

static inline uint2 at(int2 p, int w, int h) {
    return uint2(clamp(p, int2(0), int2(w - 1, h - 1)));
}

static inline float fluidHash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static inline float fluidNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float a = fluidHash(i);
    float b = fluidHash(i + float2(1, 0));
    float c = fluidHash(i + float2(0, 1));
    float d = fluidHash(i + float2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static inline float fluidPotential(float2 p, float t) {
    return fluidNoise(p + float2(0.0, t)) + 0.5 * fluidNoise(p * 2.03 + float2(t * 0.7, 3.1));
}

// MARK: - Forces

static inline float4 applySplats(float4 value, float2 uv, constant FluidUniforms& u,
                                 constant FluidSplat* splats, bool dye) {
    for (uint i = 0; i < u.splatCount; i++) {
        FluidSplat s = splats[i];
        float2 d = uv - s.point;
        d.x *= u.aspect;
        float g = exp(-dot(d, d) / s.radius);
        value += (dye ? s.dye : float4(s.force, 0.0, 0.0)) * g;
    }
    return value;
}

kernel void fluid_splat_velocity(texture2d<float, access::read> src [[texture(0)]],
                                 texture2d<float, access::write> dst [[texture(1)]],
                                 constant FluidUniforms& u [[buffer(0)]],
                                 constant FluidSplat* splats [[buffer(1)]],
                                 uint2 gid [[thread_position_in_grid]]) {
    if (outside(gid, dst.get_width(), dst.get_height())) return;
    float2 uv = (float2(gid) + 0.5) * u.velTexel;
    dst.write(applySplats(src.read(gid), uv, u, splats, false), gid);
}

kernel void fluid_splat_dye(texture2d<float, access::read> src [[texture(0)]],
                            texture2d<float, access::write> dst [[texture(1)]],
                            constant FluidUniforms& u [[buffer(0)]],
                            constant FluidSplat* splats [[buffer(1)]],
                            uint2 gid [[thread_position_in_grid]]) {
    if (outside(gid, dst.get_width(), dst.get_height())) return;
    float2 uv = (float2(gid) + 0.5) * u.dyeTexel;
    float4 v = applySplats(src.read(gid), uv, u, splats, true);
    dst.write(min(v, float4(3.0)), gid);
}

/// Ambient motion: a steady drift plus a divergence-free curl-noise wind, so the ink
/// keeps moving gently with nobody touching it.
kernel void fluid_wind(texture2d<float, access::read> src [[texture(0)]],
                       texture2d<float, access::write> dst [[texture(1)]],
                       constant FluidUniforms& u [[buffer(0)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (outside(gid, dst.get_width(), dst.get_height())) return;
    float2 uv = (float2(gid) + 0.5) * u.velTexel;
    float2 p = float2(uv.x * u.aspect, uv.y) * u.wind.w;
    float t = u.time * 0.045;
    const float e = 0.05;
    float dy = fluidPotential(p + float2(0, e), t) - fluidPotential(p - float2(0, e), t);
    float dx = fluidPotential(p + float2(e, 0), t) - fluidPotential(p - float2(e, 0), t);
    float2 curl = float2(dy, -dx) / (2.0 * e);
    float4 v = src.read(gid);
    v.xy += (curl * u.wind.z + u.wind.xy) * u.dt;
    dst.write(v, gid);
}

// MARK: - Projection

kernel void fluid_curl(texture2d<float, access::read> vel [[texture(0)]],
                       texture2d<float, access::write> dst [[texture(1)]],
                       uint2 gid [[thread_position_in_grid]]) {
    int w = vel.get_width(), h = vel.get_height();
    if (outside(gid, w, h)) return;
    int2 p = int2(gid);
    float l = vel.read(at(p + int2(-1, 0), w, h)).y;
    float r = vel.read(at(p + int2(1, 0), w, h)).y;
    float t = vel.read(at(p + int2(0, -1), w, h)).x;
    float b = vel.read(at(p + int2(0, 1), w, h)).x;
    dst.write(float4(0.5 * ((r - l) - (b - t)), 0, 0, 1), gid);
}

kernel void fluid_vorticity(texture2d<float, access::read> vel [[texture(0)]],
                            texture2d<float, access::read> curl [[texture(1)]],
                            texture2d<float, access::write> dst [[texture(2)]],
                            constant FluidUniforms& u [[buffer(0)]],
                            uint2 gid [[thread_position_in_grid]]) {
    int w = vel.get_width(), h = vel.get_height();
    if (outside(gid, w, h)) return;
    int2 p = int2(gid);
    float l = abs(curl.read(at(p + int2(-1, 0), w, h)).x);
    float r = abs(curl.read(at(p + int2(1, 0), w, h)).x);
    float t = abs(curl.read(at(p + int2(0, -1), w, h)).x);
    float b = abs(curl.read(at(p + int2(0, 1), w, h)).x);
    float c = curl.read(gid).x;
    float2 n = 0.5 * float2(r - l, b - t);
    n /= length(n) + 1e-4;
    float2 force = u.vorticity * c * float2(n.y, -n.x);
    float4 v = vel.read(gid);
    v.xy += force * u.dt;
    v.xy = clamp(v.xy, float2(-400.0), float2(400.0));
    dst.write(v, gid);
}

kernel void fluid_divergence(texture2d<float, access::read> vel [[texture(0)]],
                             texture2d<float, access::write> dst [[texture(1)]],
                             uint2 gid [[thread_position_in_grid]]) {
    int w = vel.get_width(), h = vel.get_height();
    if (outside(gid, w, h)) return;
    int2 p = int2(gid);
    float2 c = vel.read(gid).xy;
    // Solid walls: the velocity reflects at the edges.
    float l = p.x == 0 ? -c.x : vel.read(at(p + int2(-1, 0), w, h)).x;
    float r = p.x == w - 1 ? -c.x : vel.read(at(p + int2(1, 0), w, h)).x;
    float t = p.y == 0 ? -c.y : vel.read(at(p + int2(0, -1), w, h)).y;
    float b = p.y == h - 1 ? -c.y : vel.read(at(p + int2(0, 1), w, h)).y;
    dst.write(float4(0.5 * (r - l + b - t), 0, 0, 1), gid);
}

kernel void fluid_pressure_decay(texture2d<float, access::read> src [[texture(0)]],
                                 texture2d<float, access::write> dst [[texture(1)]],
                                 constant FluidUniforms& u [[buffer(0)]],
                                 uint2 gid [[thread_position_in_grid]]) {
    if (outside(gid, dst.get_width(), dst.get_height())) return;
    dst.write(src.read(gid) * u.pressureDecay, gid);
}

kernel void fluid_jacobi(texture2d<float, access::read> pressure [[texture(0)]],
                         texture2d<float, access::read> divergence [[texture(1)]],
                         texture2d<float, access::write> dst [[texture(2)]],
                         uint2 gid [[thread_position_in_grid]]) {
    int w = pressure.get_width(), h = pressure.get_height();
    if (outside(gid, w, h)) return;
    int2 p = int2(gid);
    float l = pressure.read(at(p + int2(-1, 0), w, h)).x;
    float r = pressure.read(at(p + int2(1, 0), w, h)).x;
    float t = pressure.read(at(p + int2(0, -1), w, h)).x;
    float b = pressure.read(at(p + int2(0, 1), w, h)).x;
    float d = divergence.read(gid).x;
    dst.write(float4((l + r + t + b - d) * 0.25, 0, 0, 1), gid);
}

kernel void fluid_gradient(texture2d<float, access::read> pressure [[texture(0)]],
                           texture2d<float, access::read> vel [[texture(1)]],
                           texture2d<float, access::write> dst [[texture(2)]],
                           uint2 gid [[thread_position_in_grid]]) {
    int w = vel.get_width(), h = vel.get_height();
    if (outside(gid, w, h)) return;
    int2 p = int2(gid);
    float l = pressure.read(at(p + int2(-1, 0), w, h)).x;
    float r = pressure.read(at(p + int2(1, 0), w, h)).x;
    float t = pressure.read(at(p + int2(0, -1), w, h)).x;
    float b = pressure.read(at(p + int2(0, 1), w, h)).x;
    float4 v = vel.read(gid);
    v.xy -= 0.5 * float2(r - l, b - t);
    dst.write(v, gid);
}

// MARK: - Advection

kernel void fluid_advect(texture2d<float, access::sample> vel [[texture(0)]],
                         texture2d<float, access::sample> src [[texture(1)]],
                         texture2d<float, access::write> dst [[texture(2)]],
                         constant FluidUniforms& u [[buffer(0)]],
                         constant float2& fade [[buffer(1)]],
                         uint2 gid [[thread_position_in_grid]]) {
    uint w = dst.get_width(), h = dst.get_height();
    if (outside(gid, w, h)) return;
    float2 uv = (float2(gid) + 0.5) / float2(w, h);
    float2 v = vel.sample(fluidSampler, uv).xy;
    float2 from = uv - u.dt * v * u.velTexel;
    float4 result = src.sample(fluidSampler, from) / (1.0 + fade.x * u.dt);
    if (fade.y > 0.0) {
        // Dye thins out against the walls instead of piling up there.
        float edge = smoothstep(0.0, 0.06, min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)));
        result *= 1.0 - (1.0 - edge) * 0.04 * fade.y * u.dt * 60.0;
    }
    dst.write(result, gid);
}

// MARK: - Display

struct FluidDisplayUniforms {
    float4 ground;
    float4 pigmentA;
    float4 pigmentB;
    float4 pigmentC;
    float4 rect;           // this view's rectangle in domain uv: origin xy, size zw
    float2 dyeTexel;
    float intensity;
    float time;
    float contour;         // strength of the marbling contour lines
    float sheen;
    float2 pad;
};

struct FluidVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex FluidVertexOut fluid_display_vertex(uint vid [[vertex_id]]) {
    float2 p = float2(float((vid << 1) & 2), float(vid & 2));
    FluidVertexOut out;
    out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(p.x, 1.0 - p.y);
    return out;
}

static inline float pigmentHeight(texture2d<float> dye, float2 uv) {
    float3 c = max(dye.sample(fluidSampler, uv).rgb, 0.0);
    return c.r + c.g + c.b;
}

fragment float4 fluid_display_fragment(FluidVertexOut in [[stage_in]],
                                       texture2d<float> dye [[texture(0)]],
                                       constant FluidDisplayUniforms& d [[buffer(0)]]) {
    float2 uv = d.rect.xy + in.uv * d.rect.zw;
    float3 c = max(dye.sample(fluidSampler, uv).rgb, 0.0);
    float3 cover = 1.0 - exp(-c * 1.5);
    float total = cover.r + cover.g + cover.b;
    float3 pigment = (d.pigmentA.rgb * cover.r + d.pigmentB.rgb * cover.g + d.pigmentC.rgb * cover.b) / max(total, 1e-4);
    float3 color = mix(d.ground.rgb, pigment, min(total, 1.0) * 0.92);

    // Suminagashi: ink spreads in rings, so draw faint contour lines through the
    // pigment field, antialiased by the field's own screen-space derivative.
    float h = c.r + c.g + c.b;
    float bands = h * 3.5;
    float distanceToLine = abs(fract(bands + 0.5) - 0.5);
    float lineWidth = max(fwidth(bands) * 1.1, 1e-3);
    float line = (1.0 - smoothstep(0.0, lineWidth, distanceToLine)) * smoothstep(0.04, 0.35, h) * (1.0 - smoothstep(2.2, 3.0, h))
                 * (1.0 - smoothstep(0.12, 0.35, fwidth(bands)));
    color = mix(color, color * 0.55 + float3(0.94, 0.92, 0.88) * 0.45, line * d.contour);

    // Wet sheen from the pigment surface's slope.
    float2 o = d.dyeTexel * 1.5;
    float hx = pigmentHeight(dye, uv + float2(o.x, 0)) - pigmentHeight(dye, uv - float2(o.x, 0));
    float hy = pigmentHeight(dye, uv + float2(0, o.y)) - pigmentHeight(dye, uv - float2(0, o.y));
    float3 normal = normalize(float3(-hx * 1.8, -hy * 1.8, 1.0));
    float3 lightDir = normalize(float3(-0.35, -0.6, 0.9));
    float spec = pow(max(dot(reflect(-lightDir, normal), float3(0, 0, 1)), 0.0), 22.0);
    color += spec * d.sheen * smoothstep(0.02, 0.4, h);

    // Gentle vignette and grain so gradients never band.
    float2 q = in.uv - 0.5;
    color *= 1.0 - 0.22 * dot(q, q);
    float grain = fluidHash(in.position.xy + fract(d.time) * 97.0) - 0.5;
    color += grain * (2.0 / 255.0);

    color = mix(d.ground.rgb, color, d.intensity);
    return float4(saturate(color), 1.0);
}
