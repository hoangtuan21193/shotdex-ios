# FS-19.08 loop — trạng thái

Loop tự chạy (`/loop`, 2026-11-03) làm hết task của [plan](2026-11-03-fs1908-common-photos.md). File này là trí nhớ
của loop: mỗi vòng đọc nó trước, ghi lại sau.

## Luật mỗi vòng

1. Một task: code → build iOS + `ShotDexMac` → test liên quan (`-only-testing`, không full suite) → **2 lượt review độc
   lập**, sửa hết → e2e trên SMB ảo nếu task chạm server → task UI: `Tools/mac-shot` sáng + tối, xem ảnh, so board.
2. Cập nhật 08b (cột chứng minh), plan (trạng thái), dòng Tiến độ intent → commit chỉ file mình đổi.
3. **Không tắt/xoá SMB ảo** tới khi xong T12.

## SMB ảo

| | |
|---|---|
| Server | impacket `smbserver.py -smb2support`, `127.0.0.1:4450`, share `photos`, user `tester` / `secret` |
| Chạy | `cd build && nohup smb-venv/bin/python smb-venv/bin/smbserver.py -smb2support -username tester -password secret -port 4450 -ip 127.0.0.1 photos smb-share/photos > smb-server.log 2>&1 &` |
| Dữ liệu | `build/smb-share/photos` sinh bằng `build/smb-venv/bin/python build/smb-make-fixtures.py build/smb-share/photos` — phong cảnh tổng hợp, không người. `Tuan/2025/06/IMG_0001…0012`, `Vo/from-tuan/2025-06-01 IMG_0001…0008` (cùng byte, khác tên), `Vo/own/` 4 ảnh riêng, `Vo/edited/IMG_0001.JPG` (cùng tên, khác byte), `Shared/` rỗng |
| Kiểm còn chạy | `lsof -iTCP:4450 -sTCP:LISTEN` |

## Môi trường

- 2026-11-03: máy không còn runtime simulator iOS; người dùng chọn tải iOS 27.1 (`xcodebuild -downloadPlatform iOS`;
  lệnh kéo thêm iOS 27.0 sau đó — đã dừng). Runtime 27.1 chỉ nhận **iPhone Duo** → máy test
  `claude iPhone Duo 27.1` `6E3CE306-B474-4EBD-953B-E7D807BB25BC`. Test: `-destination 'id=6E3CE306-…'`, chạy nền (lần
  đầu > 10 phút).

## Task

| Task | Trạng thái | Commit | Ghi chú |
|---|---|---|---|
| T1+T2 | xong | `eefcf32c` | `ServerTreeListing` tách từ `ServerSourceIndexer.list`; matcher ở Domain, scanner ở Data; `CommonPhotosSelection` (kiểm folder) kéo vào T1 |
| (T2) | gộp vào T1 (chung file test) | `eefcf32c` | `CommonPhotosVerifier`: đọc thiếu byte → bỏ file; SHA cache cần ngày sửa + băm lại một bản; WebDAV kiểm `Content-Range` |
| T3 | xong | (xem git log) | migration `v46-commonPhotos`: trạng thái `copying`/`moving`/`placed`, `partPath`, nguồn có tem + `isRemoved`, run `finishing`, đọc hỏng → chỉ Discard |
| T4 | xong | (xem git log) | runner Copy + trùng tên (AC-126 kéo từ T5), lý do lưu dạng mã |
| T5 | xong | (xem git log) | sidecar theo luật RAW+JPEG, thử lại khi Resume; e2e Copy thật trên SMB |
| T6 | xong | (xem git log) | Move: máy trạng thái; xoá = đổi tên sang `.shotdex-removing` → kiểm đích → xoá (chặn hai đường dẫn một file); e2e Move trên SMB |
| T7 | xong | (xem git log) | Resume: chặn chạy hai lần (`isActive` cho banner), nhận `finishing`, lượt bị kill giữa chừng |
| T8 | xong | (xem git log) | CSV (tiếng Anh cố định, BOM, chặn công thức), `afterRun` + `HistoryChange`, sổ Backup đi theo; nối Mac ở T10 |
| T9a | xong | (xem git log) | màn duyệt server Mac: cột + lưới, Rescan, sao/cờ, ⌘/⇧ sẵn cho T9b; accent sáng #C6730E; `ServerSourceRefresh` cho lượt sau chờ lượt đang chạy. Chưa bấm thử được (không có quyền Accessibility) |
| T9b | xong | (xem git log) | ⌘/⇧ chọn nhiều (ClickSelection, Domain), chuột phải chọn lại mục rồi mới mở menu, menu ẩn Find Common Photos… dưới 2 folder (HIG), File ⇧⌘F; hook `commonPhotosRequest` cho T10. Chưa bấm thử được |
| T10 | xong | (xem git log) | sheet + `MacCommonPhotosRuns` (connect, giữ máy thức, afterRun: lịch sử 1 lần ghi + rescan `fresh`); chạy thật Copy 8 ảnh + Move 3 ảnh từ app trên SMB ảo (scratch, đã dọn); SHA cache chỉ cho bản folder đầu; `ServerIdentity` (SFTP username, WebDAV share) |
| T11a | xong | (xem git log) | board `MAC_Activity` 900×560 sáng/tối + tweak empty, publish canvas Mac v76 |
| T11, T11b, T12 | chưa | — | T11 đang làm |

Tiếp: T11a (vẽ board `MAC_Activity`) → T11 (cửa sổ `MAC_CommonPhotosRun`) → T11b (Activity).

Chụp Mac: `ShotDex.app/Contents/MacOS/ShotDex -ApplePersistenceIgnoreState YES -ShotDexDemoLibrary -ShotDexSection serverBrowser -ShotDexServerPath Tuan/2025/06 [-ShotDexAppearance dark] [-ShotDexServerLayout list]` (DB demo trong RAM, connection "Test SMB" tới SMB ảo) + reopen Apple Event: scratchpad `tools/shot.sh`.

Bài học: không chạy test nền khi sắp dừng lượt — hook build-check build cùng `build/sim` và báo "database is locked".
