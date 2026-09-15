"""Assign an exact processed build to the existing internal group; no beta review."""
import json
import os
import sys
import urllib.parse
import urllib.request
from slack_release import apple, apple_token
from prepare_release import build_number

TARGETS = {
    'iphone': ('6809810244', '08b44746-1f96-4214-ab2a-71f58f3af05d'),
    'mac': ('6811774996', '89123d5e-d868-4e99-947d-274cb8065ac9'),
}

def main():
    if os.environ.get('GITHUB_REF') != 'refs/heads/main' or os.environ.get('GITHUB_ACTIONS') != 'true':
        raise ValueError('Only release main may assign builds')
    app, group = TARGETS[sys.argv[1]]
    number = build_number(os.environ['GITHUB_RUN_NUMBER'], os.environ['GITHUB_RUN_ATTEMPT'])
    token = apple_token()
    info = apple('betaGroups/' + group, token)['data']
    if not info['attributes']['isInternalGroup']:
        raise ValueError('Expected internal group')
    if apple('betaGroups/' + group + '/app', token)['data']['id'] != app:
        raise ValueError('Wrong group app')
    query = urllib.parse.urlencode({'filter[app]': app, 'filter[version]': number})
    builds = apple('builds?' + query, token)['data']
    if len(builds) != 1 or builds[0]['attributes']['processingState'] != 'VALID' or builds[0]['attributes'].get('expired'):
        raise ValueError('Expected one valid unexpired build')
    build = builds[0]
    path = 'betaGroups/' + group + '/relationships/builds'
    req = urllib.request.Request('https://api.appstoreconnect.apple.com/v1/' + path,
        data=json.dumps({'data': [{'type': 'builds', 'id': build['id']}]}).encode(),
        headers={'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'}, method='POST')
    with urllib.request.urlopen(req, timeout=30) as response:
        if response.status != 204: raise ValueError('Unexpected assignment response')
    print('Internal group assigned build ' + number + '. Testers must accept their invitation.')

if __name__ == '__main__':
    try: main()
    except Exception as error:
        raise SystemExit('Internal assignment failed: ' + type(error).__name__)
