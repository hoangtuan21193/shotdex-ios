# FS-03.15e — Lens Blur

`FS-03.15e` · `ShotDexKit/Render/DepthImageReader.swift` · kernel trong `ShotDexKit/Render/Kernels/`
· cập nhật 2026-09-28

**Một câu:** thay slider Depth Blur bằng Lens Blur đủ ba thứ Lightroom có — độ mạnh, dải lấy nét, hình
bokeh — cho mọi ảnh: ảnh có bản đồ độ sâu dùng bản đồ đó, ảnh không có thì ước lượng bằng model kèm app.

Tổng quan: [FS-03.15](15-lightroom-parameter-parity.md). Depth Blur hôm nay (bị thay):
[FS-04.03](../FS-04-color-mixer-point-grading/03-depth-blur.md). Kernel: [FS-16](../FS-16-metal-kernels.md).

## 1. Control

Nhóm **Lens Blur** riêng trong danh sách Edit, ngay sau Effects (thay hàng Depth Blur ở đầu Effects):

| Control | Giá trị |
|---|---|
| Amount | 0…100; 0 = ảnh như lúc chụp |
| Bokeh | hàng chip: **Circle · Bubble · 5-Blade · Ring · Cat Eye** (kiểu chip chung FS-03.12) |
| Focus Range | hai hàng **Near · Far** 0…100 trên bản đồ độ sâu chuẩn hoá (0 xa nhất, 100 gần nhất), mặc định 60–100 |
| Focus | chạm ảnh khi đang ở nhóm Lens Blur = đặt dải lấy nét quanh độ sâu tại điểm chạm (±10) |
| Visualize Depth | công tắc: canvas hiện bản đồ độ sâu tô màu, dải lấy nét sáng lên; chỉ hiển thị, không vào file lưu |

- Chạm ảnh để lấy nét chỉ bật khi nhóm Lens Blur đang mở, như ống hút Point Color: mọi cử chỉ mức ảnh tắt,
  dòng nhắc "Tap to focus" dưới đáy ảnh.
- Mỗi cú kéo / một chạm lấy nét là một bước Undo.
- **Không có trong mask** (giữ luật Depth Blur: Lens Blur có ý riêng về vùng). Boost vùng sáng của Lightroom
  không có ở bản này.

## 2. Render

- Chạy **đầu chuỗi**, trên ảnh chưa chỉnh (luật của Depth Blur giữ nguyên) và trong không gian tuyến tính —
  nên đèn nhỏ thành đốm bokeh sáng thay vì vệt xám.
- Bán kính mờ tại một pixel = Amount × **3,5% cạnh ngắn** × khoảng cách độ sâu của pixel ra ngoài dải lấy nét
  (chuẩn hoá). Trong dải: nét hoàn toàn.
- Ảnh chia **8 lớp độ sâu**, mỗi lớp làm mờ bằng hình bokeh của nó rồi chồng từ xa tới gần — tiền cảnh nét
  không bị hậu cảnh mờ tràn đè, hậu cảnh không lem vào mép tiền cảnh.
- Hình bokeh: Circle = đĩa đều; Bubble = đĩa viền sáng hơn; 5-Blade = ngũ giác; Ring = vành sáng, lõi tối;
  Cat Eye = đĩa bị cắt dần về phía mép khung.
- Mặt nạ chân dung (khi có) tinh chỉnh mép người như Depth Blur hôm nay — bản đồ độ sâu chỉ ¼ độ phân giải.
- Kernel viết Metal cho Core Image, có golden ≤ 1/255 (FS-16 §4).

**Giữ mượt khi kéo** — preview không hạ độ phân giải (FS-03.04):
- Preview dựng sẵn **8 mức mờ** ở cỡ hiển thị (8 bán kính cố định, tới bán kính của Amount 100); mỗi pixel
  **trộn** hai mức kề theo bán kính của nó.
- Kéo **Amount** chỉ trộn lại, không làm mờ lại. Kéo slider khác dùng lại kết quả đã trộn — Lens Blur chạy
  trên ảnh chưa chỉnh nên kết quả không đổi.
- Đổi Bokeh, Near/Far hoặc chạm lấy nét: dựng lại 8 mức; trong lúc kéo Near/Far chấp nhận ít khung hơn.
- Lưu ảnh không dựng sẵn: chạy thẳng 8 lớp độ sâu một lần ở độ phân giải đầy đủ. *Vì 8 khung 100MP vượt
  trần 1,5GB (§5 tổng quan).*

## 3. Ảnh không có độ sâu

- **Depth Anything V2** (bản Core ML trên trang model của Apple, ~50MB F16) **kèm trong app**; chạy trên
  máy, không cần mạng.
- Ảnh không có bản đồ độ sâu: ước lượng **một lần** khi mở nhóm Lens Blur, hoặc khi recipe có Lens Blur
  được mở/dán lên ảnh đó. Đầu nhóm ghi nhãn "Estimated depth".
- Trong lúc ước lượng: control Lens Blur mờ kèm vòng quay nhỏ; các nhóm khác vẫn dùng được.
- Kết quả lưu thành file trong kho matte (15d §5); mở lại ảnh đọc file, không ước lượng lại.
- Ước lượng lỗi (Core ML lỗi, thiếu bộ nhớ): trả ảnh gốc, nhóm mờ kèm "Couldn't estimate depth for this
  photo." — không alert.
- Recipe có Lens Blur dán sang ảnh không có độ sâu thì ước lượng trên ảnh đích (thay luật "trả ảnh gốc,
  không đoán" của FS-04.03).
- Số đo thật của model (dung lượng, thời gian, mép tóc) ghi ở AC-60 — là phép đo, không chặn phát hành.

## 4. Thẻ `crs:`

| Control | Thẻ | Ghi chú |
|---|---|---|
| Lens Blur (bật, Amount, Bokeh, Focus Range) | LensBlur (cấu trúc: bật, độ mạnh, hình bokeh, dải lấy nét, boost…) | tên trường và giá trị hình bokeh cần kiểm (§7 tổng quan) |
| Boost vùng sáng | trong LensBlur | không nhập, báo "≈" trong báo cáo import |

## 5. Tiêu chí nghiệm thu

Ảnh thử: 512×512 dựng trong code, nửa trên vân sọc với độ sâu 1,0 (gần), nửa dưới vân sọc với độ sâu 0,2
(xa), bản đồ độ sâu tổng hợp ¼ độ phân giải — cùng cách `DepthBlurTests` đang dựng.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-53 | ảnh thử, Focus Range 70–100 | đặt Amount 50 | phương sai Laplacian nửa gần ≥ 90% ảnh gốc; nửa xa ≤ 40% | ⚠️ chưa có (dự kiến `LensBlurTests.focusRangeKeepsTheNearHalfSharp`) |
| AC-54 | nền tối 0,05 ở độ sâu 0,2 có một điểm sáng 1,0 cỡ 3px; Amount 80, dải lấy nét 70–100 | đặt Bokeh Ring (so với Circle) | Ring: độ sáng vành ≥ 1,3 lần lõi; Circle: vành/lõi ≤ 1,1; cả hai khớp golden ≤ 1/255 | ⚠️ chưa có (dự kiến `LensBlurTests.ringBokehHasABrightRim` + ca golden `lensBlurRing`) |
| AC-55 | ảnh thử, nhóm Lens Blur mở | chạm vào nửa xa | dải lấy nét thành 10–30 (±2); nửa xa nét, nửa gần mờ; Undo một lần trả dải cũ | ⚠️ chưa có (dự kiến `LensBlurTests.tapToFocusCentresTheRange`) + `ShotDexUITests/scripts/iphone-lens-blur.json` |
| AC-56 | ảnh JPEG không có bản đồ độ sâu | Paste Edits từ ảnh có Lens Blur 50, rồi đóng và mở lại ảnh | ước lượng chạy đúng 1 lần; nhãn "Estimated depth"; lần mở lại đọc file, ước lượng 0 lần; không alert | ⚠️ chưa có (dự kiến `LensBlurTests.noDepthPhotoIsEstimatedOnce`, model giả) + ảnh Edit, iPhone 17 26.5 |
| AC-57 | ảnh Portrait 12MP, Lens Blur 50 đã thả tay | kéo Exposure qua 30 giá trị | làm mờ và trộn Lens Blur chạy 0 lần trong lúc kéo; thời gian khung trung bình ≤ 1,1 lần bản Lens Blur tắt; preview đúng cỡ hiển thị | ⚠️ chưa có (dự kiến `LensBlurTests.otherSlidersReuseTheBlendedResult`) |
| AC-58 | ảnh Portrait 12MP, nhóm Lens Blur mở | kéo Amount 20 → 80 qua 30 giá trị | 8 mức mờ dựng 0 lần thêm, chỉ lượt trộn chạy; ở Amount 80, preview lệch bản lưu (chạy thẳng 8 lớp) trung bình ≤ 2/255 | ⚠️ chưa có (dự kiến `LensBlurTests.amountDragOnlyReblends`) |
| AC-59 | ảnh không độ sâu, bộ ước lượng giả trả lỗi | mở nhóm Lens Blur, đặt Amount 50 | ảnh bằng ảnh gốc ± 1/255; nhóm mờ với "Couldn't estimate depth for this photo."; không alert | ⚠️ chưa có (dự kiến `LensBlurTests.estimationFailureRendersTheOriginal`) |
| AC-60 | bản Release trên iPhone 12 và iPhone 15 | đo Depth Anything kèm app | ghi vào §3: dung lượng model trong app (MB), thời gian ước lượng ảnh 12MP, IoU mép tóc với mặt nạ chân dung trên 10 ảnh Portrait hình nộm; phép đo, không ngưỡng chặn | ⚠️ chưa đo — máy thật, Instruments |

**Chưa chứng minh được:** AC-53…AC-60 (chưa code; AC-60 cần máy thật).
