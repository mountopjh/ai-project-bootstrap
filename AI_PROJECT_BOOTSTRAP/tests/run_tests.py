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
        agents_text = (target / "AGENTS.md").read_text(encoding="utf-8")
        for required_rule in (
            "项目规则不得声称覆盖上级指令",
            "完整等于“初始化”或“初始化启动器”",
            "纯咨询、解释、状态询问",
            "授权仅覆盖已复述范围，并持续到任务完成",
            "项目开发、代码开发、代码修改",
            "项目子目录或隔离的系统临时目录",
            "保留用户已有改动",
            "不得泄露、写入或提交密钥",
            "修改后运行与风险相称的测试",
            "已生成的归档正文不可修改",
            "生态、框架或工具规定的标准文件名",
            "业务数据、接口协议、数据库",
        ):
            assert required_rule in agents_text
        start_here_text = (target / "START_HERE.md").read_text(encoding="utf-8")
        assert "执行任务时必须以当前项目根目录" not in start_here_text
        ai_prompt_text = (target / "AI_START_PROMPT.md").read_text(encoding="utf-8")
        assert "仅在人类明确发送" not in ai_prompt_text
        assert "不要逐个分析启动器源码" in ai_prompt_text

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

        unmatched_event = {
            "hook_event_name": "Stop",
            "session_id": f"unmatched-{uuid.uuid4().hex}",
            "turn_id": f"turn-{uuid.uuid4().hex}",
            "model": "local-test",
            "last_assistant_message": "未捕获用户消息时仍应有可识别的归档名",
        }
        archiver = target / ".codex/hooks/archive_conversation.py"
        unmatched_process = subprocess.run(
            [sys.executable, str(archiver), "--project-root", str(target)],
            input=json.dumps(unmatched_event, ensure_ascii=False),
            text=True,
            encoding="utf-8",
            capture_output=True,
        )
        if unmatched_process.returncode:
            raise AssertionError(unmatched_process.stderr)
        unmatched_conversations = [
            path
            for path in (target / "archive/conversations").glob("*.md")
            if path.name != "INDEX.md" and path.name not in {c.name for c in conversations + minimal_conversations}
        ]
        assert len(unmatched_conversations) == 1
        assert "用户消息未捕获" in unmatched_conversations[0].name
        assert "未命名" not in unmatched_conversations[0].name
        assert "未匹配" not in unmatched_conversations[0].name

        temp_profile = target / "test_profile.ps1"
        install_res = run("install", "--profile-path", str(temp_profile))
        assert install_res["ok"] and install_res["installed"]
        assert "function ai-init" in temp_profile.read_text(encoding="utf-8")
        uninstall_res = run("install", "--uninstall", "--profile-path", str(temp_profile))
        assert uninstall_res["ok"] and not uninstall_res["installed"]
        assert "function ai-init" not in temp_profile.read_text(encoding="utf-8")

        custom_agents_root = target / "custom-agents-init-conflict"
        custom_agents_root.mkdir()
        (custom_agents_root / "AGENTS.md").write_text("# 用户自定义规则\n", encoding="utf-8")
        custom_conflict = run("init", "--target", str(custom_agents_root), expected=1)
        assert not custom_conflict["ok"] and "AGENTS.md" in custom_conflict["error"]

        quick_start_root = target / "empty-project-download-python"
        quick_start_root.mkdir()
        shutil.copytree(BOOTSTRAP, quick_start_root / "AI_PROJECT_BOOTSTRAP")
        shutil.copy2(BOOTSTRAP.parent / "start.py", quick_start_root / "start.py")
        shutil.copy2(BOOTSTRAP.parent / "AGENTS.md", quick_start_root / "AGENTS.md")
        preinit_agents = (quick_start_root / "AGENTS.md").read_text(encoding="utf-8")
        assert "<!-- AI_PROJECT_BOOTSTRAP_PREINIT -->" in preinit_agents
        assert "初始化启动器" in preinit_agents
        quick_start = subprocess.run(
            [sys.executable, str(quick_start_root / "start.py")],
            cwd=quick_start_root,
            text=True,
            encoding="utf-8",
            capture_output=True,
        )
        if quick_start.returncode:
            raise AssertionError(quick_start.stderr)
        quick_result = json.loads(quick_start.stdout)
        assert quick_result["ok"] and quick_result["mode"] == "init"
        assert "无需逐个分析" in quick_result["message"]
        assert quick_result["hook_trust_required"] is True
        assert Path(quick_result["hook_config"]) == quick_start_root / ".codex" / "hooks.json"
        assert (quick_start_root / "START_HERE.md").is_file()
        assert (quick_start_root / "AGENTS.md").is_file()
        assert (quick_start_root / ".codex/hooks.json").is_file()
        assert "仅在维护启动器时进入" in (quick_start_root / "START_HERE.md").read_text(encoding="utf-8")
        initialized_agents = (quick_start_root / "AGENTS.md").read_text(encoding="utf-8")
        assert "不得扫描或分析 `AI_PROJECT_BOOTSTRAP/` 源码" in initialized_agents
        assert "完整等于“初始化”或“初始化启动器”" in initialized_agents
        assert "<!-- AI_PROJECT_BOOTSTRAP_PREINIT -->" not in initialized_agents

        quick_repeat = subprocess.run(
            [sys.executable, str(quick_start_root / "start.py")],
            cwd=quick_start_root,
            text=True,
            encoding="utf-8",
            capture_output=True,
        )
        if quick_repeat.returncode:
            raise AssertionError(quick_repeat.stderr)
        repeat_result = json.loads(quick_repeat.stdout)
        assert repeat_result["ok"] and repeat_result["mode"] == "repair"

        print("PYTHON_TESTS_OK")
        return 0
    finally:
        temp_root = Path(tempfile.gettempdir()).resolve()
        if target.parent == temp_root and target.name.startswith(prefix):
            shutil.rmtree(target)


if __name__ == "__main__":
    raise SystemExit(main())
