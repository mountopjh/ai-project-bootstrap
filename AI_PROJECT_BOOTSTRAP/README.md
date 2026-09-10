# 通用 AI 项目启动器

`AI_PROJECT_BOOTSTRAP` 用于在新项目开始前安装统一协作规范、分层上下文、开发地图、代码地图、历史归档和本地对话记录工具。

## 快速使用

### 空项目目录一句话启动（推荐）

仓库克隆到空项目目录后，用支持读取 `AGENTS.md` 和执行本地命令的 AI IDE 打开仓库根目录，发送以下任一条完整消息：

```text
初始化
```

```text
初始化启动器
```

仓库根目录预置的首次启动 `AGENTS.md` 会让 IDE 自动运行 `start.ps1` 或 `start.py`。首次运行自动执行 `init`，重复运行自动执行 `repair`，随后运行 `check`。成功后，AI 只读取根目录 `START_HERE.md`，再按项目索引按需加载上下文；无需逐个分析 `AI_PROJECT_BOOTSTRAP/` 源码。

IDE 的本地命令权限确认，以及 Codex 对 `.codex/hooks.json` 的首次安全审核与信任，仍必须由用户完成。若 IDE 不支持上述能力，可手动运行 `pwsh -NoProfile -File .\start.ps1` 或 `python start.py`。

### 全局一键命令（可选）

在仓库根目录下运行一次 `pwsh -File .\install.ps1`（或 `python install.py`），即可在终端任何项目路径直接使用：
- `ai-init`：在当前目录初始化新项目。
- `ai-repair`：在当前目录无损补齐缺失模板并重新生成本机 `.codex/hooks.json`。
- `ai-check`：检查当前项目完整性。
- `ai-upgrade -Force`：强制升级受管理模板（自动备份历史修改）。

### 脚本直接调用

Windows PowerShell 7：

```powershell
# 目标路径参数 -TargetPath 默认为当前目录（.），可省略
.\AI_PROJECT_BOOTSTRAP\bootstrap.ps1 init
```

Python 标准库版本：

```text
# 目标路径参数 --target 默认为当前目录（.），可省略
python AI_PROJECT_BOOTSTRAP/bootstrap.py init
```

支持模式：

- `init`：只初始化没有冲突的新项目。
- `check`：只读检查完整性、路径、模板变量和时间格式。
- `upgrade`：升级受管理文件；检测到人工修改时停止，使用明确的强制选项才会先备份再覆盖。
- `repair`：补齐缺失文件，并重新生成当前机器专用的本地文件；不覆盖其他已有文件。
- `install`：全局注册 `ai-init` / `ai-repair` / `ai-check` / `ai-upgrade` 快捷命令至 PowerShell `$PROFILE` 并同步脚手架至 `$HOME/.ai-project-bootstrap`。

PowerShell 强制升级参数为 `-Force`；Python 为 `--force`。备份目录使用 `archive/bootstrap/YYYYMMDD-HHMMSS/`。

`upgrade` 只替换由初始化器管理的规则、入口和工具文件；开发地图、代码地图、项目索引与对话索引属于项目状态，不会被覆盖。`repair` 也只补缺失内容及重新生成本地文件。

### 本机 Codex 钩子

`.codex/hooks.json` 包含当前机器和项目路径，不应提交到 Git。新项目首次使用时运行 `init` 生成；已有项目 clone 到新机器或移动路径后，运行一次 `repair` 重新生成本机可用的钩子配置，也可在已有本地登记信息时通过 `upgrade` 更新。

在目标项目根目录运行 `ai-init` 后，用 Codex 打开该项目并信任本地钩子，再开启一个新会话。每轮“用户消息 + AI 回答”完成时，钩子都会在本地写入 `archive/conversations/YYYYMMDD-HHMMSS_请求摘要.md` 并更新 `INDEX.md`。摘要取有效用户请求、移除文件名非法字符；消息缺失时会明确标注为“用户消息缺失”或“用户消息未捕获”，不会产生“未命名”文件。归档写入不调用模型或外部 API，也不会额外消耗 Token。

### 其他 AI IDE 指引

启动器可以在任意 AI IDE 打开的**目标项目根目录**中初始化和执行；`ai-init` 的默认目标就是当前目录 `.`。通用规则由 `AGENTS.md` 和 `START_HERE.md` 提供，所有任务都应在该项目目录内运行。

当前仅 Codex 已接入自动生命周期钩子。其他 IDE 若能调用本地命令，可在每轮对话结束后把 JSON 输入传给项目内的 `tools/record-conversation.ps1` 或 `tools/record_conversation.py`，复用相同的 Markdown 归档器；没有可用生命周期钩子的 IDE 不能保证自动归档。后续应按各 IDE 的官方钩子机制新增适配器，而不是假定存在通用钩子。

## 自检

```powershell
.\AI_PROJECT_BOOTSTRAP\tests\run-tests.ps1
```

```text
python AI_PROJECT_BOOTSTRAP/tests/run_tests.py
```

测试在系统临时目录创建隔离项目，覆盖初始化、检查、补缺、冲突保护、强制升级备份、状态保留和对话归档，结束后仅清理本次测试目录。

## AI 兼容策略

- Codex：使用项目 `AGENTS.md` 与 `.codex/hooks.json`。
- 能读取项目文件的其他AI：从 `START_HERE.md` 开始。
- 无自动规则发现能力的AI：把 `AI_START_PROMPT.md` 作为第一条提示发送。
- 支持本地命令但没有生命周期钩子的AI：调用 `tools/record-conversation.ps1` 或 `tools/record_conversation.py` 保存对话。
- 不能读取文件或执行本地命令的AI无法自动保存对话，只能人工调用记录工具。

规则只存在于 `AGENTS.md`；其他入口只负责指向它，避免多份规则失效或冲突。

当前授权口令尚未配置化；修改“执行任务”口令时，需要同步修改 `templates/AGENTS.md.template`、`adapters/codex/archive-conversation.ps1` 和 `adapters/codex/archive_conversation.py`。

## Token 使用

初始化、校验、升级、修复、标题生成、对话保存和索引维护均在本地执行，不调用模型或外部 API。AI读取项目规则仍会占用正常上下文；索引模式会限制默认读取范围。

## Codex 信任

项目本地 Codex 钩子首次安装或发生变化后，需要在新运行中审核并信任。初始化器不会绕过该安全机制。
