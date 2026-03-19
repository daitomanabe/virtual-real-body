from __future__ import annotations

import math

from core.analyzer_base import AnalysisResult, Analyzer


class OpticalFlowAnalyzer(Analyzer):
    name = "flow.dense"
    zmq_topic = b"flow.dense"

    def process(self, frame_bgr: object, frame_id: int) -> AnalysisResult:
        phase = frame_id / 12.0
        energy = min(0.15 + abs(math.sin(phase)) * 0.65, 1.0)
        direction = math.atan2(math.sin(phase * 0.7), math.cos(phase * 0.45))
        quadrants = {
            "tl": round(energy * 0.7, 4),
            "tr": round(energy * 0.9, 4),
            "bl": round(energy * 0.5, 4),
            "br": round(energy * 0.8, 4),
        }
        payload = {
            "flow_f16": [
                [round(math.sin(phase), 4), round(math.cos(phase), 4)],
                [round(math.sin(phase + 0.5), 4), round(math.cos(phase + 0.5), 4)],
            ],
            "energy": round(energy, 4),
            "direction": round(direction, 4),
            "quadrants": quadrants,
        }
        return AnalysisResult(self.name, self.zmq_topic, frame_id, energy > 0.01, payload)

    def osc_messages(self, result: AnalysisResult) -> list[tuple[str, list[float]]]:
        return [
            ("/vrb/flow/energy", [result.data.get("energy", 0.0)]),
            ("/vrb/flow/direction", [result.data.get("direction", 0.0)]),
        ]


class SparseFlowAnalyzer(Analyzer):
    name = "flow.sparse"
    zmq_topic = b"flow.sparse"

    def process(self, frame_bgr: object, frame_id: int) -> AnalysisResult:
        phase = frame_id / 10.0
        vectors = []
        for index in range(4):
            start_x = 0.2 + index * 0.15
            start_y = 0.3 + (index % 2) * 0.2
            delta_x = 0.03 * math.cos(phase + index * 0.4)
            delta_y = 0.04 * math.sin(phase + index * 0.3)
            vectors.append(
                {
                    "from": [round(start_x, 4), round(start_y, 4)],
                    "to": [round(start_x + delta_x, 4), round(start_y + delta_y, 4)],
                    "vel": [round(delta_x, 4), round(delta_y, 4)],
                    "speed": round(math.hypot(delta_x, delta_y) * 10.0, 4),
                }
            )
        trails = [vector["to"] for vector in vectors]
        return AnalysisResult(
            self.name,
            self.zmq_topic,
            frame_id,
            True,
            {"vectors": vectors, "trails": trails, "count": len(vectors)},
        )
