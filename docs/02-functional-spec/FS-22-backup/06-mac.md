# FS-22.06 — Backup trên Mac, và helper chạy cả khi app đã Quit

`FS-22.06` · tier A · board (vẽ ở bước Design này, canvas Mac): `MAC_Backup` · `MAC_BackupNew` · `MAC_BackupOrganize` ·
`MAC_SettingsGeneral` (hàng mới) · mã đề xuất: `ShotDexMac/Backup/`, target mới `ShotDexMacAgent` · cập nhật 2026-11-02

**Một câu:** trên Mac, Backup có cùng job, cùng Organize, cùng sổ và cùng luật chép như iOS (01–05); khác ở chỗ ai chạy
job — một **helper đăng ký làm login item** chạy job Backup và lượt kiểm On Server (FS-19.07 §11) cả khi ShotDex đã Quit.

Nguồn: người dùng 2026-11-02 — "trên macos chưa cần edit và video studio, ưu tiên quản lý ảnh: backup và smart album
filter ảnh đã có trên NAS"; chọn **helper chạy cả khi app đã Quit** (thay vì chỉ khi app mở) và **nguồn Photos + thư
mục/ổ ngoài** như iOS.

## 1. Cái gì giữ nguyên, cái gì khác

| Giữ nguyên (dùng lại code Domain/Data đã build cho macOS) | Khác trên Mac |
|---|---|
| job, sổ từng file, Organize, tên file, trùng tên, SHA-256, `.shotdex-part` (01, 03) | ai chạy: helper, không phải BGTask (§2) |
| phát hiện file mới §1 của 02, chép một file §2 của 02, không chép trùng giữa máy (05) | chỗ để database: thư mục nhóm app, dùng chung app + helper (§3) |
| trạng thái và câu chữ của 02 §5 | điều kiện mạng và nguồn điện theo Mac (§4) |
| | màn: một cửa sổ, danh sách + inspector, sheet thay cho đẩy màn (§5) |

**Cố ý không có trên Mac:** phần mở rộng tải nền của Photos (02 §3c, chỉ có iOS 26.1+) · Keep Screen On (02 §3) — thay
bằng giữ Mac thức (§4) · lịch chạy, menu bar icon. *Vì* helper đã chạy liên tục, không cần đường thứ hai.

## 2. Helper

- Target mới `ShotDexMacAgent`, nằm trong `ShotDex.app/Contents/Library/LoginItems/`, đăng ký bằng
  `SMAppService.loginItem(identifier:)`. Không cửa sổ, không icon Dock, không menu bar (`LSUIElement`). Sandbox như app.
- **Một người chạy tại một thời điểm.** Helper bật → mọi job Backup và lượt kiểm On Server chạy trong helper; app chỉ đọc
  database và gửi lệnh (Pause, Resume, Back Up Now, Retry, job mới/sửa/xoá) qua XPC. Helper tắt (người dùng tắt, hay
  macOS từ chối) → app tự chạy job khi app đang mở, như iOS lúc ở trước mặt; Quit app là dừng.
- Helper bật mặc định khi người dùng **tạo job Backup đầu tiên** hay mở smart album On Server đầu tiên; macOS hiện thông
  báo hệ thống "Background Items Added" — app không tự hiện câu nào thêm.
- Không còn job và không còn nguồn server nào có lượt kiểm → helper tự thoát; vẫn là login item, lần đăng nhập sau mở rồi
  tự thoát nếu vẫn không có việc. Tạo job mới → app mở helper ngay.
- Helper chết giữa file (crash, bị Force Quit, máy tắt): luật "sổ ghi sau khi đổi tên thật" của 02 §2 giữ nguyên; lần mở
  kế (login, hay app mở lại) chạy tiếp từ file kế.
- Settings › General thêm nhóm **Background** (§5.4). Hàng nói thật trạng thái của macOS: `On` · `Off` · `Needs Approval`
  (người dùng tắt trong System Settings › General › Login Items) + nút **Open Login Items Settings**.
- Thông báo người dùng: helper không gửi notification nào. *Vì* Backup là việc nền, lỗi đọc thấy khi mở màn Backup.

**Q-M1 — nguồn thư mục/ổ ngoài trong helper** (chốt 2026-11-02, người dùng): bookmark có phạm vi app do app tạo **không**
mở được trong helper (khác bundle id), nên lúc tạo job nguồn thư mục, **helper tự xin quyền một lần**: hiện hộp chọn thư
mục điền sẵn ("Allow ShotDex to keep backing up *T7 RAW Archive* after you quit"), người dùng bấm Allow một lần mỗi
nguồn, helper giữ bookmark của nó. Đã bỏ phương án "thư mục chỉ chạy khi app mở". Spike SM-1 (§7) đo trước khi code.

## 3. Dữ liệu dùng chung app + helper

- Database ShotDex của Mac ở thư mục nhóm app `group.com.hoangtuan.shotdex` (không phải container riêng của app), mở bằng
  `DatabasePool` ở cả hai tiến trình (WAL). App Mac chưa phát hành → không chuyển dữ liệu cũ (luật CLAUDE.md).
- Màn của app thấy thay đổi do helper ghi trong ≤ 1 s: helper gửi thông báo Darwin sau mỗi transaction của sổ/trạng thái,
  app đọc lại. *Vì* `ValueObservation` của GRDB không thấy tiến trình khác ghi.
- Mật khẩu server: nhóm Keychain chung app + helper (cùng nhóm đã dùng cho phần mở rộng iOS).
- Index thư viện (`photo_metadata`) vẫn chỉ app ghi; helper chỉ ghi bảng Backup, bảng hash On Server và mốc thay đổi.

## 4. Điều kiện chạy trên Mac

| Hàng iOS | Trên Mac | Luật |
|---|---|---|
| Only on Wi‑Fi | **không có hàng** (Q-M2, chốt 2026-11-02) | Mac chạy trên mọi mạng; cờ trong database của job Mac luôn tắt |
| Only While Charging | **Only on Power Adapter** | chỉ hiện trên Mac có pin; Mac để bàn không có hàng này; job cũ mang cờ bật thì coi như luôn đủ điều kiện |
| Keep Screen On | — | thay bằng **Keep Mac Awake While Copying** (§5.4) |

- **Máy ngủ:** Mac ngủ thì helper dừng ở file đang làm như Pause của hệ thống (02 §4); thức dậy chạy tiếp. Dòng 2 của
  `Paused`: `Mac was asleep · resumes now`.
- **Keep Mac Awake While Copying** (Settings › General › Background, mặc định **bật khi cắm điện**): đang chép thì giữ
  Mac không tự ngủ vì rảnh (không chặn gập máy hay bấm Sleep). *Vì* lượt đầu hàng trăm GB, Mac để mặc định ngủ sau
  vài phút. Hàng **Keep Mac Awake While Uploading** của Servers (FS-18.04 §3) gộp vào hàng này.
- **Ổ chứa Photos Library ngoài rút ra / nguồn thư mục offline:** `Source Offline` như 02 §5.
- **Không gian trống:** luật 2 GB của 02 §2 tính trên ổ chứa thư mục tạm của helper (ổ hệ thống).

## 5. Màn

### 5.1 Lối vào

- Sidebar › Utilities: hàng **Backup** đứng **đầu** Utilities (trước Statistics), icon như iOS. Đếm = số job; job nào
  đang lỗi (Can't Reach, Is Full, Needs Approval) thì thay số bằng chấm cảnh báo.
- Menu **Go › Backup** (⌥⌘B) · **File › New Backup…**.

### 5.2 Màn Backup (`MAC_Backup`) — gộp 1/5 và 5/5

- Vùng nội dung: danh sách job (mỗi hàng: tên nguồn, connection, `<folder> · <What to Copy>`, dòng trạng thái 02 §5,
  vòng tiến độ nhỏ). Nhấp chọn → **inspector phải** là nội dung 5/5 của job đó (vòng %, đếm, file đang chép, N Files
  Not Copied, Watching…).
- Toolbar: **+** (New Backup…) · **Back Up Now** · **Pause/Resume** (theo hàng đang chọn) · nút inspector.
- Chuột phải hàng: Edit… · Back Up Now · Pause/Resume · Show Destination in Finder (chỉ khi share đang mount) · Delete Job…
  (xác nhận như iOS).
- Rỗng: câu của iOS + **New Backup…**; chưa có connection → **Add a Server…** mở form `MAC_ServerForm`.
- Chân danh sách: một dòng theo §2 — `Backups keep running after you quit ShotDex.` hoặc (helper tắt)
  `Backups stop when you quit ShotDex.` + link **Change…** mở Settings › General.

### 5.3 New Backup / Edit (`MAC_BackupNew`, `MAC_BackupOrganize`)

- Sheet 640×560 (cỡ sheet Mac của smart album, FS-18.04 §1). Nhóm và luật y 01 §2: Source · Destination · Organize ·
  What to Copy · Automatic Backup (hàng theo §4). Start / Save · Cancel ở chân; Return = Start khi sáng.
- Organize: một hàng tóm tắt + đường dẫn ví dụ; **Organize…** đẩy trang thứ hai trong cùng sheet (3/5 + 4/5 gộp): Levels,
  kiểu từng mức, Videos, RAW Files, File Names, Preview cây ở trên. Custom… mở popover cạnh popup (4/5).
- Destination › Folder mở `MAC_ServerBrowser` dạng sheet chồng.
- Nguồn thư mục theo Q-M1: sau Start, nếu helper bật, helper hiện hộp chọn thư mục điền sẵn; người dùng Cancel →
  job vẫn lưu, chạy khi app mở, dòng trạng thái `Allow access to keep backing up after quit` + nút **Allow…**.

### 5.4 Settings › General › Background (`MAC_SettingsGeneral`)

| Hàng | Mặc định | Ghi chú |
|---|---|---|
| Keep Working After Quit | bật khi có job/smart album On Server đầu tiên | công tắc + trạng thái `Needs Approval` + Open Login Items Settings; chân: "Backups and On Server checks continue in the background." |
| Keep Mac Awake While Copying | On Power Adapter | Never · On Power Adapter · Always |

## 6. Tiêu chí nghiệm thu (Mac)

Server giả như 04: WebDAV (wsgidav) và SMB (impacket) ở 127.0.0.1. Máy: Mac Apple silicon, macOS 26 (macOS 15: chưa kiểm
— cần máy thật, như FS-18). Thư viện Photos thử không có ảnh mặt người.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-40 | cửa sổ Library, chưa có job, có 1 connection | nhìn sidebar Utilities, nhấp Backup | hàng Backup đứng đầu Utilities; vùng nội dung rỗng có **New Backup…** | ⚠️ chưa có (`mac-backup-flow.json`) + `design-parity` `MAC_Backup` |
| AC-41 | chưa có connection nào | mở Backup | nút là **Add a Server…**, nhấp mở sheet form server | ⚠️ chưa có (`mac-backup-no-server.json`) |
| AC-42 | New Backup…, nguồn Photos, connection WebDAV, chưa chọn Folder | nhìn Start; chọn folder | Start mờ → sáng; Return = Start; hàng điều kiện theo §4 (Mac có pin: Only on Power Adapter) | `BackupJobFormTests` (dùng lại) + ⚠️ chưa có (`mac-backup-flow.json`) |
| AC-43 | job Photos 10 ảnh + 2 video, helper bật | Start, rồi **Quit ShotDex** ngay | sau Quit, helper chép đủ 12 file; đích khớp `shasum -a 256`; mở lại app thấy `Watching · Up to Date` | ⚠️ chưa có (`MacAgentTests.runsAfterAppQuits` + script host) |
| AC-44 | helper đang chép file 5/12 | `kill -9` helper, mở lại app | file 1–4 trong sổ, lượt tiếp chép từ file 5; ≤ 1 `.shotdex-part` bị ghi đè | ⚠️ chưa có (`MacAgentTests.resumesAfterKill`) |
| AC-45 | helper đang chạy job | app mở cùng lúc, nhấp Back Up Now | chỉ helper chép (0 byte app ghi lên đích); app hiện tiến độ đổi trong ≤ 1 s sau mỗi file | ⚠️ chưa có (`MacAgentTests.singleRunner` + `.appSeesAgentWritesWithinOneSecond`) |
| AC-46 | người dùng tắt ShotDex trong System Settings › Login Items | mở Settings › General | Keep Working After Quit hiện `Needs Approval` + Open Login Items Settings; chân Backup ghi `Backups stop when you quit ShotDex.`; app tự chạy job khi đang mở | ⚠️ chưa có (`MacAgentStatusTests.needsApproval` + ảnh cửa sổ) |
| AC-47 | không còn job nào, không smart album On Server | xoá job cuối | helper thoát trong ≤ 10 s; vẫn là login item | ⚠️ chưa có (`MacAgentTests.exitsWhenIdle`) |
| AC-48 | job nguồn thư mục `T7 RAW Archive` (Q-M1) | Start | helper hiện hộp chọn thư mục điền sẵn; Allow → job chạy sau khi Quit; Cancel → `Allow access to keep backing up after quit` + Allow… | ⚠️ chưa có — chờ spike SM-1 |
| AC-49 | Mac ngủ giữa file 7/20 | thức dậy | trạng thái `Paused · Mac was asleep` rồi tự chạy tiếp từ file 7 | ⚠️ chưa có (`MacAgentTests.sleepPausesAndResumes`, giả lập thông báo ngủ/thức) |
| AC-50 | Keep Mac Awake While Copying = On Power Adapter, cắm điện | đang chép | có power assertion chặn ngủ vì rảnh (`pmset -g assertions` liệt kê ShotDex); hết hàng đợi → assertion nhả | ⚠️ chưa có (`MacPowerTests` + `pmset` trên host) |
| AC-51 | New Backup… trên Mac, mạng là hotspot iPhone (mạng đắt) | nhìn Automatic Backup; Start với 12 mục | không có hàng Only on Wi‑Fi; job chép đủ 12 mục, không bao giờ `Waiting for Wi‑Fi` | ⚠️ chưa có (`BackupJobFormTests.macHasNoWiFiRow` + `BackupRunnerTests` với cờ tắt) |
| AC-52 | job đang lỗi `Can't Reach NAS Home` | nhìn sidebar | hàng Backup có chấm cảnh báo thay số; chuột phải job có Edit…, Back Up Now, Delete Job… | ⚠️ chưa có (`mac-backup-states.json`) |
| AC-53 | job Up to Date, app đã Quit, thêm 3 ảnh vào Photos trên Mac | chờ | ≤ 30 s sau 3 file lên đích (helper nghe sự kiện đổi thư viện) | ⚠️ chưa có (`MacAgentTests.libraryChangeWhileAppQuit` + thư viện Photos thử trên Mac) |

## 7. Spike (máy thật, trước khi chốt AC)

| # | Câu hỏi | Đạt khi | Phụ thuộc |
|---|---|---|---|
| SM-1 | Helper sandbox giữ được bookmark của chính nó cho thư mục/ổ ngoài qua đăng nhập lại; mở được khi ổ cắm lại | 3/3 lần (khởi động lại, rút cắm ổ, đổi tên ổ) | Q-M1 |
| SM-2 | PhotoKit trong helper (không phải app chính, `LSUIElement`) có quyền Photos của app không, hay hỏi lại? | dùng được quyền đã cấp, hay hỏi đúng một lần | §2; không đạt → helper chỉ chạy nguồn server/thư mục, Photos chạy khi app mở |
| SM-3 | `DatabasePool` hai tiến trình + Darwin notify: độ trễ app thấy dòng sổ mới | ≤ 1 s, 0 lỗi `SQLITE_BUSY` qua 10.000 file | §3 |
| SM-4 | Hai thư viện SMB/SFTP chạy trong sandbox helper (FS-18.05 §6 đã ghi rủi ro) | liệt kê + ghi 1 GB | §2 |
