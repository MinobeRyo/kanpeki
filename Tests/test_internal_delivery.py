import sys
from pathlib import Path
import unittest
from unittest.mock import patch, MagicMock
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import internal_delivery as m

class InternalDeliveryTests(unittest.TestCase):
    def test_external_group_rejected(self):
        with patch.dict(m.os.environ, {'GITHUB_REF':'refs/heads/main','GITHUB_ACTIONS':'true','GITHUB_RUN_NUMBER':'2','GITHUB_RUN_ATTEMPT':'1'}), patch.object(sys,'argv',['script','iphone']), patch.object(m,'apple_token',return_value='test'), patch.object(m,'apple',return_value={'data':{'attributes':{'isInternalGroup':False}}}), patch.object(m.urllib.request,'urlopen') as post:
            with self.assertRaises(ValueError): m.main()
            post.assert_not_called()
    def test_valid_build_assigned_to_internal_group(self):
        replies=[{'data':{'attributes':{'isInternalGroup':True}}}, {'data':{'id':'6809810244'}}, {'data':[{'id':'build-id','attributes':{'processingState':'VALID'}}]}]
        response=MagicMock();response.__enter__.return_value.status=204
        with patch.dict(m.os.environ, {'GITHUB_REF':'refs/heads/main','GITHUB_ACTIONS':'true','GITHUB_RUN_NUMBER':'2','GITHUB_RUN_ATTEMPT':'1'}), patch.object(sys,'argv',['script','iphone']), patch.object(m,'apple_token',return_value='test'), patch.object(m,'apple',side_effect=replies) as read, patch.object(m.urllib.request,'urlopen',return_value=response) as post:
            m.main()
            self.assertIn('1002.1.0',read.call_args_list[-1].args[0])
            req=post.call_args.args[0]
            self.assertIn('08b44746-1f96-4214-ab2a-71f58f3af05d',req.full_url)
            self.assertEqual(req.method,'POST')
if __name__=='__main__':unittest.main()
