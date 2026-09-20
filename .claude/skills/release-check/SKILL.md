---
name: release-check
description: Pre-submission checklist for ShotDex and its three extensions — version and build numbers, privacy manifest and usage strings, entitlements and app groups, localization completeness, archive validation. Run before any TestFlight or App Store build; reports each item as pass / fail / not checkable here.
---

# Release check

Seven targets ship together: `ShotDex`, `ShotDexKit`, `ShotDexEdit` (photo
editing extension), `ShotDexShare`, `ShotDexWidget`, plus the two test targets
that do not ship. Everything below is checked from the project file and the
built product, not from memory.

## 1. Versions

```bash
grep -n "MARKETING_VERSION\|CURRENT_PROJECT_VERSION" ShotDex.xcodeproj/project.pbxproj | sed 's/^[^:]*:[^=]*= //' | sort | uniq -c
```

Every shipping target must have the **same** `MARKETING_VERSION` and
`CURRENT_PROJECT_VERSION`; App Store Connect rejects an extension whose version
differs from its host. Bump both in one edit if asked; never bump only the app.

## 2. Privacy

- `find ShotDex ShotDexEdit ShotDexShare ShotDexWidget -name PrivacyInfo.xcprivacy` —
  each **shipping target** needs one. Absence is a fail (the `privacy-manifest`
  agent lists which required-reason APIs are in use).
- Usage strings in the app's Info.plist / build settings:
  `NSPhotoLibraryUsageDescription`, `NSPhotoLibraryAddUsageDescription`
  (the app writes edits and albums), `NSCameraUsageDescription` only if used.
  `grep -rn "NSPhotoLibrary" ShotDex.xcodeproj/project.pbxproj ShotDex/Info.plist`.
- No `NSPrivacyTracking` true, no tracking domains — this app has none.

## 3. Entitlements and capabilities

- App group shared between app and extensions if any store is shared
  (`grep -rn "group\." --include=*.entitlements .`).
- `ShotDexEdit`'s `NSExtension` dictionary: `PHSupportedMediaTypes` includes
  `Image`; extension attributes match what the kit renders.
- Widget: `NSExtensionPointIdentifier = com.apple.widgetkit-extension`.
- Share: activation rule accepts images only, count bounded.

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
- Extension memory: `ShotDexEdit` has a ~120MB ceiling; any image decode at
  full resolution in the extension path is a fail (the `extension-boundary`
  agent checks the code path).
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

## 7. Functional smoke, on device class

Run `/screens` for: first launch with no permission, `.limited` access, an empty
library, the editor round-trip (open → adjust → save → reopen shows edit), the
extension invoked from Photos, the widget in the gallery. Physical device for the
55k library and Optimize Storage proxies.

## Report

One table: item · pass/fail/not-checkable · evidence (the grep line or file).
Fails first. Nothing marked pass without the command that showed it.
