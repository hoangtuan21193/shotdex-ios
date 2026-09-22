# FS-06.05 — Trips

`FS-06.05` · `Domain/Places/TripGrouping.swift` · `TripsScreen` · test `TripGroupingTests` (5 ca)
· cập nhật 2026-09-22

**Một câu:** gom ảnh thành chuyến đi bằng luật **cố ý máy móc** — không "thông minh", nên người dùng đoán
được nó sẽ gom thế nào.

## 1. Định nghĩa một chuyến

Một chuỗi ảnh:

- cách **nhà** hơn **80 km**,
- không đoạn nào hở quá **2 ngày**,
- kéo dài ít nhất **1 ngày**,
- và có ít nhất **8 ảnh**.

## 2. "Nhà"

**Ô 0.5° dày ảnh nhất**, và chỉ tính là nhà khi chiếm **≥ 20%** thư viện.

Dưới ngưỡng đó coi như người dùng chụp khắp nơi (`home = nil`, mọi ảnh đều tính là "đi xa") — không có tín
hiệu nào khác về "nhà" khi chạy offline.

## 3. Cắt và nối

- Khoảng hở đo với ảnh **cuối của chuỗi đang gom**, không phải ảnh vừa duyệt qua — một tấm lạc giữa chừng
  không được reset đồng hồ.
- Một ảnh chụp ở nhà **kết thúc** chuỗi.
- Sau đó một lượt nối lại các chuỗi liền kề **cùng tên địa điểm** và cách nhau ≤ 2 ngày: một tấm sai
  giờ, một lần import từ máy khác, hay một đêm về nhà giữa chuyến sẽ cắt một kỳ nghỉ thành ba.
- Ảnh bìa lấy **giữa chuỗi**, không lấy tấm đầu — ảnh lúc mới tới hiếm khi đáng làm bìa.

## 4. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
