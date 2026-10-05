"""Serves a Flutter web build with correct WASM/JS MIME types.

Usage: python tool/serve_web.py [build_dir] [port]
"""
import functools
import http.server
import sys
from pathlib import Path

BUILD_DIR = Path(sys.argv[1] if len(sys.argv) > 1 else "build/web")
PORT = int(sys.argv[2] if len(sys.argv) > 2 else 8123)


class WasmCapableHandler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".mjs": "text/javascript",
        ".js": "text/javascript",
    }

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(BUILD_DIR), **kwargs)

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))


def main() -> None:
    handler = functools.partial(WasmCapableHandler)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), handler)
    print(f"Serving {BUILD_DIR.resolve()} at http://127.0.0.1:{PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()
