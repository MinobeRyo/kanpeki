#!/usr/bin/env python3
"""Check a PR's explicit documentation impact; never execute text from its body."""
import argparse
import json
from pathlib import PurePosixPath
import re
import subprocess
import sys


def living_document(path):
    parts = PurePosixPath(path).parts
    if not parts or '..' in parts or path.startswith('/'):
        return False
    if 'archive' in parts or PurePosixPath(path).name in {'PROMPTS.md', 'LICENSE.md'}:
        return False
    return (path.endswith('.md') and
            (len(parts) == 1 or parts[0] in {'docs', 'specs', 'apps', 'experiments', 'integrations'}))


def validate_documentation(body, files):
    """files: GitHub-style filename/status records, including deletions and renames."""
    # Template instructions and quoted examples are not declarations.
    body = re.sub(r'<!--.*?-->', '', body or '', flags=re.S)
    visible = []
    fence = None
    for line in body.splitlines():
        if fence:
            if re.fullmatch(r' {0,3}' + re.escape(fence[0]) + '{' + str(len(fence)) + r',}[ \t]*', line):
                fence = None
            continue
        opening = re.match(r' {0,3}(`{3,}|~{3,})(.*)$', line)
        if opening and not (opening[1][0] == '`' and '`' in opening[2]):
            fence = opening[1]
            continue
        visible.append(line)
    body = '\n'.join(visible)
    impacts = re.findall(r'^Docs-Impact:\s*(\S+)\s*$', body, flags=re.M)
    reasons = re.findall(r'^Docs-Reason:[ \t]*(.+)$', body, flags=re.M)
    errors = []
    if len(impacts) != 1 or impacts[0] not in {'updated', 'none'}:
        errors.append('Declare exactly one Docs-Impact: updated or Docs-Impact: none.')
    if (len(reasons) != 1 or len(reasons[0].strip()) < 12 or
            reasons[0].strip().lower() in {'todo', 'tbd'} or
            re.fullmatch(r'<[^<>]+>', reasons[0].strip()) or '記入してください' in reasons[0]):
        errors.append('Docs-Reason needs a concrete explanation (at least 12 characters), not a placeholder.')
    changed_docs = sorted({f['filename'] for f in files
                           if f.get('status') != 'removed' and living_document(f['filename'])})
    if impacts == ['updated'] and not changed_docs:
        errors.append('Docs-Impact is updated, but no current documentation was added/modified in this PR.')
    if impacts == ['none'] and changed_docs:
        errors.append('Current documentation changed: declare Docs-Impact: updated and describe its scope.')
    return errors


def changed_files(base, head):
    # Resolve revisions without permitting command-line options from an event argument.
    for ref in (base, head):
        subprocess.check_call(['git', 'rev-parse', '--verify', '--end-of-options', ref + '^{commit}'], stdout=subprocess.DEVNULL)
    names = subprocess.check_output(['git', 'diff', '--no-renames', '--name-status', '-z', base + '...' + head, '--'])
    fields = names.decode('utf-8').split('\0')
    files = []
    for i in range(0, len(fields) - 1, 2):
        files.append({'filename': fields[i + 1], 'status': 'removed' if fields[i] == 'D' else 'modified'})
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', required=True)
    parser.add_argument('--head', default='HEAD')
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument('--event')
    source.add_argument('--body-file')
    args = parser.parse_args()
    with open(args.event or args.body_file, encoding='utf-8') as file:
        body = json.load(file)['pull_request'].get('body') if args.event else file.read()
    errors = validate_documentation(body, changed_files(args.base, args.head))
    for error in errors:
        print('Documentation: ' + error, file=sys.stderr)
    if not errors:
        print('Documentation impact declaration passed. Semantic accuracy still requires review.')
    return int(bool(errors))


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit('Documentation check unavailable: ' + str(error))
