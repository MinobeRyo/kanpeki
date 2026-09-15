import importlib.util
import json
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('exporter',ROOT/'scripts/export_infrastructure.py')
e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e)

class ExportTests(unittest.TestCase):
    def config(self):
        return {'repository':'example/fresh-app','members':['alice','bob']}

    def test_export_excludes_product_and_secrets(self):
        with tempfile.TemporaryDirectory() as tmp:
            out=Path(tmp)/'new'
            e.export(self.config(),out)
            files=[p.relative_to(out).as_posix() for p in out.rglob('*') if p.is_file()]
            self.assertFalse(any(p.startswith(('Mac/','Phone/','Shared/','experiments/','.git/')) or p.endswith(('.p8','.p12','.swift','.pbxproj','.png')) for p in files))
            self.assertFalse((out/'Tests/run_tests.sh').exists())
            self.assertFalse((out/'.github/workflows/camera.yml').exists())
            self.assertIn('specs/FEATURE_TEMPLATE.md',files)
            self.assertIn('example/fresh-app',(out/'scripts/team.py').read_text())
            self.assertNotIn('MinobeRyo/kanpeki',(out/'scripts/slack_release.py').read_text())
            members=json.loads(subprocess.check_output([sys.executable,'-c','import json; from slack_progress import TEAM; print(json.dumps(sorted(TEAM)))'],cwd=out/'scripts',text=True))
            self.assertEqual(members,['alice','bob'])
            settings=json.loads((out/'infrastructure/github-settings.json').read_text())
            self.assertEqual(settings['initial_variables']['IOS_DISTRIBUTION_ENABLED'],'false')
            self.assertIn('ASC_KEY_ID',settings['secrets_to_register'])
            self.assertIn('CONFIGURE_APPLE_TEAM',(out/'scripts/prepare_release.py').read_text())
            for name,digest in json.loads((out/'infrastructure/provenance.json').read_text())['files'].items():
                self.assertEqual(e.hashlib.sha256((out/name).read_bytes()).hexdigest(),digest)
            for source in out.rglob('*.py'):
                compile(source.read_text(),str(source),'exec')

    def test_never_overwrites_destination(self):
        with tempfile.TemporaryDirectory() as tmp:
            marker=Path(tmp)/'keep';marker.write_text('valuable')
            with self.assertRaises(ValueError):e.export(self.config(),tmp)
            self.assertEqual(marker.read_text(),'valuable')

    def test_reject_source_and_code_in_configuration(self):
        for update in ({'repository':'MinobeRyo/kanpeki'}, {'members':['alice;rm']}, {'apple_team':"'; dangerous()"}, {'api_key':'secret'}):
            c=self.config();c.update(update)
            with self.assertRaises(ValueError):e.validate(c)

    def test_explicit_identity_mapping(self):
        with tempfile.TemporaryDirectory() as tmp:
            c=self.config();c.update({key:'NEW_VALUE' for key in e.REPLACEMENTS if key!='repository'})
            out=Path(tmp)/'new';e.export(c,out)
            for path in ('scripts/prepare_release.py','scripts/package_mac_testflight.py','fastlane/Fastfile','.github/workflows/slack-release.yml'):
                content=(out/path).read_text()
                for old in e.REPLACEMENTS.values():self.assertNotIn(old,content)

if __name__=='__main__':unittest.main()
