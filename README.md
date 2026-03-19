# virtual-real-body

リアル身体とバーチャル身体を往復接続するリアルタイム・フィードバックシステムです。Python でダンサー映像を解析し、ZMQ で Swift/Satin レンダラへ、OSC で Swift と SuperCollider へ状態を配信します。Swift 側はカメラ映像と仮想身体を横並び 2 面で合成し、SuperCollider 側は連続制御とトリガーを音響へ変換します。

## Architecture

```text
Camera
  -> Python analysis engine
      -> ZMQ PUB tcp://*:5555
      -> OSC UDP 127.0.0.1:9000
      -> OSC UDP 127.0.0.1:57120
  -> Swift / Satin / Metal renderer
  -> SuperCollider receiver
```

- Python: `python/main.py` が `AnalysisEngine` を起動し、YOLO、optical flow、MediaPipe、depth、event、particle の各アナライザを実行します。
- Swift: `swift/Sources/VirtualRealBody/Rendering/MainRenderer.swift` が `VirtualBody.metal`、`PoseOverlay.metal`、`Compositor.metal` の 3 パスを使って 2560x720 の 2 面出力を描画します。
- SuperCollider: `supercollider/vrb_receiver.scd` が `/synth/body`、`/fx/*`、`/trigger/*` を受けて持続音とトリガー音を生成します。

## Requirements

- macOS 14+
- Python 3
- Swift 5.9+
- `external/Satin` と `external/lygia` の submodule
- Python dependencies: `pip install -r python/requirements.txt`
- SuperCollider は任意ですが、音響系を実行するには `sclang` が必要です

## How to Run

### 1. Python analysis engine

```bash
cd python
python3 -m pip install -r requirements.txt
python3 main.py --synthetic-input --frame-limit 120
```

- カメラ実行時は `python3 main.py`
- 接続確認のみなら `python3 main.py --dry-run`

### 2. Swift renderer

```bash
cd swift
swift build
swift run VirtualRealBody
```

- `PoseReceiver` は `tcp://localhost:5555` を購読し、`mp.pose` と `yolo.pose` を受信します。
- `external/lygia` のシェーダ include は `LygiaResolver.swift` が実行時に展開します。

### 3. SuperCollider receiver

```bash
sclang supercollider/vrb_receiver.scd
```

- 受信ポートは `57120`
- オーディオ設定は `numInputBusChannels = 0`、`sampleRate = 44100`

## ZMQ Topics

| Topic | Payload summary |
| --- | --- |
| `yolo.detect` | `detections[{id, cls, name, conf, bbox, cx, cy}]` |
| `yolo.pose` | `persons[{id, keypoints, velocity, speed, com, bbox}]` |
| `yolo.seg` | `segments[{id, cls, conf, polygon}]` |
| `flow.dense` | `flow_f16`, `energy`, `direction`, `quadrants` |
| `flow.sparse` | `vectors`, `trails`, `count` |
| `mp.pose` | `landmarks_norm`, `landmarks_world`, `velocity`, `speed_norm`, `energy`, `com` |
| `depth.map` | `depth_f16`, `mean`, `com_depth`, `range` |
| `particle.state` | `spawn_points`, `attractors`, `emitters`, `field` |
| `event` | `events`, `pose_speed`, `flow_energy`, `com` |
| `meta.fps` | `fps{analyzer: hz}` |

各 ZMQ パケットは `topic + b" " + msgpack_payload` の形式です。`msgpack` が無い環境では Python 側が `repr(...)` フォールバックを使い、Swift 側はそれも decode できるようにしています。

## OSC Addresses

### Swift / visual side (`127.0.0.1:9000`)

| Address | Values |
| --- | --- |
| `/vrb/person/{id}/pos` | `x y` |
| `/vrb/person/{id}/speed` | `v` |
| `/vrb/person/{id}/bbox` | `x1 y1 x2 y2 conf` |
| `/vrb/person/{id}/joint/{name}` | `x y conf` |
| `/vrb/person/mp/{name}` | `x y z vis` |
| `/vrb/flow/energy` | `v` |
| `/vrb/flow/direction` | `angle` |
| `/vrb/depth/com` | `d` |
| `/vrb/meta/detected` | `0 or 1` |

### SuperCollider (`127.0.0.1:57120`)

| Address | Values |
| --- | --- |
| `/synth/body` | `["freq", v, "amp", v, "cutoff", v, "pan", v]` |
| `/fx/reverb/mix` | `[v]` |
| `/fx/reverb/room` | `[v]` |
| `/fx/delay/time` | `[v]` |
| `/fx/delay/feedback` | `[v]` |
| `/trigger/motion_onset` | `["amp", v, "freq", v, "pan", v]` |
| `/trigger/person_enter` | `["amp", v, "freq", v, "pan", v]` |
| `/trigger/person_exit` | `["amp", v, "freq", v, "pan", v]` |
| `/trigger/impact` | `["amp", v, "freq", v, "pan", v]` |
| `/trigger/flow_burst` | `["amp", v, "freq", v, "pan", v]` |
| `/vrb/meta/detected` | `[0 or 1]` |

## Verification Status

- Verified: `cd python && python3 -c 'import config, main; from analyzers import YOLODetectAnalyzer, YOLOPoseAnalyzer, YOLOSegAnalyzer, OpticalFlowAnalyzer, SparseFlowAnalyzer, MediaPipeAnalyzer, DepthAnalyzer, EventAnalyzer, ParticleAnalyzer; from transport.zmq_publisher import ZMQPublisher, deserialise; from transport.osc_broadcaster import OSCBroadcaster; print("python import gate OK")'`
- Verified: `cd python && python3 main.py --dry-run`
- Verified: `cd python && python3 main.py --synthetic-input --frame-limit 2`
- Verified: `cd swift && swift build`
- Not locally verified: `sclang supercollider/vrb_receiver.scd` because `sclang` is not installed in this environment
- Not locally verified: `xcrun -sdk macosx metal ...` because the Metal CLI tool is not installed in this environment
