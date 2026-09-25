# FS-16 — Kernel render bằng Metal

`FS-16` · không có màn · `ShotDexKit/Render/` · `ShotDex/Data/Sources/VideoMaskRenderer.swift` · cập nhật 2026-09-25
Nguồn intent: [2026-09-25-metal-ci-kernels](../_intents/2026-09-25-metal-ci-kernels.md)

**Một câu:** 40 kernel Core Image tự viết chuyển từ Kernel Language dạng chuỗi (deprecated) sang Metal
biên dịch lúc build, ảnh ra không đổi.

## 1. Người dùng cần gì

Người chụp kéo slider mask, HSL, vignette, heal, ghép panorama — và thấy ảnh đổi. Hôm nay một chuỗi kernel
sai làm tính năng tắt mà không ai biết; ngày Apple gỡ Kernel Language thì 40 tính năng tắt cùng lúc.
Người chụp không được thấy khác biệt nào sau khi chuyển.

## 2. Phạm vi

**Có** — 40 kernel, port theo 4 nhóm, mỗi nhóm (hoặc nhóm con) một commit, theo đúng thứ tự:

| # | Nhóm | Kernel | Nằm ở |
|---|---|---|---|
| 0 | Hạ tầng + chụp golden | 0 | build setting, test |
| 1 | Mask: cộng, trừ, đảo, theo độ sáng, theo màu, theo cạnh | 6 | kit |
| 2 | Color/Optics/Detail: HSL mixer, point color, color grading, vignette, lens warp, tách nhiễu (2) | 7 | kit |
| 3a | Heal: vòng đo màu, trọng số vòng, trộn | 3 | kit |
| 3b | Photo Stack + Focus Stack: quyết định, đỉnh, cộng/chia trọng số, Laplacian, stream (2) | 8 | kit |
| 3c | Panorama: warp, ramp, cộng dồn, max, mask, band, resolve… + warp biên | 14 | kit |
| 4 | Video: key theo độ sáng, key theo màu | 2 | app |

**Cố ý không có:**
- Đo khựng lần đầu — có hay không cũng không đổi quyết định (intent, 2026-09-25).
- Gộp key video vào mask ảnh — hai bên tính feather và tolerance khác nhau, gộp là đổi ảnh video; việc riêng.
- Đổi thuật toán, thêm tham số, sửa lỗi ảnh đang có — spec này chỉ đổi ngôn ngữ, lỗi nào thấy thì ghi ra.

## 3. Hành vi

- Kernel nằm trong file Metal, biên dịch lúc build cho Core Image. Kernel sai cú pháp là **build đỏ**.
- Kernel của kit đóng gói trong framework và nạp từ bundle của framework; kernel video đóng gói trong app.
- Kernel được nạp **một lần mỗi tiến trình**. Key video hôm nay dựng lại kernel mỗi khung — hết.
- Biên dải hue của HSL hôm nay chèn từ Swift vào chuỗi; sang Metal nó đi vào kernel **làm tham số**,
  không chép tay vào file Metal. *Vì chép tay là hai nguồn, sớm muộn lệch nhau.*
- Số slot point color (8) là chữ ký của kernel, không truyền được; một test khoá nó bằng tối đa của model.
- Nạp kernel thất bại (sai tên, thiếu metallib): bản debug dừng bằng assertion nêu tên kernel; bản release
  trả ảnh vào không đổi như hôm nay. Chặn chính là test nạp đủ 40 kernel (AC-5).
- Một kernel thay được bằng filter có sẵn của Apple (ví dụ cộng mask, đảo mask) thì thay — **chỉ khi**
  qua đúng golden ở AC-2. Không qua thì port, không nới ngưỡng.
- Sau nhóm 4: gỡ define tắt warning khỏi project; 0 chỗ còn khởi tạo kernel từ chuỗi, kể cả target test.

## 4. Ảnh golden

- Chụp ở commit nhóm 0, **trước** commit port đầu tiên, bằng chính kernel chuỗi hôm nay.
- Ảnh vào 48×48, dựng trong code: một lưới 16 ô (đen, trắng, 6 màu bão hoà, alpha 0 và 0,5, gần đen,
  gần trắng, dải xám, dải hue, dải bão hoà, ô cờ) và ảnh thật thu nhỏ. Đầu vào thứ hai trở đi xoay/lật.
- Mỗi kernel × mỗi bộ ảnh vào một file golden half-float nén; ảnh toàn pipeline và video lưu PNG 8-bit.
- Thêm một ảnh thật: crop vuông 512×512 JPEG sRGB, ≤ 150 KB, của chính tác giả, không người, đã xoá
  metadata (chốt 2026-09-25). Nó có cạnh sắc, trời chuyển mượt, màu bão hoà nhiều hue, bóng tối có nhiễu,
  vùng cháy sáng. *Vì ảnh dựng bằng code không có kết cấu thật cho cạnh, nhiễu và heal.*
- So: lệch ≤ **1/255 mỗi kênh** là giống (đã chốt 2026-09-25). Giá trị ngoài 0…1 (kernel cộng dồn,
  hiệu có dấu) so tương đối: ≤ 1/255 × độ lớn của golden.

## 5. Ràng buộc

| Mặt | Ràng buộc |
|---|---|
| Ảnh ra | ≤ 1/255 mỗi kênh so với golden, với cả 40 kernel |
| Vùng con | kernel màu áp trên một vùng phải để yên pixel xa vùng đó, thử với ≥ 2 edit (memory `coreimage-color-kernel-region-trap`) |
| Bộ nhớ | test footprint panorama / focus stack đang có giữ nguyên ngưỡng ([NF-02](../04-non-functional-design/NF-02-memory-and-resources.md)) |
| Ranh giới kit | không SwiftUI/GRDB ([EX-01](../03-extensions-and-integrations/EX-01-shotdexkit-and-edit-extension.md)) |
| Extension | widget, share, edit action **không** link kit renderer (grep 2026-09-25) — không có đường nạp metallib trong extension để lo |
| Nền tảng | iOS 17 trở lên, không thêm dependency, chạy được trên simulator (test chạy ở đó) |
| Dung lượng | tổng file golden ≤ 2 MB |

## 6. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | 40 kernel chuỗi hôm nay, commit nhóm 0 | chạy bộ chụp golden | có golden cho mỗi kernel × mỗi ảnh vào ở §4, tổng ≤ 2 MB, commit trước mọi commit port | `KernelGoldenTests.matchesItsGolden` (45 ca × 2), `everyKernelHasACase`; 95 file, 1,0 MB |
| AC-2 | golden của một kernel đã port | render cùng ảnh vào bằng bản Metal | mọi pixel lệch ≤ 1/255 mỗi kênh; lặp cho cả 40 kernel | `KernelGoldenTests.matchesItsGolden` — Metal 38/40 (mọi nhóm trừ video) |
| AC-3 | ảnh 256×256, 2 mask ở ô 64×64 góc trên trái, 1 color edit ở giữa | render nhóm 1+2 bằng Metal | khối 32×32 quanh (0,875; 0,875) bằng bản chỉ có color edit ± 1/255, góc có mask đổi > 8/255, khớp golden | `KernelPipelineGoldenTests.editsInOneCornerLeaveTheFarCornerAlone` |
| AC-4 | một kernel Metal cố ý viết sai cú pháp | build scheme ShotDex | build đỏ, lỗi trỏ đúng file:dòng; hoàn lại thì build xanh | thử 2026-09-26: `MaskKernels.ci.metal:19:32: error: illegal vector component name 'q'`, TEST BUILD FAILED |
| AC-5 | build đủ 4 nhóm | chạy test nạp kernel | 40/40 nạp được; đổi tên một hàm kernel thì test đỏ | `KernelLibraryTests.everyKernelLoads` (Metal: 38/40 sau nhóm 6/8) |
| AC-6 | metallib của kit nằm trong framework | test nạp một kernel kit | nạp từ bundle framework; bundle chính của app không có metallib của kit | `KernelLibraryTests.kitKernelsComeFromTheFrameworkBundle` |
| AC-7 | bản release, kernel không nạp được | render ảnh có mask | ảnh ra bằng ảnh vào, không crash | `KernelLibraryTests.aMissingKernelIsNilNotACrash` + các nơi gọi trả ảnh vào khi kernel `nil` |
| AC-8 | point color với 8 điểm (tối đa của model) | render | điểm thứ 8 đổi màu đúng như golden 8 điểm | ca `pointColorLastSlot` + `KernelLibraryTests.pointColorSlotsMatchTheModel` |
| AC-9 | ảnh thử 512×512, recipe bật mọi kernel nhóm 1–2 cùng lúc | render qua renderer đầy đủ | khớp golden toàn pipeline ≤ 1/255 | `KernelPipelineGoldenTests.groupsOneAndTwoMatchTheirGolden` |
| AC-10 | clip 1080p 120 khung, key theo độ sáng bật | render 120 khung | khung 1, 60, 120 khớp golden; kernel được tạo 1 lần | ⚠️ chưa có |
| AC-11 | các test render đang có (mask, color, lens, heal, stack, focus, panorama) | chạy sau mỗi nhóm | xanh **không sửa assertion nào** | `Tools/gate` |
| AC-12 | test footprint panorama / focus stack đang có | chạy sau nhóm 3b, 3c | xanh với ngưỡng không đổi | `Tools/gate` |
| AC-13 | một file golden bị xoá | chạy test so pixel | test đỏ, không bỏ qua | `KernelGoldenTests.aMissingGoldenIsAFailure` |
| AC-14 | sau nhóm 4 | build + grep toàn repo | 0 khởi tạo kernel từ chuỗi, 0 define tắt warning, Issue navigator 0 warning | hook `build-check.py` + grep |

**Đường hỏng không áp dụng**: mạng, iCloud-only, quyền `.limited`, huỷ giữa chừng, undo — spec không đổi
đường đọc ảnh, lịch sử sửa hay luồng export; ba luồng đó giữ test đang có (AC-11).

**Chưa chứng minh được:** AC-2 (2/40 kernel chưa port), AC-5 (đủ 40 bằng Metal), AC-10, AC-12, AC-14.

## 7. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Cờ biên dịch Core Image áp cho **mọi** file Metal của target — sau này thêm shader compute thường vào kit sẽ vỡ | ghi vào EX-01 lúc làm nhóm 0; shader thường đặt target khác |
| GPU thật làm tròn khác simulator, test chỉ chạy simulator | mở editor trên máy thật một lần sau nhóm 2 và 3c, so ảnh xuất với bản trên sim |
| Kernel dùng half-float trung gian ra lệch > 1/255 ở phép chia (resolve panorama, focus stack) | dùng float đầy đủ trong kernel; không nới ngưỡng |
| Laplacian và warp biên panorama là kernel tổng quát có vùng quan tâm tự khai | giữ nguyên hàm vùng quan tâm; AC-3 và golden phủ biên ảnh |
