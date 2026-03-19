# virtual-real-body

`virtual-real-body` is a three-part realtime pipeline:

1. Python captures camera frames, runs body and motion analyzers, then publishes MessagePack payloads over ZMQ and control messages over OSC.
2. Swift builds a fullscreen Satin renderer that subscribes to pose data, expands LYGIA shader includes from the local submodule, and renders a two-panel Metal output.
3. SuperCollider receives OSC control data and maps motion, flow, and detection state into a continuous body synth plus discrete trigger events.

An optional browser control surface can sit on top of the SuperCollider layer for manual performance, preset recall, and macro actions.

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
- Registers persistent body, delay, chorus, reverb, and master synths plus trigger synths for motion onset, impact, enter, exit, and flow burst
- Accepts both analysis OSC from Python and manual control OSC from the WebUI bridge

The OSC parser accepts named-pair payloads from Python, including both `String` and `Symbol` keys.

### Browser control surface

- Bridge server: `python/sc_control_server.py`
- Static UI: `webui/index.html`, `webui/app.js`, `webui/styles.css`
- HTTP default: `127.0.0.1:8080`

The control surface mirrors the SuperCollider runtime state, exposes six presets, seven macro actions, direct trigger fire buttons, and continuous sliders for body, FX, and trigger parameters.

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
- A Python environment with `python-osc` installed for the WebUI bridge

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

### 4. Start the browser control surface

```bash
.venv/bin/python python/sc_control_server.py --port 8080 --sc-port 57120
```

Then open `http://127.0.0.1:8080/`.

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
| `/ui/body` | SuperCollider | named pairs `mode/texture/noiseMix/subMix/motion/resonance` |
| `/ui/fx/delay` | SuperCollider | named pairs `time/feedback/mix/tone` |
| `/ui/fx/chorus` | SuperCollider | named pairs `mix/rate/depth` |
| `/ui/fx/reverb` | SuperCollider | named pairs `mix/room/damp/tone` |
| `/ui/master` | SuperCollider | named pairs `drive/width/tremRate/tremDepth/output` |
| `/ui/trigger/onset` | SuperCollider | named pairs `mode/color` |
| `/ui/trigger/impact` | SuperCollider | named pairs `mode/color` |
| `/ui/trigger/enter` | SuperCollider | named pairs `mode/color` |
| `/ui/trigger/exit` | SuperCollider | named pairs `mode/color` |
| `/ui/trigger/flow` | SuperCollider | named pairs `mode/color` |
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
- `sclang supercollider/vrb_receiver.scd` boot / OSC registration
- `.venv/bin/python python/sc_control_server.py --port 8080 --sc-port 57120`
- browser control surface load, preset recall, macro actions, trigger fire, detected toggle, and slider-driven state patching
- `cd swift && swift build`

Not verified in the current environment:

- Live camera capture path with a physical device
- Standalone `xcrun metal` compilation
- Human-audition QA of every preset / action combination on external speakers

## Known limitations

- The live Python camera path depends on `opencv-python` and a locally accessible camera device.
- Metal CLI validation is blocked until Xcode command line Metal tools are available.
- The current browser control surface is performance-oriented and local-only; it does not persist custom presets yet.
