# FS-06.10 loop Bản gốc trên máy — trạng thái

Loop tự chạy (`/loop`, 2026-11-04), làm hết task T0–T12 của [plan](2026-11-04-fs0610-original-on-device.md). File này
là trí nhớ của loop: mỗi vòng đọc nó trước khi làm, ghi lại sau khi làm.

## Luật mỗi vòng

1. Làm **một** task theo bảng dưới, theo thứ tự:
   - task UI: vẽ/sửa board trước (đọc lại canvas trước khi sửa — người dùng có thể đã sửa/comment; publish lên canvas
     của thiết bị; xem `docs/design/README.md`);
   - code;
   - build iOS (`-destination 'id=<udid>' -derivedDataPath build/sim`) và `ShotDexMac`
     (`-destination 'platform=macOS' -derivedDataPath build/mac`); file mới dưới `App/`/`Features/` cần cho Mac →
     `Tools/mac-membership.shared` + `Tools/mac-membership`;
   - chạy test liên quan bằng `-only-testing` (không chạy cả bộ, không `Tools/gate` — người dùng 2026-11-04);
   - **2 lượt review độc lập** (agent khác nhau theo vùng: `photokit-guard`, `data-migration`, `swift-concurrency`,
     `perf-profiler`, `ux-reviewer`, `design-reviewer`, `ios26-parity`, `device-layout`, `hig-components`…), sửa hết
     những gì chúng tìm ra (blocker + nên sửa; việc ngoài plan → `REVIEW_QUEUE.md`);
   - task UI: **chụp ảnh** mọi trạng thái bị đụng (iPhone, iPad, Duo `Tools/sim-shot`, Mac `Tools/mac-shot` sáng + tối),
     nhìn từng ảnh, lỗi thì sửa và chụp lại; so board. Ảnh vào `build/design/shots/FS0610/<task>/`.
2. Cập nhật FS-06.10 (cột "Chứng minh bằng"), bảng dưới (trạng thái, ghi chú) và dòng Tiến độ của intent, rồi commit
   chỉ những file mình đổi (`/usr/bin/git commit -- <paths>`; zsh: danh sách đường dẫn dùng mảng `set -- …; "$@"`).
3. Không đụng file phiên khác đang sửa (thấy `M` mà mình chưa đổi): lúc bắt đầu là `project.pbxproj`,
   `LiquidGlassTabBar.swift`, `Localizable.xcstrings`, `MacSidebar.swift`, các board `docs/design/duo/project/DC_*`.
   Không `git add -A`, `stash`, `checkout --`, `reset --hard`.
4. Không dùng ảnh có mặt người. Hỏi người dùng bằng AskUserQuestion có lựa chọn. Dòng "chờ người dùng" thì bỏ qua,
   làm dòng kế.
5. Migration kế tiếp là **v58** (v57 đã là `commonPhotosLeftOut`). Kiểm lại số trước khi viết.
6. Xong một đợt test trên simulator: `~/.claude/tools/sim-clean`. Không tạo simulator mới.
7. Hết task (T12 xong) thì dừng loop.

## Task

| Task | Trạng thái | Commit | Ghi chú |
|---|---|---|---|
| T0 | chưa | | board: trường Original trong editor (iPhone, iPad, Duo, Mac), dòng tiến độ ở smart album, mục menu Filter |
| T1 | chưa | | harness DEBUG đo (a) probe offline mọi resource và (b) KVC; **số đo cần iPhone thật của người dùng** — harness làm trong loop, đo thì chờ người dùng |
| T2 | chưa | | test phép theo mọi trường (AC-13) |
| T3 | chưa | | Domain `OriginalPresence` (AC-3, AC-4) |
| T4 | chưa | | v58 + `OriginalPresenceStore` (AC-6, AC-7) |
| T5 | chưa | | trường Original + SQL + chip + `migrating` (AC-2, AC-10, AC-13) |
| T6 | chưa | | lượt kiểm nền, cách (a) mặc định theo spec; đổi sang (b) nếu T1 đo > 2 giờ (AC-5, AC-9) |
| T7 | chưa | | kích hoạt + luật 24 giờ + `changedObjects` (AC-8) |
| T8 | chưa | | dòng tiến độ iOS + Mac |
| T9 | chưa | | menu Filter iOS (AC-11) |
| T10 | chưa | | Mac: lượt kiểm, trường, dòng tiến độ (AC-12) |
| T11 | chưa | | Mac popover Filter and Sort (FS-18 AC-35) |
| T12 | chưa | | `design-parity` + `/verify FS-06.10` |
