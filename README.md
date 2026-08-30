# 🚀 通用 AI 项目启动器 (AI-Project-Bootstrap)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Python 3.8+](https://img.shields.io/badge/Python-3.8%2B-green.svg)](https://www.python.org/)
[![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://learn.microsoft.com/powershell/)
[![Token Cost](https://img.shields.io/badge/Token%20Cost-0%20Zero-brightgreen.svg)](#-token-使用说明)

> **打破 AI 编程“越改越乱”、“Token 越用越贵”、“对话关掉就丢”的痛点！**
> 专为 **Codex / Cursor / Windsurf / Claude Desktop / VSCode AI** 等研发的跨 AI 协作与上下文治理脚手架。

---

## 💡 为什么需要这个启动器？

在使用 AI 助手辅助开发时，你是否遇到过以下问题：
1. **上下文污染/幻觉**：项目文件越来越多，把整个项目传给 AI 导致上下文爆满，AI 视线混乱甚至产生代码幻觉。
2. **重复消费 Token**：每次新建项目都要复制一堆 System Prompt 或规则说明，不仅繁琐还持续浪费昂贵的上下文 Token。
3. **对话记录丢失**：AI 帮助做出的关键架构决策、修改思路在关闭聊天窗口后彻底消失，无法复盘和留存知识。
4. **规则冲突**：缺少单一规则源，AI 自由发挥修改了不该改的文件。

`AI_PROJECT_BOOTSTRAP` 通过**单命令脚手架**，一键为任何新旧项目植入**统一协作规范、三层分层上下文、代码与开发地图、人工修改保护及本地零 Token 对话自动归档系统**！

---

## ✨ 核心特性

- ⚡ **零 Token 消耗 (Zero Token Overhead)**：初始化、框架检查、冲突校验、增量升级、备份归档及对话保存完全在本地 PowerShell / Python 脚本中硬核执行，**0 外部 API 调用**。
- 📜 **单一真理源 (`AGENTS.md`)**：项目规范只定义在一个地方，Codex 钩子、AI 引导入口(`START_HERE.md`)等全部集中指向 `AGENTS.md`，杜绝多份规则失效或矛盾。
- 🗺️ **三层上下文地图机制**：
  - `PROJECT_INDEX.md`：项目定位与核心技术栈索引。
  - `DEVELOPMENT_MAP.md`：当前开发状态、阶段目标与待办事项。
  - `CODE_MAP.md`：项目目录分布与核心模块职责说明。
- 💾 **自动与通用对话归档**：
  - **Codex 原生支持**：利用内置生命周期钩子（`UserPromptSubmit` / `Stop`），在后台静默保存完整对话 Markdown 与动态时间索引 `INDEX.md`。
  - **通用 AI 工具链**：内置通用 CLI 命令行记录工具 (`tools/record_conversation.py` / `record-conversation.ps1`)。
- 🛡️ **智能保护与安全升级**：
  - `init`：安全初始化，避免覆盖已有文件。
  - `check`：只读校验文件完整性、格式规范与时间戳。
  - `repair`：无损补齐缺失模版，绝不覆盖个人项目状态。
  - `upgrade`：升级脚手架版本；若检测到人工修改将主动提示保护，指定 `--force` / `-Force` 时先创建 `archive/bootstrap/YYYYMMDD-HHmmss` 增量备份再替换。

---

## 🛠️ 快速开始

### 1. PowerShell 环境 (Windows 推荐)

```powershell
# 初始化目标项目
.\AI_PROJECT_BOOTSTRAP\bootstrap.ps1 init -TargetPath "你的目标项目路径"

# 检查项目启动器完整性
.\AI_PROJECT_BOOTSTRAP\bootstrap.ps1 check -TargetPath "你的目标项目路径"
```

### 2. Python 环境 (跨平台 Linux / macOS / Windows)

```bash
# 初始化目标项目
python AI_PROJECT_BOOTSTRAP/bootstrap.py init --target "你的目标项目路径"

# 检查项目启动器完整性
python AI_PROJECT_BOOTSTRAP/bootstrap.py check --target "你的目标项目路径"
```

---

## ⚙️ 支持模式详解

| 模式命令 | 作用说明 | 冲突处理 |
| :--- | :--- | :--- |
| `init` | 初始化新项目基础规范 | 目标项目若已有受管理文件则停止操作，安全第一 |
| `check` | 检查项目规范完整性 | 只读模式，校验路径、哈希、时间戳格式与未解析变量 |
| `repair` | 修复缺失文件 | 只补齐缺失文件或模板，保留已有修改 |
| `upgrade` | 升级脚手架管理文件 | 自动校验哈希；检测到人工修改时暂停，加 `--force` / `-Force` 自动备份后覆盖 |

---

## 🤖 异构 AI 兼容指南

1. **Codex 平台**：自动挂载 `.codex/hooks.json`，在用户提问与 AI 结束回答时自动捕获并无感写入 `archive/conversations/`。
2. **具有文件读取能力的 AI (如 Cursor / Windsurf)**：引导 AI 从目标项目的 `START_HERE.md` 开始阅读，遵守 `AGENTS.md` 约束。
3. **无自动文件关联功能的 AI**：直接将目标项目生成的 `AI_START_PROMPT.md` 内容作为第一条 Prompt 发送。
4. **命令行工具集成**：在 CLI 对话结束后调用 `tools/record_conversation.py` 或 `tools/record-conversation.ps1` 传入对话内容即可完成存档。

---

## 📂 项目结构说明

```text
AI_PROJECT_BOOTSTRAP/
├── manifest.json              # 脚手架文件配置清单与哈希策略
├── bootstrap.py               # Python 标准库初始化/校验/升级引擎
├── bootstrap.ps1              # PowerShell 7/5.1 引擎
├── START_HERE.md              # 启动器入口说明
├── README.md                  # 脚手架内部说明
├── adapters/                  # 各 AI 适配器钩子与工具
│   ├── codex/                 # Codex 钩子 (archive_conversation.py / ps1)
│   └── generic/               # 通用对话记录工具 (record_conversation.py / ps1)
├── templates/                 # 规范模版集合
│   ├── AGENTS.md.template     # AI 协作主规则模版
│   ├── DEVELOPMENT_MAP.md.template
│   ├── CODE_MAP.md.template
│   └── PROJECT_INDEX.md.template
└── tests/                     # 自动化集成测试套件 (Python & PowerShell)
```

---

## 🧪 单元与集成测试

自带隔离环境自检脚本，每次运行都会在系统临时目录创建临时项目验证初始化、冲突保护、备份归档和对话记录逻辑：

```bash
# Python 测试
python AI_PROJECT_BOOTSTRAP/tests/run_tests.py

# PowerShell 测试
powershell -ExecutionPolicy Bypass -File .\AI_PROJECT_BOOTSTRAP\tests\run-tests.ps1
```

---

## 📄 开源协议

本项目采用 [MIT License](LICENSE) 开源协议，欢迎星标 ⭐️、Fork 与 Pull Request！
