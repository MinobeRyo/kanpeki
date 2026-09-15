import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('team', Path(__file__).resolve().parents[1]/'scripts/team.py')
team = importlib.util.module_from_spec(spec); spec.loader.exec_module(team)

class CoordinationTests(unittest.TestCase):
    def test_other_owner_is_rejected(self):
        with self.assertRaises(ValueError):
            team.owner_check({'state':'OPEN','assignees':[{'login':'other'}]}, 'me')

    def test_worktree_contexts_are_isolated_and_not_overwritten(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo=Path(tmp)/'repo';repo.mkdir()
            def git(*args):
                return subprocess.check_output(['git','-C',str(repo),*args],text=True,stderr=subprocess.DEVNULL)
            git('init','-b','main');git('-c','user.name=Test','-c','user.email=test@example.invalid','commit','--allow-empty','-m','init')
            a=Path(tmp)/'a';b=Path(tmp)/'b'
            git('worktree','add','-b','work/a',str(a));git('worktree','add','-b','work/b',str(b))
            def task(n): return {'number':n,'state':'OPEN','assignees':[]}
            with patch.object(team,'issue',side_effect=task):
                team.bind(a,2,'me');team.bind(b,3,'me')
                with self.assertRaises(FileExistsError): team.bind(a,4,'me')
            self.assertNotEqual(team.context_path(a),team.context_path(b))
            self.assertEqual(json.loads(team.context_path(a).read_text())['issue'],2)
            self.assertEqual(json.loads(team.context_path(b).read_text())['issue'],3)
            self.assertEqual(git('status','--porcelain').strip(),'')

    def test_empty_report_does_not_post(self):
        with tempfile.TemporaryDirectory() as tmp:
            at=Path(tmp);context=at/'context';body=at/'body';body.write_text('')
            context.write_text(json.dumps({'repo':team.REPO,'login':'me','branch':'work/a','issue':2}))
            with patch.object(team,'root',return_value=at), patch.object(team,'context_path',return_value=context), patch.object(team,'run',return_value='work/a'), patch.object(team,'gh',return_value='me') as gh, patch('sys.argv',['team.py','report','--state','doing','--body-file',str(body)]):
                with self.assertRaises(ValueError): team.main()
                self.assertEqual(gh.call_count,1)

if __name__=='__main__': unittest.main()
