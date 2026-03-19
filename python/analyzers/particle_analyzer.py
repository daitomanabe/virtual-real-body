from __future__ import annotations

from core.analyzer_base import AnalysisResult, Analyzer


class ParticleAnalyzer(Analyzer):
    name = "particle.state"
    zmq_topic = b"particle.state"

    def process(self, frame_bgr: object, frame_id: int) -> AnalysisResult:
        return AnalysisResult(self.name, self.zmq_topic, frame_id, False, {"spawn_points": []})

    def consume_sibling_result(self, result: AnalysisResult) -> list[AnalysisResult]:
        return []
