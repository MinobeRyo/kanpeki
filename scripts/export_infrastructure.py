#!/usr/bin/env python3
"""Export tracked development infrastructure, never app code, git history or credentials."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
REPLACEMENTS = {
    'repository': 'MinobeRyo/kanpeki',
    'apple_team': 'XYJX89KRDM',
    'signer_name': 'teruyoshi takura',
    'phone_bundle': 'jp.kanpeki.prototype.phone',
    'mac_bundle': 'jp.kanpeki.prototype.mac',
    'phone_app_id': '6809810244',
    'mac_app_id': '6811774996',
    'phone_group_id': 'fef3aa45-1839-492a-80c6-729735c12890',
    'mac_group_id': '7d3f3f2e-7cb0-4123-a4df-2a1b52ef934b',
}
PATTERNS = ('.github/workflows/*.yml', '.github/ISSUE_TEMPLATE/*.yml')
EXACT = ('.codex/config.toml', 'AGENTS.md', '.github/pull_request_template.md', 'scripts/check.sh',
         'fastlane/Fastfile', 'Gemfile', 'Gemfile.lock', 'docs/MERGE.md',
         'docs/CODEX.md', 'docs/AI_TEAM.md', 'assets/design/README.md',
         'scripts/team.py', 'scripts/merge_preflight.py', 'scripts/prepare_release.py',
         'scripts/package_mac.py', 'scripts/package_mac_testflight.py',
         'scripts/slack_release.py', 'scripts/slack_progress.py', 'scripts/slack_mac.py',
         'Tests/test_team.py', 'Tests/test_release.py', 'Tests/test_merge_preflight.py',
         'Tests/test_slack_release.py', 'Tests/test_slack_progress.py', 'Tests/test_mac_testflight.py',
         '.agents/skills/kanpeki-team/SKILL.md', '.agents/skills/kanpeki-facilitator/SKILL.md',
         '.agents/skills/kanpeki-native/SKILL.md', '.agents/skills/kanpeki-imagegen/SKILL.md')
DOCS = ROOT / 'infrastructure/template'


def validate(config):
    repo = config.get('repository', '')
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9][A-Za-z0-9_.-]*', repo):
        raise ValueError('repository must be owner/name')
    if repo.lower() == REPLACEMENTS['repository'].lower():
        raise ValueError('Destination must differ from the source repository')
    members = config.get('members')
    if not isinstance(members, list) or not members or any(not isinstance(m, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9-]*', m) for m in members):
        raise ValueError('members must contain GitHub logins')
    for key in REPLACEMENTS:
        value = config.get(key)
        if value is not None and (not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9_./ -]+' if key == 'signer_name' else r'[A-Za-z0-9_./-]+', value)):
            raise ValueError(f'Invalid configuration value: {key}')
    if set(config) - (set(REPLACEMENTS) | {'members'}):
        raise ValueError('Unknown configuration keys (never put secrets in this file)')


def export(config, destination):
    validate(config)
    destination = Path(destination).resolve()
    if destination.exists():
        raise ValueError('Destination already exists; choose a new empty path')
    tracked = set(subprocess.check_output(['git', 'ls-files'], cwd=ROOT, text=True).splitlines())
    paths = {p for p in EXACT if p in tracked}
    for pattern in PATTERNS:
        paths.update(p.relative_to(ROOT).as_posix() for p in ROOT.glob(pattern) if p.relative_to(ROOT).as_posix() in tracked)
    # The exporter itself and application fixture tests are not part of the new product.
    paths.discard('scripts/export_infrastructure.py')
    paths.discard('Tests/test_export_infrastructure.py')
    files = {}
    for rel in sorted(paths):
        source = ROOT / rel
        if source.is_symlink():
            raise ValueError(f'Refusing symlink: {rel}')
        value = source.read_text()
        for key, old in REPLACEMENTS.items():
            value = value.replace(old, config.get(key) or 'CONFIGURE_' + key.upper())
        if rel == '.github/workflows/ci.yml':
            value = value.replace('          python3 Tests/test_export_infrastructure.py\n', '')
        if rel == 'scripts/slack_progress.py':
            value = re.sub(r'^TEAM=\{.*\}$', 'TEAM=set(' + repr(sorted(set(config['members']))) + ')', value, flags=re.M)
        if rel == '.github/workflows/testflight.yml':
            value = value.replace("if: github.ref == 'refs/heads/main'", "if: github.ref == 'refs/heads/main' && vars.IOS_DISTRIBUTION_ENABLED == 'true'")
        files[rel] = value
    for source in sorted(DOCS.rglob('*')):
        if source.is_file():
            if source.is_symlink():
                raise ValueError('Template symlink refused')
            rel = source.relative_to(DOCS).as_posix()
            files[rel] = source.read_text().replace('DESTINATION_REPOSITORY', config['repository'])
    # Remove source-specific product assumptions in the native skill.
    files['.agents/skills/kanpeki-native/SKILL.md'] = '''---
name: kanpeki-native
description: 新しいMac/iPhoneアプリを仕様書から実装し、通信契約と実機動作を検証するときに使う。
---
Read AGENTS.md, specs/, docs/STATUS.md and the assigned Issue. Existing application code is not included. Agree on the wire contract before implementing both clients. Read infrastructure/BUILD_CONTRACT.md for CI target names. Run affected core/mac/phone checks. Report simulator, unsigned build, and real-device results separately. Use worktree-local .build outputs. Do not invent completed features or copy the old prototype as new work.
'''
    files['infrastructure/settings.json'] = json.dumps(config, ensure_ascii=False, indent=2) + '\n'
    secrets = set()
    variables = set()
    for rel, value in files.items():
        if rel.startswith('.github/workflows/'):
            secrets.update(re.findall(r'secrets\.([A-Z_0-9]+)', value))
            variables.update(re.findall(r'vars\.([A-Z_0-9]+)', value))
    files['infrastructure/github-settings.json'] = json.dumps({
        'repository': config['repository'], 'environment': 'testflight',
        'secrets_to_register': sorted(secrets), 'variables_to_configure': sorted(variables),
        'initial_variables': {v: 'false' for v in variables if v.endswith('_ENABLED')},
        'required_checks': ['check (core)', 'check (mac)', 'check (phone)'],
        'required_approving_review_count': 0, 'strict_status_checks': True,
        'members': config['members'], 'collaborator_permission': 'push',
    }, ensure_ascii=False, indent=2) + '\n'
    sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    manifest = {'source_repository': REPLACEMENTS['repository'], 'source_commit': sha,
                'files': {p: hashlib.sha256(v.encode()).hexdigest() for p,v in sorted(files.items())}}
    files['infrastructure/provenance.json'] = json.dumps(manifest, indent=2) + '\n'
    destination.mkdir(parents=True)
    for rel,value in files.items():
        target = destination / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(value)
    return len(files)

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--config', required=True, type=Path)
    p.add_argument('--output', required=True, type=Path)
    args = p.parse_args()
    try:
        count = export(json.loads(args.config.read_text()), args.output)
        print(f'Exported {count} infrastructure files to {args.output}. App implementation and server-side settings are not installed.')
    except (ValueError, OSError, subprocess.CalledProcessError) as e:
        p.exit(1, f'Export failed: {e}\n')
