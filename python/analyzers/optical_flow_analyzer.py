from __future__ import annotations

import math

from config import settings
from core.analyzer_base import AnalysisResult, Analyzer

try:
    import cv2
except ImportError:  # pragma: no cover
    cv2 = None

try:
    import numpy as np
except ImportError:  # pragma: no cover
    np = None


class OpticalFlowAnalyzer(Analyzer):
    name = "flow.dense"
    zmq_topic = b"flow.dense"
    target_fps = float(settings.flow_fps)

    def __init__(self) -> None:
        self._previous_gray = None
        self._scale = 1.0

    def process(self, frame_bgr: object, frame_id: int) -> AnalysisResult:
        if cv2 is None or np is None:
            return AnalysisResult(self.name, self.zmq_topic, frame_id, False, {"reason": "opencv_unavailable"})

        gray = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2GRAY)
        height, width = gray.shape[:2]
        max_dim = max(height, width)
        scale = min(settings.flow_max_dim / max(max_dim, 1), 1.0)
        if scale < 1.0:
            resized = cv2.resize(gray, (int(width * scale), int(height * scale)), interpolation=cv2.INTER_AREA)
        else:
            resized = gray
        self._scale = scale

        if self._previous_gray is None or self._previous_gray.shape != resized.shape:
            self._previous_gray = resized
            return AnalysisResult(
                self.name,
                self.zmq_topic,
                frame_id,
                False,
                {
                    "flow_f16": [[0.0, 0.0], [0.0, 0.0]],
                    "energy": 0.0,
                    "direction": 0.0,
                    "quadrants": {"tl": 0.0, "tr": 0.0, "bl": 0.0, "br": 0.0},
                },
            )

        flow = cv2.calcOpticalFlowFarneback(
            self._previous_gray,
            resized,
            None,
            pyr_scale=0.5,
            levels=3,
            winsize=15,
            iterations=3,
            poly_n=5,
            poly_sigma=1.2,
            flags=0,
        )
        self._previous_gray = resized

        flow_x = flow[..., 0]
        flow_y = flow[..., 1]
        magnitude = np.sqrt((flow_x * flow_x) + (flow_y * flow_y))
        mean_x = float(np.mean(flow_x))
        mean_y = float(np.mean(flow_y))
        mean_magnitude = float(np.mean(magnitude))
        energy = min(mean_magnitude / 6.0, 1.0)
        direction = math.atan2(mean_y, mean_x) if mean_magnitude > 1e-6 else 0.0

        half_h = max(flow.shape[0] // 2, 1)
        half_w = max(flow.shape[1] // 2, 1)
        quadrants = {
            "tl": round(min(float(np.mean(magnitude[:half_h, :half_w])) / 6.0, 1.0), 4),
            "tr": round(min(float(np.mean(magnitude[:half_h, half_w:])) / 6.0, 1.0), 4),
            "bl": round(min(float(np.mean(magnitude[half_h:, :half_w])) / 6.0, 1.0), 4),
            "br": round(min(float(np.mean(magnitude[half_h:, half_w:])) / 6.0, 1.0), 4),
        }

        sample_points = [
            (flow.shape[0] // 3, flow.shape[1] // 3),
            ((flow.shape[0] * 2) // 3, (flow.shape[1] * 2) // 3),
        ]
        flow_samples = []
        for y, x in sample_points:
            vector = flow[y, x]
            flow_samples.append([round(float(vector[0]), 4), round(float(vector[1]), 4)])

        payload = {
            "flow_f16": flow_samples,
            "energy": round(energy, 4),
            "direction": round(direction, 4),
            "quadrants": quadrants,
        }
        return AnalysisResult(self.name, self.zmq_topic, frame_id, energy > 0.005, payload)

    def osc_messages(self, result: AnalysisResult) -> list[tuple[str, list[float]]]:
        return [
            ("/vrb/flow/energy", [result.data.get("energy", 0.0)]),
            ("/vrb/flow/direction", [result.data.get("direction", 0.0)]),
        ]


class SparseFlowAnalyzer(Analyzer):
    name = "flow.sparse"
    zmq_topic = b"flow.sparse"
    target_fps = float(settings.sparse_flow_fps)

    def __init__(self) -> None:
        self._previous_gray = None
        self._points = None
        self._refresh_interval = 12

    def process(self, frame_bgr: object, frame_id: int) -> AnalysisResult:
        if cv2 is None or np is None:
            return AnalysisResult(self.name, self.zmq_topic, frame_id, False, {"reason": "opencv_unavailable"})

        gray = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2GRAY)
        if self._previous_gray is None:
            self._previous_gray = gray
            self._points = cv2.goodFeaturesToTrack(gray, maxCorners=24, qualityLevel=0.2, minDistance=12, blockSize=7)
            return AnalysisResult(self.name, self.zmq_topic, frame_id, False, {"vectors": [], "trails": [], "count": 0})

        if self._points is None or frame_id % self._refresh_interval == 0:
            self._points = cv2.goodFeaturesToTrack(gray, maxCorners=24, qualityLevel=0.2, minDistance=12, blockSize=7)

        if self._points is None:
            self._previous_gray = gray
            return AnalysisResult(self.name, self.zmq_topic, frame_id, False, {"vectors": [], "trails": [], "count": 0})

        next_points, status, _error = cv2.calcOpticalFlowPyrLK(self._previous_gray, gray, self._points, None)
        self._previous_gray = gray
        if next_points is None or status is None:
            self._points = None
            return AnalysisResult(self.name, self.zmq_topic, frame_id, False, {"vectors": [], "trails": [], "count": 0})

        good_new = next_points[status.flatten() == 1]
        good_old = self._points[status.flatten() == 1]
        self._points = good_new.reshape(-1, 1, 2) if len(good_new) else None

        height, width = gray.shape[:2]
        vectors = []
        trails = []
        for new, old in zip(good_new[:8], good_old[:8]):
            start_x, start_y = float(old[0]), float(old[1])
            end_x, end_y = float(new[0]), float(new[1])
            delta_x = end_x - start_x
            delta_y = end_y - start_y
            vectors.append(
                {
                    "from": [round(start_x / width, 4), round(start_y / height, 4)],
                    "to": [round(end_x / width, 4), round(end_y / height, 4)],
                    "vel": [round(delta_x / width, 4), round(delta_y / height, 4)],
                    "speed": round(min(math.hypot(delta_x, delta_y) / 24.0, 1.0), 4),
                }
            )
            trails.append([round(end_x / width, 4), round(end_y / height, 4)])

        return AnalysisResult(
            self.name,
            self.zmq_topic,
            frame_id,
            bool(vectors),
            {"vectors": vectors, "trails": trails, "count": len(vectors)},
        )
