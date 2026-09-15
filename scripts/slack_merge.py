#!/usr/bin/env python3
"""Notify merged main PRs using trusted workflow code and inert Slack text."""
import json
import os
from pathlib import Path
import re
import sys
import uuid
from slack_release import REPO, brief, plain, post, gh


def messages(pr, channel):
    if not re.fullmatch(r"[CG][A-Z0-9]+", channel):
        raise ValueError("Invalid channel")
    if not pr.get("merged") or pr.get("base", {}).get("ref") != "main":
        return None
    if pr.get("base", {}).get("repo", {}).get("full_name") != REPO:
        return None
    number = int(pr["number"])
    url = f"https://github.com/{REPO}/pull/{number}"
    title = brief(pr.get("title", ""), 65, 1) or "変更を統合しました"
    summary = f"マージ #{number}：{title}\nコード更新。アプリ配布とは別です。\n{url}"
    parent = {"channel": channel, "text": summary, "parse": "none",
              "unfurl_links": False, "unfurl_media": False,
              "client_msg_id": str(uuid.uuid5(uuid.NAMESPACE_URL, url + ":merge")),
              "blocks": [{"type": "section", "text": plain(summary, 200)}]}
    detail = brief(pr.get("body", ""), 180, 3) or "変更内容と確認事項はPRへ。"
    child = {"channel": channel, "text": "変更内容・確認事項", "parse": "none",
             "unfurl_links": False, "unfurl_media": False,
             "client_msg_id": str(uuid.uuid5(uuid.NAMESPACE_URL, url + ":merge-details")),
             "blocks": [{"type": "section", "text": plain(detail, 180)}]}
    return parent, child


def main():
    if os.environ.get("GITHUB_REPOSITORY") != REPO:
        raise ValueError("Unexpected repository")
    if os.environ.get("GITHUB_EVENT_NAME") == "workflow_dispatch":
        if os.environ.get("GITHUB_REF") != "refs/heads/main":
            raise ValueError("Dispatch only from main")
        number = int(os.environ["PR_NUMBER"])
    else:
        event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
        if event.get("action") != "closed" or not event.get("pull_request", {}).get("merged"):
            print("Not merged; skipped")
            return
        number = int(event["pull_request"]["number"])
    # Verify current GitHub state instead of trusting the event's prose.
    pair = messages(gh(f"pulls/{number}"), os.environ["SLACK_CHANNEL_ID"])
    if pair is None:
        raise ValueError("Not a merged PR for this main branch")
    parent, child = pair
    if os.environ.get("SLACK_PREVIEW") == "true":
        print(json.dumps(pair, ensure_ascii=False))
        return
    sent = post(parent)
    child["thread_ts"] = sent["ts"]
    reply = post(child)
    print("Slack merge notification and thread delivered: " + sent["ts"] + " / " + reply["ts"])


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        sys.exit("Merge notification failed: " + type(exc).__name__ + ". Check delivery before retrying.")
