#!/usr/bin/env python3
"""OpenAI-compatible shim in front of the prima.cpp llama-server.

The prima.cpp llama.cpp base rejects request fields that
newer clients send by default (``tools``, ``tool_choice``,
``response_format`` and friends) with a 500. GBrain, Pi and
QM all send them. This proxy strips those fields, rewrites
the model id to what the upstream serves, and forwards
everything else unchanged, including SSE streams.

    python3 compat_proxy.py --listen 0.0.0.0:8088 \
        --upstream http://127.0.0.1:8080 --alias qwen2.5-7b
"""

import argparse
import http.client
import json
import sys
from http.server import BaseHTTPRequestHandler
from http.server import ThreadingHTTPServer
from urllib.parse import urlparse

STRIP_FIELDS = (
    "tools",
    "tool_choice",
    "parallel_tool_calls",
    "response_format",
    "stream_options",
    "functions",
    "function_call",
    "reasoning_effort",
    "reasoning",
    "store",
    "metadata",
    "service_tier",
)

HOP_HEADERS = {
    "connection",
    "keep-alive",
    "transfer-encoding",
    "content-length",
    "host",
    "accept-encoding",
}


class Upstream:
    def __init__(self, url, alias, served_model):
        parsed = urlparse(url)
        self.host = parsed.hostname
        self.port = parsed.port
        self.alias = alias
        self.served_model = served_model

    def connection(self):
        return http.client.HTTPConnection(self.host, self.port, timeout=600)


UPSTREAM = None


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))

    def _forward(self, method, body):
        headers = {}
        for key, value in self.headers.items():
            if key.lower() in HOP_HEADERS:
                continue
            headers[key] = value
        if body is not None:
            headers["Content-Length"] = str(len(body))
        headers["Connection"] = "close"
        conn = UPSTREAM.connection()
        conn.request(method, self.path, body=body, headers=headers)
        response = conn.getresponse()
        self.send_response(response.status)
        streaming = False
        for key, value in response.getheaders():
            lowered = key.lower()
            if lowered in ("transfer-encoding", "connection", "content-length"):
                continue
            if lowered == "content-type" and "text/event-stream" in value:
                streaming = True
            self.send_header(key, value)
        if streaming:
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            while True:
                chunk = response.read(4096)
                if not chunk:
                    break
                self.wfile.write(b"%x\r\n%s\r\n" % (len(chunk), chunk))
                self.wfile.flush()
            self.wfile.write(b"0\r\n\r\n")
            self.wfile.flush()
        else:
            payload = response.read()
            payload = self._rewrite_response(payload)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        conn.close()

    def _rewrite_response(self, payload):
        if not UPSTREAM.alias:
            return payload
        try:
            data = json.loads(payload)
        except ValueError:
            return payload
        if isinstance(data, dict) and data.get("object") == "list":
            for item in data.get("data", []):
                if isinstance(item, dict) and "id" in item:
                    item["id"] = UPSTREAM.alias
        elif isinstance(data, dict) and "model" in data:
            data["model"] = UPSTREAM.alias
        return json.dumps(data).encode("utf-8")

    def _rewrite_request(self, body):
        try:
            data = json.loads(body)
        except ValueError:
            return body
        if not isinstance(data, dict):
            return body
        for field in STRIP_FIELDS:
            data.pop(field, None)
        if UPSTREAM.served_model:
            data["model"] = UPSTREAM.served_model
        messages = data.get("messages")
        if isinstance(messages, list):
            data["messages"] = _flatten_messages(messages)
        return json.dumps(data).encode("utf-8")

    def do_GET(self):
        self._forward("GET", None)

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length)
        if self.path.startswith("/v1/chat/completions") or self.path.startswith(
            "/v1/completions"
        ):
            body = self._rewrite_request(body)
        self._forward("POST", body)


def _flatten_messages(messages):
    """Collapse content-part arrays into plain strings.

    The upstream chat template expects string content; newer
    clients send ``[{"type": "text", "text": ...}]`` parts.
    """
    flattened = []
    for message in messages:
        if not isinstance(message, dict):
            continue
        role = message.get("role")
        if role == "tool":
            role = "user"
        content = message.get("content")
        if isinstance(content, list):
            parts = []
            for part in content:
                if isinstance(part, dict) and part.get("type") == "text":
                    parts.append(str(part.get("text", "")))
            content = "\n".join(parts)
        if content is None:
            content = ""
        flattened.append({"role": role, "content": content})
    return flattened


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--listen", default="0.0.0.0:8088")
    parser.add_argument("--upstream", default="http://127.0.0.1:8080")
    parser.add_argument("--alias", default="qwen2.5-7b")
    parser.add_argument(
        "--served-model",
        default="",
        help="model id to send upstream; empty keeps the client's id",
    )
    args = parser.parse_args()
    global UPSTREAM
    UPSTREAM = Upstream(args.upstream, args.alias, args.served_model)
    host, port = args.listen.rsplit(":", 1)
    server = ThreadingHTTPServer((host, int(port)), Handler)
    sys.stderr.write("compat proxy on %s -> %s\n" % (args.listen, args.upstream))
    server.serve_forever()


if __name__ == "__main__":
    main()
