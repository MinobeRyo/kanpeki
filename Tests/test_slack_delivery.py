import importlib
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
m = importlib.import_module('slack_delivery')

class DeliveryTests(unittest.TestCase):
    def test_auth_error_still_posts_and_recovers_without_duplicate(self):
        from datetime import datetime, timezone
        run = {'id':42, 'run_attempt':1, 'run_number':2, 'head_branch':'main',
               'path':'.github/workflows/testflight.yml', 'status':'completed',
               'updated_at':datetime.now(timezone.utc).isoformat(), 'conclusion':'failure',
               'head_sha':'a'*40, 'html_url':'https://github.com/MinobeRyo/kanpeki/actions/runs/42'}
        env = {'GITHUB_REF':'refs/heads/main', 'RELEASE_RUN_ID':'42', 'SLACK_CHANNEL_ID':'C123',
               'SLACK_BOT_TOKEN':'test', 'TESTFLIGHT_TESTER_URL':'https://testflight.apple.com/join/phone',
               'MAC_TESTER_URL':'https://testflight.apple.com/join/mac'}
        previous = Path.cwd()
        try:
            with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, env), \
                 patch.object(m,'gh',side_effect=lambda p:run if p.startswith('actions/') else []), \
                 patch.object(m,'apple_token',side_effect=ValueError('secret-key-must-not-leak')) as token, \
                 patch.object(m,'status',return_value=('内部テスト可能','0.1.0')) as status, \
                 patch.object(m,'post',return_value={'ts':'123'}) as post, \
                 patch.object(m,'request',return_value={'ok':True}) as update:
                os.chdir(folder)
                m.main()
                self.assertEqual(post.call_count,2)
                payload = post.call_args_list[0].args[0]
                self.assertIn('CD: failure',payload['text'])
                self.assertEqual(payload['text'].count('Apple接続エラー'),2)
                self.assertNotIn('secret-key',str(payload))
                self.assertNotIn('内部テスト可能',payload['text'])
                status.assert_not_called()
                m.main()
                self.assertEqual(post.call_count,2)
                update.assert_not_called()
                token.side_effect = None; token.return_value = 'token'
                m.main()
                update.assert_called_once()
                self.assertIn('内部テスト可能',update.call_args.args[2]['text'])
                self.assertEqual(post.call_count,2)
        finally:
            os.chdir(previous)

    def test_one_platform_error_does_not_hide_other_platform(self):
        env = {'TESTFLIGHT_TESTER_URL':'phone', 'MAC_TESTER_URL':'mac'}
        with patch.dict(os.environ,env), patch.object(m,'apple_token',return_value='token'), \
             patch.object(m,'status',side_effect=[RuntimeError('secret-response'),('内部テスト可能','0.1.0')]):
            results = m.platform_results('1002.1.0')
            self.assertIn('未確認',results[0][1])
            self.assertEqual(results[1][1],'内部テスト可能')
            self.assertNotIn('secret-response',str(results))

    def test_slack_send_error_is_not_silently_saved(self):
        # Apple fallback is narrow: Slack transport failures must still fail the run.
        env = {'GITHUB_REF':'refs/heads/main', 'RELEASE_RUN_ID':'42', 'SLACK_CHANNEL_ID':'C123'}
        from datetime import datetime, timezone
        run = {'id':42,'run_attempt':1,'run_number':2,'head_branch':'main',
               'path':'.github/workflows/testflight.yml','status':'completed',
               'updated_at':datetime.now(timezone.utc).isoformat(),'conclusion':'failure',
               'html_url':'https://github.com/MinobeRyo/kanpeki/actions/runs/42'}
        previous = Path.cwd()
        try:
            with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ,env), \
                 patch.object(m,'gh',return_value=run), patch.object(m,'platform_results',return_value=[]), \
                 patch.object(m,'post',side_effect=RuntimeError('Slack unavailable')):
                os.chdir(folder)
                with self.assertRaises(RuntimeError): m.main()
                self.assertFalse(Path('.delivery-state/state.json').exists())
        finally: os.chdir(previous)

    def test_missing_build_not_installable(self):
        with patch.object(m, 'apple', return_value={'data': []}):
            self.assertIn('未確認', m.status('app','group','1001.1.0','token')[0])

    def test_approved_without_group_not_installable(self):
        replies = [
            {'data': [{'id':'b', 'attributes':{'processingState':'VALID'}}]},
            {'data': {'attributes': {'internalBuildState':'IN_BETA_TESTING'}}},
            {'data': {'attributes': {'version':'0.1.0'}}},
            {'data': [], 'links': {}}]
        with patch.object(m, 'apple', side_effect=replies):
            self.assertIn('割当は未確認', m.status('app','group','1001.1.0','token')[0])

    def test_group_pagination(self):
        replies = [
            {'data': [{'id':'b', 'attributes':{'processingState':'VALID'}}]},
            {'data': {'attributes': {'internalBuildState':'IN_BETA_TESTING'}}},
            {'data': {'attributes': {'version':'0.1.0'}}},
            {'data': [], 'links': {'next':'https://api.appstoreconnect.apple.com/v1/next'}},
            {'data': [{'id':'b'}], 'links': {}}]
        with patch.object(m, 'apple', side_effect=replies):
            self.assertIn('内部テスト可能', m.status('app','group','1001.1.0','token')[0])

    def test_unchanged_no_duplicate_changed_updates_parent(self):
        from datetime import datetime, timezone
        run = {'id':42,'run_attempt':1,'run_number':2,'head_branch':'main',
               'path':'.github/workflows/testflight.yml','status':'completed',
               'updated_at':datetime.now(timezone.utc).isoformat(), 'conclusion':'success',
               'head_sha':'a'*40, 'html_url':'https://github.com/MinobeRyo/kanpeki/actions/runs/42'}
        env = {'GITHUB_REF':'refs/heads/main','RELEASE_RUN_ID':'42','SLACK_CHANNEL_ID':'C123',
               'SLACK_BOT_TOKEN':'test', 'TESTFLIGHT_TESTER_URL':'https://testflight.apple.com/join/phone',
               'MAC_TESTER_URL':'https://testflight.apple.com/join/mac'}
        previous = Path.cwd()
        try:
            with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, env), \
                 patch.object(m,'gh',side_effect=lambda p:run if p.startswith('actions/') else []), \
                 patch.object(m,'apple_token',return_value='token'), \
                 patch.object(m,'status',return_value=('審査待ち','0.1.0')) as status, \
                 patch.object(m,'post',return_value={'ts':'123'}) as post, \
                 patch.object(m,'request',return_value={'ok':True}) as update:
                os.chdir(folder)
                m.main(); self.assertEqual(post.call_count,2)
                m.main(); self.assertEqual(post.call_count,2); update.assert_not_called()
                status.return_value=('テスト可能','0.1.0')
                m.main(); self.assertEqual(post.call_count,2); update.assert_called_once()
        finally:
            os.chdir(previous)

if __name__ == '__main__': unittest.main()
