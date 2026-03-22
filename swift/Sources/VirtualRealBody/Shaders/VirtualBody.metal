#include <metal_stdlib>
using namespace metal;

#include "lygia/generative/fbm.msl"
#include "lygia/sdf/circleSDF.msl"
#include "lygia/sdf/lineSDF.msl"
#include "lygia/draw/stroke.msl"
#include "lygia/color/palette.msl"
#include "lygia/math/map.msl"

#ifndef VRB_SHARED_TYPES
#define VRB_SHARED_TYPES
struct RasterizerData {
    float4 position [[position]];
    float2 uv;
};

struct VelocityRasterizerData {
    float4 position [[position]];
    float speed;
    float energy;
    float visibility;
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
constant uint kMaxSegmentPointCount = 8;
constant uint kMaxParticlePointCount = 8;

float2 vrbClipPosition(float2 uv, float2 resolution) {
    float2 clip = uv * 2.0 - 1.0;
    clip.y *= -1.0;
    return clip;
}

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

float vrbHash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float vrbJointMetric(float2 uv, float2 joint, float radius, float2 resolution) {
    float2 centered = vrbAspectUV(uv, resolution);
    float2 point = vrbAspectUV(joint, resolution);
    float safeRadius = max(radius, 0.0001);
    float2 local = (centered - point) / (safeRadius * 2.0) + 0.5;
    return circleSDF(local) * safeRadius;
}

float2 vrbAveragePoint(constant float2 *points, uint count, float2 fallback, float2 resolution) {
    if (count == 0u) {
        return vrbAspectUV(fallback, resolution);
    }

    float2 sum = float2(0.0);
    for (uint i = 0; i < min(count, kMaxSegmentPointCount); ++i) {
        sum += vrbAspectUV(points[i], resolution);
    }
    return sum / float(count);
}

float vrbPolylineField(float2 aspectUV, constant float2 *points, uint count, float2 resolution, float width) {
    if (count < 2u) {
        return 0.0;
    }

    float field = 0.0;
    for (uint i = 0; i < min(count, kMaxSegmentPointCount); ++i) {
        uint next = (i + 1u) % count;
        float2 start = vrbAspectUV(points[i], resolution);
        float2 end = vrbAspectUV(points[next], resolution);
        field += stroke(lineSDF(aspectUV, start, end), 0.0, width);
    }
    return saturate(field);
}

float vrbPointCloudField(float2 aspectUV, constant float2 *points, uint count, float2 resolution, float radius) {
    if (count == 0u) {
        return 0.0;
    }

    float field = 0.0;
    for (uint i = 0; i < min(count, kMaxSegmentPointCount); ++i) {
        float2 point = vrbAspectUV(points[i], resolution);
        float dist = distance(aspectUV, point);
        field += 1.0 - smoothstep(radius * 0.3, radius, dist);
    }
    return saturate(field / float(count));
}

float4 vrbMembraneLayer(
    float2 uv,
    float2 aspectUV,
    constant float2 *segmentPoints,
    constant VirtualBodyUniform &uniforms
) {
    uint segmentCount = min(uniforms.segmentCount, kMaxSegmentPointCount);
    float2 center = vrbAveragePoint(segmentPoints, segmentCount, uniforms.com, uniforms.resolution);
    float density = vrbPointCloudField(aspectUV, segmentPoints, segmentCount, uniforms.resolution, 0.34 + uniforms.analysis.x * 0.18);
    float contour = vrbPolylineField(aspectUV, segmentPoints, segmentCount, uniforms.resolution, 0.01 + uniforms.analysis.z * 0.012);
    float shell = 0.5 + 0.5 * sin(distance(aspectUV, center) * (18.0 + uniforms.analysis.x * 10.0) - uniforms.time * (1.2 + uniforms.analysis.w * 2.4));
    float bodyGlow = (1.0 - smoothstep(0.14, 0.58, distance(aspectUV, center))) * (0.45 + shell * 0.55);
    float alpha = saturate((density * 0.58) + (contour * 0.9) + (bodyGlow * 0.48));
    float3 color = mix(float3(0.11, 0.28, 0.44), float3(0.43, 0.94, 1.0), uniforms.analysis.x);
    color += float3(0.16, 0.08, 0.24) * shell;
    return float4(color * alpha, alpha);
}

float4 vrbRibbonLayer(
    float2 aspectUV,
    constant JointUniform *joints,
    constant VirtualBodyUniform &uniforms
) {
    float2 flow = float2(uniforms.flowVector.x * (uniforms.resolution.x / max(uniforms.resolution.y, 1.0)), uniforms.flowVector.y);
    float2 direction = normalize(flow + float2(0.0001, 0.0001));
    float2 normal = float2(-direction.y, direction.x);
    float3 color = float3(0.0);
    float alpha = 0.0;

    for (uint i = 0; i < min(uniforms.jointCount, kMaxJointCount); ++i) {
        float visibility = saturate(joints[i].visibility);
        if (visibility <= 0.01) {
            continue;
        }

        float2 start = vrbAspectUV(joints[i].positionXY, uniforms.resolution);
        float ribbonLength = 0.08 + uniforms.analysis.w * 0.32 + joints[i].energy * 0.18;
        float2 end = start + direction * ribbonLength;
        float laneOffset = (float(i % 3u) - 1.0) * (0.012 + uniforms.analysis.z * 0.01);
        float sdf = lineSDF(aspectUV, start + normal * laneOffset, end + normal * laneOffset);
        float width = 0.004 + joints[i].speed * 0.016 + uniforms.analysis.w * 0.01;
        float ribbon = stroke(sdf, 0.0, width);
        float shimmer = 0.5 + 0.5 * sin((distance(aspectUV, start) * 24.0) - uniforms.time * 6.0 + float(i));
        float3 tint = palette(
            saturate(joints[i].energy + uniforms.analysis.w * 0.35),
            float3(0.21, 0.22, 0.38),
            float3(0.32, 0.42, 0.22),
            float3(0.85, 0.92, 1.0),
            float3(0.08, 0.18, 0.34)
        );
        color += tint * ribbon * shimmer * visibility;
        alpha += ribbon * visibility;
    }

    return float4(color, saturate(alpha));
}

float4 vrbSwarmLayer(
    float2 aspectUV,
    constant float2 *particlePoints,
    constant VirtualBodyUniform &uniforms
) {
    uint particleCount = min(uniforms.particleCount, kMaxParticlePointCount);
    if (particleCount == 0u) {
        return float4(0.0);
    }

    float2 center = vrbAspectUV(uniforms.com, uniforms.resolution);
    float3 color = float3(0.0);
    float alpha = 0.0;
    for (uint i = 0; i < particleCount; ++i) {
        float2 point = vrbAspectUV(particlePoints[i], uniforms.resolution);
        float radius = 0.015 + uniforms.analysis.w * 0.05 + float(i) * 0.002;
        float dist = distance(aspectUV, point);
        float core = 1.0 - smoothstep(radius * 0.3, radius, dist);
        float ring = stroke(dist, radius * 1.2, radius * 0.32);
        float tether = stroke(lineSDF(aspectUV, center, point), 0.0, 0.003 + uniforms.analysis.z * 0.006);
        float3 tint = mix(float3(0.34, 0.98, 0.92), float3(1.0, 0.56, 0.32), fract((float(i) * 0.17) + uniforms.time * 0.05));
        color += tint * (core * 0.9 + ring * 0.65 + tether * 0.22);
        alpha += core * 0.85 + ring * 0.42 + tether * 0.18;
    }

    return float4(color, saturate(alpha));
}

float4 vrbPrismLayer(float2 uv, float2 aspectUV, constant VirtualBodyUniform &uniforms) {
    float2 center = vrbAspectUV(uniforms.com, uniforms.resolution);
    float dist = distance(aspectUV, center);
    float angle = atan2(aspectUV.y - center.y, aspectUV.x - center.x);
    float sliceA = 0.5 + 0.5 * sin(angle * 6.0 + uniforms.time * 0.8 + uniforms.analysis.x * 4.0);
    float sliceB = 0.5 + 0.5 * cos((uv.x - uv.y) * 18.0 + uniforms.time * 1.6);
    float shell = stroke(dist, 0.22 + uniforms.analysis.x * 0.18, 0.09 + uniforms.analysis.w * 0.04);
    float beam = stroke(lineSDF(aspectUV, center, center + normalize(uniforms.flowVector + float2(0.0001, 0.0001)) * (0.85 + uniforms.analysis.x * 0.25)), 0.0, 0.016);
    float energy = max(max(uniforms.quadrants.x, uniforms.quadrants.y), max(uniforms.quadrants.z, uniforms.quadrants.w));
    float alpha = saturate(shell * 0.75 + sliceA * sliceB * (0.15 + energy * 0.35) + beam * 0.32);
    float3 color = mix(float3(0.24, 0.16, 0.5), float3(0.72, 0.88, 1.0), sliceA);
    color += float3(0.22, 0.08, 0.32) * sliceB;
    return float4(color * alpha, alpha);
}

float4 vrbAuroraLayer(float2 uv, float2 aspectUV, constant VirtualBodyUniform &uniforms) {
    float2 center = vrbAspectUV(uniforms.com, uniforms.resolution);
    float flow = dot(aspectUV - center, normalize(float2(uniforms.flowVector.x + 0.001, uniforms.flowVector.y + 0.001)));
    float curtain = 0.5 + 0.5 * sin((aspectUV.y * 12.0) + (flow * 8.0) - uniforms.time * (1.2 + uniforms.analysis.w * 2.0));
    float drift = fbm(float3(aspectUV * 2.8 + float2(0.0, uniforms.time * 0.12), uniforms.time * 0.08));
    float falloff = 1.0 - smoothstep(0.2, 1.25, distance(aspectUV, center) + abs(flow) * 0.22);
    float alpha = saturate((curtain * 0.5 + drift * 0.45) * falloff);
    float3 color = mix(float3(0.08, 0.9, 0.62), float3(0.48, 0.24, 1.0), curtain);
    color += float3(0.12, 0.35, 0.85) * drift;
    return float4(color * alpha, alpha);
}

float4 vrbSonarLayer(float2 aspectUV, constant VirtualBodyUniform &uniforms) {
    float2 center = vrbAspectUV(uniforms.com, uniforms.resolution);
    float dist = distance(aspectUV, center);
    float pulse = fract(dist * (8.0 + uniforms.analysis.z * 18.0) - uniforms.time * (0.9 + uniforms.analysis.w * 2.8));
    float ring = smoothstep(0.04, 0.0, abs(pulse - 0.5));
    float sweepAngle = uniforms.time * 0.85 + uniforms.analysis.w * 5.0;
    float2 sweepDirection = float2(cos(sweepAngle), sin(sweepAngle));
    float beam = pow(saturate(dot(normalize(aspectUV - center + 0.0001), sweepDirection)), 24.0);
    float gridPulse = 0.5 + 0.5 * sin((aspectUV.x + aspectUV.y) * 22.0 - uniforms.time * 4.0);
    float alpha = saturate(ring * 0.7 + beam * 0.38 + gridPulse * 0.08);
    float3 color = mix(float3(0.0, 0.85, 0.78), float3(0.5, 1.0, 0.92), beam);
    color += float3(0.0, 0.15, 0.12) * gridPulse;
    return float4(color * alpha, alpha);
}

float4 vrbGlitchLayer(float2 uv, float2 aspectUV, constant VirtualBodyUniform &uniforms) {
    float stripeIndex = floor(uv.y * 96.0);
    float glitchSeed = vrbHash21(float2(stripeIndex, floor(uniforms.time * 7.0)));
    float stripeMask = step(0.78, glitchSeed);
    float offset = (glitchSeed - 0.5) * (0.18 + uniforms.analysis.w * 0.35) * stripeMask;
    float displacedNoise = fbm(float3(float2(aspectUV.x + offset, aspectUV.y) * 5.2, uniforms.time * 0.2));
    float shards = smoothstep(0.48, 0.82, displacedNoise);
    float scan = 0.5 + 0.5 * sin((uv.y * 420.0) - uniforms.time * 18.0);
    float alpha = saturate(shards * stripeMask * (0.4 + scan * 0.5));
    float3 color = float3(
        shards,
        smoothstep(0.35, 0.9, displacedNoise + 0.18),
        smoothstep(0.2, 0.78, displacedNoise + 0.33)
    );
    color *= float3(1.0, 0.42 + scan * 0.4, 0.9);
    return float4(color * alpha, alpha);
}

float4 vrbEclipseLayer(float2 uv, float2 aspectUV, constant VirtualBodyUniform &uniforms) {
    float2 center = vrbAspectUV(uniforms.com, uniforms.resolution);
    float dist = distance(aspectUV, center);
    float radius = 0.18 + uniforms.analysis.x * 0.24;
    float umbra = 1.0 - smoothstep(radius * 0.72, radius, dist);
    float corona = stroke(dist, radius * 1.05, 0.08 + uniforms.analysis.w * 0.04);
    float rays = pow(saturate(0.5 + 0.5 * cos(atan2(aspectUV.y - center.y, aspectUV.x - center.x) * 14.0 - uniforms.time * 1.4)), 2.0);
    float halo = (1.0 - smoothstep(radius, radius * 2.2, dist)) * rays;
    float vignette = smoothstep(1.45, 0.25, distance(aspectUV, float2(0.0)));
    float alpha = saturate(corona * 0.82 + halo * 0.36 + umbra * 0.22);
    float3 color = mix(float3(1.0, 0.46, 0.18), float3(0.48, 0.76, 1.0), uniforms.analysis.x);
    color = color * (corona + halo * 0.8) + float3(0.02, 0.03, 0.06) * umbra;
    return float4(color * alpha * vignette, alpha);
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

vertex VelocityRasterizerData velocityVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant JointUniform *joints [[buffer(0)]],
    constant VirtualBodyUniform &uniforms [[buffer(1)]]
) {
    VelocityRasterizerData out;

    if (instanceID >= min(uniforms.jointCount, kMaxJointCount)) {
        out.position = float4(0.0, 0.0, 0.0, 1.0);
        out.speed = 0.0;
        out.energy = 0.0;
        out.visibility = 0.0;
        return out;
    }

    JointUniform joint = joints[instanceID];
    float2 start = vrbClipPosition(joint.positionXY, uniforms.resolution);
    float2 velocity = float2(
        cos(uniforms.time * 0.9 + float(instanceID) * 0.37),
        sin(uniforms.time * 1.3 + float(instanceID) * 0.21)
    ) * joint.energy * 0.16;
    float2 end = start + float2(velocity.x, -velocity.y);
    float2 clipPosition = vertexID == 0 ? start : end;

    out.position = float4(clipPosition, 0.0, 1.0);
    out.speed = joint.speed;
    out.energy = joint.energy;
    out.visibility = joint.visibility;
    return out;
}

fragment float4 velocityFragment(VelocityRasterizerData in [[stage_in]]) {
    float visibility = saturate(in.visibility);
    float3 tint = palette(
        saturate(in.speed * 0.75 + in.energy * 0.25),
        float3(0.24, 0.42, 0.56),
        float3(0.35, 0.28, 0.38),
        float3(1.0, 1.0, 1.0),
        float3(0.15, 0.22, 0.32)
    );
    float alpha = saturate(map(clamp(in.energy, 0.0, 1.0), 0.0, 1.0, 0.2, 0.95) * visibility);
    return float4(tint, alpha);
}

fragment float4 virtualBodyFragment(
    RasterizerData in [[stage_in]],
    constant JointUniform *joints [[buffer(0)]],
    constant BoneUniform *bones [[buffer(1)]],
    constant float2 *segmentPoints [[buffer(2)]],
    constant float2 *particlePoints [[buffer(3)]],
    constant VirtualBodyUniform &uniforms [[buffer(4)]]
) {
    float2 uv = in.uv;
    float2 aspectUV = vrbAspectUV(uv, uniforms.resolution);

    float2 flowWarp = float2(
        uniforms.flowVector.x * (uniforms.resolution.x / max(uniforms.resolution.y, 1.0)),
        uniforms.flowVector.y
    );
    float noise = fbm(float3(aspectUV * (2.1 + uniforms.analysis.w * 0.9) + flowWarp * 0.22, uniforms.time * 0.18));
    float field = saturate(noise * 0.5 + 0.5);
    float grid = vrbGrid(uv, uniforms.resolution);

    float3 background = mix(
        float3(0.018, 0.028, 0.05),
        float3(0.07, 0.19, 0.31) + float3(uniforms.analysis.x * 0.06, uniforms.analysis.w * 0.04, uniforms.analysis.x * 0.09),
        field
    );
    background += grid * (float3(0.09, 0.14, 0.18) + uniforms.quadrants.xyz * 0.05);
    background += (0.5 + 0.5 * sin((uv.y + uniforms.time * 0.03) * 120.0)) * 0.012;

    if (uniforms.detected == 0u) {
        return float4(saturate(background), 1.0);
    }

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
        float jointMetric = vrbJointMetric(uv, joints[i].positionXY, radius, uniforms.resolution);
        float ring = stroke(jointMetric, radius, radius * 0.3);
        float core = 1.0 - smoothstep(radius * 0.35, radius, jointMetric);
        float3 tint = mix(
            float3(0.08, 0.38, 0.92),
            float3(0.35, 0.98, 1.0),
            saturate(joints[i].speed)
        );
        jointColor += tint * (ring * 0.85 + core * 0.55) * visibility;
        jointMask += (ring + core) * visibility;
    }

    float4 velocity = vrbVelocityOverlay(uv, joints, uniforms);
    float4 membrane = vrbMembraneLayer(uv, aspectUV, segmentPoints, uniforms);
    float4 ribbons = vrbRibbonLayer(aspectUV, joints, uniforms);
    float4 swarm = vrbSwarmLayer(aspectUV, particlePoints, uniforms);
    float4 prism = vrbPrismLayer(uv, aspectUV, uniforms);
    float4 aurora = vrbAuroraLayer(uv, aspectUV, uniforms);
    float4 sonar = vrbSonarLayer(aspectUV, uniforms);
    float4 glitch = vrbGlitchLayer(uv, aspectUV, uniforms);
    float4 eclipse = vrbEclipseLayer(uv, aspectUV, uniforms);
    float latticeWeight = uniforms.renderMode == 1u
        ? 1.0
        : saturate(1.0 - max(max(uniforms.styleMix.x, uniforms.styleMix.y), max(uniforms.styleMix.z, uniforms.styleMix.w)) * 0.72);
    latticeWeight = uniforms.renderMode == 0u ? max(latticeWeight, 0.3 + uniforms.analysis.z * 0.3) : latticeWeight;
    float auroraWeight = uniforms.renderMode == 6u ? 1.0 : (uniforms.renderMode == 0u ? saturate(uniforms.analysis.w * 0.35 + uniforms.analysis.x * 0.2) : 0.0);
    float sonarWeight = uniforms.renderMode == 7u ? 1.0 : (uniforms.renderMode == 0u ? saturate(uniforms.analysis.z * 0.28 + uniforms.analysis.w * 0.18) : 0.0);
    float glitchWeight = uniforms.renderMode == 8u ? 1.0 : (uniforms.renderMode == 0u ? saturate(uniforms.analysis.w * 0.26) : 0.0);
    float eclipseWeight = uniforms.renderMode == 9u ? 1.0 : (uniforms.renderMode == 0u ? saturate(abs(uniforms.analysis.x - 0.5) * 0.55 + max(uniforms.quadrants.x, uniforms.quadrants.z) * 0.22) : 0.0);

    float3 color = background;
    color = mix(color, color + boneColor * latticeWeight, saturate(boneMask * latticeWeight));
    color = mix(color, color + jointColor * latticeWeight, saturate(jointMask * latticeWeight));
    color = mix(color, color + velocity.rgb * latticeWeight, velocity.a * latticeWeight);
    color = mix(color, color + membrane.rgb, membrane.a * uniforms.styleMix.x);
    color = mix(color, color + ribbons.rgb, ribbons.a * uniforms.styleMix.y);
    color = mix(color, color + swarm.rgb, swarm.a * uniforms.styleMix.z);
    color = mix(color, color + prism.rgb, prism.a * uniforms.styleMix.w);
    color = mix(color, color + aurora.rgb, aurora.a * auroraWeight);
    color = mix(color, color + sonar.rgb, sonar.a * sonarWeight);
    color = mix(color, color + glitch.rgb, glitch.a * glitchWeight);
    color = mix(color, color + eclipse.rgb, eclipse.a * eclipseWeight);
    color += field * (0.02 + uniforms.analysis.w * 0.03);

    return float4(saturate(color), 1.0);
}
