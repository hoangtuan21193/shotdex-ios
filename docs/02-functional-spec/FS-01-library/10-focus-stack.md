# FS-01.10 — Focus Stack

`FS-01.10` · tier D · `ShotDexKit/Render/PhotoStackRenderer.swift` · `Features/Editing/PhotoStack*` · test
`PhotoStackRendererTests`, `FocusStack*Tests` · cập nhật 2026-09-24 · nguồn
[intent](../../_intents/2026-09-23-focus-stack-helicon-parity.md) · [spike](../../_intents/2026-09-24-focus-stack-spike.md)

**Một câu:** Combine Photos ▸ **Focus Stack** ghép một chuỗi focus bracketing (10–200 khung) thành một ảnh nét
suốt chiều sâu, ngang Helicon Focus ở bốn thứ người chụp macro cần: căn đúng khi ống kính đổi độ phóng, hai
cách ghép, hai tham số, và tô sửa từ một khung.

> Trạng thái: **spec, chưa build.** Hôm nay màn Focus Stack (FS-01.09) căn chỉ theo phép dịch, một cách ghép,
> không tham số, khung căn hỏng bị ghép chưa căn mà không báo.
> Các dòng `⚠️ CẦN QUYẾT (tạm chốt)` được chốt theo mặc định đề xuất lúc người dùng vắng (2026-09-24) —
> người dùng xem lại khi duyệt.

## 1. Người dùng cần gì

Người chụp macro bấm một chuỗi khung, mỗi khung nét một lát mỏng; người chụp phong cảnh bấm 3–10 khung
từ tiền cảnh tới vô cực. Họ cần một tấm nét hết, không quầng ở mép vật, không bóng ma do ống kính phóng to
dần khi lấy nét — hôm nay họ mang sang Helicon hoặc Zerene trên máy tính.

## 2. Phạm vi

**Có:** căn dịch + co giãn + xoay · hai cách ghép · Radius · Smoothing · tô sửa từ một khung · báo khung
không căn được · không trần số khung · xuất JPEG theo dải.

**Cố ý không có:** cách ghép pyramid (Helicon C) · xuất bản đồ độ sâu · 3D · batch · Dust Map · DNG/TIFF —
chốt ở câu 1 và 3 của intent.

## 3. Luồng và màn

Tầng D như FS-01.09 §3: `Cancel` · `Focus Stack` · `Save`; stage đen; một panel. Panel, từ trên xuống:

1. **Method** — hai lựa chọn: **Depth Map** (bản đồ độ sâu — mượt, giữ màu, chuỗi dài, bề mặt trơn) và
   **Weighted** (trung bình có trọng số độ nét — lông, tóc, chi tiết đan chéo). Dưới là một câu nói cách đó hợp
   với cảnh nào.
2. **Radius** — slider 1–10. **Smoothing** — slider 0–10. Hàng slider tầng D sẵn có, không component mới.
3. **Retouch** — nút vào chế độ tô sửa (§5).
4. Dòng nhắc căn khung như hôm nay; khi có khung không căn được thì thay bằng dòng báo (§4).

- ⚠️ CẦN QUYẾT (tạm chốt): **cách ghép mặc định** — **Weighted**, Radius 2, Smoothing 0; chọn Depth Map thì
  Radius 4, Smoothing 4. Spike: Weighted nhỉnh hơn 0,3–0,4 dB ở mép độ sâu, bằng nhau ở toàn ảnh.
- Đổi cách ghép hay tham số **không nạp lại khung**: dựng lại từ khung preview đã căn.
- Mở ra với > 50 khung: ước lượng thời gian trước khi ghép, như FS-14.01 §1.

## 4. Căn khung

- Khung đi **theo thứ tự lấy nét**: sắp theo thời điểm chụp, cùng thời điểm thì theo tên file. Không lấy thứ
  tự lưới hay thứ tự chạm.
- Mỗi khung căn với **khung liền trước**, mô hình dịch + co giãn + xoay (4 bậc tự do), rồi nối về khung đầu.
  *Vì* căn thẳng về khung đầu thì một nửa khung thất bại — khung nét gần và nét xa không có chi tiết sắc
  chung (spike §2). Không dùng mô hình phối cảnh đầy đủ: chuỗi trên tripod hay ray chỉ trôi co giãn + dịch.
- Dùng lại bộ dò và so khớp điểm đặc trưng của FS-14, không dùng bộ căn dịch của Vision.
- Khung **không căn được** bị **loại** khỏi ảnh ghép, và panel ghi "2 of 40 frames couldn't be lined up and
  were left out" kèm cách xem đó là khung nào. Không lặng lẽ ghép khung chưa căn.
- Khung giải mã hỏng (iCloud mất mạng…) cũng được nói ra theo cùng cách — hôm nay nó bị bỏ không báo.

## 5. Tô sửa (Retouch)

- Chế độ Retouch: stage hiện ảnh ghép; dưới là **dải khung** (filmstrip của editor, không component mới).
- Chọn một khung trong dải, rồi tô trên stage: vùng tô lấy điểm ảnh **từ khung đó**. Mặc định chọn sẵn khung
  **nét nhất ở chỗ vừa chạm** (như "auto-pick" của Helicon).
- Mỗi nét tô là một bước **Undo**. Rời Retouch giữ nguyên các nét; đổi cách ghép hay tham số thì hỏi trước khi
  xoá chúng.
- Nét tô ghi vào bản đồ "khung nào thắng" (2 byte/điểm ảnh, không phụ thuộc số khung) — Save dùng đúng bản
  đồ đó ở độ phân giải gốc.
- Bút tô chỉ sống trong phiên; không lưu.

## 6. Lưu

- Như FS-01.09 §3: Save → ảnh mới, Cancel giữ lựa chọn, lưu xong mở viewer theo màn đang đứng.
- Full-res **theo dải**, khung giữ trên đĩa và ánh xạ vào bộ nhớ — cùng cách FS-14.02 §6. JPEG chất lượng 0,95.
- Bộ nhớ **không tăng theo số khung** và **không tăng theo cỡ ảnh**.

## 7. Tiêu chí nghiệm thu

Chuỗi thử là khung ảo có đáp án như spike §1 (16 khung, breathing 0/2/5%), dựng trong test từ ảnh nhỏ đóng
trong test bundle. PSNR so với ảnh nét hoàn toàn, bỏ viền 60 px.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | chuỗi 16 khung, breathing 2% | ghép Weighted | PSNR ≥ 33 dB, và ≥ khung đơn tốt nhất + 2 dB | ⚠️ bộ căn đạt (≤ 1 px, `FocusStackAlignmentTests`); PSNR của cả chuỗi chưa đo trong test |
| AC-2 | chuỗi breathing 5% | căn | sai lệch trung bình của phép căn ≤ 1 px | ✅ `FocusStackAlignmentTests.breathingBracketLinesUpWithinAPixel` (0, 2, 5%) |
| AC-3 | chuỗi 16 khung, đảo thứ tự chọn | ghép | cùng kết quả như thứ tự đúng (sắp theo thời điểm chụp) | ⚠️ chưa có — `FocusStackAlignmentTests` |
| AC-4 | chuỗi có 1 khung ảnh khác cảnh chen vào giữa | ghép | khung đó bị loại; panel ghi "1 of 17 frames couldn't be lined up…" | ⚠️ một nửa: `FocusStackAlignmentTests.aFrameFromAnotherSceneIsLeftOutAndTheChainGoesOn`, `PhotoStackRendererTests.aFocusStackLeavesOutAFrameItCannotLineUp`; chưa có ảnh panel |
| AC-5 | cùng chuỗi | chạy Depth Map rồi Weighted | cả hai ≥ 33 dB; Weighted ≥ Depth Map ở vùng mép độ sâu | ⚠️ chưa có — `FocusStackMethodTests` |
| AC-6 | màn Focus Stack đang mở | đổi Method, Radius, Smoothing | preview dựng lại, không nạp lại khung (số lần đọc khung không đổi) | ⚠️ chưa có — `PhotoStackModelTests` |
| AC-7 | mở màn Focus Stack | nhìn panel | Weighted chọn sẵn, Radius 2, Smoothing 0; chọn Depth Map thì Radius 4, Smoothing 4 | ⚠️ chưa có — ảnh + dump |
| AC-8 | ảnh ghép có một vùng lấy sai khung | Retouch: chọn khung 5, tô vùng đó | điểm ảnh trong vùng tô trùng khung 5 (sai ≤ 1/255); ngoài vùng không đổi | ⚠️ chưa có — `FocusStackRetouchTests` |
| AC-9 | vừa tô 3 nét | Undo 3 lần | ảnh ghép trùng từng điểm ảnh với trước khi tô | ⚠️ chưa có — `FocusStackRetouchTests` |
| AC-10 | chạm một điểm trong Retouch | — | khung được chọn sẵn là khung có độ nét cao nhất tại điểm đó | ⚠️ chưa có — `FocusStackRetouchTests` |
| AC-11 | 100 khung × 24 MP | Save | footprint đỉnh ≤ 500 MB, và như nhau (± 10%) ở 10 khung | ⚠️ chưa có — đo tay máy thật + `FocusStackExportTests` |
| AC-12 | 3 khung chỉ trên iCloud, máy mất mạng | mở màn | báo "3 photos couldn't be downloaded" + Retry; không ghép với số khung thiếu mà không báo | ⚠️ chưa có — ảnh |
| AC-13 | đang lưu | Cancel | không asset nào được tạo; thư mục tạm của phiên rỗng | ⚠️ chưa có — `FocusStackExportTests` |
| AC-14 | ảnh ghép đã lưu | xem EXIF trong viewer | máy, ống kính, ngày của khung đầu; không tiêu cự lấy nét | ⚠️ chưa có — `FocusStackExportTests` |

**Chưa chứng minh được:** cả 14 — chưa build. AC-11 là mục tiêu, đo trên máy thật mới chốt.

## 8. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Chỉ có khung ảo; lông tóc thật và quầng mép thật chưa thử | `/verify` chạy thêm trên chuỗi macro thật |
| Khung chụp cùng giây (máy bắn 10 khung/giây) làm thứ tự theo thời điểm chụp không chắc | đường lùi theo tên file; AC-3 là cổng |
| Bộ dò điểm đặc trưng là của FS-14 (phiên khác) | chỉ dùng qua API public của kit, không sửa |
| Bản spike tốn 1,1–1,4 GB ở 24 MP (float trên CPU) | render theo dải, half-float; AC-11 là cổng |
