from __future__ import annotations

from dataclasses import dataclass, field


ZMQ_BIND = "tcp://*:5555"
OSC_SWIFT_HOST = "127.0.0.1"
OSC_SWIFT_PORT = 9000
OSC_SC_HOST = "127.0.0.1"
OSC_SC_PORT = 57120

YOLO_DEVICE = "mps"
CAMERA_INDEX = 0
TARGET_FPS = 60
FLOW_FPS = 30
DEPTH_FPS = 10
FPS_PUBLISH_INTERVAL = 10.0

SC_FREQ_HIGH = 1200.0
SC_FREQ_LOW = 60.0
SC_REVERB_ROOM_MIN = 0.2
SC_REVERB_ROOM_MAX = 0.95
SC_DELAY_TIME_MIN = 0.05
SC_DELAY_TIME_MAX = 0.75

MOTION_ONSET_THRESHOLD = 0.18
IMPACT_ACCEL_THRESHOLD = 0.24
FLOW_BURST_THRESHOLD = 0.2
EVENT_COOLDOWN_FRAMES = 8


@dataclass
class OSCClientTarget:
    host: str
    port: int


@dataclass
class Settings:
    zmq_bind: str = ZMQ_BIND
    osc_targets: list[OSCClientTarget] = field(
        default_factory=lambda: [
            OSCClientTarget(OSC_SWIFT_HOST, OSC_SWIFT_PORT),
            OSCClientTarget(OSC_SC_HOST, OSC_SC_PORT),
        ]
    )
    yolo_device: str = YOLO_DEVICE
    camera_index: int = CAMERA_INDEX
    target_fps: int = TARGET_FPS


settings = Settings()
