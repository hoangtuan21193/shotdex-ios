# HandBrake 1.11.2: how Convert works (reverse-engineering evidence)

Date: 2026-11-17. Goal: understand how HandBrake shrinks a video while keeping its quality, then
carry the idea, not the code, into ShotDex (batch video compression).
Targets (shipped artifacts, macOS, arm64 slice):

| Artifact | SHA-256 |
|---|---|
| `/Applications/HandBrake.app/Contents/MacOS/HandBrake` (UI, ObjC) | `08444f02e6788fec6d400aea4372ddca1409675e2b4fe1fd7c55794c1f082649` |
| `…/Frameworks/HandBrakeKit.framework/Versions/A/HandBrakeKit` (libhb + FFmpeg + x265 …, 108.7 MB) | `ee4fb49b61394f7598981077c1610f30c722a9f93bb85ed7825db719a0b17349` |

Tools: REA + Hopper (UI binary, decompiled), `nm` / `strings` (HandBrakeKit; Hopper's initial
analysis did not finish within 120 s on the 108 MB binary, so it has no decompiled code).

## 1. Pipeline: Queue → Worker → separate process → libhb

**Observed** (REA Hopper pseudocode on the UI binary):

- `-[HBQueue start]` (0x10003ba6c): if `canEncode` → posts `HBQueueDidStartNotification`,
  `preventSleep`, then `encodeNextQueueItem`. Evidence `ev_6cf7047a…`.
- `-[HBQueueWorker initWithXPCServiceName:]` (0x100049504): each worker owns an `HBRemoteCore`
  bound to its own **XPC service** and observes its `state` (KVO). Evidence `ev_b315cf18…`.
- `-[HBQueueWorker realEncodeItem:]` (0x10004a2f0): reads `HBUseHardwareDecoder` /
  `HBAlwaysUseHardwareDecoder` → `job.hwDecodeUsage` (0/1/2), then
  `[core encodeJob:job progressHandler:… completionHandler:…]`. Evidence `ev_8d2006cc…`.
- Strings (Evidence `ev_b5fcee5d…`): `fr.handbrake.HandBrakeXPCService` … `Service4`,
  `values.HBQueueWorkerCounts`, `setUpForMultipleWorkers`, `firstAvailableWorker`,
  and progress notification keys (`…PercentKey`, `…HoursKey/MinutesKey/SecondsKey`).
- The bundle ships `Contents/XPCServices/HandBrakeXPCService{,2,3,4}.xpc`.

**Inference:** batch = a persisted queue. A setting (`HBQueueWorkerCounts`) picks 1 to 4
workers. Each job is encoded in its own XPC process, so an encoder crash does not take the app
down, and up to 4 files run in parallel. The default is 1 worker (not verified on this machine).

## 2. Engine: libhb, scan → job → encoder → muxer

**Observed** (exported symbols in HandBrakeKit, `nm -arch arm64`):
`hb_scan`, `hb_preset_job_init`, `hb_job_init_json`, `hb_add_json`, `hb_start`,
`hb_presets_builtin_get_json`, encoder vtables `hb_encvt` (VideoToolbox), `hb_encx265`,
`hb_encx264`, `hb_encsvtav1`, `hb_muxer`; 851 `x265_*` symbols (x265 linked statically).

Apple-hardware path, `encvt_init / encvt_work / encvt_close`, plus `hb_vt_init_session`,
`hb_vt_is_constant_quality_available`, `hb_vt_is_multipass_available`, `hb_vt_h265_levels`.
VideoToolbox imports actually used:
`VTCompressionSessionCreate`, `VTCompressionSessionEncodeFrame`,
`kVTCompressionPropertyKey_Quality`, `…_AverageBitRate`, `…_DataRateLimits`, `…_ProfileLevel`,
`…_MaxKeyFrameInterval`, `…_AllowFrameReordering`, `…_ExpectedFrameRate`,
`…_PrioritizeEncodingSpeedOverQuality`,
`kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder`.

**Inference:** HandBrake reads the source with FFmpeg (scan), builds a job from a JSON preset,
and encodes each frame with either VideoToolbox (hardware) or x265 (software). On the
VideoToolbox path, "constant quality" means `kVTCompressionPropertyKey_Quality`, not a bitrate.

## 3. "Small file, same quality": the presets

**Observed**: built-in presets are JSON inside HandBrakeKit (`strings`, lines 42301 / 42411 / 39664):

| Preset | VideoEncoder | QualityType | Slider | Speed | Container / audio |
|---|---|---|---|---|---|
| H.265 Apple VideoToolbox 1080p | `vt_h265_10bit` | 2 (constant quality) | **60** (0–100) | `speed` | MP4, AAC 160 kbps stereo, max 1920×1080, VFR |
| H.265 Apple VideoToolbox 2160p 4K | `vt_h265_10bit` | 2 | **55** | `speed` | MP4 |
| H.265 MKV 1080p30 | `x265_10bit` | 2 | **RF 22** (lower is better) | `slow` | MKV |

The UI also lists `H.264 (VideoToolbox)`, `H.265 (VideoToolbox)` and `H.265 10-bit (VideoToolbox)`.

**Inference, the core of the trick:**
1. **Constant quality, not a fixed bitrate.** The encoder spends bits where the scene needs them,
   so static footage shrinks a lot while busy footage keeps its detail.
   `VideoAvgBitrate` (5500 / 17500) applies only when the user switches to bitrate mode.
2. **HEVC 10-bit:** about 40–50% smaller than H.264 at similar quality, and it keeps HDR and
   gradients without banding.
3. **Hardware (VideoToolbox) for speed; x265 `slow` for the smallest files**, at several times
   slower.
4. **Limit resolution to the preset** (1080p / 4K) and use VFR, so it never upscales or adds frames.
5. **Audio re-encoded to AAC 160 kbps** (small against the video).

## 4. Settled by HandBrake's public source (tag `1.11.2`, `libhb/platform/macosx/encvt.c`)

HandBrake is open source (<https://github.com/HandBrake/HandBrake>), so the encoder questions
were answered by reading the source rather than by decompiling. Source of the same version as
the binary above:

- `encvt.c:634-636`: `settings.quality = job->vquality / 100` → **slider 60 = `Quality` 0.60**,
  4K 55 = 0.55. `:1508-1515` sets `kVTCompressionPropertyKey_Quality` when quality > -1;
  otherwise it uses bitrate.
- `encvt.c:484-486`: `VideoPreset = "speed"` → `prioritizeEncodingSpeedOverQuality = true`;
  `:1292-1295` applies it only when the encoder supports it.
- `encvt.c:1265-1272`: `kVTCompressionPropertyKey_RealTime = false` for offline encoding, so
  VideoToolbox runs at full speed instead of the frame rate.
- Still open: the default of `HBQueueWorkerCounts` (in the macOS UI's source, not checked).

**Note:** the binary is GPL; ShotDex reads it to understand behaviour only and copies no code.

## 5. What ShotDex takes, and what it does not

- **No code taken from HandBrake.** HandBrake is GPL-2; linking libhb/FFmpeg/x265 into
  ShotDex (App Store) is not compatible. Only the idea is reused (constant quality, HEVC
  10-bit, size cap, batch queue).
- iOS/iPadOS/macOS already have hardware HEVC encoding through VideoToolbox / AVAssetWriter
  (`AVVideoQualityKey` / `kVTCompressionPropertyKey_Quality`). ShotDex already has
  `ShotDex/Data/Sources/VideoExportWriter.swift` (AVAssetReader → AVAssetWriter, HEVC Main).
  **But** it forces SDR Rec.709 + 8-bit Main + a fixed bitrate. Compressing iPhone videos
  (HLG / Dolby Vision 10-bit) through it would lose HDR, so the compression feature needs a
  separate encode profile (Main10, carry the source's colour, quality instead of bitrate).
- Batch: no XPC on iOS. Use a sequential queue (1 file at a time, 2 on Mac at most),
  background-task / `BGContinuedProcessingTask` (iOS 26) so the batch keeps running when the
  user leaves the app.
