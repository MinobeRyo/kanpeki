import importlib.util
from pathlib import Path
import unittest
spec=importlib.util.spec_from_file_location('preflight',Path(__file__).resolve().parents[1]/'scripts/merge_preflight.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class MergeTests(unittest.TestCase):
    def setUp(self):
        self.pr=dict(state='OPEN',isDraft=False,baseRefName='main',isCrossRepository=False,mergeable='MERGEABLE',mergeStateStatus='CLEAN',reviewDecision='')
        self.protection={'required_status_checks':{'strict':True,'contexts':sorted(m.EXPECTED)},'required_pull_request_reviews':{'required_approving_review_count':0}}
        self.compare={'status':'ahead'}
        self.checks=[{'bucket':'pass','name':n} for n in m.EXPECTED]
    def check(self):return m.blockers(self.pr,self.protection,self.compare,self.checks)
    def test_ready_without_self_approval(self):self.assertEqual(self.check(),[])
    def test_main_advanced(self):
        self.compare['status']='diverged';self.assertTrue(self.check())
    def test_ci_incomplete(self):
        for bucket in ['pending','fail','skipping','cancel']:
            self.checks[0]['bucket']=bucket;self.assertTrue(self.check())
    def test_no_checks(self):
        self.checks=[];self.assertTrue(self.check())
    def test_changed_live_review_requirement(self):
        self.protection['required_pull_request_reviews']['required_approving_review_count']=1
        self.assertTrue(self.check());self.pr['reviewDecision']='APPROVED';self.assertEqual(self.check(),[])
    def test_missing_protection(self):
        self.protection={};self.assertTrue(self.check())
    def test_verified_unprotected_with_passing_checks(self):
        self.protection={'_verified_unprotected':True}
        self.assertEqual(self.check(),[])
    def test_skipped_optional_checks_allowed(self):
        self.protection={'_verified_unprotected':True}
        self.checks.append({'name':'optional','bucket':'skipping'})
        self.assertEqual(self.check(),[])
    def test_unknown_merge_state(self):
        self.pr['mergeable']='UNKNOWN';self.assertTrue(self.check())
    def test_draft(self):
        self.pr['isDraft']=True;self.assertTrue(self.check())
if __name__=='__main__':unittest.main()
