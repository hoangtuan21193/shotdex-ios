---
name: build
description: Build one ShotDex scheme for the simulator with quiet output — only errors, unused-variable warnings and the BUILD line survive. Use after every code change, before reporting anything done. Arguments: [scheme] [destination-name]; defaults ShotDex on "iPhone 17".
---

# Build

The rule in CLAUDE.md is "always build after code changes, fix every error before
reporting done". This is the one command that does it, with the destination that is
known to exist on this machine and output cut down to what decides pass/fail.

## Command

```bash
xcodebuild -project ShotDex.xcodeproj -scheme "${1:-ShotDex}" \
  -destination "platform=iOS Simulator,name=${2:-iPhone 17}" \
  -derivedDataPath build/sim build 2>&1 \
  | grep -E "error:|warning: (unused|variable .* was never|immutable value)|BUILD (SUCCEEDED|FAILED)" \
  | sort -u
```

- `-derivedDataPath build/sim` keeps the products where `/sim` and `/screens`
  expect them: `build/sim/Build/Products/Debug-iphonesimulator/ShotDex.app`.
- Schemes that exist: `ShotDex`, `ShotDexKit`, `ShotDexEdit`, `ShotDexShare`,
  `ShotDexWidget`, `ShotDexTests`, `ShotDexUIDriver`. Building `ShotDex` builds the
  kit and all three extensions as dependencies, so it is the default.
- Destination names that are booted right now can be listed with
  `xcrun simctl list devices booted`. If the named device does not exist the
  error is `Unable to find a device matching`; pick another, do not invent one.

## Reading the output

| Line | Meaning | Do |
|---|---|---|
| `error:` | compile or link failure | fix, rebuild; never report done with one present |
| `warning: unused` / `never mutated` | dead binding introduced by the change | remove it in the same turn |
| `BUILD FAILED` with no `error:` line | usually a code-sign or SPM resolve problem | rerun without the grep to see it |
| nothing at all | grep swallowed a crash of xcodebuild itself | rerun with `\| tail -20` |

## Rules

- Build every target the change touches. A change in `ShotDexKit` needs
  `ShotDex` built (which links it) **and** `ShotDexEdit` built — the extension
  has its own deployment constraints and memory ceiling, and a kit type that
  compiles for the app can still fail there.
- After a build passes, the next step for anything visual is `/screens`, not
  reporting. For Domain or Database changes it is `/test`.
- Do not `clean` to make an error go away. If a clean build differs from an
  incremental one, that is a finding to report.
