#!/usr/bin/env python3
"""Install and maintain the reusable AI project collaboration baseline."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent
META_NAME = ".ai-project-bootstrap.json"
ARCHIVE_DIRS = (
    "archive/development",
    "archive/code",
    "archive/conversations",
    "archive/bootstrap",
)
TIME_RE = re.compile(r"^\d{8}-\d{6}$")
VARIABLE_RE = re.compile(r"{{[A-Z0-9_]+}}")


class BootstrapError(RuntimeError):
    pass


def now() -> str:
    return datetime.now().strftime("%Y%m%d-%H%M%S")


def valid_time(value: str) -> bool:
    if not TIME_RE.fullmatch(value):
        return False
    try:
        datetime.strptime(value, "%Y%m%d-%H%M%S")
        return True
    except ValueError:
        return False


def read_json(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        raise BootstrapError(f"无法读取 JSON：{path}：{exc}") from exc


def manifest() -> dict[str, Any]:
    data = read_json(ROOT / "manifest.json")
    if data.get("name") != "AI_PROJECT_BOOTSTRAP" or not isinstance(data.get("files"), list):
        raise BootstrapError("manifest.json 无效")
    return data


def atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{now()}.{os.getpid()}.tmp")
    try:
        temporary.write_bytes(data)
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_digest(path: Path) -> str:
    return digest(path.read_bytes())


def command_quote(value: str) -> str:
    return '"' + value.replace('"', '\\"') + '"'


def render_context(target: Path, data: dict[str, Any], stamp: str) -> dict[str, str]:
    executable = str(Path(sys.executable).resolve())
    hook = str((target / ".codex/hooks/archive_conversation.py").resolve())
    command = f"{command_quote(executable)} {command_quote(hook)}"
    command_json = json.dumps(command, ensure_ascii=False)[1:-1]
    return {
        "{{TIMESTAMP}}": stamp,
        "{{PROJECT_NAME}}": target.name,
        "{{PROJECT_ROOT}}": str(target),
        "{{BOOTSTRAP_VERSION}}": str(data["version"]),
        "{{HOOK_COMMAND_JSON}}": command_json,
        "{{HOOK_COMMAND_WINDOWS_JSON}}": command_json,
    }


def content(entry: dict[str, Any], context: dict[str, str]) -> bytes:
    source = ROOT / entry["source"]
    if not source.is_file():
        raise BootstrapError(f"初始化器源文件缺失：{source}")
    raw = source.read_bytes()
    if not entry.get("render"):
        return raw
    text = raw.decode("utf-8-sig")
    for key, value in context.items():
        text = text.replace(key, value)
    unresolved = sorted(set(VARIABLE_RE.findall(text)))
    if unresolved:
        raise BootstrapError(f"{entry['source']} 仍有变量：{', '.join(unresolved)}")
    return text.encode("utf-8")


def append_required(path: Path, data: bytes) -> bool:
    required = [line for line in data.decode("utf-8-sig").splitlines() if line.strip()]
    current = path.read_text(encoding="utf-8-sig") if path.exists() else ""
    lines = current.splitlines()
    missing = [line for line in required if line not in lines]
    if not missing:
        return False
    prefix = current.rstrip("\r\n")
    updated = (prefix + "\n" if prefix else "") + "\n".join(missing) + "\n"
    atomic_write(path, updated.encode("utf-8"))
    return True


def ensure_dirs(target: Path) -> None:
    for relative in ARCHIVE_DIRS:
        (target / relative).mkdir(parents=True, exist_ok=True)


def meta_path(target: Path) -> Path:
    return target / META_NAME


def read_meta(target: Path, required: bool = False) -> dict[str, Any]:
    path = meta_path(target)
    if not path.exists():
        if required:
            raise BootstrapError(f"缺少 {META_NAME}；请先 init，或用 repair 补齐登记")
        return {}
    return read_json(path)


def current_hashes(target: Path, data: dict[str, Any]) -> dict[str, str]:
    result: dict[str, str] = {}
    for entry in data["files"]:
        path = target / entry["target"]
        if entry["policy"] == "managed" and path.is_file():
            result[entry["target"]] = file_digest(path)
    return result


def write_meta(
    target: Path,
    data: dict[str, Any],
    installed: str,
    updated: str,
    hashes: dict[str, str],
) -> None:
    value = {
        "name": data["name"],
        "version": data["version"],
        "installed_at": installed,
        "updated_at": updated,
        "target_root": str(target),
        "managed_files": dict(sorted(hashes.items())),
    }
    atomic_write(
        meta_path(target),
        (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8"),
    )


def init(target: Path, data: dict[str, Any]) -> dict[str, Any]:
    conflicts = [
        entry["target"]
        for entry in data["files"]
        if entry["policy"] != "append" and (target / entry["target"]).exists()
    ]
    if meta_path(target).exists():
        conflicts.append(META_NAME)
    if conflicts:
        raise BootstrapError("init 已停止，避免覆盖：" + ", ".join(sorted(set(conflicts))))
    stamp = now()
    target.mkdir(parents=True, exist_ok=True)
    ensure_dirs(target)
    context = render_context(target, data, stamp)
    changed: list[str] = []
    for entry in data["files"]:
        path = target / entry["target"]
        raw = content(entry, context)
        if entry["policy"] == "append":
            if append_required(path, raw):
                changed.append(entry["target"])
        else:
            atomic_write(path, raw)
            changed.append(entry["target"])
    write_meta(target, data, stamp, stamp, current_hashes(target, data))
    return {"action": "init", "ok": True, "target": str(target), "changed": changed}


def repair(target: Path, data: dict[str, Any]) -> dict[str, Any]:
    stamp = now()
    target.mkdir(parents=True, exist_ok=True)
    ensure_dirs(target)
    context = render_context(target, data, stamp)
    previous = read_meta(target)
    recorded = previous.get("managed_files", {})
    changed: list[str] = []
    for entry in data["files"]:
        path = target / entry["target"]
        raw = content(entry, context)
        if entry["policy"] == "append":
            if append_required(path, raw):
                changed.append(entry["target"])
        elif entry["policy"] == "local":
            actual = file_digest(path) if path.is_file() else None
            if actual != digest(raw):
                atomic_write(path, raw)
                changed.append(entry["target"])
        elif not path.exists():
            atomic_write(path, raw)
            changed.append(entry["target"])
    hashes: dict[str, str] = {}
    for entry in data["files"]:
        relative = entry["target"]
        path = target / relative
        if entry["policy"] != "managed" or not path.is_file():
            continue
        actual = file_digest(path)
        expected = digest(content(entry, context))
        if relative in recorded or relative in changed or actual == expected:
            hashes[relative] = actual
    installed = previous.get("installed_at", stamp)
    write_meta(target, data, installed, stamp, hashes)
    return {"action": "repair", "ok": True, "target": str(target), "changed": changed}


def upgrade(target: Path, data: dict[str, Any], force: bool) -> dict[str, Any]:
    previous = read_meta(target, required=True)
    stamp = now()
    context = render_context(target, data, stamp)
    recorded = previous.get("managed_files", {})
    replacements: list[tuple[dict[str, Any], bytes, bool]] = []
    conflicts: list[str] = []
    for entry in data["files"]:
        if entry["policy"] != "managed":
            continue
        path = target / entry["target"]
        expected = content(entry, context)
        if not path.exists():
            replacements.append((entry, expected, False))
            continue
        actual_hash = file_digest(path)
        if actual_hash == digest(expected):
            continue
        if recorded.get(entry["target"]) != actual_hash:
            conflicts.append(entry["target"])
        replacements.append((entry, expected, True))
    if conflicts and not force:
        raise BootstrapError(
            "检测到人工修改，upgrade 已停止："
            + ", ".join(conflicts)
            + "；确认覆盖时使用 --force，原文件会先归档"
        )
    ensure_dirs(target)
    backup_root = target / "archive/bootstrap" / stamp
    changed: list[str] = []
    backed_up = False
    for entry, raw, existed in replacements:
        path = target / entry["target"]
        if existed:
            backup = backup_root / entry["target"]
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, backup)
            backed_up = True
        atomic_write(path, raw)
        changed.append(entry["target"])
    for entry in data["files"]:
        path = target / entry["target"]
        raw = content(entry, context)
        if entry["policy"] == "state" and not path.exists():
            atomic_write(path, raw)
            changed.append(entry["target"])
        elif entry["policy"] == "append" and append_required(path, raw):
            changed.append(entry["target"])
        elif entry["policy"] == "local":
            actual = file_digest(path) if path.is_file() else None
            if actual != digest(raw):
                atomic_write(path, raw)
                changed.append(entry["target"])
    installed = previous.get("installed_at", stamp)
    write_meta(target, data, installed, stamp, current_hashes(target, data))
    result: dict[str, Any] = {
        "action": "upgrade",
        "ok": True,
        "target": str(target),
        "changed": changed,
    }
    if backed_up:
        result["backup"] = str(backup_root)
    return result


def time_issues(path: Path, label: str) -> list[str]:
    if not path.is_file():
        return []
    text = path.read_text(encoding="utf-8-sig")
    match = re.search(rf"{re.escape(label)}\s*\x60?([^\x60\s]+)\x60?", text)
    if not match:
        return [f"{path.name} 缺少时间字段：{label}"]
    if not valid_time(match.group(1)):
        return [f"{path.name} 时间格式无效：{match.group(1)}"]
    return []


def hook_issues(target: Path) -> list[str]:
    path = target / ".codex/hooks.json"
    if not path.is_file():
        return []
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except json.JSONDecodeError as exc:
        return [f".codex/hooks.json 无效：{exc}"]
    issues: list[str] = []
    for event in ("UserPromptSubmit", "Stop"):
        try:
            item = value["hooks"][event][0]["hooks"][0]
            command = item.get("commandWindows") or item.get("command")
        except (KeyError, IndexError, TypeError):
            command = None
        if not command:
            issues.append(f".codex/hooks.json 缺少 {event} 命令")
        elif str(target).replace("\\", "/").lower() not in command.replace("\\", "/").lower():
            issues.append(f".codex/hooks.json 的 {event} 未指向当前项目")
    return issues


def check(target: Path, data: dict[str, Any]) -> dict[str, Any]:
    issues: list[str] = []
    context = render_context(target, data, now())
    if not target.is_dir():
        issues.append("目标目录不存在")
    for entry in data["files"]:
        path = target / entry["target"]
        if not path.is_file():
            issues.append(f"缺少文件：{entry['target']}")
            continue
        if entry["policy"] == "append":
            required = [
                line
                for line in content(entry, context).decode("utf-8-sig").splitlines()
                if line.strip()
            ]
            lines = path.read_text(encoding="utf-8-sig").splitlines()
            for line in required:
                if line not in lines:
                    issues.append(f"{entry['target']} 缺少条目：{line}")
        elif entry.get("render"):
            unresolved = sorted(set(VARIABLE_RE.findall(path.read_text(encoding="utf-8-sig"))))
            if unresolved:
                issues.append(f"{entry['target']} 存在变量：{', '.join(unresolved)}")
    for relative in ARCHIVE_DIRS:
        if not (target / relative).is_dir():
            issues.append(f"缺少目录：{relative}")
    for relative, label in (
        ("PROJECT_INDEX.md", "更新时间："),
        ("DEVELOPMENT_MAP.md", "更新时间："),
        ("CODE_MAP.md", "更新时间："),
        ("archive/conversations/INDEX.md", "更新时间："),
    ):
        issues.extend(time_issues(target / relative, label))
    issues.extend(hook_issues(target))
    metadata = read_meta(target)
    if not metadata:
        issues.append(f"缺少 {META_NAME}")
    else:
        if metadata.get("name") != data["name"]:
            issues.append("初始化器登记名称不匹配")
        if str(metadata.get("target_root", "")).lower() != str(target).lower():
            issues.append("初始化器登记路径不匹配")
        for field in ("installed_at", "updated_at"):
            if not valid_time(str(metadata.get(field, ""))):
                issues.append(f"{META_NAME} 的 {field} 无效")
        recorded = metadata.get("managed_files", {})
        for entry in data["files"]:
            relative = entry["target"]
            path = target / relative
            if entry["policy"] != "managed" or not path.is_file():
                continue
            if relative not in recorded:
                issues.append(f"受管理文件未登记：{relative}")
            elif recorded[relative] != file_digest(path):
                issues.append(f"受管理文件已被修改：{relative}")
    return {"action": "check", "ok": not issues, "target": str(target), "issues": issues}


def get_profile_path(override: str = "") -> Path:
    if override.strip():
        return Path(override).expanduser().resolve()
    if sys.platform == "win32":
        personal = Path(os.environ.get("USERPROFILE", Path.home())) / "Documents" / "PowerShell"
        return personal / "Microsoft.PowerShell_profile.ps1"
    return Path.home() / ".bashrc"


def install_global(uninstall: bool = False, profile_override: str = "") -> dict[str, Any]:
    profile_file = get_profile_path(profile_override)
    start_marker = "# >>> AI_PROJECT_BOOTSTRAP >>>"
    end_marker = "# <<< AI_PROJECT_BOOTSTRAP <<<"

    bootstrap_ps1 = (ROOT / "bootstrap.ps1").resolve().as_posix()
    home_bootstrap = (Path.home() / ".ai-project-bootstrap/AI_PROJECT_BOOTSTRAP/bootstrap.ps1").as_posix()

    block_lines = [
        start_marker,
        "function ai-init {",
        '    param([string]$Path = ".", [switch]$Force)',
        "    $target = (Resolve-Path $Path).Path",
        f'    $boot = if (Test-Path "{home_bootstrap}") {{ "{home_bootstrap}" }} else {{ "{bootstrap_ps1}" }}',
        "    if (-not (Test-Path $boot)) {",
        '        Write-Error "AI_PROJECT_BOOTSTRAP 未找到，请确保已安装至 $HOME/.ai-project-bootstrap 或正确路径。"',
        "        return",
        "    }",
        '    $params = @("init", "-TargetPath", $target)',
        '    if ($Force) { $params += "-Force" }',
        "    pwsh -NoProfile -File $boot @params",
        "}",
        "",
        "function ai-repair {",
        '    param([string]$Path = ".", [switch]$Force)',
        "    $target = (Resolve-Path $Path).Path",
        f'    $boot = if (Test-Path "{home_bootstrap}") {{ "{home_bootstrap}" }} else {{ "{bootstrap_ps1}" }}',
        "    if (-not (Test-Path $boot)) {",
        '        Write-Error "AI_PROJECT_BOOTSTRAP 未找到，请确保已安装至 $HOME/.ai-project-bootstrap 或正确路径。"',
        "        return",
        "    }",
        '    $params = @("repair", "-TargetPath", $target)',
        '    if ($Force) { $params += "-Force" }',
        "    pwsh -NoProfile -File $boot @params",
        "}",
        "",
        "function ai-check {",
        '    param([string]$Path = ".")',
        "    $target = (Resolve-Path $Path).Path",
        f'    $boot = if (Test-Path "{home_bootstrap}") {{ "{home_bootstrap}" }} else {{ "{bootstrap_ps1}" }}',
        "    if (-not (Test-Path $boot)) {",
        '        Write-Error "AI_PROJECT_BOOTSTRAP 未找到，请确保已安装至 $HOME/.ai-project-bootstrap 或正确路径。"',
        "        return",
        "    }",
        "    pwsh -NoProfile -File $boot check -TargetPath $target",
        "}",
        "",
        "function ai-upgrade {",
        '    param([string]$Path = ".", [switch]$Force)',
        "    $target = (Resolve-Path $Path).Path",
        f'    $boot = if (Test-Path "{home_bootstrap}") {{ "{home_bootstrap}" }} else {{ "{bootstrap_ps1}" }}',
        "    if (-not (Test-Path $boot)) {",
        '        Write-Error "AI_PROJECT_BOOTSTRAP 未找到，请确保已安装至 $HOME/.ai-project-bootstrap 或正确路径。"',
        "        return",
        "    }",
        '    $params = @("upgrade", "-TargetPath", $target)',
        '    if ($Force) { $params += "-Force" }',
        "    pwsh -NoProfile -File $boot @params",
        "}",
        end_marker,
    ]
    block_content = "\n".join(block_lines)

    profile_file.parent.mkdir(parents=True, exist_ok=True)
    current_text = profile_file.read_text(encoding="utf-8") if profile_file.is_file() else ""
    pattern = re.compile(re.escape(start_marker) + r"[\s\S]*?" + re.escape(end_marker))

    if uninstall:
        updated_text = pattern.sub("", current_text).strip()
        if updated_text:
            updated_text += "\n"
        profile_file.write_text(updated_text, encoding="utf-8")
        return {
            "action": "install",
            "ok": True,
            "profile": str(profile_file),
            "installed": False,
            "message": "已从 Profile 移除 AI_PROJECT_BOOTSTRAP 全局函数。",
        }

    if pattern.search(current_text):
        updated_text = pattern.sub(block_content, current_text)
    else:
        trimmed = current_text.strip()
        updated_text = f"{trimmed}\n\n{block_content}\n" if trimmed else f"{block_content}\n"

    profile_file.write_text(updated_text, encoding="utf-8")

    global_dir = Path.home() / ".ai-project-bootstrap"
    repo_root = ROOT.parent
    copied = False
    if repo_root.resolve() != global_dir.resolve() and (repo_root / "AI_PROJECT_BOOTSTRAP").is_dir():
        try:
            global_dir.mkdir(parents=True, exist_ok=True)
            dest_bootstrap = global_dir / "AI_PROJECT_BOOTSTRAP"
            if not dest_bootstrap.exists():
                shutil.copytree(repo_root / "AI_PROJECT_BOOTSTRAP", dest_bootstrap)
                copied = True
            for root_file in ("README.md", "LICENSE", ".gitignore", "install.ps1", "install.py"):
                src = repo_root / root_file
                if src.is_file():
                    shutil.copy2(src, global_dir / root_file)
        except OSError:
            pass

    return {
        "action": "install",
        "ok": True,
        "profile": str(profile_file),
        "installed": True,
        "synced_to_home": copied,
        "functions": ["ai-init", "ai-repair", "ai-check", "ai-upgrade"],
    }


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="通用 AI 项目启动器")
    parser.add_argument("action", choices=("init", "check", "upgrade", "repair", "install"))
    parser.add_argument("--target", default=".", help="目标项目目录（默认为当前目录）")
    parser.add_argument("--force", action="store_true", help="备份并覆盖人工修改的受管理文件")
    parser.add_argument("--uninstall", action="store_true", help="卸载全局命令配置")
    parser.add_argument("--profile-path", default="", help="自定义 profile 路径（供测试或特殊场景使用）")
    return parser.parse_args()


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    args = arguments()
    try:
        data = manifest()
        target = Path(args.target).expanduser().resolve()
        if args.action == "init":
            result = init(target, data)
        elif args.action == "check":
            result = check(target, data)
        elif args.action == "repair":
            result = repair(target, data)
        elif args.action == "install":
            result = install_global(args.uninstall, args.profile_path)
        else:
            result = upgrade(target, data, args.force)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0 if result["ok"] else 1
    except (BootstrapError, OSError) as exc:
        print(
            json.dumps(
                {"action": args.action, "ok": False, "error": str(exc)},
                ensure_ascii=False,
                indent=2,
            ),
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
