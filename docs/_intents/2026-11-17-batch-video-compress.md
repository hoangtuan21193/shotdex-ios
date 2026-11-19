# Intent: Batch video compression, smaller files at the same quality

| Field | Value |
|---|---|
| Author | Hoang Tuan (user) · drafted by Claude |
| Date | 2026-11-17 |
| Status | accepted (2026-11-17, user accepted the 4 default proposals) |
| Progress | **in progress** (2026-11-18) — FS-24 coded on all devices; Compare 4/8 AC green (AC-24.15/17/19/21), missing AC-24.16/18/20/22 (partial: Duo cover, Duo zoom, confirmed delete, Esc/⌘⌫ on iPad) |
| Source | user idea, after the 105 GB-but-"not enough storage" camera import on a real iPhone (same day); HandBrake evidence |
| Spec produced from this | (filled in at Design) |

## Problem

Photographers fill their phone with video: camera clips copied over the cable (Canon MP4
H.264, high bitrate) and iPhone 4K clips. A 4K H.264 minute is several hundred MB. The library
fills up, and importing from the camera starts failing for lack of space (incident 2026-11-17:
an 8 GB import failed even though the phone showed 105 GB free).

Today ShotDex **cannot shrink a video**:
- `Compress` in the selection bar handles **photos only** (`SelectionBarModel.swift:24,51`:
  "How many of the selected assets are images — Collage / Compress / Export").
- The only video encoder, `VideoExportWriter` (Video Studio), forces **SDR Rec.709, HEVC Main
  8-bit, fixed bitrate** (`VideoExportWriter.swift:73-95`). Running an iPhone HDR video through
  it would lose HDR and give the file a bitrate unrelated to its content.
- The user has to install another app (HandBrake on the Mac) and move files back and forth,
  losing date, place and album along the way.

## Proposed outcome

- Select one or many videos (Library, album, search results) → **Compress** → pick a level
  (for example High quality / Balanced / Smallest) and a resolution cap → see the **estimated
  size before and after** → run.
- Results: HEVC that looks the same at normal viewing, often 40–70% smaller for H.264 sources;
  **HDR stays HDR**; capture date, place, favourite and albums carry over; the original is
  handled by the user's choice (see Open questions).
- The batch runs to completion with overall and per-file progress. It can be cancelled, and a
  file that fails does not stop the others. A file that would come out larger (already
  efficient HEVC) is **skipped**, with the reason given.
- At the end: "Compressed 12 videos, saved 3.4 GB".
- Same behaviour on iPhone, iPad, Duo (inner + cover) and Mac.

How HandBrake does it (evidence: `docs/_intents/2026-11-17-handbrake-convert-evidence.md`):
encode with **constant quality** (VideoToolbox `Quality`, 1080p preset = 60/100, 4K = 55) rather
than a fixed bitrate, HEVC **10-bit**, cap the resolution at the preset, AAC audio at 160 kbps,
and a queue of 1–4 workers.

## Affected users and systems

- **Screens:** selection bar (enable Compress when the selection contains videos), a new
  "Compress videos" sheet/screen, batch progress, end-of-run summary; the photo Viewer/Player
  ("Compress this video"); Mac: menu + Activity popover (`mac-few-windows` rule: no new window).
- **Devices:** iPhone · iPad · Duo inner · Duo cover · Mac. Each needs a board on its device
  canvas before code.
- **Code layers:** Data (an encoder separate from or extending `VideoExportWriter`: quality mode,
  Main10, carry colour/HDR metadata; PhotoKit creation + copying date/location/albums), Domain
  (size estimation, level → quality mapping, skip rule), Features (sheet + queue model).
- **Saved data:** no schema change expected. Creating/deleting PHAssets is **writing to the
  user's real library** → photokit-guard review needed.

## Constraints

- **No HandBrake/FFmpeg/x265** (GPL, App Store). Only Apple's AVFoundation / VideoToolbox.
  No new dependency.
- **On-device processing**: nothing is uploaded to a server.
- Never fill the device storage: check free space (real free space, not including purgeable)
  before each file, and stop the batch when it runs low.
- iCloud originals (Optimize Storage): the original has to be downloaded first. This can take
  long and use data, so the network policy follows existing settings.
- Background: iOS cuts long work short. A batch has to survive switching apps
  (iOS 26: `BGContinuedProcessingTask`; earlier: run while foreground, resumable).
- **No real photos/videos changed or deleted during tests** (`no-real-photo-writes-in-tests`):
  demo library only.
- Keep the iOS 26 and pre-26 branches working; Video Studio export must not regress.

## Open questions

Decided (user, 2026-11-17):

1. ~~Original~~ → **keep both**; the summary has a "Delete originals" button (goes to Recently Deleted).
2. ~~Quality levels~~ → **3 levels** (High quality / Balanced / Smallest) + a **resolution cap**
   (Original / 4K / 1080p); no RF/bitrate number shown.
3. ~~HDR~~ → **keep HDR 10-bit**.
4. ~~Destination~~ → **into Photos**, carrying date, place, favourite and albums; Export to Files stays as it is today.

Still open (answered at /spec or on a real device):
5. Starting point known (HandBrake source: `Quality` = slider/100, 1080p = 0.60, 4K = 0.55,
   `RealTime=false`). Still to measure: the mapping of ShotDex's 3 levels → `AVVideoQualityKey`, and the real size saved on Canon
   files (H.264 4:2:0 8-bit) vs iPhone files: **measured in a spike** on real sample files
   before writing the ACs (Claude does this at /spec).
   **Measured 2026-11-18** on two 21 s Canon R6 Mark II clips (3840×2160 59.94p, H.264 High
   8-bit full range, indoor low light, fine text): ALL-I 620.6 MB (233 Mbps), IPB 324.2 MB
   (123 Mbps). Encoded on the Mac's VideoToolbox with the app's settings (HEVC Main10,
   RealTime off, speed hint on; ~7 s per clip). VMAF 4K model (harmonic mean) and SSIM against
   a ProRes 422 HQ reference decoded by the same AVFoundation reader, so the score is the
   encoder's loss alone:

   | Quality | ALL-I size | VMAF | IPB size | VMAF |
   |---|---|---|---|---|
   | 0.50 (Balanced) | 31.6 MB (5%) | 94.2 | 20.7 MB (6%) | 95.1 |
   | 0.60 (High) | 70.7 MB (11%) | 97.6 | 50.2 MB (15%) | 98.0 |
   | 0.70 | 202.2 MB (33%) | 99.5 | 165.3 MB (51%) | 99.7 |
   | 0.80 | 587.0 MB (95%) | 99.98 | 473.7 MB (146%) | 100.0 |
   | 0.90 | 2042 MB (329%) | 100.0 | 1599 MB (493%) | 100.0 |

   The speed hint costs ~0.1 VMAF and halves the encode time. 0.80 and above are larger than
   the camera file. ffmpeg decodes the full-range source ~2/255 apart from AVFoundation
   (PSNR ceiling ~34 dB against the camera file at any quality) — a decoder difference, not
   encoder loss; Photos plays through AVFoundation. Not yet measured: iPhone's encoder, an
   outdoor/high-motion scene, Smallest (0.40).
6. Can the Duo cover / iPhone sustain a 10-minute 4K batch without throttling or running hot?
   Needs a real device to measure; the simulator does not answer it.

---

_When accepted: commit it as its own commit, then run `/spec` to move to Design._
