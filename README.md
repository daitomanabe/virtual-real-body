# virtual-real-body

`virtual-real-body` is a three-part realtime pipeline:

1. Python captures camera frames, runs body and motion analyzers, then publishes MessagePack payloads over ZMQ and control messages over OSC.
2. Swift builds a fullscreen Satin renderer that subscribes to pose data, expands LYGIA shader includes from the local submodule, and renders a two-panel Metal output.
3. SuperCollider receives OSC control data and maps motion, flow, and detection state into a continuous body synth plus discrete trigger events.

The repository is public at `https://github.com/daitomanabe/virtual-real-body` and keeps both renderer dependencies as git submodules:

- `external/Satin`
- `external/lygia`

## Architecture

### Python analysis engine

- Entry point: `python/main.py`
- Core runtime: `python/core/engine.py`
- Transport:
  - ZMQ PUB `tcp://*:5555`
  - OSC `127.0.0.1:9000` and `127.0.0.1:57120`
- Analyzer set:
  - `yolo.detect`
  - `yolo.pose`
  - `yolo.seg`
  - `flow.dense`
  - `flow.sparse`
  - `mp.pose`
  - `depth.map`
  - `event`
  - `particle.state`

`EventAnalyzer` converts pose, flow, and depth state into both continuous OSC controls such as `/synth/body` and `/fx/*`, plus trigger events such as `/trigger/motion_onset` and `/trigger/impact`.

### Swift renderer

- Package root: `swift/`
- Dependency: local Satin package at `../external/Satin`
- Receiver: `swift/Sources/VirtualRealBody/Input/PoseReceiver.swift`
- Renderer: `swift/Sources/VirtualRealBody/Rendering/MainRenderer.swift`
- Shader include resolver: `swift/Sources/VirtualRealBody/Rendering/LygiaResolver.swift`

The renderer creates two offscreen passes:

- `VirtualBody.metal` for the synthetic body pass
- `PoseOverlay.metal` for camera and pose overlay

Those passes are combined in `Compositor.metal` into the final side-by-side output.

### SuperCollider receiver

- Script: `supercollider/vrb_receiver.scd`
- Boot config sets `numInputBusChannels = 0` and `sampleRate = 44100`
- Registers persistent body, delay, and reverb synths plus trigger synths for motion onset, impact, enter, exit, and flow burst

The OSC parser accepts named-pair payloads from Python, including both `String` and `Symbol` keys.

## Setup

### 1. Clone with submodules

```bash
git clone --recurse-submodules https://github.com/daitomanabe/virtual-real-body.git
cd virtual-real-body
```

If the repo is already cloned:

```bash
git submodule update --init --recursive
```

### 2. Install Python dependencies

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r python/requirements.txt
```

### 3. Prepare local tooling

- macOS 14+
- Swift 5.9+
- Xcode / Metal developer tools for full runtime shader validation
- SuperCollider for `sclang`

## Run

### 1. Start the Python engine

Smoke test without a camera:

```bash
cd python
python3 main.py --dry-run
python3 main.py --synthetic-input --frame-limit 2
python3 main.py --video-file /path/to/test.mp4 --frame-limit 60
```

Run the live pipeline:

```bash
cd python
python3 main.py
```

### 2. Start the Swift renderer

```bash
cd swift
swift build
swift run
```

### 3. Start the SuperCollider receiver

```bash
sclang supercollider/vrb_receiver.scd
```

## ZMQ topics

| Topic | Purpose |
| --- | --- |
| `yolo.detect` | YOLO person detection payloads |
| `yolo.pose` | YOLO keypoints, per-person CoM, velocity, speed |
| `yolo.seg` | Segmentation output payloads |
| `flow.dense` | Dense optical-flow energy and direction |
| `flow.sparse` | Sparse flow tracks |
| `mp.pose` | MediaPipe landmarks and motion data |
| `depth.map` | Depth summary payloads |
| `event` | Derived event state and current motion metrics |
| `particle.state` | Particle spawn and flow-derived state |
| `meta.fps` | Analyzer FPS snapshots |

## OSC addresses

| Address | Target | Payload |
| --- | --- | --- |
| `/synth/body` | SuperCollider | named pairs `freq/amp/cutoff/pan` |
| `/fx/reverb/mix` | SuperCollider | `[mix]` |
| `/fx/reverb/room` | SuperCollider | `[room]` |
| `/fx/delay/time` | SuperCollider | `[seconds]` |
| `/fx/delay/feedback` | SuperCollider | `[feedback]` |
| `/trigger/motion_onset` | SuperCollider | named pairs `amp/freq/pan` |
| `/trigger/person_enter` | SuperCollider | named pairs `amp/freq/pan` |
| `/trigger/person_exit` | SuperCollider | named pairs `amp/freq/pan` |
| `/trigger/impact` | SuperCollider | named pairs `amp/freq/pan` |
| `/trigger/flow_burst` | SuperCollider | named pairs `amp/freq/pan` |
| `/vrb/person/{id}/pos` | Swift / tools | `[x, y]` |
| `/vrb/person/{id}/speed` | Swift / tools | `[speed]` |
| `/vrb/person/{id}/bbox` | Swift / tools | `[x1, y1, x2, y2, conf]` |
| `/vrb/person/{id}/joint/{name}` | Swift / tools | `[x, y, conf]` |
| `/vrb/person/mp/{name}` | Swift / tools | `[x, y, z, vis]` |
| `/vrb/flow/energy` | Swift / tools | `[energy]` |
| `/vrb/flow/direction` | Swift / tools | `[angle]` |
| `/vrb/depth/com` | Swift / tools | `[depth]` |
| `/vrb/meta/detected` | Swift / SuperCollider | `[0 or 1]` |

## Verification status

Verified in the current environment:

- `git submodule status`
- `cd python && python3 -c "...import gate..."`
- `cd python && python3 main.py --dry-run`
- `cd python && python3 main.py --synthetic-input --frame-limit 2`
- `cd swift && swift build`

Not verified in the current environment:

- Live camera capture path with a physical device
- `sclang supercollider/vrb_receiver.scd`
- Standalone `xcrun metal` compilation

## Known limitations

- The live Python camera path depends on `opencv-python` and a locally accessible camera device.
- SuperCollider runtime validation is blocked until `sclang` is installed locally.
- Metal CLI validation is blocked until Xcode command line Metal tools are available.
