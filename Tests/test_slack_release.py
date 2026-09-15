import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('slack',Path(__file__).resolve().parents[1]/'scripts/slack_release.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class SlackTests(unittest.TestCase):
    def test_uploaded_is_not_distributed(self):
        self.assertIn('未提出',m.state_label({'processingState':'VALID'},{'externalBuildState':'READY_FOR_BETA_SUBMISSION'},False))
    def test_group_membership_required(self):
        b={'processingState':'VALID'};d={'externalBuildState':'IN_BETA_TESTING'}
        self.assertIn('未確認',m.state_label(b,d,False));self.assertIn('指定の外部グループでテスト可能',m.state_label(b,d,True))
    def test_expired(self):self.assertIn('利用不可',m.state_label({'expired':True},{},True))
    def test_missing_build(self):self.assertIn('未確認',m.state_label(None,{},False))
    def test_pending_review(self):self.assertEqual(m.state_label({'processingState':'VALID'},{'externalBuildState':'IN_BETA_REVIEW'},True),'Apple審査中')
    def make_messages(self):
        return m.messages('0.1.0','3.1.0','審査中',{'html_url':'https://github.com/MinobeRyo/kanpeki/actions/runs/1','head_sha':'a'*40,'conclusion':'success'},[{'number':3,'title':'@channel <test>','body':'補足'*3000}],'確認項目','C123')
    @patch.dict('os.environ',{'TESTFLIGHT_TESTER_URL':''})
    def test_plain_text_and_limits(self):
        p,r=self.make_messages()
        self.assertIn('3.1.0',p['text']);self.assertNotIn('thread_ts',p)
        self.assertEqual(r['blocks'][0]['text']['type'],'plain_text')
        self.assertLessEqual(len(r['blocks'][0]['text']['text']),400)
        self.assertEqual(len(p['blocks'][2]['elements']),2)
        self.assertNotIn('補足',r['blocks'][0]['text']['text'])
        self.assertIn('確認項目',r['blocks'][0]['text']['text'])
        self.assertIn('/pull/3',r['blocks'][1]['elements'][0]['url'])
    @patch.dict('os.environ',{'TESTFLIGHT_TESTER_URL':'https://evil.example/join'})
    def test_untrusted_tester_url(self):
        with self.assertRaises(ValueError):self.make_messages()
    @patch.dict('os.environ',{'SLACK_BOT_TOKEN':'test'})
    @patch.object(m,'request',return_value={'ok':False,'error':'not_in_channel'})
    def test_slack_http_success_api_failure(self,_):
        with self.assertRaises(ValueError):m.post({})
    @patch.dict('os.environ',{'TESTFLIGHT_TESTER_URL':'https://testflight.apple.com/join/a8W7TAaE','MAC_TESTER_URL':'https://github.com/MinobeRyo/kanpeki/releases/download/mac-'+'a'*40+'/KanpekiMac.dmg'})
    def test_app_links_and_slack_button_limit(self):
        p,_=self.make_messages()
        self.assertEqual([x['text']['text'] for x in p['blocks'][2]['elements'][:2]],['iPhoneで試す','Mac版をダウンロード'])
        self.assertEqual(len(p['blocks'][2]['elements']),4)
    @patch.dict('os.environ',{'TESTFLIGHT_TESTER_URL':'','MAC_TESTER_URL':'https://github.com/another/repo/releases/download/secret'})
    def test_wrong_mac_repo_rejected(self):
        with self.assertRaises(ValueError):m.app_actions()
    @patch.dict('os.environ',{'MAC_TESTER_URL':''})
    @patch.object(m,'gh',return_value=[{'draft':True,'tag_name':'mac-'+'a'*40,'assets':[{'name':'KanpekiMac.dmg','state':'uploaded','browser_download_url':'https://example.com'}]}])
    def test_draft_mac_is_not_advertised(self,_):
        m.discover_mac_download()
        self.assertEqual(m.os.environ['MAC_TESTER_URL'],'')
if __name__=='__main__':unittest.main()
