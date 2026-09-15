import copy
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from package_mac_testflight import validate_profile

class MacProfileTests(unittest.TestCase):
    def setUp(self):
        self.profile={'TeamIdentifier':['XYJX89KRDM'],'Entitlements':{'com.apple.application-identifier':'XYJX89KRDM.jp.kanpeki.prototype.mac'}}
    def test_distribution_profile(self): validate_profile(self.profile)
    def test_phone_profile_rejected(self):
        self.profile['Entitlements']['com.apple.application-identifier']='XYJX89KRDM.jp.kanpeki.prototype.phone'
        with self.assertRaises(RuntimeError):validate_profile(self.profile)
    def test_other_team_rejected(self):
        self.profile['TeamIdentifier']=['OTHER']
        with self.assertRaises(RuntimeError):validate_profile(self.profile)
    def test_development_profile_rejected(self):
        self.profile['Entitlements']['get-task-allow']=True
        with self.assertRaises(RuntimeError):validate_profile(self.profile)
if __name__=='__main__':unittest.main()
