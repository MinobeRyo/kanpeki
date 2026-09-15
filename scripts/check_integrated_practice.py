"""Compile the real Mac model/UI with a synthetic peer and run the rehearsal lifecycle.
Run scripts/check.sh mac first. This does not start a physical microphone or ChatGPT.
"""
from pathlib import Path
import json, subprocess, platform
root = Path(__file__).resolve().parent.parent
out = root / '.build/integrated-practice'
out.mkdir(parents=True, exist_ok=True)
products = root / '.build/mac/Build/Products/Debug'
project = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(root / 'Kanpeki.xcodeproj/project.pbxproj')]))['objects']
phase = project['61C1F9A06EA58B99F89C784A']
paths = [root / project[project[b]['fileRef']]['path'] for b in phase['files']]
source = root / 'Mac/KanpekiMacApp.swift'
copy = out / 'MacAppForTests.swift'
copy.write_text(source.read_text().replace('@main struct KanpekiMacApp', 'struct KanpekiMacApp'))
paths = [copy if p == source else p for p in paths]
subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-target', f'{platform.machine()}-apple-macos14.0',
    '-I', str(products), '-F', str(products), '-framework', 'whisper',
    '-Xlinker', '-rpath', '-Xlinker', str(products),
    *map(str, paths), str(root / 'Tests/IntegratedPracticeTests.swift'),
    str(products / 'KanpekiCamera.o'), str(products / 'KanpekiAudioHost.o'),
    '-o', str(out / 'tests')], check=True)
subprocess.run([str(out / 'tests')], check=True)
