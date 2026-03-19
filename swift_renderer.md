# Swift Renderer Spec — virtual-real-body

## Paths (CRITICAL)

```
Satin: /Users/daitomacm5/development/lab/source/github-public-only/fabric/Satin
Lygia: /Users/daitomacm5/development/lab/source/github-public-only/fabric/Lygia
```

## Package.swift

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VirtualRealBody",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "/Users/daitomacm5/development/lab/source/github-public-only/fabric/Satin"),
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

### VirtualBodyUniform (24 bytes)
```swift
struct VirtualBodyUniform {
    var time:        Float
    var resolution:  SIMD2<Float>
    var jointCount:  UInt32
    var boneCount:   UInt32
    var _pad:        SIMD2<Float>
}
```

## ZMQ Reception

SwiftZMQ が利用できない場合のフォールバック:
Python側が Unix domain socket にも書き出す（pose_server.py の旧実装を参照）。
または Network.framework で TCP接続し raw bytes を読む。

推奨: pyzmq の Python側 → SwiftZMQ の Swift側
SwiftZMQ: https://github.com/azawawi/SwiftZMQ

## LygiaResolver

```swift
// Lygia root は定数で持つ
static let LYGIA_ROOT = URL(fileURLWithPath:
    "/Users/daitomacm5/development/lab/source/github-public-only/fabric/Lygia"
)

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
