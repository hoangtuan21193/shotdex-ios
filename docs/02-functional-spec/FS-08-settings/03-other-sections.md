# FS-08.03 — Các mục còn lại

`FS-08.03` · `Features/Settings/SettingsScreen.swift` · `CompressionPresetsScreen`
· `CameraDatabaseScreen` · cập nhật 2026-09-22

**Một câu:** Notifications · Display · Playback · Sharing · Export · People and Pets · Camera Database ·
Support.

## 1. Notifications

- Công tắc **Daily On This Day Reminder** (mặc định tắt) + ô chọn giờ **Remind Me At** (mặc định 09:00, lưu
  bằng số phút tính từ nửa đêm). Phần đặt lịch: [FS-06.07](../FS-06-collections/07-on-this-day.md).
- **Chỉ xin quyền khi người dùng bật công tắc.** Bị từ chối — kể cả đã từ chối từ trước, khi đó hệ thống trả
  lời ngay mà không hỏi lại — thì **công tắc bật lại về tắt** thay vì lưu một tuỳ chọn không bao giờ bắn
  được, và mục hiện thêm dòng "Notifications: Denied" + nút **Open Settings**.
- Quyền bị thu hồi sau đó: hệ thống tự ngừng giao, và lần làm mới kế tiếp còn **dọn sạch tập đang chờ** nên
  lần cấp lại sau không bắn lại một tuần cũ.
- Ô chọn giờ **chờ 500ms rồi mới đặt lại lịch**: bánh xe báo giá trị mới ở **mỗi nấc**, mà mỗi lần đặt lại
  là 7 lượt đọc và 7 lượt ghi lịch.
- **Hai nơi khai giá trị mặc định phải khớp nhau**: giao diện hiện 09:00, và bộ đặt lịch phải **tự viết ra
  đúng con số đó** chứ không đọc thẳng — cách đọc thẳng trả về 0 cho một khoá chưa ghi, tức là đặt lịch lúc
  nửa đêm trên máy mới cài trong khi màn hình ghi 09:00.
- Thông báo bắn lúc app đang mở **vẫn hiện biểu ngữ**: nó là lời mời vào xem một ngày cụ thể, vẫn dùng được
  giữa phiên và vẫn chạm được.

## 2. Display (Thumbnail Metadata)

| Hàng | Mặc định |
|---|---|
| Nhãn định dạng file ở góc thumbnail | bật |
| Thông số dưới thumbnail — ISO · khẩu · tốc độ · tiêu cự · megapixel · dung lượng | từng thứ một công tắc |
| Focal Length Style | Actual / Equivalent |

Mật độ lưới **không phải công tắc** — chỉ có một dòng chú nói pinch trên lưới để đổi.

## 3. Playback

- **View Full HDR**, **mặc định tắt**: bật thì ảnh trong viewer hiển thị dải sáng đầy đủ. Tắt sẵn có lý do —
  một khung HDR đứng cạnh chrome tiêu chuẩn làm chrome trông xám, và trên vài màn hình thì chói.
- **Autoplay Videos**, mặc định bật. Tắt thì video chờ bấm play. **Dừng khi rời trang không phải một tuỳ
  chọn** — trang đã trôi đi thì luôn phải dừng. Lặp lại vẫn là nút trên chính player, không đưa vào đây.

## 4. Sharing

**Include Location** — mặc định bật; luật ghi lại file khi tắt nằm ở
[NF-03](../../04-non-functional-design/NF-03-privacy-and-security.md).

## 5. Export

**Resize Presets**: luôn hiện bốn preset dựng sẵn, và cho tạo, sửa, xoá preset riêng (tên, Fill/Fit, rộng,
cao, chất lượng, JPEG/HEIC). Preset riêng lưu **cục bộ trong cài đặt của app**, không đồng bộ.

## 6. People and Pets

Điều khiển lượt quét chủ thể — xem [FS-06.04](../FS-06-collections/04-people-and-pets.md).

## 7. Camera Database

- **Unknown Cameras** — danh sách máy chưa tra được, và chỗ gán tay ngay tại đó.
- **Reset Custom Mappings** — hành động phá huỷ, có hộp xác nhận.
- Luật tra cứu: [BD-05](../../01-basic-design/BD-05-imaging-business-rules.md).

## 8. Support

Xem [FS-13](../FS-13-support.md). Đây là **ngoại lệ duy nhất** của cam kết xử lý cục bộ
([NF-03](../../04-non-functional-design/NF-03-privacy-and-security.md)).

## 9. Cài đặt lưu ở đâu

Mọi công tắc trong màn này lưu trong **cài đặt của app**, và **mọi khoá khai một chỗ** — không gõ chuỗi
rời rạc ở từng màn.

## 10. Tiêu chí nghiệm thu

Xem [05](05-acceptance-criteria.md).
