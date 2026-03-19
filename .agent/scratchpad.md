# Scratchpad — virtual-real-body

## Current State
- Iteration #1 active under Git Setup hat.
- GitHub auth is valid for account `daitomanabe`.
- Repository is not initialized yet; `git` inspection failed because `.git/` is absent.
- Top-level `scratchpad.md` exists as prior planning context, but `.agent/scratchpad.md` is now the workflow source of truth.

## Objective Focus
- Complete only Phase 0 Git setup in this iteration.
- Initialize git, confirm `.gitignore`, create the initial commit, create or attach the GitHub remote, and emit `git.ready`.

## Next Actions
- Run `git init`.
- Inspect `.gitignore` against the required bootstrap entries.
- Commit current project files and push `main` to GitHub.

## Outcome
- Git repository initialized on branch `main`.
- GitHub remote created at `https://github.com/daitomanabe/virtual-real-body`.
- Initial bootstrap commit pushed successfully.
- `.gitignore` now excludes `.ralph/` runtime state.

## Ready For Next Hat
- Emit `git.ready`.
- Planner should create the implementation task breakdown for Python, Swift, shaders, SuperCollider, and integration.

## Iteration #2 — Planner

### Repo Audit
- `PROMPT.md` and all files under `specs/` were reviewed as the current source of truth.
- `python/`, `swift/`, and `supercollider/` do not exist yet, so every implementation file in the target directory structure is still missing.
- Runtime task graph now mirrors the event flow: `python:core-transport` -> `python:analyzers` -> `swift:app-shell` -> `shader:metal-passes` -> `sc:receiver` -> `integration:verify` -> `final:review-docs`.

### Priority Order
- Priority 1: Python core and transport, because all downstream hats depend on the analysis engine contract and runtime message formats.
- Priority 2: Python analyzers and OSC/ZMQ payload shaping, completing the `python.built` boundary.
- Priority 3: Swift app shell and inputs, then Metal/Lygia shader passes for `swift.built` and `shader.built`.
- Priority 4: SuperCollider receiver after shader completion, matching the prescribed hat order.
- Priority 5: Integration verification and final documentation.

## Phase 1: Python Analysis Engine
- [ ] `python/config.py` — 全パラメータ（ZMQ/OSC ports, YOLO settings, SC mapping）
- [ ] `python/core/analyzer_base.py` — 抽象基底クラス
- [ ] `python/core/engine.py` — AnalysisEngine（スレッド管理、meta-analyzerフック）
- [ ] `python/transport/zmq_publisher.py` — ZMQ PUB + MessagePack
- [ ] `python/transport/osc_broadcaster.py` — OSC UDP → port 9000 + 57120
- [ ] `python/analyzers/yolo_analyzer.py` — YOLODetect/Pose/Seg（MPS backend）
- [ ] `python/analyzers/optical_flow_analyzer.py` — Farneback + Lucas-Kanade
- [ ] `python/analyzers/mediapipe_analyzer.py` — 33点骨格
- [ ] `python/analyzers/depth_analyzer.py` — Depth Anything v2（optional）
- [ ] `python/analyzers/event_analyzer.py` — 離散イベント検出 → SC `/trigger/*`
- [ ] `python/analyzers/particle_analyzer.py` — フロー → パーティクル spawn データ
- [ ] `python/main.py` — エントリポイント（CLI args）
- [ ] `python/requirements.txt`

## Phase 2: Swift Renderer（Satin + LYGIA）
- [ ] `swift/Package.swift` — Satin local path dependency
- [ ] `swift/Sources/VirtualRealBody/App/main.swift` + `AppDelegate.swift` — NSApp / fullscreen MTKView
- [ ] `swift/Sources/VirtualRealBody/Data/PoseData.swift` — バイナリプロトコル + GPU uniform structs
- [ ] `swift/Sources/VirtualRealBody/Input/PoseReceiver.swift` — ZMQ SUB（SwiftZMQ preferred, fallback if needed）
- [ ] `swift/Sources/VirtualRealBody/Input/CameraCapture.swift` — AVCapture → MTLTexture
- [ ] `swift/Sources/VirtualRealBody/Rendering/LygiaResolver.swift` — `#include "lygia/..."` → inline MSL
- [ ] `swift/Sources/VirtualRealBody/Rendering/MainRenderer.swift` — MetalViewRenderer subclass (3 passes)
- [ ] `swift/Sources/VirtualRealBody/Shaders/VirtualBody.metal` — SDF virtual body + LYGIA
- [ ] `swift/Sources/VirtualRealBody/Shaders/PoseOverlay.metal` — skeleton overlay + LYGIA
- [ ] `swift/Sources/VirtualRealBody/Shaders/Compositor.metal` — final 2-panel composite

## Phase 3: SuperCollider
- [ ] `supercollider/vrb_receiver.scd` — SynthDef + OSCdef

## Integration
- [ ] `python -> ZMQ -> Swift`（pose data flow）
- [ ] `python -> OSC -> SuperCollider`（events + continuous）
- [ ] `camera -> Python -> ZMQ -> Swift`（camera texture and overlay coordination）

### Next Hat Focus
- The next ready task after this plan closes is `python:core-transport`.
- Python Builder should create the directory tree first, then establish the shared message/result contract before implementing analyzer-specific logic.

## Iteration #3 — Ralph Coordination

### Current State
- `git.ready` and planning are complete; the workflow is positioned at the `plan.ready -> python_builder` boundary.
- Runtime task `task-1773905687-5825` (`python:core-transport`) is now in progress as the only unblocked implementation task.
- No relevant prior memory exists for Python engine scaffolding beyond the project bootstrap fixes already captured.

### Delegation Decision
- Re-emit `plan.ready` with a brief payload that points the Python Builder at `python:core-transport`.
- Keep this iteration coordination-only; no implementation work belongs in Ralph.

### Next Expected Work
- Python Builder should scaffold `python/config.py`, `python/main.py`, `python/core/`, and `python/transport/` first.
- Once core transport is built and importable, the builder can emit `python.built` to unblock Swift work and the analyzer task chain.

## Iteration #4 — Python Builder

### Core/Transport Scaffold
- Created the `python/` package tree with `config.py`, `main.py`, `core/`, `transport/`, and analyzer stub modules so the Python engine contract now exists on disk.
- Implemented `AnalysisResult`, `Analyzer`, `AnalysisEngine`, `ZMQPublisher`, and `OSCBroadcaster` with optional dependency guards so module imports succeed before runtime packages are installed.
- Added `requirements.txt` for the intended runtime stack and validated the current scaffold with `python3 -c` import checks.

### Notes
- `python` is not available as a shell command in this environment; `python3` was required for verification.
- Analyzer implementations are still placeholders and remain the next Python task.

## Phase 1: Python Analysis Engine
- [x] `python/config.py` — 全パラメータ（ZMQ/OSC ports, YOLO settings, SC mapping）
- [x] `python/core/analyzer_base.py` — 抽象基底クラス
- [x] `python/core/engine.py` — AnalysisEngine（スレッド管理、meta-analyzerフック）
- [x] `python/transport/zmq_publisher.py` — ZMQ PUB + MessagePack
- [x] `python/transport/osc_broadcaster.py` — OSC UDP → port 9000 + 57120
- [ ] `python/analyzers/yolo_analyzer.py` — YOLODetect/Pose/Seg（MPS backend）
- [ ] `python/analyzers/optical_flow_analyzer.py` — Farneback + Lucas-Kanade
- [ ] `python/analyzers/mediapipe_analyzer.py` — 33点骨格
- [ ] `python/analyzers/depth_analyzer.py` — Depth Anything v2（optional）
- [ ] `python/analyzers/event_analyzer.py` — 離散イベント検出 → SC `/trigger/*`
- [ ] `python/analyzers/particle_analyzer.py` — フロー → パーティクル spawn データ
- [x] `python/main.py` — エントリポイント（CLI args）
- [x] `python/requirements.txt`
