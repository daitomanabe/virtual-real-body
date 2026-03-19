# Task: virtual-real-body

リアル身体 ↔ バーチャル身体 フィードバックシステム。
カメラで撮影したダンサーをリアルタイム解析し、仮想身体へフィードバック。
解析映像とCGバーチャルボディを並列プロジェクション出力する。

## ⚠️ CRITICAL: 毎iteration必須事項

**全てのHatは作業開始時・完了後に必ず実行:**

### 作業開始時
1. `.agent/scratchpad.md` を読んで現在の状況を把握
2. `.agent/iteration.log` を読んで直近の進捗を確認

### 作業完了後（イベント発行前）
1. `.agent/iteration.log` に記録を追記
   ```
   [{ISO8601}] iteration #{n} | {Hat名} | {受け取ったイベント} | {状態} | {具体的な変更内容}
   ```
2. `.agent/scratchpad.md` を更新（現在の状態・次に必要な作業を明記）
3. Git commit & push
   ```bash
   git add -A
   git commit -m "[Ralph] {Hat名}: {完了内容}"
   git push origin main
   ```

### エラー発生時
1. `.agent/errors.log` にエラー詳細を記録
2. 修正可能なら修正して続行、不可能なら LOOP_COMPLETE

---

## System Architecture

```
Camera
  │
  ▼
[Python Analysis Engine]  ← MPS (M5 Max) 加速
  ├── YOLODetectAnalyzer   yolo11n.pt         ZMQ: yolo.detect
  ├── YOLOPoseAnalyzer     yolo11n-pose.pt    ZMQ: yolo.pose  ← COCO-17
  ├── YOLOSegAnalyzer      yolo11n-seg.pt     ZMQ: yolo.seg   (opt)
  ├── OpticalFlowAnalyzer  Farneback dense    ZMQ: flow.dense
  ├── SparseFlowAnalyzer   Lucas-Kanade       ZMQ: flow.sparse
  ├── MediaPipeAnalyzer    33点骨格            ZMQ: mp.pose
  ├── DepthAnalyzer        Depth Anything v2  ZMQ: depth.map  (opt)
  ├── EventAnalyzer        離散イベント検出    ZMQ: event + OSC /trigger/*
  └── ParticleAnalyzer     パーティクル生成    ZMQ: particle.state
          │
          ├── ZMQ PUB  tcp://*:5555   (MessagePack binary)
          └── OSC UDP  → :9000  (Swift/Satin)
                       → :57120 (SuperCollider)

[Swift/Satin Renderer]  ← Metal / Apple Silicon GPU
  PoseReceiver: ZMQ SUB tcp://localhost:5555
  CameraCapture: AVCapture → MTLTexture
  MainRenderer (MetalViewRenderer):
    Pass 1: VirtualBody.metal  → virtualBodyTex (1280×720)
    Pass 2: PoseOverlay.metal  → overlayTex     (1280×720)
    Pass 3: Compositor.metal   → screen          (2560×720)
  LygiaResolver: #include "lygia/..." → inline MSL at runtime

[SuperCollider]
  OSCdef receivers on port 57120
  vrb_body (持続音) + 5×trigger synths + reverb/delay FX bus
```

---

## ⚠️ Critical Paths

```
Satin: /Users/daitomacm5/development/lab/source/github-public-only/fabric/Satin
Lygia: /Users/daitomacm5/development/lab/source/github-public-only/fabric/Lygia
```

Package.swift の依存:
```swift
.package(path: "/Users/daitomacm5/development/lab/source/github-public-only/fabric/Satin")
```

LygiaResolver の lygiaRoot:
```swift
URL(fileURLWithPath: "/Users/daitomacm5/development/lab/source/github-public-only/fabric/Lygia")
```

---

## Event Flow

```
work.start → git_setup → git.ready
git.ready  → planner   → plan.ready
plan.ready → python_builder → python.built
python.built → swift_builder → swift.built
swift.built  → shader_builder → shader.built
shader.built → sc_builder → sc.built
sc.built → integrator → integration.done / review.python / review.swift / review.shader / review.sc
review.python  → python_builder  (修正ループ)
review.swift   → swift_builder   (修正ループ)
review.shader  → shader_builder  (修正ループ)
review.sc      → sc_builder      (修正ループ)
integration.done → final_reviewer → LOOP_COMPLETE
```

---

## ZMQ Protocol (port 5555, MessagePack)

各メッセージ = topic_bytes + b" " + msgpack_payload

payload schema:
```json
{
  "analyzer":  "yolo.pose",
  "frame_id":  12345,
  "timestamp": 1234567890.123,
  "detected":  true,
  "data": { ... analyzer-specific ... }
}
```

numpy arrays は以下でシリアライズ:
```python
{"__ndarray__": true, "dtype": "float32", "shape": [33,3], "data": b"..."}
```

トピック一覧:
| topic | data.keys | fps |
|---|---|---|
| yolo.detect | detections[{id,cls,name,conf,bbox,cx,cy}] | 60 |
| yolo.pose   | persons[{id,keypoints(17,3),velocity(17,2),speed,com,bbox}] | 60 |
| yolo.seg    | segments[{id,cls,conf,polygon}] | 30 |
| flow.dense  | flow_f16(ndarray), energy, direction, quadrants | 30 |
| flow.sparse | vectors[{from,to,vel,speed}], trails, count | 30 |
| mp.pose     | landmarks_norm(33,4), landmarks_world(33,3), velocity, speed_norm, energy, com | 60 |
| depth.map   | depth_f16(ndarray), mean, com_depth, range | 10 |
| particle.state | spawn_points, attractors, emitters, field(ndarray) | 30 |
| event       | events[str], pose_speed, flow_energy, com | 60 |
| meta.fps    | fps{analyzer:hz} | 0.1 |

---

## OSC Protocol

### Swift/Satin 受信 (port 9000) — 連続値
```
/vrb/person/{id}/pos      x y          YOLO bbox重心 normalised
/vrb/person/{id}/speed    v            動きの速さ [0,1]
/vrb/person/{id}/bbox     x1 y1 x2 y2 conf
/vrb/person/{id}/joint/{name} x y conf COCO-17
/vrb/person/mp/{name}     x y z vis    MediaPipe 33点
/vrb/flow/energy          v
/vrb/flow/direction       angle
/vrb/depth/com            d
/vrb/meta/detected        0 or 1
```

### SuperCollider 受信 (port 57120)
```
# 連続制御 → named pair [key, val, key, val ...]
/synth/body      [freq, v, amp, v, cutoff, v, pan, v]
/fx/reverb/mix   [v]
/fx/reverb/room  [v]
/fx/delay/time   [v]
/fx/delay/feedback [v]

# 離散トリガー → [amp, v, freq, v]
/trigger/motion_onset
/trigger/person_enter
/trigger/person_exit
/trigger/impact
/trigger/flow_burst

# メタ
/vrb/meta/detected  [0 or 1]
```

### SC Synth Param Mapping
```python
# pose CoM y [0→1] → freq [1200→60 Hz] (exponential, inverted: top=high)
# pose speed  [0→1] → amp [0→0.85]
# flow energy [0→1] → reverb mix [0.05→0.80]
# flow dir (angle) → delay time [0.05→0.75 sec]
# depth com  [0→1] → reverb room [0.2→0.95]
```

---

## Directory Structure

```
virtual-real-body/
  ralph.yml
  PROMPT.md
  README.md               (final_reviewerが生成)
  COMPLETION_REPORT.md    (final_reviewerが生成)
  .gitignore
  .agent/
    scratchpad.md
    iteration.log
    errors.log
    memories.md
  specs/
    architecture.md
    python_engine.md
    swift_renderer.md
    sc_receiver.md
    osc_zmq_protocol.md
  python/
    config.py
    main.py
    requirements.txt
    core/
      __init__.py
      analyzer_base.py
      engine.py
    analyzers/
      __init__.py
      yolo_analyzer.py
      optical_flow_analyzer.py
      mediapipe_analyzer.py
      depth_analyzer.py
      event_analyzer.py
      particle_analyzer.py
    transport/
      __init__.py
      zmq_publisher.py
      osc_broadcaster.py
  swift/
    Package.swift
    Sources/VirtualRealBody/
      App/
        main.swift
        AppDelegate.swift
      Data/
        PoseData.swift
      Input/
        PoseReceiver.swift
        CameraCapture.swift
      Rendering/
        LygiaResolver.swift
        MainRenderer.swift
      Shaders/
        VirtualBody.metal
        PoseOverlay.metal
        Compositor.metal
  supercollider/
    vrb_receiver.scd
```

---

## Hat Roles

| Hat | 役割 | 入力 | 出力 |
|-----|------|------|------|
| git_setup | Git/GitHub初期化 | work.start | git.ready |
| planner | タスク分解・計画 | git.ready | plan.ready |
| python_builder | Python解析エンジン実装 | plan.ready / review.python | python.built |
| swift_builder | Swift/Satinアプリ構造 | python.built / review.swift | swift.built |
| shader_builder | Metal + LYGIAシェーダー | swift.built / review.shader | shader.built |
| sc_builder | SuperCollider受信エンジン | shader.built / review.sc | sc.built |
| integrator | 統合テスト・問題検出 | sc.built | integration.done / review.* |
| final_reviewer | 最終確認・README生成 | integration.done | LOOP_COMPLETE |

---

## Success Criteria

- [ ] `python main.py` が起動しカメラから解析を開始できる
- [ ] ZMQ メッセージが `tcp://localhost:5555` で受信できる
- [ ] OSC メッセージが port 9000 + 57120 に送信される
- [ ] `swift build` が成功する
- [ ] Satin の MetalViewRenderer が 60fps で動作する
- [ ] VirtualBody.metal が LYGIA の SDF 関数を使って描画する
- [ ] SC で vrb_receiver.scd が実行でき、OSCdef が登録される
- [ ] 全変更が remote に push 済み
- [ ] `.agent/iteration.log` が最新
- [ ] `COMPLETION_REPORT.md` が生成済み
- [ ] LOOP_COMPLETE
