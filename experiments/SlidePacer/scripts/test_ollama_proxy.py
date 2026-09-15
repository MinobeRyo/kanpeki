"""Verify routing and Host rewriting against a fake local upstream; no model needed."""
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import threading
import unittest
from ollama_proxy import handler_for, MAX_REQUEST


class ProxyTests(unittest.TestCase):
    def setUp(self):
        self.seen = []
        seen = self.seen

        class Upstream(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                seen.append((self.path, self.headers.get("Host"), b"", self.headers.get("Cookie")))
                data = b'{"version":"test"}'
                self.send_response(200)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def do_POST(self):
                body = self.rfile.read(int(self.headers["Content-Length"]))
                seen.append((self.path, self.headers.get("Host"), body, self.headers.get("Cookie")))
                status = 503 if json.loads(body).get("prompt") == "busy" else 200
                data = b'{"error":"busy"}' if status == 503 else b'{"response":"4","done":true}'
                self.send_response(status)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

        self.upstream = ThreadingHTTPServer(("127.0.0.1", 0), Upstream)
        self.proxy = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(self.upstream.server_port))
        for server in (self.upstream, self.proxy):
            threading.Thread(target=server.serve_forever, daemon=True).start()

    def tearDown(self):
        for server in (self.proxy, self.upstream):
            server.shutdown()
            server.server_close()

    def request(self, method="GET", path="/api/version", body=None, extra=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.proxy.server_port, timeout=5)
        headers = {"Host": "team.example.ts.net", "Cookie": "not-forwarded"}
        headers.update(extra or {})
        connection.request(method, path, body, headers)
        response = connection.getresponse()
        result = response.status, response.read()
        connection.close()
        return result

    def test_host_rewritten_without_forwarding_cookies(self):
        status, data = self.request()
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(data)["version"], "test")
        self.assertEqual(self.seen[0][1], "127.0.0.1:%d" % self.upstream.server_port)
        self.assertIsNone(self.seen[0][3])

    def test_generate_body_preserved(self):
        payload = json.dumps({"stream": False, "prompt": "条件を保持", "format": {"type": "object"}}).encode()
        status, data = self.request("POST", "/api/generate", payload)
        self.assertEqual(status, 200)
        self.assertTrue(json.loads(data)["done"])
        self.assertEqual(self.seen[0][2], payload)

    def test_upstream_busy_is_preserved(self):
        status, data = self.request("POST", "/api/generate", b'{"stream":false,"prompt":"busy"}')
        self.assertEqual(status, 503)
        self.assertEqual(json.loads(data)["error"], "busy")

    def test_model_management_not_forwarded(self):
        self.assertEqual(self.request("POST", "/api/pull", b'{}')[0], 404)
        self.assertEqual(self.request("GET", "/api/version?redirect=elsewhere")[0], 404)
        self.assertEqual(self.seen, [])

    def test_streaming_and_invalid_json_rejected(self):
        for body in (b'{"stream":true}', b'{}', b'[]', b'broken'):
            self.assertEqual(self.request("POST", "/api/generate", body)[0], 400)
        self.assertEqual(self.seen, [])

    def test_large_request_rejected_before_forwarding(self):
        self.assertEqual(self.request("POST", "/api/generate", b'', {"Content-Length": str(MAX_REQUEST + 1)})[0], 413)
        self.assertEqual(self.seen, [])


if __name__ == "__main__":
    unittest.main()
