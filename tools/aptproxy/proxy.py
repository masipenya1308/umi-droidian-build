#!/usr/bin/env python3
"""Small caching HTTP proxy for apt.

Why: releases.droidian.org serves this phone at ~1 KB/s over Wi-Fi (the flow
stalls after ~33 KB), while the same URL from the Windows box on the same LAN
runs at 1-2 MB/s.  Point apt at this proxy and the downloads happen here and
get cached; the phone only pulls over the LAN.

Usage:
    python proxy.py [--port 3142] [--cache DIR]

Then on the phone:
    echo 'Acquire::http::Proxy "http://<windows-ip>:3142";' \
        > /etc/apt/apt.conf.d/99proxy
"""

import argparse
import hashlib
import json
import os
import socket
import socketserver
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CACHE_DIR = None
LOG_PATH = None
LOCK = threading.Lock()
LOG_LOCK = threading.Lock()
HOP = {
    "connection", "proxy-connection", "keep-alive", "te", "trailer",
    "transfer-encoding", "upgrade", "proxy-authorization", "proxy-authenticate",
}


def cache_paths(url):
    key = hashlib.sha256(url.encode()).hexdigest()
    return os.path.join(CACHE_DIR, key + ".body"), os.path.join(CACHE_DIR, key + ".json")


def load_cached(url):
    body_path, meta_path = cache_paths(url)
    if not (os.path.exists(body_path) and os.path.exists(meta_path)):
        return None
    try:
        with open(meta_path, "r", encoding="utf-8") as fh:
            meta = json.load(fh)
        with open(body_path, "rb") as fh:
            body = fh.read()
    except OSError:
        return None
    return meta, body


def store_cached(url, meta, body):
    body_path, meta_path = cache_paths(url)
    tmp = body_path + ".part"
    with open(tmp, "wb") as fh:
        fh.write(body)
    os.replace(tmp, body_path)
    with open(meta_path, "w", encoding="utf-8") as fh:
        json.dump(meta, fh)


def fetch_upstream(url, timeout=120):
    req = urllib.request.Request(url, headers={"User-Agent": "umi-apt-proxy/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        body = resp.read()
        meta = {
            "status": resp.status,
            "headers": {k: v for k, v in resp.headers.items()
                        if k.lower() not in HOP},
        }
    return meta, body


def parse_range(value, total):
    """Return (start, end) inclusive or None if unparsable/unsatisfiable."""
    if not value or not value.startswith("bytes="):
        return None
    spec = value[6:].split(",")[0].strip()
    if "-" not in spec:
        return None
    first, last = spec.split("-", 1)
    if first == "":
        n = int(last)
        return max(0, total - n), total - 1
    start = int(first)
    end = int(last) if last else total - 1
    if start >= total:
        return None
    return start, min(end, total - 1)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "umi-apt-proxy/1.0"

    def log_message(self, fmt, *args):
        # pythonw.exe has no stdout/stderr, so never touch sys.stderr here.
        line = "%s %s\n" % (time.strftime("%H:%M:%S"), fmt % args)
        if not LOG_PATH:
            return
        try:
            with LOG_LOCK:
                if os.path.exists(LOG_PATH) and os.path.getsize(LOG_PATH) > 5 * 1024 * 1024:
                    os.replace(LOG_PATH, LOG_PATH + ".1")
                with open(LOG_PATH, "a", encoding="utf-8") as fh:
                    fh.write(line)
        except OSError:
            pass

    # ---- helpers -------------------------------------------------------
    def send_simple(self, code, text):
        body = text.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def send_cached(self, meta, body, url):
        total = len(body)
        headers = dict(meta["headers"])
        rng = self.headers.get("Range")
        span = parse_range(rng, total) if rng else None
        if span is None:
            payload = body
            self.send_response(meta["status"])
            for k, v in headers.items():
                if k.lower() not in ("content-length", "accept-ranges"):
                    self.send_header(k, v)
            self.send_header("Content-Length", str(total))
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("X-Cache", "HIT")
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(payload)
            return
        start, end = span
        payload = body[start:end + 1]
        self.send_response(206)
        for k, v in headers.items():
            if k.lower() not in ("content-length", "accept-ranges", "content-range"):
                self.send_header(k, v)
        self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, total))
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("X-Cache", "HIT")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(payload)

    def handle_proxy(self):
        url = self.path
        if not url.lower().startswith("http://"):
            self.send_simple(400, "only absolute http:// URLs are proxied\n")
            return
        cached = load_cached(url)
        if cached is not None:
            meta, body = cached
            self.send_cached(meta, body, url)
            return
        try:
            meta, body = fetch_upstream(url)
        except urllib.error.HTTPError as exc:
            self.send_simple(exc.code, "upstream: %s\n" % exc.reason)
            return
        except Exception as exc:  # noqa: BLE001 - report anything to apt
            self.send_simple(502, "upstream failed: %s\n" % exc)
            return
        with LOCK:
            store_cached(url, meta, body)
        headers = dict(meta["headers"])
        headers["X-Cache"] = "MISS"
        total = len(body)
        self.send_response(meta["status"])
        for k, v in headers.items():
            if k.lower() not in ("content-length",):
                self.send_header(k, v)
        self.send_header("Content-Length", str(total))
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    # ---- verbs ---------------------------------------------------------
    def do_GET(self):
        self.handle_proxy()

    def do_HEAD(self):
        self.handle_proxy()

    def do_POST(self):
        self.send_simple(405, "read-only proxy\n")

    def do_CONNECT(self):
        host, _, port = self.path.partition(":")
        port = int(port or 443)
        try:
            upstream = socket.create_connection((host, port), timeout=30)
        except OSError as exc:
            self.send_simple(502, "connect failed: %s\n" % exc)
            return
        self.send_response(200, "Connection Established")
        self.end_headers()
        self.close_connection = True
        client = self.connection
        try:
            while True:
                chunk = client.recv(65536)
                if not chunk:
                    break
                upstream.sendall(chunk)
                data = upstream.recv(65536)
                if data:
                    client.sendall(data)
        except OSError:
            pass
        finally:
            upstream.close()


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def main():
    global CACHE_DIR, LOG_PATH
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=3142)
    ap.add_argument("--cache", default=os.path.join(here, "cache"))
    ap.add_argument("--log", default=os.path.join(here, "proxy.log"))
    args = ap.parse_args()
    CACHE_DIR = args.cache
    LOG_PATH = args.log
    os.makedirs(CACHE_DIR, exist_ok=True)
    server = Server(("0.0.0.0", args.port), Handler)
    print("umi-apt-proxy listening on 0.0.0.0:%d, cache %s" % (args.port, CACHE_DIR), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
