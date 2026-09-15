import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('documentation_check', Path(__file__).resolve().parents[1] / 'scripts/documentation_check.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class DocumentationTests(unittest.TestCase):
    def body(self, impact='updated'):
        return f'Docs-Impact: {impact}\nDocs-Reason: 録音と発表の関連付け仕様を更新し、実機未検証を明記しました。'

    def test_updated(self):
        self.assertEqual(m.validate_documentation(self.body(), [{'filename': 'docs/AUDIO_CAPTURE.md', 'status': 'modified'}]), [])

    def test_missing_declaration(self):
        self.assertTrue(m.validate_documentation('', []))

    def test_no_document_change(self):
        self.assertTrue(m.validate_documentation(self.body(), [{'filename': 'Mac/MacModel.swift'}]))

    def test_none_with_explanation(self):
        self.assertEqual(m.validate_documentation(self.body('none'), [{'filename': 'Tests/Unit.swift'}]), [])

    def test_none_but_document_changed(self):
        self.assertTrue(m.validate_documentation(self.body('none'), [{'filename': 'README.md'}]))

    def test_deleted_document_does_not_count(self):
        self.assertTrue(m.validate_documentation(self.body(), [{'filename': 'docs/old.md', 'status': 'removed'}]))

    def test_historical_prompt_does_not_count(self):
        for path in ['assets/design/PROMPTS.md', 'docs/archive/old.md', 'experiments/x/PROMPTS.md']:
            self.assertTrue(m.validate_documentation(self.body(), [{'filename': path}]))

    def test_duplicate_and_invalid_impact(self):
        for body in [self.body() + '\nDocs-Impact: none', self.body().replace('updated', 'maybe')]:
            self.assertTrue(m.validate_documentation(body, [{'filename': 'README.md'}]))

    def test_placeholder_and_short_reason(self):
        for reason in ['TBD', '不要', '<具体的な理由をここへ記入してください>', '記入してください。具体的な理由を。']:
            self.assertTrue(m.validate_documentation('Docs-Impact: none\nDocs-Reason: ' + reason, []))

    def test_duplicate_reason(self):
        self.assertTrue(m.validate_documentation(self.body('none') + '\nDocs-Reason: 別の説明をここにも書いてある。', []))

    def test_examples_and_comments_are_not_declarations(self):
        for body in ['<!--\n' + self.body('none') + '\n-->'] + [
            opening + '\n' + self.body('none') + '\n' + closing
            for opening, closing in [('```text', '```'), ('~~~text', '~~~'), ('````text', '````'), ('   ~~~~~text', '   ~~~~~~')]
        ]:
            self.assertTrue(m.validate_documentation(body, []))

    def test_declaration_and_fenced_examples(self):
        body = self.body('none') + '\n````text\n```\n' + self.body() + '\n```\n````'
        self.assertEqual(m.validate_documentation(body, []), [])

    def test_unclosed_fence_is_not_declaration(self):
        self.assertTrue(m.validate_documentation('~~~\n' + self.body('none'), []))

    def test_comparison_symbol_in_real_reason(self):
        body = 'Docs-Impact: updated\nDocs-Reason: specs/LIMITS.mdの待ち時間 < 100ms の判定条件を実装に合わせました。'
        self.assertEqual(m.validate_documentation(body, [{'filename': 'specs/LIMITS.md'}]), [])

    def test_nested_and_root_document_paths(self):
        for path in ['AGENTS.md', 'apps/SlidePacer/README.md', 'specs/PRODUCT.md', 'integrations/mcp/README.md',
                     'assets/design/device-size/LAYOUT.md', '.agents/skills/x/SKILL.md', '.github/pull_request_template.md']:
            self.assertTrue(m.living_document(path))
        for path in ['../README.md', '/tmp/README.md', 'Tests/fake.md']:
            self.assertFalse(m.living_document(path))

    def test_body_is_data(self):
        self.assertEqual(m.validate_documentation('Docs-Impact: none\nDocs-Reason: shell $(touch /tmp/never-execute) is just text', []), [])

    def test_cli_reads_git_diff_and_event_without_shell_expansion(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return subprocess.check_output(['git', *args], cwd=root, text=True).strip()
            git('init', '-q')
            git('config', 'user.name', 'Documentation test')
            git('config', 'user.email', 'docs-test@example.invalid')
            (root / 'README.md').write_text('Before\n')
            git('add', 'README.md'); git('commit', '-qm', 'base')
            base = git('rev-parse', 'HEAD')
            (root / 'README.md').write_text('After\n')
            git('add', 'README.md'); git('commit', '-qm', 'update')
            event = root / 'event.json'
            import json
            event.write_text(json.dumps({'pull_request': {'body': self.body()}}))
            script = Path(__file__).resolve().parents[1] / 'scripts/documentation_check.py'
            command = ['python3', str(script), '--base', base, '--event', str(event)]
            self.assertEqual(subprocess.run(command, cwd=root, capture_output=True).returncode, 0)
            event.write_text(json.dumps({'pull_request': {'body': self.body('none')}}))
            self.assertNotEqual(subprocess.run(command, cwd=root, capture_output=True).returncode, 0)


if __name__ == '__main__':
    unittest.main()
