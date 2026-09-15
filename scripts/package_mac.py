"""Build, Developer ID sign and notarize a universal Mac DMG. Fail closed."""
import base64
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import shlex
import subprocess
import tempfile


def run(*args, capture=False):
    return subprocess.run(args, check=True, text=True,
        stdout=subprocess.PIPE if capture else None).stdout


def main():
    names=['MAC_DEVELOPER_ID_P12_BASE64','MAC_DEVELOPER_ID_P12_PASSWORD',
           'ASC_KEY_P8_BASE64','ASC_KEY_ID','ASC_ISSUER_ID','GITHUB_RUN_NUMBER']
    if any(not os.environ.get(n) for n in names):
        raise RuntimeError('Mac signing/notarization configuration missing')
    out=Path('dist').resolve();out.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='kanpeki-mac-',dir=os.environ['RUNNER_TEMP']) as tmp:
        root=Path(tmp);keychain=str(root/'signing.keychain-db')
        password=secrets.token_hex(32)
        p12=root/'developer.p12';p12.write_bytes(base64.b64decode(os.environ[names[0]],validate=True));p12.chmod(0o600)
        key=root/'AuthKey.p8';key.write_bytes(base64.b64decode(os.environ['ASC_KEY_P8_BASE64'],validate=True));key.chmod(0o600)
        original_keychains=shlex.split(run('security','list-keychains','-d','user',capture=True))
        try:
            run('security','create-keychain','-p',password,keychain)
            run('security','set-keychain-settings','-lut','3600',keychain)
            run('security','unlock-keychain','-p',password,keychain)
            run('security','list-keychains','-d','user','-s',keychain,*original_keychains)
            run('security','import',str(p12),'-k',keychain,'-P',os.environ[names[1]],'-T','/usr/bin/codesign')
            run('security','set-key-partition-list','-S','apple-tool:,apple:,codesign:','-k',password,keychain,capture=True)
            identities=run('security','find-identity','-v','-p','codesigning',keychain,capture=True)
            match=re.search(r'([A-F0-9]{40}) "Developer ID Application: [^\n]+ \(XYJX89KRDM\)"',identities)
            if not match:raise RuntimeError('Expected Developer ID Application identity not found')
            identity=match.group(1)
            derived=root/'build'
            run('xcodebuild','-project','Kanpeki.xcodeproj','-scheme','KanpekiMac','-configuration','Release',
                '-derivedDataPath',str(derived),'ARCHS=arm64 x86_64','ONLY_ACTIVE_ARCH=NO','CODE_SIGNING_ALLOWED=NO','build')
            app=derived/'Build/Products/Release/KanpekiMac.app'
            info=app/'Contents/Info.plist'
            data=plistlib.loads(info.read_bytes());data['CFBundleVersion']=os.environ['GITHUB_RUN_NUMBER'];info.write_bytes(plistlib.dumps(data))
            run('lipo',str(app/'Contents/MacOS/KanpekiMac'),'-verify_arch','arm64','x86_64')
            run('codesign','--force','--deep','--options','runtime','--timestamp','--entitlements','Config/Mac.entitlements','--keychain',keychain,'--sign',identity,str(app))
            run('codesign','--verify','--deep','--strict',str(app))
            stage=root/'dmg';stage.mkdir();run('ditto',str(app),str(stage/'カンペき.app'));(stage/'Applications').symlink_to('/Applications')
            dmg=out/'KanpekiMac.dmg'
            run('hdiutil','create','-volname','カンペき','-srcfolder',str(stage),'-ov','-format','UDZO',str(dmg))
            run('codesign','--timestamp','--keychain',keychain,'--sign',identity,str(dmg))
            result=json.loads(run('xcrun','notarytool','submit',str(dmg),'--key',str(key),
                '--key-id',os.environ['ASC_KEY_ID'],'--issuer',os.environ['ASC_ISSUER_ID'],
                '--wait','--timeout','30m','--output-format','json',capture=True))
            if result.get('status')!='Accepted':raise RuntimeError('Apple notarization not accepted')
            run('xcrun','stapler','staple',str(dmg));run('xcrun','stapler','validate',str(dmg))
        finally:
            subprocess.run(['security','list-keychains','-d','user','-s',*original_keychains],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            subprocess.run(['security','delete-keychain',keychain],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)


if __name__=='__main__':
    try:main()
    except Exception:
        raise SystemExit('Mac packaging failed; no release published. Check the failed stage without logging signing credentials.')
