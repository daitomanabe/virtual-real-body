from __future__ import annotations

import argparse
import colorsys
import json
import math
import subprocess
import sys
import wave
import zlib
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import cv2
import numpy as np


ROOT = Path(__file__).resolve().parents[2]
PYTHON_ROOT = ROOT / "python"
if str(PYTHON_ROOT) not in sys.path:
    sys.path.insert(0, str(PYTHON_ROOT))

from analyzers import (  # noqa: E402
    DepthAnalyzer,
    EventAnalyzer,
    MediaPipeAnalyzer,
    OpticalFlowAnalyzer,
    ParticleAnalyzer,
    SparseFlowAnalyzer,
    YOLODetectAnalyzer,
    YOLOPoseAnalyzer,
    YOLOSegAnalyzer,
)
from core.analyzer_base import AnalysisResult  # noqa: E402


COCO_EDGES = [
    (0, 1),
    (0, 2),
    (1, 3),
    (2, 4),
    (5, 6),
    (5, 7),
    (7, 9),
    (6, 8),
    (8, 10),
    (5, 11),
    (6, 12),
    (11, 12),
    (11, 13),
    (13, 15),
    (12, 14),
    (14, 16),
]


@dataclass(frozen=True)
class VisualFamily:
    slug: str
    label: str
    base_hue: float
    tint: float
    edge_mix: float
    seg_alpha: float
    trail_decay: float
    ghost_mix: float
    scanlines: float
    mirror_mix: float
    posterize_levels: int
    flow_gain: float
    particle_gain: float


@dataclass(frozen=True)
class AudioPreset:
    slug: str
    label: str
    hue_shift: float
    oscillator: str
    base_gain: float
    sub_mix: float
    noise_mix: float
    fm_ratio: float
    fm_index: float
    shimmer_mix: float
    delay_mix: float
    delay_time: float
    reverb_mix: float
    width: float
    event_gain: float
    texture_mode: str
    lowpass_hz: float
    highpass_hz: float
    drive: float
    ring_mix: float
    crush_mix: float
    chorus_mix: float
    tremolo_rate: float
    event_mode: str


@dataclass(frozen=True)
class Variant:
    slug: str
    label: str
    visual: VisualFamily
    audio: AudioPreset
    palette: dict[str, tuple[int, int, int]]


@dataclass
class FrameAnalysis:
    frame_id: int
    source_bgr: np.ndarray
    detect: AnalysisResult
    pose: AnalysisResult
    seg: AnalysisResult
    flow: AnalysisResult
    sparse: AnalysisResult
    mediapipe: AnalysisResult
    depth: AnalysisResult
    event: AnalysisResult
    particle: AnalysisResult


@dataclass
class VideoAnalysis:
    source_path: Path
    fps: float
    size: tuple[int, int]
    frames: list[FrameAnalysis]


VISUAL_FAMILIES = [
    VisualFamily("neon-skeleton", "Neon Skeleton", 0.47, 0.18, 0.34, 0.18, 0.84, 0.18, 0.0, 0.0, 6, 1.0, 0.9),
    VisualFamily("liquid-depth", "Liquid Depth", 0.57, 0.26, 0.18, 0.28, 0.9, 0.28, 0.0, 0.0, 8, 0.55, 0.65),
    VisualFamily("particle-ribbon", "Particle Ribbon", 0.83, 0.1, 0.12, 0.12, 0.93, 0.12, 0.0, 0.0, 10, 0.8, 1.45),
    VisualFamily("contour-heat", "Contour Heat", 0.06, 0.22, 0.48, 0.2, 0.88, 0.14, 0.0, 0.0, 4, 0.7, 0.75),
    VisualFamily("ritual-grid", "Ritual Grid", 0.11, 0.16, 0.24, 0.16, 0.8, 0.22, 0.18, 0.38, 5, 0.7, 0.55),
    VisualFamily("spectral-window", "Spectral Window", 0.68, 0.14, 0.2, 0.22, 0.86, 0.32, 0.0, 0.18, 7, 0.95, 0.95),
]


AUDIO_PRESETS = [
    AudioPreset("glass-cavern", "Glass Cavern", 0.02, "fm", 0.16, 0.2, 0.08, 2.1, 2.8, 0.22, 0.28, 0.26, 0.24, 0.36, 0.82, "glass", 9800.0, 110.0, 0.12, 0.22, 0.0, 0.08, 0.21, "glass"),
    AudioPreset("machine-ritual", "Machine Ritual", -0.04, "pulse", 0.22, 0.48, 0.04, 1.0, 0.0, 0.04, 0.14, 0.18, 0.1, 0.14, 0.96, "pulsebed", 5400.0, 90.0, 0.28, 0.34, 0.08, 0.02, 0.36, "pulse"),
    AudioPreset("tidal-halo", "Tidal Halo", 0.09, "sine", 0.14, 0.12, 0.12, 1.6, 1.4, 0.26, 0.34, 0.34, 0.28, 0.52, 0.74, "halo", 7600.0, 70.0, 0.08, 0.12, 0.0, 0.16, 0.14, "halo"),
    AudioPreset("ember-choir", "Ember Choir", -0.01, "tri", 0.18, 0.26, 0.06, 1.5, 1.2, 0.18, 0.18, 0.22, 0.18, 0.3, 0.88, "choir", 6200.0, 120.0, 0.18, 0.08, 0.0, 0.1, 0.18, "choir"),
    AudioPreset("submerged-brass", "Submerged Brass", -0.08, "saw", 0.21, 0.42, 0.03, 1.25, 0.8, 0.06, 0.12, 0.16, 0.1, 0.18, 0.92, "brass", 3800.0, 60.0, 0.24, 0.16, 0.0, 0.04, 0.12, "brass"),
    AudioPreset("shattered-lattice", "Shattered Lattice", 0.14, "blend", 0.15, 0.08, 0.16, 2.8, 3.2, 0.3, 0.3, 0.3, 0.26, 0.58, 0.78, "glitch", 11200.0, 180.0, 0.34, 0.42, 0.28, 0.12, 0.42, "shard"),
]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Generate preview video variants from a source performance clip")
    parser.add_argument(
        "--video-file",
        default="/Users/daitomacm5/development/sandbox/assets/IMG_6770.mov",
        help="Source video file for concept previews",
    )
    parser.add_argument(
        "--output-dir",
        default=str(ROOT / "outputs" / "preview-batches" / "img_6770_batch"),
        help="Directory for rendered previews and gallery",
    )
    parser.add_argument("--width", type=int, default=640, help="Preview render width")
    parser.add_argument("--sample-rate", type=int, default=44100, help="Audio sample rate")
    parser.add_argument("--max-variants", type=int, default=0, help="Optional cap for quick testing")
    parser.add_argument("--max-frames", type=int, default=0, help="Optional frame cap for quick testing")
    parser.add_argument("--fps", type=float, default=0.0, help="Override render fps")
    return parser


def build_variant_matrix() -> list[Variant]:
    variants: list[Variant] = []
    for visual in VISUAL_FAMILIES:
        for audio in AUDIO_PRESETS:
            slug = f"{visual.slug}__{audio.slug}"
            label = f"{visual.label} / {audio.label}"
            variants.append(Variant(slug, label, visual, audio, build_palette(visual, audio)))
    return variants


def build_palette(visual: VisualFamily, audio: AudioPreset) -> dict[str, tuple[int, int, int]]:
    hue = (visual.base_hue + audio.hue_shift) % 1.0
    accent = hsv_to_bgr(hue, 0.82, 1.0)
    secondary = hsv_to_bgr((hue + 0.08) % 1.0, 0.65, 0.92)
    tertiary = hsv_to_bgr((hue + 0.46) % 1.0, 0.28, 0.86)
    ink = hsv_to_bgr(hue, 0.25, 0.12)
    highlight = hsv_to_bgr((hue + 0.56) % 1.0, 0.42, 0.98)
    return {
        "accent": accent,
        "secondary": secondary,
        "tertiary": tertiary,
        "ink": ink,
        "highlight": highlight,
    }


def hsv_to_bgr(h: float, s: float, v: float) -> tuple[int, int, int]:
    r, g, b = colorsys.hsv_to_rgb(h, s, v)
    return int(b * 255), int(g * 255), int(r * 255)


def analyze_video(video_path: Path, width: int, max_frames: int) -> VideoAnalysis:
    capture = cv2.VideoCapture(str(video_path))
    if not capture.isOpened():
        raise RuntimeError(f"Failed to open video file: {video_path}")

    source_fps = float(capture.get(cv2.CAP_PROP_FPS) or 30.0)
    source_width = int(capture.get(cv2.CAP_PROP_FRAME_WIDTH) or 1280)
    source_height = int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT) or 720)
    render_height = ensure_even(max(2, int(round(source_height * (width / max(source_width, 1))))))
    render_size = (ensure_even(width), render_height)

    inline_analyzers = [
        YOLODetectAnalyzer(),
        YOLOPoseAnalyzer(),
        YOLOSegAnalyzer(),
        OpticalFlowAnalyzer(),
        SparseFlowAnalyzer(),
        MediaPipeAnalyzer(),
        DepthAnalyzer(),
    ]
    meta_analyzers = [EventAnalyzer(), ParticleAnalyzer()]

    frames: list[FrameAnalysis] = []
    frame_id = 0
    try:
        while True:
            ok, frame_bgr = capture.read()
            if not ok:
                break
            if max_frames > 0 and frame_id >= max_frames:
                break

            resized = cv2.resize(frame_bgr, render_size, interpolation=cv2.INTER_AREA)
            result_map: dict[str, AnalysisResult] = {}
            for analyzer in inline_analyzers:
                result = analyzer.process(resized, frame_id)
                result_map[result.analyzer] = result
                for meta in meta_analyzers:
                    for meta_result in meta.consume_sibling_result(result):
                        result_map[meta_result.analyzer] = meta_result

            frames.append(
                FrameAnalysis(
                    frame_id=frame_id,
                    source_bgr=resized,
                    detect=result_map["yolo.detect"],
                    pose=result_map["yolo.pose"],
                    seg=result_map["yolo.seg"],
                    flow=result_map["flow.dense"],
                    sparse=result_map["flow.sparse"],
                    mediapipe=result_map["mp.pose"],
                    depth=result_map["depth.map"],
                    event=result_map["event"],
                    particle=result_map["particle.state"],
                )
            )
            frame_id += 1
    finally:
        capture.release()

    if not frames:
        raise RuntimeError(f"No frames were decoded from {video_path}")
    stabilize_preview_analysis(frames)
    return VideoAnalysis(video_path, source_fps, render_size, frames)


def stabilize_preview_analysis(frames: list[FrameAnalysis]) -> None:
    tracked = track_subject_geometries([frame.source_bgr for frame in frames])
    if not tracked:
        return

    com_array = np.array([entry["com"] for entry in tracked], dtype=np.float32)
    area_array = np.array([float(entry["area"]) for entry in tracked], dtype=np.float32)
    keypoint_array = np.array([entry["keypoints"] for entry in tracked], dtype=np.float32)

    velocity_array = np.zeros_like(com_array)
    velocity_array[1:] = com_array[1:] - com_array[:-1]
    speed_array = np.linalg.norm(velocity_array, axis=1)
    area_delta = np.zeros(len(area_array), dtype=np.float32)
    area_delta[1:] = np.abs(area_array[1:] - area_array[:-1])
    pose_speed = np.clip(speed_array * 18.0 + area_delta * 10.0, 0.0, 1.0)
    flow_energy = np.clip(speed_array * 28.0 + area_delta * 16.0, 0.0, 1.0)
    depth_curve = normalize_curve(area_array)

    direction_array = np.zeros(len(frames), dtype=np.float32)
    last_direction = 0.0
    for idx in range(len(direction_array)):
        velocity = velocity_array[idx]
        if float(np.linalg.norm(velocity)) > 1e-4:
            last_direction = float(math.atan2(float(velocity[1]), float(velocity[0])))
        direction_array[idx] = last_direction

    previous_detected = False
    previous_speed = 0.0
    previous_flow = 0.0
    for idx, (frame, subject) in enumerate(zip(frames, tracked)):
        detected = bool(subject["detected"])
        com = round_point(subject["com"])
        bbox = round_box(subject["bbox"])
        keypoints = round_keypoints(subject["keypoints"], confidence=0.96)
        polygon = round_polygon(subject["polygon"])
        mp_landmarks = build_preview_landmarks(subject["keypoints"], subject["polygon"])
        velocity = keypoint_velocity(keypoint_array[idx - 1] if idx > 0 else None, keypoint_array[idx])
        sparse_vectors = build_sparse_vectors(
            keypoint_array[idx - 1] if idx > 0 else None,
            keypoint_array[idx],
            velocity_array[idx],
        )
        spawn_points = build_spawn_points(subject["keypoints"], subject["com"], float(flow_energy[idx]), float(direction_array[idx]))
        quadrants = compute_quadrants(subject["polygon"], subject["com"])

        events: list[str] = []
        current_speed = float(pose_speed[idx])
        current_flow = float(flow_energy[idx])
        accel = max(current_speed - previous_speed, 0.0)
        if detected and not previous_detected:
            events.append("person_enter")
        if not detected and previous_detected:
            events.append("person_exit")
        if current_speed > 0.16 and previous_speed <= 0.16:
            events.append("motion_onset")
        if accel > 0.18:
            events.append("impact")
        if current_flow > 0.3 and previous_flow <= 0.3:
            events.append("flow_burst")

        frame.detect.detected = detected
        frame.detect.data = {
            "detections": [
                {
                    "id": 0,
                    "cls": 0,
                    "name": "person",
                    "conf": 0.96 if detected else 0.0,
                    "bbox": bbox,
                    "cx": com[0],
                    "cy": com[1],
                    "frame_size": [frame.source_bgr.shape[1], frame.source_bgr.shape[0]],
                }
            ]
            if detected
            else []
        }

        frame.pose.detected = detected
        frame.pose.data = {
            "persons": [
                {
                    "id": 0,
                    "keypoints": keypoints,
                    "velocity": velocity,
                    "speed": round(current_speed, 4),
                    "com": com,
                    "bbox": bbox,
                }
            ]
            if detected
            else []
        }

        frame.seg.detected = detected
        frame.seg.data = {"segments": [{"id": 0, "cls": 0, "conf": 0.92, "polygon": polygon}] if detected else []}

        frame.mediapipe.detected = detected
        frame.mediapipe.data = {
            "landmarks_norm": mp_landmarks,
            "landmarks_world": [[round((point[0] - 0.5) * 2.0, 4), round((0.5 - point[1]) * 2.0, 4), 0.0] for point in mp_landmarks],
            "velocity": expand_velocity_points(velocity, len(mp_landmarks)),
            "speed_norm": round(current_speed, 4),
            "energy": round(current_flow, 4),
            "com": [com[0], com[1], round(depth_curve[idx] - 0.5, 4)],
        }

        frame.depth.detected = detected
        frame.depth.data = {
            "depth_f16": [
                [round(float(depth_curve[idx]), 4), round(float(depth_curve[idx] * 0.92), 4)],
                [round(float(depth_curve[idx] * 1.05), 4), round(float(depth_curve[idx]), 4)],
            ],
            "mean": round(float(0.28 + (1.0 - depth_curve[idx]) * 0.34), 4),
            "com_depth": round(float(depth_curve[idx]), 4),
            "range": [
                round(max(float(depth_curve[idx]) - 0.12, 0.0), 4),
                round(min(float(depth_curve[idx]) + 0.12, 1.0), 4),
            ],
        }

        frame.flow.detected = detected
        frame.flow.data = {
            "flow_f16": [
                [round(float(velocity_array[idx][0]), 4), round(float(velocity_array[idx][1]), 4)],
                [round(float(math.cos(direction_array[idx]) * current_flow), 4), round(float(math.sin(direction_array[idx]) * current_flow), 4)],
            ],
            "energy": round(current_flow, 4),
            "direction": round(float(direction_array[idx]), 4),
            "quadrants": quadrants,
        }

        frame.sparse.detected = detected
        frame.sparse.data = {
            "vectors": sparse_vectors,
            "trails": [vector["to"] for vector in sparse_vectors],
            "count": len(sparse_vectors),
        }

        frame.particle.detected = detected
        frame.particle.data = {
            "spawn_points": spawn_points,
            "attractors": [{"position": com, "weight": 1.0}],
            "emitters": [{"position": spawn_points[0] if spawn_points else com, "rate": round(4.0 + current_flow * 18.0, 4)}],
            "field": [
                [round(float(math.cos(direction_array[idx]) * current_flow), 4), round(float(math.sin(direction_array[idx]) * current_flow), 4)],
                [round(float(-math.sin(direction_array[idx]) * current_flow), 4), round(float(math.cos(direction_array[idx]) * current_flow), 4)],
            ],
        }

        frame.event.detected = detected
        frame.event.data = {
            "events": events,
            "pose_speed": round(current_speed, 4),
            "flow_energy": round(current_flow, 4),
            "com": com,
        }

        previous_detected = detected
        previous_speed = current_speed
        previous_flow = current_flow


def track_subject_geometries(frames: list[np.ndarray]) -> list[dict[str, object]]:
    if not frames:
        return []

    height, width = frames[0].shape[:2]
    bg_model = np.zeros((1, 65), dtype=np.float64)
    fg_model = np.zeros((1, 65), dtype=np.float64)
    previous_mask: np.ndarray | None = None
    previous_bbox: tuple[int, int, int, int] | None = None
    previous_frame: np.ndarray | None = None

    raw_subjects: list[dict[str, object]] = []
    for frame in frames:
        motion_mask = make_motion_mask(frame, previous_frame, previous_bbox)
        candidate_mask = grabcut_subject_mask(frame, previous_mask, previous_bbox, motion_mask, bg_model, fg_model)
        component = select_primary_component(candidate_mask, previous_bbox, width, height)
        if component is None:
            component = previous_mask.copy() if previous_mask is not None else default_subject_mask(width, height)
        geometry = geometry_from_mask(component)
        raw_subjects.append(geometry)
        previous_mask = component
        previous_bbox = geometry["bbox_px"]  # type: ignore[assignment]
        previous_frame = frame
    return smooth_subject_geometries(raw_subjects)


def make_motion_mask(
    frame_bgr: np.ndarray,
    previous_frame: np.ndarray | None,
    previous_bbox: tuple[int, int, int, int] | None,
) -> np.ndarray | None:
    if previous_frame is None:
        return None
    current_gray = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2GRAY)
    previous_gray = cv2.cvtColor(previous_frame, cv2.COLOR_BGR2GRAY)
    diff = cv2.absdiff(current_gray, previous_gray)
    _, motion = cv2.threshold(diff, 14, 255, cv2.THRESH_BINARY)
    motion = cv2.GaussianBlur(motion, (0, 0), sigmaX=1.8)
    _, motion = cv2.threshold(motion, 18, 255, cv2.THRESH_BINARY)
    if previous_bbox is not None:
        x1, y1, x2, y2 = previous_bbox
        pad_x = max(18, (x2 - x1) // 2)
        pad_y = max(18, (y2 - y1) // 2)
        focus = np.zeros_like(motion)
        x1 = max(0, x1 - pad_x)
        y1 = max(0, y1 - pad_y)
        x2 = min(motion.shape[1], x2 + pad_x)
        y2 = min(motion.shape[0], y2 + pad_y)
        focus[y1:y2, x1:x2] = 255
        motion = cv2.bitwise_and(motion, focus)
    kernel = np.ones((5, 5), dtype=np.uint8)
    motion = cv2.morphologyEx(motion, cv2.MORPH_CLOSE, kernel, iterations=1)
    motion = cv2.dilate(motion, kernel, iterations=1)
    return motion


def grabcut_subject_mask(
    frame_bgr: np.ndarray,
    previous_mask: np.ndarray | None,
    previous_bbox: tuple[int, int, int, int] | None,
    motion_mask: np.ndarray | None,
    bg_model: np.ndarray,
    fg_model: np.ndarray,
) -> np.ndarray:
    height, width = frame_bgr.shape[:2]
    mask = np.full((height, width), cv2.GC_PR_BGD, dtype=np.uint8)
    mask[:8, :] = cv2.GC_BGD
    mask[-8:, :] = cv2.GC_BGD
    mask[:, :8] = cv2.GC_BGD
    mask[:, -8:] = cv2.GC_BGD

    try:
        if previous_mask is None:
            rect = (
                int(width * 0.34),
                int(height * 0.12),
                int(width * 0.32),
                int(height * 0.74),
            )
            cv2.grabCut(frame_bgr, mask, rect, bg_model, fg_model, 3, cv2.GC_INIT_WITH_RECT)
        else:
            dilated = cv2.dilate(previous_mask, np.ones((11, 11), dtype=np.uint8), iterations=1)
            eroded = cv2.erode(previous_mask, np.ones((7, 7), dtype=np.uint8), iterations=1)
            mask[dilated > 0] = cv2.GC_PR_FGD
            mask[eroded > 0] = cv2.GC_FGD
            if previous_bbox is not None:
                x1, y1, x2, y2 = previous_bbox
                pad_x = max(16, (x2 - x1) // 3)
                pad_y = max(16, (y2 - y1) // 3)
                x1 = max(0, x1 - pad_x)
                y1 = max(0, y1 - pad_y)
                x2 = min(width, x2 + pad_x)
                y2 = min(height, y2 + pad_y)
                mask[y1:y2, x1:x2] = np.where(mask[y1:y2, x1:x2] == cv2.GC_BGD, cv2.GC_PR_BGD, mask[y1:y2, x1:x2])
            if motion_mask is not None and int(np.count_nonzero(motion_mask)) > 0:
                mask[motion_mask > 0] = cv2.GC_PR_FGD
            cv2.grabCut(frame_bgr, mask, None, bg_model, fg_model, 2, cv2.GC_INIT_WITH_MASK)
    except cv2.error:
        return previous_mask.copy() if previous_mask is not None else default_subject_mask(width, height)

    foreground = np.where((mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD), 255, 0).astype(np.uint8)
    kernel = np.ones((5, 5), dtype=np.uint8)
    foreground = cv2.morphologyEx(foreground, cv2.MORPH_OPEN, kernel, iterations=1)
    foreground = cv2.morphologyEx(foreground, cv2.MORPH_CLOSE, kernel, iterations=2)
    return cv2.medianBlur(foreground, 5)


def select_primary_component(
    mask: np.ndarray,
    previous_bbox: tuple[int, int, int, int] | None,
    width: int,
    height: int,
) -> np.ndarray | None:
    count, labels, stats, centroids = cv2.connectedComponentsWithStats(mask, connectivity=8)
    if count <= 1:
        return None

    if previous_bbox is None:
        target_x, target_y = width * 0.5, height * 0.55
    else:
        x1, y1, x2, y2 = previous_bbox
        target_x = (x1 + x2) * 0.5
        target_y = (y1 + y2) * 0.5

    best_label = 0
    best_score = -1e9
    for label in range(1, count):
        area = int(stats[label, cv2.CC_STAT_AREA])
        if area < max(220, (width * height) // 500):
            continue
        cx, cy = centroids[label]
        distance = math.hypot(float(cx - target_x), float(cy - target_y))
        score = float(area) - distance * 18.0
        if previous_bbox is not None:
            x1, y1, x2, y2 = previous_bbox
            if x1 <= cx <= x2 and y1 <= cy <= y2:
                score += 1200.0
        if score > best_score:
            best_score = score
            best_label = label

    if best_label == 0:
        return None
    component = np.where(labels == best_label, 255, 0).astype(np.uint8)
    if int(np.count_nonzero(component)) > int(width * height * 0.42):
        return None
    return component


def default_subject_mask(width: int, height: int) -> np.ndarray:
    mask = np.zeros((height, width), dtype=np.uint8)
    cv2.ellipse(
        mask,
        (width // 2, int(height * 0.56)),
        (int(width * 0.11), int(height * 0.28)),
        0,
        0,
        360,
        255,
        -1,
        cv2.LINE_AA,
    )
    return mask


def geometry_from_mask(mask: np.ndarray) -> dict[str, object]:
    height, width = mask.shape[:2]
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return fallback_geometry(width, height)

    contour = max(contours, key=cv2.contourArea)
    area = float(cv2.contourArea(contour)) / float(max(width * height, 1))
    if area <= 1e-4:
        return fallback_geometry(width, height)

    x, y, w, h = cv2.boundingRect(contour)
    bbox_px = (x, y, x + w, y + h)
    moments = cv2.moments(contour)
    if abs(moments["m00"]) > 1e-6:
        center_x = float(moments["m10"] / moments["m00"])
        center_y = float(moments["m01"] / moments["m00"])
    else:
        center_x = x + w * 0.5
        center_y = y + h * 0.5

    hull = cv2.convexHull(contour).reshape(-1, 2).astype(np.float32)
    hull = normalize_polygon_start(hull)
    polygon_px = resample_closed_polygon(hull, 24)
    keypoints = keypoints_from_mask(mask, bbox_px)

    return {
        "detected": True,
        "com": [center_x / max(width - 1, 1), center_y / max(height - 1, 1)],
        "bbox": px_box_to_norm(bbox_px, width, height),
        "bbox_px": bbox_px,
        "polygon": px_points_to_norm(polygon_px, width, height),
        "keypoints": keypoints,
        "area": area,
    }


def fallback_geometry(width: int, height: int) -> dict[str, object]:
    bbox_px = (int(width * 0.4), int(height * 0.18), int(width * 0.6), int(height * 0.88))
    polygon_px = np.array(
        [
            [bbox_px[0], bbox_px[1]],
            [bbox_px[2], bbox_px[1]],
            [bbox_px[2], bbox_px[3]],
            [bbox_px[0], bbox_px[3]],
        ],
        dtype=np.float32,
    )
    return {
        "detected": False,
        "com": [0.5, 0.55],
        "bbox": px_box_to_norm(bbox_px, width, height),
        "bbox_px": bbox_px,
        "polygon": px_points_to_norm(resample_closed_polygon(polygon_px, 24), width, height),
        "keypoints": default_keypoints(),
        "area": 0.04,
    }


def keypoints_from_mask(mask: np.ndarray, bbox_px: tuple[int, int, int, int]) -> list[list[float]]:
    height, width = mask.shape[:2]
    x1, y1, x2, y2 = bbox_px
    box_height = max(y2 - y1, 1)

    head_left, head_right = row_bounds(mask, x1, x2, y1 + int(box_height * 0.16))
    shoulder_left, shoulder_right = row_bounds(mask, x1, x2, y1 + int(box_height * 0.28))
    elbow_left, elbow_right = row_bounds(mask, x1, x2, y1 + int(box_height * 0.44))
    wrist_left, wrist_right = row_bounds(mask, x1, x2, y1 + int(box_height * 0.62))
    hip_left, hip_right = row_bounds(mask, x1, x2, y1 + int(box_height * 0.58))
    knee_left, knee_right = row_bounds(mask, x1, x2, y1 + int(box_height * 0.8))
    ankle_left, ankle_right = row_bounds(mask, x1, x2, y1 + int(box_height * 0.96))

    head_width = max(head_right - head_left, 6.0)
    head_center_x = (head_left + head_right) * 0.5
    nose = [head_center_x / max(width - 1, 1), (y1 + box_height * 0.12) / max(height - 1, 1)]
    left_eye = [(head_center_x - head_width * 0.1) / max(width - 1, 1), (y1 + box_height * 0.1) / max(height - 1, 1)]
    right_eye = [(head_center_x + head_width * 0.1) / max(width - 1, 1), (y1 + box_height * 0.1) / max(height - 1, 1)]
    left_ear = [(head_center_x - head_width * 0.22) / max(width - 1, 1), (y1 + box_height * 0.12) / max(height - 1, 1)]
    right_ear = [(head_center_x + head_width * 0.22) / max(width - 1, 1), (y1 + box_height * 0.12) / max(height - 1, 1)]

    left_shoulder, right_shoulder = inset_pair(shoulder_left, shoulder_right, y1 + box_height * 0.28, 0.12, width, height)
    left_elbow, right_elbow = inset_pair(elbow_left, elbow_right, y1 + box_height * 0.45, 0.08, width, height)
    left_wrist, right_wrist = inset_pair(wrist_left, wrist_right, y1 + box_height * 0.62, 0.03, width, height)
    left_hip, right_hip = inset_pair(hip_left, hip_right, y1 + box_height * 0.58, 0.18, width, height)
    left_knee, right_knee = inset_pair(knee_left, knee_right, y1 + box_height * 0.8, 0.28, width, height)
    left_ankle, right_ankle = inset_pair(ankle_left, ankle_right, y1 + box_height * 0.97, 0.34, width, height)

    return [
        clip_point(nose),
        clip_point(left_eye),
        clip_point(right_eye),
        clip_point(left_ear),
        clip_point(right_ear),
        left_shoulder,
        right_shoulder,
        left_elbow,
        right_elbow,
        left_wrist,
        right_wrist,
        left_hip,
        right_hip,
        left_knee,
        right_knee,
        left_ankle,
        right_ankle,
    ]


def default_keypoints() -> list[list[float]]:
    return [
        [0.5, 0.26],
        [0.48, 0.24],
        [0.52, 0.24],
        [0.46, 0.26],
        [0.54, 0.26],
        [0.44, 0.38],
        [0.56, 0.38],
        [0.42, 0.5],
        [0.58, 0.5],
        [0.4, 0.64],
        [0.6, 0.64],
        [0.46, 0.56],
        [0.54, 0.56],
        [0.46, 0.78],
        [0.54, 0.78],
        [0.46, 0.94],
        [0.54, 0.94],
    ]


def row_bounds(mask: np.ndarray, x1: int, x2: int, y: int) -> tuple[float, float]:
    height, width = mask.shape[:2]
    y1 = max(0, min(height - 1, y - 2))
    y2 = max(y1 + 1, min(height, y + 3))
    pad = max(8, (x2 - x1) // 6)
    x1 = max(0, x1 - pad)
    x2 = min(width, x2 + pad)
    band = mask[y1:y2, x1:x2]
    xs = np.where(band > 0)[1]
    if xs.size == 0:
        return float(x1), float(x2)
    return float(x1 + int(xs.min())), float(x1 + int(xs.max()))


def inset_pair(left: float, right: float, y: float, inset: float, width: int, height: int) -> tuple[list[float], list[float]]:
    span = max(right - left, 1.0)
    left_point = [float((left + span * inset) / max(width - 1, 1)), float(y / max(height - 1, 1))]
    right_point = [float((right - span * inset) / max(width - 1, 1)), float(y / max(height - 1, 1))]
    return clip_point(left_point), clip_point(right_point)


def normalize_polygon_start(points: np.ndarray) -> np.ndarray:
    if len(points) == 0:
        return points
    order = np.lexsort((points[:, 0], points[:, 1]))
    return np.roll(points, -int(order[0]), axis=0)


def resample_closed_polygon(points: np.ndarray, count: int) -> np.ndarray:
    if len(points) == 0:
        return np.zeros((count, 2), dtype=np.float32)
    if len(points) == 1:
        return np.repeat(points.astype(np.float32), count, axis=0)
    closed = np.vstack([points, points[0]])
    segment_lengths = np.linalg.norm(np.diff(closed, axis=0), axis=1)
    total_length = float(segment_lengths.sum())
    if total_length <= 1e-6:
        return np.repeat(points[:1].astype(np.float32), count, axis=0)

    samples = np.linspace(0.0, total_length, count, endpoint=False)
    result = np.zeros((count, 2), dtype=np.float32)
    cursor = 0
    accumulated = 0.0
    for index, sample in enumerate(samples):
        while cursor < len(segment_lengths) - 1 and accumulated + float(segment_lengths[cursor]) < sample:
            accumulated += float(segment_lengths[cursor])
            cursor += 1
        local = (sample - accumulated) / max(float(segment_lengths[cursor]), 1e-6)
        result[index] = closed[cursor] + (closed[cursor + 1] - closed[cursor]) * local
    return result


def px_box_to_norm(bbox_px: tuple[int, int, int, int], width: int, height: int) -> list[float]:
    x1, y1, x2, y2 = bbox_px
    return [
        float(x1 / max(width - 1, 1)),
        float(y1 / max(height - 1, 1)),
        float(x2 / max(width - 1, 1)),
        float(y2 / max(height - 1, 1)),
    ]


def px_points_to_norm(points: np.ndarray, width: int, height: int) -> list[list[float]]:
    return [[float(point[0] / max(width - 1, 1)), float(point[1] / max(height - 1, 1))] for point in points]


def smooth_subject_geometries(raw_subjects: list[dict[str, object]]) -> list[dict[str, object]]:
    com = smooth_curve(np.array([entry["com"] for entry in raw_subjects], dtype=np.float32), radius=4)
    bbox = smooth_curve(np.array([entry["bbox"] for entry in raw_subjects], dtype=np.float32), radius=4)
    polygon = smooth_curve(np.array([entry["polygon"] for entry in raw_subjects], dtype=np.float32), radius=5)
    keypoints = smooth_curve(np.array([entry["keypoints"] for entry in raw_subjects], dtype=np.float32), radius=4)
    area = smooth_curve(np.array([float(entry["area"]) for entry in raw_subjects], dtype=np.float32), radius=6)

    stabilized: list[dict[str, object]] = []
    for index, entry in enumerate(raw_subjects):
        stabilized.append(
            {
                "detected": bool(entry["detected"]),
                "com": clip_point(com[index].tolist()),
                "bbox": clip_box(bbox[index].tolist()),
                "bbox_px": entry["bbox_px"],
                "polygon": clip_points(polygon[index].tolist()),
                "keypoints": clip_points(keypoints[index].tolist()),
                "area": float(np.clip(area[index], 0.0, 1.0)),
            }
        )
    return stabilized


def smooth_curve(values: np.ndarray, radius: int) -> np.ndarray:
    if radius <= 0 or len(values) < 2:
        return values.astype(np.float32, copy=True)
    weights = np.hanning(radius * 2 + 1)
    if not np.any(weights):
        weights = np.ones(radius * 2 + 1, dtype=np.float64)
    weights = weights / weights.sum()
    pad_spec = [(radius, radius)] + [(0, 0)] * (values.ndim - 1)
    padded = np.pad(values.astype(np.float64), pad_spec, mode="edge")
    result = np.empty_like(values, dtype=np.float64)
    for index in range(len(values)):
        window = padded[index : index + len(weights)]
        result[index] = np.tensordot(weights, window, axes=(0, 0))
    return result.astype(np.float32)


def normalize_curve(values: np.ndarray) -> np.ndarray:
    if len(values) == 0:
        return values
    minimum = float(np.min(values))
    maximum = float(np.max(values))
    if maximum - minimum <= 1e-6:
        return np.full_like(values, 0.5)
    return ((values - minimum) / (maximum - minimum)).astype(np.float32)


def build_preview_landmarks(keypoints: list[list[float]], polygon: list[list[float]]) -> list[list[float]]:
    landmarks: list[list[float]] = []
    for point in keypoints:
        landmarks.append([round(float(point[0]), 4), round(float(point[1]), 4), 0.0, 0.92])
    for point in polygon:
        if len(landmarks) >= 33:
            break
        landmarks.append([round(float(point[0]), 4), round(float(point[1]), 4), 0.0, 0.84])
    while len(landmarks) < 33:
        fill = landmarks[-1] if landmarks else [0.5, 0.5, 0.0, 0.8]
        landmarks.append(list(fill))
    return landmarks[:33]


def keypoint_velocity(previous: np.ndarray | None, current: np.ndarray) -> list[list[float]]:
    if previous is None or len(previous) != len(current):
        delta = np.zeros_like(current)
    else:
        delta = current - previous
    return [[round(float(point[0]), 4), round(float(point[1]), 4)] for point in delta]


def expand_velocity_points(points: list[list[float]], count: int) -> list[list[float]]:
    if not points:
        return [[0.0, 0.0] for _ in range(count)]
    expanded = list(points)
    while len(expanded) < count:
        expanded.append(list(expanded[-1]))
    return expanded[:count]


def build_sparse_vectors(previous: np.ndarray | None, current: np.ndarray, velocity: np.ndarray) -> list[dict[str, object]]:
    anchors = [5, 6, 11, 12]
    vectors: list[dict[str, object]] = []
    for anchor in anchors:
        end = clip_point(current[anchor].tolist())
        if previous is None:
            start = clip_point([end[0] - float(velocity[0]) * 2.0, end[1] - float(velocity[1]) * 2.0])
        else:
            start = clip_point(previous[anchor].tolist())
        delta_x = end[0] - start[0]
        delta_y = end[1] - start[1]
        vectors.append(
            {
                "from": round_point(start),
                "to": round_point(end),
                "vel": [round(delta_x, 4), round(delta_y, 4)],
                "speed": round(float(math.hypot(delta_x, delta_y) * 52.0), 4),
            }
        )
    return vectors


def build_spawn_points(keypoints: list[list[float]], com: list[float], flow_energy: float, direction: float) -> list[list[float]]:
    points = [keypoints[index] for index in (0, 9, 10, 15, 16)]
    radius = 0.04 + flow_energy * 0.08
    points.append([com[0] + math.cos(direction) * radius, com[1] + math.sin(direction) * radius])
    return [round_point(clip_point(point)) for point in points]


def compute_quadrants(polygon: list[list[float]], com: list[float]) -> dict[str, float]:
    if not polygon:
        return {"tl": 0.0, "tr": 0.0, "bl": 0.0, "br": 0.0}
    counts = {"tl": 0, "tr": 0, "bl": 0, "br": 0}
    for point in polygon:
        if point[0] <= com[0] and point[1] <= com[1]:
            counts["tl"] += 1
        elif point[0] > com[0] and point[1] <= com[1]:
            counts["tr"] += 1
        elif point[0] <= com[0] and point[1] > com[1]:
            counts["bl"] += 1
        else:
            counts["br"] += 1
    total = max(sum(counts.values()), 1)
    return {key: round(value / total, 4) for key, value in counts.items()}


def round_point(point: Iterable[float]) -> list[float]:
    values = list(point)
    return [round(float(values[0]), 4), round(float(values[1]), 4)]


def round_box(box: Iterable[float]) -> list[float]:
    return [round(float(value), 4) for value in box]


def round_polygon(points: list[list[float]]) -> list[list[float]]:
    return [round_point(point) for point in points]


def round_keypoints(points: list[list[float]], confidence: float) -> list[list[float]]:
    return [[round(float(point[0]), 4), round(float(point[1]), 4), round(confidence, 4)] for point in points]


def clip_point(point: Iterable[float]) -> list[float]:
    values = list(point)
    return [float(np.clip(values[0], 0.0, 1.0)), float(np.clip(values[1], 0.0, 1.0))]


def clip_points(points: list[list[float]]) -> list[list[float]]:
    return [clip_point(point) for point in points]


def clip_box(box: list[float]) -> list[float]:
    x1, y1, x2, y2 = [float(np.clip(value, 0.0, 1.0)) for value in box]
    return [min(x1, x2), min(y1, y2), max(x1, x2), max(y1, y2)]


def ensure_even(value: int) -> int:
    return value if value % 2 == 0 else value + 1


def render_variant_set(video: VideoAnalysis, variants: Iterable[Variant], output_dir: Path, sample_rate: int, fps: float) -> list[dict[str, object]]:
    output_dir.mkdir(parents=True, exist_ok=True)
    videos_dir = output_dir / "videos"
    posters_dir = output_dir / "posters"
    videos_dir.mkdir(parents=True, exist_ok=True)
    posters_dir.mkdir(parents=True, exist_ok=True)

    manifest: list[dict[str, object]] = []
    variant_list = list(variants)
    for index, variant in enumerate(variant_list, start=1):
        print(f"[preview-batch] rendering {index}/{len(variant_list)}: {variant.slug}", flush=True)
        entry = render_single_variant(video, variant, videos_dir, posters_dir, sample_rate, fps, index)
        manifest.append(entry)

    manifest_path = output_dir / "manifest.json"
    manifest_path.write_text(json.dumps({"source": str(video.source_path), "variants": manifest}, indent=2), encoding="utf-8")
    gallery_path = output_dir / "index.html"
    gallery_path.write_text(build_gallery_html(video, manifest), encoding="utf-8")
    return manifest


def render_single_variant(
    video: VideoAnalysis,
    variant: Variant,
    videos_dir: Path,
    posters_dir: Path,
    sample_rate: int,
    fps: float,
    ordinal: int,
) -> dict[str, object]:
    video_temp = videos_dir / f"{variant.slug}.silent.mp4"
    audio_path = videos_dir / f"{variant.slug}.wav"
    final_path = videos_dir / f"{ordinal:02d}_{variant.slug}.mp4"
    poster_path = posters_dir / f"{ordinal:02d}_{variant.slug}.png"

    writer = open_writer(video_temp, video.size, fps)
    trail_layer = np.zeros((video.size[1], video.size[0], 3), dtype=np.float32)
    ghost_layer = np.zeros_like(trail_layer)
    mid_index = len(video.frames) // 2

    for idx, frame in enumerate(video.frames):
        rendered = render_frame(frame, variant, trail_layer, ghost_layer)
        writer.write(rendered)
        if idx == mid_index:
            cv2.imwrite(str(poster_path), rendered)
    writer.release()

    audio = synthesize_audio(video, variant, sample_rate, fps)
    write_wav(audio_path, audio, sample_rate)
    mux_video_audio(video_temp, audio_path, final_path)
    video_temp.unlink(missing_ok=True)
    audio_path.unlink(missing_ok=True)

    return {
        "ordinal": ordinal,
        "slug": variant.slug,
        "label": variant.label,
        "visual_family": variant.visual.label,
        "audio_preset": variant.audio.label,
        "video": f"videos/{final_path.name}",
        "poster": f"posters/{poster_path.name}",
    }


def open_writer(path: Path, size: tuple[int, int], fps: float) -> cv2.VideoWriter:
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(str(path), fourcc, fps, size)
    if not writer.isOpened():
        raise RuntimeError(f"Failed to open video writer for {path}")
    return writer


def render_frame(frame: FrameAnalysis, variant: Variant, trail_layer: np.ndarray, ghost_layer: np.ndarray) -> np.ndarray:
    source = frame.source_bgr
    height, width = source.shape[:2]
    palette = variant.palette

    base = apply_base_treatment(source, variant)
    ghost_layer[:] = ghost_layer * (1.0 - variant.visual.ghost_mix * 0.04) + source.astype(np.float32) * (variant.visual.ghost_mix * 0.04)
    trail_layer[:] *= variant.visual.trail_decay

    overlay = np.zeros_like(source)
    glow = np.zeros_like(source)
    trail_stamp = np.zeros_like(source)

    pose_person = frame.pose.data.get("persons", [{}])[0]
    com = pose_person.get("com", [0.5, 0.5])
    bbox = pose_person.get("bbox", [0.3, 0.2, 0.7, 0.9])
    keypoints = pose_person.get("keypoints", [])
    mp_landmarks = frame.mediapipe.data.get("landmarks_norm", [])
    polygon = frame.seg.data.get("segments", [{}])[0].get("polygon", [])
    sparse_vectors = frame.sparse.data.get("vectors", [])
    spawn_points = frame.particle.data.get("spawn_points", [])
    depth_com = float(frame.depth.data.get("com_depth", 0.5))
    flow_energy = float(frame.flow.data.get("energy", 0.0))
    events = frame.event.data.get("events", [])

    com_px = norm_to_px(com, width, height)
    bbox_px = bbox_to_px(bbox, width, height)
    polygon_px = np.array([norm_to_px(point, width, height) for point in polygon], dtype=np.int32) if polygon else np.empty((0, 2), dtype=np.int32)
    keypoint_px = [norm_to_px(point[:2], width, height) for point in keypoints]
    mp_px = [norm_to_px(point[:2], width, height) for point in mp_landmarks]

    if polygon_px.size > 0:
        fill_polygon(base, polygon_px, palette["secondary"], variant.visual.seg_alpha)
        cv2.polylines(glow, [polygon_px], True, palette["accent"], 2, cv2.LINE_AA)

    draw_bbox(overlay, bbox_px, palette["highlight"], 2)
    draw_skeleton(glow, keypoint_px, palette["accent"], 3)
    draw_skeleton(overlay, keypoint_px, palette["highlight"], 1)
    draw_points(overlay, keypoint_px, palette["secondary"], 3)
    draw_points(glow, mp_px[::2], palette["tertiary"], 2)
    draw_sparse_flow(glow, sparse_vectors, width, height, palette["accent"], variant.visual.flow_gain)
    draw_particles(trail_stamp, spawn_points, width, height, palette["highlight"], variant.visual.particle_gain)

    if variant.visual.slug == "neon-skeleton":
        edge_mix(base, source, palette["accent"], variant.visual.edge_mix)
        add_orbit_rings(glow, com_px, depth_com, palette["highlight"])
    elif variant.visual.slug == "liquid-depth":
        apply_depth_gradient(base, depth_com, palette)
        add_depth_contours(glow, com_px, depth_com, palette["accent"])
        base[:] = cv2.GaussianBlur(base, (0, 0), sigmaX=3.2)
    elif variant.visual.slug == "particle-ribbon":
        base[:] = desaturate(base, 0.68)
        draw_particle_ribbons(trail_stamp, spawn_points, com_px, width, height, palette["accent"])
        base[:] = posterize(base, variant.visual.posterize_levels)
    elif variant.visual.slug == "contour-heat":
        edge_mix(base, source, palette["highlight"], variant.visual.edge_mix * 1.4)
        base[:] = posterize(base, variant.visual.posterize_levels)
        add_heat_pulses(glow, keypoint_px, flow_energy, palette["accent"])
    elif variant.visual.slug == "ritual-grid":
        base[:] = mirror_frame(base, variant.visual.mirror_mix)
        draw_grid(overlay, width, height, palette["secondary"])
        draw_event_labels(overlay, events, palette["accent"])
    elif variant.visual.slug == "spectral-window":
        base[:] = chroma_split(base)
        add_radial_burst(glow, com_px, flow_energy, palette["highlight"])
        draw_prism_segments(glow, polygon_px, palette["tertiary"])

    if events:
        add_event_flash(glow, com_px, palette["accent"], len(events))

    trail_layer[:] = np.clip(trail_layer + trail_stamp.astype(np.float32), 0.0, 255.0)
    trail_img = np.clip(trail_layer, 0.0, 255.0).astype(np.uint8)
    glow_blurred = cv2.GaussianBlur(glow, (0, 0), sigmaX=9.5)
    ghost_img = np.clip(ghost_layer, 0.0, 255.0).astype(np.uint8)

    composed = cv2.addWeighted(base, 1.0, ghost_img, variant.visual.ghost_mix * 0.32, 0)
    composed = cv2.addWeighted(composed, 1.0, glow_blurred, 0.78, 0)
    composed = cv2.addWeighted(composed, 1.0, trail_img, 0.72, 0)
    composed = cv2.addWeighted(composed, 1.0, overlay, 0.9, 0)
    if variant.visual.scanlines > 0.0:
        composed = add_scanlines(composed, variant.visual.scanlines, palette["ink"])

    draw_variant_title(composed, variant, frame.frame_id)
    return composed


def apply_base_treatment(source: np.ndarray, variant: Variant) -> np.ndarray:
    base = source.astype(np.float32)
    tint_color = np.array(variant.palette["ink"], dtype=np.float32)
    base = base * (0.72 - variant.visual.tint * 0.2) + tint_color * variant.visual.tint
    base = np.clip(base, 0.0, 255.0)
    if variant.visual.posterize_levels > 0:
        base = posterize(base.astype(np.uint8), max(3, variant.visual.posterize_levels + 2)).astype(np.float32)
    return base.astype(np.uint8)


def edge_mix(base: np.ndarray, source: np.ndarray, color: tuple[int, int, int], amount: float) -> None:
    edges = cv2.Canny(cv2.cvtColor(source, cv2.COLOR_BGR2GRAY), 80, 160)
    colored = np.zeros_like(base)
    colored[edges > 0] = color
    mixed = cv2.addWeighted(base, 1.0, colored, amount, 0)
    base[:] = mixed


def fill_polygon(image: np.ndarray, polygon: np.ndarray, color: tuple[int, int, int], alpha: float) -> None:
    mask = np.zeros(image.shape[:2], dtype=np.uint8)
    cv2.fillPoly(mask, [polygon], 255)
    overlay = np.zeros_like(image)
    overlay[mask > 0] = color
    mixed = cv2.addWeighted(image, 1.0, overlay, alpha, 0)
    image[:] = mixed


def draw_bbox(image: np.ndarray, bbox_px: tuple[int, int, int, int], color: tuple[int, int, int], thickness: int) -> None:
    x1, y1, x2, y2 = bbox_px
    cv2.rectangle(image, (x1, y1), (x2, y2), color, thickness, cv2.LINE_AA)


def draw_skeleton(image: np.ndarray, points: list[tuple[int, int]], color: tuple[int, int, int], thickness: int) -> None:
    for start, end in COCO_EDGES:
        if start >= len(points) or end >= len(points):
            continue
        cv2.line(image, points[start], points[end], color, thickness, cv2.LINE_AA)


def draw_points(image: np.ndarray, points: list[tuple[int, int]], color: tuple[int, int, int], radius: int) -> None:
    for point in points:
        cv2.circle(image, point, radius, color, -1, cv2.LINE_AA)


def draw_sparse_flow(image: np.ndarray, vectors: list[dict[str, object]], width: int, height: int, color: tuple[int, int, int], gain: float) -> None:
    thickness = max(1, int(round(2 * gain)))
    for vector in vectors:
        start = norm_to_px(vector.get("from", [0.5, 0.5]), width, height)
        end = norm_to_px(vector.get("to", [0.5, 0.5]), width, height)
        cv2.arrowedLine(image, start, end, color, thickness, cv2.LINE_AA, tipLength=0.25)


def draw_particles(image: np.ndarray, spawn_points: list[list[float]], width: int, height: int, color: tuple[int, int, int], gain: float) -> None:
    radius = max(2, int(round(4 * gain)))
    for point in spawn_points:
        cv2.circle(image, norm_to_px(point, width, height), radius, color, -1, cv2.LINE_AA)


def add_orbit_rings(image: np.ndarray, center: tuple[int, int], depth_com: float, color: tuple[int, int, int]) -> None:
    for idx in range(3):
        radius = int(24 + idx * 18 + depth_com * 42)
        cv2.circle(image, center, radius, color, 1, cv2.LINE_AA)


def apply_depth_gradient(image: np.ndarray, depth_com: float, palette: dict[str, tuple[int, int, int]]) -> None:
    height, width = image.shape[:2]
    gradient = np.linspace(0.0, 1.0, height, dtype=np.float32).reshape(height, 1, 1)
    top = np.array(palette["tertiary"], dtype=np.float32).reshape(1, 1, 3)
    bottom = np.array(palette["ink"], dtype=np.float32).reshape(1, 1, 3)
    blend = top * (1.0 - gradient) + bottom * gradient
    depth_mix = np.clip(0.24 + depth_com * 0.32, 0.2, 0.62)
    image[:] = np.clip(image.astype(np.float32) * (1.0 - depth_mix) + blend * depth_mix, 0.0, 255.0).astype(np.uint8)


def add_depth_contours(image: np.ndarray, center: tuple[int, int], depth_com: float, color: tuple[int, int, int]) -> None:
    for idx in range(4):
        radius = int(10 + depth_com * 120 + idx * 24)
        cv2.ellipse(image, center, (radius, max(8, radius // 3)), 0, 0, 360, color, 1, cv2.LINE_AA)


def desaturate(image: np.ndarray, amount: float) -> np.ndarray:
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    gray_bgr = cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR)
    return cv2.addWeighted(image, 1.0 - amount, gray_bgr, amount, 0)


def posterize(image: np.ndarray, levels: int) -> np.ndarray:
    levels = max(2, levels)
    step = max(1, 256 // levels)
    return ((image // step) * step + step // 2).astype(np.uint8)


def draw_particle_ribbons(image: np.ndarray, spawn_points: list[list[float]], center: tuple[int, int], width: int, height: int, color: tuple[int, int, int]) -> None:
    for point in spawn_points:
        target = norm_to_px(point, width, height)
        cv2.line(image, center, target, color, 2, cv2.LINE_AA)


def add_heat_pulses(image: np.ndarray, points: list[tuple[int, int]], energy: float, color: tuple[int, int, int]) -> None:
    radius = int(8 + energy * 26)
    for point in points[::3]:
        cv2.circle(image, point, radius, color, 1, cv2.LINE_AA)


def mirror_frame(image: np.ndarray, mirror_mix: float) -> np.ndarray:
    if mirror_mix <= 0.0:
        return image
    flipped = cv2.flip(image, 1)
    return cv2.addWeighted(image, 1.0 - mirror_mix * 0.5, flipped, mirror_mix * 0.5, 0)


def draw_grid(image: np.ndarray, width: int, height: int, color: tuple[int, int, int]) -> None:
    for x in range(0, width, max(48, width // 10)):
        cv2.line(image, (x, 0), (x, height), color, 1, cv2.LINE_AA)
    for y in range(0, height, max(48, height // 8)):
        cv2.line(image, (0, y), (width, y), color, 1, cv2.LINE_AA)


def draw_event_labels(image: np.ndarray, events: list[str], color: tuple[int, int, int]) -> None:
    if not events:
        return
    label = " + ".join(events)
    cv2.putText(image, label, (24, 64), cv2.FONT_HERSHEY_SIMPLEX, 0.72, color, 2, cv2.LINE_AA)


def chroma_split(image: np.ndarray) -> np.ndarray:
    b, g, r = cv2.split(image)
    shift_r = np.roll(r, 6, axis=1)
    shift_b = np.roll(b, -6, axis=1)
    return cv2.merge([shift_b, g, shift_r])


def add_radial_burst(image: np.ndarray, center: tuple[int, int], energy: float, color: tuple[int, int, int]) -> None:
    rays = 12
    length = int(40 + energy * 110)
    for idx in range(rays):
        angle = (idx / rays) * math.tau
        end = (
            int(center[0] + math.cos(angle) * length),
            int(center[1] + math.sin(angle) * length),
        )
        cv2.line(image, center, end, color, 1, cv2.LINE_AA)


def draw_prism_segments(image: np.ndarray, polygon: np.ndarray, color: tuple[int, int, int]) -> None:
    if polygon.size == 0:
        return
    offset = np.array([10, -8])
    shifted = polygon + offset
    cv2.polylines(image, [shifted], True, color, 2, cv2.LINE_AA)


def add_event_flash(image: np.ndarray, center: tuple[int, int], color: tuple[int, int, int], strength: int) -> None:
    radius = 26 + strength * 18
    cv2.circle(image, center, radius, color, -1, cv2.LINE_AA)


def add_scanlines(image: np.ndarray, amount: float, ink: tuple[int, int, int]) -> np.ndarray:
    height = image.shape[0]
    overlay = np.zeros_like(image)
    overlay[::3, :, :] = ink
    return cv2.addWeighted(image, 1.0, overlay, amount, 0)


def draw_variant_title(image: np.ndarray, variant: Variant, frame_id: int) -> None:
    cv2.putText(image, variant.label, (24, image.shape[0] - 42), cv2.FONT_HERSHEY_SIMPLEX, 0.62, variant.palette["highlight"], 2, cv2.LINE_AA)
    cv2.putText(image, f"{variant.slug}  frame {frame_id:04d}", (24, image.shape[0] - 18), cv2.FONT_HERSHEY_SIMPLEX, 0.44, variant.palette["secondary"], 1, cv2.LINE_AA)


def norm_to_px(point: Iterable[float], width: int, height: int) -> tuple[int, int]:
    values = list(point)
    x = int(np.clip(values[0], 0.0, 1.0) * (width - 1))
    y = int(np.clip(values[1], 0.0, 1.0) * (height - 1))
    return x, y


def bbox_to_px(bbox: list[float], width: int, height: int) -> tuple[int, int, int, int]:
    x1 = int(np.clip(bbox[0], 0.0, 1.0) * (width - 1))
    y1 = int(np.clip(bbox[1], 0.0, 1.0) * (height - 1))
    x2 = int(np.clip(bbox[2], 0.0, 1.0) * (width - 1))
    y2 = int(np.clip(bbox[3], 0.0, 1.0) * (height - 1))
    return x1, y1, x2, y2


def synthesize_audio(video: VideoAnalysis, variant: Variant, sample_rate: int, fps: float) -> np.ndarray:
    frame_count = len(video.frames)
    duration = frame_count / fps
    total_samples = int(duration * sample_rate)
    sample_times = np.arange(total_samples, dtype=np.float64) / sample_rate
    frame_times = np.arange(frame_count, dtype=np.float64) / fps

    pose_speed = np.array([float(frame.event.data.get("pose_speed", 0.0)) for frame in video.frames], dtype=np.float64)
    flow_energy = np.array([float(frame.event.data.get("flow_energy", 0.0)) for frame in video.frames], dtype=np.float64)
    depth = np.array([float(frame.depth.data.get("com_depth", 0.5)) for frame in video.frames], dtype=np.float64)
    com = np.array([frame.event.data.get("com", [0.5, 0.5]) for frame in video.frames], dtype=np.float64)
    com_x = com[:, 0]
    com_y = com[:, 1]

    variant_seed = zlib.crc32(variant.slug.encode("utf-8")) & 0xFFFFFFFF
    rng = np.random.default_rng(variant_seed)
    detune = 1.0 + (((variant_seed % 19) - 9) * 0.0018)
    hue_bias = 0.94 + variant.visual.base_hue * 0.14

    freq_curve = np.interp(sample_times, frame_times, 65.0 + (1.0 - com_y) * 420.0) * detune * hue_bias
    speed_curve = np.interp(sample_times, frame_times, pose_speed)
    flow_curve = np.interp(sample_times, frame_times, flow_energy)
    depth_curve = np.interp(sample_times, frame_times, depth)
    pan_curve = np.interp(sample_times, frame_times, (com_x - 0.5) * variant.audio.width * 1.8)
    amp_curve = variant.audio.base_gain * (0.18 + speed_curve * (0.86 + variant.visual.flow_gain * 0.12))

    phase = np.cumsum((2.0 * math.pi * freq_curve) / sample_rate)
    body = oscillator_bank(phase, flow_curve, depth_curve, variant.audio, variant.visual)
    bed = texture_bed(sample_times, phase, freq_curve, flow_curve, depth_curve, variant.audio, variant.visual)
    sub = np.sin(phase * 0.5) * variant.audio.sub_mix
    shimmer = np.sin(phase * (2.0 + depth_curve * (2.2 + variant.visual.flow_gain))) * (variant.audio.shimmer_mix * (0.16 + flow_curve))
    ring = body * np.sin(phase * (1.15 + depth_curve * (1.0 + variant.audio.fm_ratio * 0.35))) * variant.audio.ring_mix
    noise = rng.standard_normal(total_samples) * variant.audio.noise_mix * (0.08 + flow_curve * 0.28)

    mono = (body + bed + sub + shimmer + ring + noise) * amp_curve
    mono = apply_tremolo(mono, sample_times, variant.audio.tremolo_rate * (0.85 + variant.visual.flow_gain * 0.2), 0.08 + variant.visual.edge_mix * 0.22)
    mono = apply_one_pole_filter(mono, max(variant.audio.highpass_hz, 24.0), sample_rate, "highpass")
    mono = apply_one_pole_filter(
        mono,
        min(variant.audio.lowpass_hz * (0.86 + depth_curve * 0.28).mean(), sample_rate * 0.45),
        sample_rate,
        "lowpass",
    )
    if variant.audio.crush_mix > 0.0:
        crushed = bitcrush(mono, 14 - int(variant.audio.crush_mix * 8), hold=max(1, int(1 + variant.visual.scanlines * 12)))
        mono = mono * (1.0 - variant.audio.crush_mix) + crushed * variant.audio.crush_mix
    mono = saturate(mono, variant.audio.drive + variant.visual.edge_mix * 0.18)

    stereo = np.column_stack(
        [
            mono * (1.0 - np.clip(pan_curve, -1.0, 1.0)) * 0.5,
            mono * (1.0 + np.clip(pan_curve, -1.0, 1.0)) * 0.5,
        ]
    ).astype(np.float64)

    for frame in video.frames:
        events = frame.event.data.get("events", [])
        if not events:
            continue
        onset_sample = int((frame.frame_id / fps) * sample_rate)
        freq = 90.0 + (1.0 - float(frame.event.data.get("com", [0.5, 0.5])[1])) * 680.0
        pan = (float(frame.event.data.get("com", [0.5, 0.5])[0]) - 0.5) * 1.4
        for event in events:
            if event == "motion_onset":
                add_event_tone(
                    stereo,
                    onset_sample,
                    sample_rate,
                    0.16,
                    freq * 1.8,
                    freq * 0.95,
                    0.26 * variant.audio.event_gain,
                    pan,
                    event_tone_mode(variant.audio, event),
                )
            elif event == "impact":
                add_event_tone(
                    stereo,
                    onset_sample,
                    sample_rate,
                    0.24,
                    freq * 0.9,
                    freq * 0.42,
                    0.44 * variant.audio.event_gain,
                    pan,
                    event_tone_mode(variant.audio, event),
                )
            elif event == "person_enter":
                add_event_tone(
                    stereo,
                    onset_sample,
                    sample_rate,
                    0.72,
                    freq * 0.65,
                    freq * 2.2,
                    0.24 * variant.audio.event_gain,
                    pan,
                    event_tone_mode(variant.audio, event),
                )
            elif event == "person_exit":
                add_event_tone(
                    stereo,
                    onset_sample,
                    sample_rate,
                    0.68,
                    freq * 1.6,
                    freq * 0.38,
                    0.18 * variant.audio.event_gain,
                    pan,
                    event_tone_mode(variant.audio, event),
                )
            elif event == "flow_burst":
                add_event_tone(
                    stereo,
                    onset_sample,
                    sample_rate,
                    0.42,
                    freq * 2.4,
                    freq * 1.2,
                    0.24 * variant.audio.event_gain,
                    pan,
                    event_tone_mode(variant.audio, event),
                )

    stereo = apply_chorus(
        stereo,
        sample_rate,
        variant.audio.chorus_mix * (0.7 + variant.visual.particle_gain * 0.24),
        0.16 + variant.visual.flow_gain * 0.18,
    )
    stereo = apply_delay(stereo, sample_rate, variant.audio.delay_time, variant.audio.delay_mix)
    stereo = apply_reverb(stereo, sample_rate, variant.audio.reverb_mix)
    peak = np.max(np.abs(stereo)) if stereo.size else 1.0
    if peak > 0.98:
        stereo *= 0.98 / peak
    return stereo.astype(np.float32)


def oscillator_bank(phase: np.ndarray, flow: np.ndarray, depth: np.ndarray, preset: AudioPreset, visual: VisualFamily) -> np.ndarray:
    sine = np.sin(phase)
    tri = (2.0 / math.pi) * np.arcsin(np.sin(phase))
    saw = 2.0 * ((phase / (2.0 * math.pi)) % 1.0) - 1.0
    pulse = np.where(np.sin(phase) > 0.1, 1.0, -1.0)
    fm = np.sin(phase + np.sin(phase * preset.fm_ratio) * (preset.fm_index * (0.2 + flow * (1.2 + visual.flow_gain * 0.2))))

    if preset.oscillator == "sine":
        return sine * 0.8 + fm * 0.2
    if preset.oscillator == "tri":
        return tri * 0.7 + sine * 0.3
    if preset.oscillator == "saw":
        return saw * 0.72 + sine * 0.28
    if preset.oscillator == "pulse":
        return pulse * 0.55 + saw * 0.2 + sine * 0.25
    if preset.oscillator == "fm":
        return fm * 0.78 + sine * 0.22
    return sine * 0.28 + saw * 0.24 + tri * 0.2 + fm * 0.28 + np.sin(phase * (3.0 + depth * 1.2)) * 0.08


def texture_bed(
    sample_times: np.ndarray,
    phase: np.ndarray,
    freq_curve: np.ndarray,
    flow_curve: np.ndarray,
    depth_curve: np.ndarray,
    preset: AudioPreset,
    visual: VisualFamily,
) -> np.ndarray:
    if preset.texture_mode == "glass":
        partial_a = np.sin(phase * (2.8 + depth_curve * 1.1))
        partial_b = np.sin(phase * (5.2 + flow_curve * 2.4))
        return (partial_a * 0.14 + partial_b * 0.1) * (0.24 + flow_curve * 0.56)
    if preset.texture_mode == "pulsebed":
        rhythm = np.sign(np.sin(sample_times * math.tau * (3.2 + visual.scanlines * 12.0)))
        return rhythm * np.sin(phase * 0.5) * (0.08 + flow_curve * 0.18)
    if preset.texture_mode == "halo":
        slow = np.sin(sample_times * math.tau * 0.18) * 0.5 + 0.5
        return np.sin(phase * (1.0 + depth_curve * 0.22)) * (0.12 + slow * 0.12)
    if preset.texture_mode == "choir":
        vowel = np.sin(phase * 2.0) * 0.12 + np.sin(phase * 3.1) * 0.08
        return vowel * (0.32 + depth_curve * 0.38)
    if preset.texture_mode == "brass":
        brassy = (2.0 * ((phase * 1.01 / (2.0 * math.pi)) % 1.0) - 1.0) * 0.16
        return brassy + np.sin(phase * 1.5) * (0.08 + flow_curve * 0.08)
    if preset.texture_mode == "glitch":
        stepped = np.sin(phase * (1.0 + visual.edge_mix * 3.2))
        return bitcrush(stepped, bits=7, hold=4) * (0.16 + flow_curve * 0.18)
    return np.zeros_like(freq_curve)


def event_tone_mode(preset: AudioPreset, event: str) -> str:
    if preset.event_mode == "glass":
        return {"motion_onset": "glass", "impact": "shard", "person_enter": "halo", "person_exit": "tri", "flow_burst": "noise"}[event]
    if preset.event_mode == "pulse":
        return {"motion_onset": "pulse", "impact": "thump", "person_enter": "saw", "person_exit": "tri", "flow_burst": "noise"}[event]
    if preset.event_mode == "halo":
        return {"motion_onset": "halo", "impact": "sine", "person_enter": "halo", "person_exit": "tri", "flow_burst": "noise"}[event]
    if preset.event_mode == "choir":
        return {"motion_onset": "choir", "impact": "thump", "person_enter": "choir", "person_exit": "tri", "flow_burst": "noise"}[event]
    if preset.event_mode == "brass":
        return {"motion_onset": "brass", "impact": "thump", "person_enter": "saw", "person_exit": "tri", "flow_burst": "noise"}[event]
    return {"motion_onset": "shard", "impact": "thump", "person_enter": "glass", "person_exit": "tri", "flow_burst": "noise"}[event]


def apply_tremolo(signal: np.ndarray, sample_times: np.ndarray, rate: float, depth: float) -> np.ndarray:
    if rate <= 0.0 or depth <= 0.0:
        return signal
    lfo = 1.0 - depth + (np.sin(sample_times * math.tau * rate) * 0.5 + 0.5) * depth
    return signal * lfo


def apply_one_pole_filter(signal: np.ndarray, cutoff_hz: float, sample_rate: int, mode: str) -> np.ndarray:
    cutoff_hz = float(np.clip(cutoff_hz, 24.0, sample_rate * 0.45))
    alpha = math.exp(-(2.0 * math.pi * cutoff_hz) / sample_rate)
    output = np.zeros_like(signal)
    low = 0.0
    for index, sample in enumerate(signal):
        low = (1.0 - alpha) * sample + alpha * low
        output[index] = low if mode == "lowpass" else sample - low
    return output


def saturate(signal: np.ndarray, drive: float) -> np.ndarray:
    if drive <= 0.0:
        return signal
    amount = 1.0 + drive * 6.0
    return np.tanh(signal * amount) / np.tanh(amount)


def bitcrush(signal: np.ndarray, bits: int, hold: int) -> np.ndarray:
    bits = max(4, bits)
    levels = float((2 ** bits) - 1)
    crushed = np.round(signal * levels) / levels
    if hold <= 1:
        return crushed
    held = crushed.copy()
    for index in range(hold, len(held)):
        held[index] = held[index - (index % hold)]
    return held


def apply_chorus(stereo: np.ndarray, sample_rate: int, mix: float, rate: float) -> np.ndarray:
    if mix <= 0.0:
        return stereo
    wet = stereo.copy()
    phase = 0.0
    for index in range(len(stereo)):
        phase += (math.tau * rate) / sample_rate
        modulation = (math.sin(phase) * 0.5 + 0.5)
        delay_samples = int((0.008 + modulation * 0.012) * sample_rate)
        if index <= delay_samples:
            continue
        wet[index, 0] += stereo[index - delay_samples, 1] * mix * 0.35
        wet[index, 1] += stereo[index - delay_samples, 0] * mix * 0.35
    return wet


def add_event_tone(
    stereo: np.ndarray,
    start: int,
    sample_rate: int,
    duration: float,
    freq_start: float,
    freq_end: float,
    amp: float,
    pan: float,
    mode: str,
) -> None:
    length = int(duration * sample_rate)
    if length <= 0 or start >= stereo.shape[0]:
        return
    end = min(stereo.shape[0], start + length)
    actual = end - start
    time_axis = np.linspace(0.0, 1.0, actual, endpoint=False)
    freq = np.linspace(freq_start, freq_end, actual, endpoint=False)
    phase = np.cumsum((2.0 * math.pi * freq) / sample_rate)
    env = np.exp(-5.0 * time_axis)

    if mode == "saw":
        wave_data = (2.0 * ((phase / (2.0 * math.pi)) % 1.0) - 1.0) * env
    elif mode == "tri":
        wave_data = ((2.0 / math.pi) * np.arcsin(np.sin(phase))) * env
    elif mode == "pulse":
        wave_data = np.where(np.sin(phase) > 0.0, 1.0, -1.0) * env * 0.72
    elif mode == "thump":
        click = np.sin(phase * 0.5) * np.exp(-7.5 * time_axis)
        crack = np.sin(phase * 2.0) * np.exp(-18.0 * time_axis) * 0.3
        wave_data = click + crack
    elif mode == "glass":
        shimmer = np.sin(phase * 1.8 + np.sin(phase * 3.4) * 0.7) * np.exp(-7.0 * time_axis)
        ping = np.sin(phase * 4.8) * np.exp(-18.0 * time_axis) * 0.2
        wave_data = shimmer + ping
    elif mode == "halo":
        wave_data = (np.sin(phase) * 0.7 + np.sin(phase * 0.5) * 0.3) * np.exp(-2.2 * time_axis)
    elif mode == "choir":
        wave_data = (np.sin(phase) * 0.55 + np.sin(phase * 2.02) * 0.24 + np.sin(phase * 3.14) * 0.14) * np.exp(-3.6 * time_axis)
    elif mode == "brass":
        saw = 2.0 * ((phase / (2.0 * math.pi)) % 1.0) - 1.0
        wave_data = np.tanh((saw * 0.8 + np.sin(phase) * 0.25) * 1.8) * np.exp(-4.0 * time_axis)
    elif mode == "shard":
        shard = 2.0 * ((phase * 1.7 / (2.0 * math.pi)) % 1.0) - 1.0
        wave_data = bitcrush(shard, bits=6, hold=3) * np.exp(-9.0 * time_axis)
    elif mode == "noise":
        rng = np.random.default_rng(start + length)
        wave_data = (rng.standard_normal(actual) * np.exp(-6.0 * time_axis) * 0.6) + np.sin(phase) * env * 0.18
    else:
        wave_data = np.sin(phase) * env

    left_gain = (1.0 - np.clip(pan, -1.0, 1.0)) * 0.5
    right_gain = (1.0 + np.clip(pan, -1.0, 1.0)) * 0.5
    stereo[start:end, 0] += wave_data * amp * left_gain
    stereo[start:end, 1] += wave_data * amp * right_gain


def apply_delay(stereo: np.ndarray, sample_rate: int, delay_time: float, mix: float) -> np.ndarray:
    if mix <= 0.0:
        return stereo
    delay = max(1, int(delay_time * sample_rate))
    wet = stereo.copy()
    if delay < len(stereo):
        wet[delay:] += stereo[:-delay] * mix
    if delay * 2 < len(stereo):
        wet[delay * 2 :] += stereo[: -delay * 2] * mix * 0.55
    return wet


def apply_reverb(stereo: np.ndarray, sample_rate: int, mix: float) -> np.ndarray:
    if mix <= 0.0:
        return stereo
    wet = stereo.copy()
    taps = [
        (0.011, 0.22),
        (0.017, 0.17),
        (0.029, 0.12),
        (0.041, 0.09),
        (0.053, 0.06),
    ]
    for seconds, gain in taps:
        offset = int(seconds * sample_rate)
        if offset < len(stereo):
            wet[offset:] += stereo[:-offset] * gain * mix
    return wet


def write_wav(path: Path, stereo: np.ndarray, sample_rate: int) -> None:
    clipped = np.clip(stereo, -1.0, 1.0)
    pcm = (clipped * 32767.0).astype(np.int16)
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(2)
        wav.setsampwidth(2)
        wav.setframerate(sample_rate)
        wav.writeframes(pcm.tobytes())


def mux_video_audio(video_path: Path, audio_path: Path, output_path: Path) -> None:
    command = [
        "ffmpeg",
        "-y",
        "-hide_banner",
        "-loglevel",
        "error",
        "-i",
        str(video_path),
        "-i",
        str(audio_path),
        "-c:v",
        "libx264",
        "-pix_fmt",
        "yuv420p",
        "-crf",
        "18",
        "-c:a",
        "aac",
        "-b:a",
        "192k",
        "-shortest",
        str(output_path),
    ]
    subprocess.run(command, check=True)


def build_gallery_html(video: VideoAnalysis, manifest: list[dict[str, object]]) -> str:
    cards = []
    for entry in manifest:
        cards.append(
            f"""
            <article class="card">
              <img src="{entry["poster"]}" alt="{entry["label"]}" />
              <div class="meta">
                <h2>{entry["ordinal"]:02d}. {entry["label"]}</h2>
                <p>{entry["visual_family"]} / {entry["audio_preset"]}</p>
              </div>
              <video controls preload="metadata" poster="{entry["poster"]}">
                <source src="{entry["video"]}" type="video/mp4" />
              </video>
            </article>
            """.strip()
        )
    return f"""<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>VRB Preview Batch</title>
    <link
      rel="icon"
      href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'%3E%3Crect width='64' height='64' rx='14' fill='%23090d13'/%3E%3Ccircle cx='32' cy='32' r='18' fill='%2372efbf'/%3E%3Cpath d='M18 44 L32 18 L46 44' stroke='%23090d13' stroke-width='6' fill='none' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E"
    />
    <style>
      :root {{
        color-scheme: dark;
        --bg: #090d13;
        --panel: rgba(19, 26, 36, 0.92);
        --line: rgba(164, 191, 224, 0.15);
        --text: #f3f7fb;
        --muted: #9ab0c6;
        --accent: #72efbf;
      }}
      * {{ box-sizing: border-box; }}
      body {{
        margin: 0;
        font-family: "IBM Plex Sans", "Avenir Next", sans-serif;
        background:
          radial-gradient(circle at top left, rgba(114, 239, 191, 0.12), transparent 30%),
          radial-gradient(circle at top right, rgba(126, 203, 255, 0.12), transparent 22%),
          var(--bg);
        color: var(--text);
      }}
      header {{
        padding: 28px 28px 10px;
      }}
      header p {{
        margin: 8px 0 0;
        color: var(--muted);
      }}
      .grid {{
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
        gap: 18px;
        padding: 18px 28px 36px;
      }}
      .card {{
        border: 1px solid var(--line);
        background: var(--panel);
        border-radius: 20px;
        overflow: hidden;
        box-shadow: 0 24px 60px rgba(0, 0, 0, 0.32);
      }}
      img {{
        display: block;
        width: 100%;
        aspect-ratio: 16 / 9;
        object-fit: cover;
        background: #04070b;
      }}
      .meta {{
        padding: 14px 16px 10px;
      }}
      .meta h2 {{
        margin: 0;
        font-size: 1rem;
      }}
      .meta p {{
        margin: 8px 0 0;
        color: var(--muted);
      }}
      video {{
        display: block;
        width: 100%;
        background: #000;
      }}
      .accent {{
        color: var(--accent);
      }}
    </style>
  </head>
  <body>
    <header>
      <p class="accent">Virtual Real Body Preview Batch</p>
      <h1>{len(manifest)} variants from {video.source_path.name}</h1>
      <p>Each preview combines source footage, analyzer overlays, generative graphics, and synthesized audio.</p>
    </header>
    <section class="grid">
      {"".join(cards)}
    </section>
  </body>
</html>
"""


def main() -> int:
    args = build_parser().parse_args()
    source = Path(args.video_file).expanduser().resolve()
    output_dir = Path(args.output_dir).expanduser().resolve()

    analysis = analyze_video(source, args.width, args.max_frames)
    print(
        json.dumps(
            {
                "source": str(source),
                "frame_count": len(analysis.frames),
                "fps": analysis.fps,
                "size": analysis.size,
            }
        ),
        flush=True,
    )
    variants = build_variant_matrix()
    if args.max_variants > 0:
        variants = variants[: args.max_variants]

    fps = args.fps if args.fps > 0 else analysis.fps
    manifest = render_variant_set(analysis, variants, output_dir, args.sample_rate, fps)
    print(json.dumps({"output_dir": str(output_dir), "variant_count": len(manifest)}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
