from __future__ import annotations

import argparse
import copy
import json
import random
import threading
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

from pythonosc.udp_client import SimpleUDPClient


ROOT = Path(__file__).resolve().parent.parent
WEBUI_DIR = ROOT / "webui"


DEFAULT_STATE: dict[str, object] = {
    "body": {
        "core": {
            "freq": 220.0,
            "amp": 0.34,
            "cutoff": 1600.0,
            "pan": 0.0,
            "detected": True,
        },
        "voice": {
            "mode": 0.0,
            "texture": 0.35,
            "noiseMix": 0.18,
            "subMix": 0.55,
            "motion": 0.35,
            "resonance": 0.22,
        },
    },
    "fx": {
        "delay": {"time": 0.22, "feedback": 0.28, "mix": 0.32, "tone": 0.62},
        "chorus": {"mix": 0.12, "rate": 0.18, "depth": 0.012},
        "reverb": {"mix": 0.18, "room": 0.55, "damp": 0.45, "tone": 0.6},
        "master": {"drive": 0.18, "width": 0.25, "tremRate": 0.0, "tremDepth": 0.0, "output": 0.9},
    },
    "triggers": {
        "onset": {"mode": 0.0, "color": 0.35, "amp": 0.55, "freq": 480.0, "pan": 0.0},
        "impact": {"mode": 0.0, "color": 0.45, "amp": 0.75, "freq": 180.0, "pan": 0.0},
        "enter": {"mode": 0.0, "color": 0.45, "amp": 0.5, "freq": 320.0, "pan": -0.1},
        "exit": {"mode": 0.0, "color": 0.35, "amp": 0.35, "freq": 180.0, "pan": 0.1},
        "flow": {"mode": 0.0, "color": 0.5, "amp": 0.58, "freq": 1200.0, "pan": 0.2},
    },
}


PRESETS: dict[str, dict[str, object]] = {
    "glass-cavern": {
        "body": {
            "core": {"freq": 196.0, "amp": 0.4, "cutoff": 2100.0, "pan": -0.12, "detected": True},
            "voice": {"mode": 2.0, "texture": 0.42, "noiseMix": 0.16, "subMix": 0.48, "motion": 0.24, "resonance": 0.28},
        },
        "fx": {
            "delay": {"time": 0.34, "feedback": 0.46, "mix": 0.38, "tone": 0.68},
            "chorus": {"mix": 0.26, "rate": 0.18, "depth": 0.019},
            "reverb": {"mix": 0.34, "room": 0.84, "damp": 0.32, "tone": 0.76},
            "master": {"drive": 0.14, "width": 0.44, "tremRate": 0.0, "tremDepth": 0.0, "output": 0.84},
        },
        "triggers": {
            "onset": {"mode": 1.0, "color": 0.62, "amp": 0.48, "freq": 620.0, "pan": -0.12},
            "impact": {"mode": 1.0, "color": 0.54, "amp": 0.68, "freq": 220.0, "pan": 0.0},
            "enter": {"mode": 3.0, "color": 0.72, "amp": 0.42, "freq": 420.0, "pan": -0.15},
            "exit": {"mode": 1.0, "color": 0.4, "amp": 0.32, "freq": 180.0, "pan": 0.12},
            "flow": {"mode": 1.0, "color": 0.7, "amp": 0.62, "freq": 1480.0, "pan": 0.28},
        },
    },
    "machine-ritual": {
        "body": {
            "core": {"freq": 144.0, "amp": 0.52, "cutoff": 1200.0, "pan": 0.04, "detected": True},
            "voice": {"mode": 1.0, "texture": 0.68, "noiseMix": 0.12, "subMix": 0.72, "motion": 0.28, "resonance": 0.2},
        },
        "fx": {
            "delay": {"time": 0.18, "feedback": 0.34, "mix": 0.24, "tone": 0.58},
            "chorus": {"mix": 0.08, "rate": 0.31, "depth": 0.01},
            "reverb": {"mix": 0.12, "room": 0.42, "damp": 0.52, "tone": 0.5},
            "master": {"drive": 0.36, "width": 0.18, "tremRate": 0.0, "tremDepth": 0.0, "output": 0.92},
        },
        "triggers": {
            "onset": {"mode": 3.0, "color": 0.44, "amp": 0.64, "freq": 540.0, "pan": 0.0},
            "impact": {"mode": 0.0, "color": 0.35, "amp": 0.86, "freq": 132.0, "pan": 0.0},
            "enter": {"mode": 2.0, "color": 0.34, "amp": 0.5, "freq": 280.0, "pan": -0.08},
            "exit": {"mode": 2.0, "color": 0.26, "amp": 0.34, "freq": 120.0, "pan": 0.08},
            "flow": {"mode": 3.0, "color": 0.42, "amp": 0.5, "freq": 980.0, "pan": 0.18},
        },
    },
    "tidal-halo": {
        "body": {
            "core": {"freq": 286.0, "amp": 0.28, "cutoff": 3200.0, "pan": 0.18, "detected": True},
            "voice": {"mode": 3.0, "texture": 0.52, "noiseMix": 0.3, "subMix": 0.3, "motion": 0.78, "resonance": 0.34},
        },
        "fx": {
            "delay": {"time": 0.42, "feedback": 0.51, "mix": 0.4, "tone": 0.76},
            "chorus": {"mix": 0.34, "rate": 0.22, "depth": 0.026},
            "reverb": {"mix": 0.38, "room": 0.92, "damp": 0.28, "tone": 0.84},
            "master": {"drive": 0.1, "width": 0.58, "tremRate": 0.17, "tremDepth": 0.18, "output": 0.78},
        },
        "triggers": {
            "onset": {"mode": 2.0, "color": 0.78, "amp": 0.46, "freq": 720.0, "pan": 0.16},
            "impact": {"mode": 2.0, "color": 0.62, "amp": 0.58, "freq": 240.0, "pan": 0.0},
            "enter": {"mode": 1.0, "color": 0.74, "amp": 0.38, "freq": 510.0, "pan": 0.2},
            "exit": {"mode": 3.0, "color": 0.62, "amp": 0.28, "freq": 160.0, "pan": -0.18},
            "flow": {"mode": 0.0, "color": 0.86, "amp": 0.72, "freq": 1880.0, "pan": -0.22},
        },
    },
    "ember-choir": {
        "body": {
            "core": {"freq": 172.0, "amp": 0.38, "cutoff": 2400.0, "pan": -0.06, "detected": True},
            "voice": {"mode": 2.0, "texture": 0.64, "noiseMix": 0.24, "subMix": 0.44, "motion": 0.48, "resonance": 0.38},
        },
        "fx": {
            "delay": {"time": 0.28, "feedback": 0.36, "mix": 0.24, "tone": 0.58},
            "chorus": {"mix": 0.18, "rate": 0.12, "depth": 0.016},
            "reverb": {"mix": 0.29, "room": 0.76, "damp": 0.36, "tone": 0.7},
            "master": {"drive": 0.22, "width": 0.36, "tremRate": 0.0, "tremDepth": 0.0, "output": 0.84},
        },
        "triggers": {
            "onset": {"mode": 2.0, "color": 0.58, "amp": 0.42, "freq": 560.0, "pan": -0.06},
            "impact": {"mode": 1.0, "color": 0.48, "amp": 0.7, "freq": 164.0, "pan": 0.0},
            "enter": {"mode": 0.0, "color": 0.68, "amp": 0.46, "freq": 360.0, "pan": -0.1},
            "exit": {"mode": 3.0, "color": 0.42, "amp": 0.26, "freq": 140.0, "pan": 0.1},
            "flow": {"mode": 2.0, "color": 0.62, "amp": 0.64, "freq": 1540.0, "pan": 0.14},
        },
    },
    "submerged-brass": {
        "body": {
            "core": {"freq": 128.0, "amp": 0.48, "cutoff": 1040.0, "pan": 0.08, "detected": True},
            "voice": {"mode": 1.0, "texture": 0.74, "noiseMix": 0.14, "subMix": 0.76, "motion": 0.18, "resonance": 0.18},
        },
        "fx": {
            "delay": {"time": 0.16, "feedback": 0.24, "mix": 0.18, "tone": 0.42},
            "chorus": {"mix": 0.09, "rate": 0.08, "depth": 0.008},
            "reverb": {"mix": 0.16, "room": 0.52, "damp": 0.54, "tone": 0.46},
            "master": {"drive": 0.28, "width": 0.2, "tremRate": 0.0, "tremDepth": 0.0, "output": 0.9},
        },
        "triggers": {
            "onset": {"mode": 3.0, "color": 0.32, "amp": 0.6, "freq": 420.0, "pan": 0.02},
            "impact": {"mode": 0.0, "color": 0.28, "amp": 0.9, "freq": 110.0, "pan": 0.0},
            "enter": {"mode": 2.0, "color": 0.3, "amp": 0.44, "freq": 260.0, "pan": -0.04},
            "exit": {"mode": 1.0, "color": 0.22, "amp": 0.28, "freq": 104.0, "pan": 0.04},
            "flow": {"mode": 3.0, "color": 0.35, "amp": 0.46, "freq": 860.0, "pan": 0.16},
        },
    },
    "shattered-lattice": {
        "body": {
            "core": {"freq": 344.0, "amp": 0.26, "cutoff": 4200.0, "pan": 0.22, "detected": True},
            "voice": {"mode": 3.0, "texture": 0.82, "noiseMix": 0.34, "subMix": 0.18, "motion": 0.88, "resonance": 0.46},
        },
        "fx": {
            "delay": {"time": 0.38, "feedback": 0.56, "mix": 0.44, "tone": 0.82},
            "chorus": {"mix": 0.3, "rate": 0.44, "depth": 0.022},
            "reverb": {"mix": 0.36, "room": 0.88, "damp": 0.22, "tone": 0.86},
            "master": {"drive": 0.18, "width": 0.62, "tremRate": 0.28, "tremDepth": 0.24, "output": 0.74},
        },
        "triggers": {
            "onset": {"mode": 1.0, "color": 0.82, "amp": 0.5, "freq": 860.0, "pan": 0.24},
            "impact": {"mode": 2.0, "color": 0.68, "amp": 0.52, "freq": 280.0, "pan": 0.0},
            "enter": {"mode": 3.0, "color": 0.86, "amp": 0.36, "freq": 560.0, "pan": 0.2},
            "exit": {"mode": 2.0, "color": 0.74, "amp": 0.22, "freq": 200.0, "pan": -0.18},
            "flow": {"mode": 1.0, "color": 0.92, "amp": 0.78, "freq": 2140.0, "pan": -0.26},
        },
    },
}


ACTION_PATCHES: dict[str, dict[str, object]] = {
    "mute": {
        "body": {"core": {"amp": 0.0, "detected": False}},
        "fx": {"master": {"output": 0.72, "drive": 0.08}},
    },
    "dry": {
        "fx": {
            "delay": {"mix": 0.08, "feedback": 0.16},
            "chorus": {"mix": 0.04},
            "reverb": {"mix": 0.08, "room": 0.38},
            "master": {"width": 0.14, "tremDepth": 0.0},
        }
    },
    "wide": {
        "fx": {
            "chorus": {"mix": 0.28, "depth": 0.022},
            "reverb": {"mix": 0.3, "room": 0.82, "tone": 0.78},
            "master": {"width": 0.72, "output": 0.82},
        }
    },
    "storm": {
        "body": {
            "core": {"amp": 0.46, "cutoff": 3600.0, "detected": True},
            "voice": {"mode": 3.0, "texture": 0.76, "noiseMix": 0.34, "motion": 0.92, "resonance": 0.4},
        },
        "fx": {
            "delay": {"time": 0.44, "feedback": 0.52, "mix": 0.4, "tone": 0.8},
            "chorus": {"mix": 0.26, "rate": 0.38, "depth": 0.024},
            "reverb": {"mix": 0.34, "room": 0.92, "damp": 0.24, "tone": 0.88},
            "master": {"drive": 0.22, "width": 0.58, "tremRate": 0.24, "tremDepth": 0.18, "output": 0.76},
        },
        "triggers": {
            "flow": {"mode": 1.0, "color": 0.92, "amp": 0.82, "freq": 1980.0},
            "impact": {"mode": 2.0, "color": 0.68, "amp": 0.7, "freq": 260.0},
        },
    },
}


AVAILABLE_ACTIONS = ["reset", "mute", "dry", "wide", "storm", "random-soft", "random-bold"]


TRIGGER_ADDRESS = {
    "onset": "/trigger/motion_onset",
    "impact": "/trigger/impact",
    "enter": "/trigger/person_enter",
    "exit": "/trigger/person_exit",
    "flow": "/trigger/flow_burst",
}


def deep_merge(target: dict[str, object], patch: dict[str, object]) -> None:
    for key, value in patch.items():
        if isinstance(value, dict) and isinstance(target.get(key), dict):
            deep_merge(target[key], value)  # type: ignore[index]
        else:
            target[key] = value


class ControlBridge:
    def __init__(self, sc_host: str, sc_port: int) -> None:
        self.client = SimpleUDPClient(sc_host, sc_port)
        self.lock = threading.Lock()
        self.state = copy.deepcopy(DEFAULT_STATE)

    def snapshot(self) -> dict[str, object]:
        with self.lock:
            return copy.deepcopy(self.state)

    def replace_state(self, next_state: dict[str, object]) -> dict[str, object]:
        with self.lock:
            self.state = copy.deepcopy(next_state)
            state = copy.deepcopy(self.state)
        self._emit_full_state(state)
        return state

    def apply_patch(self, patch: dict[str, object]) -> dict[str, object]:
        with self.lock:
            deep_merge(self.state, patch)
            state = copy.deepcopy(self.state)
        self._emit_full_state(state)
        return state

    def recall_preset(self, name: str) -> dict[str, object]:
        if name not in PRESETS:
            raise KeyError(name)
        return self.apply_patch(copy.deepcopy(PRESETS[name]))

    def perform_action(self, name: str) -> dict[str, object]:
        if name == "reset":
            return self.replace_state(copy.deepcopy(DEFAULT_STATE))
        if name == "random-soft":
            return self._randomize(0.18)
        if name == "random-bold":
            return self._randomize(0.42)
        if name in ACTION_PATCHES:
            return self.apply_patch(copy.deepcopy(ACTION_PATCHES[name]))
        raise KeyError(name)

    def fire_trigger(self, name: str, overrides: dict[str, object] | None = None) -> dict[str, object]:
        state = self.snapshot()
        triggers = state["triggers"]  # type: ignore[index]
        if name not in triggers:
            raise KeyError(name)
        payload = copy.deepcopy(triggers[name])  # type: ignore[index]
        if overrides:
            deep_merge(payload, overrides)
        self._send_pairs(
            TRIGGER_ADDRESS[name],
            {
                "amp": payload["amp"],
                "freq": payload["freq"],
                "pan": payload["pan"],
                "mode": payload["mode"],
                "color": payload["color"],
            },
        )
        return state

    def _randomize(self, intensity: float) -> dict[str, object]:
        rng = random.Random()
        state = self.snapshot()
        body = state["body"]  # type: ignore[index]
        fx = state["fx"]  # type: ignore[index]
        triggers = state["triggers"]  # type: ignore[index]
        patch = {
            "body": {
                "core": {
                    "freq": self._jitter(rng, body["core"]["freq"], 70.0, 520.0, intensity),  # type: ignore[index]
                    "amp": self._jitter(rng, body["core"]["amp"], 0.08, 0.56, intensity),  # type: ignore[index]
                    "cutoff": self._jitter(rng, body["core"]["cutoff"], 220.0, 6400.0, intensity),  # type: ignore[index]
                    "pan": self._jitter(rng, body["core"]["pan"], -1.0, 1.0, intensity),  # type: ignore[index]
                    "detected": True,
                },
                "voice": {
                    "mode": float(self._mode_variant(rng, body["voice"]["mode"], intensity)),  # type: ignore[index]
                    "texture": self._jitter(rng, body["voice"]["texture"], 0.05, 0.95, intensity),  # type: ignore[index]
                    "noiseMix": self._jitter(rng, body["voice"]["noiseMix"], 0.0, 0.45, intensity),  # type: ignore[index]
                    "subMix": self._jitter(rng, body["voice"]["subMix"], 0.1, 0.86, intensity),  # type: ignore[index]
                    "motion": self._jitter(rng, body["voice"]["motion"], 0.02, 0.96, intensity),  # type: ignore[index]
                    "resonance": self._jitter(rng, body["voice"]["resonance"], 0.08, 0.82, intensity),  # type: ignore[index]
                },
            },
            "fx": {
                "delay": {
                    "time": self._jitter(rng, fx["delay"]["time"], 0.04, 0.64, intensity),  # type: ignore[index]
                    "feedback": self._jitter(rng, fx["delay"]["feedback"], 0.08, 0.72, intensity),  # type: ignore[index]
                    "mix": self._jitter(rng, fx["delay"]["mix"], 0.04, 0.56, intensity),  # type: ignore[index]
                    "tone": self._jitter(rng, fx["delay"]["tone"], 0.16, 0.9, intensity),  # type: ignore[index]
                },
                "chorus": {
                    "mix": self._jitter(rng, fx["chorus"]["mix"], 0.0, 0.42, intensity),  # type: ignore[index]
                    "rate": self._jitter(rng, fx["chorus"]["rate"], 0.04, 0.82, intensity),  # type: ignore[index]
                    "depth": self._jitter(rng, fx["chorus"]["depth"], 0.002, 0.03, intensity),  # type: ignore[index]
                },
                "reverb": {
                    "mix": self._jitter(rng, fx["reverb"]["mix"], 0.04, 0.42, intensity),  # type: ignore[index]
                    "room": self._jitter(rng, fx["reverb"]["room"], 0.32, 0.96, intensity),  # type: ignore[index]
                    "damp": self._jitter(rng, fx["reverb"]["damp"], 0.12, 0.72, intensity),  # type: ignore[index]
                    "tone": self._jitter(rng, fx["reverb"]["tone"], 0.24, 0.92, intensity),  # type: ignore[index]
                },
                "master": {
                    "drive": self._jitter(rng, fx["master"]["drive"], 0.02, 0.46, intensity),  # type: ignore[index]
                    "width": self._jitter(rng, fx["master"]["width"], 0.0, 0.82, intensity),  # type: ignore[index]
                    "tremRate": self._jitter(rng, fx["master"]["tremRate"], 0.0, 0.8, intensity),  # type: ignore[index]
                    "tremDepth": self._jitter(rng, fx["master"]["tremDepth"], 0.0, 0.28, intensity),  # type: ignore[index]
                    "output": self._jitter(rng, fx["master"]["output"], 0.68, 0.96, intensity),  # type: ignore[index]
                },
            },
            "triggers": {},
        }
        for name, values in triggers.items():  # type: ignore[assignment]
            patch["triggers"][name] = {
                "mode": float(self._mode_variant(rng, values["mode"], intensity)),
                "color": self._jitter(rng, values["color"], 0.08, 0.96, intensity),
                "amp": self._jitter(rng, values["amp"], 0.16, 0.94, intensity),
                "freq": self._jitter(rng, values["freq"], 80.0, 2200.0, intensity),
                "pan": self._jitter(rng, values["pan"], -1.0, 1.0, intensity),
            }
        return self.apply_patch(patch)

    @staticmethod
    def _jitter(rng: random.Random, current: object, minimum: float, maximum: float, intensity: float) -> float:
        current_value = float(current)
        span = maximum - minimum
        next_value = current_value + rng.uniform(-span * intensity, span * intensity)
        return round(max(minimum, min(maximum, next_value)), 4)

    @staticmethod
    def _mode_variant(rng: random.Random, current: object, intensity: float) -> int:
        spread = 1 if intensity < 0.25 else 3
        next_mode = int(float(current)) + rng.randint(-spread, spread)
        return max(0, min(3, next_mode))

    def _emit_full_state(self, state: dict[str, object]) -> None:
        body = state["body"]  # type: ignore[index]
        body_core = body["core"]  # type: ignore[index]
        body_voice = body["voice"]  # type: ignore[index]
        fx = state["fx"]  # type: ignore[index]
        triggers = state["triggers"]  # type: ignore[index]

        self._send_pairs(
            "/synth/body",
            {
                "freq": body_core["freq"],
                "amp": body_core["amp"],
                "cutoff": body_core["cutoff"],
                "pan": body_core["pan"],
            },
        )
        self._send("/vrb/meta/detected", [1 if body_core["detected"] else 0])
        self._send_pairs("/ui/body", body_voice)
        self._send_pairs("/ui/fx/delay", fx["delay"])  # type: ignore[index]
        self._send_pairs("/ui/fx/chorus", fx["chorus"])  # type: ignore[index]
        self._send_pairs("/ui/fx/reverb", fx["reverb"])  # type: ignore[index]
        self._send_pairs("/ui/master", fx["master"])  # type: ignore[index]
        self._send_pairs("/ui/trigger/onset", self._pick_trigger_voice(triggers["onset"]))  # type: ignore[index]
        self._send_pairs("/ui/trigger/impact", self._pick_trigger_voice(triggers["impact"]))  # type: ignore[index]
        self._send_pairs("/ui/trigger/enter", self._pick_trigger_voice(triggers["enter"]))  # type: ignore[index]
        self._send_pairs("/ui/trigger/exit", self._pick_trigger_voice(triggers["exit"]))  # type: ignore[index]
        self._send_pairs("/ui/trigger/flow", self._pick_trigger_voice(triggers["flow"]))  # type: ignore[index]

    @staticmethod
    def _pick_trigger_voice(trigger_state: dict[str, object]) -> dict[str, object]:
        return {
            "mode": trigger_state["mode"],
            "color": trigger_state["color"],
        }

    def _send(self, address: str, values: list[float | int | str]) -> None:
        self.client.send_message(address, values)

    def _send_pairs(self, address: str, values: dict[str, object]) -> None:
        payload: list[float | int | str] = []
        for key, value in values.items():
            payload.append(key)
            payload.append(value)  # type: ignore[arg-type]
        self._send(address, payload)


class ControlHandler(SimpleHTTPRequestHandler):
    bridge: ControlBridge

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(WEBUI_DIR), **kwargs)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/api/state":
            self._write_json({"state": self.bridge.snapshot()})
            return
        if parsed.path == "/api/presets":
            self._write_json({"presets": sorted(PRESETS.keys())})
            return
        if parsed.path == "/api/actions":
            self._write_json({"actions": AVAILABLE_ACTIONS})
            return
        if parsed.path == "/":
            self.path = "/index.html"
        super().do_GET()

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        body = self._read_json_body()
        if parsed.path == "/api/state":
            state = self.bridge.apply_patch(body)
            self._write_json({"state": state})
            return
        if parsed.path.startswith("/api/preset/"):
            preset_name = parsed.path.rsplit("/", 1)[-1]
            try:
                state = self.bridge.recall_preset(preset_name)
            except KeyError:
                self.send_error(HTTPStatus.NOT_FOUND, f"Unknown preset: {preset_name}")
                return
            self._write_json({"state": state, "preset": preset_name})
            return
        if parsed.path.startswith("/api/action/"):
            action_name = parsed.path.rsplit("/", 1)[-1]
            try:
                state = self.bridge.perform_action(action_name)
            except KeyError:
                self.send_error(HTTPStatus.NOT_FOUND, f"Unknown action: {action_name}")
                return
            self._write_json({"state": state, "action": action_name})
            return
        if parsed.path.startswith("/api/trigger/"):
            trigger_name = parsed.path.rsplit("/", 1)[-1]
            try:
                state = self.bridge.fire_trigger(trigger_name, body if body else None)
            except KeyError:
                self.send_error(HTTPStatus.NOT_FOUND, f"Unknown trigger: {trigger_name}")
                return
            self._write_json({"state": state, "trigger": trigger_name})
            return
        self.send_error(HTTPStatus.NOT_FOUND, "Unknown endpoint")

    def log_message(self, format: str, *args) -> None:  # noqa: A003
        super().log_message(format, *args)

    def _read_json_body(self) -> dict[str, object]:
        content_length = int(self.headers.get("Content-Length", "0"))
        if content_length == 0:
            return {}
        raw = self.rfile.read(content_length)
        if not raw:
            return {}
        return json.loads(raw.decode("utf-8"))

    def _write_json(self, payload: dict[str, object], status: int = HTTPStatus.OK) -> None:
        encoded = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Serve a WebUI for SuperCollider control")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--sc-host", default="127.0.0.1")
    parser.add_argument("--sc-port", type=int, default=57120)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    bridge = ControlBridge(args.sc_host, args.sc_port)
    bridge.apply_patch({})

    handler = type("BoundControlHandler", (ControlHandler,), {"bridge": bridge})
    server = ThreadingHTTPServer((args.host, args.port), handler)
    print(f"sc-control-server listening on http://{args.host}:{args.port} -> {args.sc_host}:{args.sc_port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
