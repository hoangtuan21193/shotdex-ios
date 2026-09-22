# OV-03 — Lộ trình dựng app

`OV-03` · cập nhật 2026-09-22

**Một câu:** thứ tự năm phase đã dựng nên app — tài liệu lịch sử, cả năm phase đã xong.

## 1. Năm phase

| Phase | Nội dung |
|---|---|
| 1 — Foundation | Project + SPM GRDB · Info.plist quyền · bundle `sensor_database.json` · model · schema + migration · lớp bọc PhotoKit · màn gốc + chrome |
| 2 — Metadata | bộ đọc EXIF · bộ chuẩn hoá tên máy · bộ chuẩn hoá tên lens · tra khổ cảm biến · tiêu cự tương đương · bộ dựng metadata (kèm unit test) · bộ nạp sensor database · pipeline index |
| 3 — Library | Grid lưới của UIKit + pinch density + prefetch · nhãn metadata · bộ phân tích truy vấn + gợi ý · filter sheet + token + đếm khớp · sort menu · Photo Detail |
| 4 — Albums + Statistics | Albums grid + detail · lớp truy vấn thống kê · màn thống kê (thẻ tóm tắt, biểu đồ body/lens, histogram tiêu cự, donut cảm biến) + drill-down về Library |
| 5 — Polish | Onboarding + đủ trạng thái quyền · Settings đầy đủ · empty/error state · Dark Mode + Dynamic Type + VoiceOver · perf 50k–100k ảnh · test suite |

## 2. Luật còn hiệu lực cho mọi phase sau

- Mỗi phase kết thúc bằng project **build được** (`xcodebuild`), không thêm dependency thừa.
- Gặp giới hạn nền tảng (PhotoKit, iCloud) → **không âm thầm giả lập dữ liệu**; mô tả rõ giới hạn và
  làm phương án thực tế tốt nhất.

Việc sau MVP (editor, collage, video studio, extension) không theo phase nữa mà theo quy trình sáu
giai đoạn của [PROCESS.md](../PROCESS.md).
