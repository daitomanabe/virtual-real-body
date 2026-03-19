from __future__ import annotations

from core.analyzer_base import AnalysisResult, Analyzer


class _BaseYOLOAnalyzer(Analyzer):
    def process(self, frame_bgr: object, frame_id: int) -> AnalysisResult:
        return AnalysisResult(
            analyzer=self.name,
            topic=self.zmq_topic,
            frame_id=frame_id,
            detected=False,
            data={},
        )


class YOLODetectAnalyzer(_BaseYOLOAnalyzer):
    name = "yolo.detect"
    zmq_topic = b"yolo.detect"


class YOLOPoseAnalyzer(_BaseYOLOAnalyzer):
    name = "yolo.pose"
    zmq_topic = b"yolo.pose"


class YOLOSegAnalyzer(_BaseYOLOAnalyzer):
    name = "yolo.seg"
    zmq_topic = b"yolo.seg"
