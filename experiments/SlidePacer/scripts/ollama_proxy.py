"""Loopback-only adapter for SlidePacer behind Tailscale Serve (no extra packages)."""
import argparse
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import socket

MAX_REQUEST = 2 * 1024 * 1024
MAX_RESPONSE = 8 * 1024 * 1024


def handler_for(upstream_port):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass  # Do not log slide text, prompts, or caller identity.

        def reply(self, status, data, content_type="application/json"):
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            try:
                self.wfile.write(data)
            except (BrokenPipeError, ConnectionResetError):
                pass

        def fail(self, status, message):
            self.reply(status, json.dumps({"error": message}).encode())

        def do_GET(self):
            if self.path not in ("/api/version", "/api/tags"):
                return self.fail(404, "Unsupported endpoint")
            self.forward(None)

        def do_POST(self):
            if self.path != "/api/generate":
                return self.fail(404, "Unsupported endpoint")
            if self.headers.get("Transfer-Encoding"):
                return self.fail(400, "Use Content-Length, not Transfer-Encoding")
            lengths = self.headers.get_all("Content-Length", [])
            if len(lengths) != 1 or not lengths[0].isascii() or not lengths[0].isdigit():
                return self.fail(411, "A single Content-Length is required")
            length = int(lengths[0])
            if length > MAX_REQUEST:
                return self.fail(413, "Request too large")
            body = self.rfile.read(length)
            if len(body) != length:
                return self.fail(400, "Incomplete request")
            try:
                payload = json.loads(body)
            except (ValueError, UnicodeDecodeError):
                return self.fail(400, "Invalid JSON")
            if not isinstance(payload, dict) or payload.get("stream") is not False:
                return self.fail(400, "SlidePacer proxy requires stream: false")
            self.forward(body)

        def forward(self, body):
            connection = http.client.HTTPConnection("127.0.0.1", upstream_port, timeout=300)
            try:
                # HTTPConnection creates Host: 127.0.0.1:<port>; never forward the
                # public-facing Host, cookies, or Tailscale identity headers.
                headers = {"Content-Type": "application/json"} if body is not None else {}
                connection.request(self.command, self.path, body=body, headers=headers)
                response = connection.getresponse()
                data = response.read(MAX_RESPONSE + 1)
                if len(data) > MAX_RESPONSE:
                    return self.fail(502, "Upstream response too large")
                self.reply(response.status, data, response.getheader("Content-Type", "application/json"))
            except (TimeoutError, socket.timeout):
                self.fail(504, "Ollama timed out")
            except (OSError, http.client.HTTPException):
                self.fail(502, "Cannot reach local Ollama")
            finally:
                connection.close()

        def setup(self):
            super().setup()
            self.connection.settimeout(30)

    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=11435)
    parser.add_argument("--upstream-port", type=int, default=11434)
    args = parser.parse_args()
    if not all(1 <= port <= 65535 for port in (args.port, args.upstream_port)):
        parser.error("Ports must be between 1 and 65535")
    if args.port == args.upstream_port:
        parser.error("Proxy and Ollama ports must differ")
    with ThreadingHTTPServer(("127.0.0.1", args.port), handler_for(args.upstream_port)) as server:
        print("SlidePacer proxy: localhost:%d -> localhost:%d" % (args.port, args.upstream_port), flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
