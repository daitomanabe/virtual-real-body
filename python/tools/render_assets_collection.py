from __future__ import annotations

import argparse
import json
from pathlib import Path

from preview_batch import build_variant_matrix, analyze_video, render_variant_set


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_ASSETS_DIR = Path("/Users/daitomacm5/development/sandbox/assets")
DEFAULT_OUTPUT_ROOT = ROOT / "outputs" / "preview-batches"
VIDEO_EXTENSIONS = {".mov", ".mp4", ".m4v"}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Render preview batches for every video in an assets directory")
    parser.add_argument("--assets-dir", default=str(DEFAULT_ASSETS_DIR), help="Directory containing source videos")
    parser.add_argument("--output-root", default=str(DEFAULT_OUTPUT_ROOT), help="Root output directory for per-video batches")
    parser.add_argument("--width", type=int, default=640, help="Preview render width")
    parser.add_argument("--sample-rate", type=int, default=44100, help="Audio sample rate")
    parser.add_argument("--max-variants", type=int, default=0, help="Optional cap for quick testing")
    parser.add_argument("--max-frames", type=int, default=0, help="Optional frame cap for quick testing")
    parser.add_argument("--fps", type=float, default=0.0, help="Optional render fps override")
    parser.add_argument("--force", action="store_true", help="Re-render batches even when manifest.json already exists")
    return parser


def build_collection_html(collection_manifest: list[dict[str, object]]) -> str:
    cards = []
    for entry in collection_manifest:
        poster = str(entry["first_poster"])
        slug = str(entry["slug"])
        cards.append(
            f"""
            <article class="card">
              <a class="poster" href="{entry["gallery"]}">
                <img src="{slug}/{poster}" alt="{entry["label"]}" />
              </a>
              <div class="meta">
                <p class="eyebrow">{entry["variant_count"]} variants</p>
                <h2><a href="{entry["gallery"]}">{entry["label"]}</a></h2>
                <p>{entry["duration_seconds"]} sec</p>
                <p>{entry["status"]}</p>
              </div>
            </article>
            """.strip()
        )

    return f"""<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>VRB Assets Collection</title>
    <style>
      :root {{
        color-scheme: dark;
        --bg: #07090d;
        --panel: rgba(18, 24, 35, 0.94);
        --line: rgba(164, 191, 224, 0.15);
        --text: #f6f8fb;
        --muted: #98afc5;
        --accent: #8cf2d0;
      }}
      * {{ box-sizing: border-box; }}
      body {{
        margin: 0;
        font-family: "IBM Plex Sans", "Avenir Next", sans-serif;
        color: var(--text);
        background:
          radial-gradient(circle at top left, rgba(140, 242, 208, 0.12), transparent 28%),
          radial-gradient(circle at top right, rgba(116, 168, 255, 0.1), transparent 24%),
          var(--bg);
      }}
      header {{
        padding: 28px;
      }}
      header p {{
        margin: 8px 0 0;
        color: var(--muted);
      }}
      .grid {{
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
        gap: 20px;
        padding: 0 28px 36px;
      }}
      .card {{
        overflow: hidden;
        border-radius: 20px;
        background: var(--panel);
        border: 1px solid var(--line);
        box-shadow: 0 24px 60px rgba(0, 0, 0, 0.34);
      }}
      .poster {{
        display: block;
      }}
      img {{
        display: block;
        width: 100%;
        aspect-ratio: 16 / 9;
        object-fit: cover;
        background: #030405;
      }}
      .meta {{
        padding: 14px 16px 18px;
      }}
      .meta h2 {{
        margin: 6px 0 0;
        font-size: 1.08rem;
      }}
      .meta p {{
        margin: 8px 0 0;
        color: var(--muted);
      }}
      .eyebrow {{
        color: var(--accent);
        text-transform: uppercase;
        letter-spacing: 0.08em;
        font-size: 0.76rem;
      }}
      a {{
        color: inherit;
        text-decoration: none;
      }}
    </style>
  </head>
  <body>
    <header>
      <p>Virtual Real Body Assets Collection</p>
      <h1>{len(collection_manifest)} source videos</h1>
      <p>Each gallery contains analyzer composites, generated graphics, and synthesized audio variants.</p>
    </header>
    <section class="grid">
      {"".join(cards)}
    </section>
  </body>
</html>
"""


def existing_duration_seconds(manifest: dict[str, object]) -> float:
    source_value = manifest.get("source")
    if not source_value:
        return 0.0
    source_path = Path(str(source_value))
    if not source_path.exists():
        return 0.0
    capture = __import__("cv2").VideoCapture(str(source_path))
    try:
        fps = float(capture.get(__import__("cv2").CAP_PROP_FPS) or 30.0)
        frame_count = int(capture.get(__import__("cv2").CAP_PROP_FRAME_COUNT) or 0)
        if fps <= 0.0:
            return 0.0
        return round(frame_count / fps, 3)
    finally:
        capture.release()


def main() -> int:
    args = build_parser().parse_args()
    assets_dir = Path(args.assets_dir).expanduser().resolve()
    output_root = Path(args.output_root).expanduser().resolve()
    output_root.mkdir(parents=True, exist_ok=True)

    videos = sorted(
        path
        for path in assets_dir.iterdir()
        if path.is_file() and path.suffix.lower() in VIDEO_EXTENSIONS
    )
    if not videos:
        raise SystemExit(f"No video files found in {assets_dir}")

    variants = build_variant_matrix()
    if args.max_variants > 0:
        variants = variants[: args.max_variants]

    collection_manifest: list[dict[str, object]] = []
    for video_path in videos:
        batch_slug = f"{video_path.stem.lower()}_batch"
        batch_output_dir = output_root / batch_slug
        manifest_path = batch_output_dir / "manifest.json"
        if manifest_path.exists() and not args.force:
            existing = json.loads(manifest_path.read_text(encoding="utf-8"))
            collection_manifest.append(
                {
                    "source": str(video_path),
                    "slug": batch_slug,
                    "label": video_path.name,
                    "gallery": f"{batch_slug}/index.html",
                    "variant_count": len(existing.get("variants", [])),
                    "duration_seconds": existing_duration_seconds(existing),
                    "first_poster": existing.get("variants", [{}])[0].get("poster", "") if existing.get("variants") else "",
                    "status": "reused",
                }
            )
            print(json.dumps({"source": str(video_path), "output_dir": str(batch_output_dir), "status": "reused"}), flush=True)
            continue
        analysis = analyze_video(video_path, args.width, args.max_frames)
        fps = args.fps if args.fps > 0 else analysis.fps
        print(
            json.dumps(
                {
                    "source": str(video_path),
                    "frame_count": len(analysis.frames),
                    "fps": fps,
                    "size": analysis.size,
                    "output_dir": str(batch_output_dir),
                }
            ),
            flush=True,
        )
        manifest = render_variant_set(analysis, variants, batch_output_dir, args.sample_rate, fps)
        collection_manifest.append(
            {
                "source": str(video_path),
                "slug": batch_slug,
                "label": video_path.name,
                "gallery": f"{batch_slug}/index.html",
                "variant_count": len(manifest),
                "duration_seconds": round(len(analysis.frames) / fps, 3),
                "first_poster": manifest[0]["poster"] if manifest else "",
                "status": "rendered",
            }
        )

    collection_manifest_path = output_root / "assets_collection_manifest.json"
    collection_manifest_path.write_text(json.dumps({"videos": collection_manifest}, indent=2), encoding="utf-8")
    collection_index_path = output_root / "assets_collection_index.html"
    collection_index_path.write_text(build_collection_html(collection_manifest), encoding="utf-8")
    print(
        json.dumps(
            {
                "output_root": str(output_root),
                "video_count": len(collection_manifest),
                "collection_index": str(collection_index_path),
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
