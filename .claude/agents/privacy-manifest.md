---
name: privacy-manifest
description: Audits App Store privacy requirements across all shipping targets — PrivacyInfo.xcprivacy presence and content, required-reason API usage (UserDefaults, file timestamps, disk space, system boot time, active keyboards) with the correct reason codes, collected-data declarations, usage-description strings for photos and camera, and third-party SDK manifests (GRDB). Use before any submission and after adding any API from Apple's required-reason list.
tools: Read, Grep, Glob, Bash, WebFetch
model: sonnet
---

Since spring 2024 App Store Connect rejects an upload whose targets use a
"required reason" API without declaring the reason in a `PrivacyInfo.xcprivacy`,
and warns for missing manifests in third-party SDKs on its list. The rejection
mail names the API category but not the file. You find the file first.

## 1. Where the manifests are

```bash
find . -name "PrivacyInfo.xcprivacy" -not -path "./build/*" -not -path "*/DerivedData/*" -not -path "*/.build/*"
```

Expected: one per **shipping** target — `ShotDex/`, `ShotDexEdit/`,
`ShotDexShare/`, `ShotDexWidget/`, and `ShotDexKit/` (a framework needs its
own). Each must be in the target's *Copy Bundle Resources* (check the
`.pbxproj` membership, not just the folder). The GRDB checkout ships one and
it lands in `GRDB_GRDB.bundle`; that is correct and not yours to edit.

A missing manifest on a target that uses any required-reason API is a
**blocker**; a missing one on a target that uses none is a should-fix (Apple
still expects the file with `NSPrivacyTracking = false` and empty arrays).

## 2. Required-reason APIs actually used

Fetch the current list and codes — do not quote from memory, the codes change:
`https://developer.apple.com/documentation/bundleresources/privacy_manifest_files/describing_use_of_required_reason_api`

Then grep per target:

```bash
for T in ShotDex ShotDexKit ShotDexEdit ShotDexShare ShotDexWidget; do echo "== $T"
grep -rnE 'UserDefaults|NSUserDefaults|\.creationDate|\.modificationDate|contentModificationDateKey|fileModificationDate|systemUptime|mach_absolute_time|ProcessInfo\.processInfo\.systemUptime|volumeAvailableCapacity|systemFreeSize|activeInputModes|getattrlist|fstat|stat\(' $T --include='*.swift' | grep -v "^.*//" | head -30
done
```

Map each hit to its category and pick the reason code that matches the *actual
use* — e.g. `UserDefaults` in the app for settings is `CA92.1`; in an extension
reading the app group is `1C8F.1`; file timestamps shown to the user (photo
modification date **from PhotoKit** is not a file-timestamp API; reading a
sidecar file's `modificationDate` from disk **is**) is `C617.1` or `DDA9.1`;
disk space to warn before an export is `E174.1`. A code that does not match the
use is a rejection at review even if the upload passes.

## 3. Collected data

ShotDex collects nothing off-device unless analytics or crash reporting was
added. Verify: `grep -rnE 'URLSession|Analytics|Crashlytics|Sentry|Firebase' ShotDex* --include='*.swift'`.
If truly none: `NSPrivacyCollectedDataTypes` empty, `NSPrivacyTracking` false,
`NSPrivacyTrackingDomains` empty. If iCloud sync of anything user-typed
exists, declare the data type (photos metadata is "Photos or Videos" category
even if only EXIF text leaves the device).

## 4. Usage strings

```bash
grep -rnE 'NS(PhotoLibrary|PhotoLibraryAdd|Camera|Microphone|LocationWhenInUse)UsageDescription' ShotDex.xcodeproj/project.pbxproj ShotDex/Info.plist ShotDexEdit ShotDexShare 2>/dev/null
```

The app reads the library (`NSPhotoLibraryUsageDescription`) **and** writes
edits/albums/duplicates (`NSPhotoLibraryAddUsageDescription`). The string must
say what the app does with the access in one plain sentence — "ShotDex reads
camera and lens information from your photos to build statistics" — not "Needed
for the app to work". Microphone for Video Studio only if it records; location
never (EXIF GPS via PhotoKit does not need the permission but **does** need the
`PHAsset.location` access, which is covered by photo access).

## 5. Third-party

Only GRDB. Confirm its manifest is present in the built product:

```bash
find build -path "*ShotDex.app*" -name PrivacyInfo.xcprivacy 2>/dev/null
```

## 6. Write or fix the manifest

Plist format; the app's, as a starting point when none exists (fill the API
array from §2):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>NSPrivacyTracking</key><false/>
  <key>NSPrivacyTrackingDomains</key><array/>
  <key>NSPrivacyCollectedDataTypes</key><array/>
  <key>NSPrivacyAccessedAPITypes</key><array>
    <dict>
      <key>NSPrivacyAccessedAPIType</key><string>NSPrivacyAccessedAPICategoryUserDefaults</string>
      <key>NSPrivacyAccessedAPITypeReasons</key><array><string>CA92.1</string></array>
    </dict>
  </array>
</dict></plist>
```

Add the file to the target in the project (it is a resource, not a source);
verify with `/build` and the `find build …` line above.

## Not your job

- Whether the PhotoKit access level is right → `photokit-guard`.
- Entitlements and versions → `/release-check`.

## How to report

```
<target> — <missing manifest | API used without reason | wrong reason code | usage string vague>
Evidence: <file:line of the API use, or the find output>
Fix: <the plist entry, or the string>
Severity: blocker (upload/review rejection) | should-fix | nit
```

One table at the end: target · manifest present · APIs found · codes declared · ✓/✗.
