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
CAMERA_WIDTH = 1280
CAMERA_HEIGHT = 720
FLOW_FPS = 30
DEPTH_FPS = 10
FPS_PUBLISH_INTERVAL = 10.0
POSE_FPS = 45
SPARSE_FLOW_FPS = 20
FLOW_MAX_DIM = 320
MEDIAPIPE_MODEL_COMPLEXITY = 1
MEDIAPIPE_MIN_DETECTION_CONFIDENCE = 0.55
MEDIAPIPE_MIN_TRACKING_CONFIDENCE = 0.55

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

COCO17_JOINT_NAMES = [
    "nose",
    "left_eye",
    "right_eye",
    "left_ear",
    "right_ear",
    "left_shoulder",
    "right_shoulder",
    "left_elbow",
    "right_elbow",
    "left_wrist",
    "right_wrist",
    "left_hip",
    "right_hip",
    "left_knee",
    "right_knee",
    "left_ankle",
    "right_ankle",
]

MEDIAPIPE_33_JOINT_NAMES = [
    "nose",
    "left_eye_inner",
    "left_eye",
    "left_eye_outer",
    "right_eye_inner",
    "right_eye",
    "right_eye_outer",
    "left_ear",
    "right_ear",
    "mouth_left",
    "mouth_right",
    "left_shoulder",
    "right_shoulder",
    "left_elbow",
    "right_elbow",
    "left_wrist",
    "right_wrist",
    "left_pinky",
    "right_pinky",
    "left_index",
    "right_index",
    "left_thumb",
    "right_thumb",
    "left_hip",
    "right_hip",
    "left_knee",
    "right_knee",
    "left_ankle",
    "right_ankle",
    "left_heel",
    "right_heel",
    "left_foot_index",
    "right_foot_index",
]


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
    camera_width: int = CAMERA_WIDTH
    camera_height: int = CAMERA_HEIGHT
    pose_fps: int = POSE_FPS
    flow_fps: int = FLOW_FPS
    sparse_flow_fps: int = SPARSE_FLOW_FPS
    flow_max_dim: int = FLOW_MAX_DIM
    mediapipe_model_complexity: int = MEDIAPIPE_MODEL_COMPLEXITY
    mediapipe_min_detection_confidence: float = MEDIAPIPE_MIN_DETECTION_CONFIDENCE
    mediapipe_min_tracking_confidence: float = MEDIAPIPE_MIN_TRACKING_CONFIDENCE


settings = Settings()
