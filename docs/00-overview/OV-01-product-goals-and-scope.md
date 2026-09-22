# OV-01 — Mục tiêu sản phẩm và phạm vi

`OV-01` · cập nhật 2026-09-22

**Một câu:** vì sao app tồn tại, ai dùng, cái gì trong MVP và cái gì để sau.

## 1. Câu hỏi app trả lời

Người chụp bằng nhiều body và lens muốn biết:

- Body nào, lens nào dùng nhiều nhất?
- Thường chụp ở tiêu cự, ISO, khẩu độ, tốc độ nào?
- Full Frame, APS-C hay Micro Four Thirds chiếm phần lớn?
- Quy về tiêu cự tương đương Full Frame thì góc nhìn quen thuộc là bao nhiêu?

Trọng tâm: duyệt ảnh, đọc metadata, tìm/lọc, thống kê thói quen chụp, so sánh camera/lens/tiêu cự.

## 2. Phạm vi MVP

| # | Hạng mục |
|---|---|
| 1 | Quyền Photo Library — onboarding + đủ trạng thái quyền |
| 2 | Index ảnh và EXIF — batch, progress, cancel, resume, incremental |
| 3 | Photo grid kèm metadata dưới thumbnail (ISO, khẩu, tiêu cự) |
| 4 | Lọc: body, lens, ISO, tốc độ, khẩu, tiêu cự thật, tiêu cự FF, khổ cảm biến |
| 5 | Photo detail — zoom, vuốt, share, favorite, bảng metadata |
| 6 | Statistics: body, lens, tiêu cự thật, tiêu cự FF, khổ cảm biến |
| 7 | Sensor database + mapping thủ công |
| 8 | Riêng tư: xử lý hoàn toàn cục bộ |
| 9 | Dark Mode |
| 10 | Truy cập cơ bản (VoiceOver, Dynamic Type) |

**Cố ý không có trong MVP:** đăng nhập, server, subscription, AI.

## 3. Hướng mở rộng kiến trúc không được khoá

Statistics theo năm/chuyến đi · map · tổ hợp body+lens ưa dùng · so sánh RAW/JPEG · phát hiện trùng ·
chấm sao · export thống kê · widget · layout iPad · so sánh hai khoảng thời gian · nhận xét cá nhân
hoá (ví dụ *"RF100-500mm chiếm 62% ảnh động vật của bạn"*).

Trạng thái hôm nay vượt xa MVP: editor, collage, video studio, extension — xem `FS-*` và `EX-*`.
