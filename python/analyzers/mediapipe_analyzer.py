from __future__ import annotations

from core.analyzer_base import AnalysisResult, Analyzer


class MediaPipeAnalyzer(Analyzer):
    name = "mp.pose"
    zmq_topic = b"mp.pose"

    def process(self, frame_bgr: object, frame_id: int) -> AnalysisResult:
        return AnalysisResult(self.name, self.zmq_topic, frame_id, False, {"landmarks_norm": [], "energy": 0.0})
