# FS-19.07 — Ảnh Photos đã có trên server chưa

`FS-19.07` · tier B (smart album, lưới, Photo Info) · mã có sẵn: `Data/Sources/PhotosContentHashPass.swift`,
`Data/Sources/FileServer/ServerSourceIndexer.swift`, `Data/Database/SmartAlbumSQLBuilder.swift`,
`Data/Sources/Folders/DeletionService.swift` · AC + spike: [07b](07b-on-server-check-ac.md) · cập nhật 2026-10-25

**Một câu:** ShotDex biết chắc từng ảnh/video trong Photos có bản giống hệt trên một folder của nguồn server hay chưa —
kể cả khi file bị script ngoài dời, đổi tên — kiểm cả thư viện ở nền, làm tiếp được, và kiểm lại NAS trước khi xoá.

Nguồn: [intent 2026-10-24-smart-album-on-nas](../../_intents/2026-10-24-smart-album-on-nas.md) (accepted) · trả lời
người dùng 2026-10-25: dựa trên nguồn FS-19 · ảnh chỉ có trên NAS vẫn hiện trong Library · chọn folder ngay trong điều
kiện · một dấu lưới nghĩa là "đang có trên server".

## 1. Người dùng cần gì

- iCloud đầy; bản gốc đã nằm trên NAS (Backup FS-22, script gộp của người dùng dời file sang `Shared/`).
- Cần một album "ảnh trên máy này đã có trên `NAS › iCloud Photo/Shared`" để xoá khỏi Photos mà chắc chắn không mất gì.
- Hàng chục nghìn mục, hàng trăm GB: kiểm phải tự chạy, chạy nền, dừng ở đâu làm tiếp ở đó.

## 2. Phạm vi

**Có:** băm ảnh Photos (gồm video, Live Photo, RAW+JPEG) chạy nền · băm đầy đủ file server khi có ứng viên · điều kiện
Source có Folder · trạng thái "chưa kiểm" · tiến độ · kiểm lại server trước khi xoá · dấu lưới + Photo Info theo hiện trạng.

**Cố ý không có:**
- Tìm/gộp ảnh trùng giữa các folder, dời hay xoá file trên NAS — *vì* script của người dùng làm (intent).
- So ảnh đã nén lại (Messages, Zalo) với bản gốc — *vì* byte khác; Duplicates FS-06.06 lo phần giống hình.
- Đưa ảnh từ NAS về Photos — intent riêng `2026-10-24-restore-from-nas-to-album`.

## 3. Khớp bằng nội dung

- Dùng hash danh tính của FS-19 (SHA-256 phần dữ liệu ảnh, [02 §1](02-identity-and-sidecars.md)). Video và file lạ:
  theo luật của bộ băm đó. *Vì* một hệ hash duy nhất; Backup ghi thêm hash này (§6) nên không đọc lại NAS.
- Một mục Photos **có trên folder F của server S** khi **mỗi file gốc** của nó có một file trong F (mọi tầng con) cùng
  hash đầy đủ: ảnh · RAW của RAW+JPEG · video đi kèm Live Photo · video. Bản sửa không tính.
- Thiếu một file (Live Photo chỉ có HEIC trên NAS) → **không** có trên F.
- Đổi tên, dời trong cùng nguồn: hash giữ danh tính ([02 §2](02-identity-and-sidecars.md)); không băm lại file đã biết.

## 4. Băm phía Photos

- Chạy khi có ít nhất một nguồn server. Lấy mọi mục Photos chưa có hash đầy đủ cho đủ file gốc, mới nhất trước.
- Bản gốc chỉ ở iCloud: tải về **thư mục tạm, một file một lúc**, băm theo khối 1 MB, xoá ngay. Không bao giờ giữ cả bản
  gốc trong RAM; video đọc luồng ([NF-02](../../04-non-functional-design/NF-02-memory-and-resources.md)).
- Máy còn trống − cỡ file < 2 GB → chờ, trạng thái `Waiting for space` (luật FS-22).
- Mỗi mục băm xong ghi ngay vào database → bị dừng ở đâu làm tiếp ở mục kế; mục đang dở băm lại từ đầu.
- Quyền `.limited`: chỉ băm mục được cấp; dòng tiến độ thêm "Only photos ShotDex can access are checked."

## 5. Băm phía server

- Liệt kê lại cây (tên, cỡ, ngày sửa): **mỗi lần app về trước mặt**, khi server về lại, khi bấm Rescan. Một lượt đang chạy
  thì lần về trước mặt kế không mở lượt mới.
- Hash nhanh như FS-19.03 §2. Hash đầy đủ **chỉ** cho file server có hash nhanh trùng một file gốc Photos — không băm
  cả NAS. *Vì* 500 GB qua Wi‑Fi là nhiều giờ, và file không có ứng viên thì không đổi kết quả.
- Một lệnh tới server một lúc mỗi connection; Backup và kiểm dùng chung hàng đợi đó, Backup đi trước.

## 6. Backup ghi sẵn

- Backup (FS-22) đẩy một file vào folder nằm trong một nguồn server → ghi luôn bản sao server **có hash đầy đủ** (băm từ
  file tạm đang có trên máy). Ảnh vừa backup có trên F ngay, không đọc lại NAS.

## 7. Khi nào chạy

| Việc | Điều kiện |
|---|---|
| Liệt kê, hash nhanh, hash đầy đủ phía server; tải bản gốc iCloud để băm | connection có job Backup → Only on Wi‑Fi / Only While Charging của job đó; không có job → chỉ Wi‑Fi, không cần sạc |
| Nền | tác vụ xử lý nền + tác vụ tiếp tục của iOS 26, dùng chung khung chạy nền của Backup (FS-22.02 §3) |
| Mở app | chạy tiếp ngay khi về trước mặt |

Chốt N1 (người dùng 2026-10-25): **Use Cellular Data for Indexing** chỉ còn áp cho index Photos; mọi việc với server
theo bảng trên (sửa FS-19.03 §2).

## 8. Smart album

- Điều kiện **Source** với nguồn server/thư mục có thêm dòng **Folder** — trống = cả nguồn; chọn bằng màn duyệt folder
  FS-15.02 §2a, bắt đầu ở Folder của connection. Chip chỉ đọc: `Source: NAS Home › Shared`.
- **is**: có trên folder theo §3. **is not**: mục Photos đã kiểm xong mà thiếu ít nhất một file gốc trên folder.
- **Chưa kiểm xong** (thiếu hash một file gốc, hoặc server có ứng viên chưa băm đầy đủ): không vào **is** lẫn **is not**.
- Album có điều kiện Source-server: dòng trên thanh điều kiện `Checking · 12,408 of 54,920 · 38 GB to download`, lý do
  chờ nếu có (`Waiting for Wi‑Fi`, `Waiting for space`, `NAS Home isn't reachable`); xong thì `Checked 3 min ago`.

## 9. Dấu lưới và Photo Info

- Glyph "trên server" của FS-15.02c giữ hình, **đổi nghĩa**: mục có trên ít nhất một nguồn server theo §3 (không còn
  theo lịch sử upload). VoiceOver "On server".
- Photo Info: mục **On Server** — mỗi bản sao một dòng `NAS Home`, dưới là đường dẫn; mục lịch sử **Uploaded to Server**
  giữ nguyên.

## 10. Xoá

- Xoá bản Photos của một mục mà nó **dựa vào** bản server (mọi lối xoá, không riêng album này): ngay trước khi gọi Photos,
  hỏi server từng file đã khớp còn đúng đường dẫn, đúng cỡ không.
- File mất → mục đó **không** bị xoá; alert sau lượt: "2 photos weren't deleted — they're no longer on NAS Home." +
  danh sách. Server không với tới → không xoá mục nào dựa vào nó: "Can't reach NAS Home. Nothing was deleted."
- Hộp xác nhận thêm câu: "They move to Recently Deleted. iCloud space is freed after Recently Deleted is emptied."
- Chốt N2 (người dùng 2026-10-25): kiểm lại ở **mọi** lối xoá — Library, album, Free Up Space, Delete Rejected. *Vì*
  câu "They stay in ShotDex from NAS Home" của 03 §8 phải đúng.

## 11. Board

Chưa vẽ: dòng Folder trong `PH_/IP_/DI_/DC_SmartAlbumEditor`; dòng Checking trên `PH_SmartAlbum` và bản iPad/Duo; mục
On Server trong Photo Info; alert §10. Vẽ trước khi code (luật design-đi-cùng-code).
