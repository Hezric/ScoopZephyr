# Zephyr

Zephyr is a Scoop bucket: lightweight, refined tools for seamless workflows. Public source, issues, PRs, commits, and documentation are English. `README.md` governs; keep `README_zh-Hans.md` synchronized in natural Chinese. README prose and the GitHub About description keep a literary, humane voice; commands and facts stay exact.

## Delivery and tracker

GitHub Issues in `Hezric/scoop-zephyr` is the formal tracker. Specifications are parent issues; implementation tickets are native sub-issues. Create issues with `gh issue create`; attach a child using `gh api repos/Hezric/scoop-zephyr/issues/<parent>/sub_issues -F sub_issue_id=<child-database-id>`. State dependencies as issue links. This declaration is complete; formal delivery stays in Issues.

Labels map state: `ready-for-agent` -> `in-progress` -> `done`; use `blocked` with the exact prerequisite. Acceptance closes the issue with its PR/commit and verification; close a parent when all children are accepted. Use Git and Issues for progress. Read [manifest update behavior](docs/features/manifest-updates.md) before changing the updater. Maintain affected current behavior under `docs/features/`; create `GLOSSARY.md` and `docs/adr/` only for confirmed language and consequential architectural decisions.

## Git and checks

- Work on `<type>/<short-desc>` branches, such as `feat/add-app`, with one PR per coherent stage.
- Every commit and PR title uses lowercase `type(scope): subject` (or `type(scope)!:` for breaking changes). Preserve meaningful technical casing. Wrap package names, commands, and paths in backticks. Allowed types and validation live in `cchk.toml`.
- Sign every commit with a GitHub-registered key; verify SSH signatures with a local allowed-signers file. Keep signing enabled when a key is unavailable and resume publishing after it is unlocked.
- With Scoop, BuildHelpers >= 2.0.1, and Pester >= 5.2.0 available, run `pwsh -NoProfile -File bin/test.ps1`, `pwsh -NoProfile -File .github/scripts/test-excavator.ps1`, and `pwsh -NoProfile -File .github/scripts/test-excavator-publish.ps1`. Set `SCOOP_HOME` to the Scoop checkout and `CI=false` to test every manifest. The runner removes `.markdownlint.json`; restore it afterward. CI also tests Windows PowerShell 5.1. There is no build step.
- Required GitHub Actions checks are `test` and `policy`; preserve those names. `test` aggregates both PowerShell suites and publisher checks. `policy` uses commit-check for commits and PR titles and enforces branch names.
- Main requires strict up-to-date checks, signed commits, and linear history; force pushes and deletion are forbidden. Use GitHub squash merging after green checks. Squash title and body come from the PR; read back the resulting commit's API signature verification. Merged branches are deleted automatically.
- Rebase a stale development branch locally onto current main, re-sign rewritten commits, and use `--force-with-lease` only on that development branch. Wait for fresh checks before squash merging.
- A direct update must fast-forward main to the exact signed SHA already green on a branch and based on current main. Excavator uses PRs: it stages signed Contents API commits, starts only its own native PR checks, squash-merges the checked head, verifies GitHub's resulting signature, and removes the unchanged merged staging branch. Main has no bypass actors. See the Feature document for failure and recovery behavior.
- Dependabot retains its native `dependabot/` branches; only its branch-name check is exempt. Scoped messages, tests, signatures, and squash merging apply. GitHub Actions updates are grouped weekly and auto squash-merge after required checks.

## Distribution and license

This bucket ships manifests, not release artifacts. App versions and licenses belong to their upstream projects. A bucket release workflow, release reminder, and bucket SemVer are inapplicable. Preserve existing history, tags, releases, and public URLs. Repository contributions use MIT; see `LICENSE`.
