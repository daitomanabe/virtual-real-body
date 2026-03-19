#include <metal_stdlib>
#include "lygia/generative/fbm.msl"
#include "lygia/sdf/circleSDF.msl"
#include "lygia/sdf/lineSDF.msl"
#include "lygia/draw/stroke.msl"
#include "lygia/color/palette.msl"
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

#ifndef VRB_FULLSCREEN_VERTEX
#define VRB_FULLSCREEN_VERTEX
vertex RasterizerData fullscreenVertex(uint vertexID [[vertex_id]]) {
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2(3.0, -1.0),
        float2(-1.0, 3.0)
    };

    RasterizerData out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = float2(
        vertexID == 1 ? 2.0 : 0.0,
        vertexID == 2 ? 2.0 : 0.0
    );
    return out;
}
#endif

constant uint kMaxJointCount = 33;

float2 vrbAspectUV(float2 uv, float2 resolution) {
    float2 centered = uv * 2.0 - 1.0;
    centered.x *= resolution.x / max(resolution.y, 1.0);
    return centered;
}

float vrbGrid(float2 uv, float2 resolution) {
    float2 scaled = uv * resolution / 56.0;
    float2 cell = abs(fract(scaled) - 0.5);
    float major = 1.0 - smoothstep(0.47, 0.5, max(cell.x, cell.y));
    float minor = 1.0 - smoothstep(0.485, 0.5, min(cell.x, cell.y));
    return max(major * 0.55, minor * 0.25);
}

float vrbJointDistance(float2 uv, float2 joint, float radius, float2 resolution) {
    float2 centered = vrbAspectUV(uv, resolution);
    float2 point = vrbAspectUV(joint, resolution);
    return lineSDF(centered, point, point + float2(0.0001, 0.0));
}

float4 vrbVelocityOverlay(float2 uv, constant JointUniform *joints, constant VirtualBodyUniform& uniforms) {
    float3 color = float3(0.0);
    float alpha = 0.0;

    for (uint i = 0; i < min(uniforms.jointCount, kMaxJointCount); ++i) {
        float visibility = saturate(joints[i].visibility);
        if (visibility <= 0.01) {
            continue;
        }

        float2 start = joints[i].positionXY;
        float2 centeredStart = vrbAspectUV(start, uniforms.resolution);
        float2 velocity = float2(
            cos(uniforms.time * 0.9 + float(i) * 0.37),
            sin(uniforms.time * 1.3 + float(i) * 0.21)
        ) * joints[i].energy * 0.08;
        float2 end = centeredStart + velocity;
        float distanceToVector = lineSDF(vrbAspectUV(uv, uniforms.resolution), centeredStart, end);
        float width = map(clamp(joints[i].energy, 0.0, 1.0), 0.0, 1.0, 0.002, 0.012);
        float intensity = stroke(distanceToVector, 0.0, width);
        float3 tint = palette(
            saturate(joints[i].speed * 0.8 + joints[i].energy * 0.2),
            float3(0.24, 0.42, 0.56),
            float3(0.35, 0.28, 0.38),
            float3(1.0, 1.0, 1.0),
            float3(0.15, 0.22, 0.32)
        );
        color += tint * intensity * visibility;
        alpha += intensity * visibility;
    }

    return float4(color, saturate(alpha));
}

fragment float4 virtualBodyFragment(
    RasterizerData in [[stage_in]],
    constant JointUniform *joints [[buffer(0)]],
    constant BoneUniform *bones [[buffer(1)]],
    constant VirtualBodyUniform &uniforms [[buffer(2)]]
) {
    float2 uv = in.uv;
    float2 aspectUV = vrbAspectUV(uv, uniforms.resolution);

    float noise = fbm(float3(aspectUV * 2.1, uniforms.time * 0.18));
    float field = saturate(noise * 0.5 + 0.5);
    float grid = vrbGrid(uv, uniforms.resolution);

    float3 background = mix(
        float3(0.018, 0.028, 0.05),
        float3(0.07, 0.19, 0.31),
        field
    );
    background += grid * float3(0.09, 0.14, 0.18);

    float3 boneColor = float3(0.0);
    float boneMask = 0.0;
    for (uint i = 0; i < uniforms.boneCount; ++i) {
        BoneUniform bone = bones[i];
        if (bone.joints.x >= uniforms.jointCount || bone.joints.y >= uniforms.jointCount) {
            continue;
        }
        JointUniform a = joints[bone.joints.x];
        JointUniform b = joints[bone.joints.y];
        float visibility = min(saturate(a.visibility), saturate(b.visibility));
        if (visibility <= 0.01) {
            continue;
        }

        float2 start = vrbAspectUV(a.positionXY, uniforms.resolution);
        float2 end = vrbAspectUV(b.positionXY, uniforms.resolution);
        float sdf = lineSDF(aspectUV, start, end);
        float thickness = map(clamp(max(a.speed, b.speed), 0.0, 1.0), 0.0, 1.0, 0.006, 0.024);
        float strokeAmount = stroke(sdf, 0.0, thickness);
        float3 tint = palette(
            saturate(max(a.speed, b.speed)),
            float3(0.12, 0.35, 0.44),
            float3(0.32, 0.28, 0.41),
            float3(1.0, 1.0, 1.0),
            float3(0.03, 0.18, 0.26)
        );
        boneColor += tint * strokeAmount * visibility;
        boneMask += strokeAmount * visibility;
    }

    float3 jointColor = float3(0.0);
    float jointMask = 0.0;
    for (uint i = 0; i < min(uniforms.jointCount, kMaxJointCount); ++i) {
        float visibility = saturate(joints[i].visibility);
        if (visibility <= 0.01) {
            continue;
        }

        float radius = map(clamp(joints[i].speed, 0.0, 1.0), 0.0, 1.0, 0.014, 0.042);
        float distanceToJoint = vrbJointDistance(uv, joints[i].positionXY, radius, uniforms.resolution);
        float ring = stroke(distanceToJoint, 0.0, radius);
        float core = 1.0 - smoothstep(radius * 0.35, radius, distanceToJoint);
        float3 tint = mix(
            float3(0.08, 0.38, 0.92),
            float3(0.35, 0.98, 1.0),
            saturate(joints[i].speed)
        );
        jointColor += tint * (ring * 0.85 + core * 0.55) * visibility;
        jointMask += (ring + core) * visibility;
    }

    float4 velocity = vrbVelocityOverlay(uv, joints, uniforms);
    float3 color = background;
    color = mix(color, color + boneColor, saturate(boneMask));
    color = mix(color, color + jointColor, saturate(jointMask));
    color = mix(color, color + velocity.rgb, velocity.a);
    color += field * 0.03;

    return float4(saturate(color), 1.0);
}
