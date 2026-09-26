#!/usr/bin/env python3
"""PostToolUse: ghi lại file nguồn mà phiên này vừa sửa, để Stop hook
(build-check.py) biết phải build lại trước khi cho agent dừng.

Rẻ, không bao giờ chặn: chỉ append đường dẫn vào build/hook/dirty-<session>.
"""
import json
import os
import pathlib
import re
import sys

ROOT = pathlib.Path(os.environ.get("CLAUDE_PROJECT_DIR")
                    or pathlib.Path(__file__).resolve().parents[2])
SOURCE_DIRS = ("ShotDex", "WidgetShared")          # ShotDex, ShotDexKit, ShotDex.xcodeproj, ...
SOURCE_RE = r"(?:ShotDex[\w.]*|WidgetShared)/"
# Lệnh shell có thể đổi file nguồn mà không qua Edit/Write.
BASH_MUTATES = re.compile(
    r"\b(?:sed|perl)\s+[^|;&\n]*-\w*i"              # sed -i / perl -pi
    r"|\bgit\s+(?:apply|am|checkout|restore|stash|merge|rebase|pull|cherry-pick|revert|reset|switch)\b"
    r"|\b(?:mv|cp|rm|tee|patch|swift-format|swiftformat)\b[^|;&\n]*" + SOURCE_RE +
    r"|>>?\s*\S*" + SOURCE_RE
)


def is_source(path: str) -> bool:
    try:
        rel = pathlib.Path(path).resolve().relative_to(ROOT)
    except ValueError:
        return False
    return bool(rel.parts) and rel.parts[0].startswith(SOURCE_DIRS)


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0
    tool = data.get("tool_name", "")
    inp = data.get("tool_input", {}) or {}
    touched = ""
    if tool == "Bash":
        if BASH_MUTATES.search(inp.get("command", "")):
            touched = "<bash>"
    else:
        path = inp.get("file_path") or inp.get("notebook_path") or ""
        if path and is_source(path):
            touched = str(pathlib.Path(path).resolve().relative_to(ROOT))
    if not touched:
        return 0
    state = ROOT / "build" / "hook"
    state.mkdir(parents=True, exist_ok=True)
    with open(state / f"dirty-{data.get('session_id', 'default')}", "a") as f:
        f.write(touched + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
