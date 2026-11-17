# FS-24 Video compression (batch HEVC)

| Field | Value |
|---|---|
| Intent | [`docs/_intents/2026-11-17-batch-video-compress.md`](../_intents/2026-11-17-batch-video-compress.md) (accepted 2026-11-17) |
| Evidence | [`docs/_intents/2026-11-17-handbrake-convert-evidence.md`](../_intents/2026-11-17-handbrake-convert-evidence.md) |
| Devices | iPhone · iPad · Duo inner + cover · Mac |
| Progress | **in progress** (2026-11-17): code + boards (`PH_/IP_/DI_/DC_/MAC_VideoCompress[Run]`) on all 4 canvases; screenshot review ×2 |

## 1. Behaviour

1. The selection's ⋯ menu has its own **Compress Videos** row (after Resize), on Library,
   Album, Smart Album and On This Day; Mac: **Image › Compress Videos…**. It is enabled when the
   selection holds at least one video. Resize (photos, FS-03 §7) is unchanged. Mixed photos and
   videos → Compress Videos works on the videos alone, and the screen says how many photos were
   left out.
2. Compress Videos screen:
   - **Quality**: `High Quality` (default) · `Balanced` · `Smallest`, each with a one-line
     description. No raw RF/bitrate number.
   - **Size** (resolution cap): `Original` (default) · `4K` · `1080p`. The long edge is capped,
     never enlarged; aspect ratio is kept.
   - **Estimate**: total before → estimated total after, and the space saved.
   - Note: "HDR stays HDR. Originals are kept until you delete them."
   - Header: `Cancel` · title · `Compress` (accent).
3. Encoding (idea from HandBrake `encvt.c`, own code on AVFoundation):
   - HEVC, **constant quality** `AVVideoQualityKey`: High 0.60 · Balanced 0.50 · Smallest 0.40
     (HandBrake VT 1080p = 0.60; spike 2026-11-17: synthetic 1080p H.264 40 Mbps → 88% / 58% / 38%).
   - `RealTime = false`, `PrioritizeEncodingSpeedOverQuality = true` (HandBrake preset `speed`).
   - The source is read as 10-bit 4:2:0. **HDR (HLG / PQ) stays HDR**: Main10 + the source's
     primaries, transfer function and matrix. SDR sources stay SDR (Main10 is still used, which
     costs nothing in size and avoids banding).
   - Audio: AAC 160 kbps, keeping the source's channel count (max 2). Frame rate and duration
     unchanged.
4. Batch: a queue, **one file at a time** (two on Mac). The screen does not lock while it runs;
   iOS gets the system's background grace period when the user leaves the app (no
   `BGContinuedProcessingTask` yet: a long batch left in the background can be stopped by iOS —
   the files already saved stay). Per-file and overall progress. `Stop`
   cancels the current file and the rest; files already done are kept. One file failing does not
   stop the others.
5. **Skip rule:** if the output is ≥ 95% of the source size, it is thrown away and the file is
   reported as "Already compact". The original is untouched.
6. **Free space:** before each file, the space available for important work (`DiskSpace`,
   `volumeAvailableCapacityForImportantUsage`, the same figure Resize and the downloads use) must
   be at least 2 × the source size + 500 MB (original copy + output + Photos' copy of it), re-checked after the download; otherwise the batch stops with "Not enough free
   space". (Purgeable space counts: the system reclaims it for a write the user asked for.)
7. Save: a new video in Photos with the original's **capture date, location and favourite** and
   in the **same albums** (user albums). The original is kept. The copy's file name is the
   original's with `_compressed` appended (`IMG_0042.MOV` → `IMG_0042_compressed.mp4`), so the two
   are told apart in Photos' Info, in Files and on a server; a name that already ends in
   `_compressed` keeps a single suffix.
8. Summary: "Compressed N videos · saved X" plus a list of skipped/failed files with the reason.
   Buttons `Delete Originals` (moves the originals of successful files to Recently Deleted
   through PhotoKit's own confirmation) and `Done`.
9. iCloud originals are downloaded first (network allowed), with that phase shown in the
   per-file progress.

## 2. Acceptance criteria

| AC | Criterion | Proof |
|---|---|---|
| AC-24.01 | ⋯ menu has Compress Videos, enabled with ≥1 video selected; Resize unchanged | ui-drive iPhone + screenshot |
| AC-24.02 | Mixed selection: the screen says "M photo(s) in the selection … left out" | screenshot |
| AC-24.03 | The 3 quality levels map to quality 0.60 / 0.50 / 0.40 | unit test `VideoCompressionRulesTests` |
| AC-24.04 | Resolution cap: 3840×2160 source with 1080p → 1920×1080; 1280×720 with 4K → unchanged (never enlarged); portrait keeps orientation | unit test |
| AC-24.05 | Estimate shown before running, total before → after | unit test of the estimate + screenshot |
| AC-24.06 | Encode outputs HEVC, the same duration (±1 frame) and frame rate, with audio when the source has audio | test on a generated file |
| AC-24.07 | HDR source (HLG) → output still HLG BT.2020 10-bit | test on a generated HLG file |
| AC-24.08 | Output ≥ 95% of source → "Already compact", nothing saved | unit test of the skip rule |
| AC-24.09 | Not enough free space → the batch stops with the message, already-finished files are kept | unit test of the space rule |
| AC-24.10 | Saves to Photos with the same date, location, favourite and albums | sim, demo library |
| AC-24.14 | The copy is named `<original>_compressed.mp4`, never with the suffix twice | unit test `outputFilenameAddsSuffixOnce` + sim Photos library |
| AC-24.11 | Progress per file + overall; Stop works; a failing file does not stop the batch | screenshot + unit test of the queue |
| AC-24.12 | Summary with space saved; Delete Originals goes to Recently Deleted | screenshot |
| AC-24.13 | Screen present on iPhone, iPad, Duo inner, Duo cover, Mac, matching each device's board | screenshots of every device, 2 review rounds |
