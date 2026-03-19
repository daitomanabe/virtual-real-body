# Scratchpad — virtual-real-body

## Current State
- Git repository is initialized on `main` and connected to `origin`.
- GitHub auth is valid for account `daitomanabe`.
- GitHub repository `https://github.com/daitomanabe/virtual-real-body` is public.
- `Satin` and `lygia` submodules are checked out under `external/Satin` and `external/lygia`.
- No Ralph loop is currently active; the last completed handoff was `plan.ready`.
- Top-level `scratchpad.md` exists as prior planning context, but `.agent/scratchpad.md` is now the workflow source of truth.

## Infrastructure Update
- GitHub repository `https://github.com/daitomanabe/virtual-real-body` is public.
- `Satin` and `lygia` are managed as git submodules under `external/Satin` and `external/lygia`.
- Future Swift work should treat those submodule paths as the only supported dependency roots.
- Every Ralph iteration must push `origin/main` before emitting its done event.

## Objective Focus
- Keep the dependency strategy aligned with the new submodule/public requirements.
- Resume Ralph from `python_builder` after the infra/config update commit is pushed.

## Next Actions
- Commit the submodule and config updates.
- Push `origin/main`.
- Resume Ralph with `--continue` so `python_builder` continues under the new dependency assumptions.

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
- [ ] `swift/Package.swift` — Satin submodule dependency
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

## Iteration #5 — Ralph Coordination

### Current State
- `python:core-transport` is complete enough for imports; the remaining unblocked runtime task is `python:analyzers`.
- The builder needs to replace analyzer stubs with actual payload shaping and OSC event mapping before `python.built` can legitimately unblock Swift work.
- Relevant prior fixes still apply: use `python3` for import verification, and create/inspect files with safe quoted edits rather than shell heredocs that expand.

### Delegation Decision
- Re-emit `plan.ready` as the single routing event for Python Builder, with payload focused on analyzer implementation and event mapping.
- Keep Ralph coordination-only in this iteration; no direct implementation work is performed here.

### Next Expected Work
- Implement YOLO, optical flow, MediaPipe, depth, particle, and event analyzers against the established `AnalysisResult` contract.
- Wire OSC continuous values for ports `9000` and `57120`, plus `/trigger/*` event output for SuperCollider.
- Verify with `python3 -c 'import ...'` before the builder emits `python.built`.

## Iteration #6 — Python Builder

### Analyzer Implementation
- Replaced analyzer stubs with import-safe payload builders for YOLO detect/pose/seg, dense+sparse flow, MediaPipe pose, optional depth, particle state, and event synthesis.
- Fixed `AnalysisEngine.register_analyzer()` so only `event` and `particle.state` are treated as meta-analyzers.
- Added OSC mappings for person pose, MediaPipe joints, flow, depth, continuous SC control, and `/trigger/*` events derived from sibling analyzer state.
- Verified the required module set with `cd python && python3 -c ...`, which now prints `all imports OK`.

## Phase 1: Python Analysis Engine
- [x] `python/config.py` — 全パラメータ（ZMQ/OSC ports, YOLO settings, SC mapping）
- [x] `python/core/analyzer_base.py` — 抽象基底クラス
- [x] `python/core/engine.py` — AnalysisEngine（スレッド管理、meta-analyzerフック）
- [x] `python/transport/zmq_publisher.py` — ZMQ PUB + MessagePack
- [x] `python/transport/osc_broadcaster.py` — OSC UDP → port 9000 + 57120
- [x] `python/analyzers/yolo_analyzer.py` — YOLODetect/Pose/Seg（MPS backend contract scaffold）
- [x] `python/analyzers/optical_flow_analyzer.py` — Farneback + Lucas-Kanade payload scaffold
- [x] `python/analyzers/mediapipe_analyzer.py` — 33点骨格 payload scaffold
- [x] `python/analyzers/depth_analyzer.py` — Depth payload scaffold
- [x] `python/analyzers/event_analyzer.py` — 離散イベント検出 → SC `/trigger/*`
- [x] `python/analyzers/particle_analyzer.py` — フロー → パーティクル spawn データ
- [x] `python/main.py` — エントリポイント（CLI args）
- [x] `python/requirements.txt`

## Next Hat Focus
- Swift Builder can now rely on the Python-side topic names, payload keys, and OSC address map being present in code.

## Iteration #7 — Ralph Coordination

### Recovery State
- `task.resume` arrived because the previous loop did not publish an event even though Python Builder completed its implementation pass.
- Runtime tasks show `swift:app-shell` already marked `in_progress`, while downstream shader/SC/integration/doc tasks remain blocked behind the missing Python completion handoff.
- `swift/` exists as an untracked directory, so Ralph should not inspect or alter Swift implementation here; the correct recovery is to restore the missing workflow signal.

### Verification
- Re-ran the required Python import gate with `python3` from `python/` and confirmed the current package imports succeed.
- An initial probe used the wrong optical-flow export names; the resulting ImportError was recorded in `.agent/errors.log` and stored as a fix memory, then retried with the actual public names from `python/analyzers/__init__.py`.

### Delegation Decision
- Re-emit `python.built` with a brief recovery payload so Swift Builder can continue from the Python-complete boundary.
- Keep this iteration coordination-only; do not touch the untracked Swift worktree from Ralph.
