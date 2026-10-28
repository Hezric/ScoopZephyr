"""Validate an actual update PR during explicitly dispatched CI."""

import json
import os
import re
import subprocess


def api(path, *args):
    return subprocess.check_output(['gh', 'api', path, *args], text=True)


number = os.environ['PR_NUMBER']
if not re.fullmatch(r'[1-9][0-9]*', number):
    raise SystemExit('Invalid PR number')
repo = os.environ['REPOSITORY']
path = f'repos/{repo}/pulls/{number}'
pr = json.loads(api(path))
if not (pr['state'] == 'open' and pr['head']['sha'] == os.environ['HEAD_SHA']
        and pr['head']['ref'] == os.environ['HEAD_BRANCH']
        and pr['head']['repo']['full_name'] == repo
        and pr['base']['ref'] == os.environ['BASE_BRANCH']):
    raise SystemExit('PR head or base does not match the dispatched checkout')

# Reuse the action's provenance-verified CLI for the actual PR title and range.
cli = os.path.join(os.environ['RUNNER_TEMP'], 'commit-check-action/venv/bin/commit-check')
subprocess.run([cli, '-m'], input=pr['title'] + '\n', text=True, check=True)
for sha in api(path + '/commits', '--paginate', '--jq', '.[].sha').splitlines():
    subprocess.run([cli, '-m', '--rev', sha], check=True)
