from __future__ import annotations

import math
from time import monotonic

from config import MEDIAPIPE_33_JOINT_NAMES, settings
from core.analyzer_base import AnalysisResult, Analyzer

try:
    import cv2
except ImportError:  # pragma: no cover
    cv2 = None

try:
    import mediapipe as mp
except ImportError:  # pragma: no cover
    mp = None


class MediaPipeAnalyzer(Analyzer):
    name = "mp.pose"
    zmq_topic = b"mp.pose"
    target_fps = float(settings.pose_fps)

    def __init__(self) -> None:
        self._pose = None
        self._previous_landmarks: list[list[float]] | None = None
        self._previous_timestamp = monotonic()
        if mp is not None:
            self._pose = mp.solutions.pose.Pose(
                static_image_mode=False,
                model_complexity=settings.mediapipe_model_complexity,
                smooth_landmarks=True,
                enable_segmentation=False,
                min_detection_confidence=settings.mediapipe_min_detection_confidence,
                min_tracking_confidence=settings.mediapipe_min_tracking_confidence,
            )

    def process(self, frame_bgr: object, frame_id: int) -> AnalysisResult:
        if self._pose is None or cv2 is None:
            return AnalysisResult(self.name, self.zmq_topic, frame_id, False, {"reason": "mediapipe_unavailable"})

        frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
        result = self._pose.process(frame_rgb)
        now = monotonic()
        delta = max(now - self._previous_timestamp, 1e-6)
        self._previous_timestamp = now

        if not result.pose_landmarks:
            self._previous_landmarks = None
            return AnalysisResult(
                self.name,
                self.zmq_topic,
                frame_id,
                False,
                {
                    "landmarks_norm": [],
                    "landmarks_world": [],
                    "velocity": [],
                    "speed_norm": 0.0,
                    "energy": 0.0,
                    "com": [0.5, 0.5, 0.0],
                    "pseudo_depth": 0.5,
                },
            )

        landmarks_norm: list[list[float]] = []
        landmarks_world: list[list[float]] = []
        velocities: list[list[float]] = []
        visible_points: list[tuple[float, float, float]] = []

        for index, landmark in enumerate(result.pose_landmarks.landmark[: len(MEDIAPIPE_33_JOINT_NAMES)]):
            visibility = float(getattr(landmark, "visibility", 0.0))
            landmarks_norm.append(
                [
                    round(float(landmark.x), 4),
                    round(float(landmark.y), 4),
                    round(float(landmark.z), 4),
                    round(visibility, 4),
                ]
            )
            if visibility > 0.35:
                visible_points.append((float(landmark.x), float(landmark.y), float(landmark.z)))

        pose_world = getattr(result, "pose_world_landmarks", None)
        if pose_world:
            for landmark in pose_world.landmark[: len(MEDIAPIPE_33_JOINT_NAMES)]:
                landmarks_world.append(
                    [
                        round(float(landmark.x), 4),
                        round(float(landmark.y), 4),
                        round(float(landmark.z), 4),
                    ]
                )
        else:
            landmarks_world = [[point[0], point[1], point[2]] for point in landmarks_norm]

        if self._previous_landmarks is None:
            velocities = [[0.0, 0.0, 0.0] for _ in landmarks_norm]
        else:
            for current, previous in zip(landmarks_norm, self._previous_landmarks):
                velocities.append(
                    [
                        round((current[0] - previous[0]) / delta, 4),
                        round((current[1] - previous[1]) / delta, 4),
                        round((current[2] - previous[2]) / delta, 4),
                    ]
                )
        self._previous_landmarks = [point[:] for point in landmarks_norm]

        speed_values = [
            math.sqrt((velocity[0] * velocity[0]) + (velocity[1] * velocity[1]))
            for velocity, point in zip(velocities, landmarks_norm)
            if point[3] > 0.35
        ]
        speed_norm = min((sum(speed_values) / max(len(speed_values), 1)) * 0.2, 1.0)

        if visible_points:
            com_x = sum(point[0] for point in visible_points) / len(visible_points)
            com_y = sum(point[1] for point in visible_points) / len(visible_points)
            com_z = sum(point[2] for point in visible_points) / len(visible_points)
        else:
            com_x, com_y, com_z = 0.5, 0.5, 0.0

        left_shoulder = landmarks_norm[11]
        right_shoulder = landmarks_norm[12]
        left_hip = landmarks_norm[23]
        right_hip = landmarks_norm[24]
        shoulder_width = math.hypot(left_shoulder[0] - right_shoulder[0], left_shoulder[1] - right_shoulder[1])
        torso_height = math.hypot(
            ((left_shoulder[0] + right_shoulder[0]) * 0.5) - ((left_hip[0] + right_hip[0]) * 0.5),
            ((left_shoulder[1] + right_shoulder[1]) * 0.5) - ((left_hip[1] + right_hip[1]) * 0.5),
        )
        pseudo_depth = min(max(1.0 - min((shoulder_width + torso_height) * 1.35, 1.0), 0.0), 1.0)

        return AnalysisResult(
            self.name,
            self.zmq_topic,
            frame_id,
            True,
            {
                "landmarks_norm": landmarks_norm,
                "landmarks_world": landmarks_world,
                "velocity": velocities,
                "speed_norm": round(speed_norm, 4),
                "energy": round(speed_norm, 4),
                "com": [round(com_x, 4), round(com_y, 4), round(com_z, 4)],
                "pseudo_depth": round(pseudo_depth, 4),
            },
        )

    def osc_messages(self, result: AnalysisResult) -> list[tuple[str, list[float]]]:
        messages: list[tuple[str, list[float]]] = []
        for name, landmark in zip(MEDIAPIPE_33_JOINT_NAMES, result.data.get("landmarks_norm", [])):
            messages.append((f"/vrb/person/mp/{name}", landmark))
        return messages

    def close(self) -> None:
        if self._pose is not None:
            self._pose.close()
