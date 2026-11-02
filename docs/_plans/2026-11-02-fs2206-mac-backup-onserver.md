# Kế hoạch — Backup và smart album On Server trên Mac (FS-22.06, FS-19.07 §11)

| | |
|---|---|
| Spec | [FS-22.06](../02-functional-spec/FS-22-backup/06-mac.md) (AC-40…53, SM-1…4) · [FS-19.07 §11](../02-functional-spec/FS-19-photo-sources/07-on-server-check.md#11-mac-2026-11-02) + [07b §3](../02-functional-spec/FS-19-photo-sources/07b-on-server-check-ac.md#3-mac) (AC-107…113) |
| Commit spec | `649d2a3c` |
| Ngày | 2026-11-02 |
| Ưu tiên | người dùng 2026-11-02: Mac làm quản lý ảnh trước; Editor, Video Studio, Collage của FS-18 dời lại |

## 1. Đã có (không viết lại)

- Logic: `BackupRunner`, `BackupStore`, `BackupPathPlanner`, `PhotoKitBackupSource`, `SourceCopyBackupSource`,
  `OnServerCheck`, `OnServerPresenceSQL`, `OnServerProgressQueries`, `PhotoDeletionGate`, `SmartAlbumSQLBuilder` — nằm
  trong Data/Domain, **đã build cho macOS** (FS-18 P1–P4; build xanh `e06370fa`).
- Mô hình màn iOS không dùng UIKit, dùng lại qua `Tools/mac-membership.shared`: `SmartAlbumDetailModel`,
  `SmartAlbumConditionsBar`, `SmartAlbumRuleRow` (cần thử), `AlbumsModel`, `ServerDiscoveryModel`, `ConnectAsModel`.
  `BackupFormModel` có `import UIKit` → gỡ (chỉ dùng cho tên máy).
- `BackupCoordinator` (App/, 304 dòng): gần như không phụ thuộc iOS; chỉ `ScreenHolding` (Keep Screen On) và
  `BackupBackgroundService` (BGTask). Dời lõi sang `Domain/Backup/`, phần iOS ở lại App/.

## 2. Thiếu (Mac chưa có gì, phải dựng trước khi Backup/smart album dùng được)

| Cần | Vì sao | Board |
|---|---|---|
| Form server (thêm/sửa connection) + màn duyệt folder | New Backup chọn connection + folder; Folder của smart album | `MAC_ServerForm`, `MAC_ServerBrowser` |
| Thêm nguồn server (FS-19) | điều kiện Source của smart album là nguồn server | `MAC_AddSource` |
| Albums + smart album editor + màn album | AC-107 | `MAC_SmartAlbumEditor`, `MAC_SmartAlbum` |
| Cửa sổ Settings (chỉ General › Background lúc này) | AC-46 | `MAC_SettingsGeneral` |

## 3. Thứ tự task — mỗi task một commit, build Mac + iOS sau mỗi commit

### Khối H — helper và hạ tầng

| # | Task | AC | Test |
|---|---|---|---|
| H0 | Spike SM-2, SM-3, SM-4 trên máy này (macOS 27); SM-1 cần ổ ngoài của người dùng | — | số ghi vào intent |
| H1 | Nhóm app + nhóm Keychain cho `ShotDexMac`; `AppDatabase.makeShared` trên macOS mở ở container nhóm app | nền AC-45 | `AppDatabaseLocationTests.macUsesAppGroup` |
| H2 | Dời lõi `BackupCoordinator` sang `Domain/Backup/` (giữ `ScreenHolding` sau protocol, BGTask ở App/) — iOS không đổi hành vi | nền | `BackupCoordinatorTests` hiện có |
| H3 | ✅ 2026-11-02 Helper = chính file chạy với `--agent`, LaunchAgent qua `SMAppService.agent` (đổi từ target riêng) | AC-46, 47 | `MacAgentStatusTests` |
| H4 | (On Server ✅ 2026-11-02) Agent chạy: coordinator + `OnServerCheck`; nghe đổi thư viện Photos, tick nguồn 5 phút, liệt kê server 30 phút, ngủ/thức, power assertion | AC-43, 44, 49, 50, 53, 109, 110 | `MacAgentTests.*` |
| H5 | XPC lệnh app → agent; Darwin notify agent → app; một người chạy (agent bật thì app không chạy job) | AC-45 | `MacAgentTests.singleRunner` |
| H6 | Quyền thư mục trong helper (Q-M1): helper hỏi một lần, giữ bookmark riêng; bảng mới qua `data-migration` | AC-48 | sau SM-1 |

### Khối U — màn Mac

| # | Task | AC | Board |
|---|---|---|---|
| U1 | Sidebar hàng Backup đầu Utilities (đếm/chấm cảnh báo), Go › Backup ⌥⌘B, File › New Backup… | AC-40, 52 | `Main`, `MAC_Backup` |
| U2 | Form server + duyệt folder (sheet) | AC-41 | `MAC_ServerForm`, `MAC_ServerBrowser` |
| U3 | Màn Backup: danh sách + inspector, chuột phải, rỗng | AC-40, 41, 52 | `MAC_Backup` |
| U4 | Sheet New/Edit + trang Organize + popover Custom (không hàng Wi‑Fi; Only on Power Adapter khi có pin) | AC-42, 51 | `MAC_BackupNew`, `MAC_BackupOrganize` |
| U5 | ✅ 2026-11-02 Cửa sổ Settings › General › Background | AC-46, 50 | `MAC_SettingsGeneral` |
| U6 | Thêm nguồn server (FS-19) trên Mac | nền AC-107 | `MAC_AddSource` |
| U7 | Smart album: editor sheet (điều kiện Source + Folder), màn album có chip + dòng tiến độ | AC-107, 108 | `MAC_SmartAlbumEditor`, `MAC_SmartAlbum` |
| U8 | Xoá qua cổng (⌘⌫, NSAlert Delete Anyway/Cancel) | AC-111, 112 | — (alert hệ thống) |
| U9 | Glyph trên server ở ô lưới + Get Info mục On Server | AC-113 | `MAC_GetInfoSingle` |

**Thứ tự:** H0 → H1 → H2 → U1 → U2 → U3 → U4 (app tự chạy job khi mở — dùng được ngay, chưa cần helper) → H3 → H4 → H5
→ U5 → U6 → U7 → U8 → U9 → H6 (sau SM-1). Chứng minh UI: `Tools/mac-shot` + `design-parity` theo board — cần quyền
Screen Recording cho Terminal (người dùng cấp, FS-18 ghi là còn thiếu).

## 4. Rủi ro

| Rủi ro | Xử lý |
|---|---|
| PhotoKit trong helper hỏi quyền lại hay từ chối (SM-2) | không đạt → Photos chạy trong app khi mở, helper chỉ chạy nguồn server/thư mục; sửa §2 FS-22.06 |
| GRDB hai tiến trình (SM-3) | `DatabasePool` + `busyMode` timeout; chỉ helper ghi sổ khi đang chạy |
| UI test Mac chưa có (FS-18 T3) | AC giao diện chứng minh bằng ảnh `mac-shot` + compare board tới khi có T3 |
