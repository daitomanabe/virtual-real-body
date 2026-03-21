from __future__ import annotations

import copy
import json
import threading
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_ASSETS_DIR = ROOT.parent / "assets"
SESSION_STATE_PATH = ROOT / "runtime" / "session_state.json"
VIDEO_EXTENSIONS = {".mov", ".mp4", ".m4v", ".avi", ".mkv"}
DEFAULT_CAMERA_INDICES = tuple(range(6))

DEFAULT_SESSION_STATE: dict[str, object] = {
    "source": {
        "mode": "camera",
        "camera_index": 0,
        "video_file": "",
        "loop": True,
    },
    "display": {
        "overlay_window": "separate",
        "target_screen": "main",
        "fullscreen": False,
    },
}


def deep_merge(target: dict[str, object], patch: dict[str, object]) -> None:
    for key, value in patch.items():
        if isinstance(value, dict) and isinstance(target.get(key), dict):
            deep_merge(target[key], value)  # type: ignore[index]
        else:
            target[key] = value


def clone_default_session_state() -> dict[str, object]:
    return copy.deepcopy(DEFAULT_SESSION_STATE)


def normalise_session_state(state: dict[str, object] | None) -> dict[str, object]:
    merged = clone_default_session_state()
    if state:
        deep_merge(merged, state)

    source = merged["source"]  # type: ignore[index]
    source["mode"] = "video" if str(source.get("mode", "camera")).lower() == "video" else "camera"
    source["camera_index"] = max(int(source.get("camera_index", 0) or 0), 0)
    source["video_file"] = str(source.get("video_file", "") or "")
    source["loop"] = bool(source.get("loop", True))

    display = merged["display"]  # type: ignore[index]
    display["overlay_window"] = "separate"
    display["target_screen"] = (
        "main" if str(display.get("target_screen", "external_preferred")).lower() == "main" else "external_preferred"
    )
    display["fullscreen"] = bool(display.get("fullscreen", True))
    return merged


def ensure_session_state_file(path: Path = SESSION_STATE_PATH) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        path.write_text(json.dumps(clone_default_session_state(), indent=2), encoding="utf-8")
    return path


def load_session_state(path: Path = SESSION_STATE_PATH) -> dict[str, object]:
    ensure_session_state_file(path)
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        raw = clone_default_session_state()
    if not isinstance(raw, dict):
        raw = clone_default_session_state()
    state = normalise_session_state(raw)
    path.write_text(json.dumps(state, indent=2), encoding="utf-8")
    return state


def media_catalog(assets_dir: Path = DEFAULT_ASSETS_DIR) -> dict[str, object]:
    videos = []
    if assets_dir.exists():
        for path in sorted(assets_dir.iterdir()):
            if path.suffix.lower() not in VIDEO_EXTENSIONS or not path.is_file():
                continue
            videos.append({"label": path.name, "path": str(path.resolve())})
    cameras = [{"label": f"Device {index}", "index": index} for index in DEFAULT_CAMERA_INDICES]
    return {"assets_dir": str(assets_dir.resolve()), "videos": videos, "cameras": cameras}


class RuntimeSessionStore:
    def __init__(self, path: Path = SESSION_STATE_PATH, assets_dir: Path = DEFAULT_ASSETS_DIR) -> None:
        self.path = path
        self.assets_dir = assets_dir
        self._lock = threading.Lock()
        self._state = load_session_state(self.path)

    def snapshot(self) -> dict[str, object]:
        with self._lock:
            return copy.deepcopy(self._state)

    def apply_patch(self, patch: dict[str, Any]) -> dict[str, object]:
        with self._lock:
            next_state = copy.deepcopy(self._state)
            deep_merge(next_state, patch)
            self._state = normalise_session_state(next_state)
            ensure_session_state_file(self.path)
            self.path.write_text(json.dumps(self._state, indent=2), encoding="utf-8")
            return copy.deepcopy(self._state)

    def payload(self) -> dict[str, object]:
        return {
            "session": self.snapshot(),
            "media": media_catalog(self.assets_dir),
            "session_file": str(self.path.resolve()),
        }
