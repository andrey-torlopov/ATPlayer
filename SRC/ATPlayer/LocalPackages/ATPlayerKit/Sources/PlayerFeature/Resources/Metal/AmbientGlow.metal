#include <metal_stdlib>
using namespace metal;

struct AmbientGlowVertex {
    float4 position [[position]];
    float2 uv;
};

struct AmbientGlowUniforms {
    float4 parameters; // time, drawable width, drawable height, light theme
    float4 spectrumParameters; // maximum displayed amplitude, reserved, reserved, reserved
};

// Matches AmbientSpectrum.bandCount; buffer 1 always supplies all bands.
constant uint ambientSpectrumBandCount = 72;

vertex AmbientGlowVertex ambient_glow_vertex(uint vertexID [[vertex_id]]) {
    const float2 positions[] = {
        float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0)
    };
    AmbientGlowVertex out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = float2(out.position.x * 0.5 + 0.5, 0.5 - out.position.y * 0.5);
    return out;
}

static float ambientLobe(float2 point, float2 center, float2 radius) {
    const float2 local = (point - center) / radius;
    return exp(-dot(local, local) * 2.2);
}

static float ambientSpectrumSample(constant float *spectrum, int index) {
    return spectrum[clamp(index, 0, int(ambientSpectrumBandCount) - 1)];
}

static float ambientSpectrumCurve(constant float *spectrum, float x) {
    // A cubic B-spline joins all frequencies across the entire width, without cell gaps.
    // Positive weights smooth sharp peaks without inventing negative amplitudes or overshoot.
    const float position = clamp(x, 0.0, 1.0) * float(ambientSpectrumBandCount - 1);
    const int index = int(floor(position));
    const float t = fract(position);
    const float t2 = t * t;
    const float t3 = t2 * t;
    const float inverse = 1.0 - t;
    const float4 weights = float4(
        inverse * inverse * inverse,
        3.0 * t3 - 6.0 * t2 + 4.0,
        -3.0 * t3 + 3.0 * t2 + 3.0 * t + 1.0,
        t3
    ) / 6.0;
    const float4 samples = float4(
        ambientSpectrumSample(spectrum, index - 1),
        ambientSpectrumSample(spectrum, index),
        ambientSpectrumSample(spectrum, index + 1),
        ambientSpectrumSample(spectrum, index + 2)
    );
    return clamp(dot(samples, weights), 0.0, 1.0);
}

static float ambientSpectrumLine(float y, float height) {
    const float delta = y - height;
    // Convert to screen-pixel distance so steep sections retain a soft, even stroke.
    const float pixelStep = max(length(float2(dfdx(delta), dfdy(delta))), 0.0001);
    const float distance = abs(delta) / pixelStep;
    return 1.0 - smoothstep(0.85, 2.25, distance);
}

fragment float4 ambient_glow_fragment(
    AmbientGlowVertex in [[stage_in]],
    constant AmbientGlowUniforms &uniforms [[buffer(0)]],
    constant float *spectrum [[buffer(1)]]
) {
    const float time = uniforms.parameters.x;
    const float aspect = uniforms.parameters.y / max(uniforms.parameters.z, 1.0);
    const bool isLight = uniforms.parameters.w > 0.5;
    const float2 point = (in.uv - 0.5) * float2(aspect, 1.0);

    // A shared drifting center and overlapping lobes keep the brighter colors in one volume.
    const float2 center = float2(
        sin(time * 0.32) * 0.24,
        cos(time * 0.39) * 0.14
    );
    const float breathing = 1.0 + sin(time * 0.45) * 0.12;
    const float rotation = sin(time * 0.28) * 0.55;
    const float cosine = cos(rotation);
    const float sine = sin(rotation);
    const float2 delta = point - center;
    const float2 flowingPoint = float2(
        cosine * delta.x - sine * delta.y,
        sine * delta.x + cosine * delta.y
    );
    const float lobe1 = ambientLobe(flowingPoint, float2(0.0), float2(0.76, 0.48) * breathing);
    const float lobe2 = ambientLobe(
        flowingPoint,
        float2(-0.25 + sin(time * 0.41) * 0.08, 0.13),
        float2(0.54, 0.39)
    );
    const float lobe3 = ambientLobe(
        flowingPoint,
        float2(0.26, -0.12 + cos(time * 0.35) * 0.07),
        float2(0.52, 0.37)
    );

    // The listening stage stays dark in either app theme; light mode only lifts the navy base.
    const float3 base = isLight ? float3(0.035, 0.045, 0.10) : float3(0.015, 0.020, 0.055);
    const float3 violet = float3(0.66, 0.08, 1.0);
    const float3 cyan = float3(0.02, 0.82, 1.0);
    const float3 rose = float3(1.0, 0.06, 0.48);
    const float weight = lobe1 + lobe2 * 0.90 + lobe3 * 0.90;
    const float3 glow = (
        violet * lobe1 + cyan * lobe2 * 0.90 + rose * lobe3 * 0.90
    ) / max(weight, 0.001);

    // Keep only a subtle quiet area for white transport symbols, without washing out the blob.
    const float quietCenter = ambientLobe(point, float2(0.0), float2(0.46, 0.16));
    const float strength = (1.0 - exp(-weight * 1.25)) * (1.0 - quietCenter * 0.08);
    float3 finalColor = mix(base, glow, strength);

    // A shared visibility gate keeps quiet frequency ranges connected edge to edge,
    // while complete silence/pause removes all contours. Heights still come only from audio.
    if (uniforms.spectrumParameters.x > 0.0001) {
        const float amplitude = ambientSpectrumCurve(spectrum, in.uv.x);
        const float curveY = (1.0 - in.uv.y) / 0.2;
        // Evaluate derivatives before the varying band boundary to keep edge AA defined.
        const float mainLine = ambientSpectrumLine(curveY, 0.08 + amplitude * 0.84);
        const float middleLine = ambientSpectrumLine(curveY, 0.05 + amplitude * 0.64);
        const float lowerLine = ambientSpectrumLine(curveY, 0.025 + amplitude * 0.43);
        if (in.uv.y >= 0.8) {
            const float visibility = smoothstep(0.0001, 0.02, uniforms.spectrumParameters.x);
            const float stroke = max(mainLine, max(middleLine * 0.70, lowerLine * 0.45));
            const float3 bandColor = mix(float3(0.04, 0.85, 1.0), float3(0.65, 0.26, 1.0), in.uv.x);
            const float3 spectrumColor = mix(bandColor, float3(0.94, 0.97, 1.0), mainLine * 0.45);
            // Opacity is reduced by 20% relative to the previous 0.54 peak.
            const float opacity = stroke * visibility * 0.54 * 0.8;
            finalColor = mix(finalColor, spectrumColor, opacity);
        }
    }
    return float4(finalColor, 1.0);
}
