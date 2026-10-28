"""Exercise dispatched PR policy at its GitHub and commit-check boundaries."""

import copy
import json
import os
from pathlib import Path
import runpy
import subprocess
import unittest
from unittest.mock import patch


class UpdatePrPolicy(unittest.TestCase):
    def setUp(self):
        self.pr = {
            'state': 'open', 'title': 'fix(bucket): repair `codex-acp` notes',
            'head': {'sha': 'head-sha', 'ref': 'chore/update-apps-42-1',
                     'repo': {'full_name': 'Hezric/scoop-zephyr'}},
            'base': {'ref': 'main'},
        }
        self.env = {
            'PR_NUMBER': '7', 'REPOSITORY': 'Hezric/scoop-zephyr',
            'HEAD_SHA': 'head-sha', 'HEAD_BRANCH': 'chore/update-apps-42-1',
            'BASE_BRANCH': 'main', 'RUNNER_TEMP': '/runner-temp',
        }

    def execute(self):
        runpy.run_path(str(Path(__file__).with_name('check-update-pr.py')))

    def test_validates_api_title_and_every_commit(self):
        with patch.dict(os.environ, self.env), patch('subprocess.check_output', side_effect=[json.dumps(self.pr), 'first-sha\nhead-sha\n']) as api, patch('subprocess.run') as check:
            self.execute()
        self.assertEqual(api.call_args_list[1].args[0][-3:], ['--paginate', '--jq', '.[].sha'])
        self.assertEqual(check.call_args_list[0].kwargs['input'], self.pr['title'] + '\n')
        self.assertEqual([call.args[0][-1] for call in check.call_args_list[1:]], ['first-sha', 'head-sha'])
        self.assertTrue(all(call.kwargs['check'] for call in check.call_args_list))

    def test_rejects_changed_head_base_or_repository_before_checking(self):
        for key, value in [('state', 'closed'), ('sha', 'other-sha'), ('ref', 'other-branch'), ('base', 'develop'), ('repo', 'other/repo')]:
            pr = copy.deepcopy(self.pr)
            if key == 'state':
                pr[key] = value
            elif key == 'base':
                pr['base']['ref'] = value
            elif key == 'repo':
                pr['head']['repo']['full_name'] = value
            else:
                pr['head'][key] = value
            with self.subTest(key=key), patch.dict(os.environ, self.env), patch('subprocess.check_output', return_value=json.dumps(pr)), patch('subprocess.run') as check:
                with self.assertRaises(SystemExit):
                    self.execute()
                check.assert_not_called()

    def test_commit_check_failure_fails_policy(self):
        with patch.dict(os.environ, self.env), patch('subprocess.check_output', return_value=json.dumps(self.pr)), patch('subprocess.run', side_effect=subprocess.CalledProcessError(1, 'commit-check')):
            with self.assertRaises(subprocess.CalledProcessError):
                self.execute()

    def test_invalid_pr_number_never_calls_github(self):
        self.env['PR_NUMBER'] = '../7'
        with patch.dict(os.environ, self.env), patch('subprocess.check_output') as api:
            with self.assertRaises(SystemExit):
                self.execute()
            api.assert_not_called()


if __name__ == '__main__':
    unittest.main()
