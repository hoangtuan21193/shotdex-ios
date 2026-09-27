# Plan FS-03.13…16 — chỗ spec và code lệch — các quyết định

> Chốt 2026-09-28 sau 1 vòng · nguồn: .planboard/plans-deviations/plan.json

| ID | Quyết định | Kết quả | Lựa chọn |
|---|---|---|---|
| E1 | [13·AC-12] Nhãn VoiceOver của nút histogram và ⋯ là “Histogram” / “More” (spec) hay “RGB histogram” / “More editor actions” (code)? | OK | Theo code: “RGB histogram”, “More editor actions” |
| E2 | [13·AC-13] Menu ⋯ có giữ Undo/Redo (code, cho tay cầm một tay) hay chỉ đúng 5 mục như spec? | OK | Theo spec: bỏ khỏi ⋯ |
| E3 | [13·AC-23] Nút Auto của Straighten ghi vào góc xoay khung crop (spec) hay vào slider Rotate của Geometry như Upright Level đang làm (code)? | OK | Theo spec: ghi góc Straighten của crop |
| E4 | [13·AC-26] Tên mask mới là “Mask 1” kèm dòng phụ “Sky − Brush” (spec) hay “Brush 1”, “Radial 1” theo loại (code, FS-03.05 AC-18)? | OK | Theo spec: “Mask 1” + dòng phụ vùng |
| E5 | [13·AC-40] Apply Previous trong menu Sync luôn hiện (mờ khi chưa có ảnh trước) hay chỉ hiện khi có (code)? | OK | Theo spec: luôn hiện, mờ khi chưa có |
| E6 | [14·AC-b1] Áp một look nhập từ Lightroom: thông số preset không nhắc tới thì về 0 (như look ShotDex hôm nay) hay giữ nguyên giá trị trên ảnh (spec)? | OK | Chỉ đổi thông số preset có ghi |
| E7 | [14·AC-b5] Nhiệt độ màu RAW: thêm trường Kelvin/Tint tuyệt đối để nhận preset Lightroom, hay bỏ qua và báo “chưa có trong ShotDex”? | OK | Thêm trường tuyệt đối cho RAW |
| E8 | [14·AC-c6] Đổi tên look trùng tên look khác: từ chối (spec) hay cho phép như hôm nay (code)? | OK | Từ chối, gợi ý hậu tố |
| E9 | [14·AC-c7] Banner “look added” hiện ở mọi màn hình có Undo ~4 giây (spec), hay dùng lại toast của editor (3 giây, chỉ trong editor)? | OK | Banner cấp app, Undo, ~4 giây |
| E10 | [15·AC-41] Trừ vùng khỏi mask: “hiện tại − vùng trừ” (code) hay “hiện tại × (1 − vùng trừ)” (spec)? | OK | Nhân phần bù (spec) |
| E11 | [15·AC-24] Vẽ đường guide thứ 5 trong Upright Guided thì báo “Up to 4 guides” (15b) hay “4 of 4 drawn.” (13b)? | OK | “Up to 4 guides” |
| E12 | [15·AC-31] Mục tiêu “0,4 ± 2/255” của test Heal Opacity đo trong không gian tuyến tính (code ra 0,4) hay trên pixel sRGB (code ra ~0,46)? | OK | Tuyến tính |
| E13 | [15·AC-6] Dời B&W, Vignette, Grain ra khỏi khâu chỉnh chung: mask có còn ba slider này không, và video có đổi thứ tự theo không? | OK | Mask bỏ 3 slider; video giữ thứ tự cũ |
| E14 | [15] Hai cặp slider cùng tên “Distortion · Vignetting” trong Optics (cặp theo hồ sơ ống 0–200 và cặp chỉnh tay ±100): đổi tên một cặp? | OK | Giữ tên, tách bằng nhãn nhóm như Lightroom |
| E15 | [15] Pipeline render đang chép tay ở 3 chỗ (ảnh tĩnh, Live Photo, mask tự động): gộp làm một trước khi đổi thứ tự pass? | OK | Gộp trước (task riêng, đầu giai đoạn) |
| E16 | [16·AC-6] Tiêu chí “render trong extension tăng ≤ 10MB” khi không extension nào render ảnh qua kit, và nạp cả bảng ống kính đã tốn ~12–24MB? | OK | Bỏ tiêu chí (khác đề xuất) |
| E17 | [16·AC-a9] Bù tối góc cho RAW khi kéo slider Vignetting: giải mã lại mỗi khung (hạ độ phân giải nháp), giữ sẵn bản tuyến tính (gấp đôi cache), hay bù sau cache (sai khi +1 EV)? | OK | Giữ bản tuyến tính (~2× bộ nhớ cache) |
| E18 | [16] Sync “Everything” đang chép cả hồ sơ ống kính ảnh A sang ảnh B; spec nói không được. Sửa code hay sửa spec? | OK | Theo spec: mỗi ảnh giữ hồ sơ riêng |
| E19 | [16] RAW vừa mở: ghi nguồn sửa ống kính vào recipe ngay lúc mở, hay chỉ khi có lần chỉnh đầu tiên? | OK | Ghi ở lần chỉnh đầu tiên |

## E1 — [13·AC-12] Nhãn VoiceOver của nút histogram và ⋯ là “Histogram” / “More” (spec) hay “RGB histogram” / “More editor actions” (code)?
- **Chốt:** Giữ nhãn của code (dài, rõ nghĩa hơn khi nghe), sửa spec.
- **Vì sao:** Nhãn VoiceOver là thứ người khiếm thị nghe; đổi qua lại làm hỏng thói quen và test UI dựa trên nhãn.
- **Đã cân nhắc:** Theo spec: “Histogram”, “More”
- **Lịch sử:** vòng 1 — OK

## E2 — [13·AC-13] Menu ⋯ có giữ Undo/Redo (code, cho tay cầm một tay) hay chỉ đúng 5 mục như spec?
- **Chốt:** Bỏ Undo/Redo khỏi ⋯ (theo spec): băng trên đã có, và vuốt hai ngón cũng undo được.
- **Vì sao:** Undo/Redo đã có ở băng trên; lặp trong ⋯ làm menu dài. Nhưng code để đó có chủ ý vì nút trên cùng khó với bằng ngón cái.
- **Đã cân nhắc:** Theo code: giữ trong ⋯
- **Lịch sử:** vòng 1 — OK

## E3 — [13·AC-23] Nút Auto của Straighten ghi vào góc xoay khung crop (spec) hay vào slider Rotate của Geometry như Upright Level đang làm (code)?
- **Chốt:** Ghi vào góc Straighten của crop (theo spec); Upright Level vẫn là việc của Upright.
- **Vì sao:** Hai chỗ lưu cho cùng một góc xoay thì Reset/Copy Edits xử lý khác nhau: Straighten thuộc crop (không chép sang ảnh khác), Geometry thì đi theo look.
- **Đã cân nhắc:** Theo code: ghi slider Rotate của Geometry
- **Lịch sử:** vòng 1 — OK

## E4 — [13·AC-26] Tên mask mới là “Mask 1” kèm dòng phụ “Sky − Brush” (spec) hay “Brush 1”, “Radial 1” theo loại (code, FS-03.05 AC-18)?
- **Chốt:** Theo spec: “Mask 1” + dòng phụ liệt kê các vùng; sửa FS-03.05 AC-18.
- **Vì sao:** Tên là thứ hiện trên hàng “đang chọn ▼” và trong danh sách; mask nhiều vùng mà tên theo loại vùng đầu tiên sẽ sai khi thêm vùng khác.
- **Đã cân nhắc:** Theo code: “Brush 1”, “Radial 1”
- **Lịch sử:** vòng 1 — OK

## E5 — [13·AC-40] Apply Previous trong menu Sync luôn hiện (mờ khi chưa có ảnh trước) hay chỉ hiện khi có (code)?
- **Chốt:** Luôn hiện, mờ khi chưa có ảnh trước (theo spec) — menu luôn 4 mục.
- **Vì sao:** Menu đổi số mục theo trạng thái làm người dùng không nhớ vị trí; nhưng mục mờ cũng chiếm chỗ.
- **Đã cân nhắc:** Theo code: chỉ hiện khi có ảnh trước
- **Lịch sử:** vòng 1 — OK

## E6 — [14·AC-b1] Áp một look nhập từ Lightroom: thông số preset không nhắc tới thì về 0 (như look ShotDex hôm nay) hay giữ nguyên giá trị trên ảnh (spec)?
- **Chốt:** Look nhập chỉ đổi đúng thông số preset ghi (giống Lightroom); look ShotDex tự lưu vẫn như hôm nay.
- **Vì sao:** Preset Lightroom thường chỉ ghi vài thông số (ví dụ chỉ màu). Về 0 thì áp preset màu sẽ xoá luôn Exposure bạn đã chỉnh; giữ nguyên thì look ShotDex và look nhập chạy hai kiểu.
- **Đã cân nhắc:** Mọi thông số tone/màu/curve bị thay, cái không ghi về 0
- **Lịch sử:** vòng 1 — OK

## E7 — [14·AC-b5] Nhiệt độ màu RAW: thêm trường Kelvin/Tint tuyệt đối để nhận preset Lightroom, hay bỏ qua và báo “chưa có trong ShotDex”?
- **Chốt:** Thêm trường Kelvin/Tint tuyệt đối chỉ cho RAW; slider hiện số Kelvin thật.
- **Vì sao:** ShotDex lưu độ lệch so với As Shot (±4000K); preset Lightroom cho RAW ghi số tuyệt đối (ví dụ 5200K). Bỏ qua thì preset có chỉnh WB sẽ lệch màu rõ.
- **Đã cân nhắc:** Bỏ qua, ghi ✕ trong báo cáo
- **Lịch sử:** vòng 1 — OK

## E8 — [14·AC-c6] Đổi tên look trùng tên look khác: từ chối (spec) hay cho phép như hôm nay (code)?
- **Chốt:** Từ chối, gợi ý tên kèm hậu tố “(2)”.
- **Vì sao:** Hai look cùng tên thì chọn nhầm và nhập preset trùng tên (luật thêm hậu tố) không còn nghĩa.
- **Đã cân nhắc:** Cho phép trùng
- **Lịch sử:** vòng 1 — OK

## E9 — [14·AC-c7] Banner “look added” hiện ở mọi màn hình có Undo ~4 giây (spec), hay dùng lại toast của editor (3 giây, chỉ trong editor)?
- **Chốt:** Làm một banner cấp app (mọi màn), ~4 giây, nút Undo.
- **Vì sao:** AirDrop tới lúc bạn đang ở thư viện chứ không phải editor; dùng toast editor thì ngoài editor không có Undo.
- **Đã cân nhắc:** Dùng lại toast editor
- **Lịch sử:** vòng 1 — OK

## E10 — [15·AC-41] Trừ vùng khỏi mask: “hiện tại − vùng trừ” (code) hay “hiện tại × (1 − vùng trừ)” (spec)?
- **Chốt:** Theo spec: nhân với phần bù — mép mềm giữ lại được, giống Lightroom.
- **Vì sao:** Chỉ khác ở mép mềm: 0,8 trừ 0,5 ra 0,3 (code) hay 0,4 (spec). Cách code làm mép trừ bị khuyết sâu hơn; cách spec giống Lightroom và Photoshop hơn.
- **Đã cân nhắc:** Trừ thẳng (code)
- **Lịch sử:** vòng 1 — OK

## E11 — [15·AC-24] Vẽ đường guide thứ 5 trong Upright Guided thì báo “Up to 4 guides” (15b) hay “4 of 4 drawn.” (13b)?
- **Chốt:** “Up to 4 guides” — nói luật, không chỉ nói trạng thái.
- **Vì sao:** Hai spec ghi hai câu khác nhau cho cùng một lúc; phải chọn một.
- **Đã cân nhắc:** “4 of 4 drawn.”
- **Lịch sử:** vòng 1 — OK

## E12 — [15·AC-31] Mục tiêu “0,4 ± 2/255” của test Heal Opacity đo trong không gian tuyến tính (code ra 0,4) hay trên pixel sRGB (code ra ~0,46)?
- **Chốt:** Đo trong không gian làm việc tuyến tính; sửa câu chữ của AC-31.
- **Vì sao:** Chọn sai thì test đỏ dù code đúng, hoặc xanh dù trộn sai. Core Image trộn trong không gian tuyến tính.
- **Đã cân nhắc:** Trên pixel sRGB
- **Lịch sử:** vòng 1 — OK

## E13 — [15·AC-6] Dời B&W, Vignette, Grain ra khỏi khâu chỉnh chung: mask có còn ba slider này không, và video có đổi thứ tự theo không?
- **Chốt:** Mask bỏ Vignette và Grain (Lightroom cũng không có ở mask), giữ Saturation −100 thay cho B&W; video giữ thứ tự cũ tới khi FS-12 tự quyết.
- **Vì sao:** Hôm nay khâu chỉnh chung chạy cả trong từng mask, nên mask có B&W/Vignette/Grain. Dời ra thì mask mất ba slider đó; video Studio dùng lại khâu này.
- **Đã cân nhắc:** Mask giữ 3 slider (chạy riêng cho mask); Mask bỏ 3 slider; video đổi theo luôn
- **Lịch sử:** vòng 1 — OK

## E14 — [15] Hai cặp slider cùng tên “Distortion · Vignetting” trong Optics (cặp theo hồ sơ ống 0–200 và cặp chỉnh tay ±100): đổi tên một cặp?
- **Chốt:** Giữ tên như Lightroom: cặp hồ sơ nằm dưới nhãn nhóm “LENS PROFILE”, cặp tay dưới “MANUAL” — cùng tên nhưng khác nhóm, như Lightroom.
- **Vì sao:** Cùng panel, cùng tên, hai nghĩa: người dùng không biết đang kéo cái nào; VoiceOver đọc trùng.
- **Đã cân nhắc:** Đổi tên cặp tay: “Manual Distortion”, “Lens Vignetting”
- **Lịch sử:** vòng 1 — OK

## E15 — [15] Pipeline render đang chép tay ở 3 chỗ (ảnh tĩnh, Live Photo, mask tự động): gộp làm một trước khi đổi thứ tự pass?
- **Chốt:** Gộp thành một danh sách pass dùng chung, làm task đầu tiên của giai đoạn render.
- **Vì sao:** Không gộp thì đổi thứ tự pass ở ảnh tĩnh mà quên Live Photo — Live Photo lưu ra sẽ khác ảnh xem trong editor.
- **Đã cân nhắc:** Sửa song song ba chỗ
- **Lịch sử:** vòng 1 — OK

## E16 — [16·AC-6] Tiêu chí “render trong extension tăng ≤ 10MB” khi không extension nào render ảnh qua kit, và nạp cả bảng ống kính đã tốn ~12–24MB?
- **Chốt:** Chọn “Bỏ tiêu chí”.
- **Vì sao:** Giữ nguyên thì tiêu chí đỏ ngay; bỏ thì sau này thêm extension render sẽ vỡ bộ nhớ mà không ai biết.
- **Đã cân nhắc:** Đo trong test, nạp bảng từng phần; Hoãn tiêu chí (như D60)
- **Lịch sử:** vòng 1 — OK

## E17 — [16·AC-a9] Bù tối góc cho RAW khi kéo slider Vignetting: giải mã lại mỗi khung (hạ độ phân giải nháp), giữ sẵn bản tuyến tính (gấp đôi cache), hay bù sau cache (sai khi +1 EV)?
- **Chốt:** Giữ sẵn một bản giải mã tuyến tính nửa độ chính xác (half-float); kéo slider chỉ nhân gain lên bản đó.
- **Vì sao:** Luật FS-03.04: không hạ độ phân giải khi kéo. Nhưng bù đúng phải làm ở ánh sáng tuyến tính, trong lúc giải mã.
- **Đã cân nhắc:** Giải mã lại mỗi khung như Exposure hôm nay; Bù sau cache
- **Lịch sử:** vòng 1 — OK

## E18 — [16] Sync “Everything” đang chép cả hồ sơ ống kính ảnh A sang ảnh B; spec nói không được. Sửa code hay sửa spec?
- **Chốt:** Sửa code: Sync giữ hồ sơ ống của từng ảnh, chỉ chép ba mức độ mạnh.
- **Vì sao:** Ảnh B có thể chụp ống khác; chép hồ sơ A sang là sửa méo sai.
- **Đã cân nhắc:** Theo code: chép cả hồ sơ
- **Lịch sử:** vòng 1 — OK

## E19 — [16] RAW vừa mở: ghi nguồn sửa ống kính vào recipe ngay lúc mở, hay chỉ khi có lần chỉnh đầu tiên?
- **Chốt:** Giải nguồn lúc mở nhưng chỉ giữ trong phiên; ghi vào recipe ở lần chỉnh đầu tiên.
- **Vì sao:** Ghi lúc mở thì mọi RAW vừa mở đều bị tính là “đã chỉnh” (hiện dấu, hỏi lưu khi thoát).
- **Đã cân nhắc:** Ghi ngay lúc mở
- **Lịch sử:** vòng 1 — OK
