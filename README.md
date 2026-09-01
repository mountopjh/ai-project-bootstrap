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

---

## 🛠️ 快速开始

```powershell
# 1. 检查目标项目完整性
pwsh -File .\AI_PROJECT_BOOTSTRAP\bootstrap.ps1 check -TargetPath "目标项目路径"

# 2. 初始化新项目规范
pwsh -File .\AI_PROJECT_BOOTSTRAP\bootstrap.ps1 init -TargetPath "目标项目路径"

# 3. 无损修复缺失模板
pwsh -File .\AI_PROJECT_BOOTSTRAP\bootstrap.ps1 repair -TargetPath "目标项目路径"

# 4. 安全升级（自动增量备份原修改）
pwsh -File .\AI_PROJECT_BOOTSTRAP\bootstrap.ps1 upgrade -TargetPath "目标项目路径" -Force
```

---

## 📄 开源协议
MIT License © [mountopjh](https://github.com/mountopjh)
