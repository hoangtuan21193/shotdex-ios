# Intent: Common Photos chạy lại chỉ ảnh mới, và tự gom liên tục

| Trường | Giá trị |
|---|---|
| Tác giả | Tuấn (qua Claude) |
| Ngày | 2026-11-03 |
| Trạng thái | accepted (2026-11-03) |
| Tiến độ | **đang làm** (2026-11-03) — task 1/10, 1/15 AC xanh; plan [2026-11-03-fs1908-new-only-and-gather](../_plans/2026-11-03-fs1908-new-only-and-gather.md) |
| Nguồn | phản hồi người dùng 2026-11-03: "chọn lại thư mục A và B, rồi cùng thư mục share, thì làm sao để chạy lại những ảnh mới thôi, không phải chạy lại từ đầu, hoặc phải có chức năng luôn sync liên tục để có ảnh mới là check liền" |
| Spec sinh ra từ đây | [FS-19.08 §6c](../02-functional-spec/FS-19-photo-sources/08-common-photos.md) · AC-159…173 ở [08b](../02-functional-spec/FS-19-photo-sources/08b-common-photos-ac.md) |

## Problem — vấn đề

Hai người backup vào `Tuấn/` và `Vợ/` trên NAS. Họ đã gom phần ảnh chung vào `Shared/` một lần (FS-19.08). Từ đó ảnh mới
cứ vào A và B hằng ngày. Muốn gom tiếp thì hôm nay chỉ có một cách: chọn lại A, B, Shared rồi **Scan lại cả hai cây
từ đầu**. Với 50k ảnh mỗi bên thì:

- Lần nào cũng liệt kê lại toàn bộ cây A và B (`CommonPhotosScanner.list`).
- SHA-256 chỉ được dùng lại khi folder là **nguồn** đã index. `CommonPhotosScanModel.knownHashes` chỉ đọc `copy_files`
  của nguồn server. Folder không phải nguồn bị băm lại mọi file cùng cỡ, tức tải lại hàng GB qua mạng nhà mỗi lần.
- Ảnh chung đã gom ở lượt trước hiện lại trong kết quả, lẫn với vài ảnh mới thật sự. Chế độ Copy coi những ảnh đó là
  Skipped (already there), nhưng vẫn phải hỏi server từng file.
- Không có gì tự chạy. Người dùng phải nhớ quay lại làm tay, và ảnh mới nằm lệch giữa A và B cho tới lúc đó.

Ai bị ảnh hưởng: người dùng Mac có NAS nhiều người cùng backup (FS-19.08 chỉ có trên Mac). Mức độ: tính năng dùng được
một lần, dùng đều thì tốn thời gian và băng thông, nên gần như không ai chạy lại.

## Proposed outcome — kết quả mong muốn

- Gom lại cùng bộ A + B → Shared chỉ xử lý **ảnh mới hoặc đổi từ lượt trước**. Có bao nhiêu ảnh mới thì tốn bấy nhiêu thời
  gian, không phụ thuộc cỡ cả thư viện. Ảnh đã gom không hiện lại, không đọc lại.
- Có thể đặt bộ A + B → Shared ở chế độ **tự gom**: có ảnh mới cùng byte ở mọi folder là nó vào Shared, không cần mở
  sheet. Vẫn giữ mọi bảo đảm của FS-19.08: kiểm SHA trước khi xoá, log từng file, hoàn tác được.
- Người dùng thấy bộ nào đang được theo dõi, lần cuối kiểm lúc nào, đã gom thêm bao nhiêu, và tắt được.

## Affected users and systems — phạm vi ảnh hưởng

- Màn hình: sheet Find Common Photos, Activity / danh sách lượt (`MacCommonPhotosRuns`), Settings của Mac (nếu tự gom
  có công tắc ở đó). Board `MAC_CommonPhotos`, `MAC_CommonPhotosRun`, có thể thêm trạng thái "đang theo dõi".
- Thiết bị: chỉ Mac, như FS-19.08 (ngoại lệ đã chốt ở FS-18.07).
- Tầng code: Domain `CommonPhotos*` (chọn ảnh mới); Data (`CommonPhotosScanner`, `CommonPhotosStore`, nơi giữ SHA của
  file đã quét); helper Mac (`--agent`, đang chạy kiểm On Server định kỳ) nếu tự gom chạy nền.
- Dữ liệu đã lưu: thêm bảng hoặc cột cho "bộ được theo dõi" và cho SHA của file đã quét, kể cả folder không phải nguồn.
  Đây là dữ liệu người dùng tạo, nên ở bảng riêng, không ở `photo_metadata` (BD-02). App chưa phát hành nên không cần
  migration ngược.

## Constraints — ràng buộc

- Không nới bảo đảm an toàn của FS-19.08: không xoá bản nguồn nào trước khi bản ở đích được kiểm. Move tự động không được
  xoá gì mà người dùng không biết.
- Không lấy ngày sửa làm bằng chứng hai ảnh giống nhau. Ngày sửa chỉ dùng để biết file **có đổi không**, so với lượt trước.
- SMB/WebDAV/SFTP không báo khi có file mới: "liên tục" nghĩa là kiểm lại theo chu kỳ. Không giữ kết nối mở mãi, không
  chặn Backup (khoá kết nối, Backup đi trước).
- Không thêm dependency. Không ghi gì lên NAS ngoài Shared và CSV như hôm nay.
- iOS không chạy nền hàng giờ, nên không đưa phần tự gom sang iPhone/iPad ở bản này.

## Open questions — câu hỏi còn treo

Đã chốt (người dùng 2026-11-03):

1. **Làm cả hai.** Tự gom chính là "chạy lại chỉ ảnh mới" được helper Mac gọi theo chu kỳ.
2. **Copy tự chạy, Move phải hỏi.** Bộ Move gom sẵn danh sách rồi gửi thông báo, người dùng bấm mới dời và xoá.
3. **15 phút một lần**, chỉ khi Mac cắm điện và mạng không tính tiền.
4. **SHA của lượt quét giữ ở bảng riêng.** Folder không phải nguồn cũng không bị băm lại; không bắt thêm nguồn.

Chốt khi duyệt:

5. "Ảnh mới" là file mới hoặc đổi (đường dẫn + cỡ + ngày sửa khác lượt trước). Ảnh mới chỉ có ở A, chưa có ở B thì chờ,
   khi nào B có thì gom. Giữ đúng nghĩa này (người dùng duyệt 2026-11-03); `/spec` ghi thành AC.

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
