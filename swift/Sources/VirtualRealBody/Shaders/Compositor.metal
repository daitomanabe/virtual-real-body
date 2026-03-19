#include <metal_stdlib>
using namespace metal;

struct RasterizerData {
    float4 position [[position]];
    float2 uv;
};

fragment float4 compositorFragment(
    RasterizerData in [[stage_in]],
    texture2d<float> leftTexture [[texture(0)]],
    texture2d<float> rightTexture [[texture(1)]]
) {
    constexpr sampler texSampler(address::clamp_to_edge, filter::linear);
    bool isLeft = in.uv.x < 0.5;
    float2 localUV = float2(isLeft ? in.uv.x * 2.0 : (in.uv.x - 0.5) * 2.0, in.uv.y);
    float4 color = isLeft ? leftTexture.sample(texSampler, localUV) : rightTexture.sample(texSampler, localUV);
    float seam = smoothstep(0.497, 0.5, in.uv.x) * smoothstep(0.503, 0.5, in.uv.x);
    color.rgb = mix(color.rgb, float3(1.0), seam * 0.25);
    return color;
}
