#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import uuid
from datetime import datetime
from pathlib import Path


TIMESTAMP_FORMAT = "%Y%m%d-%H%M%S"


def now_timestamp() -> str:
    return datetime.now().strftime(TIMESTAMP_FORMAT)


def write_atomic(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.parent / f".tmp-{uuid.uuid4().hex}"
    try:
        temporary.write_text(content, encoding="utf-8", newline="\n")
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def safe_identifier(value: object) -> str:
    identifier = re.sub(r"[^\w.-]+", "_", str(value or ""), flags=re.UNICODE).strip("_.")
    return identifier or "unknown"


def conversation_title(prompt: object) -> str:
    title = str(prompt or "")
    title = re.sub(r"<environment_context>.*?</environment_context>", " ", title, flags=re.DOTALL)
    title = re.sub(r"```.*?```", " ", title, flags=re.DOTALL)
    title = re.sub(r"^\s{0,3}#{1,6}\s*", "", title, flags=re.MULTILINE)
    title = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", title)
    title = re.sub(r"^\s*执行任务[。.!！]?\s*", "", title)
    title = re.sub(r"^(?:请你?|麻烦你?|请帮我|帮我|我想要?|我需要|需要|希望|做个|创建|实现)\s*", "", title)
    title = re.sub(r"[<>:\"/\\|?*\x00-\x1f]+", " ", title)
    title = re.sub(r"\s+", " ", title).strip(" .")
    if not title:
        return "未命名对话"
    return title[:48].strip()


class IndexLock:
    def __init__(self, lock_path: Path) -> None:
        self.lock_path = lock_path
        self.handle: int | None = None

    def __enter__(self) -> "IndexLock":
        deadline = time.monotonic() + 3
        while True:
            try:
                self.handle = os.open(self.lock_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
                return self
            except FileExistsError:
                try:
                    if time.time() - self.lock_path.stat().st_mtime > 30:
                        self.lock_path.unlink(missing_ok=True)
                        continue
                except FileNotFoundError:
                    continue
                if time.monotonic() >= deadline:
                    raise TimeoutError("无法在限定时间内取得对话索引写锁。")
                time.sleep(0.05)

    def __exit__(self, exc_type: object, exc_value: object, traceback: object) -> None:
        if self.handle is not None:
            os.close(self.handle)
        self.lock_path.unlink(missing_ok=True)


def update_index(index_path: Path, timestamp: str, title: str, file_name: str) -> None:
    index_path.parent.mkdir(parents=True, exist_ok=True)
    with IndexLock(index_path.parent / ".index.lock"):
        rows: list[str] = []
        if index_path.exists():
            rows = [
                line
                for line in index_path.read_text(encoding="utf-8").splitlines()
                if re.match(r"^\| `\d{8}-\d{6}` \|", line)
            ]
        display_title = title.replace("|", r"\|").replace("[", r"\[").replace("]", r"\]")
        rows.append(f"| `{timestamp}` | {display_title} | [{file_name}](<{file_name}>) |")
        content = (
            "# 对话归档索引\n\n"
            f"更新时间：`{timestamp}`\n\n"
            "| 时间 | 核心内容 | 文件 |\n"
            "| --- | --- | --- |\n"
            + "\n".join(rows)
            + "\n"
        )
        write_atomic(index_path, content)


def process_event(event: dict[str, object], project_root: Path) -> None:
    event_name = str(event.get("hook_event_name") or "")
    archive_root = project_root / "archive" / "conversations"
    pending_root = archive_root / ".pending"
    state_root = archive_root / ".state"
    error_root = archive_root / ".errors"
    for directory in (pending_root, state_root, error_root):
        directory.mkdir(parents=True, exist_ok=True)

    session_id = safe_identifier(event.get("session_id"))
    turn_id = safe_identifier(event.get("turn_id"))
    pending_path = pending_root / f"{session_id}_{turn_id}.json"
    state_path = state_root / f"{session_id}.json"

    if event_name == "UserPromptSubmit":
        timestamp = now_timestamp()
        prompt = str(event.get("prompt") or "")
        authorization_only = not re.sub(r"^\s*执行任务[。.!！]?\s*$", "", prompt)
        if authorization_only and state_path.exists():
            previous = json.loads(state_path.read_text(encoding="utf-8"))
            title = f"{previous.get('title', '未命名对话')}-执行"
        else:
            title = conversation_title(prompt)
            write_atomic(state_path, json.dumps({"title": title}, ensure_ascii=False))
        record = {
            "timestamp": timestamp,
            "title": title,
            "prompt": prompt,
            "session_id": str(event.get("session_id") or ""),
            "turn_id": str(event.get("turn_id") or ""),
            "model": str(event.get("model") or ""),
        }
        write_atomic(pending_path, json.dumps(record, ensure_ascii=False, indent=2) + "\n")
        return

    if event_name != "Stop":
        return

    if pending_path.exists():
        record = json.loads(pending_path.read_text(encoding="utf-8"))
    else:
        record = {
            "timestamp": now_timestamp(),
            "title": "未匹配对话",
            "prompt": "[未获取到用户消息]",
            "session_id": str(event.get("session_id") or ""),
            "turn_id": str(event.get("turn_id") or ""),
            "model": str(event.get("model") or ""),
        }

    timestamp = str(record["timestamp"])
    title = conversation_title(record["title"])
    file_name = f"{timestamp}_{title}.md"
    final_path = archive_root / file_name
    if final_path.exists():
        file_name = f"{timestamp}_{title}_{turn_id[:8]}.md"
        final_path = archive_root / file_name
    answer = str(event.get("last_assistant_message") or "[未获取到AI回答]")
    content = (
        f"# {title}\n\n"
        f"记录时间：`{timestamp}`\n\n"
        f"会话标识：`{record['session_id']}`\n\n"
        f"轮次标识：`{record['turn_id']}`\n\n"
        f"模型：`{record['model']}`\n\n"
        f"## 用户\n\n{record['prompt']}\n\n"
        f"## AI\n\n{answer}\n"
    )
    write_atomic(final_path, content)
    update_index(archive_root / "INDEX.md", timestamp, title, file_name)
    pending_path.unlink(missing_ok=True)
    print(json.dumps({"continue": True}, separators=(",", ":")))


def main() -> int:
    if hasattr(sys.stdin, "reconfigure"):
        sys.stdin.reconfigure(encoding="utf-8")
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--project-root")
    arguments, _ = parser.parse_known_args()
    raw = sys.stdin.read()
    if not raw.strip():
        return 0
    event: dict[str, object] = json.loads(raw)
    event_name = str(event.get("hook_event_name") or "")
    project_root = (
        Path(arguments.project_root).expanduser().resolve()
        if arguments.project_root
        else Path(__file__).resolve().parents[2]
    )
    try:
        process_event(event, project_root)
    except Exception as error:
        try:
            timestamp = now_timestamp()
            error_root = project_root / "archive" / "conversations" / ".errors"
            error_root.mkdir(parents=True, exist_ok=True)
            (error_root / f"{timestamp}_archive-error.log").write_text(
                f"时间：{timestamp}\n事件：{event_name}\n错误：{error!r}\n",
                encoding="utf-8",
                newline="\n",
            )
        except Exception:
            pass
        if event_name == "Stop":
            print(json.dumps({"continue": True}, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
