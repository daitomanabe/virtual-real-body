#include <metal_stdlib>
using namespace metal;

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

struct OverlayUniform {
    float2 resolution;
    uint detected;
    uint pad;
};

fragment float4 poseOverlayFragment(
    RasterizerData in [[stage_in]],
    texture2d<float> cameraTexture [[texture(0)]],
    constant JointUniform *joints [[buffer(0)]],
    constant BoneUniform *bones [[buffer(1)]],
    constant OverlayUniform &uniforms [[buffer(2)]]
) {
    constexpr sampler texSampler(address::clamp_to_edge, filter::linear);
    float2 uv = float2(in.uv.x, 1.0 - in.uv.y);
    float4 base = cameraTexture.get_width() > 0 ? cameraTexture.sample(texSampler, uv) : float4(0.02, 0.02, 0.02, 1.0);
    float overlay = 0.0;
    for (uint i = 0; i < min(33u, uniforms.detected > 0 ? 33u : 0u); ++i) {
        float d = distance(in.uv, joints[i].positionXY);
        overlay += smoothstep(0.035, 0.0, d);
    }
    float3 tint = mix(base.rgb, float3(1.0, 0.45, 0.2), saturate(overlay));
    return float4(tint, 1.0);
}
