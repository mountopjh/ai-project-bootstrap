#!/usr/bin/env python3
"""Initialize or repair the cloned project with one local command."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parent
BOOTSTRAP = PROJECT_ROOT / "AI_PROJECT_BOOTSTRAP" / "bootstrap.py"
METADATA = PROJECT_ROOT / ".ai-project-bootstrap.json"


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

    response = {
        "action": "start",
        "ok": True,
        "mode": mode,
        "project_root": str(PROJECT_ROOT),
        "changed": result.get("changed", []),
        "ai_entry": str(PROJECT_ROOT / "START_HERE.md"),
        "hook_config": str(PROJECT_ROOT / ".codex" / "hooks.json"),
        "hook_trust_required": True,
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
