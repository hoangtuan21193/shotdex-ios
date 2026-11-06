# FS-06.11 — Điều kiện "Shared Library"

`FS-06.11` · tier A · `Core/Models/SmartAlbumQuery.swift` · `Domain/Indexing/IndexPipeline.swift` ·
`Domain/Deletion/MixedDeletionPlan.swift` · cập nhật 2026-11-04

**Một câu:** smart album và bộ lọc phân biệt được ảnh trong **iCloud Shared Library** với ảnh trong **Personal
Library**. Hộp xoá nói rõ ảnh Shared Library sẽ mất **cho mọi người** tham gia. Spec này **chỉ đi tiếp nếu spike
AC-1 tìm ra API công khai**. Không có thì đóng intent.

Nguồn: [intent 2026-11-04-smart-album-shared-library](../../_intents/2026-11-04-smart-album-shared-library.md).
Liền kề: [08 Smart Album](08-smart-albums.md) · [10 Bản gốc trên máy](10-original-on-device.md) · luồng xoá
[FS-19.04 §2](../FS-19-photo-sources/04-deleting-and-duplicates.md) · cổng xoá [FS-19.07 §9](../FS-19-photo-sources/07-on-server-check.md).

## 1. Người dùng cần gì

Hai vợ chồng dùng chung một Shared Library. Mỗi người gom ảnh *đã có trên NAS* rồi xoá để lấy lại chỗ iCloud. Một ảnh
Shared Library bị xoá trên máy này thì máy kia cũng mất. Người dùng cần thấy ranh giới đó *trước* khi bấm xoá.

## 2. Phạm vi

**Có (nếu spike thành công):**
- Trường **Library** trong bộ dựng điều kiện, giá trị *Personal* / *Shared*, phép *is* và *is not*.
- Mục trong menu Filter nhanh, như FS-06.10.
- Một câu cảnh báo trong hộp xác nhận xoá khi lựa chọn có ảnh Shared Library.

**Cố ý không có:**
- Đoán bằng tín hiệu gián tiếp (ai chụp, album hệ thống, thời điểm thêm vào). Vì: đoán sai ở chỗ xoá còn tệ hơn là
  không có gì.
- Cảnh báo chung chung khi không biết ảnh nào là ảnh chung (người dùng chốt 2026-11-04: không đọc được thì đóng).
- Chuyển ảnh giữa hai thư viện. PhotoKit không có API cho việc này
  ([restore-from-nas-to-album](../../_intents/2026-10-24-restore-from-nas-to-album.md)).

## 3. Spike trước

| Bước | Cách | Đạt khi |
|---|---|---|
| 1 | Đọc header Photos của SDK mới nhất (iOS 27.x, macOS) và tài liệu Apple | thấy một thuộc tính, kiểu collection hay tuỳ chọn fetch nào gắn với Shared Library |
| 2 | Trên máy thật của người dùng đã bật Shared Library: fetch với từng tuỳ chọn tìm được | tách đúng ảnh chung và ảnh riêng, so với app Photos (bộ lọc Library của Photos) |
| 3 | Ghi kết quả vào `docs/_intents/` | có số: bao nhiêu ảnh mỗi bên, khớp app Photos bao nhiêu % |

Simulator không có Shared Library, nên spike chỉ chạy trên máy thật. Đã biết (2026-11-04): SDK iOS 27.1 chỉ có các loại
nguồn *User Library*, *Cloud Shared* (đó là Shared Albums) và *iTunes Synced*. Chưa thấy gì cho Shared Library.

## 4. Hành vi (khi spike thành công)

- Trạng thái thư viện đọc được ngay lúc index. Mỗi lần index lại đọc lại, nên nó là cột suy ra được từ ảnh
  ([BD-02](../../01-basic-design/BD-02-database-design.md)).
- Hộp xoá: lựa chọn có N ảnh Shared Library thì thêm một câu *"N are in the Shared Library and will be deleted for
  everyone in it."* Trường hợp hộp hệ thống là hộp duy nhất (lựa chọn chỉ có ảnh Photos) thì ShotDex hiện hộp của
  mình trước.
  - Hộp thêm này chỉ chèn khi lựa chọn có ít nhất một ảnh Shared Library (người dùng chốt 2026-11-04).
- **Tên:** trường **Library**, giá trị *Personal* / *Shared*, theo chữ của app Photos (người dùng chốt 2026-11-04).

## 5. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | (spike) iPhone thật của người dùng, Shared Library bật | chạy §3 | báo cáo có hoặc không có API. Có: số ảnh mỗi bên khớp app Photos 100%. Không: intent thành `dismissed`, ghi lý do | ⚠️ chưa có — spike |
| AC-2 | 100 ảnh: 30 Shared, 70 Personal | album *Library is Shared* | *Matches 30 photos*; *is Personal* ra 70 | ⚠️ chưa có |
| AC-3 | ảnh chuyển từ Personal sang Shared trong app Photos | lần index kế | ảnh rời *Personal*, vào *Shared* | ⚠️ chưa có — máy thật |
| AC-4 | chọn 5 ảnh, 2 ảnh Shared | Delete | hộp ShotDex có câu *"2 are in the Shared Library and will be deleted for everyone in it."* trước hộp hệ thống | ⚠️ chưa có |
| AC-5 | chọn 5 ảnh Personal | Delete | không có câu cảnh báo, không có hộp thêm | ⚠️ chưa có |
| AC-6 | album *Source is NAS Home* VÀ *Library is Shared*, trên Mac | ⌘⌫ | `NSAlert` có câu cảnh báo như AC-4 | ⚠️ chưa có — Mac |
| AC-7 | iPhone, iPad, Duo, Mac | mở editor, menu Filter, hộp xoá | khớp board, lệch ≤ 2pt | ⚠️ chưa có — `design-parity` |

**Chưa chứng minh được:** AC-1…AC-7. AC-2…AC-7 chỉ còn hiệu lực nếu AC-1 tìm ra API.
