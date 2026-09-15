#!/usr/bin/env python3
"""GitHub issue reports and per-worktree task context. No third-party Python packages."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import uuid

REPO = 'MinobeRyo/kanpeki'
STATES = ('todo', 'doing', 'blocked', 'review', 'done')

def run(*args, cwd=None):
    return subprocess.check_output(args, cwd=cwd, text=True).strip()

def gh(*args):
    return run('gh', *args)

def root():
    return Path(run('git', 'rev-parse', '--show-toplevel'))

def context_path(at):
    return Path(run('git', 'rev-parse', '--path-format=absolute', '--git-path', 'kanpeki-task.json', cwd=at))

def worktrees(at):
    """Inventory this clone's worktrees, including paths containing spaces."""
    raw = run('git', 'worktree', 'list', '--porcelain', '-z', cwd=at)
    records = []
    for block in raw.split('\0\0'):
        fields = dict(field.split(' ', 1) if ' ' in field else (field, True)
                      for field in block.split('\0') if field)
        if 'worktree' not in fields:
            continue
        path = Path(fields['worktree'])
        row = {'path': str(path), 'branch': str(fields.get('branch', '')).removeprefix('refs/heads/'),
               'available': path.is_dir(), 'issue': None, 'owner': None}
        if path.is_dir() and not fields.get('bare'):
            context = context_path(path)
            if context.exists():
                data = json.loads(context.read_text())
                if data.get('repo') == REPO:
                    row.update(issue=data['issue'], owner=data['login'])
        records.append(row)
    return records


def require_unused_issue(at, number):
    for row in worktrees(at):
        if row['issue'] == number:
            raise ValueError(f"Issue #{number} already has a local worktree: {row['path']}. Resume it instead.")


def issue(number):
    return json.loads(gh('issue', 'view', str(number), '--repo', REPO, '--json', 'number,title,state,assignees,labels,url'))

def owner_check(task, login):
    if task['state'] != 'OPEN':
        raise ValueError('Issue is closed. Reopen or use a new issue.')
    others = [x['login'] for x in task['assignees'] if x['login'] != login]
    if others:
        raise ValueError('Issue already assigned to: ' + ', '.join(others))

def bind(at, number, login):
    branch = run('git', 'branch', '--show-current', cwd=at)
    if not branch or branch in ('main', 'master'):
        raise ValueError('Use a feature branch/worktree, not main or detached HEAD.')
    task = issue(number)
    owner_check(task, login)
    path = context_path(at)
    if path.exists():
        raise FileExistsError('This worktree already has a task context.')
    require_unused_issue(at, number)
    data = {'repo': REPO, 'issue': number, 'login': login, 'branch': branch, 'session': uuid.uuid4().hex}
    # Exclusive creation: never overwrite a running worktree's assignment.
    with path.open('x') as f:
        json.dump(data, f, indent=2)
    print(f'Bound #{number}: {at}\nNot yet published. Run report --state doing --body-file FILE before coding.')

def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest='cmd', required=True)
    sub.add_parser('board')
    sub.add_parser('list', help='List local worktrees and their issue assignments; no GitHub login required')
    b = sub.add_parser('bind'); b.add_argument('issue', type=int)
    s = sub.add_parser('start'); s.add_argument('issue', type=int); s.add_argument('slug')
    u = sub.add_parser('report'); u.add_argument('--state', choices=STATES, required=True); u.add_argument('--body-file', type=Path, required=True)
    a = p.parse_args()
    if a.cmd == 'board':
        print(gh('issue', 'list', '--repo', REPO, '--state', 'open', '--limit', '100', '--json', 'number,title,assignees,labels,updatedAt,url'))
        return
    at = root()
    if a.cmd == 'list':
        print(json.dumps(worktrees(at), ensure_ascii=False, indent=2))
        return
    login = gh('api', 'user', '--jq', '.login')
    if a.cmd == 'bind':
        bind(at, a.issue, login)
    elif a.cmd == 'start':
        if not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,39}', a.slug):
            raise ValueError('slug must be lowercase letters/digits/hyphens, max 40 characters.')
        owner_check(issue(a.issue), login)
        require_unused_issue(at, a.issue)
        # Remote is explicit; never trust a fork's origin to be the team repository.
        default = gh('repo', 'view', REPO, '--json', 'defaultBranchRef', '--jq', '.defaultBranchRef.name')
        run('git', 'fetch', f'https://github.com/{REPO}.git', default, cwd=at)
        base = run('git', 'rev-parse', 'FETCH_HEAD', cwd=at)
        suffix = f'{a.issue}-{a.slug}-{uuid.uuid4().hex[:8]}'
        branch = f'work/{login}/{suffix}'
        common = Path(run('git', 'rev-parse', '--path-format=absolute', '--git-common-dir', cwd=at))
        dest = common.parent.parent / f'{common.parent.name}-worktrees' / login / suffix
        dest.parent.mkdir(parents=True, exist_ok=True)
        run('git', 'worktree', 'add', '-b', branch, str(dest), base, cwd=at)
        bind(dest, a.issue, login)
    else:
        data = json.loads(context_path(at).read_text())
        branch = run('git', 'branch', '--show-current', cwd=at)
        if data['repo'] != REPO or data['login'] != login or data['branch'] != branch:
            raise ValueError('Task context does not match current repository/user/branch.')
        text = a.body_file.read_text().strip()
        if not text:
            raise ValueError('Empty progress report.')
        task = issue(data['issue']); owner_check(task, login)
        gh('issue', 'edit', str(data['issue']), '--repo', REPO, '--add-assignee', login)
        owner_check(issue(data['issue']), login)
        stamp = datetime.now(timezone.utc).isoformat()
        update = uuid.uuid4().hex
        body = f'## {a.state} · @{login}\n\n{stamp}\n\nBranch: `{branch}`\nSession: `{data["session"]}`\nUpdate-id: `{update}`\n\n{text}\n'
        print(f'Posting update-id: {update}', flush=True)
        with tempfile.TemporaryDirectory(prefix='kanpeki-report-') as tmp:
            path = Path(tmp)/'body.md'; path.write_text(body)
            print(gh('issue', 'comment', str(data['issue']), '--repo', REPO, '--body-file', str(path)), flush=True)
        # Only after comment succeeds. Labels may fail independently; no false success.
        existing = {x['name'] for x in task['labels']}
        args = ['issue', 'edit', str(data['issue']), '--repo', REPO, '--add-label', f'status:{a.state}']
        for state in STATES:
            if state != a.state and f'status:{state}' in existing:
                args += ['--remove-label', f'status:{state}']
        gh(*args)
        print(f'Published #{data["issue"]}: {a.state}')

if __name__ == '__main__':
    try:
        main()
    except (subprocess.CalledProcessError, ValueError, OSError, KeyError) as e:
        sys.exit(f'Not completed: {e}. Check the issue before retrying; earlier steps may have succeeded.')
