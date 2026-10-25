# FS-19.07 — Ảnh Photos đã có trên server chưa

`FS-19.07` · tier B (smart album, lưới, Photo Info) · mã có sẵn: `Data/Sources/PhotosContentHashPass.swift`,
`Data/Sources/FileServer/ServerSourceIndexer.swift`, `Data/Database/SmartAlbumSQLBuilder.swift`,
`Data/Sources/Folders/DeletionService.swift` · AC + spike: [07b](07b-on-server-check-ac.md) · cập nhật 2026-10-25

**Một câu:** ShotDex biết chắc từng ảnh/video trong Photos có bản **giống hệt từng byte** trên một folder của nguồn
server hay chưa — kể cả file do công cụ khác chép, hay bị script dời, đổi tên — và kiểm lại NAS trước khi xoá.

Nguồn: [intent 2026-10-24-smart-album-on-nas](../../_intents/2026-10-24-smart-album-on-nas.md) · người dùng 2026-10-25:
dựa trên nguồn FS-19 · Folder trong điều kiện · một dấu lưới · N1, N2 · sau phản biện: SHA-256 cả file, lọc theo cỡ,
ảnh đã sửa cần bản sửa trên NAS, hai đợt, có *Delete Anyway* khi NAS tắt.

## 1. Người dùng cần gì

- iCloud đầy; bản gốc nằm trên NAS — do Backup FS-22, do script gộp của người dùng, hay chép bằng công cụ khác.
- Cần album "ảnh trên máy này đã có trên `NAS › iCloud Photo/Shared`" để xoá khỏi Photos mà không mất gì.
- Hàng chục nghìn mục: kiểm phải tự chạy, dừng ở đâu làm tiếp ở đó, và tải từ iCloud càng ít càng tốt.

## 2. Phạm vi và hai đợt

| Đợt | Có |
|---|---|
| 1 — xoá được an toàn | hash theo từng file gốc · lấy lại SHA của Backup · lọc theo cỡ · kiểm khi app ở trước mặt · Folder trong Source · chưa kiểm · dòng tiến độ · cổng xoá ở smart album, Free Up Space, Library |
| 2 — sau khi đo S3 | chạy nền · ghép Live Photo trên nguồn thư mục/server (ảnh + MOV cùng tên gốc trong một folder là một Live Photo) · dấu lưới theo hiện trạng · Photo Info On Server · cổng xoá ở mọi lối còn lại · gộp Photos ↔ server để hiển thị |

**Cố ý không có:**
- Tìm/gộp ảnh trùng, dời hay xoá file trên NAS — *vì* script của người dùng làm (intent).
- Bản cùng điểm ảnh nhưng metadata khác (app khác nhúng XMP), bản nén lại — **không** tính là có. *Vì* cỡ khác nên không
  lọc được, bắt nó phải tải cả thư viện; và xoá theo nó có thể mất ngày chụp, GPS. Duplicates FS-06.06 lo phần giống hình.
- File hash do script ghi sẵn trên NAS — để sau; đợt 1 ShotDex tự đọc ứng viên.
- Đưa ảnh từ NAS về Photos — intent `2026-10-24-restore-from-nas-to-album`.

## 3. Khớp

- **Hash:** SHA-256 của **cả file**, cho từng file gốc — cùng loại hash Backup đã ghi. Khác một byte là khác.
- Một mục Photos **có trên folder F của nguồn S** khi mỗi file sau có một file trong F (mọi tầng con) cùng SHA-256:
  ảnh · RAW của RAW+JPEG · video đi kèm Live Photo · video · và, nếu mục **đã sửa** trong Photos, **bản sửa** (ảnh, video).
- Mục đã sửa mà bản sửa chưa có trên NAS → **không** có trên F; tiến độ và hộp xoá gọi tên: *"Edited — edit not on NAS
  Home"*. Bản sửa lên NAS khi job Backup bật **Include Edited Versions** (FS-22.01 §2).
- Kiểm **không phụ thuộc** việc gộp ảnh của FS-19 (§02): đọc thẳng bảng hash theo file. Gộp chỉ để hiển thị (đợt 2), và
  không bao giờ ghi sidecar lên NAS vì một lần kiểm.

## 4. Hash phía Photos

- **Đã có từ Backup:** sổ Backup có SHA-256 từng file gốc nó đã chép, theo dấu nguồn. Dấu nguồn còn khớp → dùng luôn,
  không tải. Đây là phần lớn thư viện của người dùng có Backup.
- **Chưa có:** cỡ từng file gốc lấy từ Photos không cần tải. Chỉ mục có **ít nhất một file trên NAS cùng cỡ** mới được tải
  bản gốc để băm; mục không có ứng viên nào thì đã biết là *không có*, không tải. Photos không báo cỡ một file (hiếm) →
  file đó là ứng viên khi nguồn server có file nào đó.
- Tải: thư mục tạm, **một file một lúc**, băm theo khối 1 MB, xoá ngay; không giữ cả file trong RAM; video đọc luồng.
- Còn trống − cỡ file < 2 GB → chờ, `Waiting for space` (luật FS-22).
- Mỗi file băm xong ghi ngay → bị dừng ở đâu làm tiếp ở file kế. Mục mới nhất trước. Đọc hỏng → ghi lỗi, đi tiếp, lượt sau
  mới thử lại — mục hỏng không chặn hàng.
- `.limited`: chỉ mục được cấp; dòng tiến độ thêm "Only photos ShotDex can access are checked."

## 5. Hash phía server

- Liệt kê cây (tên, cỡ, ngày sửa): **mỗi lần app về trước mặt**, khi server về lại, khi bấm Rescan; một lượt đang chạy thì
  không mở lượt mới.
- **Ứng viên** = file có cỡ bằng cỡ một file gốc Photos chưa khớp. Chỉ ứng viên được đọc trọn (tải ra file tạm rồi băm).
  Kết quả nhớ theo đường dẫn + cỡ + ngày sửa; file dời/đổi tên nối bằng hash nhanh + cỡ, không băm lại.
- **Backup ghi sẵn:** Backup đẩy file vào folder nằm trong nguồn → lượt quét nguồn lấy SHA-256 trong sổ Backup (bản đã
  đẩy và đọc lại) và sổ chung `.shotdex` (file của máy khác) cho file cùng đường dẫn + cỡ, không đọc file. Ảnh vừa
  backup có trên F ngay, không đọc lại NAS.
- Mỗi connection **một lệnh một lúc**, dùng chung với Backup và Upload; Backup đi trước; kiểm nhả khoá giữa các file và
  không giữ khoá trong lúc tải iCloud.

## 6. Khi nào chạy

| Việc | Điều kiện |
|---|---|
| Liệt kê, băm phía server; tải iCloud để băm | job Backup của connection: Only on Wi‑Fi / Only While Charging, nhiều job thì **khắt nhất**; không có job → chỉ Wi‑Fi. **Use Cellular Data for Indexing** chỉ còn cho index Photos |
| Đợt 1 | khi app ở trước mặt; về trước mặt thì chạy tiếp |
| Đợt 2 | thêm tác vụ nền (xử lý nền + tác vụ tiếp tục iOS 26), sau khi S3 cho số |

## 7. Smart album

- Điều kiện **Source** với nguồn thư mục/server có dòng **Folder** — trống = cả nguồn; chọn bằng màn duyệt folder
  FS-15.02 §2a. Chip chỉ đọc ghi **tên** nguồn: `Source: NAS Home › Shared`.
- **is**: có trên folder theo §3. **is not**: đã kiểm xong và thiếu ít nhất một file.
- **Chưa kiểm xong** (một file gốc chưa có hash mà NAS có ứng viên cùng cỡ chưa băm): không vào **is** lẫn **is not**.
- Chỉ mục **có bản Photos** được đếm: ảnh riêng của NAS (dòng của nó trong Library) không vào album — album là danh sách
  mục xoá được khỏi Photos. Nguồn thư mục/ổ đĩa giữ nghĩa cũ (FS-19.04 §5: có bản ở đó, đang có, không ẩn), thu hẹp theo
  Folder. Mục đã đổi trong Photos sau lần liệt kê file cuối thì chờ liệt kê lại, không vào **is** lẫn **is not**.
  Mã: `OnServerPresenceSQL.swift`, gọi từ `SmartAlbumSQLBuilder.sourceClause`.
- Thanh điều kiện: `Checking · 12,408 of 54,920 · 38 GB to download`; lý do chờ (`Waiting for Wi‑Fi`, `Waiting for space`,
  `NAS Home isn't reachable`, `Open ShotDex to continue` ở đợt 1); xong thì `Checked 3 min ago`.

## 8. Dấu lưới và Photo Info (đợt 2)

- Glyph "trên server" của FS-15.02c giữ hình, đổi nghĩa: mục có trên ít nhất một nguồn server theo §3. Tới khi đợt 2
  xong, glyph giữ nghĩa cũ (lịch sử upload). VoiceOver "On server".
- Photo Info: mục **On Server** — mỗi file khớp một dòng `NAS Home` + đường dẫn; mục Uploaded to Server giữ nguyên.

## 9. Xoá

- **Dựa vào server** = mục đang có trên ít nhất một folder server theo §3. Chỉ những mục đó qua bước kiểm; mục khác xoá
  như cũ.
- Ngay trước khi gọi Photos: hỏi server từng file đã khớp — còn đúng đường dẫn, đúng cỡ, đúng ngày sửa. Lệch đường dẫn →
  tìm lại bằng hash nhanh + cỡ trong cùng nguồn trước khi coi là mất. Không băm lại lúc xoá.
- File mất hay đổi → mục đó **không** bị xoá; alert sau lượt: "2 photos weren't deleted — they're no longer on NAS Home."
- Server không với tới → alert "Can't reach NAS Home" + "ShotDex couldn't check that these are still on NAS Home." ·
  **Delete Anyway** (đỏ) · **Cancel**. Mục không dựa vào server trong cùng lượt vẫn xoá.
- Xoá bản Photos **không bao giờ** ẩn hay đụng bản server; mục còn trong Library qua bản NAS.
- Hộp xác nhận thêm: "They move to Recently Deleted. iCloud space is freed after Recently Deleted is emptied."
- Đợt 1 nối cổng vào xoá ở smart album, Free Up Space, chọn-rồi-xoá ở Library; một test chặn mọi lời gọi xoá PhotoKit
  mới nằm ngoài cổng. Đợt 2 nối mọi lối còn lại (N2: mọi lối xoá).
- Ngoài phạm vi: file trên NAS hỏng âm thầm sau khi đã băm.

## 10. Board

Dòng Folder: `PH_/IP_/DI_/DC_SmartAlbumEditor` · dòng tiến độ + chip Source: `PH_/IP_/DI_/DC_SmartAlbum` (vẽ
2026-10-25). Alert sau xoá và alert *Delete Anyway* là alert hệ thống, không vẽ — chữ ghi trong comment của
`PH_/IP_/DI_DeleteCopies`. Mục On Server trong Photo Info vẽ ở đợt 2.
