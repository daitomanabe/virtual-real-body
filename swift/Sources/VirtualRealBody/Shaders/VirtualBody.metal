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

struct VirtualBodyUniform {
    float time;
    float2 resolution;
    uint jointCount;
    uint boneCount;
    float2 pad;
};

vertex RasterizerData fullscreenVertex(uint vertexID [[vertex_id]]) {
    float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    RasterizerData out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = 0.5 * (positions[vertexID] + 1.0);
    return out;
}

fragment float4 virtualBodyFragment(
    RasterizerData in [[stage_in]],
    constant JointUniform *joints [[buffer(0)]],
    constant BoneUniform *bones [[buffer(1)]],
    constant VirtualBodyUniform &uniforms [[buffer(2)]]
) {
    float2 uv = in.uv;
    float glow = 0.0;
    for (uint i = 0; i < min(uniforms.jointCount, 33u); ++i) {
        float2 joint = joints[i].positionXY;
        float d = distance(uv, joint);
        glow += smoothstep(0.12, 0.0, d) * max(joints[i].visibility, 0.05);
    }
    float pulse = 0.5 + 0.5 * sin(uniforms.time * 1.5);
    float3 color = mix(float3(0.02, 0.03, 0.08), float3(0.15, 0.7, 1.0), saturate(glow * (0.75 + 0.25 * pulse)));
    return float4(color, 1.0);
}
