# FS-03.15c — Retouch đầy đủ và Red Eye

`FS-03.15c` · `ShotDexKit/Models/PhotoHealing.swift` · `ShotDexKit/Render/PhotoHealingRenderer.swift`
· cập nhật 2026-09-28

**Một câu:** Heal hôm nay chỉ có vết tròn; người chụp cần tô theo dây điện, lật tìm nguồn khác, soi bụi cảm
biến và sửa mắt đỏ — đủ những gì Lightroom có ở cùng chỗ, trừ Remove (tạm bỏ, §6).

Tổng quan: [FS-03.15](15-lightroom-parameter-parity.md). Heal v1 (vết tròn, vá bằng normalized convolution):
[FS-03.11 §2](11-parity-with-lightroom.md). Bố cục panel Heal: [FS-03.13](13-iphone-editor-layout.md).

## 1. Panel Heal

Theo FS-03.13: hàng chế độ **Heal · Clone · Red Eye** · Size · Feather · **Opacity** · vết đang chọn
(**New Source** · Delete Spot) · mọi vết (**Visualize Spots** + Threshold · **Show Spot Pins** · **Clear All**).
Hàng Size/Feather/Opacity cùng kiểu hàng cọ của Mask.

- Thứ tự chốt của hàng chế độ là Remove · Heal · Clone · **Red Eye** — Red Eye là ô thứ tư. Ô Remove không
  hiện khi Remove tạm bỏ (luật "hàng chưa có thì không hiện, giữ chỗ" của FS-03.13).
- Ở chế độ Red Eye, Size/Feather/Opacity nhường chỗ cho **Pupil Size · Darken** và nút **Fix Red Eye** (§5).

## 2. Vết dạng nét cọ

- **Chạm** tạo vết tròn như v1; **kéo** tạo vết theo nét cọ, bề ngang = Size. Size tính theo điểm trên màn
  (FS-03.05b §2): zoom vào thì nét nhỏ đi trên ảnh — cách tô một sợi dây mảnh.
- Cửa sổ xác nhận chạm/kéo và luật một ngón vẽ, hai ngón zoom dùng lại trọng tài của FS-03.05b §4.
- Heal/Clone dạng nét: nguồn gợi ý dời **cả nét** sang bên, vuông góc hướng chính của nét, cách 1,3 bề ngang;
  kéo vòng nguồn để đổi. Heal sửa màu trên vành quanh **hình nét**, cùng phép của vết tròn.
- **Opacity** 0…100 áp cho vết đang chọn; vết mới nhận giá trị đang đặt. Trộn trong không gian làm việc
  tuyến tính của Core Image, nên Opacity 50 là nửa đường theo ánh sáng, không theo pixel sRGB.
- Toạ độ vẫn chuẩn hoá theo khung sau crop; pass chạy ngay sau crop, trước Red Eye và mask (§3 tổng quan).
- Vết không bao giờ chép sang ảnh khác (FS-03.10).

## 3. New Source, Visualize Spots, Spot Pins, Clear All

- **New Source** (Heal/Clone): chấm điểm các vị trí quanh vết theo độ khớp màu và vân của vành, bỏ vị trí
  chồng lên vết; mỗi lần bấm nhảy sang ứng viên tốt kế tiếp. Mỗi lần bấm là một bước Undo.
- **Visualize Spots**: ảnh trên canvas thành bản đồ đen trắng tách rìa (bụi hiện thành chấm trắng); slider
  **Threshold** 0…100 chỉnh độ nhạy. Chỉ hiển thị — không vào render, không vào file lưu; rời Heal là tắt.
- **Show Spot Pins**: tắt thì ẩn mọi ghim và vòng nguồn; vết đang chọn vẫn hiện ghim của nó.
- **Clear All**: gỡ mọi vết (kể cả Red Eye) trong **một** bước Undo; hỏi xác nhận khi có **từ 2 vết** ("Clear all spots?" · nút "Clear All Spots").

## 4. Red Eye — chạm từng mắt

- **Chạm vào mắt**: Vision tìm điểm mốc khuôn mặt trong vùng quanh chỗ chạm; có con ngươi cách chỗ chạm
  ≤ 3 lần bán kính mặc định thì **căn tâm vào con ngươi**, bán kính theo bề ngang mắt.
- Không thấy mặt, hoặc Vision lỗi: vết đặt đúng chỗ chạm, bán kính mặc định 1% cạnh ngắn — không báo lỗi.
- Trong vòng tròn, pixel **đỏ trội** (đỏ lớn hơn hẳn lục và lam) được kéo đỏ về mức lục/lam rồi làm tối theo
  **Darken**; pixel không đỏ (mống mắt nâu, lông mi) không đổi. Hai slider: **Pupil Size** · **Darken** (0…100).
- Mỗi vết Red Eye kéo để dời, Delete Spot để xoá; một chạm là một bước Undo.

## 5. Red Eye — nút Fix Red Eye

- Bấm **Fix Red Eye**: Vision tìm mọi khuôn mặt và con ngươi trên preview; chỉ con ngươi **đỏ trội** (cùng
  phép thử của §4) mới nhận vết. *Vì tự dò trên mắt không đỏ là làm tối oan mắt nâu tối.*
- Mỗi vết tự dò là một vết Red Eye thường — dời, xoá, chỉnh như vết chạm. Con ngươi đã có vết thì bỏ qua.
- Cả lượt bấm là **một** bước Undo.
- Không tìm thấy mắt đỏ nào, hoặc Vision lỗi: không tạo vết, pill "No red eyes found" 3s — không alert.

## 6. Ngoài phạm vi / tạm bỏ: Remove

Remove (tô lên vật để xoá, tự lấp từ xung quanh) **tạm bỏ** tới khi Apple có API/model vá ảnh hỗ trợ.
*Vì lấp tự viết hỏng trên cỏ/tường, còn model vá ảnh thì Apple chưa công bố.* Khi quay lại, bắt đầu từ:

- Vùng lấp giải **một lần** thành bản đồ tương ứng, có hạt giống trong recipe; kéo slider khác chỉ tra bản đồ.
- Undo / Delete Spot giữa lúc lấp huỷ lượt lấp; New Source = giải lại với hạt giống khác; trần diện tích
  kèm "This area is too large to remove. Paint a smaller area."
- Lưu full-res: phóng bản đồ ở cỡ preview lên, tra pixel full-res, vá mép bằng phép sửa màu của Heal (D63).
- Bản đồ lưu thành file trong kho matte (15d §5).
- Các AC chờ Remove quay lại (không tính vào số AC):

| # | Cho | Khi | Thì |
|---|---|---|---|
| R-1 | vân cỏ tổng hợp có một vật đỏ phủ 3% khung | tô Remove phủ vật rồi nhấc tay | ≤ 0,5% pixel trong vùng còn hue đỏ; phương sai cục bộ bằng 50%…150% vành ngoài |
| R-2 | một vết Remove đã lấp | kéo Exposure qua 20 giá trị | bản đồ giải đúng 1 lần; hai lần render cùng recipe khớp từng pixel |
| R-3 | vết Remove đang lấp | bấm Undo | lượt lấp dừng, 0 vết, ảnh bằng trước khi tô; không cảnh báo |
| R-4 | vân cỏ 8064×6048, vết Remove lấp ở preview 2400px | lưu full resolution | năng lượng tần số cao vùng lấp ≥ 70% vành ngoài; mép lệch màu trung bình ≤ 2/255 |

## 7. Thẻ `crs:`

| Control | Thẻ | Ghi chú |
|---|---|---|
| vết Heal/Clone, tròn và nét | RetouchAreas (mỗi vết: loại vết, nguồn, độ lệch, Opacity, Feather, hình tròn hoặc chuỗi dấu cọ) · RetouchInfo (bản cũ) | cấu trúc cần kiểm (§7 tổng quan); vết Remove bỏ qua |
| Red Eye | RedEyeInfo | cần kiểm |
| Visualize Spots · Threshold · Show Spot Pins | — | chỉ là chế độ xem, Lightroom không ghi vào preset |

## 8. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-30 | trời chuyển màu tổng hợp có một dây tối rộng 3px chạy chéo 40% khung | kéo một nét Heal Size vừa phủ dây | trong vùng vá sai lệch trung bình ≤ 2/255, tệ nhất ≤ 4/255 so với nền; không mép cứng | ⚠️ chưa có (dự kiến `PhotoHealingTests.brushHealRemovesAWire`) |
| AC-31 | vết Clone tròn trên hai vùng phẳng 0,2 (đích) và 0,6 (nguồn), giá trị tuyến tính | đặt Opacity 50 | lõi vết ra 0,4 ± 2/255, đo trong không gian làm việc tuyến tính (không phải pixel sRGB) | `PhotoHealingTests.opacityBlendsHalfway` · slider Opacity ở panel Heal (`ShotDexUITests/scripts/iphone-heal-opacity.json`) |
| AC-32 | vết Heal với nguồn gợi ý | bấm New Source | nguồn mới khác chỗ cũ ≥ 1 bán kính, không chồng lên vết; Undo một lần trả nguồn cũ | ⚠️ chưa có (dự kiến `PhotoHealingTests.newSourcePicksAnotherPlace`) |
| AC-33 | ảnh có 5 chấm bụi, Visualize Spots bật | lưu ảnh | file lưu khớp từng pixel bản Visualize tắt; Threshold 80 cho nhiều pixel trắng hơn Threshold 20 | ⚠️ chưa có (dự kiến `SpotVisualizerTests.visualizeIsDisplayOnly`) |
| AC-34 | 6 vết heal/clone + 1 Red Eye, Show Spot Pins tắt | bấm Clear All rồi xác nhận | hộp xác nhận hiện (7 ≥ 2); sau khi xác nhận 0 vết; Undo một lần trả đủ 7; lúc pins tắt, bảng phần tử không có ghim nào ngoài vết đang chọn | ⚠️ chưa có (dự kiến `PhotoHealingTests.clearAllIsOneStep`) + `ShotDexUITests/scripts/iphone-heal-panel.json` |
| AC-35 | ảnh mặt người tổng hợp có con ngươi đỏ (220,40,40) bán kính 12px | chạm Red Eye cách tâm con ngươi 20px | tâm vết lệch tâm con ngươi ≤ 2px; trong con ngươi đỏ ≤ max(lục, lam) + 10/255; mống mắt lệch ≤ 2/255 | ⚠️ chưa có (dự kiến `RedEyeTests.tapCentresOnThePupil`). Không dùng ảnh mặt người thật |
| AC-36 | ảnh không có mặt nào (hoặc Vision báo lỗi — simulator) | chạm Red Eye | vết đặt đúng chỗ chạm, bán kính 1% cạnh ngắn; không alert | ⚠️ chưa có (dự kiến `RedEyeTests.noFaceFallsBackToTheTap`) |
| AC-37 | ảnh tổng hợp 2 mặt: một cặp con ngươi đỏ (220,40,40), một cặp nâu tối (60,40,30) | bấm Fix Red Eye | đúng 2 vết, cả hai trên con ngươi đỏ; con ngươi nâu lệch ≤ 2/255; Undo một lần gỡ cả 2 | ⚠️ chưa có — cần máy thật hoặc Vision của Mac (dự kiến `RedEyeTests.fixRedEyeSkipsDarkPupils`). Không dùng ảnh mặt người thật |
| AC-38 | ảnh không mắt đỏ nào (hoặc Vision báo lỗi — simulator) | bấm Fix Red Eye | 0 vết, 0 bước Undo; pill "No red eyes found" 3s; không alert | ⚠️ chưa có (dự kiến `RedEyeTests.fixRedEyeWithNothingToFix`) |
| AC-39 | editor mở, iPhone 17 26.5 và 18.6 | mở Heal | hàng chế độ đúng 3 ô Heal · Clone · Red Eye, không ô Remove; chạm Red Eye hiện Pupil Size · Darken · Fix Red Eye | ⚠️ chưa có (`ShotDexUITests/scripts/iphone-heal-panel.json` + element dump) |

**Chưa chứng minh được:** AC-30…AC-39 (chưa code).
