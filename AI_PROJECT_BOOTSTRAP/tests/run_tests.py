#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import tempfile
import uuid
from datetime import datetime
from pathlib import Path

BOOTSTRAP = Path(__file__).resolve().parents[1]
SCRIPT = BOOTSTRAP / "bootstrap.py"


def run(*arguments: str, expected: int = 0) -> dict:
    process = subprocess.run(
        [sys.executable, str(SCRIPT), *arguments],
        text=True,
        encoding="utf-8",
        capture_output=True,
    )
    if process.returncode != expected:
        raise AssertionError(
            f"退出码 {process.returncode}，预期 {expected}\n"
            f"stdout:\n{process.stdout}\nstderr:\n{process.stderr}"
        )
    stream = process.stdout if process.stdout.strip() else process.stderr
    return json.loads(stream)


def main() -> int:
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    prefix = f"AI_PROJECT_BOOTSTRAP_TEST_{stamp}_"
    target = Path(tempfile.mkdtemp(prefix=prefix)).resolve()
    try:
        assert run("init", "--target", str(target))["ok"]
        assert run("check", "--target", str(target))["ok"]
        (target / "START_HERE.md").unlink()
        repaired = run("repair", "--target", str(target))
        assert "START_HERE.md" in repaired["changed"]

        (target / ".ai-project-bootstrap.json").unlink()
        stale_hook_marker = r"C:\stale-machine\wrong-project\archive-conversation.py"
        (target / ".codex/hooks.json").write_text(stale_hook_marker, encoding="utf-8")
        local_repair = run("repair", "--target", str(target))
        assert ".codex/hooks.json" in local_repair["changed"]
        repaired_hook = (target / ".codex/hooks.json").read_text(encoding="utf-8")
        assert stale_hook_marker not in repaired_hook
        local_check = run("check", "--target", str(target))
        assert local_check["ok"] and not any(
            "未指向当前项目" in issue for issue in local_check["issues"]
        )

        state_marker = "\n测试状态必须保留。\n"
        managed_marker = "\n测试人工修改。\n"
        with (target / "DEVELOPMENT_MAP.md").open("a", encoding="utf-8") as stream:
            stream.write(state_marker)
        with (target / "AGENTS.md").open("a", encoding="utf-8") as stream:
            stream.write(managed_marker)
        conflict = run("upgrade", "--target", str(target), expected=1)
        assert not conflict["ok"] and "人工修改" in conflict["error"]
        upgraded = run("upgrade", "--target", str(target), "--force")
        assert upgraded["ok"] and "backup" in upgraded
        assert state_marker.strip() in (target / "DEVELOPMENT_MAP.md").read_text(encoding="utf-8")
        backup_agents = Path(upgraded["backup"]) / "AGENTS.md"
        assert managed_marker.strip() in backup_agents.read_text(encoding="utf-8")
        assert run("check", "--target", str(target))["ok"]

        payload = {
            "session_id": f"test-{uuid.uuid4().hex}",
            "turn_id": f"turn-{uuid.uuid4().hex}",
            "model": "local-test",
            "user": "验证通用记录工具",
            "assistant": "记录成功",
        }
        recorder = target / "tools/record_conversation.py"
        process = subprocess.run(
            [sys.executable, str(recorder), "--project-root", str(target)],
            input=json.dumps(payload, ensure_ascii=False),
            text=True,
            encoding="utf-8",
            capture_output=True,
        )
        if process.returncode:
            raise AssertionError(process.stderr)
        conversations = [
            path
            for path in (target / "archive/conversations").glob("*.md")
            if path.name != "INDEX.md"
        ]
        assert len(conversations) == 1
        assert re.fullmatch(r"\d{8}-\d{6}_.+\.md", conversations[0].name)
        archived = conversations[0].read_text(encoding="utf-8")
        assert payload["user"] in archived and payload["assistant"] in archived

        minimal_payload = {
            "user": "缺少会话标识的最小请求",
            "assistant": "仍应成功归档",
            "model": "kiro",
        }
        minimal_process = subprocess.run(
            [sys.executable, str(recorder), "--project-root", str(target)],
            input=json.dumps(minimal_payload, ensure_ascii=False),
            text=True,
            encoding="utf-8",
            capture_output=True,
        )
        if minimal_process.returncode:
            raise AssertionError(minimal_process.stderr)
        minimal_conversations = [
            path
            for path in (target / "archive/conversations").glob("*.md")
            if path.name != "INDEX.md" and path.name not in {c.name for c in conversations}
        ]
        assert len(minimal_conversations) == 1
        minimal_archived = minimal_conversations[0].read_text(encoding="utf-8")
        assert minimal_payload["user"] in minimal_archived
        assert minimal_payload["assistant"] in minimal_archived
        print("PYTHON_TESTS_OK")
        return 0
    finally:
        temp_root = Path(tempfile.gettempdir()).resolve()
        if target.parent == temp_root and target.name.startswith(prefix):
            shutil.rmtree(target)


if __name__ == "__main__":
    raise SystemExit(main())
