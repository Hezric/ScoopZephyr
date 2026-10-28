<div align="center">
    <h1>🎐 Zephyr</h1>
    <p>Lightweight, refined tools for seamless workflows.</p>
    <p>
        <a href="https://github.com/Hezric/scoop-zephyr/actions/workflows/ci.yml"><img src="https://github.com/Hezric/scoop-zephyr/actions/workflows/ci.yml/badge.svg" alt="Bucket tests and policy"></a>
        <a href="https://github.com/Hezric/scoop-zephyr/actions/workflows/excavator.yml"><img src="https://github.com/Hezric/scoop-zephyr/actions/workflows/excavator.yml/badge.svg" alt="Automatic manifest updates"></a>
    </p>
    <p>English | <a href="README_zh-Hans.md">简体中文</a></p>
</div>

A small [Scoop](https://scoop.sh) bucket for Windows, gathering useful tools that leave room for the work you care about.

## Install

Add the bucket in PowerShell, then choose an app:

```pwsh
scoop bucket add zephyr https://github.com/Hezric/scoop-zephyr
scoop install zephyr/<app_name>
```

## Apps

| Manifest | Description | Upstream |
| --- | --- | --- |
| `autohotkey` | Includes `Ahk2Exe` and sets `AHK_HOME` to the AutoHotkey root. | [AutoHotkey](https://github.com/AutoHotkey/AutoHotkey) |
| `codex-acp` | Codex ACP adapter for compatible Windows clients such as Zed. | [codex-acp](https://github.com/zed-industries/codex-acp) |
| `cua-driver` | Cross-platform desktop automation driver for Cua. | [Cua](https://github.com/trycua/cua) |
| `lineup` | A JSON-first Windows startup manager. | [Lineup](https://github.com/Hezric/Lineup) |

## Contribute

See [CONTRIBUTING.md](CONTRIBUTING.md) for manifest tests and contributions, and [AGENTS.md](AGENTS.md) for the complete delivery rules. GitHub Issues is the tracker; specifications use parent issues and tickets use native sub-issues, with `ready-for-agent`, `in-progress`, `blocked`, and `done` labels.

Use signed commits, lowercase scoped Conventional Commits and PR titles, and `<type>/<short-desc>` branches. Required `test` and `policy` checks guard a signed, linear main; changes normally land through squash PRs. [Automatic updates](docs/features/manifest-updates.md) stage verified bot commits, run those same checks and PR policy, and squash-merge the checked update without a bypass. Dependabot groups GitHub Actions updates weekly and auto squash-merges them after checks.

The bucket ships manifests rather than release artifacts. Repository code is [MIT licensed](LICENSE); each app retains its upstream license.
