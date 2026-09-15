"""Build a sandboxed Mac App Store package using isolated signing material."""
import base64
import os
from pathlib import Path
import plistlib
import re
import secrets
import shlex
import subprocess
import tempfile
from package_mac import run
from prepare_release import build_number

BUNDLE = 'jp.kanpeki.prototype.mac'
TEAM = 'XYJX89KRDM'

def validate_profile(data):
    if data.get('TeamIdentifier') != [TEAM] or data.get('Entitlements', {}).get('com.apple.application-identifier') != TEAM+'.'+BUNDLE:
        raise RuntimeError('Wrong Mac provisioning profile')
    if data['Entitlements'].get('get-task-allow'):
        raise RuntimeError('Development profile is not distributable')


def main():
    if os.environ.get('GITHUB_REF') != 'refs/heads/main' or os.environ.get('GITHUB_ACTIONS') != 'true':
        raise RuntimeError('Release only from main on GitHub Actions')
    number = build_number(os.environ["GITHUB_RUN_NUMBER"], os.environ["GITHUB_RUN_ATTEMPT"])
    with open(os.environ["GITHUB_ENV"], "a") as f:
        f.write("RELEASE_BUILD_NUMBER=" + number + "\n")
    out = Path('dist').resolve(); out.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='kanpeki-mac-store-', dir=os.environ['RUNNER_TEMP']) as tmp:
        root = Path(tmp); keychain = str(root/'signing.keychain-db'); password = secrets.token_hex(32)
        original = shlex.split(run('security', 'list-keychains', '-d', 'user', capture=True))
        try:
            run('security','create-keychain','-p',password,keychain)
            run('security','set-keychain-settings','-lut','3600',keychain)
            run('security','unlock-keychain','-p',password,keychain)
            run('security','list-keychains','-d','user','-s',keychain,*original)
            for prefix in ['IOS_DISTRIBUTION','MAC_INSTALLER']:
                p12=root/(prefix+'.p12')
                p12.write_bytes(base64.b64decode(os.environ[prefix+'_P12_BASE64'],validate=True));p12.chmod(0o600)
                print('Importing '+prefix+' signing identity',flush=True)
                run('security','import',str(p12),'-k',keychain,'-P',os.environ[prefix+'_P12_PASSWORD'],
                    '-t','cert','-f','pkcs12','-T','/usr/bin/codesign','-T','/usr/bin/productbuild','-T','/usr/bin/security')
            run('security','set-key-partition-list','-S','apple-tool:,apple:,codesign:','-k',password,keychain,capture=True)
            ids=run('security','find-identity','-v','-p','codesigning',keychain,capture=True)
            match=re.search(r'([A-F0-9]{40}) "Apple Distribution: [^\n]+ \('+TEAM+r'\)"',ids)
            if not match:raise RuntimeError('Expected Apple Distribution identity missing')
            profile=root/'MacAppStore.provisionprofile'
            profile.write_bytes(base64.b64decode(os.environ['MAC_APPSTORE_PROFILE_BASE64'],validate=True))
            data=plistlib.loads(run('security','cms','-D','-i',str(profile),capture=True).encode())
            validate_profile(data)
            derived=root/'build'
            run('xcodebuild','-project','Kanpeki.xcodeproj','-scheme','KanpekiMac','-configuration','Release',
                '-derivedDataPath',str(derived),'ARCHS=arm64 x86_64','ONLY_ACTIVE_ARCH=NO','CODE_SIGNING_ALLOWED=NO',
                'ENABLE_APP_SANDBOX=YES','CODE_SIGN_ENTITLEMENTS=Config/Mac-AppStore.entitlements',
                'CURRENT_PROJECT_VERSION='+number,'build')
            app=derived/'Build/Products/Release/KanpekiMac.app'
            (app/'Contents/embedded.provisionprofile').write_bytes(profile.read_bytes())
            ent=plistlib.loads(Path('Config/Mac-AppStore.entitlements').read_bytes())
            ent.update({k:v for k,v in data['Entitlements'].items() if k != 'keychain-access-groups'})
            if not ent.get('com.apple.security.app-sandbox') or ent.get('get-task-allow'):
                raise RuntimeError('Invalid distribution entitlements')
            entfile=root/'sign.entitlements';entfile.write_bytes(plistlib.dumps(ent))
            run('lipo',str(app/'Contents/MacOS/KanpekiMac'),'-verify_arch','arm64','x86_64')
            run('codesign','--force','--options','runtime','--timestamp','--entitlements',str(entfile),
                '--keychain',keychain,'--sign',match.group(1),str(app))
            run('codesign','--verify','--deep','--strict',str(app))
            run('productbuild','--component',str(app),'/Applications','--sign',
                '3rd Party Mac Developer Installer: teruyoshi takura ('+TEAM+')','--keychain',keychain,str(out/'KanpekiMac.pkg'))
            run('pkgutil','--check-signature',str(out/'KanpekiMac.pkg'))
        finally:
            subprocess.run(['security','list-keychains','-d','user','-s',*original],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            subprocess.run(['security','delete-keychain',keychain],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)

if __name__ == '__main__':
    try:main()
    except Exception:
        raise SystemExit('Mac TestFlight packaging failed; no upload performed. Inspect the failed stage without exposing secrets.')
