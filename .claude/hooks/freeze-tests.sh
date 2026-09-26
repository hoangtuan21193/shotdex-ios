#!/bin/bash
# Khi đang sửa bug: viết test đỏ trước, rồi KHÔNG cho agent sửa test cho xanh.
# Bật bằng:  export SHOTDEX_FREEZE_TESTS=1
# (giai đoạn Test của docs/PROCESS.md, mục 5)
[ -z "$SHOTDEX_FREEZE_TESTS" ] && exit 0
INPUT=$(cat)
PATHNAME=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))' 2>/dev/null)

case "$PATHNAME" in
  *ShotDexTests/*|*Tests.swift)
    echo "Chặn: SHOTDEX_FREEZE_TESTS đang bật — file test bị đóng băng trong lúc sửa bug. Sửa code cho test xanh, đừng sửa test." >&2
    exit 2
    ;;
esac
exit 0
