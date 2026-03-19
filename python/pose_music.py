from __future__ import annotations

import math
from copy import deepcopy
from typing import Any

from config import COCO17_JOINT_NAMES


JOINT_INDEX = {name: index for index, name in enumerate(COCO17_JOINT_NAMES)}
POSE_MUSIC_KEYS = (
    "lift",
    "spread",
    "twist",
    "gesture",
    "stride",
    "symmetry",
    "height",
    "lean",
    "energy",
)


def neutral_pose_metrics() -> dict[str, float]:
    return {
        "lift": 0.0,
        "spread": 0.0,
        "twist": 0.0,
        "gesture": 0.0,
        "stride": 0.0,
        "symmetry": 0.5,
        "height": 0.5,
        "lean": 0.0,
        "energy": 0.0,
    }


def copy_pose_person(person: dict[str, Any]) -> dict[str, Any]:
    return deepcopy(
        {
            "keypoints": person.get("keypoints", []),
            "bbox": person.get("bbox", []),
            "com": person.get("com", []),
            "speed": person.get("speed", 0.0),
        }
    )


def compute_pose_music_metrics(person: dict[str, Any], previous_person: dict[str, Any] | None = None) -> dict[str, float]:
    keypoints = person.get("keypoints", [])
    previous_keypoints = previous_person.get("keypoints", []) if previous_person else []
    bbox = _bbox(person.get("bbox", []))
    com = _point2(person.get("com", [0.5, 0.5]), (0.5, 0.5))
    speed = float(person.get("speed", 0.0))

    left_shoulder = _joint_point(keypoints, "left_shoulder", com)
    right_shoulder = _joint_point(keypoints, "right_shoulder", com)
    left_elbow = _joint_point(keypoints, "left_elbow", left_shoulder)
    right_elbow = _joint_point(keypoints, "right_elbow", right_shoulder)
    left_wrist = _joint_point(keypoints, "left_wrist", left_elbow)
    right_wrist = _joint_point(keypoints, "right_wrist", right_elbow)
    left_hip = _joint_point(keypoints, "left_hip", com)
    right_hip = _joint_point(keypoints, "right_hip", com)
    left_ankle = _joint_point(keypoints, "left_ankle", left_hip)
    right_ankle = _joint_point(keypoints, "right_ankle", right_hip)

    shoulder_center = _midpoint(left_shoulder, right_shoulder)
    hip_center = _midpoint(left_hip, right_hip)
    wrist_center = _midpoint(left_wrist, right_wrist)
    torso = max(_distance(shoulder_center, hip_center), 0.12)
    body_width = max(abs(bbox[2] - bbox[0]), _distance(left_shoulder, right_shoulder), 0.08)

    arm_span = max(
        left_shoulder[0],
        right_shoulder[0],
        left_elbow[0],
        right_elbow[0],
        left_wrist[0],
        right_wrist[0],
    ) - min(
        left_shoulder[0],
        right_shoulder[0],
        left_elbow[0],
        right_elbow[0],
        left_wrist[0],
        right_wrist[0],
    )
    leg_span = abs(left_ankle[0] - right_ankle[0])

    lift = _clip(((shoulder_center[1] - wrist_center[1]) / torso + 0.15) / 1.1, 0.0, 1.0)
    spread = _clip((arm_span / body_width - 0.85) / 1.25, 0.0, 1.0)
    twist = _clip(
        (((left_wrist[0] - left_shoulder[0]) - (right_shoulder[0] - right_wrist[0])) / body_width)
        + (((left_wrist[1] - right_wrist[1]) / torso) * 0.22),
        -1.0,
        1.0,
    )
    stride = _clip((leg_span / body_width - 0.22) / 0.9, 0.0, 1.0)

    arm_symmetry = abs(_distance(left_shoulder, left_wrist) - _distance(right_shoulder, right_wrist)) / max(
        _distance(left_shoulder, left_wrist) + _distance(right_shoulder, right_wrist),
        1e-6,
    )
    wrist_level_diff = abs(left_wrist[1] - right_wrist[1]) / torso
    leg_symmetry = abs(_distance(left_hip, left_ankle) - _distance(right_hip, right_ankle)) / max(
        _distance(left_hip, left_ankle) + _distance(right_hip, right_ankle),
        1e-6,
    )
    symmetry = _clip(1.0 - ((arm_symmetry * 0.45) + (wrist_level_diff * 0.35) + (leg_symmetry * 0.2)), 0.0, 1.0)

    lean = _clip((shoulder_center[0] - hip_center[0]) / torso, -1.0, 1.0)
    height = _clip(1.0 - shoulder_center[1], 0.0, 1.0)

    gesture_speed = _average(
        [
            _joint_speed(keypoints, previous_keypoints, "left_wrist"),
            _joint_speed(keypoints, previous_keypoints, "right_wrist"),
            _joint_speed(keypoints, previous_keypoints, "left_elbow"),
            _joint_speed(keypoints, previous_keypoints, "right_elbow"),
            _joint_speed(keypoints, previous_keypoints, "left_ankle"),
            _joint_speed(keypoints, previous_keypoints, "right_ankle"),
        ]
    )
    gesture = _clip((gesture_speed / torso) * 4.8 + (speed * 0.42), 0.0, 1.0)
    energy = _clip((gesture * 0.5) + (spread * 0.14) + (lift * 0.14) + (stride * 0.08) + (abs(twist) * 0.14) + (speed * 0.3), 0.0, 1.0)

    return {
        "lift": round(lift, 4),
        "spread": round(spread, 4),
        "twist": round(twist, 4),
        "gesture": round(gesture, 4),
        "stride": round(stride, 4),
        "symmetry": round(symmetry, 4),
        "height": round(height, 4),
        "lean": round(lean, 4),
        "energy": round(energy, 4),
    }


def metrics_to_named_pairs(metrics: dict[str, float]) -> list[float | str]:
    values: list[float | str] = []
    for key in POSE_MUSIC_KEYS:
        values.extend([key, float(metrics.get(key, neutral_pose_metrics()[key]))])
    return values


def _joint_point(keypoints: list[Any], name: str, fallback: tuple[float, float]) -> tuple[float, float]:
    index = JOINT_INDEX[name]
    if index < len(keypoints):
        return _point2(keypoints[index], fallback)
    return fallback


def _joint_speed(keypoints: list[Any], previous_keypoints: list[Any], name: str) -> float:
    index = JOINT_INDEX[name]
    if index >= len(keypoints) or index >= len(previous_keypoints):
        return 0.0
    current = _point2(keypoints[index], (0.5, 0.5))
    previous = _point2(previous_keypoints[index], current)
    return _distance(current, previous)


def _bbox(values: Any) -> tuple[float, float, float, float]:
    if isinstance(values, (list, tuple)) and len(values) >= 4:
        return (
            float(values[0]),
            float(values[1]),
            float(values[2]),
            float(values[3]),
        )
    return (0.3, 0.2, 0.7, 0.9)


def _point2(values: Any, fallback: tuple[float, float]) -> tuple[float, float]:
    if isinstance(values, (list, tuple)) and len(values) >= 2:
        return float(values[0]), float(values[1])
    return fallback


def _midpoint(a: tuple[float, float], b: tuple[float, float]) -> tuple[float, float]:
    return ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5)


def _distance(a: tuple[float, float], b: tuple[float, float]) -> float:
    return math.hypot(a[0] - b[0], a[1] - b[1])


def _average(values: list[float]) -> float:
    if not values:
        return 0.0
    return sum(values) / len(values)


def _clip(value: float, minimum: float, maximum: float) -> float:
    return max(minimum, min(maximum, value))
