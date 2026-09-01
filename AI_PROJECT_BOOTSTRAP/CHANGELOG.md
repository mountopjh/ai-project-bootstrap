# 更新日志

本项目的所有重要变更都记录在此文件中。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

## [1.1.0] - 2026-09-01

### 新增

- 增加 Windows CI，在 push 和 pull request 时自动运行 PowerShell 与 Python 测试套件。
- 增加 PowerShell 7 版本前置检查，为误用 Windows PowerShell 5.1 的用户提供清晰提示。

### 修复

- 将 `.codex/hooks.json` 改为本机生成的 `local` 策略，使 `repair` 和 `upgrade` 能在项目移动或 clone 到新机器后重建正确路径，同时不再把该文件纳入 Git 和受管理哈希。
- 增加跨机器旧 hooks 配置的 PowerShell 与 Python 回归测试。

### 已知限制

- 授权口令尚未配置化；修改“执行任务”时，需要同步修改规则模板和 PowerShell、Python 两个 Codex 归档脚本。

## [1.0.0] - 2026-08-27

### 新增

- 首次发布通用 AI 项目启动器。
- 提供 `init`、`check`、`upgrade` 和 `repair` 模式的 PowerShell 与 Python 实现。
- 提供统一协作规则、分层项目上下文、开发与代码地图、归档目录，以及 Codex 和通用 AI 适配器。
- 提供本地对话记录、冲突保护、强制升级备份和双实现测试套件。
