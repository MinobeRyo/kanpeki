"""Slack CLI deploy hook: register the verified notification Bot in GitHub Secrets."""
import json
import os
import subprocess
import sys
import urllib.request


def main():
    token = os.environ.get('SLACK_BOT_TOKEN', '')
    if not token.startswith('xoxb-'):
        raise RuntimeError('Bot token unavailable')
    req = urllib.request.Request('https://slack.com/api/auth.test',
        headers={'Authorization': 'Bearer ' + token}, data=b'')
    with urllib.request.urlopen(req, timeout=30) as response:
        identity = json.load(response)
    if not identity.get('ok') or identity.get('team_id') != 'TENL4FM16' or not identity.get('bot_id'):
        raise RuntimeError('Unexpected Slack identity')
    env = {k: v for k, v in os.environ.items() if not k.startswith('SLACK_')}
    result = subprocess.run(['gh', 'secret', 'set', 'SLACK_BOT_TOKEN',
        '--repo', 'MinobeRyo/kanpeki'],
        input=token, text=True, capture_output=True, env=env)
    if result.returncode:
        raise RuntimeError('GitHub secret registration failed')
    print('Verified Slack Bot registered in repository SLACK_BOT_TOKEN. Notifications remain disabled until channel setup.')


if __name__ == '__main__':
    try:
        main()
    except Exception:
        sys.exit('Secret registration failed; no credential values printed. Check authentication and retry deliberately.')
