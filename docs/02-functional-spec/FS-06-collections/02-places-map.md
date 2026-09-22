# FS-06.02 — Places

`FS-06.02` · `PlacesMapScreen` · `Domain/Places/PlaceClustering.swift` · `LibraryQueries.locatedPhotos()`
· cập nhật 2026-09-22

**Một câu:** duyệt thư viện bằng bản đồ — pin gom theo lưới độ nên chúng không nhảy khi pan.

## 1. Quy tắc

- Lấy **toàn bộ** ảnh có toạ độ **một lần**, không query theo khung nhìn: query lại khi pan thì gom cụm
  không ổn định, mà mỗi dòng chỉ là ba số và một chuỗi ngắn.
- **Gom cụm bằng lưới theo độ, không theo khoảng cách** — gom theo khoảng cách sẽ đảo thứ tự pin khi pan.
- Tự gom cụm chứ **không** dùng annotation clustering của MapKit: cần thumbnail bìa + số đếm riêng cho
  từng cụm.

## 2. Gom cụm

| Tham số | Giá trị |
|---|---|
| Kích thước ô | bề rộng đang thấy chia cho **7** |
| Sàn | **0,0004°** — một loạt ảnh chụp cùng chỗ không vỡ thành chục pin |
| Toạ độ pin | **trọng tâm** các ảnh trong ô, không phải tâm ô |

Cùng một ảnh luôn rơi vào cùng ô ở cùng mức zoom.

## 3. Pin

- Nhãn = tên địa điểm **xuất hiện nhiều nhất** trong cụm (ảnh trong một ô có thể vắt qua ranh giới hành
  chính); không có thì hiện toạ độ. Phụ đề = ngày hoặc khoảng ngày.
- Bản đồ chỉ báo lại **khi camera dừng hẳn**, nên pin gộp và tách theo mức phóng mà không tính lại giữa lúc kéo.
- Chạm cụm → màn danh sách ảnh ([FS-06.03](03-memories-and-movie-builder.md)).

Mỗi dòng dữ liệu mang: id ảnh · ngày · toạ độ · tên phường/quận, tỉnh và quốc gia.

## 4. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
