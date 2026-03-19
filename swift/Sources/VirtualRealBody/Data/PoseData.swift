import Foundation
import simd

let JOINT_COUNT = 33
let MAX_SEGMENT_POINTS = 8
let MAX_PARTICLE_POINTS = 8
let ZMQ_HOST = "127.0.0.1"
let ZMQ_PORT: UInt16 = 5555

struct PoseFrame: Sendable {
    var source: String
    var frameID: UInt64
    var timestamp: TimeInterval
    var detected: Bool
    var landmarks: [SIMD4<Float>]
    var velocities: [SIMD2<Float>]
    var speeds: [Float]
    var com: SIMD3<Float>
    var segmentCount: Int
    var segmentPoints: [SIMD2<Float>]
    var particleCount: Int
    var particlePoints: [SIMD2<Float>]
    var flowVector: SIMD2<Float>
    var quadrants: SIMD4<Float>
    var flowEnergy: Float
    var depth: Float
    var depthMean: Float

    static let empty = PoseFrame(
        source: "none",
        frameID: 0,
        timestamp: 0,
        detected: false,
        landmarks: Array(repeating: SIMD4<Float>(0, 0, 0, 0), count: JOINT_COUNT),
        velocities: Array(repeating: SIMD2<Float>(0, 0), count: JOINT_COUNT),
        speeds: Array(repeating: 0, count: JOINT_COUNT),
        com: SIMD3<Float>(0.5, 0.5, 0),
        segmentCount: 0,
        segmentPoints: Array(repeating: SIMD2<Float>(0.5, 0.5), count: MAX_SEGMENT_POINTS),
        particleCount: 0,
        particlePoints: Array(repeating: SIMD2<Float>(0.5, 0.5), count: MAX_PARTICLE_POINTS),
        flowVector: SIMD2<Float>(0, 0),
        quadrants: SIMD4<Float>(0, 0, 0, 0),
        flowEnergy: 0,
        depth: 0.5,
        depthMean: 0.5
    )
}

struct JointUniform {
    var positionXY: SIMD2<Float>
    var speed: Float
    var energy: Float
    var visibility: Float
    var pad: SIMD3<Float> = .zero
}

struct BoneUniform {
    var joints: SIMD2<UInt32>
    var pad: SIMD2<UInt32> = .zero
}

struct VirtualBodyUniform {
    var time: Float
    var resolution: SIMD2<Float>
    var jointCount: UInt32
    var boneCount: UInt32
    var segmentCount: UInt32
    var particleCount: UInt32
    var renderMode: UInt32
    var detected: UInt32
    var com: SIMD2<Float>
    var flowVector: SIMD2<Float>
    var quadrants: SIMD4<Float>
    var analysis: SIMD4<Float>
    var styleMix: SIMD4<Float>
}

struct OverlayUniform {
    var resolution: SIMD2<Float>
    var detected: UInt32
    var pad: UInt32 = 0
}

let BONES: [SIMD2<UInt32>] = [
    SIMD2(11, 13), SIMD2(13, 15),
    SIMD2(12, 14), SIMD2(14, 16),
    SIMD2(11, 12), SIMD2(11, 23),
    SIMD2(12, 24), SIMD2(23, 24),
    SIMD2(23, 25), SIMD2(25, 27),
    SIMD2(24, 26), SIMD2(26, 28),
    SIMD2(0, 11), SIMD2(0, 12)
]
