# Intent: Duplicates — keep what the deleted copies carried, and decide faster

| Trường | Giá trị |
|---|---|
| Tác giả | Claude (from the user's request, 2026-11-15) |
| Ngày | 2026-11-15 |
| Trạng thái | accepted (user, 2026-11-15 — every proposed default in Open questions accepted) |
| Tiến độ | **gần xong** (2026-11-16) — mọi task đã commit; /verify: 4/10 AC xanh (I10, I12, I14, D10). Còn thiếu: I11 (sim không có nhóm Similar), I13 (Duo trong chưa chụp), I15 (bảng ⌘-giữ), D9/D11 (ghi Photos thật iOS 27), D12 (ảnh banner) |
| Nguồn | so sánh với Immich (self-host, mã nguồn mở) — người dùng chọn 3 ý resolve + 3 ý giao diện |
| Spec sinh ra từ đây | [FS-06.06 §14](../02-functional-spec/FS-06-collections/06-duplicates.md) · [06b §2](../02-functional-spec/FS-06-collections/06b-duplicates-marks-merge-delete.md) |

Companion intent: [`2026-11-15-duplicates-immich-detection.md`](2026-11-15-duplicates-immich-detection.md) (how groups are found).

## Problem — vấn đề

1. **Deleting a copy loses what the user typed on it.** On delete, the keeper inherits albums,
   favorite, location (only if it has none) and the earlier date for Exact
   (`Domain/Duplicates/DuplicateInheritance.swift:24-51`). It does **not** inherit the rating
   (`pending_photo_rating`), keywords (`photo_keyword`, `photo_user_keyword`), captions
   (`photo_caption`) or hidden state. A photographer who rated the JPEG 5★ and keeps the RAW loses
   the rating silently.
2. **Two equally good copies are split by file size alone.** Keeper order is quality → edited →
   favorite → larger file → more pixels (`DuplicateReview.swift:69-111`). A copy stripped of EXIF by
   a messenger can win over the original on a size tie.
3. **Similar groups must be done one by one.** Quick clean covers Exact only
   (`DuplicateProtection.swift:88-89`); a library with hundreds of Similar groups where the suggested
   keeper is right takes hundreds of taps.
4. **Hard to see why two photos differ.** The card shows at most two caption lines
   (`DuplicateReview.swift:163-177`); Compare shows the photos, not the facts. The user cannot see at
   a glance that one copy has location and the other doesn't, or lives in two albums.
5. **Tile state is implicit.** A 44pt mark ring plus a Keep badge (`DuplicatesScreen.swift:855`, `:890`)
   — the user has to learn that "no ring" means "kept".
6. **No keyboard on iPad/Mac.** Every decision is a tap.

How Immich does it (commit `e5d6eb7`):
- Resolve merges into the single keeper: favorite if any copy is, the most private visibility,
  **max rating**, descriptions joined **line by line without repeats**, location **only if every copy
  agrees**, union of albums and tags (`server/src/services/duplicate.service.ts` `getSyncMergeResult`).
  Only runs when exactly one copy is kept.
- Keeper suggestion: largest file, then **most non-empty EXIF fields** (`server/src/utils/duplicate.ts`).
- "Deduplicate all" applies the suggestion to every group after one confirmation; "Keep all" too
  (`web/src/routes/(user)/utilities/duplicates/…/+page.svelte`).
- Compare lists metadata per copy, **only the fields that differ**, first 5 then "Show N more"
  (`web/src/lib/utils/duplicate-utils.ts:216-285`, `DuplicatesCompareControl.svelte:34-38`).
- Each copy has an explicit **Keep / To trash** toggle; the button reads "Trash N" or "Keep all"
  (`DuplicateAsset.svelte`, `DuplicatesCompareControl.svelte`).
- Shortcuts: A keep all, D trash all, ⇧C resolve, ⇧S stack, ←/→ previous/next group.

## Proposed outcome — kết quả mong muốn

- After a delete, the kept photo carries every rating, keyword, caption, album and favorite the
  deleted copies had; nothing the user typed disappears.
- On a tie, the copy with the fuller photo info is suggested.
- One reviewed action clears every Similar group whose suggestion the user accepts, with the same
  delete review sheet and protection rules as Quick clean.
- In Compare (and the card), the user sees a short list of exactly what differs between copies.
- Every tile says Keep or Trash in words; tapping flips it.
- On iPad and Mac a whole review can be done from the keyboard.

## Affected users and systems — phạm vi ảnh hưởng

- Screens: Duplicates list + decision card, Compare (`CompareSession`), delete review sheet
  (`DuplicatesSelectedSheet`), Quick clean summary (`DuplicatesSummaryView`).
- Devices: iPhone, iPad, Duo inner + cover, Mac. Shortcuts: iPad + Mac (+ Duo with keyboard).
- Code: `Domain/Duplicates` (`DuplicateInheritance`, `DuplicateReview`, `DuplicateProtection`),
  `Features/Duplicates`, stores for rating/keyword/caption.
- Stored data: writes into `photo_keyword`, `photo_user_keyword`, `photo_caption`,
  `pending_photo_rating` for the keeper; PhotoKit change for hidden. No new schema expected.
- Design: boards on all four canvases (iPhone/iPad/Duo/Mac) — card, Compare, sheet; light + dark.

## Constraints — ràng buộc

- PhotoKit cannot restore a deleted photo: inheritance must happen only after the delete succeeds
  (as today) and a failed write must not lose the donor's data silently.
- User-typed data stays out of `photo_metadata` (indexer rewrites those rows).
- Protection rules A2 (favorite/edited/in-album shielded from bulk) stay for the new bulk action.
- `DESIGN.md` tokens and tiers; US English copy ("Color").
- Both `#available(iOS 26)` paths.

## Open questions — câu hỏi còn treo

_Answered 2026-11-15: user accepted every default below._

1. **Hidden state.** Immich keeps the most private one. Default: if any deleted copy was hidden, hide
   the keeper — or leave it? Proposal: **do not change hidden**, show a caption "One copy was hidden"
   instead (hiding a visible photo is surprising). *Who:* user.
2. **Location rule.** Today: keeper takes the first donor's location if it has none. Immich: only if
   all copies agree. Default: keep today's rule (more useful on device, where one copy often lost GPS
   in a messenger). *Who:* user.
3. **Bulk Similar scope.** Default: only groups whose keeper is decided by measured quality or a clear
   rank (not a coin flip), protection A2 applies, review sheet lists them. *Who:* user.
4. **Keep/Trash label vs today's ring.** Default: replace the ring with a pill label "Keep"/"Trash"
   at the tile foot, 44pt hit area kept. Needs a board before deciding. *Who:* user, on the canvas.
5. **Which fields in "What differs".** Default: date, file size, resolution, format (RAW/HEIC/JPEG),
   camera/lens, location, albums, rating, keywords, edited, source app. *Who:* user.
