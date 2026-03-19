# Architecture — virtual-real-body

## Overview

3コンポーネント構成。Python解析 → ZMQ/OSC → Swift描画 / SuperCollider合成。

## Component Map

```
┌─────────────────────────────────────────────┐
│  Python Analysis Engine  (python/)          │
│  ─────────────────────────────────────────  │
│  Camera → AnalysisEngine                    │
│    inline analyzers (fast):                 │
│      OpticalFlowAnalyzer (Farneback)        │
│      SparseFlowAnalyzer (Lucas-Kanade)      │
│      EventAnalyzer (meta, reads siblings)   │
│      ParticleAnalyzer (meta, reads siblings)│
│    threaded analyzers (GPU heavy):          │
│      YOLODetectAnalyzer (yolo11n, MPS)      │
│      YOLOPoseAnalyzer   (yolo11n-pose, MPS) │
│      MediaPipeAnalyzer  (ANE)               │
│      [YOLOSegAnalyzer]  opt                 │
│      [DepthAnalyzer]    opt                 │
└──────────┬─────────────────────────────────┘
           │
    ┌──────┴──────────────────────┐
    │ ZMQ PUB tcp://*:5555        │  ← binary/MessagePack
    │ OSC UDP → :9000 + :57120    │  ← human-readable
    └──────┬──────────────┬───────┘
           │              │
    ┌──────▼──────┐  ┌────▼───────────────────┐
    │  Swift/Satin│  │  SuperCollider          │
    │  Renderer   │  │  supercollider/         │
    │  (swift/)   │  │  vrb_receiver.scd       │
    │             │  │                         │
    │  ZMQ SUB    │  │  OSCdef on port 57120   │
    │  AVCapture  │  │  vrb_body (持続音)       │
    │  Metal GPU  │  │  vrb_onset/impact/...   │
    │  3 passes   │  │  reverb + delay FX bus  │
    │  pose+seg+  │  │  aggressive FX bus      │
    │  flow+depth │  │                         │
    └─────────────┘  └─────────────────────────┘
```

## Data Flow (per frame)

```
1. OpenCV cap.read() → frame_bgr (BGR uint8)
2. inline analyzers: flow, events, particles
3. threaded analyzers: YOLO, MediaPipe (独立スレッド)
4. _on_result() callback:
   a. ZMQPublisher.publish(topic, result) → msgpack → tcp:5555
   b. OSCBroadcaster.send_batch(osc_msgs) → udp:9000 + udp:57120
   c. meta-analyzer更新 (EventAnalyzer/ParticleAnalyzer)
```

## Performance Targets (M5 Max 128GB)

| Component | Target FPS | Notes |
|---|---|---|
| YOLO detect | 60 | yolo11n nano, MPS |
| YOLO pose | 60 | yolo11n-pose, MPS |
| Optical flow | 60 | CPU (OpenCV) |
| MediaPipe | 60 | ANE加速 |
| Swift renderer | 60 | Metal GPU |
| Depth estimation | 10 | opt, MPS |
