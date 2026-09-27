# Plan — Network shortcuts (FS-17.04)

Ngày: 2026-09-27 · Spec: FS-17.04, AC-31…40 · Trạng thái: **đã duyệt** — người dùng 2026-09-27 "làm shortcut network
theo đề xuất đi" (hướng đã chốt; plan làm liền)

## 1. Đối chiếu AC ↔ code

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-31, 32 | ❌ | `ServerBrowserScreen` ⋯ chưa có mục này | model: `isShortcut`, `toggleShortcut()`; ⋯ + nhấn giữ folder |
| AC-33 | ❌ | `CollectionsSection` 8 case (`CollectionsLayoutStore.swift:5`) | case `.network` + `networkSection()` trong `AlbumsScreen` |
| AC-34 | ❌ | `ServerBrowserHost` nhận session từ `OnServerScreen` | host tự tạo session khi không được đưa; route `ServerShortcutRoute` |
| AC-35 | ❌ | cache thumbnail khoá theo size/modified, không dùng được offline từ Collections | `coverJPEG` trong bảng |
| AC-36, 37 | ❌ | — | store rename/remove; FK cascade |
| AC-38 | ❌ | `ServerFileHistory` đã có luật `ServerHistoryPaths` | thêm cập nhật `server_shortcuts` |
| AC-39 | ✅ gần như | ⋯ kiểu Files đã có | chỉ thêm Remove from Collections |
| AC-40 | ❌ | — | ảnh 3 thiết bị |

## 2. Tái dùng

`AlbumCoverTile` + `AlbumCoverWell` · `ServerBrowserModel` / `ServerBrowserScreen` / `ServerBrowserHost` ·
`ServerHistoryPaths` · `FileServerCatalog` (mẫu catalog quan sát được).

## 3. Task

1. Migration v24 + `ServerShortcut` + `ServerShortcutStore` + catalog trong `AppDependencies` + đường dẫn theo
   rename/delete — AC-31 (store), 35, 36, 37, 38.
2. Browser: Add/Remove from Collections, cập nhật bìa — AC-31, 32, 39.
3. Collections: section Network, ô, nhấn giữ, mở — AC-33, 34, 36.
4. Ảnh + `/verify` — AC-33…40.

## 4. Rủi ro

- Dữ liệu: bảng mới, không đụng bảng cũ; `eraseDatabaseOnSchemaChange` chỉ khi sửa migration cũ — không sửa.
- Layout đã lưu của người dùng: `merged(stored:)` nối section mới vào cuối (sau Utilities) cho ai đã Customize —
  chấp nhận, ghi trong spec? Không: app chưa phát hành, mặc định vẫn đúng vị trí.
- Bộ nhớ: bìa ≤ 40 KB mỗi ô, đọc một lần khi load catalog.

## 5. Agent

`data-migration` (v24), `ux-reviewer`, `design-reviewer` (ô, glyph).
