# Vòng 1 — Plan FS-03.13…16 — chỗ spec và code lệch

Không còn gì cần sửa: có thể chốt plan.

## OK (19)

- **E1** [13·AC-12] Nhãn VoiceOver của nút histogram và ⋯ là “Histogram” / “More” (spec) hay “RGB histogram” / “More editor actions” (code)? — trang fs13
  - Lựa chọn: Theo code: “RGB histogram”, “More editor actions” (code)
- **E2** [13·AC-13] Menu ⋯ có giữ Undo/Redo (code, cho tay cầm một tay) hay chỉ đúng 5 mục như spec? — trang fs13
  - Lựa chọn: Theo spec: bỏ khỏi ⋯ (doc)
- **E3** [13·AC-23] Nút Auto của Straighten ghi vào góc xoay khung crop (spec) hay vào slider Rotate của Geometry như Upright Level đang làm (code)? — trang fs13
  - Lựa chọn: Theo spec: ghi góc Straighten của crop (doc)
- **E4** [13·AC-26] Tên mask mới là “Mask 1” kèm dòng phụ “Sky − Brush” (spec) hay “Brush 1”, “Radial 1” theo loại (code, FS-03.05 AC-18)? — trang fs13
  - Lựa chọn: Theo spec: “Mask 1” + dòng phụ vùng (doc)
- **E5** [13·AC-40] Apply Previous trong menu Sync luôn hiện (mờ khi chưa có ảnh trước) hay chỉ hiện khi có (code)? — trang fs13
  - Lựa chọn: Theo spec: luôn hiện, mờ khi chưa có (doc)
- **E6** [14·AC-b1] Áp một look nhập từ Lightroom: thông số preset không nhắc tới thì về 0 (như look ShotDex hôm nay) hay giữ nguyên giá trị trên ảnh (spec)? — trang fs14
  - Lựa chọn: Chỉ đổi thông số preset có ghi (doc)
- **E7** [14·AC-b5] Nhiệt độ màu RAW: thêm trường Kelvin/Tint tuyệt đối để nhận preset Lightroom, hay bỏ qua và báo “chưa có trong ShotDex”? — trang fs14
  - Lựa chọn: Thêm trường tuyệt đối cho RAW (add)
- **E8** [14·AC-c6] Đổi tên look trùng tên look khác: từ chối (spec) hay cho phép như hôm nay (code)? — trang fs14
  - Lựa chọn: Từ chối, gợi ý hậu tố (doc)
- **E9** [14·AC-c7] Banner “look added” hiện ở mọi màn hình có Undo ~4 giây (spec), hay dùng lại toast của editor (3 giây, chỉ trong editor)? — trang fs14
  - Lựa chọn: Banner cấp app, Undo, ~4 giây (doc)
- **E10** [15·AC-41] Trừ vùng khỏi mask: “hiện tại − vùng trừ” (code) hay “hiện tại × (1 − vùng trừ)” (spec)? — trang fs15
  - Lựa chọn: Nhân phần bù (spec) (doc)
- **E11** [15·AC-24] Vẽ đường guide thứ 5 trong Upright Guided thì báo “Up to 4 guides” (15b) hay “4 of 4 drawn.” (13b)? — trang fs15
  - Lựa chọn: “Up to 4 guides” (rule)
- **E12** [15·AC-31] Mục tiêu “0,4 ± 2/255” của test Heal Opacity đo trong không gian tuyến tính (code ra 0,4) hay trên pixel sRGB (code ra ~0,46)? — trang fs15
  - Lựa chọn: Tuyến tính (linear)
- **E13** [15·AC-6] Dời B&W, Vignette, Grain ra khỏi khâu chỉnh chung: mask có còn ba slider này không, và video có đổi thứ tự theo không? — trang fs15
  - Lựa chọn: Mask bỏ 3 slider; video giữ thứ tự cũ (drop)
- **E14** [15] Hai cặp slider cùng tên “Distortion · Vignetting” trong Optics (cặp theo hồ sơ ống 0–200 và cặp chỉnh tay ±100): đổi tên một cặp? — trang fs15
  - Lựa chọn: Giữ tên, tách bằng nhãn nhóm như Lightroom (groups)
- **E15** [15] Pipeline render đang chép tay ở 3 chỗ (ảnh tĩnh, Live Photo, mask tự động): gộp làm một trước khi đổi thứ tự pass? — trang fs15
  - Lựa chọn: Gộp trước (task riêng, đầu giai đoạn) (merge)
- **E16** [16·AC-6] Tiêu chí “render trong extension tăng ≤ 10MB” khi không extension nào render ảnh qua kit, và nạp cả bảng ống kính đã tốn ~12–24MB? — trang fs16
  - Lựa chọn: Bỏ tiêu chí (drop) — KHÁC với đề xuất
- **E17** [16·AC-a9] Bù tối góc cho RAW khi kéo slider Vignetting: giải mã lại mỗi khung (hạ độ phân giải nháp), giữ sẵn bản tuyến tính (gấp đôi cache), hay bù sau cache (sai khi +1 EV)? — trang fs16
  - Lựa chọn: Giữ bản tuyến tính (~2× bộ nhớ cache) (cache)
- **E18** [16] Sync “Everything” đang chép cả hồ sơ ống kính ảnh A sang ảnh B; spec nói không được. Sửa code hay sửa spec? — trang fs16
  - Lựa chọn: Theo spec: mỗi ảnh giữ hồ sơ riêng (doc)
- **E19** [16] RAW vừa mở: ghi nguồn sửa ống kính vào recipe ngay lúc mở, hay chỉ khi có lần chỉnh đầu tiên? — trang fs16
  - Lựa chọn: Ghi ở lần chỉnh đầu tiên (lazy)
