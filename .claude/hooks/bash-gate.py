#!/usr/bin/env python3
"""Cổng duyệt cho lệnh shell (giai đoạn Deploy của docs/PROCESS.md).

Exit 2 = chặn hành động; stderr là lý do trả về cho agent.

Chỉ khớp lệnh ở VỊ TRÍ LỆNH, và bỏ qua thân heredoc — nên viết tài liệu có nhắc
tới chuỗi bị cấm thì không bị chặn nhầm.
"""
import json
import os
import re
import sys


def strip_heredocs(text: str) -> str:
    out, lines, i = [], text.split("\n"), 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        m = re.search(r"<<-?\s*[\"']?([A-Za-z_][A-Za-z0-9_]*)[\"']?", line)
        i += 1
        if m:
            end = m.group(1)
            while i < len(lines) and lines[i].strip() != end:
                i += 1
            i += 1
    return "\n".join(out)


def main() -> int:
    try:
        cmd = json.load(sys.stdin).get("tool_input", {}).get("command", "")
    except Exception:
        return 0

    cmd = strip_heredocs(cmd)
    sep = r"(?:^|[\n;]|&&|\|\||\|)\s*"

    if re.search(sep + r"git\s+push\b[^\n;&|]*--no-verify", cmd):
        print("Chặn: 'git push --no-verify' đi vòng qua Tools/gate. "
              "Chạy Tools/gate cho xanh, hoặc hỏi người dùng trước.", file=sys.stderr)
        return 2

    release = (re.search(sep + r"xcodebuild\b[^\n;&|]*\barchive\b", cmd)
               or re.search(sep + r"xcrun\s+(altool|notarytool)\b", cmd))
    if release and not os.environ.get("RELEASE_APPROVAL"):
        print("Chặn: archive/nộp bản phát hành cần RELEASE_APPROVAL=<tên người duyệt>. "
              "Xem docs/PROCESS.md mục 5.", file=sys.stderr)
        return 2

    return 0


if __name__ == "__main__":
    sys.exit(main())
