# FS-03.16a — Nguồn sửa ống kính và render

`FS-03.16a` · kit `ShotDexKit/Render/` · render `ShotDexKit/Render/PhotoRenderService.swift` · Optics
`ShotDexKit/Render/PhotoRenderService+Optics.swift` · bộ duyệt maker notes hiện có
`ShotDex/Domain/Metadata/MakerNoteParser.swift` · cập nhật 2026-09-28

**Một câu:** mỗi nguồn ở [FS-03.16 §3](16-lens-correction-sources.md) đọc gì, quy về một dạng chung thế nào,
và ba mức độ mạnh tác động lên ảnh ra sao.

## 1. Nguồn 1 — dữ liệu hãng ghi trong file RAW

| Hãng | Nơi ghi (xác nhận ở spike) | Có gì |
|---|---|---|
| Sony ARW | `DistortionCorrParams` · `VignettingCorrParams` · `ChromaticAberrationCorrParams` | méo, tối góc, CA đỏ/lam — bảng giá trị theo bán kính |
| Fujifilm RAF | `GeometricDistortionParams` · `VignettingParams` · `ChromaticAberrationParams` | cả ba, bảng theo bán kính |
| Panasonic RW2 | `DistortionInfo` | méo; tối góc và CA xác nhận ở spike |
| OM / Olympus ORF | maker notes nhóm ImageProcessing | méo; tối góc và CA xác nhận ở spike |
| DNG | `WarpRectilinear` (OpcodeList3) · `FixVignetteRadial` (OpcodeList2/3) | méo + CA (hệ số riêng từng kênh), tối góc — đa thức theo đặc tả DNG công khai |
| Canon CR3, Nikon NEF | — | không đọc trong spec này → nguồn 2 |

- v1 đọc **cả năm định dạng**. Spike với RAW thật của từng hãng là bước kiểm cách đọc, không cắt hãng khỏi v1.
- Mặt nào file không ghi thì **lấy bù từ Lensfun** nếu ống có dữ liệu mặt đó (FS-03.16 §3); Lensfun cũng thiếu
  thì slider mặt đó mờ. Nguồn chọn **theo từng mặt**, phần của Apple vẫn tắt.
- Đọc từ **byte của file gốc**; bản đã sửa/xuất mất maker notes nên không có nguồn 1.
- Bộ duyệt TIFF của bộ đếm màn trập hôm nay nằm ở app; chuyển xuống kit để dùng chung, không viết cái thứ hai.
- Khối thiếu, số phần tử sai, hoặc giá trị ngoài ngưỡng tin được → coi như **không có**, rơi xuống nguồn 2.
  Ngưỡng tin được: méo dịch góc ≤ 15% bán kính, gain tối góc 1–4×, lệch CA ≤ 0,5% bán kính.

## 2. Nguồn 2 — Lensfun, thêm tối góc và CA

- Script đổi dữ liệu giữ thêm `<vignetting model="pa">` (tiêu cự, khẩu độ, khoảng cách, k1–k3) và
  `<tca model="linear">` / `<tca model="poly3">`, **chép nguyên văn** như phần méo.
- Ống chỉ có tối góc hoặc chỉ có CA (không có méo) giờ cũng vào bảng — script hôm nay bỏ qua chúng.
- Nội suy: méo và CA theo tiêu cự (như hôm nay); tối góc theo tiêu cự **và** khẩu độ EXIF, khoảng cách lấy bản
  đo xa nhất khi EXIF không ghi.
- Việc khớp chạy cho **cả RAW** (hôm nay bị bỏ qua khi nguồn là RAW).
- Tự khớp **bỏ** dòng hiệu chuẩn trên cảm biến nhỏ hơn thân máy (crop ống > crop thân + 0,05): góc ảnh nằm
  ngoài trường đã đo. Chọn tay vẫn được. Hôm nay bộ khớp không xét crop.

## 3. Nguồn 3 và 4

- **Nguồn 3** chỉ khi không có nguồn 1 và 2, và bộ giải RAW báo hỗ trợ sửa ống kính: công tắc chung bật/tắt
  phần sửa của Apple, ba slider mờ.
- Bộ giải báo không hỗ trợ → **nguồn 4**, không sửa gì.

## 4. JPEG / HEIC

- Chỉ nguồn 2 rồi 4. Mặc định **tắt** như hôm nay; bật thì dùng ống tự khớp hoặc mở danh sách chọn.
- Ảnh điện thoại: Lensfun gần như không có ống điện thoại, và camera đã nắn sẵn → nguồn 4 là đúng (FS-03.11 §7).
- ShotDex đọc **thẻ trạng thái sửa** trong maker notes của JPEG: Sony, Panasonic, OM ghi bật/tắt; Fujifilm
  (nắn JPEG với ống XF) xác nhận ở spike.
- Thẻ báo máy đã sửa → bật công tắc **không tự khớp**, hàng trạng thái nói rõ lý do (16b §2); Choose Lens vẫn
  dùng được. *Vì* sửa lần hai là méo ngược, tối góc thành sáng góc, người dùng khó nhận ra vì sao.
- Không có thẻ, hoặc thẻ báo chưa sửa → tự khớp như thường.

## 5. Render

- **Tối góc ở ánh sáng tuyến tính, trước tone.** RAW: trong khe lọc tuyến tính của `CIRAWFilter`, chạy trước
  đường cong tone của bộ giải. JPEG: pass đầu tiên sau giải mã — Core Image làm việc trong không gian tuyến tính.
- **RAW khi kéo Vignetting**: editor giữ sẵn một bản giải mã tuyến tính half-float, trước tone; kéo slider chỉ
  nhân gain lên bản đó, không giải mã lại, không hạ độ phân giải (FS-03.04).
- Đánh đổi: bộ nhớ cache nền RAW gấp ~2× (half-float thay 8-bit). *Vì bù sau cache 8-bit đã qua tone thì
  tỉ số góc/tâm sai khi Exposure +1 EV (AC-a9).*
- **Méo + CA một pass**, ở vị trí pass nắn hôm nay: đầu nhóm hình học, trước Geo, crop và mask (render:382).
- Pass này là **kernel lấy mẫu Metal mới** (FS-16) đọc R, G, B ở ba bán kính. *Vì* kernel warp của Core Image
  trả một toạ độ cho cả ba kênh nên không tách được đỏ/lam; ba lượt warp tốn ~3× mỗi khung.
- **Dạng chung** (đề xuất, chốt sau spike): mọi nguồn quy về một bảng theo bán kính cho ba mặt — tỉ lệ méo,
  gain tối góc, tỉ lệ bán kính đỏ và lam so với lục. Đa thức Lensfun/DNG lấy mẫu vào cùng bảng.
- Bán kính quy về khung hiệu chuẩn như FS-03.11 §7 cho cả ba mặt; nguồn 1 dùng khung cảm biến của chính file.

| Mặt | Ở độ mạnh s = slider / 100 | 0 | 200 |
|---|---|---|---|
| Méo | dịch chuyển = s × dịch chuyển của hồ sơ; zoom lấp tính lại, trần 1,5× | không warp, zoom 1,0 | gấp đôi |
| Tối góc | gain = (gain hồ sơ)^s | gain 1 | gain bình phương |
| CA | lệch đỏ/lam = s × lệch của hồ sơ | không lệch | gấp đôi |

- **Chip Remove CA giữ nguyên**: khử viền màu nhẹ, không theo hồ sơ (render Optics :72) — "sửa CA không cần
  hồ sơ", tách khỏi phần hồ sơ như Lightroom. Luôn hiện, cùng bật được với slider CA theo hồ sơ.
- *Vì* ảnh không có hồ sơ ống chỉ còn chip này để sửa CA, và thẻ CA tự động của preset Lightroom (14b) đặt vào đây.

## 6. Không sửa hai lần

| Nguồn đã giải | Phần của Apple | Pass của ShotDex |
|---|---|---|
| 1 hoặc 2 | tắt | chạy, theo ba mức |
| 3 | theo công tắc | không chạy |
| 4 | tắt | không chạy |

Hai slider chỉnh tay của FS-03.15 cộng lên trên mọi nguồn: đó là chỉnh tay, không phải sửa lần hai.

- RAW vừa mở: nguồn giải lúc mở, giữ trong phiên và render theo nó; chỉ ghi vào recipe ở lần chỉnh đầu tiên
  (FS-03.16 §3). Ảnh chưa chỉnh vẫn là "chưa sửa".

## 7. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-a1 | khối maker notes tách từ một ARW Sony có cả ba bộ thông số | giải nguồn | nguồn = 1; dịch chuyển ở góc ảnh 2400px khớp giá trị tính tay từ bảng trong 0,5px; phần của Apple tắt | ⚠️ chưa có |
| AC-a2 | DNG có `WarpRectilinear` với hệ số kênh đỏ khác kênh lam | render ở 100 | bán kính góc của đỏ và lam lệch nhau đúng theo hai bộ hệ số, trong 0,5px | ⚠️ chưa có |
| AC-a3 | CR3 Canon EOS R5 + EF 24-70mm f/2.8L II USM (có trong Lensfun, không có nguồn 1) | giải nguồn và render ảnh phẳng xám tổng hợp | nguồn = 2; phần của Apple tắt, không tổ hợp nào bật cả hai (bảng §6); tỉ số gain góc/tâm khớp mô hình `pa` ở tiêu cự/khẩu độ EXIF trong 1/255 | ⚠️ chưa có |
| AC-a4 | ARW có `DistortionCorrParams` bị cắt cụt (ít phần tử hơn khai báo) | giải nguồn | không crash; ống có trong Lensfun → nguồn 2, không có → nguồn 3 | ⚠️ chưa có |
| AC-a5 | RAW hãng chưa đọc (Pentax PEF), ống không có trong Lensfun, bộ giải báo hỗ trợ | giải nguồn | nguồn = 3: phần của Apple theo công tắc, pass của ShotDex không chạy; kéo ba slider không đổi ảnh (lệch ≤ 1/255) | `LensCorrectionResolverTests.unsupportedMakerWithDecoderSupportIsBuiltIn` (seam `decoderSupportsLensCorrection`; ba slider 0 và 200 lệch ≤ 1/255) · ⚠️ file PEF thật trên sim: chưa |
| AC-a6 | RAW có ống không có ở nguồn 1, 2, và bộ giải báo không hỗ trợ | render | nguồn = 4: phần của Apple và pass của ShotDex đều tắt; ảnh lệch ≤ 1/255 so với bản giải tắt sửa ống kính | `LensCorrectionResolverTests.noDecoderSupportIsNone` |
| AC-a7 | ảnh nguồn 2 đủ ba mặt | đặt cả ba về 0 | ảnh lệch ≤ 1/255 so với công tắc tắt; zoom lấp = 1,0 | ⚠️ chưa có |
| AC-a8 | cùng ảnh | đặt cả ba về 200 | dịch chuyển méo ở góc = 2× mức 100 (±0,5px); gain tối góc = bình phương mức 100 (±1%); lệch CA = 2× (±0,5px) | ⚠️ chưa có |
| AC-a9 | ảnh phẳng 18% tuyến tính, tối góc tổng hợp góc 50%, hồ sơ khớp | render RAW ở Exposure 0 rồi +1 EV | tỉ số góc/tâm đo tuyến tính = 1,00 ± 0,01 ở **cả hai** mức Exposure | ⚠️ chưa có |
| AC-a10 | ống hiệu chuẩn crop 1,0 trên thân crop 1,53; và ống chỉ hiệu chuẩn crop 1,53 trên thân full frame | giải nguồn | ca đầu: nguồn 2, dịch góc bằng giá trị hồ sơ ở r = 1/1,53 bán kính góc full frame (±0,5px); ca sau: không tự khớp | `LensProfileTests.smallerSensorCalibrationIsNotAutoMatched` · `…normalizationFollowsTheCalibrationFrame` (cùng bán kính chuẩn hoá cho cả ba mặt) |
| AC-a11 | HEIC iPhone 17 Pro | mở editor | nguồn = 4, không có bước sửa ống kính; ảnh giống bản không sửa | `LensCorrectionResolverTests.iPhoneHEICResolvesToNone` (nguồn 4 + render bằng bản tắt ≤ 1/255) |
| AC-a12 | khối maker notes tách từ một RAF Fujifilm có cả ba bộ thông số | giải nguồn | nguồn = 1; dịch chuyển méo và lệch CA ở góc ảnh khớp giá trị tính tay từ bảng trong 0,5px; gain tối góc trong 1% | ⚠️ chưa có |
| AC-a13 | khối maker notes tách từ một RW2 Panasonic có dữ liệu méo | giải nguồn | nguồn méo = 1; dịch góc khớp tính tay trong 0,5px; ống có trong Lensfun kèm tối góc → tối góc lấy từ Lensfun (nguồn 2); mặt nào cả hai đều thiếu thì slider mặt đó mờ | ⚠️ chưa có |
| AC-a14 | khối maker notes tách từ một ORF OM/Olympus có dữ liệu méo | giải nguồn | như AC-a13 cho ORF | ⚠️ chưa có |
| AC-a15 | JPEG Sony có thẻ trạng thái "đã sửa trong máy", ống có trong Lensfun | bật Lens Correction | không tự khớp, pass của ShotDex không chạy, ảnh lệch ≤ 1/255 so với công tắc tắt; chọn tay một ống thì pass chạy | ⚠️ chưa có |
| AC-a16 | JPEG cùng thân máy, thẻ báo chưa sửa | bật Lens Correction | tự khớp ống như ảnh không có thẻ | ⚠️ chưa có |
| AC-a17 | ảnh nguồn 2 có CA đỏ/lam, chip Remove CA bật | mở Optics, kéo CA 0 → 200 | chip vẫn hiện và chạm được; tắt chip đổi ảnh ở cả hai mức CA | ⚠️ chưa có |
| AC-a18 | ảnh nguồn 2 đủ ba mặt, iPhone 17, kích thước hiển thị | kéo Distortion liên tục | méo + CA chạy trong **một** pass; ≤ 8 ms mỗi khung | ⚠️ chưa có (đo ở `/verify`) |

**Chưa chứng minh được:** mọi AC trừ phần méo của AC-a10.
