#!/usr/bin/env python3
"""Read-only GitHub merge readiness check. Does not merge or change protection."""
import argparse
import json
import subprocess
import sys

REPO = 'MinobeRyo/kanpeki'
EXPECTED = {'check (core)', 'check (mac)', 'check (phone)'}

def gh(*args):
    return json.loads(subprocess.check_output(['gh', *args], text=True))

def blockers(pr, protection, comparison, checks):
    errors = []
    if pr['state'] != 'OPEN' or pr['isDraft'] or pr['baseRefName'] != 'main':
        errors.append('PR must be open, ready for review, and target main.')
    if pr['isCrossRepository']:
        errors.append('Fork PR: inspect repository and permissions separately.')
    if pr['mergeable'] != 'MERGEABLE' or pr['mergeStateStatus'] != 'CLEAN':
        errors.append('GitHub merge state is not CLEAN/MERGEABLE; wait or resolve blockers.')
    rules = protection.get('required_status_checks') or {}
    required = set(rules.get('contexts', [])) | {c['context'] for c in rules.get('checks', [])}
    if not protection and not rules:
        errors.append('Protection state was not verified.')
    by_name = {c.get('name'): c for c in checks}
    if any(by_name.get(name, {}).get('bucket') != 'pass' for name in required):
        errors.append('A live required check is missing or has not passed.')
    if comparison.get('status') not in ('ahead', 'identical'):
        errors.append('PR does not contain current main. Update its branch, then rerun CI and this check.')
    if (not checks and not protection.get('_verified_unprotected')) or any(c.get('bucket') not in ('pass', 'skipping') for c in checks):
        errors.append('Checks failed, pending, unknown, or unavailable. Inspect results before merging.')
    reviews = protection.get('required_pull_request_reviews') or {}
    if reviews.get('required_approving_review_count', 0) > 0 and pr.get('reviewDecision') != 'APPROVED':
        errors.append('Live rules require an approving review.')
    return errors

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pr', type=int)
    args = parser.parse_args()
    fields = 'number,url,state,isDraft,isCrossRepository,baseRefName,headRefOid,mergeable,mergeStateStatus,reviewDecision'
    pr = gh('pr', 'view', str(args.pr), '--repo', REPO, '--json', fields)
    branch = gh('api', f'repos/{REPO}/branches/main')
    active_rules = gh('api', f'repos/{REPO}/rules/branches/main')
    if active_rules:
        raise ValueError('Active rulesets require manual review of their requirements; no automatic readiness claim.')
    protection = gh('api', f'repos/{REPO}/branches/main/protection') if branch.get('protected') else {'_verified_unprotected': True}
    base = gh('api', f'repos/{REPO}/commits/main')['sha']
    compare = gh('api', f'repos/{REPO}/compare/{base}...{pr["headRefOid"]}')
    # gh returns nonzero for pending/failed checks; still parse the status for diagnostics.
    result = subprocess.run(['gh','pr','checks',str(args.pr),'--repo',REPO,'--json','name,bucket,state'],capture_output=True,text=True)
    if result.returncode not in (0, 1, 8):
        raise ValueError('Cannot read required checks; verify GitHub access.')
    if result.stdout.strip():
        checks = json.loads(result.stdout)
    elif 'no checks reported' in result.stderr.lower():
        checks = []
    else:
        raise ValueError('Cannot establish check state.')
    errors = blockers(pr, protection, compare, checks)
    fresh = gh('pr','view',str(args.pr),'--repo',REPO,'--json','headRefOid,mergeStateStatus')
    if fresh['headRefOid'] != pr['headRefOid'] or gh('api',f'repos/{REPO}/commits/main')['sha'] != base:
        errors.append('PR/main changed during inspection. Run again.')
    if fresh['mergeStateStatus'] != 'CLEAN':
        errors.append('GitHub merge state changed or remains blocked.')
    print(json.dumps({'pr':pr['url'],'main_sha':base,'head_sha':pr['headRefOid'],'review_count':(protection.get('required_pull_request_reviews') or {}).get('required_approving_review_count',0),'required_checks':checks,'blockers':errors},ensure_ascii=False,indent=2))
    if errors:
        return 1
    print(f'READY snapshot. Review the actual diff against main and run relevant tests. With user authorization, merge immediately:\ngh pr merge {args.pr} --repo {REPO} --merge --match-head-commit {pr["headRefOid"]}')
    return 0

if __name__ == '__main__':
    try:
        sys.exit(main())
    except (subprocess.CalledProcessError, ValueError, KeyError, OSError) as exc:
        sys.exit(f'NOT READY: {exc}')
