from __future__ import annotations

import math

from core.analyzer_base import AnalysisResult, Analyzer


class ParticleAnalyzer(Analyzer):
    name = "particle.state"
    zmq_topic = b"particle.state"

    def __init__(self) -> None:
        self._pose_com = [0.5, 0.5]
        self._flow_energy = 0.0
        self._flow_direction = 0.0

    def process(self, frame_bgr: object, frame_id: int) -> AnalysisResult:
        return AnalysisResult(
            self.name,
            self.zmq_topic,
            frame_id,
            False,
            {"spawn_points": [], "attractors": [], "emitters": [], "field": []},
        )

    def consume_sibling_result(self, result: AnalysisResult) -> list[AnalysisResult]:
        if result.analyzer == "yolo.pose":
            persons = result.data.get("persons", [])
            if persons:
                self._pose_com = list(persons[0].get("com", self._pose_com))
        elif result.analyzer == "mp.pose":
            com = result.data.get("com", [self._pose_com[0], self._pose_com[1], 0.0])
            self._pose_com = [float(com[0]), float(com[1])]
        elif result.analyzer == "flow.dense":
            self._flow_energy = float(result.data.get("energy", 0.0))
            self._flow_direction = float(result.data.get("direction", 0.0))
        else:
            return []

        radius = 0.04 + self._flow_energy * 0.12
        spawn_points = []
        for index in range(6):
            angle = self._flow_direction + index * (math.pi / 3.0)
            spawn_points.append(
                [
                    round(self._pose_com[0] + radius * math.cos(angle), 4),
                    round(self._pose_com[1] + radius * math.sin(angle), 4),
                ]
            )
        payload = {
            "spawn_points": spawn_points,
            "attractors": [{"position": [round(self._pose_com[0], 4), round(self._pose_com[1], 4)], "weight": 1.0}],
            "emitters": [{"position": spawn_points[0], "rate": round(4.0 + self._flow_energy * 20.0, 4)}],
            "field": [
                [round(math.cos(self._flow_direction) * self._flow_energy, 4), round(math.sin(self._flow_direction) * self._flow_energy, 4)],
                [round(-math.sin(self._flow_direction) * self._flow_energy, 4), round(math.cos(self._flow_direction) * self._flow_energy, 4)],
            ],
        }
        return [AnalysisResult(self.name, self.zmq_topic, result.frame_id, True, payload)]
