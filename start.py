#!/usr/bin/env python3
"""Initialize or repair the cloned project with one local command."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parent
BOOTSTRAP = PROJECT_ROOT / "AI_PROJECT_BOOTSTRAP" / "bootstrap.py"
METADATA = PROJECT_ROOT / ".ai-project-bootstrap.json"


def detect_hook_status() -> tuple[str, bool, str]:
    """Detect whether the current IDE has a known auto-archive hook wired up."""
    is_kiro = os.environ.get("TERM_PROGRAM") == "kiro"
    kiro_hook_path = PROJECT_ROOT / ".kiro" / "hooks" / "archive-conversation.kiro.hook"
    kiro_hook_ready = is_kiro and kiro_hook_path.is_file()

    if is_kiro and kiro_hook_ready:
        message = (
            "检测到 Kiro 环境：.kiro/hooks/archive-conversation.kiro.hook 已生成并默认启用，"
            "每轮对话结束会自动归档，无需额外信任步骤。"
        )
    elif is_kiro:
        message = (
            "检测到 Kiro 环境，但未能确认 .kiro/hooks/archive-conversation.kiro.hook 已生成；"
            "请运行 repair 后重试，或改用 tools/record_conversation.py 手动归档。"
        )
    else:
        message = (
            "未检测到已知的自动钩子环境（当前 TERM_PROGRAM 非 kiro）。Codex 用户可信任 "
            ".codex/hooks.json 后自动归档；其他 IDE 请在每轮结束后手动运行 "
            "tools/record-conversation.ps1 或 tools/record_conversation.py。"
        )
    detected_ide = "kiro" if is_kiro else "unknown"
    return detected_ide, kiro_hook_ready, message


def invoke(action: str) -> tuple[int, dict[str, object] | None, str]:
    process = subprocess.run(
        [sys.executable, str(BOOTSTRAP), action, "--target", str(PROJECT_ROOT)],
        text=True,
        encoding="utf-8",
        capture_output=True,
    )
    text = (process.stdout if process.stdout.strip() else process.stderr).strip()
    try:
        result = json.loads(text) if text else None
    except json.JSONDecodeError:
        result = None
    return process.returncode, result, text


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    if not BOOTSTRAP.is_file():
        print(f"未找到启动器核心脚本：{BOOTSTRAP}", file=sys.stderr)
        return 1

    mode = "repair" if METADATA.is_file() else "init"
    exit_code, result, output = invoke(mode)
    if exit_code or result is None:
        print(output or "启动器未返回有效结果。", file=sys.stderr)
        return exit_code or 1

    check_code, check, check_output = invoke("check")
    if check_code or check is None or not check.get("ok"):
        failure = {
            "action": "start",
            "ok": False,
            "mode": mode,
            "project_root": str(PROJECT_ROOT),
            "issues": check.get("issues", []) if check else [check_output or "完整性检查失败"],
        }
        print(json.dumps(failure, ensure_ascii=False, indent=2), file=sys.stderr)
        return check_code or 1

    detected_ide, kiro_hook_active, hook_status_message = detect_hook_status()
    response = {
        "action": "start",
        "ok": True,
        "mode": mode,
        "project_root": str(PROJECT_ROOT),
        "changed": result.get("changed", []),
        "ai_entry": str(PROJECT_ROOT / "START_HERE.md"),
        "hook_config": str(PROJECT_ROOT / ".codex" / "hooks.json"),
        "hook_trust_required": True,
        "detected_ide": detected_ide,
        "kiro_hook_active": kiro_hook_active,
        "hook_status_message": hook_status_message,
        "message": (
            "启动完成。AI 只需先读取项目根目录 START_HERE.md；无需逐个分析 "
            "AI_PROJECT_BOOTSTRAP 源码。Codex 自动对话归档仍需用户审核并信任 "
            ".codex/hooks.json，然后在新会话中生效。"
        ),
    }
    print(json.dumps(response, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
