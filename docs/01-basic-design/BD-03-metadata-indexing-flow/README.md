# BD-03 — Luồng index metadata

`BD-03` · `ShotDex/Domain/Indexing/` · `Data/Sources/ExifReader.swift` · `Data/Database/MetadataStore.swift`
· test `IndexDiffTests` · `IndexNetworkStatusTests` · `IndexThermalPolicyTests` · `IndexInteractionGateTests`
· cập nhật 2026-10-02

**Một câu:** đường đi của dữ liệu từ một tấm ảnh trong thư viện tới một dòng trong database — chọn việc, đọc
EXIF, sống với iCloud, báo tiến độ, và chạy tiếp ở nền.

## Các phần

| # | Phần | Trả lời |
|---|---|---|
| 01 | [Chọn việc và chạy tiếp](01-run-selection-and-diff.md) | lượt nào chạy, đọc lại ảnh nào, chạy tiếp từ đâu |
| 02 | [Đọc EXIF](02-exif-read.md) | hai pha, thang lấy dữ liệu, ba kết cục, luật không đè dữ liệu cũ |
| 03 | [Mạng, iCloud, nhiệt](03-network-thermal-and-gate.md) | giới hạn tải, cầu dao, đồng hồ canh, chính sách cellular, nhiệt, nhường cho viewer |
| 04 | [Tiến độ và chạy nền](04-progress-and-background.md) | chỉ báo, huỷ, số cộng dồn, tự thử lại, chạy nền |
| 05 | [Chỉ đọc bản gốc, index dùng chung](05-shared-index.md) | Mac chỉ đọc ảnh đã tải về; mỗi ảnh một máy đọc, các máy khác lấy qua CloudKit |

## Quy tắc cốt lõi

- **Đọc EXIF không giải mã ảnh.** Bản trên máy đọc thẳng thuộc tính; ảnh trên iCloud chỉ tải phần đầu file.
- **Đọc hỏng không được đè lên EXIF đã có.** Không lấy được byte nào nghĩa là **không biết gì mới** về ảnh.
- **Chỉ "tải được mà đọc không ra" mới dẫn tới kết luận "ảnh này không có EXIF".** Lỗi mạng thì thử lại vô
  hạn và **không đếm**.
- **Chỉ báo chỉ bật khi có việc thật**, trừ lượt do người dùng bấm.
- **Huỷ phản hồi ngay khung hình bấm**; phần đuôi dọn ở nền.
- **"Xong" nghĩa là thư viện đã đọc hết**, không phải "một suất chạy đã hết giờ".
- Việc index chạy ở mức ưu tiên thấp, **không chặn giao diện**.
- **Nguồn thư mục và ổ ngoài** ([FS-19.01 §4](../../02-functional-spec/FS-19-photo-sources/01-folders-and-drives.md)) có lượt
  đọc riêng, cùng bộ ghép metadata với asset Photos: liệt kê (bỏ gói và tên bắt đầu bằng `.`), ghép RAW + JPEG cùng
  tên gốc, rồi với mỗi file mới hay đổi (so kích thước + ngày sửa) đọc EXIF, kích thước ảnh, ngày chụp từ đầu file
  và **hash nhanh**; ghi Ảnh + Bản sao + dòng metadata trong một transaction. File không đổi chỉ làm mới "lần thấy
  cuối". **Không bao giờ ghi vào thư mục nguồn.**

## Hằng số

| Hằng số | Giá trị |
|---|---|
| Lô đọc EXIF | 200 ảnh |
| Lô ghi nhanh | 1.000 dòng mỗi lần ghi |
| Đọc song song | 12 (khi máy mát) |
| Tải iCloud song song | **4**, tính trên toàn app |
| Cửa sổ "đứng im" | 10 giây (máy) · 8 giây (mạng) |
| Trần một lượt tải | 120 giây |
| Trần bộ đệm mỗi lần đọc | 8 MB |
| Ngưỡng bỏ đường nhanh | 5.000 ảnh chưa xong |
| Ngưỡng bật chỉ báo lúc lập kế hoạch | 200 ảnh ứng viên |
| Cầu dao mở | ≥ 10 lần đứng im trong 12 lượt gần nhất |
| Thời gian chờ của cầu dao | 30 giây cố định, rồi thử **một** lượt |
| Nghỉ sau mỗi lần đứng im | 2 giây |
| Số lần cầu dao mở tối đa mỗi lượt chạy | 3 |
| Bỏ cuộc khi đọc hỏng | sau 5 lần → kết luận "không có EXIF" |
| Tự thử lại sau lượt còn việc | 30 giây, không giãn dần |
| Nhả chốt khi lượt chạy không kết thúc | 45 giây |
| Bàn giao từ lượt nền sang lượt trước mặt | hỏi lại mỗi 200ms, tối đa 30 giây |
| Tự bỏ nhường khi cổng bị kẹt | 90 giây |

## Bước cuối cho mỗi ảnh

1. Chuẩn hoá tên máy và tên ống kính ([BD-05](../BD-05-imaging-business-rules.md)).
2. Tra khổ cảm biến từ cơ sở dữ liệu máy ảnh + phần người dùng tự gán.
3. Tính tiêu cự tương đương Full Frame ([BD-05](../BD-05-imaging-business-rules.md)).
4. Tính khung giờ chụp — theo mặt trời khi có toạ độ, theo giờ EXIF khi không ([BD-03.02 §4](02-exif-read.md)).
5. Ghi theo lô vào database và cập nhật điểm chạy tiếp.
6. Toạ độ lấy từ **dữ liệu ảnh của hệ thống**, không đọc thẻ GPS trong EXIF.

Lượt index **không** đọc phần metadata riêng của hãng. Số lần đóng màn chỉ được đọc **khi người dùng mở
bảng thông tin của một tấm ảnh** ([FS-02.03](../../02-functional-spec/FS-02-photo-detail/03-info-panel-and-metadata.md)).
