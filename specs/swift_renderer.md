# Swift Renderer Spec — virtual-real-body

## Paths (CRITICAL)

```
Satin submodule: external/Satin
Lygia submodule: external/lygia
```

## Package.swift

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VirtualRealBody",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../external/Satin"),
    ],
    targets: [
        .executableTarget(
            name: "VirtualRealBody",
            dependencies: ["Satin"],
            path: "Sources/VirtualRealBody",
            resources: [.process("Shaders")]
        )
    ]
)
```

## Render Pipeline (3 passes)

```
Frame N:
  update() — pull PoseFrame from PoseReceiver → update GPU buffers
  draw():
    Pass 1: VirtualBody.metal  (halfW×panelH) → virtualBodyTex (private)
    Pass 2: PoseOverlay.metal  (halfW×panelH) → overlayTex     (private)
    Pass 3: Compositor.metal   (outputW×panelH) → screen drawable
```

## Analysis Inputs

- `mp.pose` / `yolo.pose` for landmarks, velocity, CoM
- `yolo.seg` for silhouette polygon points
- `flow.dense` for motion energy, direction, quadrant weights
- `depth.map` for CoM depth and mean depth
- `particle.state` for spawn points around the body

`PoseReceiver` merges those topics into one render frame before GPU upload.

## GPU Buffer Layout

### JointUniform (32 bytes, shared)

```swift
struct JointUniform {
    var positionXY: SIMD2<Float>  // normalised x,y
    var speed:      Float
    var energy:     Float
    var visibility: Float
    var _pad:       SIMD3<Float>  // 12 bytes padding
}
// 8 + 4 + 4 + 4 + 12 = 32 bytes
```

### VirtualBodyUniform

```swift
struct VirtualBodyUniform {
    var time:        Float
    var resolution:  SIMD2<Float>
    var jointCount:  UInt32
    var boneCount:   UInt32
    var segmentCount: UInt32
    var particleCount: UInt32
    var renderMode:  UInt32
    var detected:    UInt32
    var com:         SIMD2<Float>
    var flowVector:  SIMD2<Float>
    var quadrants:   SIMD4<Float>
    var analysis:    SIMD4<Float>
    var styleMix:    SIMD4<Float>
}
```

`styleMix` は `membrane / ribbons / swarm / prism` の重みで、`lattice` は残差として扱う。

## ZMQ Reception

SwiftZMQ が利用できない場合のフォールバック:
Python側が Unix domain socket にも書き出す（pose_server.py の旧実装を参照）。
または Network.framework で TCP接続し raw bytes を読む。

推奨: pyzmq の Python側 → SwiftZMQ の Swift側
SwiftZMQ: https://github.com/azawawi/SwiftZMQ

## LygiaResolver

```swift
static let LYGIA_ROOT = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("../external/lygia")
    .standardizedFileURL

// #include "lygia/sdf/circleSDF.msl" → .msl ファイルをインライン展開
// makeLibrary(source:) に渡す前に resolve() を呼ぶ
```

## Output Layout

```
┌────────────────────┬────────────────────┐
│  Virtual Body      │  Camera + Overlay  │
│  (left, 1280×720)  │  (right, 1280×720) │
│  SDF data-viz      │  カメラ映像 +       │
│  Metal/LYGIA       │  骨格オーバーレイ   │
└────────────────────┴────────────────────┘
 ←─────────── 2560 × 720 ───────────────→
```

## Runtime Controls

- `0`: auto blend
- `1`: lattice
- `2`: membrane
- `3`: ribbons
- `4`: swarm
- `5`: prism
