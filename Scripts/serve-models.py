#!/usr/bin/env python3
"""A local stand-in for GitHub Releases, for exercising the model downloader.

The repo is not public yet, so the manifest's release URLs 404; and even once it
is, "kill the network mid-download" is not a test you can run against GitHub.
This serves a directory over HTTP with the two things resumable downloads need
and python's built-in http.server lacks: `Range: bytes=N-` (206) and a stable
`ETag`/`If-Range`, so a client can prove it resumes and re-verifies.

    Scripts/serve-models.py .build/models 8901

Then point a dev manifest's URLs at http://127.0.0.1:8901/<file>.zip.
`--flaky N` closes every connection after N bytes, which is how the resume path
gets exercised deterministically: first request dies at N, the retry must send
Range and finish, and the SHA256 over the joined halves must still match.

Port 0 binds a free port and announces it on the first stderr line
("listening 127.0.0.1:PORT"), which is how PluckKit's integration tests start a
server without racing another one for a hardcoded number.
"""

import hashlib
import os
import re
import socket
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8901
FLAKY = 0
if "--flaky" in sys.argv:
    FLAKY = int(sys.argv[sys.argv.index("--flaky") + 1])


class RangeHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_HEAD(self):
        self._serve(head_only=True)

    def do_GET(self):
        self._serve(head_only=False)

    def _serve(self, head_only):
        path = os.path.abspath(os.path.join(ROOT, self.path.lstrip("/")))
        if not path.startswith(ROOT) or not os.path.isfile(path):
            self.send_error(404)
            return
        size = os.path.getsize(path)
        # Strong validator from content, not mtime: a re-packaged zip must read
        # as a different entity so If-Range correctly forces a full re-download.
        with open(path, "rb") as f:
            etag = '"%s"' % hashlib.sha256(f.read(65536) + str(size).encode()).hexdigest()[:32]

        start, end = 0, size - 1
        status = 200
        ranged = self.headers.get("Range")
        if ranged:
            if_range = self.headers.get("If-Range")
            if if_range and if_range != etag:
                ranged = None  # entity changed: ignore the range, send it all
        if ranged:
            m = re.fullmatch(r"bytes=(\d+)-(\d*)", ranged.strip())
            if not m or int(m.group(1)) >= size:
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{size}")
                self.end_headers()
                return
            start = int(m.group(1))
            if m.group(2):
                end = min(int(m.group(2)), size - 1)
            status = 206

        self.send_response(status)
        self.send_header("Content-Type", "application/zip")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("ETag", etag)
        self.send_header("Content-Length", str(end - start + 1))
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        if head_only:
            return

        sent = 0
        with open(path, "rb") as f:
            f.seek(start)
            remaining = end - start + 1
            while remaining > 0:
                chunk = f.read(min(65536, remaining))
                if not chunk:
                    break
                if FLAKY and sent + len(chunk) > FLAKY:
                    chunk = chunk[: FLAKY - sent]
                    self.wfile.write(chunk)
                    self.wfile.flush()
                    # A mid-body cut, which is what a dropped connection looks
                    # like to the client — not an HTTP error it could parse.
                    # SHUT_WR, not SHUT_RDWR: half-closing sends a FIN, so the
                    # bytes already in flight still arrive and the peer sees a
                    # short body. Tearing down both directions can make the
                    # kernel answer with an RST instead, and an RST lets the
                    # client throw away everything it had buffered — which
                    # would make this a test of data loss rather than of resume.
                    self.close_connection = True
                    try:
                        self.connection.shutdown(socket.SHUT_WR)
                        # Long enough for the peer to drain the socket before
                        # the handler returns and closes it.
                        time.sleep(0.2)
                    except OSError:
                        pass
                    return
                self.wfile.write(chunk)
                sent += len(chunk)
                remaining -= len(chunk)

    def log_message(self, fmt, *args):
        sys.stderr.write("serve-models: %s\n" % (fmt % args))


if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", PORT), RangeHandler)
    port = server.server_address[1]
    mode = f", dropping every connection after {FLAKY} bytes" if FLAKY else ""
    # Machine-readable first, prose second: a test reads line one and stops.
    print(f"listening 127.0.0.1:{port}", file=sys.stderr, flush=True)
    print(f"serving {ROOT} on http://127.0.0.1:{port}{mode}", file=sys.stderr, flush=True)
    server.serve_forever()
