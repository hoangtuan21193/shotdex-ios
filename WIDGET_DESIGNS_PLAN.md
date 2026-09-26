# Photo Widget → named designs

Collapses the four photo-widget kinds (Clock, Calendar, Weather, Combined) into
**one** widget type whose look is a **named design** the user creates in
Settings. On This Day is untouched.

Decided 2026-09-21. Tracker for the work; each phase folds into `spec.md` as it
lands, then this file shrinks.

## Why

- The four kinds are one widget with four sets of defaults. The only
  differences live in `PhotoWidgetSettings.default(for:)`
  (`WidgetShared/PhotoWidgetSettings.swift:418`) — `showsTime`, `showsDate`,
  `dateSize`, `anchor`, `calendarStyle`, `maximumEventCount`, `timeSize`.
  No kind can do anything another kind cannot be configured into.
- The split **removes** capability: `kind.needsWeather` is weather+combined
  only, so a Clock widget cannot be given the weather even though the face
  draws it fine.
- Per-kind settings means two placed widgets of one kind fight over one
  settings entry. `PhotoWidgetIntentApplication` already carries a comment
  about the two "taking turns rewriting the file for ever", solved with
  `appliedIntentSignature`. Designs remove the fight instead of damping it.
- Gallery: Apple ships one configurable **Photos** entry, not four.

## Cost, and why now

Removing a `widgetKind` string orphans every placed widget of that kind —
`WidgetShared/PhotoWidgetSettings.swift:29` says so. At `MARKETING_VERSION 1.0`
/ build 1, with no release tag, nobody outside this machine has one placed, so
the cost is zero **today** and never zero again after the first TestFlight
build.

## Model

```swift
struct PhotoWidgetDesign: Codable, Equatable, Identifiable {
    var id: String          // UUID string, stable, names the frame folder
    var name: String        // user-visible, e.g. "Clock corner"
    var settings: PhotoWidgetSettings
}

struct PhotoWidgetSettingsFile: Codable, Equatable {
    var designs: [PhotoWidgetDesign]   // ordered: it is a user-facing list
    // `byKind` stays decodable for one version, for migration only.
}
```

- Array, not dictionary: the order is the order of the Settings list.
- `id` replaces `kind` as the frame-folder key: `photo-widget-<id>`.
- Two new visibility flags on `PhotoWidgetSettings`, symmetric with the two
  that exist: `showsWeather` (default false), `showsCalendar` (default false).
  `calendarStyle` keeps meaning "which calendar layout", not "whether".
- `kind.needsWeather` → `settings.showsWeather`.
  `kind.needsCalendarEvents` → `settings.showsCalendar && settings.calendarStyle.showsEvents`.
- A new design defaults to time + date on, weather + calendar off — today's
  Clock, which is the one people place most.

## Migration (v1 file → v2)

1. Decode `byKind`. For each of the four old kinds **whose `source != .none`**,
   make a design named after the old kind's title, carrying that kind's
   settings, with `showsWeather`/`showsCalendar` seeded from what the kind used
   to imply (`needsWeather` / `needsCalendarEvents`).
2. If that yields nothing, make one design named **"My Widget"** from
   `PhotoWidgetSettings.default`.
3. Delete the four `photo-widget-<kind>/` folders. The existing
   `adoptLegacyFilesIfNeeded` path already re-renders any design that has a
   source but no frames, so the pictures come back on the next launch.
4. `clock-settings.json` migration (`migratedFromClockOnlyFile`) collapses into
   step 1 and is then deleted.

## Widget target

- One type, `kind: "ShotDexPhoto"`, display name **Photo Widget** (not "Custom
  Widget" — that names the mechanism, not the thing). Description lists what it
  can carry: the time, the date, the month, today's events, the weather, over a
  photo or album.
- All six families: `systemSmall/Medium/Large` + the three accessory ones.
  `hasAccessoryFamilies` goes away; the accessory view picks what to draw from
  the design — weather if `showsWeather`, else events if `showsCalendar`, else
  the time/date. Today it switches on `kind`
  (`ShotDexWidget/PhotoWidgetAccessories.swift:17`).
- `ConfigurePhotoWidgetIntent` gains `@Parameter var design: WidgetDesignEntity?`,
  first in the summary. Empty → the first design in the list, so a
  just-placed widget draws something before it is configured. Backed by a
  `WidgetDesignEntity` + query reading the same file, the way
  `WidgetAlbumEntity` already does.
- `InstalledWidgets` reads `WidgetInfo.configuration` to learn **which designs**
  are placed, and asks only those whether they need the weather or the
  calendar. Strictly better than the current kind-level answer.

## Settings

- **Settings → Widgets** is two rows: **On This Day** (unchanged) and
  **Photo Widget**.
- **Photo Widget** pushes a designs list: one row per design (name + source
  summary), `+` to add, swipe to delete, rename and duplicate. Deleting the
  last design is refused — a placed widget needs something to read.
- Tapping a design opens today's `PhotoWidgetSettingsScreen`, now keyed by
  design id instead of kind, with the kind-gated sections replaced by the four
  visibility toggles.

## Editor screen, folded in

Carried over from the review agents' verdicts (`challenger`, `prior-art`,
2026-09-21). These get **more** necessary once every user meets the full screen
rather than only the `combined` one.

- **Selected block to the top.** `selectedComponentSection` becomes the first
  section when something is selected, holding that component's Position, nudge
  pad, size, Centre and Deselect. `arrangementSection` shrinks to a
  widget-level `layoutSection` (Text Position, Stack Everything Together, Photo
  Zoom, Reset Photo Framing) and stays visible — **not** an ellipsis menu:
  `spec.md:1142` justifies those destructive buttons having no confirmation
  precisely because they are in plain sight. The `ScrollViewReader` /
  `arrangementAnchor` scroll-jump is deleted.
- **Chips never vanish.** `PhotoWidgetComponent.components(for:settings:)`
  (`WidgetShared/PhotoWidgetComponent.swift:27`) drops a component when its
  toggle is off, so the chip disappears and there is no way back to it. The
  chip row switches to every component the widget can carry, dimmed when off;
  the face keeps using the filtered list to draw.
- **One size number per component.** The per-component row shows **pt**
  (`baseline × scale`) and writes `componentScales`; the shared
  `timeSize`/`dateSize` slider becomes **Default Text Size** in the Typeface
  section, keeping its batch behaviour. No change to the stored format. This
  also kills the two rows that both read "Time Size" today — points at
  `PhotoWidgetSettingsScreen.swift:391`, percent at `:796`.
- **Footers.** Apply the `accessExplanation(_:)` pattern already used by the
  calendar and weather permission rows to `photoSection` and `timeSection`;
  drop the per-family scaling sentence (implementation detail nobody acts on).

## Rejected

- **Ellipsis menu for the reset actions** — hides recovery exactly when it is
  wanted, and undoes the reasoning in `spec.md:1142`.
- **Style presets** — nothing stores which preset is applied, so the first
  slider drag detaches it silently; every value it would set is already
  directly settable.
- **"Custom…" folded into the format Picker** — the current labelled button is
  the category norm (Shortcuts, Widgy); saves two rows for a discoverability
  loss.
- **Replacing `componentScales` with per-component absolute sizes** — a
  wire-format change in a file both processes write, for a problem the UI-only
  fix already solves.
- **Two-pane master/detail on iPad** — that is the tier-D editor pattern
  (`DESIGN.md` §10.3); this screen is tier A.

## Phases

| # | Work | Done |
|---|------|------|
| P0 | `PhotoWidgetDesign`, file v2, migration, `showsWeather`/`showsCalendar`, unit tests | ✅ |
| P1 | One widget type, design intent parameter + entity + query, accessory from settings, `InstalledWidgets` by design | ✅ |
| P2 | App-side writers and `PhotoWidgetSettingsStore` keyed by design id | ✅ |
| P3 | Settings: two rows; designs list with add/rename/duplicate/delete | ✅ |
| P4 | Editor screen: four toggles, selected-block-to-top, chips never vanish, one size number, footers | |
| P5 | `spec.md` synced, full test run, iPhone screenshots ✅ — iPad / Duo inner + cover still to do | ◐ |

Each phase builds, runs the unit tests, and is screenshotted before its commit.

## Notes from the build

- `InstalledWidgets` answers the **union over every design** rather than only
  the placed ones. Which design a placed widget wears lives inside
  `ConfigurePhotoWidgetIntent`, a type in the extension target; reading it from
  the app would mean declaring the same AppIntent twice and having it listed
  twice in Shortcuts. The cost is one extra Open-Meteo request for someone who
  made a weather design and placed a different one. The location itself is
  still never asked for outside the Settings button.
- `PhotoWidgetFace`, `PhotoWidgetArrangedFace` and `PhotoWidgetPreview` lost
  their `kind` parameter outright: every use of it was "which rows exist",
  which is now four flags on the settings.
- **A migration that is not written back is a reload storm.** `read()` minted a
  fresh UUID per design on every call, so `PhotoWidgetSettingsStore.reloadFromDisk`
  — which compares what it holds against disk to pick up Home Screen edits —
  saw a difference every pass. Observable change on every read, the app never
  went idle, and XCUITest hung waiting for quiescence. `read()` now writes back
  whatever it synthesised; `migratingTwiceFromTheSameFileGivesTheSameIds` holds
  the line.
- The simulator's calendar prompt reappearing at launch after a `ui-drive` run
  is **not** the app asking: a driver script that taps Allow and ends without
  answering leaves the request pending in TCC, and it is re-presented on the
  next launch. `xcrun simctl privacy <udid> revoke calendar <bundle>` clears
  it; `reset` does not.
