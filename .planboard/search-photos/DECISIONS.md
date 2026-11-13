# Search giống Photos — các quyết định

> Chốt 2026-11-14, vòng 1, người dùng đồng ý mọi đề xuất. Nguồn: plan.json. Bằng chứng: docs/_research/2026-11-14-photos-search-re.md

| ID | Quyết định | Kết quả | Lựa chọn |
|---|---|---|---|
| D1 | Gợi ý khi gõ | OK | Dòng có ảnh đại diện, tên (phần gõ đậm), loại, số ảnh; ≤ 8 dòng; viên "đọc hiểu" giữ trên cùng khi câu nhiều phần |
| D2 | Chỗ hiện kết quả | OK | Ngay trong tab Search, dưới gợi ý, sau 0,15 s; nút "Mở trong Library"; Search trên bàn phím = ẩn bàn phím |
| D3 | Chọn gợi ý | OK | Thành viên lọc (token) trong ô; gõ tiếp thu hẹp trong ảnh của viên; nhiều viên = AND; xoá lùi khi ô trống gỡ viên cuối |
| D4 | Ô tìm trống | OK | Gần đây + "Trong thư viện của bạn" (máy, ống kính, nơi, năm dùng nhiều nhất, có số ảnh); dòng "Thử: …" khi thư viện trống |
| D5 | Ngày tháng | OK | Năm, tháng, tháng+năm, mùa (theo bán cầu nơi chụp, không toạ độ = Bắc), thứ/cuối tuần, today/yesterday/this week; khung giờ cũ giữ |
| D6 | Gõ sai | OK | Chỉ khi 0 kết quả: "Có phải: X (N ảnh)?" (sai ≤ 2 chữ, tên ≥ 5 chữ); không tự sửa |
| D7 | Mac | OK | Làm cùng đợt, chỉ mục và gợi ý dùng chung |
| A1–A9 | Phần Claude tự quyết | OK | Bảng nhóm + FTS5 tiền tố; chạy nền + huỷ; từ vựng dựng một lần; Recents gộp truy vấn; kết quả theo lô; chữ tự do qua FTS; báo chưa index xong; giữ mọi chức năng; quy trình |

Lý do từng câu ở trường `why` trong plan.json.
