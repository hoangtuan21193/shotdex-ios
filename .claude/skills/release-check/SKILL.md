---
name: release-check
description: Pre-submission checklist for ShotDex and its four extensions — version and build numbers, privacy manifest and usage strings, entitlements and app groups, localization completeness, archive validation. Run before any TestFlight or App Store build; reports each item as pass / fail / not checkable here.
---

# Release check

Six targets ship together: `ShotDex`, `ShotDexKit`, `ShotDexEditAction`
("Edit in ShotDex" action extension), `ShotDexShare` ("Save to ShotDex"),
`ShotDexAddLook` ("Add to ShotDex", FS-03.14c §4) and `ShotDexWidget`, plus the
two test targets that do not ship. `LookInboxShared/` and `WidgetShared/` are
folders compiled into more than one target, not targets. Everything below is checked from the project file and the
built product, not from memory.

## 1. Versions

```bash
for t in ShotDex ShotDexKit ShotDexEditAction ShotDexShare ShotDexAddLook ShotDexWidget; do
  printf "%-18s " $t
  xcodebuild -project ShotDex.xcodeproj -target $t -configuration Release -showBuildSettings 2>/dev/null \
    | /usr/bin/grep -E "^ +(MARKETING_VERSION|CURRENT_PROJECT_VERSION) =" | tr -s ' ' | tr '\n' ' '; echo
done
```

Every shipping target must have the **same** `MARKETING_VERSION` and
`CURRENT_PROJECT_VERSION`; App Store Connect rejects an extension whose version
differs from its host. Bump both in one edit if asked; never bump only the app.

## 2. Privacy

- `ls ShotDex ShotDexKit ShotDexEditAction ShotDexShare ShotDexAddLook ShotDexWidget | grep -c PrivacyInfo.xcprivacy`
  must print 6 — each **shipping target** needs one. Absence is a fail (the `privacy-manifest`
  agent lists which required-reason APIs are in use).
- Usage strings in the app's Info.plist / build settings:
  `NSPhotoLibraryUsageDescription`, `NSPhotoLibraryAddUsageDescription`
  (the app writes edits and albums), `NSCameraUsageDescription` only if used.
  `grep -rn "NSPhotoLibrary" ShotDex.xcodeproj/project.pbxproj ShotDex/Info.plist`.
- No `NSPrivacyTracking` true, no tracking domains — this app has none.

## 3. Entitlements and capabilities

- App group `group.com.hoangtuan.shotdex` in exactly the targets that share a
  store: the app (`ShotDex-AppAttest.entitlements`, Debug and Release),
  the widget and `ShotDexAddLook`. `ShotDexShare` deliberately has none — it
  keeps its minimum rights (14c §4) — so a group there is a fail, not a fix.
  `for f in ShotDex/*.entitlements ShotDexWidget/*.entitlements ShotDexShare/*.entitlements ShotDexAddLook/*.entitlements; do echo "$f $(/usr/bin/grep -c group.com.hoangtuan.shotdex $f)"; done`
- `ShotDexEditAction`: `NSExtensionPointIdentifier = com.apple.ui-services`,
  activation rule images only, max 1.
- Widget: `NSExtensionPointIdentifier = com.apple.widgetkit-extension`.
- Share: activation rule accepts images only, count bounded.
- `ShotDexAddLook` (FS-03.14c §4):
  - `NSExtensionPointIdentifier = com.apple.share-services`, principal class
    `ShotDexAddLook.AddLookViewController`.
  - Activation rule is the `SUBQUERY` over `com.hoangtuan.shotdex.look` **only** —
    every attachment must conform, at most 50 — so it never offers itself for a
    photo, a PDF or a `.xmp`. Anything wider (`public.data`, `public.json`,
    `TRUEPREDICATE`, a missing rule) is a fail.
    `/usr/bin/grep -A1 NSExtensionActivationRule ShotDexAddLook/Info.plist`
  - The type it names is the one the app exports: `UTExportedTypeDeclarations` in
    `ShotDex/Info.plist` has `com.hoangtuan.shotdex.look`, extension
    `shotdexlook`, conforming to `public.data` + `public.content` (not
    `public.json`, 14c §5).
  - Its ceilings come from `LookInboxShared/LookInboxLocation.swift` (16 MB a
    file, 50 files / 50 MB waiting); the extension reads sizes and copies bytes,
    never parses — `LookInboxTests.extensionRefusesOversizedFiles` is the proof.
  - Privacy manifest: `NSPrivacyAccessedAPITypes` empty is correct. The
    extension calls `FileManager.copyItem` and reads `URLResourceValues.fileSize`
    only; file *size* is not on Apple's required-reason list (file timestamps
    and disk space are). If it ever reads `creationDate` /
    `contentModificationDate` or volume capacity, it needs
    `NSPrivacyAccessedAPICategoryFileTimestamp` (`C617.1`) or
    `…DiskSpace` in its **own** manifest — the app's manifest does not cover it.
    The app side (`LookInbox.swift` sorts by `creationDate` inside its own
    container) is covered by the app's `C617.1`.

## 4. Localization

```bash
python3 - <<'PY'
import json
d=json.load(open("ShotDex/Resources/Localizable.xcstrings"))
src=d["sourceLanguage"]; langs=set(); missing={}
for v in d["strings"].values():
    langs |= set(v.get("localizations",{}))
langs.discard(src)  # source-language keys carry their own text; no entry needed
for v in d["strings"].values():
    if v.get("shouldTranslate") is False: continue
    for l in langs:
        if l not in v.get("localizations",{}): missing[l]=missing.get(l,0)+1
print("source:",src,"targets:",sorted(langs),"keys:",len(d["strings"])); print("missing per language:",missing)
PY
```

Any language with missing keys ships English fallbacks; report the count.

## 5. Build settings that bite at review

- `ENABLE_BITCODE` irrelevant now; `STRIP_SWIFT_SYMBOLS` yes in Release.
- `ONLY_ACTIVE_ARCH = NO` in Release.
- Extension memory: share and action extensions have a ~120MB ceiling; any
  image decode at full resolution in an extension path is a fail (the
  `extension-boundary` agent checks the code path). `ShotDexAddLook` must stay
  under 30 MB peak (FS-03.14 AC-c10): Instruments → Allocations on a device,
  sharing 20 small looks and one 40 MB file — not checkable on the simulator.
- Min deployment iOS 17 on every target (`IPHONEOS_DEPLOYMENT_TARGET`).

## 6. Archive + validate

```bash
xcodebuild -project ShotDex.xcodeproj -scheme ShotDex -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/ShotDex.xcarchive archive 2>&1 \
  | grep -E "error:|ARCHIVE (SUCCEEDED|FAILED)"
```

Export and `xcrun altool --validate-app` need the user's signing identity and
App Store Connect key; report that step as **not checkable here** and hand the
user the exact commands rather than pretending.

## 7. Lens data refresh (FS-03.16b §4)

Every release carries the newest Lensfun data. The machine running the check
has network; the app never needs it.

```bash
LF=$(mktemp -d)/lensfun
git clone --depth 1 --filter=blob:none --sparse https://github.com/lensfun/lensfun.git "$LF"
git -C "$LF" sparse-checkout set data/db
python3 Tools/lensfun-to-json.py "$LF/data/db" ShotDexKit/Resources/lensfun-profiles.json \
  --previous ShotDexKit/Resources/lensfun-profiles.json
python3 -m unittest discover -s Tools/tests
```

- The script prints one line — "Lens profiles a → b · vignetting … · TCA … ·
  cameras … · KB → KB" — and every lens id that disappeared (a warning: photos
  pointing at one fall back to "No profile for this lens yet", FS-03.16 AC-6).
- It **fails** and leaves the table untouched when the directory has no lenses,
  the lens count drops more than 1%, or the JSON passes **4 MB**. Past the
  ceiling the table moves to compressed-in-bundle; lenses are never cut.
- Then run the lens tests (`/test LensProfileTests`) and commit the new JSON on
  its own. Report the printed line as evidence.

## 8. Functional smoke, on device class

Run `/screens` for: first launch with no permission, `.limited` access, an empty
library, the editor round-trip (open → adjust → save → reopen shows edit), the
extension invoked from Photos, the widget in the gallery, and "Add to ShotDex"
from Files (`Tools/ui-drive <udid> ShotDexUITests/scripts/add-to-shotdex.json`:
two looks shared, the app shows "2 looks added"). Physical device for the 55k
library, Optimize Storage proxies, and AirDrop of a look to a phone without
ShotDex (FS-03.14 AC-c11, two devices).

## Report

One table: item · pass/fail/not-checkable · evidence (the grep line or file).
Fails first. Nothing marked pass without the command that showed it.
