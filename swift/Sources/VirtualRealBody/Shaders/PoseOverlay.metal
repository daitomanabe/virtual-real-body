#include <metal_stdlib>
#include "lygia/sdf/circleSDF.msl"
#include "lygia/sdf/lineSDF.msl"
#include "lygia/draw/stroke.msl"
#include "lygia/math/map.msl"

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

constant uint kOverlayJointCount = 33;

float2 vrbOverlayAspect(float2 uv, float2 resolution) {
    float2 centered = uv * 2.0 - 1.0;
    centered.x *= resolution.x / max(resolution.y, 1.0);
    return centered;
}

float vrbOverlayJointDistance(float2 uv, float2 joint, float2 resolution) {
    float2 point = vrbOverlayAspect(joint, resolution);
    return lineSDF(vrbOverlayAspect(uv, resolution), point, point + float2(0.0001, 0.0));
}

fragment float4 poseOverlayFragment(
    RasterizerData in [[stage_in]],
    texture2d<float> cameraTexture [[texture(0)]],
    constant JointUniform *joints [[buffer(0)]],
    constant BoneUniform *bones [[buffer(1)]],
    constant OverlayUniform &uniforms [[buffer(2)]]
) {
    constexpr sampler texSampler(address::clamp_to_edge, filter::linear);

    float2 flippedUV = float2(1.0 - in.uv.x, in.uv.y);
    float4 base = cameraTexture.get_width() > 0
        ? cameraTexture.sample(texSampler, flippedUV)
        : float4(0.03, 0.03, 0.035, 1.0);

    if (uniforms.detected == 0u) {
        return float4(base.rgb, 1.0);
    }

    float2 aspectUV = vrbOverlayAspect(in.uv, uniforms.resolution);
    float3 overlayColor = base.rgb;

    for (uint i = 0; i < 14u; ++i) {
        BoneUniform bone = bones[i];
        JointUniform a = joints[bone.joints.x];
        JointUniform b = joints[bone.joints.y];
        float visibility = min(saturate(a.visibility), saturate(b.visibility));
        if (visibility <= 0.01) {
            continue;
        }

        float2 start = vrbOverlayAspect(a.positionXY, uniforms.resolution);
        float2 end = vrbOverlayAspect(b.positionXY, uniforms.resolution);
        float sdf = lineSDF(aspectUV, start, end);
        float width = map(clamp(max(a.speed, b.speed), 0.0, 1.0), 0.0, 1.0, 0.004, 0.018);
        float strokeAmount = stroke(sdf, 0.0, width);
        overlayColor = mix(
            overlayColor,
            float3(1.0, 0.62, 0.24),
            saturate(strokeAmount * visibility * 0.85)
        );
    }

    for (uint i = 0; i < kOverlayJointCount; ++i) {
        float visibility = saturate(joints[i].visibility);
        if (visibility <= 0.01) {
            continue;
        }

        float radius = map(clamp(joints[i].speed, 0.0, 1.0), 0.0, 1.0, 0.012, 0.03);
        float distanceToJoint = vrbOverlayJointDistance(in.uv, joints[i].positionXY, uniforms.resolution);
        float ring = stroke(distanceToJoint, 0.0, radius);
        float core = 1.0 - smoothstep(radius * 0.28, radius * 0.72, distanceToJoint);
        float3 tint = mix(float3(0.2, 0.85, 1.0), float3(1.0, 0.9, 0.45), joints[i].speed);
        overlayColor = mix(overlayColor, tint, saturate((ring * 0.95 + core * 0.5) * visibility));
    }

    return float4(saturate(overlayColor), 1.0);
}
