#!/usr/bin/env python3
"""Validate secrets and install a narrowly scoped App Store profile on an ephemeral runner."""
import base64
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys

TEAM = 'XYJX89KRDM'
BUNDLE = 'jp.kanpeki.prototype.phone'
REQUIRED = ('ASC_KEY_ID','ASC_ISSUER_ID','ASC_KEY_P8_BASE64','IOS_DISTRIBUTION_P12_BASE64','IOS_DISTRIBUTION_P12_PASSWORD','IOS_APPSTORE_PROFILE_BASE64','TESTFLIGHT_EXTERNAL_GROUP')

def build_number(run, attempt):
    run, attempt = 1000 + int(run), int(attempt)
    if not 1001 <= run <= 9999 or not 1 <= attempt <= 99:
        raise ValueError('Build number range exceeded; update version strategy before releasing.')
    return f'{run}.{attempt}.0'

def validate_profile(p, now=None):
    now = now or datetime.now(timezone.utc)
    expiration = p['ExpirationDate']
    if expiration.tzinfo is None:
        expiration = expiration.replace(tzinfo=timezone.utc)
    ent = p.get('Entitlements', {})
    if p.get('TeamIdentifier') != [TEAM] or ent.get('application-identifier') != f'{TEAM}.{BUNDLE}':
        raise ValueError('Profile belongs to a different team or application.')
    if ent.get('get-task-allow') or p.get('ProvisionedDevices') or p.get('ProvisionsAllDevices') or not ent.get('beta-reports-active'):
        raise ValueError('An App Store distribution profile is required.')
    if expiration <= now:
        raise ValueError('Provisioning profile expired.')
    uuid = p.get('UUID','')
    if not re.fullmatch(r'[A-Fa-f0-9-]{36}', uuid):
        raise ValueError('Invalid profile UUID.')
    return uuid

def release_dir():
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        raise ValueError('Use only in the GitHub-hosted release job, not a developer login keychain.')
    return Path(os.environ['RUNNER_TEMP'])/'kanpeki-release'

def profile_paths(uuid):
    return [Path.home()/'Library/MobileDevice/Provisioning Profiles'/f'{uuid}.mobileprovision', Path.home()/'Library/Developer/Xcode/UserData/Provisioning Profiles'/f'{uuid}.mobileprovision']

def main():
    dest = release_dir()
    if '--cleanup' in sys.argv:
        info=dest/'profile-uuid.txt'
        if info.exists():
            uuid=info.read_text().strip()
            if re.fullmatch(r'[A-Fa-f0-9-]{36}',uuid):
                for p in profile_paths(uuid): p.unlink(missing_ok=True)
        if dest.exists(): shutil.rmtree(dest)
        return
    missing = [k for k in REQUIRED if not os.environ.get(k)]
    if missing:
        raise ValueError('Missing release settings: '+', '.join(missing))
    if not re.fullmatch(r'[A-Za-z0-9]{10}',os.environ['ASC_KEY_ID']):
        raise ValueError('Invalid API key ID.')
    if not re.fullmatch(r'[A-Fa-f0-9-]{36}',os.environ['ASC_ISSUER_ID']):
        raise ValueError('Invalid issuer ID.')
    number=build_number(os.environ['GITHUB_RUN_NUMBER'],os.environ['GITHUB_RUN_ATTEMPT'])
    os.umask(0o077);dest.mkdir(mode=0o700,exist_ok=False)
    for env,filename in [('ASC_KEY_P8_BASE64','api.p8'),('IOS_DISTRIBUTION_P12_BASE64','distribution.p12'),('IOS_APPSTORE_PROFILE_BASE64','app.mobileprovision')]:
        (dest/filename).write_bytes(base64.b64decode(os.environ[env],validate=True))
    raw=subprocess.check_output(['security','cms','-D','-i',str(dest/'app.mobileprovision')],stderr=subprocess.DEVNULL)
    uuid=validate_profile(plistlib.loads(raw))
    (dest/'profile-uuid.txt').write_text(uuid)
    for p in profile_paths(uuid):
        p.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(dest/'app.mobileprovision',p)
    with open(os.environ['GITHUB_ENV'],'a') as f:
        for key,value in [('RELEASE_DIR',str(dest)),('PROFILE_UUID',uuid),('RELEASE_BUILD_NUMBER',number)]:
            if '\n' in value or '\r' in value: raise ValueError('Invalid multiline environment value.')
            f.write(f'{key}={value}\n')
    print(f'Release settings validated. Build {number}.')

if __name__=='__main__':
    try: main()
    except Exception as e:
        # Never print decoded key/certificate content or subprocess output.
        if isinstance(e, ValueError): sys.exit(str(e))
        sys.exit('Release preparation failed. Check secret formats and the provisioning profile.')
