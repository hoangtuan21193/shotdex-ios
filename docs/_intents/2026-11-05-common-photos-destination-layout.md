# Intent: Common Photos — chọn cách xếp ảnh ở folder đích

| Trường | Giá trị |
|---|---|
| Tác giả | Tuấn (qua Claude) |
| Ngày | 2026-11-05 |
| Trạng thái | accepted (2026-11-05) |
| Tiến độ | **đang làm** (2026-11-05) — task 11/13, 29/34 AC xanh (4 một phần) — plan [2026-11-05-fs1908-6e-dated-organize-fileinfo](../_plans/2026-11-05-fs1908-6e-dated-organize-fileinfo.md) |
| Nguồn | phản hồi người dùng 2026-11-05: "Save common ra một thư mục khác thì nên có option chọn là lưu flat hay lưu theo cấu trúc ngày tháng hay chia ảnh video các kiểu nữa. giống kiểu các option ở màn hình backup trên iphone ấy. mục đích là để tìm ảnh dễ, verify kết quả cũng dễ hơn." |
| Spec sinh ra từ đây | [FS-19.08 §6e](../02-functional-spec/FS-19-photo-sources/08-common-photos.md) · AC-193…226 ở [08b](../02-functional-spec/FS-19-photo-sources/08b-common-photos-ac.md) |

Intent anh em: [2026-11-05-common-photos-dated-folders-scan](2026-11-05-common-photos-dated-folders-scan.md) (quét nhanh hơn).

## Problem — vấn đề

Find Common Photos (FS-19.08, Mac) Copy/Move mọi ảnh chung vào **một folder phẳng**: tên lấy từ bản đầu, trùng tên
thì thành `IMG_0001 (2).JPG` (`CommonPhotosRunner.swift:360`, `CommonPhotosDestinationPlan.swift`). Với vài nghìn
ảnh thì:

- **Khó tìm ảnh.** Ảnh của 5 năm đổ chung một folder; muốn xem ảnh ngày 15/3/2025 phải sắp theo tên hay ngày sửa
  và mò.
- **Khó kiểm kết quả.** Nguồn xếp `2025/03/15/DSC_0412.ARW`, đích chỉ còn `DSC_0412.ARW` (hay `DSC_0412 (3).ARW`).
  Không đặt cạnh nhau mà so folder-với-folder được; phải mở CSV log để biết file nào từ đâu ra.
- **Trùng tên nhiều.** Máy ảnh quay vòng số (`DSC_0001` mỗi 10.000 tấm), nhiều máy cùng tiền tố — folder phẳng sinh
  hàng loạt `(2)`, `(3)`, xa tên gốc.
- **Ảnh và video lẫn nhau**, không tách được như bên Backup.
- **Bên Backup đã có sẵn đủ lựa chọn** mà người dùng quen: trang Organize (iPhone `PH_BackupOrganize`, Mac
  `MAC_BackupOrganize`, `BackupOrganizeText.swift`, `BackupShared/BackupPathPlanner.swift`) — Year › Month › Day,
  Year › Month, Year › Date, Date Only, No Folders; video để chung hay tách ở đầu/năm/tháng/ngày; tên Original /
  Date and Time / Date and Original. Common Photos không có lựa chọn nào.

Mức độ: trung bình. Không mất ảnh, nhưng folder kết quả khó dùng, và khó tự tin là kết quả đúng — đúng chỗ người
dùng cần chắc nhất khi đã Move.

## Proposed outcome — kết quả mong muốn

- Trước khi chạy, chọn được cách xếp folder đích, cùng các lựa chọn và cùng chữ như Organize của Backup, có ví dụ
  đường dẫn (`2025 › Mar › 2025.03.15 › DSC_0412.ARW`).
- Thêm lựa chọn **giữ cấu trúc như folder nguồn**: `A/2025/03/15/X.ARW` → `Đích/2025/03/15/X.ARW` — so đích với nguồn
  folder-đối-folder là kiểm xong.
- Tách được ảnh và video.
- Kế hoạch sau Scan (§6d) và Compare cho thấy đường dẫn đầy đủ ở đích, không chỉ tên.
- Lựa chọn được nhớ theo bộ (connection + folders + đích), tự gom (§6c) dùng đúng lựa chọn đó.
- Undo (§6b) vẫn đưa mọi thứ về như cũ, kể cả folder con vừa tạo ở đích.
- Chạy lại cùng bộ với lựa chọn khác không làm đích thành hai bản của cùng ảnh mà không nói gì.

## Affected users and systems — phạm vi ảnh hưởng

- Tính năng: Find Common Photos — sheet (thêm chỗ chọn), kế hoạch Scan, Copy/Move, Undo, CSV log, tự gom.
  Board `MAC_CommonPhotos`, `MAC_CommonPhotosRun`, có thể thêm trang Organize cho sheet.
- Thiết bị: Mac.
- Tầng: Domain (`CommonPhotosDestinationPlan`, `CommonPhotosRunner`, `CommonPhotosUndoer`, `CommonPhotosLog`),
  `BackupShared/BackupPathPlanner` (dùng lại), ShotDexMac (sheet, trang Organize Mac đã có của Backup).
- Dữ liệu đã lưu: lựa chọn theo bộ và đường dẫn đích từng ảnh (đã có `destinationPath`) → có thể thêm cột/bảng
  trong `CommonPhotosStore` (migration). Lượt chạy cũ đã phẳng vẫn phải Undo được.

## Constraints — ràng buộc

- Luật an toàn Move/Undo (§6, §6b) giữ nguyên: không xoá nguồn trước khi đích được chứng minh; Undo xoá folder con
  mình tạo chỉ khi nó rỗng.
- Xếp theo ngày chụp cần ngày chụp: ảnh có EXIF ở đầu file (đã đọc 64 KB khi tìm giờ chụp), **video thì khó hơn** —
  không được tải cả video chỉ để lấy ngày.
- Dùng lại `BackupPathPlanner`/`BackupOrganizeText`, không làm cách xếp thứ hai cho cùng khái niệm.
- Mặc định không đổi hành vi với bộ đã có (đang phẳng) trừ khi người dùng chọn khác.
- Không thêm dependency.

## Open questions — câu hỏi còn treo

1. ~~Mặc định cho bộ mới là gì?~~ **Đã trả lời (user 2026-11-05): Giữ cấu trúc nguồn.** Bộ đã có giữ phẳng như cũ.
2. **Giữ cấu trúc nguồn theo bản nào** khi hai bản nằm khác folder ngày (A `2025/03/15`, B `2025/03/16`)? — người
   dùng. Mặc định đề xuất: theo folder thứ nhất trong danh sách. **Chốt theo mặc định đề xuất (user duyệt intent 2026-11-05).**
3. ~~Video không đọc được ngày chụp thì xếp theo gì?~~ **Đã trả lời (user 2026-11-05): folder nguồn nếu tên folder
   là ngày, không thì ngày sửa file trên server.**
4. ~~Có cần đủ cả lựa chọn đặt tên file không?~~ **Đã trả lời (user 2026-11-05): đủ như Backup** (Original / Date and
   Time / Date and Original).
5. **Đổi cách xếp cho một bộ đã gom trước đây**: ảnh cũ ở đích có được xếp lại không? — người dùng. Mặc định đề
   xuất: không; chỉ ảnh mới theo cách mới, và màn nói rõ điều đó. **Chốt theo mặc định đề xuất (user duyệt intent 2026-11-05).**
