#!/usr/bin/env python3
"""Forward authorized team.py issue reports; never interpret report text as commands."""
import json
import os
from pathlib import Path
import re
import sys
import uuid
from slack_release import post, plain, app_actions, discover_mac_download, brief

REPO='MinobeRyo/kanpeki'
TEAM={'takurateruyoshi','ini-ei','MinobeRyo','mao-sonobe'}
PATTERN=re.compile(r'^## (todo|doing|blocked|review|done) · @([A-Za-z0-9-]+)\n')

def payload(event,channel):
    if event.get('action')!='created' or event.get('repository',{}).get('full_name')!=REPO:
        return None
    issue=event.get('issue',{});comment=event.get('comment',{})
    if 'pull_request' in issue:return None
    author=comment.get('user',{}).get('login')
    if author not in TEAM or comment.get('author_association') not in ('OWNER','MEMBER','COLLABORATOR'):
        return None
    body=comment.get('body','');match=PATTERN.match(body)
    if not match or match.group(2)!=author or not re.search(r'\nUpdate-id: `[a-f0-9]{32}`\n',body):return None
    if not re.fullmatch(r'[CG][A-Z0-9]+',channel):raise ValueError('Invalid channel')
    number=int(issue['number']);cid=int(comment['id'])
    url=f'https://github.com/{REPO}/issues/{number}#issuecomment-{cid}'
    summary=f'AI進捗 #{number} · {author} · {match.group(1)}'
    content=body.split('Update-id:',1)[1].split('\n',1)[1]
    excerpt=brief(content,200,3) or '詳細はIssueを確認してください。'
    # Plain text keeps @channel, Slack mention syntax, and links in untrusted text inert.
    return {'channel':channel,'text':summary,'unfurl_links':False,'unfurl_media':False,
        'client_msg_id':str(uuid.uuid5(uuid.NAMESPACE_URL,url)),
        'blocks':[{'type':'header','text':plain(summary,150)},
                  {'type':'section','text':plain(issue.get('title',''),80)},
                  {'type':'section','text':plain(excerpt,200)},
                  {'type':'actions','elements':[{'type':'button','text':plain('詳細を開く',70),'url':url}]+app_actions()}]}

def main():
    event=json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
    data=payload(event,os.environ['SLACK_CHANNEL_ID'])
    if data is not None:
        discover_mac_download()
        data=payload(event,os.environ['SLACK_CHANNEL_ID'])
    if data is None:print('Not an authorized team progress report; skipped.');return
    result=post(data)
    print('Progress message posted; ts='+result['ts'])

if __name__=='__main__':
    try:main()
    except Exception as e:
        sys.exit('Progress forwarding failed: '+type(e).__name__+'. Check Slack delivery before retrying; no automatic retry performed.')
