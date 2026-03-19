from __future__ import annotations

from collections import defaultdict, deque
from dataclasses import dataclass
from time import monotonic
from typing import Iterable

from config import FPS_PUBLISH_INTERVAL, settings
from core.analyzer_base import AnalysisResult, Analyzer
from transport.osc_broadcaster import OSCBroadcaster
from transport.zmq_publisher import ZMQPublisher


@dataclass
class AnalyzerRuntime:
    analyzer: Analyzer
    frames: deque[float]


class AnalysisEngine:
    def __init__(
        self,
        analyzers: Iterable[Analyzer] | None = None,
        zmq_publisher: ZMQPublisher | None = None,
        osc_broadcaster: OSCBroadcaster | None = None,
        camera_index: int | None = None,
    ) -> None:
        self.camera_index = settings.camera_index if camera_index is None else camera_index
        self.zmq_publisher = zmq_publisher or ZMQPublisher(settings.zmq_bind)
        self.osc_broadcaster = osc_broadcaster or OSCBroadcaster(settings.osc_targets)
        self.inline_analyzers: list[Analyzer] = []
        self.meta_analyzers: list[Analyzer] = []
        self._fps_windows: dict[str, deque[float]] = defaultdict(lambda: deque(maxlen=120))
        self._last_fps_publish = monotonic()
        for analyzer in analyzers or []:
            self.register_analyzer(analyzer)

    def describe(self) -> str:
        names = [analyzer.name for analyzer in self.inline_analyzers + self.meta_analyzers]
        return (
            f"AnalysisEngine(camera_index={self.camera_index}, "
            f"zmq_bind={self.zmq_publisher.bind_address}, analyzers={names})"
        )

    def register_analyzer(self, analyzer: Analyzer) -> None:
        target = self.meta_analyzers if hasattr(analyzer, "consume_sibling_result") else self.inline_analyzers
        target.append(analyzer)

    def process_frame(self, frame_bgr: object, frame_id: int) -> list[AnalysisResult]:
        results: list[AnalysisResult] = []
        for analyzer in self.inline_analyzers:
            result = analyzer.process(frame_bgr, frame_id)
            results.append(result)
            self._on_result(result)
        return results

    def _on_result(self, result: AnalysisResult) -> None:
        self.zmq_publisher.publish(result.topic, result.as_payload())
        self.osc_broadcaster.send_batch(self._collect_osc_messages(result))
        self._fps_windows[result.analyzer].append(monotonic())

        for analyzer in self.meta_analyzers:
            for meta_result in analyzer.consume_sibling_result(result):
                self.zmq_publisher.publish(meta_result.topic, meta_result.as_payload())
                self.osc_broadcaster.send_batch(self._collect_osc_messages(meta_result))
                self._fps_windows[meta_result.analyzer].append(monotonic())

        self._publish_fps_if_due()

    def _collect_osc_messages(self, result: AnalysisResult) -> list[tuple[str, list[float]]]:
        messages: list[tuple[str, list[float]]] = []
        analyzers = self.inline_analyzers + self.meta_analyzers
        for analyzer in analyzers:
            if analyzer.name == result.analyzer:
                messages.extend(analyzer.osc_messages(result))
        return messages

    def _publish_fps_if_due(self) -> None:
        now = monotonic()
        if now - self._last_fps_publish < FPS_PUBLISH_INTERVAL:
            return
        payload = {
            "fps": {name: self._compute_fps(window, now) for name, window in self._fps_windows.items()}
        }
        self.zmq_publisher.publish(b"meta.fps", payload, analyzer_name="meta.fps")
        self._last_fps_publish = now

    @staticmethod
    def _compute_fps(window: deque[float], now: float) -> float:
        if len(window) < 2:
            return 0.0
        span = max(now - window[0], 1e-6)
        return round((len(window) - 1) / span, 3)
