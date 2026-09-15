import base64
import json
import threading
import time
import unittest
import urllib.error
import urllib.request
import uuid

from kanpeki_audio.server import AudioServer, JobStore
from test_analysis import wav


class APITests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.store = JobStore()
        cls.server = AudioServer(("127.0.0.1", 0), "test-only-code", cls.store)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown(); cls.server.server_close(); cls.thread.join()
        cls.store.executor.shutdown()

    def request(self, path, payload=None, token="test-only-code", method=None):
        body = json.dumps(payload).encode() if payload is not None else None
        request = urllib.request.Request(self.base + path, data=body, headers={"Authorization": "Bearer " + token}, method=method)
        try:
            with urllib.request.urlopen(request, timeout=5) as response:
                return response.status, json.load(response)
        except urllib.error.HTTPError as error:
            return error.code, json.load(error)

    def submission(self):
        return {"id": str(uuid.uuid4()), "audio_base64": base64.b64encode(wav()).decode(), "slide_events": [{"at": 0, "slide": 1}, {"at": 2, "slide": 2}]}

    def await_job(self, identifier):
        for _ in range(100):
            status, job = self.request("/v1/sessions/" + identifier)
            if job.get("status") in ("complete", "failed"):
                return job
            time.sleep(.01)
        self.fail("Job did not finish")

    def test_authorization_required_on_all_endpoints(self):
        for path, method in [("/health", "GET"), ("/v1/sessions", "POST"), ("/v1/sessions/" + str(uuid.uuid4()), "DELETE")]:
            self.assertEqual(self.request(path, token="wrong", method=method)[0], 401)

    def test_actual_upload_poll_and_delete(self):
        payload = self.submission()
        self.assertEqual(self.request("/v1/sessions", payload)[0], 202)
        job = self.await_job(payload["id"])
        self.assertEqual(job["status"], "complete")
        self.assertEqual(job["report"]["quiet_seconds"], 2)
        self.assertEqual(len(job["report"]["slides"]), 2)
        self.assertNotIn("digest", job)
        self.assertNotIn("audio_base64", job)
        path = "/v1/sessions/" + payload["id"]
        self.assertEqual(self.request(path, method="DELETE")[0], 200)
        self.assertEqual(self.request(path)[0], 404)

    def test_retry_is_idempotent_and_changed_payload_rejected(self):
        payload = self.submission()
        self.assertEqual(self.request("/v1/sessions", payload)[0], 202)
        self.await_job(payload["id"])
        self.assertEqual(self.request("/v1/sessions", payload)[0], 202)
        payload["slide_events"] = []
        self.assertEqual(self.request("/v1/sessions", payload)[0], 400)

    def test_malformed_requests(self):
        for payload in [[], {}, {"id": "bad", "audio_base64": "!"}, {"id": str(uuid.uuid4()), "audio_base64": "!"}]:
            self.assertEqual(self.request("/v1/sessions", payload)[0], 400)

    def test_health_reports_missing_model(self):
        status, body = self.request("/health")
        self.assertEqual(status, 200)
        self.assertFalse(body["transcription_ready"])

    def test_expiry_removes_results_without_another_client_request(self):
        isolated = JobStore()
        isolated.jobs["old"] = {"created": time.monotonic() - 3601, "status": "complete"}
        isolated.expire()
        self.assertEqual(isolated.jobs, {})
        isolated.executor.shutdown()


if __name__ == "__main__":
    unittest.main()
