# FS-03.15 — Đủ thông số Lightroom (trừ mask AI cần model mới và HDR)

`FS-03.15` · tier D · `ShotDexKit/Models/` · `ShotDexKit/Render/` · `ShotDex/Features/Editing/`
· `Domain/Editing/` · cập nhật 2026-09-28

**Một câu:** mỗi thông số Lightroom còn thiếu có một control trong editor, một trường trong recipe và một
thẻ `crs:` nhận nó — để preset nhập vào ([FS-03.14](14-lightroom-preset-exchange.md)) không mất phần nào.

Nguồn: intent [2026-09-27-lightroom-parameter-parity](../../_intents/2026-09-27-lightroom-parameter-parity.md);
nối tiếp [FS-03.11](11-parity-with-lightroom.md). Chỗ đặt control: [FS-03.13](13-iphone-editor-layout.md).

## 1. Người dùng cần gì

Người chụp mang thư viện preset Lightroom sang và mong look ra gần như cũ; khi tự chỉnh, họ tìm đúng
slider theo tên họ đã quen. Hôm nay preset mất Calibration, curve vùng, B&W mixer, Upright, vết cọ heal và
thông số riêng của mask — nên look nhập vào sai mà không ai báo.

## 2. Phạm vi và các phần

| Phần | Nhóm thông số |
|---|---|
| [15a](15a-tone-color-calibration.md) | curve dạng vùng · B&W mixer 8 màu · Calibration |
| [15b](15b-detail-optics-transform.md) | NR thêm 3 slider · Defringe tím/lục · méo và tối góc ống kính chỉnh tay · Aspect · Upright · Vignette Style |
| [15c](15c-retouch-and-red-eye.md) | vết heal/clone dạng nét cọ · Opacity · New Source · Visualize Spots · Spot Pins · Clear All · Red Eye |
| [15d](15d-mask-additions.md) | phép giao · Hue, phủ màu, Tone Curve, Point Color, Moiré, Defringe cho từng mask · Object · People · tóc/da/răng/kính |
| [15e](15e-lens-blur.md) | Lens Blur đầy đủ · độ sâu ước lượng bằng Depth Anything (kèm trong app) cho ảnh không có bản đồ độ sâu |

**Cố ý không có:**
- Mask cần model tự kiếm: lông mày, quần áo, tách tròng trắng / mống mắt — preset có thì bỏ qua và ghi vào
  báo cáo import ([FS-03.14](14-lightroom-preset-exchange.md)). *Vì không có model Apple công bố cho việc đó.*
- **Remove** (tô lên vật để xoá) — tạm bỏ tới khi Apple có API/model vá ảnh hỗ trợ; xem [15c §6](15c-retouch-and-red-eye.md).
- HDR (chế độ sửa HDR, xuất gain map) — intent riêng.
- Nguồn hồ sơ ống kính và ba slider độ mạnh của profile — [FS-03.16](16-lens-correction-sources.md).
  Spec này chỉ lo hai slider chỉnh tay (méo, tối góc).
- Pet Eye, Remove "Generative AI", Denoise AI — cần model, cùng lý do với mục đầu.
- Hứa giống Lightroom từng pixel: mỗi engine tính "Exposure +0,5" một kiểu. Hệ số quy đổi đo ở thử nghiệm §7.

## 3. Thứ tự render sau khi thêm

Số là thứ tự chạy; chữ đậm là pass mới hoặc dời chỗ.

| # | Pass | Mới / đổi |
|---|---|---|
| 1 | Giải mã nguồn (RAW: bù tối góc ống kính theo profile — FS-03.16) | — |
| 2 | **Lens Blur** trên ảnh chưa chỉnh, tuyến tính (preview: 8 mức mờ dựng sẵn) | thay Depth Blur (15e) |
| 3 | **Tối góc ống kính chỉnh tay**, tuyến tính | mới (15b) |
| 4 | **Calibration**, tuyến tính | mới (15a) |
| 5 | Light · WB · Presence | — |
| 6 | Detail: NR (+ Contrast, Color Detail, Smoothness) → Sharpen → Definition → Texture → Clarity | thêm slider |
| 7 | Dehaze | — |
| 8 | Color: HSL Mixer **hoặc B&W Mixer + chuyển xám** → Point Color → Grading | B&W dời từ đầu chuỗi (15a) |
| 9 | Curve: **vùng** rồi điểm, nướng chung một bảng tra 256 mức | mới (15a) |
| 10 | Nắn ống kính: profile + **méo chỉnh tay**, một lượt warp | thêm (15b) |
| 11 | Optics: CA · **Defringe tím/lục theo rìa** | viết lại (15b) |
| 12 | Geo: **phép nắn Upright đã giải** → thanh chỉnh tay (+ **Aspect**) → Constrain Crop | đổi (15b) |
| 13 | Look (film / LUT) → Crop | — |
| 14 | Retouch: Heal · Clone (tròn và nét cọ) → **Red Eye** | thêm (15c) |
| 15 | Mask: cộng · trừ · **giao**; mỗi mask thêm Hue, phủ màu, curve, point color, moiré, defringe | thêm (15d) |
| 16 | **Post-crop vignette (+ Style) → Grain** | dời từ sau Dehaze (15b) |
| 17 | Hạ cỡ preview → markup / overlay | — |

Test đọc thứ tự này từ dữ liệu, như thứ tự pass Detail đang làm (FS-03.11 AC-13). Đổi chỗ B&W và
vignette làm ảnh đã sửa ra khác — được phép vì app chưa phát hành; golden toàn pipeline chụp lại một lần.

- **Một danh sách pass dùng chung** cho ảnh tĩnh, khung Live Photo và mask tự động; không nơi nào chép tay
  chuỗi pass. *Vì chép tay thì đổi thứ tự ở ảnh tĩnh mà quên Live Photo — bản lưu ra khác ảnh trong editor.*
- **Mask không có B&W, Vignette, Grain** (Lightroom cũng không): bộ chỉnh chuẩn trong mask chỉ còn Light · WB
  · Presence · Detail · Dehaze, cộng phần riêng của 15d §2. Muốn xám trong mask thì Saturation −100.
- **Video Studio giữ thứ tự pass hôm nay** (B&W, Vignette, Grain trong khâu chỉnh chung) tới khi
  [FS-12](../FS-12-video-studio/) tự quyết; bảng trên chỉ áp cho ảnh.

## 4. Dữ liệu

- Mọi trường mới **có thì đọc, không thì mặc định**; mặc định nằm trong trạng thái "chưa sửa", nên Reset và
  nhãn "đã sửa" không sai. Decode khoan dung: một phần tử lạ chỉ mất chính nó.
- App chưa phát hành: không migration, không cờ phiên bản (luật 2026-09-23). Depth Blur bỏ hẳn.
- **Đi theo look** (Copy Edits, Sync Look, My Looks): Calibration, curve vùng, B&W mixer, NR, Defringe,
  Vignette Style, méo/tối góc chỉnh tay, **chế độ Upright** Auto/Level/Vertical/Full.
- Chế độ Upright dán sang ảnh khác thì **giải lại trên ảnh đích**; phép nắn đã giải của ảnh nguồn không chép.
- **Thuộc về một khung** (không bao giờ chép): vết retouch, Red Eye, đường guide Upright (Guided), phép nắn
  đã giải, mask, điểm lấy nét Lens Blur. Cùng lát cắt với [FS-03.10](10-copy-paste-edits.md).
- Không dữ liệu nào vào `photo_metadata`. Matte sinh ra và độ sâu ước lượng lưu thành file trong kho riêng
  ([BD-02](../../01-basic-design/BD-02-database-design.md)), xem 15d §5.

## 5. Ràng buộc

| Mặt | Ràng buộc |
|---|---|
| Hiệu năng | preview không hạ độ phân giải khi kéo ([FS-03.04](04-raw-and-render-graph.md)); pass nặng dùng kết quả đã dựng sẵn hoặc đã giải, không dùng ảnh nhỏ |
| Kernel | kernel mới viết Metal cho Core Image, có golden ≤ 1/255 ([FS-16](../FS-16-metal-kernels.md)); kernel màu trên vùng con phải để yên pixel xa |
| Kit | không SwiftUI/GRDB, type mới công khai ([EX-01](../../03-extensions-and-integrations/EX-01-shotdexkit-and-edit-extension.md)) |
| Bộ nhớ | lưu ảnh 100MP (11648×8736): đỉnh **≤ 1,5GB** (vừa máy 6GB); vượt trần thì giữ phiên, báo lỗi, không tạo ảnh rỗng ([NF-02](../../04-non-functional-design/NF-02-memory-and-resources.md)) |
| Model | chỉ model Apple công bố cho Core ML, mọi thứ chạy trên máy; Depth Anything V2 (~50MB) kèm trong app, cạnh model bầu trời 41MB |
| Chữ | không có chữ "AI" ở control nào |

- Trần bộ nhớ extension (12MP ≤ 120MB) **chưa áp** cho pass mới: hôm nay không extension nào link renderer
  (FS-16 §5). Ghi ở EX-01; ngày có extension render thì đo lại từng pass.

## 6. Đã chốt 2026-09-28

Lý do từng điểm: [.planboard/editor-specs-decisions/DECISIONS.md](../../../.planboard/editor-specs-decisions/DECISIONS.md).

- D51 — curve vùng nướng chung bảng tra với curve điểm (15a §1).
- D52 — chuyển xám B&W dời vào chặng Color, sau WB và Light (15a §2).
- D53 — Calibration ngay sau Lens Blur, trước Light (15a §3).
- D54 — tối góc chỉnh tay tuyến tính, ngay sau Lens Blur (15b §3).
- D55 — vignette rồi grain chạy sau crop và mask (15b §5).
- D56 — chế độ Upright đi theo look, giải lại trên ảnh đích; Guided ở lại (§4).
- D57 — Upright lưu chế độ + phép nắn đã giải riêng, slider tay cộng lên trên (15b §4).
- D58 — matte sinh ra lưu thành file trong kho riêng (15d §5).
- D59 — kèm Depth Anything trong app; Lens Blur chạy cả trên ảnh không có độ sâu (15e §3).
- D60 — trần bộ nhớ extension hoãn tới khi có extension render, ghi ở EX-01 (§5).
- D61 — lưu ảnh 100MP đỉnh ≤ 1,5GB (§5).
- D62 — Lens Blur dựng sẵn 8 mức mờ, kéo Amount chỉ trộn lại (15e §2).
- D63 — (luật lưu full-res của Remove) không chạy — theo Remove tạm bỏ (15c §6).
- D64 — Upright: Vision tìm chân trời cho Level, bộ dò đường dọc tự viết (15b §4).
- D65 — Constrain Crop tắt thì kéo giãn mép như hôm nay (15b §4).
- D66 — Remove tạm bỏ tới khi Apple có API/model hỗ trợ (15c §6).
- D67 — Subject = mọi đối tượng, không cần chạm; Object = chạm từng vật (15d §3).
- D68 — lưới chọn loại mask 4×4, ba ô khuôn mặt giữ ở ngoài (15d §3).
- D69 — Red Eye có cả chạm từng mắt và nút tự dò (15c §4–5).
- D70 — Red Eye là ô thứ tư trong hàng chế độ Heal (15c §1).

Chốt thêm khi đối chiếu kế hoạch với code — lý do:
[.planboard/plans-deviations/DECISIONS.md](../../../.planboard/plans-deviations/DECISIONS.md).

- E10 — Subtract của vùng mask = hiện tại × (1 − vùng trừ) (15d §1).
- E11 — guide thứ 5 của Upright Guided: dòng chú "Up to 4 guides" (15b §4, cả 13b AC-24).
- E12 — AC-31 đo trong không gian làm việc tuyến tính (15c §7).
- E13 — mask bỏ B&W, Vignette, Grain; Video Studio giữ thứ tự pass cũ tới khi FS-12 quyết (§3).
- E14 — hai cặp Distortion · Vignetting giữ tên, tách bằng nhãn nhóm LENS PROFILE / MANUAL (15b §3).
- E15 — gộp ba chuỗi pass chép tay thành một danh sách chung trước khi đổi thứ tự pass (§3).

## 7. Thử nghiệm và câu còn treo

1. **Depth Anything V2** — số đo (dung lượng trong app, thời gian trên iPhone 12 và 15, mép tóc) ghi vào 15e
   AC-60; là phép đo, không chặn phát hành.
2. **Hệ số quy đổi Lightroom → ShotDex** cho từng slider — dùng chung với FS-03.14; bảng `crs:` ở các phần
   ghi thang Lightroom, chưa ghi hệ số.
3. **Danh sách thẻ `crs:`** (Lightroom 13–15), gồm cấu trúc mask group và retouch area, giá trị số của
   chế độ Upright và loại mask — cần agent `lightroom-parity` kiểm. Thẻ trong spec này ghi theo hiểu biết.

## 8. Tiêu chí nghiệm thu chung

AC đánh số liên tục qua các phần: chung AC-1…6 · 15a AC-7…15 · 15b AC-16…29 · 15c AC-30…39 · 15d
AC-40…52 · 15e AC-53…60. Máy mặc định: iPhone 17, iOS 26.5 và 18.6.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | recipe có mọi trường mới, một mask mang loại vùng lạ và một vết retouch có chế độ lạ | decode | chỉ mất đúng mask-vùng và vết đó; Calibration, curve vùng, mixer, Upright, Lens Blur còn nguyên | `RecipeLossyDecodingTests.newParityFieldsSurviveOneBadElement` · `.untouchedParityPartsWriteNothing` |
| AC-2 | ảnh A có Calibration Red Hue +30, curve vùng Shadows +40, 2 vết Heal, 1 Red Eye, Upright Guided | Copy Edits → Paste sang B | B nhận Calibration và curve vùng; 0 vết retouch, 0 Red Eye, 0 guide | `EditClipboardTests.parityLookSlice` |
| AC-3 | mỗi control mới ở 15a–15e | đọc bảng ánh xạ của FS-03.14 | mọi control có ≥ 1 thẻ `crs:` hoặc được ghi rõ "không có trong Lightroom" | ⚠️ chưa có (dự kiến `LightroomTagCoverageTests.everyParityControlHasATag`) |
| AC-4 | ảnh tổng hợp 11648×8736, recipe Lens Blur 50 + 3 vết Heal nét cọ + 3 mask | lưu full resolution | đỉnh bộ nhớ ≤ 1,5GB; vượt thì phiên còn, có thông báo lỗi, không tạo asset rỗng | `LargeImageRenderTests.hundredMegapixelSaveStaysUnderCeiling` (sim, 2026-09-29: đỉnh **834 MB** trên nền, render + JPEG) · đường lỗi: `render`/`write` ném trước `commit` (`PhotoEditingService.swift:393-405`), nên không có asset rỗng và phiên còn · ⚠️ số trên máy thật: đo lại |
| AC-5 | build scheme ShotDex sau khi thêm mọi pass | grep thư mục kit + chạy test nạp kernel | 0 import SwiftUI/GRDB trong kit; mọi kernel mới nạp được | `KernelLibraryTests.kitHasNoSwiftUIOrGRDB` + `everyKernelLoads` (mỗi kernel mới thêm một dòng) |
| AC-6 | recipe bật mọi pass của §3 | đọc thứ tự pass của renderer | đúng thứ tự bảng §3: Lens Blur → tối góc tay → Calibration → Light; B&W trong Color; vignette, grain sau mask; ảnh tĩnh, khung Live Photo và mask tự động đọc cùng một danh sách; chuỗi của mask không có B&W, Vignette, Grain | `RenderOrderTests.parityPassOrderMatchesTheSpec` · `.stillLiveAndAutoMaskShareOnePassList` · `.livePhotoFrameMatchesStill` · `.blackAndWhiteRunsInsideColor` · `EditorAdjustmentCatalogTests.maskHasNoBlackWhiteVignetteGrain`; golden `pipeline-groups-1-2` chụp lại một lần (2026-09-28), video không đổi |

**Chưa chứng minh được:** AC-3 (dời sang FS-03.14, task 7); số đo AC-4 trên máy thật.

## 9. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Đổi vị trí B&W và vignette làm ảnh cũ ra khác | cho phép (chưa phát hành); golden toàn pipeline chụp lại một lần, có ghi chú |
| Thẻ `crs:` ghi theo hiểu biết, có thể sai tên/giá trị | câu treo 3 chặn phần ánh xạ ở FS-03.14, không chặn control |
| Nhiều pass mới cùng lúc làm chậm lúc kéo | mỗi pass bỏ qua hẳn khi ở mặc định; đo frame time trước/sau ở 15e AC-57 |
| Kèm Depth Anything thêm ~50MB tải về cho mọi người | chấp nhận (chạy không cần mạng); số đo thật ở 15e AC-60 |
