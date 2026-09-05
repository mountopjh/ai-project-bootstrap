# 🚀 通用 AI 项目启动器 (ai-project-bootstrap)

<div align="center">

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PowerShell 7](https://img.shields.io/badge/PowerShell-7%2B-blue.svg)](https://learn.microsoft.com/powershell/)
[![Python 3.8+](https://img.shields.io/badge/Python-3.8%2B-green.svg)](https://www.python.org/)
[![Token Cost](https://img.shields.io/badge/Token%20Cost-0%20Zero-brightgreen.svg)](#)

**打破 AI 编程“越改越乱”、“Token 越用越贵”、“对话关掉就丢”的痛点！跨 AI 协作与上下文治理脚手架**

</div>

---

## 💡 核心解决的问题

1. **上下文污染与幻觉**：避免全量传参爆 Token，通过 `PROJECT_INDEX.md`、`DEVELOPMENT_MAP.md`、`CODE_MAP.md` 三层地图精准治理上下文。
2. **单一真理源**：以 `AGENTS.md` 为统一规则源，杜绝不同 AI / IDE 规则失效或矛盾。
3. **对话记录自动归档**：集成 Codex 生命周期钩子 (`.codex/hooks.json`) 与通用 CLI 存档脚本，静默无感保存本地 Markdown 对话履历。
4. **零 Token 消耗**：初始化、完整性校验、冲突保护与备份升级完全由本地 PowerShell / Python 引擎硬核执行。
5. **命名与放置规范**：规则模板强制文件名自解释、按功能职责归类放置，杜绝 `temp`、`new`、`未命名` 等无信息量命名与文件随意堆放。

---

## 🛠️ 快速开始

### 方式一：安装为本机全局常驻命令（强烈推荐）

在任何电脑克隆或下载本仓库后，运行一次一键安装脚本即可将快捷命令注入 PowerShell `$PROFILE`：

```powershell
# 一键全局安装（Windows PowerShell 7+）
pwsh -File .\install.ps1

# 或 Python 3.8+ 版本
python install.py
```

安装完成后，在**任何项目目录**（无论在哪个盘符或深层路径），打开终端即可直接使用：

```powershell
# 1. 在当前项目目录一键初始化（0.2秒完成，0 Token）
ai-init

# 2. 换电脑或移动目录后，一键刷新本机 hooks 并补齐文件
ai-repair

# 3. 检查当前项目规范完整性
ai-check

# 4. 安全升级模板（自动备份修改）
ai-upgrade -Force
```

> **提示**：以上命令默认作用于当前目录（`.`），也可指定路径，例如 `ai-init "D:\my-project"`。如需卸载全局函数，运行 `pwsh -File .\install.ps1 -Uninstall` 即可。

---

### 方式二：直接通过脚本调用

无需全局安装，直接运行核心脚本（目标路径 `-TargetPath` 默认为当前目录 `.`）：

```powershell
# 1. 初始化新项目规范
pwsh -File .\AI_PROJECT_BOOTSTRAP\bootstrap.ps1 init

# 2. 检查项目完整性
pwsh -File .\AI_PROJECT_BOOTSTRAP\bootstrap.ps1 check

# 3. 无损修复缺失模板与本机 hooks
pwsh -File .\AI_PROJECT_BOOTSTRAP\bootstrap.ps1 repair

# 4. 安全升级（自动增量备份原修改）
pwsh -File .\AI_PROJECT_BOOTSTRAP\bootstrap.ps1 upgrade -Force
```

---

## 📄 开源协议
MIT License © [mountopjh](https://github.com/mountopjh)
