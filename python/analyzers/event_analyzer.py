from __future__ import annotations

from core.analyzer_base import AnalysisResult, Analyzer


class EventAnalyzer(Analyzer):
    name = "event"
    zmq_topic = b"event"

    def process(self, frame_bgr: object, frame_id: int) -> AnalysisResult:
        return AnalysisResult(self.name, self.zmq_topic, frame_id, False, {"events": []})

    def consume_sibling_result(self, result: AnalysisResult) -> list[AnalysisResult]:
        return []
