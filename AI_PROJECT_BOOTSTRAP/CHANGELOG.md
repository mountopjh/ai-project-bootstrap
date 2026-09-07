# 更新日志

本项目的所有重要变更都记录在此文件中。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

### 新增

- 新增根目录 `start.ps1` 与 `start.py`：空项目目录克隆仓库后可用单个命令完成首次初始化、重复无损修复和完整性检查，无需先安装全局函数。
- 一键启动结果明确指定 `START_HERE.md` 为 AI 唯一入口，并补充回归测试，确保 AI 不必逐个分析 `AI_PROJECT_BOOTSTRAP/` 源码。

### 变更

- 严格规范复述前置条件：明确只要涉及项目开发、代码开发、代码修改（含重构优化与缺陷修复）、增加功能，以及变更外部状态的任务，均强制先复述目标、范围、约束、预期结果和可核对方案；纯咨询仅限于不产生代码实现与修改的只读场景，防止 AI 跳过复述直接答复或执行。
- 重构 `AGENTS.md` 规则：区分只读请求与变更任务，明确授权范围及持续时间，并补充上级指令优先级、工作区保护、敏感信息、破坏性操作和验证交付要求。
- 将工作目录、命名、放置和时间格式规则改为带明确边界与生态例外的约束；归档正文保持不可修改，索引允许追加和更新时间。
- 强制规则集中到 `AGENTS.md`，`START_HERE.md`、`AI_START_PROMPT.md` 和 `PROJECT_INDEX.md` 仅保留入口、能力说明与上下文路由。

## [1.3.0] - 2026-09-05

### 新增

- 增加全局常驻脚手架与一键安装配置：新增根目录 `install.ps1` 与 `install.py`，并在 `bootstrap.ps1` 与 `bootstrap.py` 中增加 `install` 模式。自动适配 `$HOME/.ai-project-bootstrap`，并在用户 PowerShell `$PROFILE` 中幂等注入 `ai-init`、`ai-repair`、`ai-check`、`ai-upgrade` 全局快捷函数，支持一键卸载（`-Uninstall`）。
- `bootstrap.ps1` 与 `bootstrap.py` 将目标路径参数设为可选并默认指向当前目录（`.`），无需手动拼接或传递目标路径。
- 新增全局安装、卸载与默认目标路径的自动化测试用例。

### 变更

- 完善快速开始文档，首推全局快捷命令作为第一使用姿势，彻底解决不同项目路径不一致、换机换盘及每次新建项目需临时 clone 仓库的问题。

## [1.2.0] - 2026-09-03

### 新增

- 规则模板增加「命名与放置」一节：文件名必须自解释到任何AI仅凭名称即可判断功能，不限定命名语言与分隔符风格；文件须按功能职责归类放置，禁止无信息量命名与随意堆放。该节只约束今后新增和改动的文件，不追溯既有文件。

### 变更

- 归档快照命名由 `YYYYMMDD-HHMMSS` 改为 `YYYYMMDD-HHMMSS_简介`，简介不超过10字且能看出归档内容；并在「时间格式」一节明确该后缀属于允许形式，与对话归档脚本既有的 `时间戳_标题.md` 实现保持一致。

## [1.1.1] - 2026-09-01

### 修复

- `tools/record-conversation.ps1` 在 `Set-StrictMode` 下访问缺失的 `session_id`/`turn_id`/`model`/`user`/`assistant` 属性会直接崩溃，导致不提供这些字段的调用方（如 Kiro IDE 的 `agentStop` hook）无法归档对话。改为通过 `PSObject.Properties` 安全读取，行为与 Python 版本（`record_conversation.py`，本身已用 `dict.get()`）保持一致。
- 新增 PowerShell 与 Python 回归测试，覆盖"仅提供 user/assistant/model，不提供 session_id/turn_id"的最小请求场景。

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
