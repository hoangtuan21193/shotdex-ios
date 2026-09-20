---
name: screens
description: Screenshot every screen and state a UI change affects, on both the iOS 26 and pre-26 paths and on each device class it ships to, with a fixed naming scheme, then inspect each image for defects. This is the CLAUDE.md "UI change: build, run, screenshot, inspect" rule as one procedure. Arguments: <feature-or-screen> [devices...].
---

# Screens

A view change is done when the screenshots are clean, not when it compiles. This
skill turns that rule into a checklist so nothing is skipped and the final message
can say exactly which screens were checked.

## Step 1 — enumerate what the change touches

Before launching anything, write the list:

- Every screen that renders the changed view (grep the type name; a shared
  component may appear in five places).
- Every **state**: empty, loading, one item, many items, selection mode,
  error, `.limited` photo access if it reads the library.
- Both `#available(iOS 26)` branches if the file has one, or if it sits inside
  tab/toolbar/search chrome that does (`RootTabView`, `LiquidGlassTabBar`).
- Light and dark appearance for anything with custom colour
  (`xcrun simctl ui <udid> appearance dark`).
- Dynamic Type at `accessibility3` for anything with text
  (`xcrun simctl ui <udid> content_size accessibility-extra-large`).

## Step 2 — devices

| Change class | Devices |
|---|---|
| Any view | iPhone 17 (26.x) + iPhone 16 Pro (18.6) |
| Tier-D screen, grid, statistics | + iPad Pro 13" (26.5), + Duo (27.1) inner and cover |
| Tab/search/toolbar chrome | all of the above, both orientations |

Boot and install with `/sim`. Build once per architecture; the same `.app`
installs on every simulator.

## Step 3 — capture

Naming: `/tmp/shotdex-screens/<feature>/<NN>-<screen>-<state>-<device>-<ios>.png`,
e.g. `03-library-selection-iphone17-26.png`. Numbered so the list in the final
message is in route order.

Short routes: `xcrun simctl io <udid> screenshot <path>` after each navigation.
Long routes or anything needing a measured element dump: write a
`ShotDexUITests/scripts/<feature>.json` and run `/ui-drive`; its output folder
already has screenshots and per-screen JSON dumps.

## Step 4 — inspect, every image

Open each screenshot (Read tool renders PNGs). Look for, in this order:

1. Controls under the tab bar / nav bar / home indicator; content behind the
   floating chrome on pre-26.
2. Overlap, clipping, truncation (`…` where the design has room).
3. Colour, radius, spacing versus `DESIGN.md` — measure with the dump, not by eye,
   when a number is in dispute (a 28pt control on a 13" iPad is a finding).
4. Blank or half-rendered regions, placeholder thumbnails that never resolved.
5. Layout that differs from what the code intended — the diff says padding 16,
   the screenshot shows 32: find out why.
6. On iPad/Duo: phone layout blown up rather than more content
   (memory: `wide-screen-layout-rules`).

Any defect: fix, rebuild, recapture that screen. Repeat until clean.

## Step 5 — report

The final message lists screens checked as `screen · state · device/iOS`, one per
line, and names any state not reachable in the simulator (55k library, iCloud
Optimize Storage proxies, thermal throttling) as unverified rather than omitting it.
Never describe a screenshot that was not taken.
