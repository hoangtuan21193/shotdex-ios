# FS-18 — Tài liệu khác phải sửa theo

Thuộc [FS-18](README.md). Gom mọi chỗ ngoài FS-18/19/20/01.08c mà các quyết định ngày 2026-10-04
(`.planboard/macos-app/SPEC-DECISIONS.md`) làm sai. Phần riêng iPad ở [FS-21 §3](../FS-21-ipad-mac-style/03-spec-deltas.md).
`/plan` sửa từng dòng dưới đây trong cùng lượt với code của nó; file đang có thay đổi dở của phiên khác thì
chờ phiên đó commit.

## 1. Thiết kế

| Tài liệu | Sửa |
|---|---|
| DESIGN.md (mục Mac mới) | token Mac: bo 18/10/14, nút 28, nền menu/sheet/scrim/hàng xen kẽ, accent đậm, vùng bấm ≥ 20×16 — viết **trước** `/plan` |
| DESIGN.md §2, §9 | Compare không còn tầng D; trạng thái phá huỷ của thẻ Duplicates (viền đỏ 3pt, `Delete → Keep`) đổi theo cờ thật |
| DESIGN.md §10.2 | đầu nhóm ngày là ngoại lệ màn rộng (Mac, iPad, Duo trong) |
| DESIGN.md §10.3 | bàn phím iPad theo bảng phím Mac (⇧⌘C/⇧⌘V, `\`, ⌃⌘S, Z) |
| NF-05 §1 | Mac được có cách thao tác riêng (menu, phím, cửa sổ, Activity, kéo thả); **tính năng** Mac có thì iPhone/iPad cũng có |
| NF-05 §1 | ngoại lệ có chủ ý: Find Common Photos ([FS-19.08](../FS-19-photo-sources/08-common-photos.md)) chỉ có trên Mac (người dùng 2026-11-02) |
| NF-06 §1 | ngoại lệ Mac: vùng bấm ≥ 20×16 theo chuẩn con trỏ |
| NF-02 | một cache chung có trần (2/5/10/25/50 GB; Mac 25, iOS 5), ở Application Support, loại khỏi backup |
| NF-03 §2b | sidecar ghi lên server của người dùng |

## 2. Dữ liệu (cần `data-migration` duyệt trước `/plan`)

| Tài liệu | Sửa |
|---|---|
| BD-02 | id ảnh: ảnh Photos giữ id hệ thống, ảnh file/NAS nhận UUID — bảng vệ tinh **không** đổi khoá; bảng Ảnh, Bản sao (id bền, duy nhất theo nguồn + đường dẫn chuẩn hoá, không xoá dây chuyền), Nguồn; metadata một dòng mỗi ảnh từ bản sao chính ([FS-19.05](../FS-19-photo-sources/05-data.md)) |
| BD-02 | bảng **Recipe** mới (id ảnh · recipe · lúc đổi) |
| BD-02 | bảng **Bí danh** id thua → id thắng; luật gộp từng bảng (một giá trị: đổi sau cùng thắng; tập hợp: hợp lại) và luật tách |
| BD-02 | bảng **Hash** riêng (thuật toán + phiên bản, hash nhanh có chỉ mục thường, hash đầy đủ duy nhất theo thuật toán) |
| BD-02 | Duplicates khoá lại theo (độ chặt, nguồn, id ảnh); trạng thái lượt quét trùng tách theo nguồn |
| BD-02 | Dấu ảnh (sao, favorite, title, caption, keyword) · Cờ dùng chung · dấu chờ sidecar · ẩn theo bản sao · album ShotDex · lịch sử nhập thẻ; dọn mồ côi 30 ngày trừ lịch sử upload/tải về/nhập thẻ; lượt dọn neo vào bảng Ảnh |
| BD-02 §3 | gỡ các khối bảng bị chép đôi (Keyword Photos, Caption Photos, Trạng thái lượt đọc gương; đoạn khoá ngoại với `REPLACE`) |
| FS-01.12 AC-9 | ảnh bị xoá: dòng sao/cờ theo luật mồ côi 30 ngày của FS-19.05 §5, không gỡ ngay |
| EX-02 | widget cần bộ nạp ảnh file (thumbnail từ cache chung); id đã gộp đi qua bảng bí danh |
| BD-03 | đường index cho file, server và ảnh Photos: hash nhanh, hash đầy đủ chạy nền, đọc luồng bản gốc Photos rồi bỏ |

## 3. Chức năng — mọi thiết bị

| Tài liệu | Sửa |
|---|---|
| FS-01 `08-compare.md` §1–§7 | ~~Compare là chế độ Viewer (08c)~~ — bỏ 2026-10-24; 08 viết lại: màn A/B của Duplicates |
| FS-01.12 §3/§4/§7 | ghi `.xmp` và đọc rating máy ảnh áp cho ảnh file; bảng cờ dùng chung mọi ảnh |
| FS-01.12b | công tắc **Advance After**; tên lệnh xoá theo đích (Move/Delete/Hide N Rejected…) |
| FS-02.01b §2 | `.` = Favorite; ← → lùi-tiến một khung trên video đang dừng |
| FS-03.04, FS-03.07b | bỏ luật "không chọn không gian màu": popup Original/sRGB/P3/Adobe RGB mọi thiết bị |
| FS-03.06 §2 | bản sao tên `<tên> (edited).jpg`, trùng thêm ` (2)`; nút iOS đổi thành **Save as Copy** |
| FS-03.07b §5, 07c | một bộ token tên chung với nhập thẻ: Original Name · Original Number · Date · Time · Camera · Lens · Sequence · Text (Number → Sequence) **đã áp 2026-10-18** (FS-20 task 1) |
| FS-03.09b | ô Sync theo nhóm khi Paste Settings |
| FS-03.13a | Mac tự Done khi rời ảnh Photos, không hỏi bỏ thay đổi |
| FS-03.14b | lệnh Import Lightroom Edits |
| FS-06.01 | mục Hidden (ảnh ShotDex ẩn); album ShotDex cạnh album Photos; New Album theo nguồn |
| FS-06.06b | Move N…, danh sách tick từng bản sao, hộp đỏ xoá hẳn; Merge file chỉ rating/cờ/keyword |
| FS-07, FS-07.01 §2 | popup Source; placeholder cloud không tính; ảnh đếm một lần theo id; trục Giờ trong ngày, Thứ trong tuần |
| FS-08 README, 02 | "Photo Library" → **Sources**; pane cache chung; bỏ pane Server Thumbnails |
| FS-09 | thư viện trống có 3 cách thêm nguồn trên mọi thiết bị |
| FS-10 | một dòng ngoại lệ trỏ sang FS-20 |
| FS-12.17b §3 | phím A/B/T/N (Select Tool, Blade Tool, Add Text, Snapping) |
| FS-15, FS-17 (README, 01, 06, AC) | server là nguồn được index mọi thiết bị; Import to Library → Save to Photos; FS-17.06 thay thế |

## 4. Quy trình và công cụ

| Tài liệu | Sửa |
|---|---|
| CLAUDE.md, docs/PROCESS.md | luật build/chạy/chụp màn cho Mac (macOS 26 + macOS 15) |
| `Tools/gate` | build app Mac + chạy unit test Mac |
| `Tools/ui-drive` | chế độ Mac (driver JSON) |

## 5. Board phải vẽ hoặc sửa trước `/plan`

| Canvas | Board |
|---|---|
| Mac | ~~`MAC_Compare(Survey)`~~ (xoá 2026-10-24); `MAC_Duplicates` nhóm Exact chỉ hiện đường dẫn; `MAC_SettingsSources` bỏ Backup Source; `MAC_Cull` dời nút Move N Rejected…; `MAC_GetInfo` nhiều ảnh; ◀ trên `MAC_Collage`/`MAC_Compress`/`MAC_Merge`; `MAC_MenuBar` dòng Image |
| iPad | xem FS-21 §3 phần board; thêm Ingest dọc |
| iPhone | `PH_` nguồn thư mục, server, Hidden, hộp xoá hẳn, `PH_Ingest`; ⋯ thêm lệnh; Settings Sources; Viewer sáng |
| Duo | như iPhone cho `DI_`/`DC_`, gồm `DI_Ingest`, `DC_Ingest` |
