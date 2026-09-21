# FS-08.01 — Bố cục theo bề rộng và tìm kiếm

`FS-08.01` · `SettingsLayout` · `SettingsSearchIndex` · test `SettingsLayoutTests` · `SettingsSearchTests`
· cập nhật 2026-09-22

**Một câu:** một cột ở compact, `NavigationSplitView` ở regular, và một ô tìm kiếm chạy **theo hàng** ở cả hai.

## 1. Quy tắc

- **Ngưỡng là size class, không phải một con số pt.** `SettingsLayout.usesSplitView(horizontalSizeClass:)`
  là hàm **thuần, có test** — không phải một `if` trong `body`.
- `nil` size class rơi về bố cục một cột, không đoán.
- Hai bố cục dựng từ **cùng** `SettingsSection.allCases`.
- **Bố cục compact không đổi một dòng nào** so với trước khi có split view.
- **`List(selection:)` của sidebar phải là con trực tiếp của cột sidebar** (đo trên iPad, 2026-09-22).
  Bọc nó trong một nhánh điều kiện — ví dụ để thay bằng danh sách kết quả tìm kiếm — thì **chạm vào một
  mục sidebar không làm gì cả**: SwiftUI chỉ trao hành vi chọn-bằng-một-chạm cho chính list của sidebar.
  Khi tìm kiếm thì đổi **hàng bên trong** list, không thay cả list; ô "không tìm thấy" là `.overlay`.
  Xem `DESIGN.md` §10.1f.

## 2. Hai bố cục

| | Compact | Wide |
|---|---|---|
| Điều kiện | `horizontalSizeClass == .compact` | `== .regular` |
| Vật chứa | `NavigationStack` → `List(.insetGrouped)` | `NavigationSplitView` — sidebar + detail |
| Màn con | push chồng trong stack | mở **trong detail pane** |
| Thiết bị | mọi iPhone, Duo ngoài 466×678, iPad Slide Over | iPad 11" dọc 834pt trở lên, iPad Split View 1/2, **Duo trong 951×669** |

**Vì sao không dùng 900pt** (intent ban đầu chốt con số này): 900pt sẽ để iPad 11" dọc ở lại layout điện
thoại trong khi Settings của iPadOS, cùng bề rộng đó, đang chạy hai cột. Đổi lại Split View 1/2 trên 13"
(688pt) cũng vào split — đúng điều hệ thống làm.

## 3. Sidebar — 9 mục

| # | Mục | Ký hiệu | Gom section nào của compact |
|---|---|---|---|
| 1 | Photo Library | `photo.stack` | Photo Library + Library Size + Privacy |
| 2 | Notifications | `bell` | Notifications |
| 3 | Widgets | `square.grid.2x2` | Widgets |
| 4 | Display | `text.below.photo` | Thumbnail Metadata |
| 5 | Playback | `play.rectangle` | Playback |
| 6 | People and Pets | `person.2` | Subject Scan |
| 7 | Sharing and Export | `square.and.arrow.up` | Sharing + Export |
| 8 | Camera Database | `camera` | Camera Database |
| 9 | Support | `questionmark.circle` | `SupportScreen` |

- Ký hiệu **chỉ ở sidebar**; compact vẫn là section có header chữ. `.symbolRenderingMode(.hierarchical)`,
  màu accent, **không** nền bo tròn kiểu Settings hệ thống.
- Library Size và Privacy không phải mục riêng — Library Size là hai hàng số, Privacy là đoạn giải thích
  cộng nút phá huỷ, cả hai nằm cuối **Photo Library**.
- Chín mục gom lại để vừa một màn **669pt** (Duo trong) mà không phải cuộn.

## 4. Số đo

| Mục | Giá trị |
|---|---|
| Bề rộng sidebar | `AppTheme.Size.settingsSidebarWidth = 320`, qua `.navigationSplitViewColumnWidth(280/320/360)` |
| Đo thật iPad 11" dọc / iOS 18.6 | **320pt** |
| Đo thật iPad 13" ngang / iOS 26.5 | **350pt** — sidebar ở 26 là tấm kính nổi thụt vào khỏi mép (`x=26 w=288`) |
| Bề rộng nội dung detail | `AppTheme.Size.settingsDetailContentMaxWidth = 840`, canh giữa |
| Detail hẹp nhất còn vào split | 368pt (Split View 1/2 trên 13") — vẫn trên sàn 320pt |

**`List(.insetGrouped)` KHÔNG tự chừa lề trong pane rộng** — đo trên iPad 13" ngang, hàng detail rộng
1006pt và "Access" đứng cách "Full Access" ~900pt. Phải tự giới hạn bề rộng + trả nền xám nhóm cho cả
pane (`scrollContentBackground(.hidden)` + `background`); đo lại còn 800pt.

`DESIGN.md` §10.1f ghi luật này, `settingsSidebarWidth` nằm trong bảng §6 — hằng số rời trong file feature
bị cấm.

## 5. Tìm kiếm

Có ở **cả hai bố cục** — `.searchable` trên sidebar ở wide, trên `List` ở compact.

- **Tìm theo hàng, không theo mục.** Người ta gõ "ISO", "cellular", "HDR" — tên của **một hàng** nằm sâu
  bên trong. Nguồn đối sánh là `SettingsSearchIndex`: mỗi mục khai nhãn các hàng nó chứa, khai ngay cạnh
  `SettingsSection`.
- **Bỏ dấu, bỏ hoa/thường** — "hdr" khớp "View Full HDR".
- Kết quả là **danh sách hàng**: nhãn hàng + tên mục ở dòng phụ. Chạm một kết quả → mở mục đó, **cuộn tới
  hàng** (`ScrollViewReader`), rồi **nháy nền hàng 1,2 giây**.
- Không khớp gì → `ContentUnavailableView.search(text:)`, không phải danh sách rỗng.
- Search **không nhớ** truy vấn giữa hai lần mở Settings.
- **Giá phải trả:** index là bản sao thứ hai của nhãn hàng. Giảm rủi ro bằng cách dùng chung hằng chuỗi
  (`String(localized:)` một chỗ, hai nơi đọc); AC-17 đối chiếu số lượng.

## 6. Hành vi

- **Mục mặc định**: Photo Library. **Không nhớ** mục đã chọn — không thêm key `UserDefaults` cho một
  trạng thái điều hướng.
- **Done** ở toolbar **sidebar** (`.confirmationAction`), đóng toàn bộ Settings từ bất kỳ mục nào —
  `fullScreenCover` không có swipe để đóng.
- Mỗi detail pane là một `NavigationStack` riêng: **Back quay về màn trước của chính mục đó**, không nhảy
  về sidebar.
- `PhotoWidgetSettingsScreen` lấy **trọn** detail pane, giữ nguyên cấu trúc
  `VStack { previewHeader; Divider; List }` và luật cử chỉ ([04](04-photo-widget-designs.md)).
- **Đổi bề rộng lúc đang mở** (xoay, Stage Manager, gập/mở Duo): bố cục đổi ngay, **mục đang xem được
  giữ** — rơi về compact thì nó là màn đang push, lên wide thì nó là mục đang chọn.
