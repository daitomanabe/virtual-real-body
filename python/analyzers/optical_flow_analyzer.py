from __future__ import annotations

from core.analyzer_base import AnalysisResult, Analyzer


class OpticalFlowAnalyzer(Analyzer):
    name = "flow.dense"
    zmq_topic = b"flow.dense"

    def process(self, frame_bgr: object, frame_id: int) -> AnalysisResult:
        return AnalysisResult(self.name, self.zmq_topic, frame_id, False, {"energy": 0.0, "direction": 0.0})


class SparseFlowAnalyzer(Analyzer):
    name = "flow.sparse"
    zmq_topic = b"flow.sparse"

    def process(self, frame_bgr: object, frame_id: int) -> AnalysisResult:
        return AnalysisResult(self.name, self.zmq_topic, frame_id, False, {"vectors": [], "count": 0})
