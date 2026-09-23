# Spike: ghép panorama chỉ bằng API hệ thống

| Trường | Giá trị |
|---|---|
| Cho intent | [2026-09-23-panorama-stitch-from-selection.md](2026-09-23-panorama-stitch-from-selection.md) — câu 4 |
| Ngày | 2026-09-23 |
| Máy đo | MacBook Pro M1 Max 64 GB, macOS 27, Swift 6.4 — **chưa đo trên iPhone/iPad** |
| Code | Swift package macOS trong scratchpad của phiên, **không giữ lại** (người dùng chọn) |
| Kết luận | **Khả thi cho mọi mục đã chốt ở câu 6 và 8**, với ba điều kiện: tự viết phần dò điểm đặc trưng (Vision không dùng được), xuất JPEG chứ không HEIC, render theo dải |

## 1. Dữ liệu thử

Không tìm được bộ ảnh panorama "khung rời" có giấy phép CC0/CC-BY rõ ràng (ảnh mẫu `testdata/stitching`
của OpenCV không ghi giấy phép). Thay vào đó: hai ảnh 360° **CC0 của Poly Haven** (`urban_street_01`,
`museum_of_ethnography`, 8192×4096), từ đó dựng khung ảo như máy ảnh xoay thật. Được đáp án chuẩn
(xoay, tiêu cự, gain) để đo sai số bằng số.

Mỗi khung 3000×2000 (dọc 2000×3000), FOV ngang 60°, lệch ngẫu nhiên ±2° yaw/pitch/roll, gain 0.8–1.25,
vignette 30% ở góc, nhiễu, JPEG q92, **thứ tự file xáo trộn**.

| Bộ | Mô tả | Khung |
|---|---|---|
| s1 | 1 hàng ngang, chồng ~33% | 6 |
| s2 | lưới 2 hàng × 5 | 10 |
| s3 | lưới 3×3 trong nhà (bảo tàng, gần, trần/sàn ít chi tiết) | 9 |
| s4 | 1 cột dọc, khung đứng | 4 |
| s5 | 1 hàng + 1 ảnh lạc (khác cảnh) | 6 |
| s6 | vòng 360° | 10 |
| s7 | 1 hàng, chồng chỉ 12% | 4 |
| s8 | 1 hàng, ống kính méo thùng k1 = −0.12, FOV 75° | 5 |

**Giới hạn:** khung ảo không có thị sai (máy xoay đúng tâm), không có vật chuyển động, độ nét thấp hơn ảnh
thật (nguồn 360° bị phóng ~2.2×). Kết quả là **cận trên**; chuỗi chụp tay thật sẽ khó hơn.

## 2. Kết quả theo từng khâu

### 2.1 Căn ảnh — Vision **không dùng được**, tự viết thì tốt

`VNHomographicImageRegistrationRequest` chỉ đúng khi hai khung gần như trùng nhau:

| Lệch giữa hai khung | 1° | 3° | 5° | 12° | 20° | 40° (≈ chồng 34%) |
|---|---|---|---|---|---|---|
| Sai số Vision (px, ảnh 1024) | 0.1 | 23 | 68 | 176 | 303 | 620 |

Nó là công cụ chống rung, không phải để ghép panorama. Mọi chuỗi panorama thật lệch 20–45° giữa hai khung.

Tự viết: góc Harris + mô tả BRIEF-256 + so khớp Hamming hai chiều + RANSAC homography, trên ảnh 1024px:

| | Kết quả |
|---|---|
| Sai số homography từng cặp | trung vị **0.2–0.3 px**, tệ nhất 0.95 px (ảnh 1024) |
| Ghép nhầm cặp không chồng nhau | **0** trên 8 bộ; ảnh lạc ở s5 bị loại đúng |
| Chồng mép tối thiểu | ~15%. s7 (12%) đứt chuỗi thành hai mảnh — cần báo người dùng |
| Thời gian | 0.1–0.36 s cho 4–10 khung (mọi cặp, n²/2) |

### 2.2 Giải camera toàn cục

Cây khung theo số inlier → bundle adjustment Levenberg–Marquardt (xoay từng khung + một tiêu cự chung,
Huber) → chỉnh chân trời (trục x của mọi camera nằm ngang).

| | Kết quả |
|---|---|
| Tiêu cự tự dò (không cần EXIF) | sai **0.00–0.15%** |
| Xoay tương đối | trung vị **0.03°**, tệ nhất 0.25° |
| Sai số chiếu lại sau BA | 0.6 px (ảnh 1024) |
| Ống kính méo, không hiệu chỉnh (s8) | **hỏng**: tiêu cự sai 15%, xoay sai 15–29° |
| s8, thêm hệ số méo k1 vào BA | k1 ra **−0.118** (đúng −0.12), tiêu cự 0.06%, xoay 0.06° |

Thêm k1 vào BA trên bộ không méo làm xoay xấu đi (0.03° → 0.12°): chỉ bật khi không có hồ sơ ống kính.

### 2.3 Bù sáng và trộn

- Bù gain Brown–Lowe dạng tuyến tính **lệch 10–19%** (hệ không đối xứng khi có vignette). Giải trong
  miền log, bình phương tối thiểu: lệch còn **1.3–2.7%** so với đáp án.
- Trộn đa dải (6 tầng Laplacian, mặt nạ theo khung gần tâm nhất, lấp lỗ pull-push trước khi dựng
  tháp ảnh): ở 100% không thấy đường nối hay bóng ma trên bộ tĩnh. So sánh: [nối cứng, không bù](assets/panorama-spike/02-row6-hardseam-nogain.jpg) với [bù + đa dải](assets/panorama-spike/01-row6-spherical.jpg).

### 2.4 Phép chiếu, Auto Crop, Boundary Warp

| | Kết quả |
|---|---|
| Spherical | mọi bộ; vòng 360° ghép liền mép ([s6](assets/panorama-spike/08-360-row10.jpg)) |
| Cylindrical | mọi bộ trừ khi vượt ±71° dọc |
| Perspective | chỉ khi tổng góc hẹp (s7: 2 khung). s1/s2/s3/s6 **không dựng được** — giống Lightroom |
| Panorama dọc | chiếu thường ra hình đồng hồ cát, phủ 59%. **Xoay trục chiếu 90°** (transverse): phủ 93%, cạnh nhà thẳng đứng ([s4](assets/panorama-spike/07-vertical-transverse.jpg)) |
| Auto Crop | hình chữ nhật lớn nhất trong vùng có ảnh: giữ 79–90% diện tích |
| Boundary Warp, bản kéo từng cột | kéo mép về chữ nhật, nhưng **bẻ cong xe và tòa nhà ở mép** ([ảnh](assets/panorama-spike/04-grid2x5-warp-naive.jpg)) |
| Boundary Warp, lưới giữ hình | theo He et al. 2013 bỏ phần giữ đường thẳng: tự nhiên hơn hẳn ([ảnh](assets/panorama-spike/05-grid2x5-warp-mesh.jpg)); còn **một mảnh ảnh bị lặp ở góc dưới trái**. Giải 0.1–1.5 s (9–45 nghìn ẩn) |

### 2.5 Bộ nhớ khi xuất ảnh không giới hạn kích thước

| Việc | Kích thước | Footprint tăng thêm |
|---|---|---|
| Ghi **JPEG** từ luồng hàng (`CGDataProvider` tuần tự) | 24 / 240 / **720 MP** | **+1 / +1 / +2 MB** |
| Ghi **HEIC** cùng cách | 24 / 131 / 240 MP | +173 / +770 / **+1375 MB** |
| Đọc thumbnail 4096 từ JPEG 720 MP | | đỉnh 194 MB |
| 12 khung full-res 24 MP để trên đĩa, `mmap`, đọc hết theo dải | 1.1 GB dữ liệu | **+1 MB** |
| Bản spike giữ cả canvas float trong RAM | 32–37 MP | **4.5–6.9 GB** |

HEIC giữ cả ảnh trong RAM, nên ở cỡ panorama sẽ bị iOS kill. JPEG ghi theo luồng với bộ nhớ gần
như không đổi; giới hạn cứng là 65535 px mỗi cạnh.

### 2.6 Thời gian (M1 Max, Swift CPU, chưa tối ưu)

| Khâu | 10 khung, canvas 8 MP | 10 khung, canvas 32 MP |
|---|---|---|
| Căn ảnh + giải camera | 0.3 s | 0.3 s (làm ở 1024px, không đổi) |
| Chiếu + trộn đa dải | 2.0 s | 10.5 s |
| Boundary Warp lưới | 0.3 s | 2.1 s |

## 3. Hệ quả cho `/spec`

1. **Căn ảnh tự viết**, không dựa Vision. Chạy ở ~1024px nên nhanh và ít bộ nhớ ở mọi kích thước ảnh.
2. **Đầu ra JPEG** khi ảnh lớn. HEIC chỉ dùng được khi ảnh dưới một ngưỡng (khoảng ≤ 50 MP; đo lại trên máy).
   Trần cạnh 65535 px là trần cứng của định dạng, không phải lựa chọn → phải có câu trả lời khi vượt.
3. **Render theo dải**: khung full-res giải mã một lần ra file thô rồi `mmap`, mỗi dải hàng chiếu + trộn
   rồi đẩy thẳng vào bộ ghi JPEG. Trộn đa dải theo dải cần viền chồng giữa các dải, còn các tầng thô tính
   một lần trên cả canvas thu nhỏ — spike **chưa làm** phần này, chỉ chứng minh hai đầu (đọc/ghi) phẳng.
4. **Hiệu chỉnh ống kính trước khi căn** (hồ sơ Lensfun app đã có). Không có hồ sơ thì ước lượng k1 trong BA.
   Vignette nên sửa ở bước này luôn, trước khi bù gain.
5. **Perspective** chỉ bật khi tổng góc hẹp; nút bị mờ kèm lý do, như Lightroom.
6. **Panorama dọc** tự nhận ra và xoay trục chiếu.
7. **Boundary Warp** phải là bản lưới giữ hình **có** ràng buộc đường thẳng và xử lý góc; bản kéo cột
   không đạt "kiểu Lightroom".
8. **Chồng mép < ~15%** → khung rời ra: báo khung nào không nối được, không lặng lẽ bỏ.
9. Số khung lớn: so mọi cặp là n²/2 (50 khung = 1225 cặp). Cần lọc cặp ứng viên trước (thời điểm chụp,
   ảnh thu nhỏ) — chưa đo.

## 4. Chưa trả lời được — phải đo tiếp

- **Hiệu năng và bộ nhớ trên iPhone/iPad thật** (A-series, jetsam thật). Số trên là Mac.
- **Ảnh chụp tay thật**: thị sai, vật chuyển động (bóng ma → cần tìm đường nối tránh vật chuyển động),
  lệch phơi sáng lớn. Khung ảo không có mấy thứ này.
- **PhotoKit có nhận JPEG 200–700 MP không**, và Photos hiển thị ra sao.
- Trộn đa dải theo dải (mục 3.3) và Boundary Warp có ràng buộc đường thẳng (mục 3.7) chưa viết.
- Giới hạn ~50 MP cho HEIC là ước lượng từ tỉ lệ đo được, chưa kiểm.

Ảnh minh họa trong [`assets/panorama-spike/`](assets/panorama-spike/) dựng từ ảnh CC0 của Poly Haven.
