from __future__ import annotations

import argparse
from time import sleep

import numpy as np

from analyzers import (
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
from config import settings
from core.engine import AnalysisEngine

try:
    import cv2
except ImportError:  # pragma: no cover
    cv2 = None


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Virtual Real Body analysis engine")
    parser.add_argument("--camera-index", type=int, default=settings.camera_index)
    parser.add_argument("--video-file")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--frame-limit", type=int, default=0)
    parser.add_argument("--synthetic-input", action="store_true")
    return parser


def build_default_analyzers() -> list[object]:
    return [
        YOLODetectAnalyzer(),
        YOLOPoseAnalyzer(),
        YOLOSegAnalyzer(),
        OpticalFlowAnalyzer(),
        SparseFlowAnalyzer(),
        MediaPipeAnalyzer(),
        DepthAnalyzer(),
        EventAnalyzer(),
        ParticleAnalyzer(),
    ]


def _run_synthetic(engine: AnalysisEngine, frame_limit: int) -> int:
    limit = frame_limit if frame_limit > 0 else 1
    frame = np.zeros((720, 1280, 3), dtype=np.uint8)
    for frame_id in range(limit):
        engine.process_frame(frame, frame_id)
    return 0


def _run_camera(engine: AnalysisEngine, camera_index: int, frame_limit: int) -> int:
    if cv2 is None:
        raise RuntimeError(
            "OpenCV is not installed. Install python requirements or use --synthetic-input for a non-camera probe."
        )

    capture = cv2.VideoCapture(camera_index)
    if not capture.isOpened():
        raise RuntimeError(f"Failed to open camera index {camera_index}.")

    try:
        frame_id = 0
        frame_interval = 1.0 / max(settings.target_fps, 1)
        while True:
            ok, frame_bgr = capture.read()
            if not ok:
                raise RuntimeError("Camera read failed.")

            engine.process_frame(frame_bgr, frame_id)
            frame_id += 1

            if frame_limit > 0 and frame_id >= frame_limit:
                break
            sleep(frame_interval)
    finally:
        capture.release()

    return 0


def _run_video_file(engine: AnalysisEngine, video_file: str, frame_limit: int) -> int:
    if cv2 is None:
        raise RuntimeError(
            "OpenCV is not installed. Install python requirements or use --synthetic-input for a non-camera probe."
        )

    capture = cv2.VideoCapture(video_file)
    if not capture.isOpened():
        raise RuntimeError(f"Failed to open video file: {video_file}.")

    frame_id = 0
    try:
        while True:
            ok, frame_bgr = capture.read()
            if not ok:
                break

            engine.process_frame(frame_bgr, frame_id)
            frame_id += 1

            if frame_limit > 0 and frame_id >= frame_limit:
                break
    finally:
        capture.release()

    if frame_id == 0:
        raise RuntimeError(f"Video file produced no frames: {video_file}.")

    return 0


def main() -> int:
    args = build_parser().parse_args()
    engine = AnalysisEngine(
        analyzers=build_default_analyzers(),
        camera_index=args.camera_index,
    )
    if args.dry_run:
        print(engine.describe())
        return 0

    engine.zmq_publisher.connect()
    try:
        if args.synthetic_input:
            return _run_synthetic(engine, args.frame_limit)
        if args.video_file:
            return _run_video_file(engine, args.video_file, args.frame_limit)
        return _run_camera(engine, args.camera_index, args.frame_limit)
    except KeyboardInterrupt:
        return 130
    finally:
        engine.zmq_publisher.close()


if __name__ == "__main__":
    raise SystemExit(main())
