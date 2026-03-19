from __future__ import annotations

import math

from config import MEDIAPIPE_33_JOINT_NAMES
from core.analyzer_base import AnalysisResult, Analyzer


class MediaPipeAnalyzer(Analyzer):
    name = "mp.pose"
    zmq_topic = b"mp.pose"

    def process(self, frame_bgr: object, frame_id: int) -> AnalysisResult:
        phase = frame_id / 20.0
        center_x = 0.5 + 0.05 * math.sin(phase)
        center_y = 0.5 + 0.04 * math.cos(phase * 0.75)
        landmarks_norm: list[list[float]] = []
        landmarks_world: list[list[float]] = []
        velocity: list[list[float]] = []
        for index, _joint in enumerate(MEDIAPIPE_33_JOINT_NAMES):
            spread = (index / 32.0) - 0.5
            x = min(max(center_x + spread * 0.18, 0.0), 1.0)
            y = min(max(center_y + spread * 0.55, 0.0), 1.0)
            z = round(-0.15 + spread * 0.3, 4)
            landmarks_norm.append([round(x, 4), round(y, 4), z, 0.92])
            landmarks_world.append([round((x - 0.5) * 2.0, 4), round((0.5 - y) * 2.0, 4), z])
            velocity.append([round(math.sin(phase) * 0.02, 4), round(math.cos(phase) * 0.02, 4), 0.0])
        energy = min(0.12 + abs(math.sin(phase * 1.4)) * 0.7, 1.0)
        speed_norm = round(energy * 0.85, 4)
        return AnalysisResult(
            self.name,
            self.zmq_topic,
            frame_id,
            True,
            {
                "landmarks_norm": landmarks_norm,
                "landmarks_world": landmarks_world,
                "velocity": velocity,
                "speed_norm": speed_norm,
                "energy": round(energy, 4),
                "com": [round(center_x, 4), round(center_y, 4), -0.05],
            },
        )

    def osc_messages(self, result: AnalysisResult) -> list[tuple[str, list[float]]]:
        messages: list[tuple[str, list[float]]] = []
        for name, landmark in zip(MEDIAPIPE_33_JOINT_NAMES, result.data.get("landmarks_norm", [])):
            messages.append((f"/vrb/person/mp/{name}", landmark))
        return messages
