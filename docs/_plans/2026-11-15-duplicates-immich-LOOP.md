# Loop: code FS-06.06 §14 (Immich ideas), one AC per pass

Started 2026-11-15 by the user: "loop và code đi, luôn review 2 lần, chụp màn hình check ui, click test thử all button".
Spec: `docs/02-functional-spec/FS-06-collections/06-duplicates.md` §14 (+ 06b §2). Boards: committed 1824b41c, all 4 canvases.

## How a pass runs (read this first, every pass)

1. Take the **first row below with status `todo`** (skip `blocked`). Read its spec text and AC rows.
2. **Test first** for Domain/Database work (`ShotDexTests/`, Swift Testing, in-memory GRDB), then code.
3. `/build` — zero errors and zero new warnings (Stop hook checks the whole project).
4. `/test <Class>` for the touched test classes only (never the full suite, never `Tools/gate` — user rule).
5. **Review twice** — two independent passes, fix every real finding, re-build:
   - pass 1: `caveman:cavecrew-reviewer` on the diff (correctness);
   - pass 2: the specialist for the area — UI: `design-parity` against the board; Domain/Data: `test-coverage`;
     PhotoKit writes: `photokit-guard`; concurrency (`Task`, actors): `swift-concurrency`.
6. **UI rows**: install on the shared iPhone 17 sim (`/sim`), drive with `Tools/ui-drive` to every state the row
   touches, screenshot, **tap every button on that screen** (Keep/Trash pill, Review…, Show more, What differs,
   sort, Check Again, Select N, Cancel, Delete → Cancel at the system alert). Never confirm a real delete of
   non-demo photos. iPad / Duo screenshots when the row is iPad/Duo-specific. Look at every screenshot; fix and redo.
7. Update the spec AC row's last column with the proof (test name ✅ / route + screenshot ✅).
8. Commit only the files of this row (`git commit -- <paths>`, never `git add -A` — shared checkout).
9. Fill the row: status `done`, commit hash, one line of what's proven / what isn't.
10. `ScheduleWakeup` with the same /loop prompt. Never `clear_session` (kills the loop).

Stop the loop when every row is `done` or `blocked`; then `/verify FS-06.06` and report.

Rules from memory that bite here: no face photos in tests; no writes to real iCloud photos or the Windows server;
sim photo permission on 26.5 needs reset + one tap; screenshot before every tap (blind taps clone the library);
`xcodebuild` destination by `id=`; new files in `Features/` go through `Tools/mac-membership`.

## Rows (order = dependency, cheapest first)

| # | AC | What | Status | Commit | Note |
|---|---|---|---|---|---|
| 1 | AC-I10 | keeper tiebreak: size within 1% → more photo-info fields; chip *More photo info* | done | bae2725d | 3 reviews: pairwise 1% band was non-transitive → set-based `fileOrder`; info counts photo_metadata only. Chip not seen on sim (demo library has no size-tie group) |
| 2 | AC-D9, D10 | inherit highest rating (iOS 27 Photos / pending queue below 27) | done | 90cd7f8b | 3 reviews: one mixed write, shared-library/gone ids refused + counted on the delete banner. Not run on a sim with a real delete (needs a rated demo group) |
| 3 | AC-D11, D12 | inherit caption lines + keywords (iOS 27), failure alert | done | b0c6ddfc | 2 reviews: keeper caption only appended to, never rewritten; unread/changed-during-dialog keepers skipped + counted; paged reads; recount after banner. Failure is a banner line, not an alert. No real iOS 27 write on sim yet |
| 4 | AC-I13, I14 | `PhotoDifference` (only differing fields, first 5 + Show N more) | done | (this row) | 2 reviews: one basis — rows differ when they read differently (keywords case-folded, date to the second); settings via `MetadataFormatter`; lists via `.list` format; stars clamped |
| 5 | AC-I13 UI | Compare: *What differs · N* button + sheet (iPhone/Duo), table under filmstrip (iPad) | todo | | |
| 6 | AC-I12 | Keep/Trash pill replaces the mark ring; *Suggested* chip | todo | | |
| 7 | AC-I11 | *Suggested picks* band for Similar (scoreGap ≥ 0.2, A2, review sheet) | todo | | |
| 8 | AC-I15 | keyboard: ↑/↓ group focus, K, R, Space, ⌘⌫; Compare ←/→, K, ⌫, Esc | todo | | |
| 9 | AC-I4, I5, I6 | content checksum (SHA-256 stream) for exact candidates | todo | | |
| 10 | AC-I1, I2, I3, I16 | feature-print candidate search in day×camera buckets, T_fp 0.3 | todo | | needs real device for final T_fp |
| 12 | — | follow-up from review: `DuplicateQuality.better` is non-transitive (sharpness 0.9 ratio), keeper on a scored group depends on member order — pre-existing | todo | | anchor the sharpness band on the group max like `fileOrder` |
| 11 | AC-I7, I8, I9 | auto-check new photos after first Check; Low Power / thermal yield | todo | | |
