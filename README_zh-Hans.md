<div align="center">
    <h1>🎐 Zephyr</h1>
    <p>轻盈精巧的工具，让工作如风般流畅。</p>
    <p>
        <a href="https://github.com/Hezric/ScoopZephyr/actions/workflows/ci.yml"><img src="https://github.com/Hezric/ScoopZephyr/actions/workflows/ci.yml/badge.svg" alt="清单测试与提交规范检查"></a>
        <a href="https://github.com/Hezric/ScoopZephyr/actions/workflows/excavator.yml"><img src="https://github.com/Hezric/ScoopZephyr/actions/workflows/excavator.yml/badge.svg" alt="自动更新应用清单"></a>
    </p>
    <p><a href="README.md">English</a> | 简体中文</p>
</div>

一个小而用心的 Windows [Scoop](https://scoop.sh) 软件源，收拢顺手的工具，把更多心力留给值得做的事。

## 安装

在 PowerShell 中添加软件源，再安装需要的应用：

```pwsh
scoop bucket add zephyr https://github.com/Hezric/ScoopZephyr
scoop install zephyr/<app_name>
```

## 交给智能体

也可以让编程智能体替你推开这扇窗：

```text
请在这台 Windows 电脑上添加 ScoopZephyr 软件源：
scoop bucket add zephyr https://github.com/Hezric/ScoopZephyr
运行 scoop bucket list，确认添加成功。然后阅读
https://github.com/Hezric/ScoopZephyr 的应用表，帮我挑选需要的工具。
每安装一个工具，都按它的文档运行版本或帮助命令，确认可以使用。
Earmuff 和 Homing 只检查可执行文件存在，不启动程序；启动可能改变音量或 Wi-Fi 状态。
保留现有设置和启动注册。
```

## 应用

| 清单 | 说明 | 上游项目 |
| --- | --- | --- |
| `autohotkey` | 默认安装 `Ahk2Exe`，并将 `AHK_HOME` 指向 AutoHotkey 根目录。 | [AutoHotkey](https://github.com/AutoHotkey/AutoHotkey) |
| `codex-acp` | 面向 Windows 的 Codex ACP 适配器，适用于 Zed 等兼容客户端。 | [codex-acp](https://github.com/zed-industries/codex-acp) |
| `cua-driver` | Cua 的跨平台桌面自动化驱动程序。 | [Cua](https://github.com/trycua/cua) |
| `earmuff` | 按 Windows 输出设备守住音量上限，缓和突然的音量跳变。 | [Earmuff](https://github.com/Hezric/Earmuff) |
| `homing` | 在已保存的 Wi-Fi 网络断开后，自动尝试重新连接。 | [Homing](https://github.com/Hezric/Homing) |
| `lineup` | 以 JSON 为主要接口的 Windows 启动项管理器。 | [Lineup](https://github.com/Hezric/Lineup) |

## 参与贡献

清单测试与贡献方式见 [CONTRIBUTING.md](CONTRIBUTING.md)，完整交付规则见 [AGENTS.md](AGENTS.md)。GitHub Issues 是正式任务跟踪系统：规格使用父议题，实施任务使用原生子议题，以 `ready-for-agent`、`in-progress`、`blocked` 和 `done` 标签标记状态。英文 README 为准，中文版本同步维护。

提交须签名，提交信息与 PR 标题采用带作用域的小写 Conventional Commits，分支命名为 `<type>/<short-desc>`。`test` 与 `policy` 是必需检查，守护签名完整、历史线性的 main；常规变更通过 squash PR 合入。[自动更新](docs/features/manifest-updates.md)先在暂存分支生成已验证的机器人提交，运行相同测试与 PR 规范检查，再将通过检查的更新 squash 合入 main，不设绕过规则的例外。Dependabot 每周分组更新 GitHub Actions，通过检查后自动 squash 合并。

软件源仅分发清单，不发布构建产物。仓库代码采用 [MIT 许可证](LICENSE)，各应用仍遵循其上游许可证。
