from __future__ import annotations

from math import hypot

from config import COCO17_JOINT_NAMES
from core.analyzer_base import AnalysisResult, Analyzer


class _BaseYOLOAnalyzer(Analyzer):
    def _frame_shape(self, frame_bgr: object) -> tuple[int, int]:
        shape = getattr(frame_bgr, "shape", None)
        if shape and len(shape) >= 2:
            return int(shape[0]), int(shape[1])
        return 720, 1280

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

    def process(self, frame_bgr: object, frame_id: int) -> AnalysisResult:
        height, width = self._frame_shape(frame_bgr)
        detected = frame_id % 120 != 0
        bbox = [0.28, 0.18, 0.72, 0.92]
        data = {
            "detections": [
                {
                    "id": 0,
                    "cls": 0,
                    "name": "person",
                    "conf": round(0.92 if detected else 0.0, 3),
                    "bbox": bbox,
                    "cx": round((bbox[0] + bbox[2]) * 0.5, 4),
                    "cy": round((bbox[1] + bbox[3]) * 0.5, 4),
                    "frame_size": [width, height],
                }
            ]
            if detected
            else []
        }
        return AnalysisResult(self.name, self.zmq_topic, frame_id, detected, data)


class YOLOPoseAnalyzer(_BaseYOLOAnalyzer):
    name = "yolo.pose"
    zmq_topic = b"yolo.pose"

    def process(self, frame_bgr: object, frame_id: int) -> AnalysisResult:
        phase = frame_id / 18.0
        sway = 0.08 * __import__("math").sin(phase)
        lift = 0.04 * __import__("math").cos(phase * 0.65)
        com_x = min(max(0.5 + sway, 0.0), 1.0)
        com_y = min(max(0.55 + lift, 0.0), 1.0)
        speed = min(hypot(sway, lift) * 4.0 + 0.08, 1.0)

        keypoints: list[list[float]] = []
        velocities: list[list[float]] = []
        for index, _joint in enumerate(COCO17_JOINT_NAMES):
            x = min(max(com_x + ((index % 2) - 0.5) * 0.12, 0.0), 1.0)
            y = min(max(com_y + ((index / 16.0) - 0.5) * 0.5, 0.0), 1.0)
            keypoints.append([round(x, 4), round(y, 4), 0.9])
            velocities.append([round(sway * 0.6, 4), round(lift * 0.6, 4)])

        bbox = [
            round(max(com_x - 0.22, 0.0), 4),
            round(max(com_y - 0.38, 0.0), 4),
            round(min(com_x + 0.22, 1.0), 4),
            round(min(com_y + 0.38, 1.0), 4),
        ]
        person = {
            "id": 0,
            "keypoints": keypoints,
            "velocity": velocities,
            "speed": round(speed, 4),
            "com": [round(com_x, 4), round(com_y, 4)],
            "bbox": bbox,
        }
        return AnalysisResult(self.name, self.zmq_topic, frame_id, True, {"persons": [person]})

    def osc_messages(self, result: AnalysisResult) -> list[tuple[str, list[float]]]:
        persons = result.data.get("persons", [])
        messages: list[tuple[str, list[float]]] = [("/vrb/meta/detected", [1 if persons else 0])]
        for person in persons:
            person_id = person["id"]
            com_x, com_y = person["com"]
            bbox = person["bbox"]
            messages.append((f"/vrb/person/{person_id}/pos", [com_x, com_y]))
            messages.append((f"/vrb/person/{person_id}/speed", [person["speed"]]))
            messages.append((f"/vrb/person/{person_id}/bbox", [*bbox, 1.0]))
            for name, joint in zip(COCO17_JOINT_NAMES, person["keypoints"]):
                messages.append((f"/vrb/person/{person_id}/joint/{name}", joint))
        return messages


class YOLOSegAnalyzer(_BaseYOLOAnalyzer):
    name = "yolo.seg"
    zmq_topic = b"yolo.seg"

    def process(self, frame_bgr: object, frame_id: int) -> AnalysisResult:
        phase = frame_id / 30.0
        cx = 0.5 + 0.06 * __import__("math").sin(phase)
        cy = 0.55 + 0.03 * __import__("math").cos(phase)
        polygon = [
            [round(cx - 0.18, 4), round(cy - 0.34, 4)],
            [round(cx + 0.16, 4), round(cy - 0.32, 4)],
            [round(cx + 0.2, 4), round(cy + 0.3, 4)],
            [round(cx - 0.19, 4), round(cy + 0.34, 4)],
        ]
        segment = {"id": 0, "cls": 0, "conf": 0.87, "polygon": polygon}
        return AnalysisResult(self.name, self.zmq_topic, frame_id, True, {"segments": [segment]})
