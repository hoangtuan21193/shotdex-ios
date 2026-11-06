# Also on Server + Keep in Photos loop

Code [plan 2026-11-06-also-on-server-keep-in-photos](2026-11-06-also-on-server-keep-in-photos.md), one task per pass
(user 2026-11-06: "tự plan và tạo loop để code, review 2 lần, chụp ảnh màn hình để test"; "commit và push lên main,
có nhiều session đang code cùng nhau nên phải cẩn thận").

## How a pass runs (read this first every pass — it is the memory)

1. Take the first row below whose status is `todo`. Set it `doing`.
2. Read the plan row + the AC rows it names (07b §5 / FS-06.12 §7) and the board when it is UI.
3. Code it. Logic in Domain/Data, not in views. Tests in `ShotDexTests/`, Swift Testing, in-memory GRDB.
4. Build: `/build` (ShotDex, iPhone 17 by `id=`, see memory `xcodebuild-destination-by-id`); Mac scheme too when a
   shared file or `ShotDexMac/` changed. Fix every error and warning.
5. Test only the classes the task touched: `/test <Class>`. **Never** full suite / `Tools/gate`.
6. UI task: install on the shared sim, screenshot every state the board draws (light + dark), compare to the board PNG
   (`Tools/design-board render` needs the shim in `build/design/shim/support.js`). Fix until it matches.
   Test library has no faces. Run `~/.claude/tools/sim-clean` after a test batch.
7. Update docs in the same commit: the AC's "Chứng minh bằng" cell, the intent's `Tiến độ` line.
8. Commit **only your paths**: `/usr/bin/git add <paths> && /usr/bin/git commit -m … -- <paths>`. Never `add -A`,
   `stash`, `reset --hard`, `checkout -- <file>`. Then `git fetch`; if origin/main moved, `git rebase origin/main`
   only when `git status` shows no changes in your paths (other sessions' dirty files are theirs — if rebase refuses
   because of them, `git pull --rebase` is not allowed: commit stays local, retry next pass). Push `HEAD:main`.
9. Row → `done (<commit>)`. Next pass.

Review rows run agents (two rounds), merge findings into the row, fix each in its own commit.

## Rows

| # | Task | Status | Note |
|---|---|---|---|
| 1 | Model + SQL + display `.alsoOnServer` (AC-251, 252, 254, 255) | done (this commit) | gộp với 2, 3 (code), 4 vì editor phải đổi mới build qua |
| 2 | Normalizer old `Source is <server>` → Also on Server (AC-253) | done (this commit) | `AlsoOnServerMigration` trong `SmartAlbumStore.fetchAllOrdered` |
| 3 | Editor iOS + Mac (AC-246…250, 258) | code done; ảnh còn ở row 11 | |
| 4 | Progress line from Also on Server (AC-256, 259) | code done; test còn | `refreshOnServer` nhận cả `.alsoOnServer` |
| 5 | Migration + `SmartAlbumPhotosAlbumStore` | done (this commit) | `v61-smartAlbumPhotosAlbum` |
| 6 | `PhotosAlbumDiff` + `PhotosAlbumSync` (FS-06.12 AC-2…8, 10, 12, 13, 15, 17) | done (this commit) | 13 test; PhotoKit qua `PhotosAlbumWriting` |
| 7 | UI: switch, status line, delete alert, limited (AC-9, 11) | todo | |
| 8 | Triggers: save, On Server batch, library change, background (AC-4, 14) | todo | |
| 9 | Review round 1: cavecrew-reviewer + photokit-guard + data-migration | todo | |
| 10 | Review round 2: swift-concurrency + ux-reviewer + design-parity | todo | |
| 11 | Screens on every device, light/dark, vs boards (AC-16, 257) + `/verify` both specs | todo | |
