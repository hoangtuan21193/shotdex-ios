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
| 7 | UI: switch, status line, delete alert, limited (AC-9, 11) | code done (this commit); ảnh ở row 11 | công tắc ở `closing` của `AdaptiveFormColumns`: cuối cột đơn, dưới Match khi hai cột |
| 8 | Triggers: save, On Server batch, library change, background (AC-4, 14) | done (this commit) | nền chỉ chạy khi có lượt On Server; album không có điều kiện On Server thì chỉ đồng bộ khi app mở — ghi vào FS-06.12 |
| 9 | Review round 1: cavecrew-reviewer + photokit-guard + data-migration | done (this commit) | sửa: pass ghi đè công tắc/link đã xoá (🔴×2), tắt giữa lượt vẫn ghi, query rỗng → cả thư viện, ảnh không resolve/ẩn làm lượt không dừng, request nil báo synced, Limited không nói gì, BG hết giờ không huỷ, lỗi nuốt, không thử lại, chip Mac hiện id, server đã gỡ hiện "Choose Server", editor đè công tắc người dùng vừa bấm, đọc DB trên main khi xoá. Giữ: đổi tên đè (người dùng chọn ghi đè). Ngoài phạm vi → REVIEW_QUEUE (isValid vs clause nil) |
| 10 | Review round 2: swift-concurrency + ux-reviewer (+ design-parity gộp vào row 11) | done (this commit) | sửa: pass thừa khi yêu cầu đến trong lúc chờ gap, log nền sai sau hết giờ, capture không Sendable trong performChanges, link cũ đè link mới trên màn album, lỗi vĩnh viễn thử lại mãi; công tắc kẹt bật khi mất Full Access, dòng không đổi khi bật/tắt, 0 ảnh vẫn hiện hướng dẫn, hộp xoá không nói xoá gì / không hiện khi đã tắt, điều kiện chưa đủ bị bỏ không báo. Không làm (trái quyết định người dùng): nút Open Photos, cảnh báo ghi đè trong chân công tắc; dòng "đang kiểm NAS, album còn lớn" — spec §3 giữ như synced |
| 11 | Screens on every device, light/dark, vs boards (AC-16, 257) + `/verify` both specs | todo | |
