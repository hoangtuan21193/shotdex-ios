# Intent: Smart album tự đồng bộ thành album thật trong Photos — để Move to Shared Library

| Trường | Giá trị |
|---|---|
| Tác giả | Hoang Tuan (người dùng) · Claude soạn |
| Ngày | 2026-11-06 |
| Trạng thái | accepted (2026-11-06) |
| Tiến độ | **đang làm** (2026-11-06) — spec FS-06.12, 17 AC; board vẽ (`74008bba`); plan [2026-11-06-also-on-server-keep-in-photos](../_plans/2026-11-06-also-on-server-keep-in-photos.md), task 8/11, 11/17 AC xanh (AC-4, 12 còn phần kích hoạt và main thread); AC-1 cần iPhone thật |
| Nguồn | phản hồi người dùng (2026-11-06): "muốn hiện những ảnh có cả ở iCloud và NAS, sau đó move all ảnh trong album đó vào shared library của iCloud" |
| Spec sinh ra từ đây | [FS-06.12](../02-functional-spec/FS-06-collections/12-photos-album-sync.md) |

Intent anh em: [2026-11-06-also-on-nas-condition](2026-11-06-also-on-nas-condition.md) (điều kiện "Also on Server" tạo ra album này),
[2026-11-04-smart-album-shared-library](2026-11-04-smart-album-shared-library.md) (biết ảnh nào đã ở Shared Library),
[2026-10-24-restore-from-nas-to-album](2026-10-24-restore-from-nas-to-album.md) (cũng dùng album làm cầu nối sang Photos).

## Problem — vấn đề

Người dùng muốn đưa mọi ảnh "có ở cả iCloud lẫn NAS" vào **iCloud Shared Library** của gia đình. ShotDex tìm ra được
những ảnh đó (smart album FS-19.07), nhưng **không đưa chúng tới chỗ làm được Move to Shared Library**.

- PhotoKit **không có API** đưa ảnh vào Shared Library, cũng không đọc được ảnh đang ở thư viện nào (SDK iOS 27.1, kiểm
  lại 2026-11-06: không header nào trong `Photos.framework`/`PhotosUI.framework` nhắc tới shared library). Chỉ app Photos
  làm được: chọn ảnh → **Move to Shared Library**.
- Smart album của ShotDex là truy vấn trong database của ShotDex, **không hiện trong app Photos**. Trong Photos không có
  cách nào chọn đúng tập ảnh này.
- Cách duy nhất hôm nay: trong smart album → Select All → Add to Album → album mới (`AddToCollectionSheet`,
  `PhotoLibraryService.createAlbum`/`addAssets`). Nhiều bước, và album đó **đứng yên**: ảnh mới lên NAS sau đó không vào,
  phải làm lại bằng tay và tự nhớ cái nào đã thêm.
- Việc kiểm NAS chạy hàng giờ, nhiều đợt, qua nhiều ngày (FS-19.07 §5) — tập ảnh khớp lớn dần theo thời gian, nên một lần
  "chép sang album" không đủ.

Mức độ: chặn bước 5 trong kế hoạch giải phóng iCloud của gia đình (intent smart-album-on-nas). Hàng chục nghìn ảnh —
không làm tay được.

## Proposed outcome — kết quả mong muốn

1. Trên một smart album, người dùng bật **giữ một album trong Photos** cùng nội dung. ShotDex tạo album thật trong Photos
   (tên gợi ý = tên smart album) và từ đó **tự đồng bộ liên tục**: mỗi lần tập ảnh khớp đổi (kiểm NAS xong một đợt, ảnh
   mới, ảnh bị xoá), album Photos được thêm ảnh mới và bỏ ảnh không còn khớp.
2. Người dùng mở album đó trong app Photos → Select All → Move to Shared Library. Lần sau chỉ cần làm lại với ảnh mới.
3. Người dùng thấy trạng thái đồng bộ ở smart album: album Photos tên gì, có bao nhiêu ảnh, lần cập nhật cuối, lỗi nếu có
   (vd. bị xoá trong Photos, quyền ảnh chỉ là Limited).
4. Tắt đồng bộ thì ShotDex thôi đụng tới album; album còn nguyên trong Photos. Bỏ ảnh khỏi album **không** xoá ảnh.
5. Smart album nào cũng bật được (không riêng Also on Server) — luồng Shared Library chỉ là trường hợp đầu tiên.
6. Trên màn có một dòng hướng dẫn ngắn: muốn đưa vào Shared Library thì mở album này trong Photos → Move to Shared Library.

## Affected users and systems — phạm vi ảnh hưởng

- **Màn:** Smart Album detail (menu + dòng trạng thái), có thể Smart Album editor (bật lúc tạo).
- **Thiết bị:** iPhone · iPad · Duo trong/ngoài. Mac: app Mac có smart album nhưng thư viện Photos trên Mac là chuyện
  khác — cần quyết.
- **Tầng:** Data (`PhotoLibraryService`: tạo album, thêm/bỏ theo lô; theo dõi album bị xoá/đổi tên qua change observer),
  Database (bảng mới nối smart album ↔ `localIdentifier` của album Photos + trạng thái đồng bộ — dữ liệu người dùng chọn,
  không nằm trong `photo_metadata`), Features (Smart Album detail). Chạy nền: theo lượt kiểm On Server (`OnServerCheck`).
- **Dữ liệu đã lưu:** thêm bảng (migration mới). App chưa release → không cần tương thích ngược.
- **Design canvas:** board Smart Album detail trên iPhone/iPad/Duo vẽ thêm phần này trước khi code.

## Constraints — ràng buộc

- Người dùng chốt (2026-11-06): **tự đồng bộ liên tục**, không phải nút chép một lần; **ghi đè** — album Photos luôn bằng smart album (ảnh thêm tay bị bỏ, ảnh bỏ tay được thêm lại); chạy **cả ở nền**, cùng lượt kiểm On Server.
- ShotDex **không bao giờ xoá ảnh** khi đồng bộ — chỉ thêm/bỏ ảnh khỏi album của chính nó.
- Chỉ đụng album ShotDex tạo ra cho việc này (nhận bằng `localIdentifier` đã lưu), không bao giờ sửa album khác của
  người dùng, kể cả album trùng tên.
- Ảnh chưa kiểm xong (không thuộc Yes/No) không vào album.
- Không làm đầy bộ nhớ, không tải bản gốc chỉ để đồng bộ album (thêm vào album không cần dữ liệu ảnh).
- 55.000 ảnh: thêm/bỏ theo lô, không một change request mỗi ảnh; không chặn main thread (NF-01).
- Dữ liệu không rời máy; không dependency mới; nhánh iOS 26 / trước 26.
- Không test bằng ảnh có mặt người.

## Open questions — câu hỏi còn treo

Q3 (ghi đè) và Q6 (cả ở nền) đã trả lời 2026-11-06 — xem Constraints.

| # | Câu hỏi | Ai trả lời | Đề xuất mặc định |
|---|---|---|---|
| Q1 | Sau **Move to Shared Library**, ảnh có giữ `localIdentifier` và còn nằm trong album Photos không? Nếu id đổi, ShotDex thấy ảnh "biến mất" rồi "mới xuất hiện" và có thể thêm/bỏ sai. | đo trên iPhone thật có Shared Library (simulator không có) | spike trong `/spec`, chốt AC sau khi đo |
| Q2 | Ảnh đã Move to Shared Library rồi có nên **bỏ khỏi** album Photos để album chỉ còn "việc phải làm"? PhotoKit không cho đọc ảnh ở thư viện nào (xem intent smart-album-shared-library). | người dùng + spike Q1 | không bỏ — không đọc được thì không đoán |
| Q4 | Người dùng xoá album trong Photos: tắt đồng bộ hay tạo lại? | người dùng | tắt đồng bộ, báo trên smart album |
| Q5 | Quyền Limited: chỉ đồng bộ ảnh được cấp hay không cho bật? | người dùng | không cho bật, giải thích cần Full Access |
| Q7 | Mac có cần không? | người dùng | không trong intent này |

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
