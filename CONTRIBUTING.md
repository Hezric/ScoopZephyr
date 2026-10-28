# Contributing to Zephyr

Bring a useful tool into the breeze. Keep manifests small, accurate, and faithful to the app's upstream distribution. Follow Scoop's [manifest guide](https://github.com/ScoopInstaller/Scoop/wiki/App-Manifests).

Use [GitHub Issues](https://github.com/Hezric/scoop-zephyr/issues) for bugs, app requests, and delivery work. Specifications are parent issues; tickets are native sub-issues. Labels are `ready-for-agent`, `in-progress`, `blocked`, and `done`. Accepted issues close with a PR/commit and verification. [AGENTS.md](AGENTS.md) defines the complete delivery workflow.

Write public contributions in English and keep the Chinese README synchronized.

1. Create a `<type>/<short-desc>` branch, such as `feat/add-app`.
2. Sign every commit with a GitHub-registered signing key. Use lowercase scoped Conventional Commits and PR titles, for example `feat(bucket): add ` followed by the app name in backticks. Preserve meaningful technical casing. Supported types and exact checks are in `cchk.toml`.
3. Install Scoop, BuildHelpers >= 2.0.1, and Pester >= 5.2.0. Set `SCOOP_HOME` to your Scoop checkout and `CI=false`, then run:

   ```pwsh
   pwsh -NoProfile -File bin/test.ps1
   pwsh -NoProfile -File .github/scripts/test-excavator.ps1
   pwsh -NoProfile -File .github/scripts/test-excavator-publish.ps1
   git restore -- .markdownlint.json
   ```

4. Open one PR per coherent stage with behavior and verification. Wait for `test` and `policy`; CI covers Windows PowerShell 5.1 and PowerShell 7. Rebase stale branches onto current main, re-sign commits, and use `--force-with-lease` only on the development branch. Maintainers squash-merge through GitHub and verify the resulting signature.

Main is signed and linear, requires strict checks, and forbids force pushes and deletion. Direct updates must promote the exact signed SHA already green on another branch. Excavator follows that path without a bypass. Dependabot keeps native branch names and auto squash-merges weekly grouped Actions updates after checks.

This bucket distributes manifests, so it has no build artifacts or release workflow. Each app retains its upstream license. Repository contributions use [MIT](LICENSE). Report security vulnerabilities privately through the repository's Security tab.
