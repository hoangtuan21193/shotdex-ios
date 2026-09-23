---
name: ui-drive
description: Write and run a Tools/ui-drive JSON script that replays taps, swipes, text entry and orientation changes on a simulator and returns screenshots plus a measured element dump per screen. Use for any route longer than two taps, for anything that needs element frames in points, and whenever an agent has only Bash. Arguments: <script-name-or-path> [device].
---

# UI drive

`Tools/ui-drive <udid-or-name> <script.json> [out-dir]` runs the `ShotDexUIDriver`
scheme, whose only test replays a JSON step list inside the simulator. Each
`dump` step writes every on-screen element with label, identifier, frame in points
and enabled flag — the way a layout finding gets a number. A run is three to six
minutes, so script the whole route to a screen in one file.

## Step vocabulary

Read `ShotDexUITests/UIDriver.swift` for the authoritative list; today:

| action | fields | notes |
|---|---|---|
| `launch` | — | fresh launch of `com.hoangtuan.shotdex` |
| `wait` | `seconds` | first screen needs ~4s; studio/editor open ~6s |
| `tap` | `label` [, `type`, `index`] **or** `x`,`y` (0–1 normalized) | label = accessibility label or identifier, **exact match first**, prefix only when nothing matches exactly (`"Photo, file type"` + `index` walks the grid). With no `index`, several matches → the first **hittable** one, so `Cancel` hits the sheet's button, not the covered commit-bar Cancel; `type` = `button`, `cell`, `staticText`… disambiguates |
| `longPress` | same as tap, `seconds` | |
| `swipe` | `direction`, optional `x`,`y` | |
| `typeText` | `text` | into the focused field |
| `scrollTo` | `label` | |
| `orientation` | `text`: `portrait`/`landscape` | |
| `screenshot` | `name` | |
| `dump` | `name` | writes `<name>.json` |

Examples in `ShotDexUITests/scripts/`. Copy the closest one; `video-studio-layout.json`
shows a full route with orientation change and paired screenshot+dump.

## Writing a script

1. Name it after the screen and goal: `editor-crop-ipad.json`.
2. Start with `launch`, `wait 4`, then navigate by **label** wherever a label
   exists. Coordinates only for grid cells, and normalized so the same script
   works on iPhone and iPad.
3. Pair every `screenshot` with a `dump` of the same name — the screenshot is
   for eyes, the dump is for numbers.
4. End in a neutral state (portrait, no sheet) so the next script starts clean.

## Running

```bash
Tools/ui-drive "iPhone 17" ShotDexUITests/scripts/<name>.json /tmp/shotdex-ui/<name>
ls /tmp/shotdex-ui/<name>
```

The script is copied into the test bundle as a resource because the runner
cannot read Mac paths or `TEST_RUNNER_` env (measured; see memory
`ui-driver-xcutest`). `report.json` says what each step did and the first one
that failed. A step failing on `tap label` usually means the label changed or a
sheet is covering it — read the previous dump to see what is actually on screen.

## Reading a dump

```bash
python3 -c 'import json,sys;[print(f"{e.get(\"frame\")} {e.get(\"type\",\"\")[:10]:10} {e.get(\"label\",\"\")!r}") for e in json.load(open(sys.argv[1]))]' /tmp/shotdex-ui/<name>/<screen>.json
```

Empty `label` on a `button` = missing accessibility label (a11y finding). Height
under 44 on a button = target-size finding. Same control 28pt on iPhone and 28pt
on iPad 13" = `device-layout` finding.

## Limits

- Video Studio does not enumerate on the phone-size runner in some states
  (memory: `ui-driver-xcutest`); use iPad for those routes.
- Menus inside `tabViewBottomAccessory` do not open on iOS 26 (memory:
  `ios26-accessory-menu-limits`); do not write a script that expects them to.
