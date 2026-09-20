---
name: sim
description: Install and launch the current ShotDex build on a booted simulator, grant photo access, and take a screenshot — the fixed routine before any UI verification. Arguments: [device-name-or-udid] (default: the booted iPhone 17 on the newest iOS). Also covers boot, log tailing and the rules that stop blind taps from cloning the library.
---

# Sim

Every UI change ends in the simulator, not in the compiler. This is the routine
that gets a fresh build onto a device and a first screenshot in one go, and the
hard-won rules for driving it afterward.

## Devices on this machine

```bash
xcrun simctl list devices booted
```

Typically booted: iPhone 16 Pro (iOS 18.6, the pre-26 path), iPhone 17 (iOS 26.5
and 27.0, Liquid Glass path), iPad Pro 11" (18.6), iPad Pro 13" (26.5). The iPhone
Duo needs the 27.1 runtime (see memory: `iphone-duo-ios27`). Boot one that is off
with `xcrun simctl boot <udid>`; it takes ~20s to be ready for install.

Pick the device by what the change touches:

| Change | Device |
|---|---|
| Anything with `#available(iOS 26)` | one 26+ **and** one 18.6 device |
| Tier-D screen (editor, collage, video studio, compare) | iPhone + iPad 13" + Duo |
| Grid / library | iPhone 17 (26.5) first; 55k-photo library is on the physical device only |
| Widget / Share extension | iPhone 17, then the host app that invokes it |

## Install + launch + screenshot

```bash
UDID="${1:-$(xcrun simctl list devices booted -j | python3 -c 'import json,sys;d=json.load(sys.stdin)["devices"];print(next(x["udid"] for k in sorted(d,reverse=True) for x in d[k] if x["state"]=="Booted" and "iPhone 17" in x["name"]))')}"
APP=build/sim/Build/Products/Debug-iphonesimulator/ShotDex.app
xcrun simctl install "$UDID" "$APP"
xcrun simctl privacy "$UDID" grant photos com.hoangtuan.shotdex
xcrun simctl launch "$UDID" com.hoangtuan.shotdex
sleep 4
xcrun simctl io "$UDID" screenshot "${2:-/tmp/shotdex-sim/first.png}"
```

`grant photos` sets full access; the app may still show its own onboarding
prompt, which needs a tap. To test `.limited`, `xcrun simctl privacy ... reset
photos` and pick "Select Photos" in the dialog.

The MCP simulator tool (`mcp__Claude_Code_iOS_Simulator__control`) does the same
with `launch` and gives `inspect` (accessibility tree) and `tap`; prefer it when it
is available, use `simctl` when it is not.

## Driving rules (learned the hard way)

1. **Screenshot before every tap.** A stray tap on "Duplicate" cloned the sim
   library twice (memory: `sim-blind-taps-duplicate`). Never tap coordinates
   from memory of a previous screen.
2. **Transient UI**: arm a background screenshot ~7s before the gesture; the
   foreground call returns after the menu has already closed
   (memory: `simulator-screenshot-timing`).
3. **Long routes**: script them for `Tools/ui-drive` (`/ui-drive`) instead of
   tapping by hand; one run gives screenshots plus a measured element dump.
4. **Logs**: `xcrun simctl spawn "$UDID" log stream --predicate 'subsystem == "com.hoangtuan.shotdex"' --style compact`
   in a background Bash while reproducing.
5. **Fresh state**: `xcrun simctl uninstall "$UDID" com.hoangtuan.shotdex` wipes
   the GRDB file and the index cursor. Do it when testing first-run or migrations.
6. `timeout` is not installed on this Mac; use the Bash tool's own timeout.

## Rules

- `/sim` presumes `/build` already ran into `build/sim`. If the `.app` is missing,
  build first; do not install a stale product from another derived-data path.
- Look at the screenshot. A screenshot not looked at is not verification.
