# Kế hoạch — menu Combine Photos theo việc (FS-01.09)

| Trường | Giá trị |
|---|---|
| Đặc tả | [FS-01.09](../02-functional-spec/FS-01-library/09-photo-stacking.md) · intent [combine-photos-purpose-menu](../_intents/2026-09-23-combine-photos-purpose-menu.md) |
| Ngày | 2026-09-23 |
| Trạng thái | đã duyệt 2026-09-23 — đang làm |

## 1. Hiểu đúng chưa

Menu ⋯ giữ **một** dòng Combine Photos, giờ là menu con ba dòng (Focus Stack · Panorama · Stack Exposures).
Focus Stack là màn một việc; Stack Exposures là màn có bộ chọn `Average · Lighten · Darken` (mặc định Average)
kèm câu giải thích từng mode; menu không còn tên phép toán. Ảnh ra không đổi một pixel. Menu có ở cả bốn lưới. Cancel giữ lựa chọn;
Save thoát chọn và mở ảnh vừa lưu. Panorama chỉ hiện khi FS-14 đã build — plan này **không** build Panorama.

## 2. Đối chiếu AC ↔ code

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 một dòng ở cấp ngoài | ✅ đạt hôm nay | một row `Combine Photos` ở `SelectionBarViews.swift:211-216` | test khoá lại khi đổi sang menu con. **Nhưng** plan FS-14 task 4 sắp thêm `Create Panorama` cạnh nó — đã sửa, §4.2 |
| AC-2 ba dòng đúng thứ tự | ❌ | chỉ có một `Button`, không menu con | menu con dựng từ danh sách việc (`allCases`), không viết tay từng dòng |
| AC-3 < 2 ảnh: mở được, mọi dòng mờ | ❌ lệch cấu trúc | hôm nay cả dòng mờ khi `imageSelectionCount < 2` (`:215`) | cha luôn bật, con `.disabled` |
| AC-4 trùng từng pixel | ❌ chưa có test | renderer không đổi (`PhotoStackRenderer.swift:79`); **không có test nào** cho renderer trong `ShotDexTests` | map việc → mode 1:1 + test so pixel + test giá trị đã biết cho average/lighten/darken |
| AC-5 Stack Exposures mở với N ảnh, bộ chọn ba mode ở Average | ❌ gần có (người dùng đã chốt tài liệu) | `Picker("Mode")` ở `PhotoStackScreen.swift:106` có **bốn** mode, mặc định `.average` ở `:25`; lọc video đã có ở `LibraryScreen.swift:241-250` | việc vào qua presentation; bộ chọn chỉ còn ba mode ở Stack Exposures, không có ở Focus Stack |
| AC-6 câu giải thích từng mode, Focus Stack không bộ chọn | ❌ | tên và câu nằm trong kit `PhotoStackRenderer.swift:23-41` (chuỗi thường, **không** qua String Catalog); câu hiện tại nói phép toán, không theo bảng §2 | chuyển tên + câu sang app qua String Catalog, câu mới theo §2; bỏ `title`/`explanation` khỏi kit (không ai khác dùng) |
| AC-7 iOS 26.5 = 18.6 | ❓ | menu con trong `Menu` của toolbar chưa thử trên 18.6 ở app này | đo bằng ui-drive: iPhone 17 (26.5) và iPad Pro 13 (18.6 — máy 18.6 duy nhất có) |
| AC-8 ba cỡ màn cùng số dòng | ❌ | theo AC-2 | dựng từ `allCases` là đủ; chụp ba máy |
| AC-9 VoiceOver đọc "menu" | ❓ | chưa có dump | dump nhãn a11y sau AC-2 |
| AC-10 Cancel giữ lựa chọn | ❌ lệch | cover gọi `stopSelecting` ở **mọi** lần đóng (`LibraryScreen.swift:161`, `PhotoStackScreen.swift:267`) | tách hai đường: Cancel không làm gì, Save gọi callback |
| AC-11 Save mở viewer | ❌ | Save chỉ `dismiss()` (`PhotoStackScreen.swift:213`); **không** index, **không** báo lưới có ảnh mới — nên `openSavedPhoto` (`LibraryScreen.swift:319`) chưa tìm thấy ảnh | dùng lại mẫu Collage: `indexSingle` → `publishAppCreatedAsset` → mở viewer (`CollageEditorModel.swift:683-690`) |
| AC-12 `Couldn't Save` | ❌ | một cảnh báo chung `Couldn't Combine` cho cả preview lẫn Save (`PhotoStackScreen.swift:53`) | tách theo pha: `Couldn't Load Photos` / `Couldn't Save` |
| AC-13 có ở ba lưới còn lại | ❌ | Album Detail (`AlbumDetailScreen.swift:369-391`), Smart Album (`SmartAlbumDetailScreen.swift:350-372`), On This Day (`OnThisDayScreen.swift:284-301`) không truyền `onCombine` | nối vào cả ba — đường mở viewer theo §4.1 |
| AC-14 album người dùng: thêm vào album + mở tại chỗ | ❌ | chưa có đường nào thêm ảnh mới vào album sau khi lưu; đã có sẵn thao tác thêm ảnh vào album (`PhotoLibraryService.swift:1062`) | dùng lại nguyên; chỉ khi album cho thêm ảnh |
| AC-15 Smart Album / On This Day → Library | ❌ | `AppNavigation.openPhoto(assetId:)` (`AppNavigation.swift:51`) chuyển tab + mở ảnh, đang dùng cho Handoff | dùng lại nguyên |

## 3. Chỗ nào trong code

| File | Đụng gì | Mới / sửa |
|---|---|---|
| `ShotDex/Domain/Editing/CombinePurpose.swift` | ba dòng: thứ tự, tên, icon, có sẵn chưa (Panorama = chưa), các mode của màn (Focus Stack → một; Stack Exposures → Average · Lighten · Darken, mặc định Average), tên + câu giải thích của từng mode | **mới**, thuần, test được |
| `ShotDexKit/Render/PhotoStackRenderer.swift` | bỏ `title`/`explanation` (tên phép toán); renderer giữ nguyên | sửa |
| `ShotDex/App/SelectionBarModel.swift` | `onCombine` nhận một việc | sửa |
| `ShotDex/Features/Library/SelectionBarViews.swift` | `Menu("Combine Photos")` con, dòng từ danh sách việc | sửa |
| `ShotDex/Features/Editing/PhotoStackModel.swift` | tải khung, preview, lưu → index → publish → báo đã lưu; lỗi theo pha | **mới** — logic ra khỏi View (plan FS-14 cũng chỉ ra đây là chỗ Combine làm sai) |
| `ShotDex/Features/Editing/PhotoStackScreen.swift` | nhận việc; bộ chọn chỉ khi việc có > 1 mode; tiêu đề = tên dòng; hai tiêu đề lỗi; `onSaved` | sửa |
| `LibraryScreen` · `AlbumDetailScreen` · `SmartAlbumDetailScreen` · `OnThisDayScreen` | trình bày cover; Cancel giữ chọn; Save → thoát chọn + mở viewer theo §4.1 (album người dùng: thêm ảnh vào album trước) | sửa |
| `Localizable.xcstrings` | 3 tên dòng, 3 tên mode, 4 câu giải thích; bỏ `Combine %lld Photos`, `Couldn't Combine` | sửa |
| `ShotDexTests/CombinePurposeTests.swift` · `PhotoStackRendererTests.swift` | AC-2, AC-4, AC-6 | **mới** |
| `ShotDexUITests/scripts/combine-menu.json` | AC-1…3, 5, 7–11, 13–15 | **mới** |

Tái dùng: lọc ảnh khỏi video (`selectedImageIDs` sẵn ở cả bốn màn), mẫu lưu → index → publish → mở viewer
của Collage, `openSavedPhoto` của Library, `AppNavigation.openPhoto(assetId:)` để mở ảnh từ tab khác.

## 4. Cần người dùng quyết

1. ~~Save từ album mở viewer ở đâu~~ — **chốt 2026-09-23**: album người dùng tạo (thêm được ảnh) → thêm ảnh
   mới vào album rồi mở viewer tại chỗ; Smart Album, On This Day, album không cho thêm → chuyển tab Library
   và mở ảnh (`AppNavigation.openPhoto`). Spec đã thêm AC-14, AC-15; FS-14.01 §6 theo cùng luật.
2. ~~Plan FS-14 lệch spec~~ — **đã sửa 2026-09-23** (`ea9bc7f`): task 4 của FS-14 chỉ còn bật việc Panorama
   trong danh sách việc của plan này.

## 5. Thứ tự task

Mỗi task một commit, build sau mỗi commit, task đụng UI thì chụp màn.

| # | Task | AC | Test kèm theo |
|---|---|---|---|
| 1 | Test renderer: giá trị đã biết cho average/lighten/darken trên ảnh 2×2, focus stack chọn khung nét | AC-4 (khoá hành vi trước khi đụng) | `PhotoStackRendererTests` |
| 2 | `CombinePurpose` + test thứ tự ba dòng, mode của từng màn, mặc định Average, không tên phép toán ở tên dòng, Panorama chưa có | AC-2, AC-4, AC-6 | `CombinePurposeTests` |
| 3 | Menu con ba dòng ở Library, cha luôn bật, con mờ < 2 ảnh | AC-1, AC-2, AC-3 | `combine-menu.json` + dump |
| 4 | Màn nhận việc: Focus Stack không bộ chọn, Stack Exposures bộ chọn ba mode; tiêu đề, câu giải thích theo §2, bỏ tên khỏi kit, String Catalog | AC-5, AC-6 | `CombinePurposeTests` + ảnh 4 màn |
| 5 | `PhotoStackModel`: lỗi theo pha | AC-12 | `PhotoStackModelTests` (lỗi theo pha) + ảnh |
| 6 | Cancel giữ chọn, Save → index → publish → thoát chọn → viewer (Library) | AC-10, AC-11 | `combine-menu.json` + ảnh |
| 7 | Nối ba lưới còn lại; Save từ album người dùng → thêm vào album + mở tại chỗ; Smart Album / On This Day → Library | AC-13, AC-14, AC-15 | `combine-menu.json` ba màn |
| 8 | Đo hai nhánh iOS, ba cỡ màn, VoiceOver | AC-7, AC-8, AC-9 | ui-drive iPhone 17 26.5 · iPad Pro 13 18.6 · Duo 27.1 + `Tools/sim-shot` |
| 9 | Sửa FS-01.06, DESIGN §10.3b + §10.6, cột "Chứng minh bằng" của 15 AC | — | `/spec-sync` |

## 6. Rủi ro và đánh đổi

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| Menu con trong `Menu` của toolbar không mở trên iOS 18.6 hoặc Duo | thấp | task 8 đo sớm; nếu hỏng thì dùng `Section` có tiêu đề thay menu con — báo lại người dùng, không tự đổi |
| Thêm dòng vào ba lưới làm menu ⋯ ở đó dài hơn Library | thấp | chỉ thêm một dòng (menu con), đúng luật "một dòng" |
| Save chưa index thì viewer không thấy ảnh (hôm nay Combine lưu mà không index) | cao nếu quên | task 6 bắt buộc `indexSingle` + `publishAppCreatedAsset` như Collage |
| Bỏ `title`/`explanation` khỏi kit là đổi API public | thấp | chỉ `PhotoStackScreen` dùng; extension không dùng (đã grep) |
| Thêm ảnh vào album là **ghi vào PhotoKit** thay người dùng | trung bình | chỉ thêm vào đúng album đang mở, chỉ khi album cho thêm; `photokit-guard` rà ở Deploy |
| Hai phiên cùng checkout — phiên FS-14 (`shotdex-ios-1`) đang build panorama | trung bình | phân vùng đã thống nhất 2026-09-23: phiên kia giữ `ShotDexKit/Render/Panorama/**`, `AppDatabase`/`MetadataStore`/`LibraryQueries`, `MetadataComposer`/`IndexPipeline`/`ExifReader`, `PhotoMetadata`/`PhotoMediaSubtype`, `AlbumsModel`, `PanoramaMerge*`; plan này giữ menu ⋯, `SelectionBar*`, `PhotoStackScreen`, `CombinePurpose`. Việc **Panorama** ở đây chỉ là **chỗ chờ** (chưa hiện, gọi một điểm nối để trống kèm TODO) — **không** dựng màn panorama; phiên FS-14 tự nối. Commit theo đường dẫn cụ thể, không `git add -A` |

**Ngoài bảng AC** (ghi vào `REVIEW_QUEUE.md`, không làm ở đây): ảnh stack không được ghi vào nhóm
Creations như Collage (`recordCreation`, `CollageEditorModel.swift:687`); ba việc không căn khung (Remove Moving
People, Light Trails, Reduce Noise) nên chụp tay sẽ nhoè.

## 7. Phản biện (điền sau khi chạy `challenger`)

| Phản đối | Trả lời / thay đổi |
|---|---|
| … | … |

## 8. Cách chứng minh là xong

- Test: `PhotoStackRendererTests`, `CombinePurposeTests`, `PhotoStackModelTests` — `/test` xanh.
- Màn hình phải chụp: menu ⋯ + menu con (đủ và < 2 ảnh), bốn màn việc, cảnh báo `Couldn't Save`, viewer sau
  Save — iPhone 17 (26.5), iPad Pro 13 (18.6), Duo trong (27.1); Album Detail theo §4.1.
- Agent ở Deploy: `photokit-guard` (thêm ảnh vào album), `ios26-parity` (menu con hai nhánh), `copy-consistency` (năm tên + câu), `a11y-voiceover`
  (AC-9), `device-layout` (Duo).
- Tài liệu: FS-01.06, DESIGN §10.3b + §10.6, cột chứng minh của FS-01.09; plan FS-14 theo §4.2.
