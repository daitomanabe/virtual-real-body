#!/usr/bin/env python3
from __future__ import annotations

import os
import sys
from http.server import HTTPServer, SimpleHTTPRequestHandler


class RangeHTTPRequestHandler(SimpleHTTPRequestHandler):
    def send_head(self):
        path = self.translate_path(self.path)
        if not os.path.isfile(path):
            return super().send_head()

        file_size = os.path.getsize(path)
        range_header = self.headers.get("Range")
        if range_header is None:
            return super().send_head()

        try:
            start_text, end_text = range_header.replace("bytes=", "").split("-", 1)
            start = int(start_text) if start_text else 0
            end = int(end_text) if end_text else file_size - 1
        except (ValueError, IndexError):
            self.send_error(416, "Invalid Range")
            return None

        end = min(end, file_size - 1)
        if start > end:
            self.send_error(416, "Invalid Range")
            return None

        content_length = end - start + 1
        content_type = self.guess_type(path)
        handle = open(path, "rb")
        handle.seek(start)

        self.send_response(206)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(content_length))
        self.send_header("Content-Range", f"bytes {start}-{end}/{file_size}")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        return _RangeFile(handle, content_length)

    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Range")
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()


class _RangeFile:
    def __init__(self, handle, remaining: int):
        self._handle = handle
        self._remaining = remaining

    def read(self, size=None):
        if self._remaining <= 0:
            return b""
        chunk_size = min(size, self._remaining) if size else self._remaining
        data = self._handle.read(chunk_size)
        self._remaining -= len(data)
        return data

    def close(self):
        self._handle.close()


def main() -> int:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    server = HTTPServer(("", port), RangeHTTPRequestHandler)
    print(f"Range-enabled HTTP server on http://127.0.0.1:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
