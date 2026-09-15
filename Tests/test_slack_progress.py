import copy
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from slack_progress import payload, TEAM
MEMBER = sorted(TEAM)[0]
class ProgressTests(unittest.TestCase):
    def setUp(self):
        self.e={'action':'created','repository':{'full_name':'MinobeRyo/kanpeki'},'issue':{'number':14,'title':'相談'},'comment':{'id':123,'user':{'login':MEMBER},'author_association':'COLLABORATOR','body':f'## doing · @{MEMBER}\n\nUpdate-id: `'+ 'a'*32 +'`\n\n@channel <!channel> 原稿の確認をお願いします'}}
    def test_valid_report(self):
        p=payload(self.e,'C123');self.assertIn(MEMBER,p['text']);self.assertEqual(p['blocks'][2]['text']['type'],'plain_text')
    def test_other_repo(self):
        self.e['repository']['full_name']='other/repo';self.assertIsNone(payload(self.e,'C123'))
    def test_untrusted_sender(self):
        self.e['comment']['user']['login']='outsider';self.assertIsNone(payload(self.e,'C123'))
    def test_spoofed_header(self):
        self.e['comment']['body']=self.e['comment']['body'].replace('@'+MEMBER,'@different-user');self.assertIsNone(payload(self.e,'C123'))
    def test_normal_comment(self):
        self.e['comment']['body']='相談したいです';self.assertIsNone(payload(self.e,'C123'))
    def test_pr_ignored(self):
        self.e['issue']['pull_request']={};self.assertIsNone(payload(self.e,'C123'))
    def test_edit_ignored(self):
        self.e['action']='edited';self.assertIsNone(payload(self.e,'C123'))
    def test_repeated_event_id(self):
        self.assertEqual(payload(self.e,'C123')['client_msg_id'],payload(copy.deepcopy(self.e),'C123')['client_msg_id'])
    def test_body_bounded(self):
        self.e['comment']['body']+='あ'*4000;self.assertEqual(len(payload(self.e,'C123')['blocks'][2]['text']['text']),200)
    def test_metadata_removed(self):
        self.e['comment']['body']=self.e['comment']['body'].replace('Update-id:', 'Branch: `work/test`\nSession: `internal`\nUpdate-id:')
        text=payload(self.e,'C123')['blocks'][2]['text']['text']
        self.assertNotIn('Update-id:',text)
        self.assertNotIn('Session:',text)
        self.assertIn('原稿の確認',text)
    def test_three_lines_and_details_link(self):
        self.e['comment']['body']+='\n二行目\n三行目\n四行目'
        p=payload(self.e,'C123')
        self.assertLessEqual(len(p['blocks'][2]['text']['text'].splitlines()),3)
        self.assertNotIn('四行目',p['blocks'][2]['text']['text'])
        self.assertTrue(p['blocks'][3]['elements'][0]['url'].endswith('#issuecomment-123'))
    def test_invalid_channel(self):
        with self.assertRaises(ValueError):payload(self.e,'U123')
if __name__=='__main__':unittest.main()
