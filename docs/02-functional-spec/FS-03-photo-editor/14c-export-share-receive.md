# FS-03.14c — Xuất, chia sẻ, nhận look và menu giữ lâu

`FS-03.14c` · `ShotDex/Domain/Editing/LookPresetStore.swift` · `ShotDex/Info.plist` · extension "Add to ShotDex"
(target mới) · `ShotDexTests/LookFileCodecTests.swift` · cập nhật 2026-09-28

**Một câu:** mỗi look rời máy thành một file, về máy khác bằng một chạm, và mọi ô Presets / My Looks / LUTs
đổi tên, chia sẻ, xuất, xoá được bằng một lần giữ lâu. Tổng quan: [FS-03.14](14-lightroom-preset-exchange.md).

## 1. Export As

Menu giữ lâu của một ô → **Export As ▸** ba định dạng; file đi ra qua share sheet của hệ thống (Save to
Files, AirDrop…). Tên file = tên look, bỏ ký tự cấm trong tên file.

| Định dạng | Nhãn trong menu | Mang gì | Độ trung thực |
|---|---|---|---|
| `.shotdexlook` | ShotDex Look | JSON UTF-8: định danh định dạng, **schema version 1**, tên, nguồn, ngày tạo, toàn bộ lát cắt look, tập thông số đã đặt (look nhập — 14b §1), bảng LUT nhúng | **100%** — nhập lại ra recipe bằng nhau từng trường |
| `.xmp` | **Export XMP Preset** | thẻ `crs:` theo chiều ngược của [14b §2](14b-lightroom-mapping.md#2-bảng-thẻ); Lens Correction bật → `LensProfileEnable`=1 + `LensProfileSetup`="Auto" | gần đúng |
| `.cube` | LUT | LUT 33³ trong sRGB nướng từ **phép theo từng pixel** (tone, curve, màu, film look, LUT) | chỉ phần màu |

- Look dùng một **LUT đã nhập** → `.shotdexlook` nhúng bảng `.cube` của LUT đó (33³ ~1 MB văn bản).
  Máy nhận thêm LUT vào My LUTs; look trỏ tới bản vừa thêm.
- Trước khi xuất `.xmp` / `.cube`, sheet xuất liệt kê **một dòng** thứ không đi theo: "Film look Velvia,
  Brilliance and Clarity don't carry into a .cube". Không có gì mất thì không có dòng.
- Sheet xuất `.xmp` luôn có hai dòng: "Export presets in XMP format for use with Adobe Lightroom." và
  "ShotDex is not affiliated with or endorsed by Adobe." ([tổng quan §7](14-lightroom-preset-exchange.md#7-tên-thương-hiệu)).
- `.cube` không mang phép nhìn điểm lân cận (Clarity, Texture, Dehaze, Sharpen, NR, Grain, Vignette,
  hình học): một LUT không biểu diễn được chúng.

## 2. Share

- **Share…** trên một ô → share sheet với **đúng một** file `Tên.shotdexlook`. Mỗi lần chia sẻ một look;
  không có chọn nhiều, không có file gói.
- File **không mang ảnh nào**: không ảnh xem trước, không thumbnail. Máy nhận tự render ô look từ ảnh của
  chính họ. *Vì* ảnh xem trước là một tấm ảnh riêng rời máy mà người dùng có thể không để ý.

## 3. Menu giữ lâu

- Giữ lâu **bất kỳ ô nào** ở Presets, My Looks hay LUTs → **Rename · Share · Export As · Delete**.
- **Delete không hiện** với preset có sẵn trong app. Delete giữ như hôm nay: một chạm trong menu, không hỏi lại.
- Rename theo luật tên của Save Current (trim, tên trắng bị từ chối), nhưng **không ghi đè**: tên đã có →
  từ chối, "A look named 'Look 2' already exists".
  - Ô tên điền sẵn gợi ý kèm hậu tố **"(2)"** ("Look 2 (2)"; đã có thì "(3)"…) — chốt E8, [DECISIONS](../../../.planboard/plans-deviations/DECISIONS.md).
- Share / Export As một ô LUT xuất look chỉ gồm LUT đó ở 100%; `.shotdexlook` nhúng bảng như §1.
- Không có màn quản lý look, không chọn nhiều, không kéo sắp xếp. Thứ tự: [§6](#6-kho-look).

## 4. Nhận

| Đường | Điều kiện | Kết quả |
|---|---|---|
| AirDrop · chạm file trong Files · Messages/Mail "Open in ShotDex" | ShotDex đang chạy **hoặc tắt hẳn** | iOS mở/khởi động app với file → nhập ngay → **banner ~4 s**, không sheet |
| Messages/Mail → extension **"Add to ShotDex"** | app không mở | file vào hộp thư chờ trong App Group; lần mở app sau → nhập → banner "N looks added" |
| Máy không cài ShotDex | — | hành vi hệ thống: lưu vào Files; file là JSON đọc được, không gây hại |

- Banner **cấp app**, hiện trên mọi màn (Library, editor, Statistics…) — không phải toast Undo 3 s của editor (chốt E9).
  *Vì* file AirDrop thường tới khi đang ở Library — [DECISIONS](../../../.planboard/plans-deviations/DECISIONS.md).
- Banner: "Golden added to My Looks" · **Undo**; có ≈/✕ thì "3 looks added · 1 skipped" + **Details** mở đúng
  sheet báo cáo của [14a §3](14a-import-and-report.md#3-báo-cáo). Một file ≈/✕: "Golden added with changes" /
  "Golden not added" + Details; không look nào vào: "No looks added · 1 skipped". Đậu **trên** panel/tab bar.
- Chỉ bề mặt trên cùng (màn gốc, trình xem, editor — cái xuất hiện sau cùng) vẽ banner và mở Details.
- **Undo gỡ toàn bộ lần nhận đó** — mọi look và LUT nhúng nó thêm. Banner tắt rồi thì gỡ từng look bằng Delete.
- Khởi động lạnh: nhập chạy **sau** khi kho look đã nạp, banner hiện trên màn đầu tiên; mỗi file nhập **một lần**.

**Extension "Add to ShotDex"** — target riêng, chỉ kích hoạt với file `.shotdexlook`:
- Có App Group với app; extension ảnh "Save to ShotDex" giữ nguyên quyền tối thiểu, không đổi.
- Chỉ **kiểm cỡ + chép byte** vào hộp thư chờ: không phân tích, không render; hiện "Added. Open ShotDex to use it."
- Trần: ≤ **16 MB** mỗi file `.shotdexlook` (14a §2); hộp thư chờ ≤ **50** file / **50 MB**. Vượt thì từ chối, nói lý do.
- Kéo theo: bản khai riêng tư riêng và một mục trong `/release-check`.

## 5. Khai báo loại file

- Loại xuất: `com.hoangtuan.shotdex.look`, đuôi `.shotdexlook`, tuân `public.data` + `public.content` —
  **không** `public.json`, để trình sửa văn bản không nhận mở nó. Một file = một look.
- Loại nhập riêng dưới `com.hoangtuan.shotdex.imported.*`, khớp theo đuôi: `.xmp`, `.lrtemplate`, `.cube`.
  *Vì* không đụng khai báo của app khác. Không khai zip, không khai DNG.
- Mở tài liệu: **chép vào** hộp thư của app, nhập, rồi **xoá** bản chép — thành công hay không. Không mở tại chỗ.
- Đường dẫn file là nhánh mới của cùng lối vào đang nhận đường dẫn widget.

## 6. Kho look

- **Một file JSON trong Application Support** cộng một thư mục ảnh, cùng khuôn kho LUT đã nhập.
- Mỗi look: tên, nguồn (ShotDex / Imported), ngày tạo, mã lượt nhận (cho Undo), file preset gốc nếu có (14b §5),
  và với look nhập: tập thông số preset có ghi (14b §1, chốt E6).
- Thư mục ảnh chứa thumbnail ô look do máy **tự render** — không bao giờ vào file chia sẻ.
- Thứ tự: **mới nhất trước**. Look mới (Save Current, nhập, nhận) vào đầu; Save Current đè cùng tên đưa look
  lên đầu như hôm nay ([FS-03.02 §9](02-film-simulation-and-presets.md#9-my-looks)).
- Không chạm `photo_metadata` ([BD-02](../../01-basic-design/BD-02-database-design.md)); kit và extension không
  đọc kho — extension chỉ ghi vào hộp thư chờ.

## 7. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-c1 | look Classic Chrome 70%, curve 3 điểm, Shadows wheel hue 200 | Export As `.shotdexlook`, xoá look, nhập lại file | recipe nhập lại bằng recipe gốc từng trường | ✅ `LookFileCodecTests.roundTripIsExact` (+ `anImportedLUTTravelsInsideTheFile`) |
| AC-c2 | `.shotdexlook` schema version 2 | nhập | ✕ "Made with a newer ShotDex — update the app to add it"; không thêm look | ✅ `LookFileCodecTests.newerSchemaIsRefusedWithReason` |
| AC-c3 | look Exposure +0.50, Lens Correction bật, film look Velvia | Export XMP Preset | file có `crs:Exposure2012`="+0.50", `LensProfileEnable`="1", `LensProfileSetup`="Auto", không thẻ film look; sheet có dòng "Film look Velvia doesn't carry", câu giải thích và dòng "not affiliated with or endorsed by Adobe" | ✅ `LookExportXMPTests.writesCrsAndDropsFilmLook` (+ `theTableRunsBackwards`) · `looks-context-menu.json` (sheet Export XMP Preset: dòng "Film look Velvia / Vivid doesn't carry into an .xmp", câu giải thích, dòng "not affiliated with or endorsed by Adobe") |
| AC-c4 | look Mono + Clarity +40 | Export As `.cube` rồi áp cube lên ảnh thử | 33³; sai lệch trung bình ≤ **1/255** so với render ShotDex của riêng Mono | ✅ `LookExportCubeTests.bakesColourOnly` (+ `identityLookIsTheIdentityTable`) · `looks-menu-formats.json` (sheet Export LUT) |
| AC-c5 | Presets có preset sẵn "Velvia"; My Looks có "Golden" | giữ lâu từng ô | "Golden": Rename · Share · Export As · Delete; "Velvia": Rename · Share · Export As, không Delete | ✅ `looks-context-menu.json` (giữ lâu Velvia: Rename · Share… · Export As, không Delete; "Golden": thêm Delete) · `LookPresetStoreTests.builtInRenamesOnThePanelOnly` |
| AC-c6 | có "Golden" và "Look 2" | Rename "Golden" thành "look 2" | từ chối kèm thông báo; ô tên gợi ý "look 2 (2)"; hai look giữ nguyên | ✅ `LookPresetStoreTests.renameRefusesATakenName` |
| AC-c7 | ShotDex tắt hẳn; `Golden.shotdexlook` | mở file (AirDrop / `simctl openurl`) | app khởi động, My Looks có "Golden" đúng một lần, banner Undo hiện ≤ 4 s | ✅ `LookInboxTests.coldLaunchFileIsImportedOnce` (+ `leftoverCopyImportsOnNextLaunch`) · tay: app tắt, `xcrun simctl openurl file://…/Harbour.shotdexlook` → app khởi động, `Tools/sim-shot` ở giây ~2 có banner "Harbour added to My Looks · Undo", `looks.json` có "Harbour" một lần, `LookInbox/` và `Documents/Inbox/` rỗng · `receive-details.json` (Details mở sheet báo cáo) |
| AC-c8 | `Teal Look.shotdexlook` nhúng LUT "Teal" | mở file rồi chạm Undo trên banner | My Looks và My LUTs về đúng số trước lần nhận; bản chép trong hộp thư đã xoá | ✅ `LookInboxTests.undoRemovesTheWholeReceive` |
| AC-c9 | 2 file `.shotdexlook` | "Add to ShotDex", rồi mở app | banner "2 looks added"; hộp thư chờ App Group rỗng | ✅ `LookInboxTests.pendingFilesImportOnLaunch` · `add-to-shotdex.json` trên simulator iOS 26.5: Files → chọn 2 file → Share → ô ShotDex (extension) → "Added. Open ShotDex to use it." → mở app → banner "2 looks added · Undo", `PendingLooks/` rỗng · ⚠️ máy thật chưa chạy |
| AC-c10 | extension; 20 file 100 KB và 1 file 40 MB | chọn cả 21 | 20 vào hộp thư, file 40 MB bị từ chối không đọc; bộ nhớ đỉnh extension < **30 MB** | `LookInboxTests.extensionRefusesOversizedFiles` + ⚠️ chưa có (Instruments trên máy) |
| AC-c11 | máy nhận **không cài** ShotDex | AirDrop `Golden.shotdexlook` tới | iOS lưu vào Files, không lỗi; cài ShotDex rồi chạm file → nhập như AC-c7 | ⚠️ chưa có (thủ công, hai máy thật) |
| AC-c12 | ảnh đang mở là một JPEG 24 MP; look "Golden" | Share "Golden" | file chỉ có các trường của §1, không dữ liệu ảnh nào; cỡ file < 10 KB | ✅ `LookFileCodecTests.sharedFileCarriesNoImage` |

**Chưa chứng minh được:** AC-c1…c12 (chưa có code); AC-c5, c7, c9, c10, c11 cần ui-drive, máy thật hoặc thao tác tay.
