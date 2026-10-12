#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Live halftone: re-screens any layer as ink dots on a rotated grid (the Vox photo look).
// `reveal` 0→1 grows dots from nothing — used for entrance animations.
[[ stitchable ]] half4 halftone(float2 position, SwiftUI::Layer layer, float cell, float angle, half4 ink, float reveal) {
    float c = cos(angle), s = sin(angle);
    float2x2 rot = float2x2(c, -s, s, c);
    float2x2 inv = float2x2(c, s, -s, c);
    float2 p = rot * position;
    float2 center = (floor(p / cell) + 0.5) * cell;
    half4 sample = layer.sample(inv * center);
    float lum = dot(float3(sample.rgb), float3(0.299, 0.587, 0.114));
    float darkness = (1.0 - lum) * float(sample.a);
    float radius = sqrt(darkness) * cell * 0.66 * reveal;
    float d = length(p - center);
    float a = smoothstep(radius + 0.7, radius - 0.7, d);
    return half4(ink.rgb, 1.0h) * half(a) * ink.a;
}

// Riso grain: per-pixel noise that steps at `fps` so it "boils" like printed film.
[[ stitchable ]] half4 grain(float2 position, half4 color, float amount, float time) {
    float seed = floor(time * 10.0);
    float n = fract(sin(dot(position + seed * 13.17, float2(12.9898, 78.233))) * 43758.5453);
    half g = half((n - 0.5) * amount);
    return half4(clamp(color.rgb + g * color.a, 0.0h, 1.0h), color.a);
}

// Stop-motion "boil": hand-drawn lines wobble a little, in steps, like redrawn frames.
[[ stitchable ]] float2 boil(float2 position, float time, float amount, float fps) {
    float t = floor(time * fps);
    float2 o = float2(sin(position.y * 0.045 + t * 1.73), cos(position.x * 0.045 + t * 2.31)) * amount;
    return position + o;
}
