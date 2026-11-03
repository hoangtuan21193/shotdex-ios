# Intent: Smart album "trong Shared Library" — biết ảnh nào là của chung trước khi xoá

| Trường | Giá trị |
|---|---|
| Tác giả | Hoang Tuan (người dùng) · Claude soạn |
| Ngày | 2026-11-04 |
| Trạng thái | accepted (2026-11-04, người dùng chốt các câu hỏi qua lựa chọn trong phiên) |
| Tiến độ | **chưa làm** (2026-11-04) — spec FS-06.11, 7 AC; chờ spike AC-1 trên máy thật |
| Nguồn | phản hồi người dùng (2026-11-04, trong phiên kiểm luồng xoá của smart album "có trên NAS") |
| Spec sinh ra từ đây | [FS-06.11](../02-functional-spec/FS-06-collections/11-shared-library.md) |

Intent anh em: [2026-11-04-smart-album-local-original](2026-11-04-smart-album-local-original.md).

## Problem — vấn đề

Gia đình người dùng có kế hoạch giải phóng iCloud ([smart-album-on-nas](2026-10-24-smart-album-on-nas.md), bước 4–5):
gom ảnh đã có trên NAS rồi xoá khỏi máy. Sau này sẽ dùng iCloud Shared Library. Hôm nay người dùng **không phân biệt
được, trong ShotDex, ảnh nào nằm trong Shared Library và ảnh nào nằm trong Personal Library**.

- Việc này quan trọng khi xoá. Xoá một ảnh trong Shared Library là xoá nó cho **mọi người** tham gia (vợ/chồng cũng
  mất), không chỉ trên máy mình. Smart album "có trên NAS" mà lẫn ảnh Shared Library thì một lần xoá đụng cả thư viện
  của người kia. ShotDex hôm nay không cảnh báo gì (luồng xoá: `SmartAlbumDetailScreen.swift:485`, `PhotoDeletionGate`).
- Smart album và bộ lọc Library không có điều kiện này (`SmartAlbumQuery.swift:33-70`, `FilterCriteria.swift:112-160`).
  Database không có cột này, và không chỗ nào đọc nó.
- **SDK có thể không cho đọc.** Trong SDK iOS 27.1, `PHAssetSourceType` chỉ có `UserLibrary`, `CloudShared` (đó là
  Shared *Albums*, không phải Shared Library) và `iTunesSynced` (`PhotosTypes.h:205-209`, tìm ngày 2026-11-04). Không
  có thuộc tính công khai nào cho biết ảnh thuộc thư viện nào, hay ai đã thêm nó. Intent
  [restore-from-nas-to-album](2026-10-24-restore-from-nas-to-album.md):19 cũng ghi PhotoKit không có API đưa ảnh vào
  Shared Library.

Mức độ: cao khi đã bật Shared Library, vì xoá nhầm làm mất ảnh của người khác. Hôm nay gia đình chưa bật nó (bước 5
chưa tới), nên chưa ai bị ảnh hưởng.

## Proposed outcome — kết quả mong muốn

1. Smart album có điều kiện **Library** *is* Personal / Shared, kết hợp được với "có trên NAS". Có trên iPhone, iPad và
   Mac.
2. Ảnh Shared Library đi vào lệnh xoá thì hộp xác nhận nói rõ ảnh sẽ mất cho mọi người tham gia.
3. Nếu PhotoKit không có cách nào đọc được, kết quả mong muốn là **nói rõ điều đó** (trong spec và trong `docs/`) rồi
   đóng intent. Không đoán bằng heuristic có thể sai, vì một heuristic sai ở chỗ xoá còn tệ hơn là không có gì.

## Affected users and systems — phạm vi ảnh hưởng

- Màn hình: Smart Album editor, màn smart album, các hộp xác nhận xoá (`PhotoDeletionFlow`, `SourceDeletionFlow`), có thể
  cả bộ lọc Library.
- Thiết bị: iPhone · iPad · Duo · Mac.
- Tầng code: Data/Sources (đọc từ PhotoKit lúc index), Database (cột mới, `SmartAlbumSQLBuilder`), Domain/Deletion
  (`MixedDeletionPlan`, lời cảnh báo).
- Dữ liệu đã lưu: một cột đo được trong `photo_metadata`, do indexer ghi lại mỗi lần chạy.

## Constraints — ràng buộc

- Chỉ dùng API công khai. Không đọc trực tiếp database của Photos, không dùng API riêng (App Review, và nó có thể đổi
  mà không báo).
- Không suy ra từ các tín hiệu gián tiếp (album hệ thống, người chụp, thời gian thêm vào) nếu không chứng minh được là
  chúng đúng trên thư viện thật.
- Không đổi hành vi xoá hiện có cho ảnh Personal.

## Open questions — câu hỏi còn treo

**Đã trả lời (người dùng, 2026-11-04):** Q1 spike trên máy thật · Q2 **không** làm cảnh báo dự phòng: không đọc được thì
đóng intent · Q3 gia đình đã hoặc sắp bật Shared Library, nên có máy thật để chạy spike.

1. **PhotoKit có cách nào công khai để biết ảnh thuộc Shared Library không?** Chẳng hạn một smart album hệ thống, một
   `PHAssetCollectionSubtype`, hay `PHFetchOptions` lọc được theo thư viện. Cũng cần xem iOS 27 có thêm gì không.
   Mặc định đề xuất: một spike ngắn (đọc header và tài liệu, rồi thử trên máy thật có Shared Library). Không có cách thì
   đóng intent (`dismissed`) với lý do ghi rõ. → spike trên máy thật của người dùng; simulator không có Shared Library.
2. **Nếu không đọc được, có muốn chặn ở phía xoá không?** Ví dụ hộp xoá luôn nhắc *"Photos in a Shared Library are
   deleted for everyone in it"* khi tài khoản có bật Shared Library. Phần này cũng cần biết Shared Library có đang bật
   không, nên có thể cũng không làm được. Mặc định đề xuất: chỉ làm nếu spike tìm ra cách biết Shared Library có đang bật
   hay không. → spike, rồi người dùng.
3. **Gia đình bật Shared Library vào lúc nào?** Nếu còn xa, intent này có thể chờ. → người dùng.

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
