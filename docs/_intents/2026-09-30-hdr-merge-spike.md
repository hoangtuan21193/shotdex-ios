# Spike: ghép HDR từ loạt bracket, chỉ bằng API hệ thống

| Trường | Giá trị |
|---|---|
| Cho intent | [2026-09-30-hdr-merge.md](2026-09-30-hdr-merge.md) — câu 6 |
| Ngày | 2026-09-30 |
| Máy đo | MacBook Pro M1 Max, macOS 27, Swift 6.4; giải mã RAW qua Core Image (GPU), phần ghép chạy CPU một luồng — **chưa đo trên iPhone/iPad** |
| Code | Swift package trong scratchpad của phiên, **không giữ lại**, như spike panorama và focus stack. Dùng lại nguyên văn `FocusStackAligner`, `PanoramaImage`, `PanoramaFeatureDetector`, `PanoramaMatcher` của ShotDexKit |
| Kết luận | **Làm được, theo hướng: ghép radiance từ RAW → tone map bằng exposure fusion của các phơi sáng ảo.** Bộ căn khung của Focus Stack dùng lại được nguyên văn. Khử bóng ma phải so với khung **gần tham chiếu nhất mà chưa cháy**, không phải với khung tham chiếu cố định. Giải mã 5 RAW 24 MP theo dải giữ đỉnh khoảng 400–500 MB. Rủi ro còn lại là **tone map ở cỡ đầy đủ**: kết quả của nó phụ thuộc độ phân giải, nên phải chạy trên cả tấm (dạng lát như bộ trộn của panorama), không được suy ra từ preview |

## 1. Dữ liệu thử

Không có loạt bracket thật nào có giấy phép mở trên máy. Thay bằng **khung ảo có đáp án**, dựng từ RAW thật
không có mặt người (kiểm bằng Vision):

- **om5** — `OM_System_OM-5_2_regular.ORF`: trời mây sáng, hàng rào cây tối. **canal** — `L1070048.DNG`: kênh
  nước dưới tán cây, trời sáng ở cuối. Giải mã tuyến tính (`CIRAWFilter`, `boostAmount` 0) ở 1536 px.
- Kéo tương phản trong miền log lên **14 EV** giữa phân vị 0,5% và 99,9% của độ sáng (giữ tỉ lệ màu), đặt
  phân vị 99,9% ở **3 EV trên điểm cháy của EV 0**: om5 có 38,7% điểm ảnh cháy ở EV 0, canal có 6,0%. Đây là
  cảnh ảo "khó hơn thật" — một cảnh ngược sáng thật thường 10–12 EV.
- Mỗi khung là một phơi sáng RAW của cảnh đó: nhiễu shot + nhiễu đọc (full well 30 000 e⁻, đọc 3 e⁻), 14-bit,
  cháy ở 1. Bản "JPEG trong máy" là sRGB 8-bit của chính khung đó.
- Bộ bracket: 3 khung −2/0/+2 EV và 5 khung −4…+4 EV.

**Giới hạn:** JPEG giả lập dùng đường sRGB biết trước, nên đảo ngược được hoàn hảo. JPEG của máy thật có đường
tông riêng của hãng, và đảo ngược nó để dựng radiance thì phải hiệu chuẩn đường phản hồi của máy (Debevec). Phần
lợi thật của RAW vì vậy **lớn hơn** con số dưới đây. Chưa thử trên loạt chụp thật.

## 2. Cách ghép

PSNR so với đáp án sạch nhiễu, cùng toán tử. Mỗi cách so với chính câu trả lời của nó (Mertens trên cảnh sạch ở
cùng bộ EV; radiance + tone map so với tone map của cảnh sạch), vì hai cách cho sắc độ khác nhau và so chéo không
có nghĩa. "Sai số radiance" là RMS theo stop của độ sáng.

| Cách | om5, 3 khung | om5, 5 khung | canal, 3 khung | canal, 5 khung |
|---|---|---|---|---|
| Mertens trên JPEG | 49,8 dB | 42,7 dB | 48,9 dB | 49,0 dB |
| Mertens trên RAW (float) | 50,5 dB | 42,9 dB | 49,4 dB | 49,6 dB |
| Radiance từ JPEG + tone map | 38,1 dB · 0,073 stop | 51,6 dB · 0,017 stop | 30,3 dB · 0,178 stop | 54,0 dB · 0,020 stop |
| **Radiance từ RAW + tone map** | 38,1 dB · 0,072 stop | **52,1 dB · 0,016 stop** | 30,3 dB · 0,177 stop | **54,5 dB · 0,019 stop** |

- **3 khung ±2 EV không đủ cho cảnh 14 EV**: khung −2 vẫn cháy một stop trên cùng, sai số vùng sáng 0,1–0,7
  stop. 5 khung ±4 EV phủ được cả cảnh. Máy chụp 3 khung ±2 EV sẽ ra ảnh tốt ở cảnh thật 10–11 EV. Đây là giới
  hạn của dữ liệu đầu vào, không phải của cách ghép.
- **RAW hơn JPEG 0,5–0,6 dB** trên dữ liệu giả lập (lợi thật lớn hơn — §1). Khác biệt rõ nhất ở vùng tối: sai số
  0,060 so với 0,062 stop (om5), 0,069 so với 0,074 stop (canal).
- **Mertens và radiance + tone map trông gần như nhau** khi tone map chính là exposure fusion của các phơi sáng
  ảo (ảnh `cmp.jpg` trong scratchpad). Khác biệt nằm ở chỗ khác:
  - **Radiance cho một thanh "độ mạnh" có nghĩa**: co giãn khoảng EV của các phơi sáng ảo. Ở độ mạnh 0,5 và
    0,75, ảnh ra khớp đáp án ở cùng độ mạnh 52,9 / 52,3 dB (om5, 5 khung). Mertens thì bị trói vào bộ EV đã chụp.
  - Radiance đi qua được mọi thứ sau đó (Auto Tone, editor) vì nó là ảnh tuyến tính.
- Ở độ mạnh 1, mây bị "HDR quá tay" (tối, đậm viền). Độ mạnh mặc định nên thấp hơn 1 — chốt ở `/spec` bằng mắt.
- Thời gian ghép radiance: 0,12 s cho 5 khung 1,8 MP trên CPU một luồng, tức khoảng 1,7 s ở 24 MP.

## 3. Căn khung khi các khung lệch sáng nhau

Dùng `FocusStackAligner.align` nguyên văn: đặc trưng góc + RANSAC, mô hình tương tự 4 bậc tự do, căn **khung
liền kề** rồi nối chuỗi về khung đầu, ở cạnh làm việc 768 px. Sai số trung bình trên lưới điểm, tính theo px ở
1536 px:

| Bước EV · lệch · xoay | Đầu vào | om5 (4 khung) | canal (4 khung) |
|---|---|---|---|
| 2 EV · ±8 px · ±0,4° | JPEG như chụp | 0,04 – 0,29 | 0,06 – 0,21 |
| | RAW, đưa về cùng phơi sáng | 0,05 – 0,17 | 0,04 – 0,21 |
| 3 EV · ±8 px · ±0,4° | JPEG như chụp | 0,03 – 0,36 | 0,09 – 0,28 |
| | RAW, đưa về cùng phơi sáng | 0,02 – 0,27 | 0,05 – 0,41 |
| 2 EV · ±30 px · ±1,5° | JPEG / RAW | 0,05 – 0,21 / 0,04 – 0,18 | 0,05 – 0,09 / 0,03 – 0,12 |
| 3 EV · ±30 px · ±1,5° | JPEG / RAW | 0,03 – 0,27 / 0,03 – 0,38 | 0,05 – 0,19 / 0,05 – 0,22 |

- **Không khung nào thất bại.** Bộ căn của Focus Stack chịu được bước 3 EV và cầm tay ±30 px, ±1,5°, ~0,1 s.
- Đưa RAW về cùng phơi sáng trước khi căn không hơn rõ so với để nguyên: bộ mô tả đặc trưng đã không phụ thuộc
  độ sáng. Căn bằng bản đã đưa về phơi sáng chung vì đường RAW có sẵn bản đó.
- Sai số tăng theo khoảng cách chuỗi (khung cuối lớn nhất), dưới 0,4 px ở 1536 px, tức khoảng 1,5 px ở 6000 px. Phần
  còn lại để khử bóng ma lo (§4).
- Chuỗi phải đi theo **thứ tự EV**, không theo thứ tự chọn — như Focus Stack đi theo thứ tự lấy nét.

## 4. Khử bóng ma

Một mảng 160 px của cảnh di chuyển giữa các khung; khung tham chiếu là khung EV 0. Mỗi khung khác được so với
tham chiếu theo độ lệch chuẩn của nhiễu (shot + đọc + lượng tử); chỗ lệch quá ngưỡng `z` thì khung đó bị bỏ ở
đó (có giãn vùng).

**Phát hiện chính: phải so với khung "neo" tại từng điểm ảnh** — khung tham chiếu nếu nó chưa cháy ở đó, không thì
khung ngắn hơn gần nhất còn đọc được. Bản đầu so cố định với EV 0 và bỏ sót đúng vật sáng di chuyển trong vùng trời
cháy (38% ảnh ở om5): sai số chỉ giảm 0,93 → 0,78 stop. Bản dùng khung neo:

| Chuyển động | Mức | Sai số ở vùng động (tham chiếu đọc được) | Điểm tĩnh bị bỏ nhầm |
|---|---|---|---|
| Vật sáng, 70 px/khung, canal | Tắt | 0,940 stop | 0% |
| | Thấp / Trung bình / Cao | 0,026 / 0,021 / 0,022 stop | 0,13% / 0,30% / 2,13% |
| Vật sáng, 70 px/khung, om5 | Tắt | 0,635 stop | 0% |
| | Thấp / Trung bình / Cao | 0,013 / 0,013 / 0,013 stop | 0,10% / 0,21% / 1,29% |
| **Kết cấu lay nhẹ, 3 px/khung, canal** | Tắt | 0,926 stop | 0% |
| | Thấp / Trung bình / Cao | **0,186 / 0,075 / 0,064 stop** | 0,06% / 0,16% / 1,86% |
| Kết cấu lay nhẹ, 3 px/khung, om5 | Tắt | 0,504 stop | 0% |
| | Thấp / Trung bình / Cao | 0,018 / 0,015 / 0,015 stop | 0,03% / 0,09% / 1,04% |

Ngưỡng `z` = 12 / 7 / 5, giãn vùng 2 / 4 / 8 px. Chi phí khoảng 0,05 s cho mỗi 1,8 MP.

- **Bốn mức có ý nghĩa**: chuyển động mạnh thì mức nào cũng bắt được; chuyển động nhẹ (lá lay) thì Thấp bỏ sót
  nhiều (0,19 stop), Trung bình và Cao bắt được (0,07). Cái giá của mức Cao là bỏ nhầm 1–2% vùng tĩnh, làm vùng tối
  nhiễu hơn một chút (0,069 → 0,072 stop). **Mặc định đề xuất: Trung bình.**
- Ngưỡng lấy theo mô hình nhiễu của cảm biến. Bản đầu dùng `z` 3,5 cho mức Cao và bỏ nhầm tới 40–62% vùng tĩnh: ngưỡng
  phải tính cả lượng tử 14-bit, và phải chỉnh lại trên loạt chụp thật (nhiễu thật không đúng mô hình).
- **Vùng mà khung tham chiếu cháy thì không khôi phục được** (1,6% ảnh ở om5): ở đó chỉ các khung ngắn thấy được
  vật, mà chúng thấy nó ở vị trí khác. Kết quả là **một** bản của vật, lấy từ khung neo, không phải nhiều bóng
  chồng lên nhau. Lightroom cũng vậy.

## 5. Bộ nhớ và thời gian ở 24 MP

`IMG_6310.CR3`, 6000 × 4000. Mỗi biến thể chạy trong một tiến trình riêng; đỉnh là `phys_footprint`, **tính cả bộ
đệm đầu ra** (RGBA half-float).

| Cách giải mã | Thời gian | Đỉnh |
|---|---|---|
| Cả tấm, 1 khung | 0,49 s | 1310 MB |
| Cả tấm, 5 khung lần lượt | 2,2 s | 1329 MB |
| Dải 512 hàng, 1 khung | 0,51 s | 755 MB |
| Dải 256 hàng, 5 khung lần lượt | 2,7 s | 495 MB |
| **5 bộ giải mã cùng sống, xen kẽ theo dải 256 hàng** (cách một phép ghép đọc) | **2,7 s** | **501 MB** |
| 5 bộ giải mã cùng sống, dải 128 hàng | 3,2 s | 391 MB |

- **Ghép theo dải từ RAW làm được**: 5 bộ `CIRAWFilter` cùng sống không làm đỉnh nhân lên 5 lần. Bộ giải mã đọc theo
  vùng được hỏi; render nhiều dải của cùng một `outputImage` không giải mã lại (dải 256 hàng chỉ chậm hơn cả tấm
  khoảng 10%).
- Phần ghép và khử bóng ma chỉ cần dải hiện tại của mọi khung, cộng một lề bằng bán kính giãn vùng.
- Chưa đo trên iPhone. Mức nền của `CIRAWFilter` (~400 MB ở đây) là thứ phải đo đầu tiên trên máy thật.

## 6. Tone map ở cỡ đầy đủ — rủi ro còn lại

Exposure fusion là một kim tự tháp Laplace: nó cần cả tấm ở tầng thô, không chạy theo dải được nếu không có lề
rất lớn. Đã thử **tone map ở 1/4 và 1/8 kích thước**, rồi phóng hệ số gain độ sáng lên cỡ đầy đủ (song tuyến, và
lọc dẫn hướng theo độ sáng):

| | Số tầng cố định 8 | Số tầng theo cỡ ảnh (tầng thô ~6 px) |
|---|---|---|
| 1/4, so với tone map cỡ đầy đủ | 18,7 dB (om5) · 23,0 dB (canal) | **29,9 dB · 30,7 dB** |
| 1/8 | 15,9 dB · 21,4 dB | 28,5 dB · 29,0 dB |

- **Số tầng của kim tự tháp phải theo cỡ ảnh.** Với số tầng cố định, ảnh nhỏ bị nén cục bộ khác hẳn ảnh lớn. Đây
  cũng đúng với **preview so với bản lưu**: preview 1536 px và bản lưu 24 MP chỉ giống nhau khi số tầng theo cỡ ảnh.
- **Kể cả vậy vẫn còn ~30 dB** — thấy được ở chi tiết nhỏ, vì fusion tăng tương phản vi mô mà gain trơn không mang
  theo. Lọc dẫn hướng không giúp (±0,5 dB). Suy ra: **bản lưu phải tone map trên cả tấm**, dạng lát trên GPU như
  bộ trộn đa dải của panorama (`PanoramaCIBlender`, FS-14), chứ không suy ra từ bản nhỏ.
- Bộ nhớ của bước này ở 24 MP **chưa đo** — đây là thứ spike chưa trả lời.

## 7. Đề xuất cho `/spec`

1. **Đường ghép:** RAW → radiance tuyến tính → tone map bằng exposure fusion của các phơi sáng ảo. Thanh độ mạnh
   co giãn khoảng EV ảo; Auto Tone chạy trên kết quả. Loạt JPEG/HEIC đi cùng đường sau khi đảo ngược sRGB, và ghi
   rõ đó là xấp xỉ (§1).
2. **Căn khung:** dùng lại `FocusStackAligner` nguyên văn, chuỗi theo thứ tự EV, căn trên bản đã đưa về phơi sáng
   chung.
3. **Khử bóng ma:** khung neo theo từng điểm ảnh; bốn mức Tắt / Thấp / Trung bình / Cao; **mặc định Trung bình**;
   ngưỡng lấy từ mô hình nhiễu và chỉnh lại trên loạt chụp thật.
4. **Bộ nhớ:** giải mã và ghép theo dải 128–256 hàng với 5 bộ giải mã cùng sống; tone map dạng lát trên GPU với số
   tầng theo cỡ ảnh. Trần cần một AC đo trên iPhone 12.
5. **Chọn khung:** 3 khung ±2 EV là đủ cho cảnh thường; nên nói rõ khi loạt quá hẹp so với cảnh (còn vùng cháy
   trong khung ngắn nhất).

## 8. Chưa đo được

- Loạt bracket **chụp thật**: cầm tay, nhiễu thật, đường tông JPEG của hãng.
- Mọi con số trên **iPhone/iPad**: nền bộ nhớ của `CIRAWFilter`, thời gian giải mã, tone map dạng lát.
- Bộ nhớ và thời gian của **tone map cỡ đầy đủ** ở 24 MP.
- Vùng mép có che khuất thật, halo ở biên sáng tối mạnh khi độ mạnh cao.
