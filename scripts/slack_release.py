#!/usr/bin/env python3
"""Post a CD result and change notes to Slack, without claiming review approval."""
import base64
import json
import os
from pathlib import Path
import re
import sys
import urllib.parse
import urllib.request
import uuid

REPO = 'MinobeRyo/kanpeki'
APP = '6809810244'

def request(url, token, body=None):
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None,
        headers={'Authorization':'Bearer '+token, 'Content-Type':'application/json', 'Accept':'application/json'})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)

def gh(path):
    return request('https://api.github.com/repos/'+REPO+'/'+path, os.environ['GH_TOKEN'])

def apple_token():
    import time
    from cryptography.hazmat.primitives.serialization import load_pem_private_key
    from cryptography.hazmat.primitives.asymmetric import ec, utils
    from cryptography.hazmat.primitives import hashes
    enc=lambda b:base64.urlsafe_b64encode(b).rstrip(b'=')
    now=int(time.time())
    head={'alg':'ES256','kid':os.environ['ASC_KEY_ID'],'typ':'JWT'}
    claims={'iss':os.environ['ASC_ISSUER_ID'],'iat':now,'exp':now+300,'aud':'appstoreconnect-v1'}
    msg=enc(json.dumps(head).encode())+b'.'+enc(json.dumps(claims).encode())
    key=load_pem_private_key(base64.b64decode(os.environ['ASC_KEY_P8_BASE64'],validate=True),password=None)
    r,s=utils.decode_dss_signature(key.sign(msg,ec.ECDSA(hashes.SHA256())))
    return (msg+b'.'+enc(r.to_bytes(32,'big')+s.to_bytes(32,'big'))).decode()

def apple(path,token):
    return request('https://api.appstoreconnect.apple.com/v1/'+path,token)

def state_label(build, detail, in_group):
    if not build:return '対象ビルドはApple側で未確認（未アップロードとは断定しません）'
    if build.get('expired'):return '期限切れ・利用不可'
    if build.get('processingState') != 'VALID':return 'Apple処理状態: '+str(build.get('processingState','不明'))
    state=detail.get('externalBuildState','UNKNOWN')
    if state=='IN_BETA_TESTING' and in_group:return '指定の外部グループでテスト可能（招待受諾が必要）'
    labels={'WAITING_FOR_BETA_REVIEW':'Apple審査待ち','IN_BETA_REVIEW':'Apple審査中','BETA_REJECTED':'Apple審査で却下','READY_FOR_BETA_SUBMISSION':'アップロード済み・外部審査未提出','BETA_APPROVED':'Apple承認済み・配布状態を要確認','IN_BETA_TESTING':'外部テスト可能だが指定グループへの割当は未確認'}
    return labels.get(state,'外部配布状態: '+state)

def plain(text,limit=2800):
    return {'type':'plain_text','text':str(text)[:limit] or '記載なし','emoji':False}

def brief(text, limit=200, lines=3):
    """Bound Slack prose; keep full context at the linked source."""
    cleaned=[]
    in_code=False
    for line in str(text).splitlines():
        line=line.strip()
        if line.startswith('```'):
            in_code=not in_code
            continue
        if in_code or not line or line.startswith(('#', 'Branch:', 'Session:', 'Update-id:')):
            continue
        cleaned.append(line)
    selected=cleaned[:lines]
    value='\n'.join(selected)
    truncated=len(cleaned)>lines or len(value)>limit
    return value[:limit-1]+'…' if truncated else value

def discover_mac_download():
    # A configured Mac TestFlight link is preferred over legacy DMG discovery.
    if os.environ.get('MAC_TESTER_URL'):
        return
    # Only published Mac releases with the expected asset are advertised.
    releases=gh('releases?per_page=30')
    for release in releases:
        if release.get('draft') or not re.fullmatch(r'mac-[a-f0-9]{40}',release.get('tag_name','')):
            continue
        for asset in release.get('assets',[]):
            if asset.get('name')=='KanpekiMac.dmg' and asset.get('state')=='uploaded':
                os.environ['MAC_TESTER_URL']=asset['browser_download_url']
                return

def app_actions():
    actions=[]
    test_url=os.environ.get('TESTFLIGHT_TESTER_URL','')
    if test_url:
        parsed=urllib.parse.urlparse(test_url)
        if parsed.scheme!='https' or parsed.hostname!='testflight.apple.com' or not parsed.path.startswith('/join/') or parsed.username or parsed.password:
            raise ValueError('Invalid tester URL')
        actions.append({'type':'button','text':plain('iPhoneで試す',70),'url':test_url})
    mac_url=os.environ.get('MAC_TESTER_URL','')
    if mac_url:
        parsed=urllib.parse.urlparse(mac_url)
        is_testflight = parsed.netloc == 'testflight.apple.com' and parsed.path.startswith('/join/')
        is_release = parsed.netloc == 'github.com' and parsed.path.startswith('/'+REPO+'/releases/')
        if parsed.scheme != 'https' or parsed.username or parsed.password or not (is_testflight or is_release):
            raise ValueError('Invalid Mac distribution URL')
        label = 'Macで試す' if is_testflight else 'Mac版をダウンロード'
        actions.append({'type':'button','text':plain(label,70),'url':mac_url})
    return actions

def messages(version, number, state, run, prs, notes, channel):
    title=f'カンペき {version} ({number})'
    actions=app_actions()+[{'type':'button','text':plain('配布・CIの詳細',70),'url':run['html_url']},
        {'type':'button','text':plain('変更一覧',70),'url':f'https://github.com/{REPO}/commit/{run["head_sha"]}'}]
    status=f'{state}\nCD: {run["conclusion"]}（通知時点）'
    parent={'channel':channel,'text':f'{title}\n{status}', 'unfurl_links':False,'unfurl_media':False,
        'blocks':[{'type':'header','text':plain(title,150)},
                  {'type':'section','text':plain(status)},
                  {'type':'actions','elements':actions}]}
    changes=[f'・#{int(pr["number"])} '+brief(pr['title'],60,1) for pr in prs[:3]]
    if len(prs)>3: changes.append('ほかの変更は「変更一覧」へ')
    if not prs: changes=['変更内容は「変更一覧」へ']
    # PR titles describe user-visible changes; detailed bodies stay on GitHub.
    # Prefer the explicit check request in release notes over setup instructions.
    checks=[line for line in notes.splitlines() if '確認してください' in line]
    check=brief('\n'.join(checks) if checks else notes,80,1) or '詳細を開いて確認してください。'
    text='\n'.join(changes)+f'\n確認：{check}\n不具合はこのスレッドへ。'
    blocks=[{'type':'section','text':plain(text,400)}]
    if prs:
        blocks.append({'type':'actions','elements':[
            {'type':'button','text':plain(f'PR #{int(pr["number"])}',70),
             'url':f'https://github.com/{REPO}/pull/{int(pr["number"])}'} for pr in prs[:3]]})
    return parent,{'channel':channel,'text':'変更点と確認事項（詳細はPRへ）','blocks':blocks,'unfurl_links':False,'unfurl_media':False}

def post(payload):
    result=request('https://slack.com/api/chat.postMessage',os.environ['SLACK_BOT_TOKEN'],payload)
    if not result.get('ok'):
        # Never print server payloads, tokens, or PR bodies to CI logs.
        raise ValueError('Slack API rejected message: '+str(result.get('error','unknown')))
    return result

def main():
    if os.environ.get('GITHUB_REF')!='refs/heads/main':raise ValueError('Notifications only from main')
    channel=os.environ.get('SLACK_CHANNEL_ID','C000000') if os.environ.get('SLACK_PREVIEW')=='true' else os.environ['SLACK_CHANNEL_ID']
    if not re.fullmatch(r'[CG][A-Z0-9]+',channel):raise ValueError('Invalid Slack channel ID')
    run=gh('actions/runs/'+os.environ['RELEASE_RUN_ID'])
    if run['head_branch']!='main' or run['path']!='.github/workflows/testflight.yml' or run['status']!='completed':
        raise ValueError('Not a completed main TestFlight CD run')
    number=f'{run["run_number"]}.{run["run_attempt"]}.0'
    token=apple_token()
    query=urllib.parse.urlencode({'filter[app]':APP,'filter[version]':number,'limit':10})
    builds=apple('builds?'+query,token)['data']
    build=builds[0] if len(builds)==1 else None
    version='バージョン未確認';detail={};in_group=False
    if build:
        detail=apple('builds/'+build['id']+'/buildBetaDetail',token)['data']['attributes']
        version=apple('builds/'+build['id']+'/preReleaseVersion',token)['data']['attributes']['version']
        group_id=os.environ['TESTFLIGHT_EXTERNAL_GROUP_ID']
        members=apple('betaGroups/'+group_id+'/relationships/builds?limit=200',token)['data']
        in_group=any(b['id']==build['id'] for b in members)
    state=state_label(build['attributes'] if build else None,detail,in_group)
    prs=[p for p in gh('commits/'+run['head_sha']+'/pulls') if p.get('merged_at') and p['base']['ref']=='main']
    notes_blob=gh('contents/docs/TESTFLIGHT_NOTES.txt?ref='+run['head_sha'])
    notes=base64.b64decode(notes_blob['content']).decode()
    discover_mac_download()
    parent,reply=messages(version,number,state,run,prs,notes,channel)
    if os.environ.get('SLACK_PREVIEW')=='true':
        print(json.dumps({'parent':parent,'reply':reply},ensure_ascii=False,indent=2))
        return
    # An uncertain POST is not retried automatically; avoid duplicate notifications.
    seed=f'{run["id"]}/{run["run_attempt"]}'
    parent['client_msg_id']=str(uuid.uuid5(uuid.NAMESPACE_URL,seed+'/parent'))
    result=post(parent)
    print('Slack parent posted; thread_ts='+result['ts'])
    reply['thread_ts']=result['ts'];reply['client_msg_id']=str(uuid.uuid5(uuid.NAMESPACE_URL,seed+'/reply'))
    post(reply)
    print('Slack change-notes reply posted.')

if __name__=='__main__':
    try:main()
    except Exception as e:
        print('Notification not completed: '+type(e).__name__+'. Check configuration and any already posted parent before retrying.',file=sys.stderr)
        sys.exit(1)
