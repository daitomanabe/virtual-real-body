from __future__ import annotations

import math

from core.analyzer_base import AnalysisResult, Analyzer


class DepthAnalyzer(Analyzer):
    name = "depth.map"
    zmq_topic = b"depth.map"

    def process(self, frame_bgr: object, frame_id: int) -> AnalysisResult:
        phase = frame_id / 24.0
        com_depth = min(max(0.5 + 0.25 * math.sin(phase), 0.0), 1.0)
        mean = round(0.35 + 0.2 * math.cos(phase * 0.7), 4)
        depth_range = [round(max(com_depth - 0.15, 0.0), 4), round(min(com_depth + 0.15, 1.0), 4)]
        payload = {
            "depth_f16": [
                [round(com_depth, 4), round(com_depth * 0.92, 4)],
                [round(com_depth * 1.08, 4), round(com_depth, 4)],
            ],
            "mean": mean,
            "com_depth": round(com_depth, 4),
            "range": depth_range,
        }
        return AnalysisResult(self.name, self.zmq_topic, frame_id, True, payload)

    def osc_messages(self, result: AnalysisResult) -> list[tuple[str, list[float]]]:
        return [("/vrb/depth/com", [result.data.get("com_depth", 0.5)])]
