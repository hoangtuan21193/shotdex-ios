# FS-21 — iPad theo kiểu app Mac

`FS-21` · tier A/B/C/D · gốc app (`ShotDex/App/`) + nhánh màn rộng của mọi `ShotDex/Features/*` · cập nhật 2026-10-04

**Một câu:** trên iPad, ShotDex là sidebar · nội dung · inspector với toolbar ở trên như bản Mac — không còn thanh
tab nổi, nút tròn kính trên ảnh hay màn đẩy toàn màn — mà vẫn là app cảm ứng: chạm 44pt, chữ 17, nhấn giữ thay chuột phải.

Nguồn: [intent](../../_intents/2026-10-04-ipad-mac-style.md) (accepted 2026-10-04) · brief vẽ
[IPAD_STYLE](../../design/ipad/IPAD_STYLE.md) (số đo ràng buộc) · luật mượn [MAC_STYLE](../../design/mac/MAC_STYLE.md)
v2 + v3 · canvas iPad `docs/design/ipad/project/` (120 board, vẽ lại cả bộ 2026-10-04 — design đi trước code).

## Các phần

| # | Phần | Trả lời |
|---|---|---|
| 01 | [Khung app](01-shell.md) | sidebar thay tab bar, toolbar, inspector, chọn nhiều, menu nhấn giữ, bàn phím, con trỏ |
| 01b | [Cửa sổ, dọc, trước 26, truy cập](01b-windows-and-access.md) | mốc 700 / 1100, số cột, màn dọc, nhánh iOS trước 26, VoiceOver, Dynamic Type, lệnh iPhone thêm qua ⋯ |
| 02 | [Từng màn (1)](02-screens.md) | Library, Search, lọc, Viewer, Editor ngang + dọc, Collections, Statistics |
| 02b | [Từng màn (2)](02b-screens.md) | Settings, Collage/Resize/Combine, lần mở đầu, server, Video Studio |
| 03 | [Sửa vào các FS khác](03-spec-deltas.md) | section nào của FS-01…17, DESIGN.md, NF-05 bị thay — trên iPad và trên mọi thiết bị; board phải vẽ trước `/plan` |
| 04 | [Tiêu chí nghiệm thu](04-acceptance-criteria.md) | 62 AC: AC-1…AC-60 cùng AC-21b, AC-27b |

## 1. Người dùng cần gì

Người chụp mở ShotDex trên iPad 13" và muốn dùng màn 1376pt như trên Mac: thấy nguồn và album bên trái, lọc và
đổi chế độ xem ở trên, đọc EXIF bên phải cạnh lưới — không phải mở một sheet rồi đóng cho mỗi lần nhìn.
Họ vẫn cầm máy bằng tay: mọi thứ chạm được, không gì đòi chuột hay bàn phím.

## 2. Phạm vi

**Có:**
- Mọi màn iPad đang có, ngang 1376×1032 và dọc 1032×1376, iOS 26 và trước 26.
- Split View, Slide Over, Stage Manager: bố cục theo bề rộng cửa sổ ([01b §1](01b-windows-and-access.md)).
- Bàn phím (thanh menu iPadOS 26, phím tắt), trackpad (chuột phải, kéo chọn), kéo-thả lên sidebar.

**Cố ý không có — FS khác viết:**
- Bản Mac — FS-18 (đang viết, chưa có file).
- Nguồn thư mục/ổ ngoài/server, danh tính ảnh theo hash, sidecar `.xmp`, xoá theo nơi chứa —
  [FS-19](../FS-19-photo-sources/README.md). FS-21 chỉ nói chúng **nằm ở đâu** trên màn iPad.
- Nhập từ thẻ nhớ — [FS-20](../FS-20-card-ingest/README.md). Compare là chế độ của Viewer — FS-01.08c.
- Số đo Video Studio iPad (pool 320, inspector 360, đầu track 200, sheet xuất 700) — FS-12.03/03b/16, phiên Video
  Studio sửa. FS-21 chỉ trỏ tới.
- Bố cục iPhone và Duo không đổi. Đổi ở mọi thiết bị (chốt 2026-10-04): tên công cụ Adjust/Crop, Viewer theo sáng/tối,
  Settings › Sources, câu chào mới, lệnh iPad thêm vào ⋯ của iPhone — danh sách ở [03 §4](03-spec-deltas.md).

## 3. Đổi gì so với iPad hôm nay

| Hôm nay | FS-21 |
|---|---|
| Thanh tab nổi Library · Collections · Statistics + tab Search | **sidebar 320** (Library · Sources · Collections · Utilities); Search là ô trên toolbar |
| Nav bar trong suốt, không tiêu đề; gear trái, Filter + Select phải | toolbar: tiêu đề 20 + dòng phụ 13, cụm viên kính 44, Select là nút chữ cuối phải |
| Chọn nhiều: thanh đáy Share · đếm · Delete | lệnh lên toolbar; inspector tóm tắt lựa chọn |
| Photo Info: cột 360 trong Viewer, nền tối | inspector 360 ở Library, Viewer, Places, Collage, Resize, Export… |
| Viewer: pager toàn màn, nút X 52 | Viewer trong cửa sổ, Back, Single · 2-Up · Survey, filmstrip 100 |
| Editor: cột 280, băng đĩa nổi, dải 6 công cụ ở chân cột | toolbar Adjust · Crop · Mask · Heal · Markup, inspector 360, Presets ở sidebar, filmstrip |
| Collage/Resize/Collage Export: cột 320/400, nút chính ghim đáy | inspector 360, nút chính trên toolbar |
| Settings: split view, mục Photo Library | split view sidebar 320, mục **Sources** (mọi thiết bị), tint hệ thống |
| Lần mở đầu: onboarding → hộp quyền Photos | onboarding → thư viện trống có 3 cách thêm nguồn |

## 4. Board

| Nhóm | Board |
|---|---|
| Khung | `Main`, `IP_LibrarySelect`, `IP_LibraryList`, `IP_MenuBar`, `IP_Share` |
| Nguồn | `IP_AddSource`, `IP_SourceIndexing`, `IP_Ingest`, `IP_EmptyLibrary`, `IP_Onboarding` |
| Tìm, xem | `IP_Search`, `IP_AdvancedSearch`, `IP_Viewer`, `IP_Metadata`, `IP_Compare`, `IP_CompareSurvey`, `IP_VideoTrim` |
| Collections | `IP_Collections`, `IP_AlbumDetail`, `IP_SmartAlbum`, `IP_SmartAlbumEditor`, `IP_OnThisDay`, `IP_Places`, `IP_Trips`, `IP_Duplicates`, `IP_Creations`, `IP_VideoProjects`, `IP_VideoProjectsDelete` |
| Thống kê | `IP_Statistics`, `IP_ChartEditor`, `IP_DateRange` |
| Settings | `IP_Settings`, `IP_WidgetSettings`, `IP_CompressionPresets`, `IP_CameraDatabase`, `IP_Support`, `IP_SupportThread`, `IP_ServerList`, `IP_ServerForm` |
| Server | `IP_ServerBrowser`, `IP_ServerUpload`, `IP_UploadedToServer` |
| Tầng D | `IP_Collage`, `IP_CollageExport`, `IP_Compress`, `IP_FocusStack`, `IP_StackExposures`, `IP_Panorama` |
| Editor ngang | `IP1_Edit` … `IP24_FileName` (24 board) |
| Editor dọc | `IPP1_Edit` … `IPP20_FileName` (20 board) |
| Video Studio | `IL*`, `F*_IL_*`, `F*_IP_*`, `MP_*`, `ES_IL_*`, `IP1_Main`, `IP2_ClipSelected`, `IP3_TextOverlay`, `IP_Export` — số ở FS-12 |

Render: `Tools/design-board render docs/design/ipad/project/<Board>.dc.html -o build/design/render-fs21` (`--dark`
cho bản tối). Board đã thay tại chỗ, cùng tên file — spec cũ trích board vẫn tìm thấy.

## 5. Ràng buộc

| Mặt | Ràng buộc |
|---|---|
| Thiết bị | iPad 13" 1376×1032 / 1032×1376 · iPad 11" 1210×834 / 834×1210 · Split View · Stage Manager; mốc < 700 · 700–1099 · ≥ 1100 ([01b §1](01b-windows-and-access.md), [NF-05](../../04-non-functional-design/NF-05-device-and-os-compatibility.md)) |
| iOS 26 vs trước | cùng một tập lệnh ở hai nhánh; trước 26 dùng sidebar/toolbar hệ thống iPadOS 17/18 ([01b §3](01b-windows-and-access.md)) |
| Phone có mọi chức năng iPad | không lệnh nào chỉ có ở iPad, trừ New Window và Activity ([01b §5](01b-windows-and-access.md)) |
| Tầng | Editor, Resize, Collage, Combine Photos, Video Studio luôn tối (tầng D); Viewer và Compare theo sáng/tối ở mọi thiết bị |
| Accent | amber ở mọi màn trừ Settings (tint hệ thống, [FS-08.01b](../FS-08-settings/01b-rows-and-root.md) AC-9) |
| Truy cập | vùng chạm ≥ 44×44 kể cả khi glyph vẽ nhỏ hơn; chữ theo Dynamic Type ([NF-06](../../04-non-functional-design/NF-06-accessibility-and-localization.md)) |
| Dữ liệu | không đổi gì đã lưu; vị trí sidebar/inspector là trạng thái cửa sổ ([FS-01.07](../FS-01-library/07-state-restoration.md)) |

## 6. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| iPad trước 26 không có kính: sidebar nổi trông khác hẳn | dùng sidebar/toolbar hệ thống của bản đó, không giả kính ([01b §3](01b-windows-and-access.md)); AC-27b |
| `Tools/ui-drive` không có bước phím, kéo-thả, Split View | AC liên quan ghi `⚠️ chưa có`, kiểm tay + test thuần cho hàm chọn bố cục |
| Board đi trước code ở 120 board — lệch tích tụ | `design-parity` từng board trước khi đóng AC; board còn thiếu liệt kê ở [03 §5](03-spec-deltas.md) |
| Hai bố cục (sidebar và tab) phải giữ đủ lệnh | mọi danh sách lệnh dựng từ một nguồn, AC-38 so dump hai bên |
