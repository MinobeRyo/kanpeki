import importlib.util
from pathlib import Path
from datetime import datetime, timedelta, timezone
import unittest
spec=importlib.util.spec_from_file_location('release',Path(__file__).resolve().parents[1]/'scripts/prepare_release.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class ReleaseTests(unittest.TestCase):
    def profile(self):
        return {'UUID':'12345678-1234-1234-1234-123456789abc','TeamIdentifier':[m.TEAM], 'ExpirationDate':datetime.now(timezone.utc)+timedelta(days=30),'Entitlements':{'application-identifier':f'{m.TEAM}.{m.BUNDLE}','get-task-allow':False,'beta-reports-active':True}}
    def test_correct_profile(self): self.assertEqual(m.validate_profile(self.profile()), self.profile()['UUID'])
    def test_wrong_team(self):
        p=self.profile();p['TeamIdentifier']=['other']
        with self.assertRaises(ValueError): m.validate_profile(p)
    def test_development_rejected(self):
        p=self.profile();p['Entitlements']['get-task-allow']=True
        with self.assertRaises(ValueError): m.validate_profile(p)
    def test_adhoc_rejected(self):
        p=self.profile();p['ProvisionedDevices']=['device']
        with self.assertRaises(ValueError): m.validate_profile(p)
    def test_expired_rejected(self):
        p=self.profile();p['ExpirationDate']=datetime.now(timezone.utc)-timedelta(days=1)
        with self.assertRaises(ValueError): m.validate_profile(p)
    def test_run_and_retry_unique(self):
        self.assertEqual(len({m.build_number(r,a) for r in range(1,20) for a in range(1,4)}),57)
        self.assertEqual(m.build_number(1,1),'1.1.0')
        with self.assertRaises(ValueError):m.build_number(10000,1)
if __name__=='__main__':unittest.main()
