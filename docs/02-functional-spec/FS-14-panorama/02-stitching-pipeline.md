# FS-14.02 — Đường ghép

`FS-14.02` · `ShotDexKit/Render/` · cập nhật 2026-09-23

**Một câu:** các bước từ N khung tới một file JPEG, và luật của từng bước — mỗi luật có con số từ
[spike](../../_intents/2026-09-23-panorama-stitch-spike.md).

## 1. Căn ảnh

- **Không dùng bộ căn homography của Vision.** Nó là công cụ chống rung: đúng 0,1 px khi hai khung lệch
  1°, sai 620 px khi lệch 40° — mà hai khung panorama luôn lệch 20–45°.
- Tự dò: góc Harris + mô tả nhị phân 256 bit + so khớp hai chiều có ratio test + RANSAC homography, trên
  bản ~1024 px của từng khung. Spike: lệch 0,2–0,3 px, 0 cặp ghép nhầm trên 8 bộ.
- Một cặp được nhận khi đủ inlier (Brown–Lowe) **và** tương quan điểm ảnh trong vùng chồng đủ cao. Cả
  hai điều kiện: hoạ tiết lặp (hàng cửa sổ, tường gạch) cho được nhiều inlier giả.
- **Lọc cặp ứng viên** trước khi so khi có > 12 khung: cặp chụp cách nhau xa về thời gian và khác hẳn
  nhau ở bản thu nhỏ thì bỏ. Tới 12 khung so mọi cặp (spike: 10 khung = 45 cặp, 0,3 s trên Mac).
- Chồng mép tối thiểu đo được: **~15%**. Dưới đó chuỗi đứt, khung rơi vào Not Placed.
- Arrange: khung thả tay được căn lại chỉ với khung chạm nó, lấy chỗ thả làm điểm xuất phát.

## 2. Hiệu chỉnh ống kính

- Có hồ sơ ống kính (Lensfun, [FS-03.11](../FS-03-photo-editor/11-parity-with-lightroom.md)) → sửa méo và vignette **trước khi căn**.
- Không có hồ sơ → ước lượng một hệ số méo trong bước giải camera. Spike: méo thùng không sửa làm tiêu
  cự sai 15% và xoay sai 15–29°; ước lượng thì còn 0,06°. Chỉ bật khi không có hồ sơ: bật trên ống kính
  không méo làm kết quả xấu đi (0,03° → 0,12°).

## 3. Giải camera

- Cây khung theo số inlier → tối ưu toàn cục (xoay từng khung + một tiêu cự chung, loss chịu ngoại lệ).
  Tiêu cự lấy từ EXIF nếu có, không thì tự dò (spike: sai ≤ 0,15%).
- **Nhóm lớn nhất** các khung nối được với nhau là panorama; mọi khung còn lại vào Not Placed.
- **Chỉnh chân trời**: trục ngang của mọi camera nằm trên mặt phẳng ngang. Cột một khung (panorama dọc)
  dùng hướng "xuống" trung bình.
- **Panorama dọc** (trải theo chiều dọc nhiều hơn ngang) được chiếu với trục xoay 90°, rồi dựng đứng lại.
  Không xoay thì ra hình đồng hồ cát, chỉ phủ 59% (spike); xoay thì 93%.

## 4. Chiếu và bù sáng

| Phép chiếu | Dựng được khi |
|---|---|
| Spherical | luôn luôn, kể cả vòng 360° (nối liền mép) |
| Cylindrical | cảnh không vượt ±71° theo chiều dọc |
| Perspective | mọi góc ảnh cách tâm < ~78°; thực tế là panorama hẹp, 2–3 khung |

- Độ phân giải đầu ra = độ phân giải gốc của khung (số pixel mỗi độ không đổi) × **Size** (25–100%, mặc định
  100%). Thu nhỏ làm ngay lúc chiếu, không render full rồi mới thu — ảnh 25% rẻ hơn ảnh 100% khoảng 16 lần.
- Bù sáng: một hệ số gain mỗi khung, giải **trong miền log** bằng bình phương tối thiểu. Dạng tuyến tính
  Brown–Lowe lệch 10–19% khi có vignette; dạng log lệch 1,3–2,7%. Tính trên giá trị tuyến tính.
- **Không gian màu**: Display P3 khi có ít nhất một khung P3, sRGB khi không.
- **Ảnh ra là SDR** (chốt 2026-09-23, sau khi đo). Gain map của khung gốc không đi theo.

  Đặc tả cũ đòi giữ gain map. Phép đo cho thấy **không làm được**: gắn dữ liệu phụ vào bộ ghi làm
  footprint tăng **theo số pixel ảnh chính** — +92 MB ở 24 MP, +369 MB ở 96 MP, **+1 230 MB ở 300 MP** —
  tức là mất đúng cái ghi-theo-luồng mà cả đường xuất dựa vào ([kế hoạch §Task 0](../../_plans/2026-09-23-fs-14-panorama.md)).
  Chi tiết ở [§2 mục Cố ý không có](README.md#2-phạm-vi).


## 5. Trộn và mép

- **Trộn đa dải** 6 tầng; đường nối theo khung gần tâm nhất; lấp lỗ ngoài biên khung trước khi dựng tháp
  ảnh (không lấp thì biên panorama có quầng tối). Spike: 100% không thấy đường nối trên bộ tĩnh.
- **Đường nối tránh vùng hai khung khác nhau**: trong vùng chồng, đường nối đi qua chỗ hai khung giống
  nhau nhất, để người hay xe qua lại giữa hai lần bấm hiện **trọn một lần hoặc không hiện**, không bị cắt
  đôi hay hiện hai lần. Tìm trên bản thu nhỏ rồi phóng lên cho dải full-res. Chi phí chưa đo — đo ở `/plan`.
- **Auto Crop**: hình chữ nhật lớn nhất nằm trọn trong vùng có ảnh (spike: giữ 79–90%).
- **Boundary Warp** 0–100: lưới giữ hình kéo biên về chữ nhật — mỗi ô giữ gần một phép đồng dạng của ô
  gốc, **đường thẳng giữ thẳng**, biên nằm trên cạnh chữ nhật. Mức giữa trộn tuyến tính giữa không warp và
  warp đầy đủ; phần còn trống thì Auto Crop cắt.
  Bản kéo từng cột **không đạt**: bẻ cong xe và nhà ở mép (spike, ảnh 04 so với 05).

## 6. Xuất file

- **Render theo dải hàng**: mỗi khung full-res giải mã **một lần** ra file thô trong thư mục tạm của phiên
  rồi ánh xạ lại vào bộ nhớ; mỗi dải chiếu + trộn rồi đẩy thẳng vào bộ ghi. Spike: đọc 1,1 GB khung qua
  ánh xạ chỉ thêm 1 MB footprint; giữ cả canvas float trong RAM tốn 4,5–6,9 GB cho 32–37 MP.
- Trộn đa dải theo dải: tầng thô tính một lần trên cả canvas thu nhỏ, tầng mịn tính theo dải có viền chồng.
- **Luôn JPEG**, chất lượng 0,95. Ghi JPEG theo luồng: 720 MP chỉ thêm 2 MB footprint; HEIC giữ cả ảnh
  (240 MP thêm 1,4 GB — vượt trần bộ nhớ của app trên iPhone). Một luật, không ngưỡng phải đo trên từng máy.
- **Vượt 65535 px một cạnh** (trần cứng của JPEG): thu nhỏ cho vừa 65535 và **nói trước khi lưu**, dưới
  nút Save ("Will save at 65,535 × 9,120 — the largest a JPEG can be").
- **AC-12** (footprint ≤ 500 MB, lưu 10 × 24 MP ≤ 120 s trên iPhone 17) là **mục tiêu**: `/plan` thiết kế theo
  nó, `/verify` đo trên máy thật rồi chốt số.
- Tạo asset **từ file**, không từ dữ liệu trong RAM (đường lưu của Combine nhận cả ảnh nén trong RAM — không
  dùng được ở cỡ này). Thư mục tạm xoá khi xong, khi Cancel, và bởi lượt quét mồ côi lúc khởi động
  ([NF-02 §2](../../04-non-functional-design/NF-02-memory-and-resources.md)).

## 7. Metadata

- Lấy từ **khung đầu tiên theo thứ tự ghép** (khung trái nhất của hàng trên cùng): máy, ống kính, tiêu cự,
  ngày chụp, vị trí.
- Tốc độ, khẩu, ISO, bù sáng: giữ nếu **mọi** khung giống nhau, bỏ nếu khác.
- Kích thước pixel là của ảnh ra; hướng ảnh là "thẳng" (đã dựng đứng khi render).
- **Thẻ panorama trong file** (XMP): mọi ảnh ghép mang **thẻ riêng của ShotDex** (đã ghép, phép chiếu, số
  khung). Thêm thẻ **GPano** chuẩn chỉ khi phép chiếu là Spherical — GPano chỉ tả đúng phép chiếu
  equirectangular; ghi nó cho Cylindrical/Perspective là khai sai với app khác (Google Photos coi là ảnh cầu).
- Indexer đọc thẻ này và coi ảnh là panorama ([BD-03](../../01-basic-design/BD-03-metadata-indexing-flow/README.md)).
  Thẻ đi theo file qua iCloud và sang máy khác; không bảng DB nào phải giữ nó. Cách ghi vào index (cột kiểu
  chụp hiện có hay cột mới) — `data-migration` xét ở `/plan`.
