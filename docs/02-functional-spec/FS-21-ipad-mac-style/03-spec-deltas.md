# FS-21.03 — Section nào của tài liệu khác bị thay

`FS-21.03` · danh sách gộp cho chủ tài liệu và `/plan` · cập nhật 2026-10-04

**Một câu:** mỗi hàng dưới đây là một chỗ phải sửa trong tài liệu khác khi làm FS-21. §1–§3 là phần iPad (khung FS-21,
bề rộng ≥ 700); §4 là phần đổi cho **mọi thiết bị** do các quyết định 2026-10-04; §5 là board phải vẽ trước `/plan`.

Luật gộp: sửa trong cùng lượt với code của AC tương ứng (docs/README.md §5). FS-21 không tự sửa các tài liệu đó.

## 1. Đặc tả chức năng — phần iPad

| Tài liệu § | Hôm nay nói | Trên iPad thay bằng |
|---|---|---|
| FS-01 README · Quy tắc chung | "tab chính của app" | Library là nhóm đầu của sidebar; nội dung theo hàng đang chọn |
| FS-01.01b | 13 cột ở iPad 11" ngang theo mật độ | giữ luật mật độ + pinch; mặc định 7 cột ở 1016pt, 6 ở 656pt ([01b §1](01b-windows-and-access.md)) |
| FS-01.02 §1–§2 | nav bar trong suốt không tiêu đề; gear trái, Filter + Select phải | toolbar có tiêu đề + dòng phụ; gear lên sidebar ([01 §3](01-shell.md)) |
| FS-01.02 §3 | chip tự mang viên kính trên ảnh | thanh điều kiện dưới toolbar, cùng hành vi chip |
| FS-01.03 | tab Search | ô search trên toolbar, token trong ô |
| FS-01.03b §5 + AC-16, AC-20 | iPad: một hàng 6 thẻ Recents 150–200pt | iPad: Recents là hàng trong popover gợi ý 400; bỏ AC-16, AC-20 viết lại theo popover. Duo inner giữ 5 thẻ |
| FS-01.05b §3–§4 + AC-26 | sheet Advanced Search của hệ thống | form sheet 700×640; chạm ngoài khi có nháp vẫn hỏi Discard |
| FS-01.06 §1–§3 | lớp phủ toàn màn, tab bar ẩn, thanh đáy | lệnh trên toolbar, inspector tóm tắt; ⌘/⇧-chạm khi chưa chọn vào chế độ chọn ([01 §5](01-shell.md)) |
| FS-01.07 | "Tab đang mở" là trạng thái cửa sổ | hàng sidebar đang chọn + inspector mở/đóng; giữ khi đổi bố cục qua mốc 700/1100 |
| FS-01.08 | Compare tầng D riêng | ~~trỏ sang FS-01.08c~~ — 08c bỏ 2026-10-24; Compare = màn A/B của Duplicates (FS-01.08) |
| FS-02 README · Chrome | nút X 52 trên-trái, bảng tóm tắt ≤ 520 | toolbar Back … Edit, inspector 360 ([02 §3](02-screens.md)) |
| FS-02.03 §3 · FS-02.03b §1–§2 | cột Photo Info 360, tiêu đề + Done, phím I | inspector không tiêu đề, đóng bằng toolbar; I và ⌥⌘I bật/tắt, ⌘I Get Info sheet |
| FS-02.01b AC-7, AC-10, AC-12 | Esc, ←/→ trên viewer toàn màn | giữ phím, viewer trong cửa sổ, Esc về lưới |
| FS-03.17 §3 · FS-03.17a (cả file) | cột 280, băng đĩa, dải 6 công cụ, phẳng không gập | toolbar + segmented, inspector 360 gập được, Presets ở sidebar |
| FS-03.07 §4 + AC-11, AC-13 | hai pane, cột 400, nút chính ghim đáy | inspector 360, nút chính trên toolbar; dọc giữ cột ([02b §2](02b-screens.md)) |
| FS-06.01 §2–§5 | tab Collections, hero 260, tile 192 | hàng Albums trong sidebar mở trang album; hero 764×150, tile 159 |
| FS-06.06 §7 · FS-06.06b §4 + AC-18 | thẻ xếp gạch ≥ 400, thanh dưới giữa màn | danh sách nhóm 360 + chi tiết; Delete N Photos trên toolbar |
| FS-07.01 §6 · FS-07.03 AC-12, AC-29, AC-30 | 3 cột ở iPad ngang 1344pt | 3 cột 328 ở 1016pt; `+` trên toolbar giữ hai mục |
| FS-08.05 AC-3, AC-12 | detail mở ở "Photo Library"; Done "về tab trước đó" | mở ở Sources; Done về hàng sidebar trước đó |
| FS-09 §2–§3 + AC-2 | Continue mở hộp quyền Photos; Continue ≤ 480 | Continue → thư viện trống 3 thẻ; hộp quyền khi Add Photos Library; Continue 320 |
| FS-11 §3 | inspector 320, tab trên, Export ghim đáy, ô mẫu 66 | inspector 360, Export… trên toolbar, ô mẫu 76; Before and After + ⋯ Discard trên toolbar; khay là panel trái |
| FS-11b §1–§2 + AC-1, AC-4 | hai pane, cột 400, Save/Share ghim đáy | inspector 360; Share… và Save to Photos trên toolbar; dọc giữ cột 360 |
| FS-15 README · 02 §1, 02c | lối vào ⋯ › Upload to; Uploaded to Server trong Utilities | giữ, thêm ⇧⌘U; hàng On Server trong sidebar |
| FS-17 README · 01 §1, §4 (regular) | iPad duyệt server rồi Import to Library | server là nguồn được index (FS-19); không Import to Library, Save to Photos là lệnh xuất |
| FS-12.03 / 03b / 16 | số Video Studio iPad cũ | phiên Video Studio viết — FS-21 không đụng |

## 2. DESIGN.md

| Mục | Hôm nay | Đổi thành |
|---|---|---|
| §2 tầng C | tab bar, selection bar, nút tròn là chrome kính | iPad: sidebar + toolbar của hệ thống; không nút tròn kính trên ảnh; trước 26 dùng sidebar/nav bar hệ thống iPadOS 17/18, không giả kính |
| §6 kích thước | nút chính full width 50; segmented 32; chừa đáy 8 / 100 | iPad: nút 44 bo 12 (kể cả board dọc), segmented 36, segmented cờ 44; không tab bar nên không chừa đáy |
| §6 · §9 | thanh tab kính tự vẽ cho mọi thiết bị trước 26 | iPad không dùng; iPhone giữ |
| §10.1c | lưới theo mật độ, 13 cột iPad ngang | giữ luật mật độ + pinch; thêm khung sidebar/inspector, mặc định 7 / 6 cột |
| §10.1d · §10.1e | tile 192, hero 260 ở regular | khung FS-21: tile 159, hero 764×150 ở 1016pt; iPhone, Duo giữ |
| §10.1f | split view Settings, sidebar 320 | giữ; tint hệ thống; mục 1 tên Sources |
| §10.2 | lưới phẳng, không header ngày; selection bar trượt từ đáy | ngoại lệ màn rộng (iPad ≥ 700, Mac): đầu nhóm ngày; lệnh chọn trên toolbar |
| mới | — | "§10.1g iPad: sidebar · nội dung · inspector" — số của [01 §1](01-shell.md) và ba mốc 700 / 1100 |

## 3. Phi chức năng và nền

| Tài liệu | Đổi gì |
|---|---|
| NF-05 §1 luật 1 | ngoại lệ nền tảng có tên: Open in New Window / New Window, cửa sổ Activity (chỉ iPad, Mac) |
| NF-05 §1 luật 3 · §3 | mốc < 700 bố cục iPhone · 700–1099 sidebar phủ · ≥ 1100 ghim; bỏ "lưới Library 9 cột ở 11" dọc" |
| NF-06 §1 | thêm: hàng sidebar đọc tên + số + trạng thái; vùng chạm 44 cho nút sidebar vẽ 32/28 |
| NF-04 | trạng thái rỗng iPad = thư viện trống 3 thẻ (`IP_EmptyLibrary`) |
| BD-03.04 | iPad: tiến độ index ở chân sidebar; sidebar ẩn → dòng phụ toolbar |
| docs/README.md (đầu file) | "Ba tab … Settings từ gear góc trên trái" — chỉ đúng với iPhone và iPad < 700 |

## 4. Đổi cho mọi thiết bị

| Tài liệu | Đổi gì |
|---|---|
| FS-01.02 (⋯ của Library) | thêm Grid / List (chế độ List như `IP_LibraryList`) và Go to Date… trên iPhone, Duo |
| FS-02.04 (⋯ của Viewer) | thêm Rotate Counterclockwise / Clockwise và Print… |
| FS-01.06 §3 (⋯ của lựa chọn) | thêm Print… |
| FS-06.06 / 06b (⋯ của nhóm Duplicates) | thêm Keep All N Photos |
| FS-07.01b (⋯ của thẻ Statistics) | thêm đổi kiểu biểu đồ (donut/cột, cột/đường) |
| FS-02 README · FS-02.03b §2 | Viewer và Photo Info theo sáng/tối, bỏ "luôn tối" — mọi thiết bị |
| FS-03.13 · 13a · 13b · 17b · 17c | tên công cụ Edit → **Adjust**, Transform → **Crop**; bố cục iPhone, Duo giữ nguyên |
| FS-08.01 §2–§3 · 01b §1 + AC-2, AC-3, AC-5, AC-6, AC-8 · FS-08.02 | mục Photo Library → **Sources** mọi thiết bị; pane không có thẻ Your library |
| FS-09 §2 | câu 4 thẻ chào "Your photos stay where they are" mọi thiết bị |
| FS-17 · FS-15 (iPhone, Duo) | server cũng là nguồn được index trên iPhone, Duo (FS-19) |

## 5. Board phải vẽ hoặc sửa trước `/plan`

| Board | Việc |
|---|---|
| `IPP*` (mọi board dọc có toolbar) | nút toolbar 36 → 44 |
| `IP_Collage` | thêm Before and After, ⋯ Discard, khay ảnh chưa đặt ở panel trái |
| `IPP21_Collage` · `IPP22_CollageExport` · `IPP23_Compress` · `IPP24_FocusStack` | mới, 1032×1376: tầng D dọc có cột inspector 360 (Stack Exposures, Panorama dùng chung bố cục `IPP24`; HDR đã có `IPP13`) |
| `IP_ServerBrowser` · `IP_MenuBar` | bỏ glyph "In Library" và "Import from Server… ⇧⌘I" |
| `IP_Compare` | vẽ lại 2026-10-24 thành màn A/B (cùng `IP_DuplicatesCompare`, thêm Delete N); `IP_CompareSurvey` xoá |
| canvas iPhone, Duo | ⋯ mới ở Library, Viewer, Duplicates, Statistics; tên Adjust/Crop; Settings Sources; Viewer sáng |
