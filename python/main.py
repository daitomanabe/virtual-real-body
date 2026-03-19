from __future__ import annotations

import argparse

from config import settings
from core.engine import AnalysisEngine


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Virtual Real Body analysis engine")
    parser.add_argument("--camera-index", type=int, default=settings.camera_index)
    parser.add_argument("--dry-run", action="store_true")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    engine = AnalysisEngine(camera_index=args.camera_index)
    if args.dry_run:
        print(engine.describe())
        return 0

    raise SystemExit(
        "Runtime capture loop is intentionally deferred until analyzer implementation is complete."
    )


if __name__ == "__main__":
    raise SystemExit(main())
