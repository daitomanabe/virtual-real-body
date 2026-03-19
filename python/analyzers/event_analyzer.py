from __future__ import annotations

import math

from config import (
    EVENT_COOLDOWN_FRAMES,
    FLOW_BURST_THRESHOLD,
    IMPACT_ACCEL_THRESHOLD,
    MOTION_ONSET_THRESHOLD,
    SC_DELAY_TIME_MAX,
    SC_DELAY_TIME_MIN,
    SC_FREQ_HIGH,
    SC_FREQ_LOW,
    SC_REVERB_ROOM_MAX,
    SC_REVERB_ROOM_MIN,
)
from core.analyzer_base import AnalysisResult, Analyzer
from pose_music import compute_pose_music_metrics, copy_pose_person, metrics_to_named_pairs, neutral_pose_metrics


class EventAnalyzer(Analyzer):
    name = "event"
    zmq_topic = b"event"

    def __init__(self) -> None:
        self.pose_speed = 0.0
        self.com = [0.5, 0.5]
        self.flow_energy = 0.0
        self.flow_direction = 0.0
        self.depth_com = 0.5
        self.pose_metrics = neutral_pose_metrics()
        self.detected = False
        self.prev_detected = False
        self.prev_pose_speed = 0.0
        self.prev_flow_energy = 0.0
        self.prev_person: dict[str, object] | None = None
        self.cooldown = 0
        self._latest_messages: list[tuple[str, list[float | int]]] = []

    def process(self, frame_bgr: object, frame_id: int) -> AnalysisResult:
        return AnalysisResult(
            self.name,
            self.zmq_topic,
            frame_id,
            self.detected,
            {
                "events": [],
                "pose_speed": round(self.pose_speed, 4),
                "flow_energy": round(self.flow_energy, 4),
                "com": [round(self.com[0], 4), round(self.com[1], 4)],
                "pose": dict(self.pose_metrics),
            },
        )

    def consume_sibling_result(self, result: AnalysisResult) -> list[AnalysisResult]:
        if result.analyzer == "yolo.pose":
            persons = result.data.get("persons", [])
            self.detected = bool(persons)
            if persons:
                self.pose_speed = float(persons[0].get("speed", 0.0))
                self.com = list(persons[0].get("com", self.com))
                self.pose_metrics = compute_pose_music_metrics(persons[0], self.prev_person)
                self.prev_person = copy_pose_person(persons[0])
            else:
                self.pose_metrics = neutral_pose_metrics()
                self.prev_person = None
        elif result.analyzer == "flow.dense":
            self.flow_energy = float(result.data.get("energy", 0.0))
            self.flow_direction = float(result.data.get("direction", 0.0))
        elif result.analyzer == "depth.map":
            self.depth_com = float(result.data.get("com_depth", self.depth_com))

        if result.analyzer not in {"yolo.pose", "flow.dense", "depth.map"}:
            return []

        accel = max(self.pose_speed - self.prev_pose_speed, 0.0)
        events: list[str] = []
        messages: list[tuple[str, list[float | int]]] = self._continuous_messages()

        if self.detected and not self.prev_detected:
            events.append("person_enter")
            messages.append(self._trigger_message("/trigger/person_enter", amp=0.55, freq=self._freq_from_com()))
        if not self.detected and self.prev_detected:
            events.append("person_exit")
            messages.append(
                self._trigger_message(
                    "/trigger/person_exit",
                    amp=0.45,
                    freq=self._freq_from_com(),
                )
            )
        if (
            self.pose_speed > MOTION_ONSET_THRESHOLD
            and self.prev_pose_speed <= MOTION_ONSET_THRESHOLD
            and self.cooldown == 0
        ):
            events.append("motion_onset")
            messages.append(self._trigger_message("/trigger/motion_onset", amp=0.7, freq=self._freq_from_com()))
            self.cooldown = EVENT_COOLDOWN_FRAMES
        if accel > IMPACT_ACCEL_THRESHOLD and self.cooldown == 0:
            events.append("impact")
            messages.append(self._trigger_message("/trigger/impact", amp=0.8, freq=self._freq_from_com() * 1.1))
            self.cooldown = EVENT_COOLDOWN_FRAMES
        if (
            self.flow_energy > FLOW_BURST_THRESHOLD
            and self.prev_flow_energy <= FLOW_BURST_THRESHOLD
            and self.cooldown == 0
        ):
            events.append("flow_burst")
            messages.append(
                self._trigger_message("/trigger/flow_burst", amp=0.65, freq=self._freq_from_com() * 0.9)
            )
            self.cooldown = EVENT_COOLDOWN_FRAMES

        self.prev_detected = self.detected
        self.prev_pose_speed = self.pose_speed
        self.prev_flow_energy = self.flow_energy
        self.cooldown = max(self.cooldown - 1, 0)
        self._latest_messages = messages

        meta_result = AnalysisResult(
            analyzer=self.name,
            topic=self.zmq_topic,
            frame_id=result.frame_id,
            detected=self.detected,
            data={
                "events": events,
                "pose_speed": round(self.pose_speed, 4),
                "flow_energy": round(self.flow_energy, 4),
                "com": [round(self.com[0], 4), round(self.com[1], 4)],
                "pose": dict(self.pose_metrics),
            },
        )
        return [meta_result]

    def osc_messages(self, result: AnalysisResult) -> list[tuple[str, list[float | int]]]:
        return list(self._latest_messages)

    def _continuous_messages(self) -> list[tuple[str, list[float | int]]]:
        freq = self._freq_from_pose()
        amp = min(max(0.06 + (self.pose_metrics["energy"] * 0.54) + (self.pose_speed * 0.22), 0.0), 0.9)
        cutoff = round(
            220.0
            + (self.pose_metrics["lift"] * 1800.0)
            + (self.pose_metrics["spread"] * 1800.0)
            + (self.pose_metrics["gesture"] * 2600.0)
            + ((1.0 - self.pose_metrics["symmetry"]) * 1200.0),
            4,
        )
        pan = round(
            ((self.com[0] - 0.5) * 1.6)
            + (self.pose_metrics["lean"] * 0.38)
            + (self.pose_metrics["twist"] * 0.18),
            4,
        )
        reverb_mix = round(0.05 + (self.flow_energy * 0.55) + (self.pose_metrics["height"] * 0.16), 4)
        room = round(
            SC_REVERB_ROOM_MIN
            + ((self.depth_com * 0.7) + (self.pose_metrics["lift"] * 0.3)) * (SC_REVERB_ROOM_MAX - SC_REVERB_ROOM_MIN),
            4,
        )
        delay_time = round(
            SC_DELAY_TIME_MIN
            + (
                (self.pose_metrics["stride"] * 0.55)
                + ((self.flow_direction + math.pi) / (2.0 * math.pi)) * 0.45
            ) * (SC_DELAY_TIME_MAX - SC_DELAY_TIME_MIN),
            4,
        )
        delay_feedback = round(min(0.15 + (self.flow_energy * 0.35) + (self.pose_metrics["spread"] * 0.24), 0.9), 4)
        return [
            ("/synth/body", ["freq", round(freq, 4), "amp", round(amp, 4), "cutoff", cutoff, "pan", pan]),
            ("/synth/pose", metrics_to_named_pairs(self.pose_metrics)),
            ("/fx/reverb/mix", [reverb_mix]),
            ("/fx/reverb/room", [room]),
            ("/fx/delay/time", [delay_time]),
            ("/fx/delay/feedback", [delay_feedback]),
            ("/vrb/meta/detected", [1 if self.detected else 0]),
        ]

    def _freq_from_com(self) -> float:
        com_y = min(max(self.com[1], 0.0), 1.0)
        return SC_FREQ_HIGH * (SC_FREQ_LOW / SC_FREQ_HIGH) ** com_y

    def _freq_from_pose(self) -> float:
        base = self._freq_from_com()
        metrics = self.pose_metrics
        modulation = (
            0.82
            + (metrics["height"] * 0.28)
            + (metrics["lift"] * 0.22)
            + (metrics["stride"] * 0.08)
            - (metrics["gesture"] * 0.06)
        )
        return max(min(base * modulation, SC_FREQ_HIGH), SC_FREQ_LOW * 0.7)

    def _trigger_message(self, address: str, *, amp: float, freq: float) -> tuple[str, list[float | str]]:
        pan = round((self.com[0] - 0.5) * 2.0, 4)
        return (
            address,
            [
                "amp",
                round(max(amp, 0.0), 4),
                "freq",
                round(max(freq, 0.0), 4),
                "pan",
                pan,
            ],
        )
