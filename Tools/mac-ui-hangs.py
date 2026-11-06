"""Split the hangs a Mac UI drive logged into the app's own and the driver's.

XCUITest reads the app's accessibility tree on the app's main thread, so a
`dump`, `screenshot` or element lookup blocks it too. A hang counts against
the app when it *started* inside a `launch` or a `wait` step. One that starts
after a click or key was pressed (`pressAt`) is listed as a suspect: XCTest
also reads the tree while it waits for the app to go idle after the press, so
only a sample says whose it is (`MAC_UI_SAMPLE=1 Tools/mac-ui-drive …`, which
writes sample.txt and the app's own heaviest main-thread frames).

    python3 Tools/mac-ui-hangs.py <out-dir>
"""
import json, os, re, sys
from datetime import datetime, timedelta

out = sys.argv[1]
report = json.load(open(os.path.join(out, "report.json")))
windows = []
for step in report:
    if "at" not in step:
        continue
    start = datetime.strptime(step["at"], "%H:%M:%S.%f")
    end = start + timedelta(milliseconds=int(step["ms"]))
    if step["action"] in ("launch", "wait"):
        windows.append((start, end, step))
    elif "pressAt" in step:
        windows.append((datetime.strptime(step["pressAt"], "%H:%M:%S.%f"), end, dict(step, index=str(int(step["index"]) + 1), suspect=True)))
previous = {int(s["index"]): s for s in report if "at" in s}
own, suspects, driver = [], [], []
ongoing = []
for line in open(os.path.join(out, "hangs.txt")):
    if "still" in line:
        ongoing.append(line.strip())
        continue
    m = re.search(r"(\d\d:\d\d:\d\d\.\d+)\s+blocked (\d+) ms", line)
    if not m:
        continue
    end = datetime.strptime(m.group(1)[:12], "%H:%M:%S.%f")
    ms = int(m.group(2))
    start = end - timedelta(milliseconds=ms)
    hit = next((w for w in windows if w[0] <= start <= w[1]), None)
    if hit:
        before = previous.get(int(hit[2]["index"]) - 1)
        cause = "launch" if hit[2]["action"] == "launch" else f"after step {int(hit[2]['index']) - 1} {before['action']} {before['detail']}" if before else "?"
        (suspects if hit[2].get("suspect") else own).append(f"{ms} ms  {cause}")
    else:
        driver.append(ms)
print(f"app hangs > 100 ms: {len(own)}")
for line in own:
    print("  " + line)
if suspects:
    print(f"suspects (after a press, maybe XCTest's idle wait — confirm with a sample): {len(suspects)}")
    for line in suspects:
        print("  " + line)
print(f"(ignored {len(driver)} during driver queries: {driver})")
if ongoing:
    print(f"hang still running when last logged: {ongoing[-1]}")
