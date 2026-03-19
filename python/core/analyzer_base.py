from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from time import time
from typing import Any


FrameLike = Any


@dataclass
class AnalysisResult:
    analyzer: str
    topic: bytes
    frame_id: int
    detected: bool
    data: dict[str, Any] = field(default_factory=dict)
    timestamp: float = field(default_factory=time)

    def as_payload(self) -> dict[str, Any]:
        return {
            "analyzer": self.analyzer,
            "frame_id": self.frame_id,
            "timestamp": self.timestamp,
            "detected": self.detected,
            "data": self.data,
        }


class Analyzer(ABC):
    name: str = ""
    zmq_topic: bytes = b""
    threaded: bool = False

    @abstractmethod
    def process(self, frame_bgr: FrameLike, frame_id: int) -> AnalysisResult:
        raise NotImplementedError

    def osc_messages(self, result: AnalysisResult) -> list[tuple[str, list[float]]]:
        return []

    def consume_sibling_result(self, result: AnalysisResult) -> list[AnalysisResult]:
        return []

    def close(self) -> None:
        return None
