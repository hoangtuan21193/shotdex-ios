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
| T0 | xong | (commit này) | 13 board: dòng rule *Original is iCloud Only* cuối editor (+ câu *Photos not checked yet aren't counted.*), tweak `original` off/checking/checked ở SmartAlbum (dòng *Checking originals · …* ngay dưới dòng On Server, có glyph iPhone-check; chip cuối, theo thứ tự rule), mục *Original on This iPhone* sau Favorites (PH_LibraryMore, DI_MoreMenus), Mac popover dòng *Storage*, Mac editor tweak `menu=field`. Canvas: iPhone v179, iPad v92, Duo v152, Mac v108. Review design + UX: bỏ chip *Source is Photos Library* (ngược điều kiện NAS), thống nhất chỗ dòng tiến độ và thứ tự chip, glyph menu khác Keep. Chưa vẽ: menu Filter iPad (không board nào vẽ), dòng tiến độ dưới thanh chip Library khi bật bộ lọc (để T9); Duo cover editor: dòng Original nằm dưới mép sheet. Commit kèm đổi icon Utilities chưa commit của phiên khác trong các board này (người dùng 2026-11-04) |
| T1 | chưa | | harness DEBUG đo (a) probe offline mọi resource và (b) KVC; **số đo cần iPhone thật của người dùng** — harness làm trong loop, đo thì chờ người dùng |
| T2 | xong | (cùng commit T5) | `SmartAlbumOperatorTests` — cần `.original` nên đi chung T5 |
| T3 | xong | (commit này) | `OriginalPresence` (onDevice/iCloudOnly) + `Resource` + `required(among:)` (bỏ `other`, khử trùng) + `judge` (một iCloud là đủ; unknown → chưa kiểm). Review test-coverage: thêm ca thứ tự; ánh xạ `PHAssetResourceType` → `Resource` chưa có (T6) |
| T4 | xong | (commit này) | v58 `original_presence` (photoKitId PK, state NULL = chưa kiểm, checkedAt + index) + `original_presence_pass` (1 dòng). Store: `nextBatch` 3 query hẹp (đánh dấu kiểm lại → chưa có dòng → cũ nhất; chỉ ảnh lưới thấy), `record` 1 transaction, `markForRecheck`, `progress`. `deleteAssets` xoá dòng. Review data-migration + test-coverage: tách nextBatch (khỏi sort cả thư viện mỗi lô), prune, test file DB mở lại, ẩn/đã xoá/NAS, biên `checkedAt == since`. Clear Index giữ bảng (như subject_scan). Lưu ý: DEBUG xoá DB sim khi thêm v58 |
| T5 | xong | (commit này) | `RuleField.original` (.choice → is/is not), nhãn theo máy (On This iPhone/iPad/Mac, iCloud Only), SQL `originalClause` khớp dương (`state = ?`, is not = giá trị kia) nên chưa kiểm không vào bên nào; chip compact *Original on This iPhone* / *Original in iCloud Only*. Gồm T2 (test lặp mọi trường, switch exhaustive). Review: test any-mode, giá trị/phép lạ bị bỏ, raw value ghim. `migrating` dời sang T9 (FilterCriteria chưa có mục). Chưa: test qua đường Statistics |
| T6 | xong | (commit này) | `OriginalPresenceProbe` (cách (a): mọi resource bắt buộc, mạng tắt, dừng ở chunk đầu, 4 song song, timeout 10 s, huỷ theo task; chỉ 3164 = iCloud, lỗi khác/rỗng = không biết) + `OriginalPresenceCheck` (@MainActor, lô 200, `offMain` mang theo huỷ, nhường khi người dùng thao tác, chờ máy nguội, token task, đọc lại `since` mỗi lô, `screenOpened` + luật 24 giờ, `assetsChanged`). Review photokit-guard + swift-concurrency: 2 lỗi chặn (huỷ không tới việc, vào nền/ra lại làm chết lượt) + race huỷ request (đọc cả video) + lượt mới bị đóng sớm — đã sửa, thêm 3 test. Chưa nối vào app (T7). Còn: liệu chunk đầu có thể là bản xem trước — chờ T1 (c) |
| T7 | chưa | | kích hoạt + luật 24 giờ + `changedObjects` (AC-8) |
| T8 | chưa | | dòng tiến độ iOS + Mac |
| T9 | chưa | | menu Filter iOS (AC-11) |
| T10 | chưa | | Mac: lượt kiểm, trường, dòng tiến độ (AC-12) |
| T11 | chưa | | Mac popover Filter and Sort (FS-18 AC-35) |
| T12 | chưa | | `design-parity` + `/verify FS-06.10` |
