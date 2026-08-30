#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import uuid
from pathlib import Path


def main() -> int:
    if hasattr(sys.stdin, "reconfigure"):
        sys.stdin.reconfigure(encoding="utf-8")
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root")
    arguments = parser.parse_args()
    raw = sys.stdin.read()
    if not raw.strip():
        return 0
    payload = json.loads(raw)
    project_root = (
        Path(arguments.project_root).expanduser().resolve()
        if arguments.project_root
        else Path(__file__).resolve().parents[1]
    )
    hook_path = project_root / ".codex" / "hooks" / "archive_conversation.py"
    if not hook_path.is_file():
        raise FileNotFoundError("未找到项目对话归档器。")

    session_id = str(payload.get("session_id") or f"generic-{uuid.uuid4().hex}")
    turn_id = str(payload.get("turn_id") or f"turn-{uuid.uuid4().hex}")
    model = str(payload.get("model") or "generic-ai")
    common = {
        "session_id": session_id,
        "turn_id": turn_id,
        "cwd": str(project_root),
        "model": model,
        "permission_mode": "default",
    }
    prompt_event = {**common, "hook_event_name": "UserPromptSubmit", "prompt": str(payload.get("user") or "")}
    stop_event = {
        **common,
        "hook_event_name": "Stop",
        "stop_hook_active": False,
        "last_assistant_message": str(payload.get("assistant") or ""),
    }
    command = [sys.executable, str(hook_path), "--project-root", str(project_root)]
    subprocess.run(
        command,
        input=json.dumps(prompt_event, ensure_ascii=False),
        text=True,
        encoding="utf-8",
        check=True,
        capture_output=True,
    )
    subprocess.run(
        command,
        input=json.dumps(stop_event, ensure_ascii=False),
        text=True,
        encoding="utf-8",
        check=True,
        capture_output=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
