# FS-18 — ShotDex trên Mac

`FS-18` · tier A/B/C/D (bảng dưới) · target app macOS mới, view layer riêng · dùng chung `ShotDexKit`, `Domain`, `Data`
· macOS 15+, Apple silicon · test: target unit test + UI test macOS, chưa dựng ([05](05-platform-and-distribution.md) §6)
· cập nhật 2026-10-04

**Một câu:** cùng thư viện, bộ lọc, thống kê và editor của ShotDex, nhưng là một app Mac thật — cửa sổ co giãn,
sidebar nguồn ảnh, toolbar, inspector, menu bar đủ lệnh và phím, chuột phải, kéo thả, nhiều cửa sổ.

Nguồn: [intent](../../_intents/2026-10-04-macos-app.md) · 19 quyết định:
[DECISIONS.md](../../../.planboard/macos-app/DECISIONS.md) · chốt spec:
[SPEC-DECISIONS.md](../../../.planboard/macos-app/SPEC-DECISIONS.md) · luật vẽ: [MAC_STYLE.md](../../design/mac/MAC_STYLE.md)
(v2 + v3 + biểu đồ kiểu C) · canvas Mac: <https://claude.ai/artifact/HEj8sG21jAEWd7Mgvuyxgj>
(bản cục bộ `docs/design/mac/project/`).

## Các phần

| # | Phần | Trả lời |
|---|---|---|
| 01 | [Cửa sổ và điều hướng](01-window-and-navigation.md) | sidebar 228, toolbar, inspector, cỡ tối thiểu và thu gọn, nhiều cửa sổ, toàn màn, lần mở đầu, accent, vùng bấm |
| 01b | [Menu, phím tắt, kéo thả](01b-menus-shortcuts-and-drag.md) | thứ tự menu bar, bản đồ phím chuẩn, tên lệnh xoá Reject, menu chuột phải, kéo thả ra Finder và file lẻ vào |
| 02 | [Thư viện, Viewer, Cull](02-library-viewer-cull.md) | lưới/bảng, đầu nhóm ngày, chọn bằng chuột, search token, popover Filter, Viewer, Cull, Get Info nhiều ảnh |
| 03 | [Editor và xuất](03-editor-and-export.md) | bố cục editor, hai kiểu lưu (D16) và tự Done, sheet Save and Export, Color Space (D17), chỗ và tên file sinh ra |
| 04 | [Các màn còn lại](04-other-screens.md) | Albums, Statistics (D18), cửa sổ Settings, Collage/Resize/Combine, Video Studio, Support |
| 05 | [Nền tảng và phát hành](05-platform-and-distribution.md) | macOS 15+ Apple silicon, sandbox + bookmark, một lần phát hành, chức năng giữa thiết bị, hạ tầng test |
| 06 | [Tiêu chí nghiệm thu](06-acceptance-criteria.md) | AC-1…66 |
| 07 | [Tài liệu khác phải sửa theo](07-spec-deltas.md) | DESIGN, BD, FS liền kề, công cụ, board |

**Không nằm ở đây** (tài liệu riêng, viết song song):

| Việc | Tài liệu |
|---|---|
| Nguồn ảnh (Photos · thư mục · server), định danh bằng hash, sidecar `.xmp`, offline, xoá, đếm một lần | FS-19 |
| Nhập từ thẻ nhớ (File › Import from Card…) | FS-20 |
| Compare là một chế độ của Viewer (Single · 2-Up · Survey, P/X) | FS-01.08c |
| iPad theo cùng canvas | FS-21 |
| Bên trong Video Studio (timeline, inspector, xuất) | [FS-12](../FS-12-video-studio/README.md) |

## Tầng bề mặt trên Mac

| Tầng | Màn |
|---|---|
| A | Settings (cửa sổ riêng), Statistics, Get Info, Support, sheet dựng điều kiện, Activity |
| B | lưới và bảng Library, album, Search, On This Day, Duplicates, **Viewer** (D10: không phải tầng D) |
| C | sidebar kính nổi, capsule toolbar, popover, menu — chrome kính trên nội dung tầng B |
| D | Editor, Cull, Resize, Collage, Combine Photos, Video Studio — luôn tối, kể cả chrome cửa sổ (D10) |

- Compare đi theo Viewer (tầng B, sáng/tối theo hệ thống) — [DESIGN.md](../../../DESIGN.md) §2.

## Board

Mỗi màn cửa sổ chính là board 1440×900; cửa sổ phụ vẽ đúng cỡ thật.

| Nhóm | Board |
|---|---|
| Thư viện | `Main` · `MAC_LibrarySelected` · `MAC_LibraryList` · `MAC_Search` · `MAC_FilterPopover` · `MAC_ContextMenu` · `MAC_EmptyLibrary` |
| Lệnh | `MAC_MenuBar` (1716×1110) |
| Nguồn (FS-19/20) | `MAC_AddSource` · `MAC_SourceIndexing` · `MAC_ServerBrowser` · `MAC_ServerForm` · `MAC_ServerUpload` · `MAC_Ingest` · `MAC_IngestProgress` |
| Xem ảnh | `MAC_Viewer` · `MAC_ViewerFullScreen` · `MAC_Compare` · `MAC_CompareSurvey` · `MAC_GetInfo` (420×640) · `MAC_Cull` |
| Collections | `MAC_Collections` · `MAC_AlbumDetail` · `MAC_SmartAlbumEditor` · `MAC_OnThisDay` · `MAC_Duplicates` · `MAC_Creations` |
| Statistics | `MAC_Statistics` · `MAC_StatisticsCamera` · `MAC_ChartEditor` · `MAC_ChartStyle` |
| Editor | `MAC_Edit` · `MAC_EditPhotos` · `MAC_EditColor` · `MAC_EditCrop` · `MAC_EditMask` · `MAC_EditHeal` · `MAC_EditMarkup` · `MAC_EditPresets` · `MAC_EditBatch` · `MAC_Export` |
| Công cụ tầng D | `MAC_Compress` (Resize) · `MAC_Collage` · `MAC_Merge` (Combine Photos) |
| Video | `MAC_VideoStudio` · `MAC_VideoStudioCompact` (1180×760) · `MAC_VideoClipSelected` · `MAC_VideoText` · `MAC_VideoExport` · `MAC_VideoProjects` |
| Cửa sổ phụ | `MAC_SettingsGeneral` · `MAC_SettingsSources` · `MAC_SettingsEditing` · `MAC_SettingsServers` · `MAC_CameraDatabase` (720×640) · `MAC_Support` (760×600) |

## Quyết định nền

| ID | Chốt | Ở phần |
|---|---|---|
| D1 · D2 | Mac App Store, sandbox · đủ tính năng trong một lần phát hành | 05 |
| D3–D8 | sidecar, hash, server là nguồn, xoá, đếm một lần, nhập thẻ | FS-19 · FS-20 (01b, 03, 04 chỉ trỏ tới) |
| D9 · D14 | Viewer/Editor mở trong cửa sổ chính, cửa sổ riêng là tuỳ chọn · không màn hình thứ hai | 01 · 05 |
| D10 · D11 | tầng D như DESIGN.md · accent luôn amber | bảng trên · 01 §8 |
| D12 · D13 | Cull giữ dải phím (ẩn được, nhớ) · lần mở đầu là trạng thái trống | 02 · 01 §7 |
| D15 | Compare là chế độ của Viewer | FS-01.08c |
| D16 · D17 | ảnh thư mục tự lưu, Done chỉ với ảnh Photos · popup không gian màu khi xuất | 03 |
| D18 · D19 | Statistics: popup Source + biểu đồ giờ/thứ · album không thư mục, không số dưới cover | 04 |

## Board lệch spec (sửa board, không sửa spec)

| Board | Lệch | Đúng là |
|---|---|---|
| `MAC_MenuBar` | File còn **Import from Server… ⇧⌘I**; thiếu **Import from Card…** | bỏ dòng server (D5); thêm dòng thẻ (D8, FS-20) |
| `MAC_Edit`, `MAC_EditPhotos`, `MAC_Export` | nút chữ ghi "Revert" | "Revert to Original…" như menu Edit (một lệnh, một tên) |
| `MAC_Statistics`, `MAC_StatisticsCamera` | "Sony α7 IV", "iPhone 16 Pro", số máy khác bảng của Library | tên theo cơ sở dữ liệu cảm biến ("Sony A7 IV"); một bảng số cho cả canvas |
| `MAC_ContextMenu` | album "Client Proofs" trong Add to Album | album có trong `MAC_Collections` |
| `canvas.json` | tiêu đề `MAC_Export` còn nhắc "Save Edit" | D16 đã bỏ segment đó; board đã đúng |
| `MAC_Cull` | nút **Move 120 Rejected…** nằm trong dải phím ở đáy | nút chữ trên toolbar (02 §7); dải đáy không có lệnh |
| `MAC_MenuBar` | Image ghi "Delete Rejected…" | "Move N Rejected…", tên theo đích (01b §1) |
| `MAC_GetInfo` | chỉ vẽ một ảnh | thêm trạng thái nhiều ảnh với "Mixed" (02 §8) |
| `MAC_Collage`, `MAC_Compress`, `MAC_Merge` | không có ◀ về nơi đã mở | trong cửa sổ chính như Editor, có ◀ (01 §5) |
