# FS-24 Video compression (batch HEVC)

| Field | Value |
|---|---|
| Intent | [`docs/_intents/2026-11-17-batch-video-compress.md`](../_intents/2026-11-17-batch-video-compress.md) (accepted 2026-11-17) |
| Evidence | [`docs/_intents/2026-11-17-handbrake-convert-evidence.md`](../_intents/2026-11-17-handbrake-convert-evidence.md) |
| Devices | iPhone · iPad · Duo inner + cover · Mac |
| Progress | **in progress**: §1–9 built 2026-11-17 (boards `*_VideoCompress[Run]`); §10 Compare Videos + summary spec and boards (`*_VideoCompressDone`, `*_VideoCompare`) 2026-11-18, **not coded** |

## 1. Behaviour

1. The selection's ⋯ menu has its own **Compress Videos** row (after Resize), on Library,
   Album, Smart Album and On This Day; Mac: **Image › Compress Videos…**. It is enabled when the
   selection holds at least one video. Resize (photos, FS-03 §7) is unchanged. Mixed photos and
   videos → Compress Videos works on the videos alone, and the screen says how many photos were
   left out.
2. Compress Videos screen:
   - **Quality**: `Maximum` · `High Quality` (default) · `Balanced` · `Smallest`, each with a one-line
     description. No raw RF/bitrate number.
   - **Size** (resolution cap): `Original` (default) · `4K` · `1080p`. The long edge is capped,
     never enlarged; aspect ratio is kept.
   - **Estimate**: total before → estimated total after, and the space saved.
   - Note: "HDR stays HDR. Originals are kept until you delete them."
   - Header: `Cancel` · title · `Compress` (accent).
3. Encoding (idea from HandBrake `encvt.c`, own code on AVFoundation):
   - HEVC, **constant quality** `AVVideoQualityKey`: Maximum 0.70 · High 0.60 · Balanced 0.50 · Smallest 0.40
     (HandBrake VT 1080p = 0.60; spike 2026-11-17: synthetic 1080p H.264 40 Mbps → 88% / 58% / 38%).
   - `RealTime = false`, `PrioritizeEncodingSpeedOverQuality = true` (HandBrake preset `speed`).
   - The source is read as 10-bit 4:2:0. **HDR (HLG / PQ) stays HDR**: Main10 + the source's
     primaries, transfer function and matrix. SDR sources stay SDR (Main10 is still used, which
     costs nothing in size and avoids banding).
   - Audio: **AAC sound is copied untouched** (camera and iPhone files: R6 II carries AAC 256 kbps, ~0.5% of
     a compressed file — encoding it again loses quality for nothing). Other sound (PCM…) is encoded once to
     AAC 256 kbps, keeping the channel count (max 2). Frame rate and duration
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
8. Summary (boards `*_VideoCompressDone`): "Compressed N videos · saved X"; each row says
   `<before> → <after> · −NN%`, or why it was skipped/failed. Buttons `Compare Before and After`
   (opens §10 on the first compressed file), `Delete Originals` (moves the originals of
   successful files to Recently Deleted through PhotoKit's own confirmation) and `Done`. A
   compressed row is itself a button (chevron) that opens §10 on that file; Mac: double-click.
9. iCloud originals are downloaded first (network allowed), with that phase shown in the
   per-file progress.

10. **Compare Videos** (boards `*_VideoCompare`; added 2026-11-18 at the user's request): the
    original (A) and its compressed copy (B), modelled on the photo Compare (`PhotoCompareScreen`).
    - **Panes**: stacked on a compact screen, side by side on a wide one (≥ 700pt, as photo
      Compare); Mac: in the same window, the list page gives way to it and `‹` comes back
      (`mac-few-windows`). Each pane is labelled `A Original · <size> · <codec>` and
      `B Compressed · <size> · −NN%`.
    - **One clock**: a single transport drives both — play/pause, a scrubber with time and
      duration, previous/next frame. B follows A's time: seeking moves both to the same frame;
      while playing, B is slaved to A's clock (drift corrected, never more than one frame apart
      when paused). Sound comes from A (identical after §1.3's copy); a speaker button mutes it.
      Opens paused on the first frame.
    - **Zoom**: a pinch zooms both panes to the same spot (1×–8×), a drag pans both, a double-tap
      toggles 1× ↔ 3× at the tapped point; a `N×` badge shows on each pane while zoomed. Works
      while playing and paused. Mac: trackpad pinch or ⌘-scroll.
    - **Hold** a pane (Mac: hold Option) = the other video's frame at the same zoom, as in photo
      Compare, so the two can be flicked at one spot.
    - **Header**: close · file name + "Saved X" · `Delete Original` (red; icon-only on a compact
      screen). It deletes this file's original through PhotoKit's confirmation; the pair then leaves
      the comparison and the next one shows; with none left the screen closes, and the summary
      counts the deletion.
    - **Stepping**: `‹ Video N of M ›` walks the files that were compressed (skipped and failed are
      not in it).
    - **Keys** (iPad with a keyboard, Mac): Space play/pause · ←/→ frame · ⌘←/⌘→ video ·
      ⌘⌫ Delete Original · Esc close.
    - iCloud originals: A streams with network allowed (as the Viewer); the compressed copy is
      local, just written.

## 2. Acceptance criteria

| AC | Criterion | Proof |
|---|---|---|
| AC-24.01 | ⋯ menu has Compress Videos, enabled with ≥1 video selected; Resize unchanged | ui-drive iPhone + screenshot |
| AC-24.02 | Mixed selection: the screen says "M photo(s) in the selection … left out" | screenshot |
| AC-24.03 | The 4 quality levels map to quality 0.70 / 0.60 / 0.50 / 0.40 (Maximum added 2026-11-18 after the R6 II measurement, intent §5) | unit test `VideoCompressionRulesTests` |
| AC-24.04 | Resolution cap: 3840×2160 source with 1080p → 1920×1080; 1280×720 with 4K → unchanged (never enlarged); portrait keeps orientation | unit test |
| AC-24.05 | Estimate shown before running, total before → after | unit test of the estimate + screenshot |
| AC-24.06 | Encode outputs HEVC, the same duration (±1 frame) and frame rate, with audio when the source has audio; AAC sound is copied, not re-encoded | test on a generated file |
| AC-24.07 | HDR source (HLG) → output still HLG BT.2020 10-bit | test on a generated HLG file |
| AC-24.08 | Output ≥ 95% of source → "Already compact", nothing saved | unit test of the skip rule |
| AC-24.09 | Not enough free space → the batch stops with the message, already-finished files are kept | unit test of the space rule |
| AC-24.10 | Saves to Photos with the same date, location, favourite and albums | sim, demo library |
| AC-24.14 | The copy is named `<original>_compressed.mp4`, never with the suffix twice | unit test `outputFilenameAddsSuffixOnce` + sim Photos library |
| AC-24.11 | Progress per file + overall; Stop works; a failing file does not stop the batch | screenshot + unit test of the queue |
| AC-24.12 | Summary with space saved; Delete Originals goes to Recently Deleted | screenshot |
| AC-24.13 | Screen present on iPhone, iPad, Duo inner, Duo cover, Mac, matching each device's board | screenshots of every device, 2 review rounds |
| AC-24.15 | Summary has `Compare Before and After`; a compressed row opens Compare on that file; skipped/failed rows do not | screenshot + ui-drive iPhone |
| AC-24.16 | Compare shows A = original and B = copy with size, codec and −NN% labels; stacked < 700pt, side by side ≥ 700pt | screenshots iPhone, iPad, Duo inner + cover, Mac vs `*_VideoCompare` |
| AC-24.17 | One transport: seek puts both on the same frame (paused: same presentation time ±1 frame); play keeps them within one frame | unit test of the time-sync rule + sim |
| AC-24.18 | Pinch/double-tap zoom and pan apply to both panes at the same spot, playing or paused; badge shows N× | ui-drive dump (both panes' zoom) + screenshot |
| AC-24.19 | Holding a pane shows the other video's frame at the same zoom | screenshot |
| AC-24.20 | `Delete Original` removes only this pair's original via PhotoKit confirmation, steps to the next pair, closes when none left; summary reflects it | sim, demo library |
| AC-24.21 | `‹ Video N of M ›` steps only through compressed files | unit test of the list + screenshot |
| AC-24.22 | Keys Space / ←→ / ⌘←⌘→ / ⌘⌫ / Esc work on iPad and Mac | ui-drive key steps / Mac run |
