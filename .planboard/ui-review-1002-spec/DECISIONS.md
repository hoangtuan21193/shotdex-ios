# Spec ui-review-1002 — các câu CẦN QUYẾT đã chốt

Chốt 2026-10-02, 1 vòng, 34/34 OK.

| ID | Câu hỏi | Kết quả | Lựa chọn |
|---|---|---|---|
| K1 | Duplicates: Delete khi có dấu ở chế độ khác (FS-06.06b §1) | OK | Chỉ dấu của chế độ đang xem |
| K2 | Duplicates trên Duo inner: 1 hay 2 cột (FS-06.06b §4) | OK | Hạ 400 (Duo inner 2 cột 410pt) |
| K3 | Smart Album: 'Place is missing' (FS-06.08 §2) | OK | Giữ, ghi 'gồm ảnh chưa tra địa chỉ' |
| K4 | Vuốt xuống khi sheet có thay đổi (FS-06.08 §3, FS-07.01b, cũng áp cho Advanced Search, form server) | OK | Bật về + hiện alert ngay |
| K5 | Compare: chỗ đặt hint 'Touch and hold to keep only this one' (FS-01.08) | OK | Dưới nút Delete |
| K6 | Compare: mấy bản phân giải cao cùng lúc (FS-01.08 §6) | OK | Tối đa 2 bản (~48 MB) |
| K7 | Đóng viewer cuộn lưới: áp cho mọi lưới dùng chung? (FS-02.01b) | OK | Mọi lưới |
| K8 | Phím ←/→ khi video đang dừng (FS-02.01b) | OK | ←/→ lật trang, ',' '.' cho khung |
| K9 | Thứ tự section Photo Info (FS-02.03) | OK | Camera & Lens, Exposure, rồi Location |
| K10 | Bề rộng cột inspector Photo Info (FS-02.03b) | OK | 360pt cố định + token |
| K11 | Inspector nhớ trạng thái mở? (FS-02.03b) | OK | Nhớ lần cuối |
| K12 | Alert lỗi Favorite/Delete có Try Again? (FS-02.04) | OK | OK + Try Again |
| K13 | Ảnh không GPS, ngoài khung đêm: ghi Day? (FS-01.03b) | OK | Ghi Day |
| K14 | Video và ảnh không EXIF, không toạ độ (FS-01.03b) | OK | Dùng múi giờ hiện tại của máy |
| K15 | 'sunset'/'sunrise' gồm giờ xanh? (FS-01.03b) | OK | Chỉ giờ vàng |
| K16 | Cách điền khung giờ cho thư viện đã index (BD-03.02 §7) | OK | Tăng phiên bản index, đọc lại cả thư viện |
| K17 | Camera ▸ / Lens ▸ ở đâu (FS-01.05b) | OK | Cả ba lưới |
| K18 | Ảnh chưa đọc xong EXIF có tính là 'thiếu' không (FS-01.05b) | OK | Chỉ ảnh đã đọc xong |
| K19 | DESIGN §10.6 còn ghi accent dùng cho chart (FS-07.01b) | OK | Sửa DESIGN |
| K20 | Glyph nút menu Add Chart / Reorder (FS-07.01b) | OK | + |
| K21 | Chân thẻ Insights lúc đang index / Limited (FS-07.01b) | OK | Bỏ chân thẻ |
| K22 | Ngưỡng cửa sổ thấp (NF-05 §4) | OK | < 720pt |
| K23 | iPhone SE (375×667) trong phạm vi kiểm? (NF-05) | OK | Bỏ SE khỏi phạm vi |
| K24 | Insights trên cửa sổ thấp (spec-pending FS-07.02) | OK | Một hàng câu (~120pt) |
| K25 | Share sau khi Resize chạy sạch ở đâu (FS-03.07 §5) | OK | Ở lại màn, Share + Done |
| K26 | Collage Export: Share… có lưu vào Photos trước? (FS-11b §3) | OK | Lưu rồi share |
| K27 | Share: phụ đề hàng không vẽ được (FS-08.06 §4) | OK | Câu giải thích ở đầu sheet |
| K28 | Trùng tên file khi upload đang chạy nền (FS-15.02b §4) | OK | Dò trùng cả lô trước khi đẩy |
| K29 | App bị đóng hẳn giữa lô upload (FS-15.02b §4) | OK | Bảng riêng, Resume khi mở lại |
| K30 | Hàng Connection khi chỉ có 1 connection (FS-15.02 §2) | OK | Vẫn là menu |
| K31 | Glyph 'In Library' trên ô ảnh server (FS-17.01 §2b) | OK | photo.badge.checkmark 14pt |
| K32 | Glyph hàng Cloud Folders (FS-17.05) | OK | cloud |
| K33 | Empty state Statistics lúc index lần đầu (FS-07.01b) | OK | — |
| K34 | Footnote Onboarding (FS-09) | OK | — |

## K1 — Duplicates: Delete khi có dấu ở chế độ khác (FS-06.06b §1)
- **Chốt:** Chỉ dấu của chế độ đang xem
- **Vì sao:** Dấu giờ sống qua đổi chế độ Exact/Similar/Series; nút Delete phải nói đúng nó xoá gì.

## K2 — Duplicates trên Duo inner: 1 hay 2 cột (FS-06.06b §4)
- **Chốt:** Hạ 400 (Duo inner 2 cột 410pt)
- **Vì sao:** Lưới adaptive 420pt cần 856pt cho 2 cột; Duo inner có 835pt.

## K3 — Smart Album: 'Place is missing' (FS-06.08 §2)
- **Chốt:** Giữ, ghi 'gồm ảnh chưa tra địa chỉ'
- **Vì sao:** Ảnh có toạ độ nhưng chưa tra địa chỉ cũng sẽ khớp 'thiếu địa điểm'.

## K4 — Vuốt xuống khi sheet có thay đổi (FS-06.08 §3, FS-07.01b, cũng áp cho Advanced Search, form server)
- **Chốt:** Bật về + hiện alert ngay
- **Vì sao:** Một quyết định cho cả 4 sheet nhập liệu (C1).

## K5 — Compare: chỗ đặt hint 'Touch and hold to keep only this one' (FS-01.08)
- **Chốt:** Dưới nút Delete
- **Vì sao:** Góc trên-phải đã là nút Delete.

## K6 — Compare: mấy bản phân giải cao cùng lúc (FS-01.08 §6)
- **Chốt:** Tối đa 2 bản (~48 MB)
- **Vì sao:** Chạm sang khung B khi A đã có bản cao: nhả A hay giữ cả hai. Mỗi bản ~24 MB.

## K7 — Đóng viewer cuộn lưới: áp cho mọi lưới dùng chung? (FS-02.01b)
- **Chốt:** Mọi lưới
- **Vì sao:** Trips, Places, album trong Collections, Uploaded to Server dùng cùng lưới.

## K8 — Phím ←/→ khi video đang dừng (FS-02.01b)
- **Chốt:** ←/→ lật trang, ',' '.' cho khung
- **Vì sao:** Hôm nay ←/→ là lùi/tiến một khung khi video dừng; Z5 muốn ←/→ lật ảnh.

## K9 — Thứ tự section Photo Info (FS-02.03)
- **Chốt:** Camera & Lens, Exposure, rồi Location
- **Vì sao:** V4 chỉ chốt Camera & Lens lên trước bản đồ.

## K10 — Bề rộng cột inspector Photo Info (FS-02.03b)
- **Chốt:** 360pt cố định + token
- **Vì sao:** Chưa có token trong DESIGN.md.

## K11 — Inspector nhớ trạng thái mở? (FS-02.03b)
- **Chốt:** Nhớ lần cuối
- **Vì sao:** Người soi EXIF thường soi cả loạt.

## K12 — Alert lỗi Favorite/Delete có Try Again? (FS-02.04)
- **Chốt:** OK + Try Again
- **Vì sao:** NF-04 đòi mọi lỗi kèm lối ra; alert hiện có chỉ có OK.

## K13 — Ảnh không GPS, ngoài khung đêm: ghi Day? (FS-01.03b)
- **Chốt:** Ghi Day
- **Vì sao:** Quyết định 'is missing' của trường này gồm những ảnh nào.

## K14 — Video và ảnh không EXIF, không toạ độ (FS-01.03b)
- **Chốt:** Dùng múi giờ hiện tại của máy
- **Vì sao:** Không có giờ địa phương ghi trong file.

## K15 — 'sunset'/'sunrise' gồm giờ xanh? (FS-01.03b)
- **Chốt:** Chỉ giờ vàng
- **Vì sao:** Hai từ trùng nhau một nửa nếu gộp.

## K16 — Cách điền khung giờ cho thư viện đã index (BD-03.02 §7)
- **Chốt:** Tăng phiên bản index, đọc lại cả thư viện
- **Vì sao:** Đọc lại cả 55k ảnh ≈ 50 GB nếu ảnh nằm trên iCloud.

## K17 — Camera ▸ / Lens ▸ ở đâu (FS-01.05b)
- **Chốt:** Cả ba lưới
- **Vì sao:** Menu lọc dùng chung với Album Detail và Smart Album (FS-06.09).

## K18 — Ảnh chưa đọc xong EXIF có tính là 'thiếu' không (FS-01.05b)
- **Chốt:** Chỉ ảnh đã đọc xong
- **Vì sao:** Lúc đang index 40.000 ảnh, 'No Lens' sẽ ra cả thư viện.

## K19 — DESIGN §10.6 còn ghi accent dùng cho chart (FS-07.01b)
- **Chốt:** Sửa DESIGN
- **Vì sao:** C3 đã chọn giữ indigo; tài liệu phải nói cùng một điều.

## K20 — Glyph nút menu Add Chart / Reorder (FS-07.01b)
- **Chốt:** +
- **Vì sao:** Nút ⇅ cũ trông như 'sắp xếp' và bị gộp vào menu.

## K21 — Chân thẻ Insights lúc đang index / Limited (FS-07.01b)
- **Chốt:** Bỏ chân thẻ
- **Vì sao:** Dải đầu màn mới đã nói 'Still reading photo info'; chân thẻ nói lần nữa.

## K22 — Ngưỡng cửa sổ thấp (NF-05 §4)
- **Chốt:** < 720pt
- **Vì sao:** Quyết định thiết bị nào nhận metrics chiều cao kiểu thấp.

## K23 — iPhone SE (375×667) trong phạm vi kiểm? (NF-05)
- **Chốt:** Bỏ SE khỏi phạm vi
- **Vì sao:** SE thấp hơn Duo 2pt nhưng không có trong bảng thiết bị.

## K24 — Insights trên cửa sổ thấp (spec-pending FS-07.02)
- **Chốt:** Một hàng câu (~120pt)
- **Vì sao:** Thẻ Insights nhiều hàng ăn chiều cao trên 669pt.

## K25 — Share sau khi Resize chạy sạch ở đâu (FS-03.07 §5)
- **Chốt:** Ở lại màn, Share + Done
- **Vì sao:** Banner cấp app có nút chỉ sống 4 s (FS-03.14c); người resize để gửi đi phải đua với đồng hồ.

## K26 — Collage Export: Share… có lưu vào Photos trước? (FS-11b §3)
- **Chốt:** Lưu rồi share
- **Vì sao:** Công thức collage chỉ được lưu khi xuất (FS-06.01b).

## K27 — Share: phụ đề hàng không vẽ được (FS-08.06 §4)
- **Chốt:** Câu giải thích ở đầu sheet
- **Vì sao:** Dòng hành động của share sheet hệ thống chỉ có tên + icon, không có phụ đề như H2 đề xuất.

## K28 — Trùng tên file khi upload đang chạy nền (FS-15.02b §4)
- **Chốt:** Dò trùng cả lô trước khi đẩy
- **Vì sao:** Lô cần người trả lời mà người dùng không nhìn màn hình.

## K29 — App bị đóng hẳn giữa lô upload (FS-15.02b §4)
- **Chốt:** Bảng riêng, Resume khi mở lại
- **Vì sao:** Người chụp sự kiện mất nhiều nhất ở đúng chỗ này.

## K30 — Hàng Connection khi chỉ có 1 connection (FS-15.02 §2)
- **Chốt:** Vẫn là menu
- **Vì sao:** Add Connection… chuyển vào menu của hàng Connection.

## K31 — Glyph 'In Library' trên ô ảnh server (FS-17.01 §2b)
- **Chốt:** photo.badge.checkmark 14pt
- **Vì sao:** Dấu ✓ tròn hiện tại trông như đã chọn.

## K32 — Glyph hàng Cloud Folders (FS-17.05)
- **Chốt:** cloud
- **Vì sao:** Hàng cloud đổi tên thành Cloud Folders; logo iCloud đọc ra là iCloud Photos.

## K33 — Empty state Statistics lúc index lần đầu (FS-07.01b)
- **Chốt:** "Charts appear as ShotDex reads your photos."
- **Vì sao:** —

## K34 — Footnote Onboarding (FS-09)
- **Chốt:** "Next, iOS asks for access — choose Allow Full Access so ShotDex can read every photo's camera info."
- **Vì sao:** —
