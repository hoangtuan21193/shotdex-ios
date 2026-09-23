# Spike: focus stack ngang Helicon, chỉ bằng API hệ thống

| Trường | Giá trị |
|---|---|
| Cho intent | [2026-09-23-focus-stack-helicon-parity.md](2026-09-23-focus-stack-helicon-parity.md) — câu 4 và 5 |
| Ngày | 2026-09-24 |
| Máy đo | MacBook Pro M1 Max, macOS 27, Swift 6.4, CPU thuần — **chưa đo trên iPhone/iPad** |
| Code | Swift package trong scratchpad của phiên, **không giữ lại** (giống spike panorama) |
| Kết luận | **Căn có co giãn là bắt buộc, không phải thêm cho đủ bộ**: với ống kính đổi độ phóng 2% khi lấy nét, cách căn hiện tại (chỉ dịch) cho ảnh **kém hơn một khung đơn**. Hai cách ghép và bộ nhớ phẳng theo số khung đều làm được |

## 1. Dữ liệu thử

Không có chuỗi focus bracketing thật nào có giấy phép mở tìm được trong lượt này. Thay bằng khung ảo có
đáp án: một vùng của ảnh 360° CC0 `urban_street_01` (Poly Haven, đã dùng cho spike panorama) làm ảnh nét
hoàn toàn, cộng một bản đồ độ sâu tự dựng — nền xa 12 m, một dải giữa 3–7 m, hai đĩa gần 0,6 m và 1,2 m, và
một vùng "lông" mảnh 0,8 m cắt ngang các bậc độ sâu.

- 16 khung, điểm nét chạy đều theo diop từ 0,55 m tới 14 m; mờ theo độ lệch diop từng điểm ảnh (tối đa σ 9 px).
- **Focus breathing**: khung k phóng to `1 + b·k/15` quanh tâm, thử b = 0%, 2%, 5%; thêm lệch ±3 px, xoay ±0,15°.
- Ảnh 1536×1024 cho phần chất lượng; 6000×4000 (24 MP) cho phần bộ nhớ.

**Giới hạn:** mờ theo từng điểm ảnh không có che khuất thật ở mép vật (không có quầng do vật gần che vật xa),
nên số ở vùng mép là cận trên. Chưa thử trên chuỗi chụp ống macro thật.

## 2. Căn khung

| Breathing | Không căn | Chỉ dịch (app hôm nay) | Dịch + co giãn + xoay |
|---|---|---|---|
| 0% | lệch 3,0 px · 20,3 dB | 1,2 px · 24,1 dB | **0,4 px · 30,3 dB** |
| 2% | 5,9 px · 17,3 dB | 5,6 px · **17,7 dB** | **0,2 px · 35,0 dB** |
| 5% | 13,2 px · 15,5 dB | 14,2 px · 16,3 dB | **0,5 px · 31,2 dB** |
| *khung đơn tốt nhất* | 30,9 dB | | |
| *cận trên (mỗi điểm lấy đúng khung nét, hình học thật)* | 36,5–37,1 dB | | |

PSNR so với ảnh nét hoàn toàn, cách ghép trung bình có trọng số, Radius 2.

- **Chỉ dịch không cứu được ống kính breathing**: 2% đã làm ảnh ghép kém hơn khung đơn tốt nhất 13 dB.
  Căn có co giãn thì đưa lên 35 dB, cách cận trên 2 dB.
- **Căn từng khung với khung liền kề**, rồi nối các phép biến đổi về khung 0. Căn thẳng về khung 0 thì
  7/15 khung **thất bại**: khung lấy nét gần và khung lấy nét xa không có chi tiết sắc chung. Helicon cũng
  đòi khung theo thứ tự lấy nét cho cách B.
- Dùng lại bộ dò điểm đặc trưng của panorama (FS-14) với mô hình 4 bậc tự do (co giãn, xoay, dịch), thay
  vì bộ căn dịch của Vision. 0,3–0,7 s cho 15 cặp ở 1536 px.

## 3. Hai cách ghép

| | Theo bản đồ độ sâu (cách hiện có — Helicon B, Zerene DMap) | Trung bình có trọng số độ nét (Helicon A, Zerene PMax) |
|---|---|---|
| Toàn ảnh, breathing 2% | 35,07 dB | 35,07 dB |
| Vùng mép độ sâu | 33,81 dB | **34,16 dB** |
| Breathing 5%, vùng mép | 32,89 dB | **33,23 dB** |

- Trung bình có trọng số nhỉnh hơn **0,3–0,4 dB ở mép**, bằng nhau ở toàn ảnh. Khoảng cách nhỏ trên khung
  ảo; vùng lông tóc thật là nơi Zerene nói PMax hơn hẳn — chưa kiểm được ở đây.
- **Radius 2–10 và Smoothing 0–8 gần như không đổi kết quả** (±0,4 dB) trên bộ này. Mặc định đề xuất:
  Radius 2, Smoothing 0 cho trung bình có trọng số; Radius 4, Smoothing 4 cho bản đồ độ sâu. Khoảng slider
  1–10 và 0–10; số thật phải chỉnh lại trên chuỗi macro thật.

## 4. Bộ nhớ

| Cách | 10 khung × 24 MP | 100 khung × 24 MP |
|---|---|---|
| Bản đồ độ sâu (không giữ khung) | đỉnh ~1,1 GB | **không tăng** |
| Trung bình có trọng số | thêm ~275 MB | **không tăng** |

- **Phẳng theo số khung**: mỗi lúc chỉ một khung giải mã; phần giữ lại là vài mặt phẳng cỡ ảnh ra.
- **Chưa phẳng theo cỡ ảnh**: bản spike giữ mọi mặt phẳng dạng float 32 bit trên CPU — 1,1–1,4 GB ở 24 MP,
  quá trần app trên iPhone đời cũ. Bản thật phải chạy theo dải (như FS-14) hoặc half-float trên GPU.
- **"Khung nào thắng" ở từng điểm ảnh** (cho bút tô sửa và cho cách bản đồ độ sâu) tốn **2 byte/điểm**:
  48 MB ở 24 MP, không phụ thuộc số khung; 16 bit đủ tới 65 535 khung.
- Cách bản đồ độ sâu cần đọc lại khung thắng ở bước cuối: giữ khung trên đĩa và ánh xạ vào bộ nhớ — spike
  panorama đo được 1,1 GB đọc qua ánh xạ chỉ thêm 1 MB footprint.

## 5. Hệ quả cho `/spec`

1. Căn **có co giãn + xoay**, nối khung liền kề — là việc phải làm đầu tiên, trước cả cách ghép thứ hai.
2. Khung phải đi **theo thứ tự lấy nét**. Lựa chọn trong lưới không có thứ tự đó: sắp theo thời điểm chụp
   (focus bracketing của máy chụp liên tục), có đường lùi khi hai khung cùng giây.
3. Hai cách ghép, chuyển qua lại không cần nạp lại khung (bản preview giữ cả hai tổng tích luỹ).
4. Bút tô sửa đọc "khung nào thắng" (2 byte/điểm) và đọc lại khung đó từ đĩa.
5. Render theo dải cho ảnh ra, như FS-14, để bộ nhớ phẳng cả theo cỡ ảnh.
6. Khung căn thất bại thì **nói ra**, không lặng lẽ ghép khung chưa căn (hôm nay app giữ khung chưa căn).

## 6. Chưa trả lời được

- Chuỗi macro thật: lông, tóc, vật chồng lên nhau, quầng ở mép — cần chuỗi có giấy phép mở hoặc do người
  dùng chụp.
- Hiệu năng trên iPhone/iPad, và bản GPU.
- Độ trễ bút tô khi đọc lại khung 45 MP từ đĩa.
