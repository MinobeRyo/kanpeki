"""Authenticated, memory-only LAN development server (Python standard library)."""
from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import hmac
import json
import secrets
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from .analysis import build_report, read_audio, validate_slides

MAX_BODY = 40 * 1024 * 1024


class JobStore:
    def __init__(self, executable=None, model=None):
        self.executable, self.model = executable, model
        self.jobs = {}
        self.lock = threading.Lock()
        self.executor = ThreadPoolExecutor(max_workers=1)

    def submit(self, identifier, audio, events):
        duration = len(read_audio(audio)) / 16000
        events = validate_slides(events, duration)
        digest = hashlib.sha256(audio + json.dumps(events, sort_keys=True).encode()).hexdigest()
        with self.lock:
            now = time.monotonic()
            self.jobs = {key: value for key, value in self.jobs.items() if value["status"] in ("queued", "processing") or now - value["created"] < 3600}
            existing = self.jobs.get(identifier)
            if existing:
                if existing["digest"] != digest:
                    raise ValueError("同じ発表IDに異なる録音が送られました。新しいIDで送信してください。")
                return
            if len(self.jobs) >= 20:
                raise OverflowError("結果の上限に達しました。不要な結果を削除してください。")
            if sum(j["status"] in ("queued", "processing") for j in self.jobs.values()) >= 2:
                raise OverflowError("分析中です。少し待ってから再送してください。")
            self.jobs[identifier] = {"id": identifier, "status": "queued", "created": now, "digest": digest}
        self.executor.submit(self._run, identifier, audio, events)

    def _run(self, identifier, audio, events):
        with self.lock:
            self.jobs[identifier]["status"] = "processing"
        try:
            report = build_report(audio, events, self.executable, self.model)
            update = {"status": "complete", "report": report}
        except Exception:
            update = {"status": "failed", "error": "分析に失敗しました。音声形式とMacの設定を確認してください。"}
        with self.lock:
            self.jobs[identifier].update(update)

    def get(self, identifier):
        with self.lock:
            job = self.jobs.get(identifier)
            if job and job["status"] not in ("queued", "processing") and time.monotonic() - job["created"] >= 3600:
                del self.jobs[identifier]
                return None
            return {key: value for key, value in job.items() if key not in ("created", "digest")} if job else None

    def expire(self):
        with self.lock:
            now = time.monotonic()
            self.jobs = {key: value for key, value in self.jobs.items() if value["status"] in ("queued", "processing") or now - value["created"] < 3600}

    def delete(self, identifier):
        with self.lock:
            job = self.jobs.get(identifier)
            if not job:
                return False
            if job["status"] in ("queued", "processing"):
                raise ValueError("分析が終了してから削除してください。")
            del self.jobs[identifier]
            return True


class AudioServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, token, store):
        self.token, self.store = token, store
        super().__init__(address, Handler)

    def service_actions(self):
        self.store.expire()


class Handler(BaseHTTPRequestHandler):
    server_version = "KanpekiAudio/0.1"

    def setup(self):
        super().setup()
        self.connection.settimeout(30)

    def log_message(self, format, *args):
        pass  # No transcript, authorization header or user data in access logs.

    def respond(self, status, body):
        payload = json.dumps(body, ensure_ascii=False, allow_nan=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(payload)
        self.close_connection = True

    def authorize(self):
        expected = "Bearer " + self.server.token
        if not hmac.compare_digest(self.headers.get("Authorization", "").encode(), expected.encode()):
            self.respond(401, {"error": "接続コードが一致しません。Macに表示されたコードを確認してください。"})
            return False
        return True

    def job_id(self):
        pieces = self.path.split("/")
        if len(pieces) != 4 or pieces[1:3] != ["v1", "sessions"]:
            return None
        try:
            return str(uuid.UUID(pieces[3]))
        except ValueError:
            return None

    def do_GET(self):
        if not self.authorize():
            return
        if self.path == "/health":
            self.respond(200, {"status": "ok", "schema_version": 1, "transcription_ready": bool(self.server.store.executable and self.server.store.model)})
            return
        job = self.server.store.get(self.job_id())
        self.respond(200 if job else 404, job or {"error": "結果が見つかりません。Macを再起動した場合や1時間経過後は再送してください。"})

    def do_POST(self):
        if not self.authorize():
            return
        if self.path != "/v1/sessions":
            self.respond(404, {"error": "存在しないAPIです。"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= MAX_BODY:
                self.respond(413, {"error": "送信サイズは40 MiB以内にしてください。"})
                return
            if self.headers.get("Transfer-Encoding"):
                raise ValueError("Content-Lengthを指定してください。")
            body = self.rfile.read(length)
            if len(body) != length:
                raise ValueError("音声の受信が途中で終了しました。再送してください。")
            payload = json.loads(body)
            if not isinstance(payload, dict):
                raise ValueError("JSONオブジェクトを送ってください。")
            identifier = str(uuid.UUID(payload["id"]))
            audio = base64.b64decode(payload["audio_base64"], validate=True)
            self.server.store.submit(identifier, audio, payload.get("slide_events", []))
            self.respond(202, {"id": identifier, "status": "accepted"})
        except OverflowError as error:
            self.respond(429, {"error": str(error)})
        except (ValueError, TypeError, KeyError, binascii.Error, AttributeError) as error:
            self.respond(400, {"error": str(error) if isinstance(error, ValueError) else "送信データの形式が不正です。"})

    def do_DELETE(self):
        if not self.authorize():
            return
        try:
            removed = self.server.store.delete(self.job_id())
            self.respond(200 if removed else 404, {"deleted": removed})
        except ValueError as error:
            self.respond(409, {"error": str(error)})


def main():
    parser = argparse.ArgumentParser(description="カンペき 音声分析・Macサーバー")
    parser.add_argument("--host", default="127.0.0.1", help="iPhone接続時は信頼できるLANで --host 0.0.0.0 を指定")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--whisper-cli")
    parser.add_argument("--model")
    args = parser.parse_args()
    if bool(args.whisper_cli) != bool(args.model):
        parser.error("--whisper-cli と --model を両方指定してください。")
    if args.model and (not Path(args.model).is_file() or not Path(args.whisper_cli).is_file()):
        parser.error("モデルまたはwhisper-cliが見つかりません。")
    token = secrets.token_urlsafe(12)
    store = JobStore(args.whisper_cli, args.model)
    server = AudioServer((args.host, args.port), token, store)
    print(f"カンペき 音声分析 http://{args.host}:{args.port}", flush=True)
    print(f"接続コード: {token}", flush=True)
    print("文字起こし: " + ("有効" if args.model else "未設定（低音量区間のみ分析）"), flush=True)
    print("音声は一時処理後に削除。結果はメモリ内に最長1時間。HTTP開発用・信頼できるLAN内で使用。", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        store.executor.shutdown(wait=True)


if __name__ == "__main__":
    main()
