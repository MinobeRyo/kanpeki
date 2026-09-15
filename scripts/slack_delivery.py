"""Reconcile both TestFlight platforms; update Slack only when Apple state changes."""
import json
import os
from pathlib import Path
import urllib.parse
import uuid
from datetime import datetime, timezone
from slack_release import gh, apple, apple_token, state_label, plain, post, request, brief
from prepare_release import build_number

PLATFORMS = (
    ('iPhone', '6809810244', 'fef3aa45-1839-492a-80c6-729735c12890', 'TESTFLIGHT_TESTER_URL'),
    ('Mac', '6811774996', '7d3f3f2e-7cb0-4123-a4df-2a1b52ef934b', 'MAC_TESTER_URL'),
)

def status(app, group, number, token):
    query = urllib.parse.urlencode({'filter[app]': app, 'filter[version]': number, 'limit': 10})
    builds = apple('builds?' + query, token)['data']
    if len(builds) != 1:
        return 'Apple側で対象ビルド未確認', '未確認'
    build = builds[0]
    detail = apple('builds/' + build['id'] + '/buildBetaDetail', token)['data']['attributes']
    version = apple('builds/' + build['id'] + '/preReleaseVersion', token)['data']['attributes']['version']
    path = 'betaGroups/' + group + '/relationships/builds?limit=200'
    found = False
    while path:
        page = apple(path, token)
        found |= any(item['id'] == build['id'] for item in page['data'])
        link = page.get('links', {}).get('next')
        prefix = 'https://api.appstoreconnect.apple.com/v1/'
        if link and not link.startswith(prefix):
            raise ValueError('Unexpected Apple pagination URL')
        path = link[len(prefix):] if link else None
    return state_label(build['attributes'], detail, found), version

def main():
    if os.environ.get('GITHUB_REF') != 'refs/heads/main':
        raise ValueError('Only trusted main may send release notifications')
    run_id = os.environ.get('RELEASE_RUN_ID')
    if run_id:
        run = gh('actions/runs/' + run_id)
    else:
        runs = gh('actions/workflows/testflight.yml/runs?branch=main&status=completed&per_page=1')['workflow_runs']
        if not runs:
            print('No completed release yet'); return
        run = runs[0]
    if run['head_branch'] != 'main' or run['path'] != '.github/workflows/testflight.yml' or run['status'] != 'completed':
        raise ValueError('Not a completed main release')
    # Older releases remain available but no longer need an hourly notification check.
    age = datetime.now(timezone.utc) - datetime.fromisoformat(run['updated_at'].replace('Z', '+00:00'))
    if age.days >= 30:
        print('No recent release to monitor'); return
    number = build_number(run['run_number'], run['run_attempt'])
    statefile = Path('.delivery-state/state.json')
    statefile.parent.mkdir(exist_ok=True)
    saved = json.loads(statefile.read_text()) if statefile.exists() else {}
    key = f'{run["id"]}/{run["run_attempt"]}'
    entry = saved.setdefault(key, {})
    token = apple_token()
    results = []
    for name, app, group, url_var in PLATFORMS:
        label, version = status(app, group, number, token)
        results.append((name, label, version, os.environ[url_var]))
    summary = f'カンペき build {number}／CD: {run["conclusion"]}\n' + '\n'.join(f'{name} {version}：{label}' for name, label, version, _ in results)
    payload = {'channel': os.environ['SLACK_CHANNEL_ID'], 'text': summary,
               'unfurl_links': False, 'unfurl_media': False,
               'blocks': [{'type': 'section', 'text': plain(summary)},
                          {'type': 'actions', 'elements': []}]}
    for name, _, _, url in results:
        parsed = urllib.parse.urlparse(url)
        if parsed.scheme != 'https' or parsed.netloc != 'testflight.apple.com' or not parsed.path.startswith('/join/'):
            raise ValueError('Invalid TestFlight URL')
        payload['blocks'][1]['elements'].append({'type': 'button', 'text': plain(name + ' TestFlight'), 'url': url})
    payload['blocks'][1]['elements'].append({'type': 'button', 'text': plain('配布ログ'), 'url': run['html_url']})
    def persist():
        statefile.write_text(json.dumps(saved))
    if entry.get('summary') != summary:
        if entry.get('ts'):
            payload['ts'] = entry['ts']
            result = request('https://slack.com/api/chat.update', os.environ['SLACK_BOT_TOKEN'], payload)
            if not result.get('ok'): raise ValueError('Slack update failed')
        else:
            payload['client_msg_id'] = str(uuid.uuid5(uuid.NAMESPACE_URL, key + '/delivery'))
            result = post(payload)
            entry['ts'] = result['ts']
        entry['summary'] = summary
        persist()
    if not entry.get('notes'):
        prs = [pr for pr in gh('commits/' + run['head_sha'] + '/pulls') if pr.get('merged_at') and pr['base']['ref'] == 'main']
        changes = '\n'.join('・' + brief(pr['title'], 65, 1) for pr in prs[:2]) or '変更内容は配布ログのコミットを確認してください。'
        post({'channel': os.environ['SLACK_CHANNEL_ID'], 'thread_ts': entry['ts'],
              'text': changes + '\nTestFlightで上記ビルドへ更新し、アイコンと起動を確認してください。',
              'client_msg_id': str(uuid.uuid5(uuid.NAMESPACE_URL, key + '/notes')),
              'unfurl_links': False, 'unfurl_media': False})
        entry['notes'] = True
        persist()
    print('Delivery status reconciled; unchanged states produce no new messages.')

if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        # HTTP responses, signing material and Slack tokens must not reach logs.
        raise SystemExit('Delivery notification failed: ' + type(error).__name__)
