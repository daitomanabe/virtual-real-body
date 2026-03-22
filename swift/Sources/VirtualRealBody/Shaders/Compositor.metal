#include <metal_stdlib>

using namespace metal;

#ifndef VRB_SHARED_TYPES
#define VRB_SHARED_TYPES
struct RasterizerData {
    float4 position [[position]];
    float2 uv;
};

struct JointUniform {
    float2 positionXY;
    float speed;
    float energy;
    float visibility;
    float3 pad;
};

struct BoneUniform {
    uint2 joints;
    uint2 pad;
};

struct VirtualBodyUniform {
    float time;
    float2 resolution;
    uint jointCount;
    uint boneCount;
    uint segmentCount;
    uint particleCount;
    uint renderMode;
    uint detected;
    float2 com;
    float2 flowVector;
    float4 quadrants;
    float4 analysis;
    float4 styleMix;
};

struct OverlayUniform {
    float2 resolution;
    uint detected;
    uint pad;
};
#endif

float4 vrbSamplePanel(texture2d<float> texture, sampler s, float2 uv) {
    if (texture.get_width() == 0 || texture.get_height() == 0) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }
    return texture.sample(s, uv);
}

float vrbCompositorNoise(float2 uv) {
    return fract(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453);
}

fragment float4 compositorFragment(
    RasterizerData in [[stage_in]],
    texture2d<float> leftTexture [[texture(0)]],
    texture2d<float> rightTexture [[texture(1)]]
) {
    constexpr sampler texSampler(address::clamp_to_edge, filter::linear);
    constexpr float dividerX = 0.5;

    bool leftPanel = in.uv.x <= dividerX;
    float2 panelUV = leftPanel
        ? float2(in.uv.x / dividerX, in.uv.y)
        : float2((in.uv.x - dividerX) / (1.0 - dividerX), in.uv.y);

    float4 color = leftPanel
        ? vrbSamplePanel(leftTexture, texSampler, panelUV)
        : vrbSamplePanel(rightTexture, texSampler, panelUV);

    float2 chromaOffset = float2((leftPanel ? -1.0 : 1.0) * 0.003, 0.0);
    float red = (leftPanel
        ? vrbSamplePanel(leftTexture, texSampler, clamp(panelUV + chromaOffset, 0.0, 1.0))
        : vrbSamplePanel(rightTexture, texSampler, clamp(panelUV + chromaOffset, 0.0, 1.0))).r;
    float blue = (leftPanel
        ? vrbSamplePanel(leftTexture, texSampler, clamp(panelUV - chromaOffset, 0.0, 1.0))
        : vrbSamplePanel(rightTexture, texSampler, clamp(panelUV - chromaOffset, 0.0, 1.0))).b;
    color.rgb = float3(red, color.g, blue);

    float scanlines = 0.96 + 0.04 * sin(panelUV.y * 900.0);
    float vignette = smoothstep(1.35, 0.18, distance(panelUV, float2(0.5)));
    float grain = vrbCompositorNoise(panelUV * float2(1440.0, 900.0) + in.uv.yx * 37.0);
    color.rgb *= scanlines;
    color.rgb = mix(color.rgb, color.rgb + grain * 0.035, 0.45);
    color.rgb *= vignette;

    float dividerDistance = abs(in.uv.x - dividerX);
    float glow = smoothstep(0.012, 0.0, dividerDistance);
    float line = smoothstep(0.0015, 0.0, dividerDistance);
    float3 dividerColor = mix(float3(0.18, 0.22, 0.28), float3(0.95, 0.98, 1.0), line);
    color.rgb = mix(color.rgb, dividerColor, glow * 0.45 + line * 0.55);

    return float4(saturate(color.rgb), 1.0);
}
