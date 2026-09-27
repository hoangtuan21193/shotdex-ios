# FS-03.16b — Panel Optics và làm mới dữ liệu ống kính

`FS-03.16b` · tier D · panel `ShotDex/Features/Editing/EditorLensProfileSection.swift` · danh mục
`ShotDex/Domain/Editing/EditorAdjustmentCatalog.swift` · ghi công `ShotDex/Features/Settings/SettingsScreen.swift` ·
skill `.claude/skills/release-check/SKILL.md` · cập nhật 2026-09-28

**Một câu:** người chụp đọc được ảnh đang sửa theo cái gì mà không gặp chữ "Lensfun", và mỗi bản phát hành
mang theo dữ liệu ống kính mới nhất.

## 1. Chỗ đặt

Nhóm **Optics** trong danh sách Edit ([FS-03.13](13-iphone-editor-layout.md)); section Optics trong sidebar
iPad/Duo. Theo thứ tự, lưới 40pt trên điện thoại, hàng xếp dọc 46pt trong sidebar ([DESIGN.md](../../../DESIGN.md)):

| Hàng | Nội dung |
|---|---|
| 1 | công tắc **Lens Correction** — một cái cho mọi nguồn, thay cả "Lens Profile" ở Optics lẫn "Lens" ở nhóm RAW (danh mục:191) |
| 2 | hàng trạng thái: tên ống · cách tìm, nút **Change** / **Choose Lens** bên phải |
| — | nhãn nhóm **LENS PROFILE** |
| 3–5 | **Distortion** · **Vignetting** · **Chromatic Aberration**, 0–200, mốc 100 |

- Sau đó là nhãn nhóm **MANUAL** với hai slider chỉnh tay của [FS-03.15](15-lightroom-parameter-parity.md)
  (15b §3), rồi Remove CA / Defringe.
- Hai cặp **Distortion · Vignetting** giữ cùng tên như Lightroom, tách bằng nhãn nhóm (tiêu đề nhỏ chữ hoa
  kiểu section có sẵn). VoiceOver đọc kèm tên nhóm: "Distortion, Lens Profile" / "Distortion, Manual".
- Năm hàng = 200pt trên điện thoại, cộng hai nhãn nhóm; Edit là một danh sách cuộn dọc nên không đụng trần 264/344pt của panel.
- Không token, màu hay bo góc mới: chữ trạng thái dùng màu phụ, dòng mờ và slider mờ dùng màu mờ có sẵn.

## 2. Chữ trên màn

| Trạng thái | Khi nào | Hàng trạng thái | Nút | Ba slider |
|---|---|---|---|---|
| tự tìm | nguồn 1, hoặc nguồn 2 tự khớp | "‹tên ống› · Found from photo info" | Change | chạy |
| tự chọn | nguồn 2 người dùng chọn | "‹tên ống› · Chosen by you" | Change | chạy |
| máy đã sửa | JPEG có thẻ "đã sửa trong máy" (16a §4) | "Already corrected in camera" | Choose Lens | mờ |
| có sẵn trong máy | nguồn 3 | "Using the camera's built-in correction" + dòng mờ "Strength controls need a lens profile" | Choose Lens | mờ, không chạm được |
| không có | nguồn 4 | "No profile for this lens yet" | Choose Lens | mờ |
| tắt | công tắc tắt | chữ của trạng thái bên dưới, màu mờ | như trên | mờ |

- Tên ống: nguồn 1 lấy tên ống trong EXIF, nguồn 2 lấy tên hiển thị của bảng. Tên dài **cắt ở giữa**; phần
  "Found from photo info" / "Chosen by you" không bao giờ bị cắt.
- Mặt nào nguồn không có dữ liệu thì slider mặt đó mờ; VoiceOver đọc slider mờ là không dùng được.
- Thay chữ hôm nay: "Found from EXIF" (panel:58), câu "RAW photos are corrected by the RAW decoder…"
  (panel:17), và "No profile for this lens yet. Choose yours from the list." (panel:64).
- Mọi chữ mới vào String Catalog.
- **Ống người dùng chọn thắng** dữ liệu nhúng: RAW nguồn 1, bấm Change chọn ống khác → nguồn 2, "Chosen by you".
- File có nguồn 1 thì **đầu danh sách chọn** có dòng "Use Lens Data Found in Photo"; chạm là về "Found from photo
  info", một bước history. *Vì* hãng ghi sai thì phải sửa được, bấm nhầm thì phải lấy lại được.
- Hai câu chữ "Already corrected in camera" và "Use Lens Data Found in Photo" đã qua rà chữ (2026-09-28).

## 3. Danh sách chọn ống và ghi công

- Danh sách giữ như hôm nay (tìm theo tên, nhóm "Fits ‹ngàm›" lên đầu); **bỏ** dòng ghi công ở chân (panel:116).
- Chọn một ống là **một** bước history; Cancel không đổi gì.
- Ghi công Lensfun (CC-BY-SA 3.0) **chỉ** ở Settings › Camera Database › Acknowledgements (đã có,
  ghi công:819–838). Không chữ "Lensfun" nào khác trong giao diện.

## 4. Làm mới dữ liệu mỗi bản phát hành

Một bước mới trong `/release-check` (spec mô tả, sửa skill ở giai đoạn Build):

1. Lấy `data/db` của Lensfun ở commit mới nhất nhánh chính — máy phát hành có mạng, app thì không cần.
2. Chạy script đổi; JSON ghi commit và ngày của Lensfun vào phần nguồn.
3. In một dòng so với bản đang có: số ống (có méo · có tối góc · có CA), số thân máy, dung lượng — ví dụ
   "Lens profiles 1527 → 1561 (+34) · vignetting … · TCA … · cameras 1054 → 1060 · 823KB → …".
4. Liệt kê id ống **biến mất** — ảnh trỏ tới chúng rơi về AC-6 của FS-03.16.
5. Chạy bộ test hồ sơ ống kính; JSON mới vào **một commit riêng**.

**Fail** khi script lỗi, số ống giảm > 1%, hoặc JSON vượt trần. Id biến mất là cảnh báo, không fail.

- **Trần: bảng là JSON thô trong bundle, ≤ 4MB.** Vượt trần thì bảng chuyển sang nén trong bundle, giải nén
  lần đầu dùng; không cắt bớt ống. *Vì* không có trần thì mỗi lần làm mới app phình dần.

## 5. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-b1 | ARW Sony + FE 24-70mm F2.8 GM II có dữ liệu nhúng, trên iPhone 17 (402×874) | mở Optics | hàng trạng thái "FE 24-70mm F2.8 GM II · Found from photo info" không bị cắt, nút Change không bị che, ba slider ở 100 chạm được, nằm dưới nhãn LENS PROFILE, nhãn VoiceOver "Distortion, Lens Profile"…; dump đo khung từng hàng cao 40pt | ⚠️ chưa có (cần RAW mẫu trong thư viện sim) |
| AC-b2 | JPEG D800E + 16-35mm f/4 trong thư viện sim | bật Lens Correction | "Nikon AF-S Nikkor 16-35mm f/4G ED VR · Found from photo info", ba slider chạy | ⚠️ chưa có (tự khớp đã có: `LensProfileTests.nikonGenericExifFindsTheRightLens`) |
| AC-b3 | cùng ảnh, đang tự tìm | Change → chọn một ống khác | "‹ống vừa chọn› · Chosen by you"; một Undo trả về trạng thái tự tìm | ⚠️ chưa có |
| AC-b4 | RAW nguồn 3 (ống không có ở nguồn 1, 2) | mở Optics | "Using the camera's built-in correction" + dòng mờ "Strength controls need a lens profile"; ba slider mờ, VoiceOver đọc không dùng được; bật/tắt công tắc làm ảnh khác nhau | ⚠️ chưa có |
| AC-b5 | JPEG Nikon D90 không có dữ liệu ống | mở Optics | "No profile for this lens yet" + Choose Lens; chạm mở danh sách chọn, không nút chết | ⚠️ chưa có (tiền lệ: `LensProfileTests.noLensDataMeansNoMatch`, `ShotDexUITests/scripts/ipad-optics-lens-0.json`) |
| AC-b6 | bản dựng bất kỳ | đọc chuỗi giao diện editor và danh mục thông số | không chuỗi nào chứa "Lensfun"; nhóm RAW không còn hàng sửa ống kính; Optics có đúng một công tắc cho RAW lẫn JPEG; Acknowledgements vẫn có "Lensfun" + CC-BY-SA 3.0 | ⚠️ chưa có |
| AC-b7 | `data/db` của Lensfun ở commit mới hơn bản đang nhúng | chạy bước làm mới của `/release-check` | in dòng số ống trước → sau, dung lượng, id biến mất; JSON ghi commit Lensfun; chạy với thư mục rỗng thì bước **fail** và JSON không đổi | ⚠️ chưa có |
| AC-b8 | JSON đổi ra lớn hơn 4MB (dữ liệu giả) | chạy bước làm mới | bước **fail**, nêu dung lượng và trần; JSON trong repo không đổi | ⚠️ chưa có |
| AC-b9 | ARW Sony nguồn 1 (như AC-b1) | Change → chọn một ống Lensfun khác, rồi mở lại danh sách → chạm "Use Lens Data Found in Photo" | sau bước đầu: "‹ống vừa chọn› · Chosen by you"; sau bước sau: "Found from photo info", ảnh lệch ≤ 1/255 so với trước khi đổi; mỗi bước là một bước history | ⚠️ chưa có |
| AC-b10 | JPEG có thẻ "đã sửa trong máy" (như AC-a15) | bật Lens Correction, mở Optics | hàng trạng thái "Already corrected in camera" không bị cắt, nút Choose Lens chạm được, ba slider mờ | ⚠️ chưa có |
| AC-b11 | JPEG D800E tự khớp (AC-b2), không có dữ liệu nhúng | mở danh sách chọn | không có dòng "Use Lens Data Found in Photo" | ⚠️ chưa có |

**Chưa chứng minh được:** AC-b1 → AC-b11. AC-b1 và AC-b4 cần file RAW mẫu không có khuôn mặt nạp vào simulator.
