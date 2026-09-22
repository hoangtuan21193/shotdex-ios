# BD-02 — Thiết kế database

`BD-02` · `ShotDex/Data/Database/` · `ShotDexTests/DatabaseTests.swift` · cập nhật 2026-09-22

**Một câu:** bảng nào giữ gì, và luật giữ cho dữ liệu người dùng không bị lượt index xoá mất.

## 1. Quy tắc

- **Lượt index ghi đè nguyên một dòng metadata.** Cột nào nó không biết sẽ bị xoá trắng ở mỗi lần index lại
  → **mọi dữ liệu người dùng tự nhập, và mọi kết quả quét đắt tiền, phải nằm ở bảng riêng.**
- **Tổng hợp (gom nhóm, chia dải, phân vị) làm trong truy vấn**, không gom trong Swift.
- Favorite: **thư viện ảnh là nguồn thật**; cột trong database chỉ để lọc nhanh và được đồng bộ lại khi thư
  viện báo thay đổi.
- **Số megapixel không lưu** — nó tính ra từ chiều rộng và chiều cao.

## 2. Bảng metadata chính

```
assetId TEXT PK                  -- id ảnh do thư viện hệ thống cấp
creationDate, modificationDate   INTEGER epoch
mediaType                        -- 1 ảnh, 2 video; video có dòng nhưng không có EXIF
cameraManufacturer, cameraModel, normalizedCameraModel, normalizedCameraManufacturer
lensManufacturer, lensModel, normalizedLensModel
originalFilename                 -- dùng cho tìm kiếm theo tên file
iso INTEGER, aperture REAL
shutterSpeedSeconds REAL, shutterSpeedDisplay TEXT
focalLength REAL, focalLengthIn35mm REAL
calculatedEquivalentFocalLength REAL, equivalentFocalLength REAL   -- bản phẳng, để lọc và vẽ biểu đồ
sensorFormat TEXT, cropFactor REAL
width, height INTEGER
fileSize INTEGER
latitude, longitude REAL
placeName, placeSubLocality, placeLocality, placeAdminArea,
placeCountry, placeCountryCode, placeAddress TEXT
placeSearchText TEXT             -- viết thường + bỏ dấu; cột DUY NHẤT tìm theo địa điểm
placeCellKey TEXT, placeResolvedAt INTEGER   -- ô lưới ~110m, ghi bằng đường riêng
isFavorite INTEGER
indexedAt INTEGER
exifStatus TEXT                  -- đã đọc / không có EXIF / chưa đọc / chờ iCloud / lỗi
indexerVersion INTEGER           -- phiên bản bộ index đã ghi dòng này
readAttempts INTEGER             -- số lần "tải được mà đọc không ra"; lỗi mạng KHÔNG đếm
```

Có chỉ mục trên: tên máy và tên ống kính đã chuẩn hoá · ISO · khẩu · tốc độ · tiêu cự · tiêu cự tương đương
· khổ cảm biến · ngày chụp · loại media.

## 3. Bảng vệ tinh

| Bảng | Giữ gì |
|---|---|
| Dấu vân tay ảnh | id ảnh · dấu vân tay 64 bit (rỗng = chưa lấy được ảnh) · ngày sửa lúc tính · thời điểm tính |
| Nhóm ảnh trùng | một dòng cho mỗi ảnh trong mỗi nhóm, theo từng mức so trùng |
| Trạng thái quét trùng | mức so trùng · lần quét cuối · số nhóm |
| Kết quả quét chủ thể | id ảnh · số khuôn mặt · số chó mèo · thời điểm quét |
| Gán cảm biến thủ công | những máy người dùng tự chỉ định |
| Trạng thái index | điểm chạy tiếp · lần index cuối · mốc thay đổi của thư viện |
| Smart album | truy vấn đã lưu |
| Biểu đồ thống kê | id · đặc tả dạng JSON · vị trí |
| Sản phẩm đã tạo | collage và project video mở lại được ([FS-06.01b](../02-functional-spec/FS-06-collections/01b-album-management-and-creations.md)) |

- Dấu vân tay có **ngày sửa lúc tính**: lệch với ngày sửa hiện tại thì tính lại (ảnh vừa được chỉnh). Video
  không có dòng.
- Bảng quét chủ thể: **có dòng nghĩa là "đã nhìn qua"**, và **số khuôn mặt bằng 0 là một câu trả lời thật**,
  không phải "chưa biết". Danh sách việc = ảnh tĩnh **chưa có dòng**.
- Mở màn ảnh trùng **chỉ đọc hai bảng cache** rồi ghép với dữ kiện hiện tại — **không** tính lại dấu vân
  tay, **không** gom lại nhóm.

## 4. Gỡ một tính năng thì phải dọn cả truy vấn đã lưu

Bất kỳ thay đổi nào **bỏ một trường điều kiện** đều phải viết lại phần truy vấn đã lưu của smart album.

**Bắt buộc, không phải dọn cho đẹp**: bộ giải mã không còn hiểu giá trị đó, mà khi dữ liệu hỏng thì nó rơi
về **một truy vấn rỗng** — và **truy vấn rỗng không có điều kiện nào nên khớp cả thư viện**. Tức là album
"ảnh tôi chọn" âm thầm biến thành "mọi ảnh".

Ngoài ra, danh sách điều kiện được giải mã **khoan dung**: một điều kiện không hiểu được thì **rơi ra**,
không giết cả album — để đỡ những album do một bản build chạy trước lần đổi lược đồ ghi ra. Có test riêng.

Tiền lệ: bảng chấm sao được thêm, rồi bỏ cờ, rồi **xoá hẳn**.

## 5. Đánh đổi đã chọn

| Chọn | Thay vì | Vì |
|---|---|---|
| Bảng riêng cho dấu vân tay và kết quả quét | thêm cột vào bảng metadata chính | index lại sẽ xoá trắng, mà dựng lại thì tốn giải mã cả thư viện (có test khoá điều này) |
| Lưu sẵn tiêu cự tương đương | tính lúc truy vấn | biểu đồ tiêu cự chạy trên cả thư viện |
| GRDB | SwiftData | cần tổng hợp bằng SQL ([OV-02](../00-overview/OV-02-platform-and-technology.md)) |

## 6. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../README.md#6-việc-còn-nợ).
