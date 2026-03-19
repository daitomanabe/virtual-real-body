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
    float2 pad;
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

    float dividerDistance = abs(in.uv.x - dividerX);
    float glow = smoothstep(0.012, 0.0, dividerDistance);
    float line = smoothstep(0.0015, 0.0, dividerDistance);
    float3 dividerColor = mix(float3(0.18, 0.22, 0.28), float3(0.95, 0.98, 1.0), line);
    color.rgb = mix(color.rgb, dividerColor, glow * 0.45 + line * 0.55);

    return float4(saturate(color.rgb), 1.0);
}
