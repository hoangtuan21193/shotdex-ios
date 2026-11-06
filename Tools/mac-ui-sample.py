"""The app's own main-thread work in a `sample` taken during a UI drive.

XCTest's accessibility reads run on the app's main thread too; this drops
those branches and the idle wait, then lists the heaviest remaining frames
(1 sample = 1 ms). A frame of ShotDex code over ~50 ms is a click that makes
the window wait.

    python3 Tools/mac-ui-sample.py <sample.txt>
"""
import re, sys

lines = open(sys.argv[1]).read().split("\n")
start = next(i for i, l in enumerate(lines) if "Main Thread" in l)
rows = []
for line in lines[start + 1:]:
    if not line.startswith(" ") or "Thread_" in line:
        break
    m = re.match(r"^([\s+!:|]*)(\d+)\s+(.*)", line)
    if m:
        rows.append((len(m.group(1)), int(m.group(2)), re.sub(r"\s+\[0x[0-9a-f]+\]", "", m.group(3))[:150]))
busy, app = 0, {}
skip_depth = None
for depth, count, text in rows:
    if skip_depth is not None and depth > skip_depth:
        continue
    skip_depth = None
    if "XCT" in text or "mach_msg" in text or "__CFRunLoopServiceMachPort" in text:
        skip_depth = depth
        continue
    if "(in ShotDex.debug.dylib)" in text and not any(k in text for k in ("partial apply", "compiler-generated", "protocol witness", "thunk", "main()", "entry_point")):
        key = text.split("(in ShotDex")[0].strip()[:110] + "  " + text.split(")")[-1].strip()[-40:]
        app[key] = max(app.get(key, 0), count)
print("heaviest ShotDex frames on the main thread (ms, XCTest excluded):")
for key, count in sorted(app.items(), key=lambda kv: -kv[1])[:15]:
    print(f"  {count:5d}  {key}")
