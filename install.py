#!/usr/bin/env python3
"""One-click global installer for AI_PROJECT_BOOTSTRAP."""

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
BOOTSTRAP_PY = ROOT / "AI_PROJECT_BOOTSTRAP" / "bootstrap.py"


def main() -> int:
    parser = argparse.ArgumentParser(description="全局安装 AI_PROJECT_BOOTSTRAP 命令")
    parser.add_argument("--uninstall", action="store_true", help="卸载全局命令配置")
    parser.add_argument("--profile-path", default="", help="自定义 profile 路径")
    args = parser.parse_args()

    if not BOOTSTRAP_PY.is_file():
        print(f"未找到脚手架核心脚本：{BOOTSTRAP_PY}", file=sys.stderr)
        return 1

    cmd = [sys.executable, str(BOOTSTRAP_PY), "install"]
    if args.uninstall:
        cmd.append("--uninstall")
    if args.profile_path:
        cmd.extend(["--profile-path", args.profile_path])

    return subprocess.run(cmd).returncode


if __name__ == "__main__":
    raise SystemExit(main())
