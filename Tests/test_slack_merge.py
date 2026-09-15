import sys
from pathlib import Path
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from slack_merge import messages, REPO

class MergeTests(unittest.TestCase):
    def pr(self):
        return {"number":8,"merged":True,"title":"接続を改善", "body":"変更点\n確認事項", "base":{"ref":"main","repo":{"full_name":REPO}}}
    def test_reject_unmerged(self):
        p=self.pr();p["merged"]=False
        self.assertIsNone(messages(p,"C012345"))
    def test_reject_other_repository_and_branch(self):
        p=self.pr();p["base"]["repo"]["full_name"]="other/repo"
        self.assertIsNone(messages(p,"C012345"))
        p=self.pr();p["base"]["ref"]="feature"
        self.assertIsNone(messages(p,"C012345"))
    def test_inert_bounded_prose_and_stable_ids(self):
        p=self.pr();p["title"]="<!channel> "*90;p["body"]="<@U123>\n"*90
        a,b=messages(p,"C012345")
        self.assertLessEqual(len(a["blocks"][0]["text"]["text"]),200)
        self.assertLessEqual(len(b["blocks"][0]["text"]["text"]),180)
        self.assertEqual(a["blocks"][0]["text"]["type"],"plain_text")
        self.assertEqual(a["client_msg_id"],messages(p,"C012345")[0]["client_msg_id"])
        self.assertIn("配布とは別",a["text"])
    def test_invalid_channel(self):
        with self.assertRaises(ValueError): messages(self.pr(),"@everyone")

if __name__=="__main__": unittest.main()
