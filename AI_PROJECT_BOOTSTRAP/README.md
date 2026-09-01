# 通用 AI 项目启动器

`AI_PROJECT_BOOTSTRAP` 用于在新项目开始前安装统一协作规范、分层上下文、开发地图、代码地图、历史归档和本地对话记录工具。

## 快速使用

Windows PowerShell 7：

```powershell
.\AI_PROJECT_BOOTSTRAP\bootstrap.ps1 init -TargetPath "目标项目目录"
```

Python 标准库版本：

```text
python AI_PROJECT_BOOTSTRAP/bootstrap.py init --target "目标项目目录"
```

支持模式：

- `init`：只初始化没有冲突的新项目。
- `check`：只读检查完整性、路径、模板变量和时间格式。
- `upgrade`：升级受管理文件；检测到人工修改时停止，使用明确的强制选项才会先备份再覆盖。
- `repair`：补齐缺失文件，并重新生成当前机器专用的本地文件；不覆盖其他已有文件。

PowerShell 强制升级参数为 `-Force`；Python 为 `--force`。备份目录使用 `archive/bootstrap/YYYYMMDD-HHMMSS/`。

`upgrade` 只替换由初始化器管理的规则、入口和工具文件；开发地图、代码地图、项目索引与对话索引属于项目状态，不会被覆盖。`repair` 也只补缺失内容及重新生成本地文件。

### 本机 Codex 钩子

`.codex/hooks.json` 包含当前机器和项目路径，不应提交到 Git。新项目首次使用时运行 `init` 生成；已有项目 clone 到新机器或移动路径后，运行一次 `repair` 重新生成本机可用的钩子配置，也可在已有本地登记信息时通过 `upgrade` 更新。

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
