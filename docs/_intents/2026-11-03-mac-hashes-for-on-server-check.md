# Intent: Mac băm SHA-256 thay iPhone, iPhone chỉ đọc — kiểm "đã có trên NAS" không phải tải

| Trường | Giá trị |
|---|---|
| Tác giả | Hoang Tuan (người dùng) · Claude soạn |
| Ngày | 2026-11-03 |
| Trạng thái | accepted (2026-11-03, người dùng duyệt trong phiên; phạm vi v1 chỉ FS-19.07 theo đề xuất) |
| Tiến độ | **đang làm** (2026-11-03) — task 1/8, 1/15 AC xanh; spec FS-19.07 §12; plan [2026-11-03-fs1907-shared-hashing](../_plans/2026-11-03-fs1907-shared-hashing.md) |
| Nguồn | phản hồi người dùng (2026-11-03, trong phiên FS-19.08) |
| Spec sinh ra từ đây | [FS-19.07 §12](../02-functional-spec/FS-19-photo-sources/07-on-server-check.md#12-băm-dùng-chung--mac-băm-hộ-máy-khác-chỉ-đọc-2026-11-03) · [07b §4](../02-functional-spec/FS-19-photo-sources/07b-on-server-check-ac.md#4-băm-dùng-chung-12) |

## Bối cảnh

Smart album "Source is NAS Home › Shared" ([FS-19.07](../02-functional-spec/FS-19-photo-sources/07-on-server-check.md))
cho biết từng ảnh trong Photos đã có bản **giống từng byte** trên một folder của NAS hay chưa, để xoá khỏi Photos mà
không mất gì. Kết quả dựa trên SHA-256 cả file ở **hai phía**:

- **Phía NAS:** liệt kê tên, cỡ và ngày sửa thì rẻ. Chỉ file cùng cỡ với một bản gốc trong Photos mới bị tải về để băm
  (§5). File do Backup đẩy lên thì lấy SHA từ sổ Backup và sổ chung `.shotdex/backup-index/*.jsonl` trong folder đích
  ([`BackupContentIndex`](../../ShotDex/Domain/Backup/BackupContentIndex.swift)), không đọc file.
- **Phía Photos:** SHA từng file gốc nằm trong bảng `copy_files` của **từng máy**
  ([`AppDatabase+OnServer.swift`](../../ShotDex/Data/Database/AppDatabase+OnServer.swift)). Có sẵn khi sổ Backup đã
  ghi; còn không thì máy phải **tải bản gốc từ iCloud** để băm (§4).

Index chia sẻ qua iCloud ([intent 2026-11-02-icloud-shared-index](2026-11-02-icloud-shared-index.md),
[BD-03.05](../01-basic-design/BD-03-metadata-indexing-flow/05-shared-index.md)) hôm nay chỉ chia sẻ EXIF và địa điểm.
Intent đó ghi rõ "hash ảnh để sau". Mac đã chạy kiểm FS-19.07 trong helper (§11), có bản gốc ở máy, nên tự băm được.

## Problem — vấn đề

- **iPhone phải tải lại cả thư viện từ iCloud chỉ để băm.** Máy thật của người dùng bật Optimize Storage. Mỗi ảnh có
  ứng viên cùng cỡ trên NAS đều phải tải bản gốc về; video thì tải nguyên file. Lượt đầu với 55k ảnh mất nhiều giờ, tốn
  4G hoặc Wi‑Fi, và tốn chỗ trống tạm (`Waiting for space`). iPad làm lại đúng việc đó một lần nữa.
- **File trên NAS do script hay công cụ khác chép thì phải tải về để băm.** Chỉ folder Backup đẩy lên mới có sổ SHA.
  Người dùng gộp ảnh bằng script (intent `2026-10-24-smart-album-on-nas`), nên phần lớn NAS không có sổ. iPhone qua
  Wi‑Fi đọc NAS chậm hơn nhiều so với Mac cắm dây trong nhà.
- **Mỗi máy băm lại từ đầu những gì máy khác đã băm.** Mac đã có SHA của cả thư viện và cả NAS, iPhone và iPad vẫn băm
  lại, cài lại app thì băm lại.

Ảnh hưởng: người dùng có Mac cùng iPhone/iPad chung iCloud Photos và dùng smart album "đã có trên NAS" để giải phóng
iCloud. Nặng nhất là iPhone có thư viện lớn.

## Proposed outcome — kết quả mong muốn

- **Mac làm phần nặng:**
  - Lúc index thư viện (hoặc lúc kiểm FS-19.07), Mac băm SHA-256 từng file gốc của từng ảnh iCloud Photos.
  - Mac băm mọi file trong các folder nguồn server, không chỉ file do Backup đẩy lên.
- **(A) Sổ SHA trên NAS:** Mac ghi sổ SHA cho các folder nguồn server, theo kiểu sổ `.shotdex` của Backup. Máy nào đọc
  NAS cũng dùng được sổ đó, kể cả khi không có iCloud.
- **(C) Chia sẻ qua iCloud:** SHA của cả hai phía (file NAS theo đường dẫn + cỡ + ngày sửa, file Photos theo ảnh + ngày
  sửa ảnh) đi qua index chia sẻ trên CloudKit tới mọi iPhone/iPad cùng iCloud.
- **Trên iPhone/iPad, sau khi Mac đã làm xong:**
  - Smart album "đã có trên NAS" đủ kết quả trong vài phút.
  - Không tải bản gốc nào từ iCloud.
  - Không tải file nào từ NAS; chỉ liệt kê để so cỡ và ngày sửa.
- **Ảnh hay file đổi sau khi Mac băm** (ngày sửa lệch): máy đó tự băm lại như hôm nay; dữ liệu cũ không bao giờ được
  dùng.
- **Xoá vẫn an toàn như hôm nay:** trước khi xoá, app vẫn hỏi lại server đúng đường dẫn, cỡ và ngày sửa
  (FS-19.07 §9). Thêm: iPhone tự băm lại vài file ngẫu nhiên mỗi lượt để kiểm SHA nhận từ Mac.
- **Không có Mac, hoặc Mac chưa làm tới:** app chạy như hôm nay, tự băm.

## Affected users and systems — phạm vi ảnh hưởng

- Tính năng: kiểm FS-19.07, smart album Source có Folder, dòng tiến độ, cổng xoá. Thêm phần chia sẻ index BD-03.05.
- Thiết bị: Mac làm và gửi; iPhone, iPad, Duo nhận. Mọi máy vẫn tự băm được những gì chưa có.
- Code:
  - Data: `OnServerCheck`, `copy_files`, `IndexShareService` / `SharedIndexStore` (CloudKit, zone `SharedIndex`),
    `BackupContentIndex` (sổ trên NAS).
  - Mac: helper `MacAgent` (FS-22.06).
  - Domain: luật tin SHA từ máy khác.
- Server: **ghi thêm file** (sổ SHA) vào các folder nguồn của người dùng trên NAS, không chỉ folder đích Backup.
- Dữ liệu đã lưu:
  - `copy_files` cần ghi nguồn gốc SHA mới (`origin`: thêm "từ máy khác" bên cạnh `backup` · `hashed`).
  - CloudKit thêm kiểu bản ghi. App chưa release nên không cần tương thích ngược.

## Constraints — ràng buộc

- **Quyết định xoá chỉ dựa trên SHA-256 cả file** và chỉ khi khoá còn khớp: file NAS theo đường dẫn + cỡ + ngày sửa,
  ảnh Photos theo ngày sửa ảnh. Tên, cỡ hay ngày chụp không bao giờ đủ.
- Không bỏ bước hỏi server trước khi xoá (§9).
- Chỉ CloudKit **private database** của người dùng. Không có server ShotDex, không thêm dependency.
- Sổ trên NAS chỉ nằm trong thư mục ẩn `.shotdex/`. Mỗi máy chỉ ghi phần của mình, như sổ Backup, vì SMB và WebDAV
  không có khoá file. Không bao giờ sửa hay xoá file ảnh của người dùng.
- Băm trên Mac không được làm chậm Backup hay index EXIF. Phải theo cổng FS-22 (khoá connection: Backup đi trước, một
  lệnh một lúc) và luật chỗ trống.
- Mạng hay CloudKit lỗi thì mọi máy vẫn chạy như hôm nay.
- Widget và extension không đụng tới.

## Open questions — câu hỏi còn treo

Đã trả lời (người dùng 2026-11-03):

1. **Sổ trên NAS (A):** **một sổ ở gốc mỗi nguồn server**, thư mục ẩn `.shotdex/`, cho cả cây folder, cùng kiểu sổ
   Backup. Đây là ngoại lệ có chủ ý của luật FS-19 "không ghi gì lên nguồn server" (§3, D6). Spec phải ghi rõ ngoại lệ
   này.
2. **Tin SHA từ máy khác:**
   - Khoá phải khớp, và trước khi xoá app vẫn hỏi lại server như §9.
   - **Thêm kiểm ngẫu nhiên:** mỗi lượt, iPhone tự băm lại vài file lấy SHA từ Mac.
   - Một file lệch thì iPhone bỏ hết SHA của máy đó và tự băm.
3. **Mac chưa có bản gốc** (Mac cũng bật Optimize Storage): Mac **tải về để băm rồi xoá ngay** bản tải tạm, như iPhone
   đang làm (thư mục tạm, một file một lúc). Bản ở Photos trên Mac vẫn tối ưu như cũ.
4. **iPhone kiểm khi Mac chưa băm tới:** **iPhone tự băm** như hôm nay. Máy nào băm trước thì chia sẻ cho máy kia.

Còn mở:

5. **Khoá ảnh Photos giữa các máy:**
   - Id ảnh khác nhau trên mỗi máy, nên phải ánh xạ qua `cloudIdentifier`.
   - Ngày sửa ảnh có trùng giữa Mac và iPhone không: spike còn mở của BD-03.05.
   - Bản sửa (edit render) tải qua iCloud có **cùng byte** trên hai máy không.
   - Trả lời bằng spike trên máy thật, ở bước `/spec` (07b §1 đã có mục spike).
6. **Phạm vi v1:** chỉ những gì kiểm FS-19.07 cần (chưa hỏi người dùng).
   - Đề xuất: chỉ FS-19.07, để sau phần chia sẻ SHA cho Duplicates "trùng byte" và FS-19.08.
   - Người dùng xác nhận khi duyệt intent.

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
