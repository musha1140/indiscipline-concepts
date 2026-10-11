#!/usr/bin/env python3
"""Switchboard state relay for the Raspberry Pi tailnet node `gsl`.

Stores one JSON document (the shared Switchboard state) and serves it to
browsers on the tailnet. Sealed channels arrive already encrypted, so the
relay only ever holds their ciphertext.

Endpoints
  GET  /state    returns the document with an ETag; honours If-None-Match (304);
                 204 when nothing has been stored yet
  PUT  /state    replaces the document; honours If-Match (412 on conflict)
  GET  /health   liveness check, no auth

Environment
  SWITCHBOARD_TOKEN     required bearer token for /state
  SWITCHBOARD_ORIGINS   comma separated CORS origins
                        (default https://gas-lighting.com,https://musha1140.github.io)
  SWITCHBOARD_DATA      path of the stored document (default ~/switchboard/state.json)
  SWITCHBOARD_PORT      listen port on 127.0.0.1 (default 8787)

Bind is loopback only. Expose it to the tailnet with:
  tailscale serve --bg 8787
"""

import hashlib
import hmac
import json
import os
import sys
import tempfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Lock

TOKEN = os.environ.get("SWITCHBOARD_TOKEN", "")
ORIGINS = {
    o.strip().rstrip("/")
    for o in os.environ.get(
        "SWITCHBOARD_ORIGINS", "https://gas-lighting.com,https://musha1140.github.io"
    ).split(",")
    if o.strip()
}
DATA = Path(os.environ.get("SWITCHBOARD_DATA", str(Path.home() / "switchboard" / "state.json")))
PORT = int(os.environ.get("SWITCHBOARD_PORT", "8787"))
MAX_BODY = 25 * 1024 * 1024
LOCK = Lock()


def etag_of(raw: bytes) -> str:
    return '"' + hashlib.sha256(raw).hexdigest()[:32] + '"'


def read_doc():
    try:
        raw = DATA.read_bytes()
    except FileNotFoundError:
        return None, None
    return raw, etag_of(raw)


def write_doc(raw: bytes) -> str:
    DATA.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(DATA.parent), prefix=".state-", suffix=".json")
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(raw)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, DATA)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    return etag_of(raw)


class Handler(BaseHTTPRequestHandler):
    server_version = "SwitchboardRelay/1"

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))

    def cors(self):
        origin = (self.headers.get("Origin") or "").rstrip("/")
        if origin in ORIGINS:
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Vary", "Origin")
            self.send_header("Access-Control-Allow-Methods", "GET, PUT, OPTIONS")
            self.send_header(
                "Access-Control-Allow-Headers",
                "Authorization, Content-Type, If-Match, If-None-Match",
            )
            self.send_header("Access-Control-Expose-Headers", "ETag")
            self.send_header("Access-Control-Allow-Private-Network", "true")
            self.send_header("Access-Control-Max-Age", "600")

    def reply(self, code, body=b"", etag=None, ctype="application/json"):
        self.send_response(code)
        self.cors()
        self.send_header("Cache-Control", "no-store")
        if etag:
            self.send_header("ETag", etag)
        if body:
            self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def authed(self):
        if not TOKEN:
            return False
        got = self.headers.get("Authorization", "")
        return hmac.compare_digest(got, "Bearer " + TOKEN)

    def do_OPTIONS(self):
        self.reply(204)

    def do_GET(self):
        if self.path == "/health":
            return self.reply(200, b'{"ok":true}')
        if self.path != "/state":
            return self.reply(404, b'{"error":"not found"}')
        if not self.authed():
            return self.reply(401, b'{"error":"unauthorized"}')
        with LOCK:
            raw, tag = read_doc()
        if raw is None:
            return self.reply(204)
        if self.headers.get("If-None-Match") == tag:
            return self.reply(304, etag=tag)
        return self.reply(200, raw, etag=tag)

    def do_PUT(self):
        if self.path != "/state":
            return self.reply(404, b'{"error":"not found"}')
        if not self.authed():
            return self.reply(401, b'{"error":"unauthorized"}')
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            return self.reply(400, b'{"error":"bad length"}')
        if length <= 0 or length > MAX_BODY:
            return self.reply(413, b'{"error":"size"}')
        raw = self.rfile.read(length)
        try:
            doc = json.loads(raw)
        except ValueError:
            return self.reply(400, b'{"error":"not json"}')
        if not isinstance(doc, dict) or doc.get("v") != 1 or not isinstance(doc.get("channels"), list):
            return self.reply(422, b'{"error":"not a switchboard document"}')
        want = self.headers.get("If-Match", "*")
        with LOCK:
            _, current = read_doc()
            if want != "*" and current is not None and want != current:
                return self.reply(412, b'{"error":"stale"}', etag=current)
            tag = write_doc(raw)
        return self.reply(200, b'{"ok":true}', etag=tag)


def main():
    if not TOKEN or len(TOKEN) < 24:
        sys.exit("Set SWITCHBOARD_TOKEN to a random string of at least 24 characters.")
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    sys.stderr.write("switchboard relay on 127.0.0.1:%d, data %s\n" % (PORT, DATA))
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
