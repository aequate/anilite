#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// MARK: - Noise helpers

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float2 hash22(float2 p) {
    float n = hash21(p);
    return float2(n, hash21(p + n + 17.17));
}

static float vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float fbm(float2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * vnoise(p);
        p = p * 2.03 + float2(1.7, 9.2);
        a *= 0.5;
    }
    return v;
}

/// Soft round particles scattered one-per-cell. `drift` is in cells per second.
static float particles(float2 uv, float cell, float t, float2 drift, float radius, float density, float seed) {
    float2 p = uv / cell + drift * t;
    float2 id = floor(p);
    float2 f = fract(p) - 0.5;
    if (hash21(id + seed) > density) { return 0.0; }
    float2 o = (hash22(id + seed * 1.37) - 0.5) * 0.55;
    float r = radius * (0.45 + 0.55 * hash21(id + seed + 7.7));
    float d = length(f - o);
    return smoothstep(r, r * 0.15, d);
}

/// Elongated, slowly rotating petal shapes.
static float petals(float2 uv, float cell, float t, float2 drift, float density, float seed) {
    float2 p = uv / cell + drift * t;
    float2 id = floor(p);
    float2 f = fract(p) - 0.5;
    if (hash21(id + seed) > density) { return 0.0; }
    float2 o = (hash22(id + seed * 2.1) - 0.5) * 0.4;
    float angle = t * (0.6 + hash21(id + 3.3)) + hash21(id + 9.1) * 6.2831;
    float2 q = f - o;
    float cs = cos(angle);
    float sn = sin(angle);
    q = float2(cs * q.x - sn * q.y, sn * q.x + cs * q.y);
    q.x *= 0.55 + 0.35 * sin(t * 1.7 + hash21(id) * 6.0);
    float d = length(q * float2(1.0, 2.2));
    return smoothstep(0.14, 0.02, d);
}

// MARK: - Atmosphere

/// Full-screen procedural backdrop. `mode` matches AniliteKit's AtmosphereMode raw values.
[[ stitchable ]] half4 atmosphere(float2 position, half4 color, float2 size, float time, float mode,
                                  half4 accentH, half4 deepH, half4 glowH, half4 secondaryH,
                                  float energy, float density) {
    float2 uv = position / max(size.y, 1.0);
    float aspect = size.x / max(size.y, 1.0);
    float2 n = position / max(size, float2(1.0));          // 0…1 in both axes
    float3 accent = float3(accentH.rgb);
    float3 deep = float3(deepH.rgb);
    float3 glow = float3(glowH.rgb);
    float3 secondary = float3(secondaryH.rgb);
    float t = time * (0.35 + energy * 0.65);
    int m = int(mode + 0.5);

    // Shared base: deep tone, a soft light from the top and a fog layer.
    float3 col = deep;
    float topLight = smoothstep(1.1, 0.0, length((n - float2(0.5, -0.15)) * float2(1.0, 1.4)));
    col = mix(col, glow, topLight * 0.55);
    float fog = fbm(uv * 1.6 + float2(t * 0.03, -t * 0.02));
    col += glow * (fog - 0.45) * 0.22;

    if (m == 0) {
        // Aurora curtains.
        float warp = fbm(float2(uv.x * 1.3 + t * 0.05, t * 0.04)) * 2.4;
        for (int i = 0; i < 3; i++) {
            float fi = float(i);
            float centre = 0.22 + 0.11 * fi + 0.06 * sin(uv.x * (2.0 + fi) + warp + t * (0.25 + 0.1 * fi));
            float band = exp(-abs(uv.y - centre) * (9.0 - fi * 2.0));
            float shimmer = 0.6 + 0.4 * vnoise(float2(uv.x * 14.0 + t * 0.6, fi * 3.0));
            float3 tint = mix(accent, secondary, fi / 2.0);
            col += tint * band * shimmer * (0.42 - 0.08 * fi);
        }
        float s = particles(uv, 0.035, t * 0.02, float2(0.0, 0.0), 0.08, 0.12 * density, 4.0);
        col += float3(s) * 0.5 * smoothstep(0.7, 0.1, n.y);
    } else if (m == 1) {
        // Drifting petals, two depth layers.
        float far = petals(uv, 0.07, t, float2(-0.18, -0.28), 0.35 * density, 1.0);
        float near = petals(uv, 0.13, t, float2(-0.28, -0.45), 0.28 * density, 5.0);
        float3 petal = mix(accent, float3(1.0, 0.86, 0.92), 0.35);
        col += petal * far * 0.35 + mix(petal, secondary, 0.25) * near * 0.75;
        col += accent * smoothstep(0.9, 0.0, length(n - float2(0.8, 0.0))) * 0.18;
    } else if (m == 2) {
        // Embers rising from heat at the bottom.
        float heat = smoothstep(0.35, 1.05, n.y) * (0.6 + 0.4 * fbm(float2(uv.x * 3.0, t * 0.5)));
        col = mix(col, accent * 0.9, heat * 0.55);
        float e1 = particles(uv, 0.045, t, float2(0.04, 0.55), 0.16, 0.5 * density, 2.0);
        float e2 = particles(uv, 0.09, t, float2(-0.05, 0.85), 0.12, 0.35 * density, 8.0);
        float flicker = 0.65 + 0.35 * sin(t * 9.0 + uv.x * 40.0);
        float3 hot = mix(accent, float3(1.0, 0.85, 0.55), 0.45);
        col += hot * (e1 * 0.55 + e2 * 0.9) * flicker * smoothstep(-0.1, 0.8, n.y);
    } else if (m == 3) {
        // Rain streaks over a cold city haze.
        float2 r = float2(uv.x * 55.0 + uv.y * 6.0, uv.y * 2.2);
        float column = floor(r.x);
        float h = hash21(float2(column, 3.0));
        float fall = fract(r.y + t * (1.6 + h * 1.4) + h * 10.0);
        float streak = smoothstep(0.0, 0.03, fall) * smoothstep(0.16, 0.03, fall);
        float thin = smoothstep(0.5, 0.0, abs(fract(r.x) - 0.5) * 3.0);
        float drops = streak * thin * step(0.55 - 0.3 * density, h);
        col += mix(glow, float3(0.75, 0.85, 1.0), 0.6) * drops * 0.38;
        float neon = smoothstep(0.65, 1.0, n.y) * (0.5 + 0.5 * vnoise(float2(uv.x * 6.0, t * 0.3)));
        col += mix(accent, secondary, n.x) * neon * 0.28;
    } else if (m == 4) {
        // Dust motes in warm light.
        float2 wobble = float2(sin(t * 0.4 + uv.y * 3.0), cos(t * 0.3 + uv.x * 2.0)) * 0.02;
        float b1 = particles(uv + wobble, 0.11, t, float2(0.03, -0.05), 0.22, 0.35 * density, 3.0);
        float b2 = particles(uv - wobble, 0.05, t, float2(-0.04, -0.08), 0.14, 0.4 * density, 6.0);
        float3 warm = mix(accent, float3(1.0, 0.94, 0.78), 0.5);
        col += warm * (b1 * 0.32 + b2 * 0.42);
        float shaft = smoothstep(0.25, 0.0, abs((n.x - 0.65) + (n.y - 0.2) * 0.6)) * smoothstep(1.0, 0.1, n.y);
        col += warm * shaft * 0.12;
    } else if (m == 5) {
        // Speed lines.
        float rows = 70.0;
        float row = floor(n.y * rows);
        float h = hash21(float2(row, 11.0));
        float run = fract(n.x * (0.6 + h) * aspect * 0.5 - t * (0.7 + h * 1.6) + h * 7.0);
        float line = smoothstep(0.0, 0.25, run) * smoothstep(0.45, 0.25, run);
        float thin = smoothstep(0.5, 0.1, abs(fract(n.y * rows) - 0.5));
        float on = step(1.0 - 0.45 * density, hash21(float2(row, floor(t * 0.5 + h * 4.0))));
        col += mix(accent, float3(1.0), 0.3) * line * thin * on * 0.5;
        col += secondary * smoothstep(0.6, 0.0, abs(n.y - 0.55)) * 0.1;
    } else if (m == 6) {
        // Starfield with nebula.
        float neb = fbm(uv * 2.2 + float2(t * 0.01, 0.0));
        col += mix(secondary, accent, neb) * smoothstep(0.45, 0.85, neb) * 0.45;
        for (int i = 0; i < 3; i++) {
            float fi = float(i);
            float cell = 0.03 + fi * 0.025;
            float s = particles(uv, cell, t * 0.05, float2(0.02 * (fi + 1.0), 0.0), 0.07 + 0.02 * fi, 0.3 * density, 20.0 + fi);
            float tw = 0.55 + 0.45 * sin(t * (2.0 + fi) + hash21(floor(uv / cell)) * 40.0);
            col += float3(0.85, 0.9, 1.0) * s * tw * (0.35 + 0.25 * fi);
        }
    } else {
        // Abyss: heavy vignette, slow fog and a faint pulse below.
        float v = smoothstep(1.25, 0.25, length((n - float2(0.5, 0.45)) * float2(aspect, 1.0)));
        col *= 0.35 + 0.65 * v;
        float pulse = 0.5 + 0.5 * sin(t * 0.7);
        col += accent * smoothstep(0.7, 0.0, length(n - float2(0.5, 1.1))) * (0.22 + 0.12 * pulse);
        float d = particles(uv, 0.08, t, float2(0.0, -0.04), 0.1, 0.15 * density, 13.0);
        col += glow * d * 0.4;
    }

    // Dither to hide gradient banding.
    col += (hash21(position + fract(time)) - 0.5) / 255.0 * 2.0;
    return half4(half3(clamp(col, 0.0, 1.0)), 1.0h);
}

// MARK: - Touch ripple

[[ stitchable ]] half4 ripple(float2 position, SwiftUI::Layer layer, float2 origin, float time,
                              float amplitude, float frequency, float decay, float speed) {
    float2 delta = position - origin;
    float distance = length(delta);
    if (distance < 0.001) { return layer.sample(position); }
    float local = max(0.0, time - distance / speed);
    float amount = amplitude * sin(frequency * local) * exp(-decay * local);
    float2 sampled = position + amount * (delta / distance);
    half4 c = layer.sample(sampled);
    c.rgb += half(0.25 * (amount / max(amplitude, 0.001))) * c.a;
    return c;
}

// MARK: - Holographic foil (achievements, Taste DNA card)

[[ stitchable ]] half4 holo(float2 position, half4 color, float2 size, float2 tilt, float time) {
    if (color.a < 0.001h) { return color; }
    float2 uv = position / max(size, float2(1.0));
    float band = uv.x * 1.4 + uv.y * 0.9 + tilt.x * 1.2 + tilt.y * 0.6 + time * 0.05;
    float3 rainbow = 0.5 + 0.5 * cos(6.28318 * (band + float3(0.0, 0.33, 0.67)));
    float sheen = pow(max(0.0, sin((uv.x - uv.y + tilt.x) * 3.14159)), 8.0);
    half3 c = color.rgb + half3(rainbow * 0.16 + sheen * 0.22) * color.a;
    return half4(min(c, half3(color.a)), color.a);
}
