#include <metal_stdlib>
using namespace metal;

#include "lygia/sdf/circleSDF.msl"
#include "lygia/sdf/lineSDF.msl"
#include "lygia/draw/stroke.msl"
#include "lygia/math/map.msl"

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

constant uint kOverlayJointCount = 33;
constant uint kOverlaySegmentPointCount = 8;
constant uint kOverlayParticlePointCount = 8;

float2 vrbOverlayAspect(float2 uv, float2 resolution) {
    float2 centered = uv * 2.0 - 1.0;
    centered.x *= resolution.x / max(resolution.y, 1.0);
    return centered;
}

float vrbOverlayJointMetric(float2 uv, float2 joint, float radius, float2 resolution) {
    float2 point = vrbOverlayAspect(joint, resolution);
    float2 centered = vrbOverlayAspect(uv, resolution);
    float safeRadius = max(radius, 0.0001);
    float2 local = (centered - point) / (safeRadius * 2.0) + 0.5;
    return circleSDF(local) * safeRadius;
}

fragment float4 poseOverlayFragment(
    RasterizerData in [[stage_in]],
    texture2d<float> cameraTexture [[texture(0)]],
    constant JointUniform *joints [[buffer(0)]],
    constant BoneUniform *bones [[buffer(1)]],
    constant float2 *segmentPoints [[buffer(2)]],
    constant float2 *particlePoints [[buffer(3)]],
    constant VirtualBodyUniform &bodyUniforms [[buffer(4)]],
    constant OverlayUniform &uniforms [[buffer(5)]]
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
    float2 com = vrbOverlayAspect(bodyUniforms.com, uniforms.resolution);

    uint segmentCount = min(bodyUniforms.segmentCount, kOverlaySegmentPointCount);
    if (segmentCount > 1u) {
        for (uint i = 0; i < segmentCount; ++i) {
            uint next = (i + 1u) % segmentCount;
            float2 start = vrbOverlayAspect(segmentPoints[i], uniforms.resolution);
            float2 end = vrbOverlayAspect(segmentPoints[next], uniforms.resolution);
            float hull = stroke(lineSDF(aspectUV, start, end), 0.0, 0.006 + bodyUniforms.analysis.x * 0.01);
            overlayColor = mix(overlayColor, float3(0.84, 0.32, 0.92), saturate(hull * 0.62));
        }
    }

    if (bodyUniforms.particleCount > 0u) {
        for (uint i = 0; i < min(bodyUniforms.particleCount, kOverlayParticlePointCount); ++i) {
            float2 point = vrbOverlayAspect(particlePoints[i], uniforms.resolution);
            float dist = distance(aspectUV, point);
            float orb = 1.0 - smoothstep(0.008, 0.024 + bodyUniforms.analysis.w * 0.03, dist);
            float tether = stroke(lineSDF(aspectUV, com, point), 0.0, 0.0025);
            overlayColor = mix(overlayColor, float3(0.45, 1.0, 0.82), saturate((orb * 0.7) + (tether * 0.22)));
        }
    }

    float2 flowEnd = com + float2(
        bodyUniforms.flowVector.x * (uniforms.resolution.x / max(uniforms.resolution.y, 1.0)),
        bodyUniforms.flowVector.y
    ) * 1.2;
    float flowBeam = stroke(lineSDF(aspectUV, com, flowEnd), 0.0, 0.01 + bodyUniforms.analysis.w * 0.02);
    overlayColor = mix(overlayColor, float3(1.0, 0.42, 0.28), saturate(flowBeam * 0.45));

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
        float jointMetric = vrbOverlayJointMetric(in.uv, joints[i].positionXY, radius, uniforms.resolution);
        float ring = stroke(jointMetric, radius, radius * 0.24);
        float core = 1.0 - smoothstep(radius * 0.28, radius * 0.72, jointMetric);
        float3 tint = mix(float3(0.2, 0.85, 1.0), float3(1.0, 0.9, 0.45), joints[i].speed);
        overlayColor = mix(overlayColor, tint, saturate((ring * 0.95 + core * 0.5) * visibility));
    }

    return float4(saturate(overlayColor), 1.0);
}
