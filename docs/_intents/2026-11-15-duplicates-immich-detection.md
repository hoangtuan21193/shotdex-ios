# Intent: Duplicates — find the copies dHash misses, and find them without a tap

| Trường | Giá trị |
|---|---|
| Tác giả | Claude (from the user's request, 2026-11-15) |
| Ngày | 2026-11-15 |
| Trạng thái | accepted (user, 2026-11-15 — every proposed default in Open questions accepted) |
| Tiến độ | **chưa làm** (2026-11-15) — spec FS-06.06 §14.1–14.3, 10 AC (AC-I1…I9, I16) |
| Nguồn | so sánh với Immich (self-host, mã nguồn mở) — người dùng chọn cả 3 ý phát hiện |
| Spec sinh ra từ đây | [FS-06.06 §14](../02-functional-spec/FS-06-collections/06-duplicates.md) |

Companion intent: [`2026-11-15-duplicates-immich-review.md`](2026-11-15-duplicates-immich-review.md) (resolve rules + UI).

## Problem — vấn đề

Three things a photographer runs into today:

1. **A crop, a recolour or a re-export of the same shot is not found.** Candidates come only from a
   64-bit dHash on a 96pt rendition (`Domain/Duplicates/PerceptualHash.swift:9-117`); look-alikes need
   Hamming ≤ 10, smaller re-saves ≤ 6 (`DuplicateGrouper.swift:140`, `:153`). The Vision feature print
   is computed, but used only to *confirm* dHash hits (`DuplicateVerifier.swift:20-48`) — a pair
   dHash never proposed is never looked at. A crop moves the 9×8 grid; a strong edit (B&W, film look)
   flips many gradient bits. Both slip through.
2. **"Exact copy" is a guess.** It is same hash + same pixel size + same second + size within 1% +
   same filename stem (`DuplicateGrouper.swift:187-206`, `:389-438`). Two byte-identical files with
   different names (`IMG_1234.HEIC` imported from AirDrop as `photo.heic`) are not called exact, and
   Quick clean — which acts on Exact only — skips them. Conversely, nothing proves an "exact" pair is
   actually the same bytes before the user is offered a one-tap delete.
3. **Duplicates are stale until the user remembers to tap Check.** The scan runs only on tap
   (`Features/Duplicates/DuplicatesModel.swift:681-723`); a photo imported this morning does not show
   up in Duplicates until then, and the count on Utilities is wrong in between.

How Immich does it (source read at commit `e5d6eb7`):
- Every asset gets a CLIP embedding; a job per asset asks the vector index for the **64 nearest**
  embeddings of the same type and keeps those within **cosine distance 0.01**
  (`server/src/repositories/duplicate.repository.ts:194-221`, default in `dtos/config.dto.ts:670-673`).
  Groups merge by joining existing `duplicateId`s (`services/duplicate.service.ts` `updateDuplicates`).
- Upload rejects a file whose **SHA-1 checksum** the owner already has (`services/asset-media.service.ts:46-59`,
  unique index `ownerId, checksum` in `schema/tables/asset.table.ts:40`).
- Detection is queued for each new asset once its embedding exists, and tracked per asset with
  `duplicatesDetectedAt` (`repositories/asset-job.repository.ts:197-210`); singleton groups are
  cleaned on read (`duplicate.repository.ts:92-112`).

## Proposed outcome — kết quả mong muốn

- A cropped, recoloured or re-exported version of a photo lands in the same Similar group as its
  original, without pulling unrelated photos of the same scene in.
- "Exact" means the same picture bytes, whatever the file is called; Quick clean acts on those with
  confidence.
- Opening Duplicates after an import shows the new copies already grouped; the Utilities count is
  current. Tapping Check still exists for a full re-run.

## Affected users and systems — phạm vi ảnh hưởng

- Screens: Duplicates (all kinds), Quick clean summary, Utilities card count. Bursts unaffected in
  intent, but share the verifier.
- Devices: iPhone, iPad, Duo (inner + cover), Mac — all run the same scan.
- Code: `Domain/Duplicates` (grouper, verifier), `Data/Sources/DuplicateQualityScanner` +
  `PerceptualHashReader`, `IndexPipeline` hook for the auto-check, `Data/Database/AppDatabase+Duplicates`
  (`duplicate_quality.featurePrint` v63, `duplicate_groups`, `duplicate_scan_state`).
- Stored data: new columns or a table for a content hash and per-asset "checked at"; `duplicate_review`
  (user marks) must survive regrouping.

## Constraints — ràng buộc

- On device only; no server, no CLIP model download, no new SPM dependency (Vision + CryptoKit only).
- 55k-photo library: the candidate search must not be all-pairs over 55k prints; memory bounded.
- Reading originals for a checksum must not download iCloud originals behind the user's back
  (Optimize Storage is on, see memory "Grid thumbnails + Optimize Storage") and must respect the
  existing network-allowed setting.
- Vision feature prints on the **simulator** are one constant vector (probe at
  `DuplicateQualityScanner.swift:83-123`); proof needs a real device or the probe-off path.
- Auto-check runs in the background of the app, must not slow the grid or the indexer's first run.
- No back-compat needed for stored groups (app unreleased), but `duplicate_review` is user data.

## Open questions — câu hỏi còn treo

_Answered 2026-11-15: user accepted every default below. Q1–Q2 of the detection intent are settled by a spike before the spec numbers are fixed._

1. **Distance for "same picture" by feature print.** Immich's 0.01 is for CLIP, not Vision rev 2;
   ShotDex already uses 0.4 to confirm. Default proposal: measure on the fixture set and pick the
   value that keeps crops/edits in and burst neighbours out — spike before spec. *Who:* a spike.
2. **Candidate search without all-pairs.** Default: bucket by capture day ± 1 and camera, brute-force
   inside buckets, plus a cross-bucket pass only for photos with no date. *Who:* spike measures recall
   on fixtures.
3. **Checksum scope.** Default: hash only members of proposed Exact groups (not the whole library),
   only when the original is local or network is allowed; otherwise keep today's heuristic and say
   "Not confirmed". *Who:* user.
4. **Auto-check trigger.** Default: after each index batch finishes, check only new/changed photos
   against the library; full regroup stays on the Check button. *Who:* user.
