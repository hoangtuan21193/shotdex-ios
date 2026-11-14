# FS-03 — Photo Editor

`FS-03` · tier D · `ShotDex/Features/Editing/` · `Domain/Editing/` · render core ở `ShotDexKit`
· cập nhật 2026-09-24

**Một câu:** editor ảnh đầy đủ — tone, màu, curve, look phim, mask cục bộ, markup — chạy trên cùng một lõi
render với extension sửa ảnh và các màn khác.

## Các phần

| # | Phần | Trả lời |
|---|---|---|
| 01 | [Phạm vi và panel](01-scope-and-panel.md) | ba tầng dọc, hàng lệnh nổi, bánh xe nhóm, histogram, dòng slider |
| 01b | [Thông số và Crop](01b-adjustments-and-crop.md) | từng nhóm slider làm gì, Upright, crop commit lúc nào |
| 02 | [Film simulation và preset](02-film-simulation-and-presets.md) | 49 look, năm cái được đo, bảng tra màu, My Looks |
| 03 | [Cử chỉ, so sánh, undo](03-gestures-compare-and-undo.md) | tranh chấp vuốt, mốc identity, History, Reset All |
| 04 | [RAW và render](04-raw-and-render-graph.md) | vì sao preview không hạ độ phân giải |
| 04b | [RAW iOS chưa đọc được](04b-unsupported-raw.md) | phán quyết theo máy × bản iOS, dấu trên lưới, câu báo nói máy và việc cần làm, cặp RAW+JPEG |
| 05 | [Mask cục bộ](05-local-masks.md) | hai tầng UI, bảy loại vùng, guide, overlay đỏ |
| 05b | [Vẽ mask và zoom](05b-mask-painting-and-zoom.md) | cỡ cọ theo màn hình, trọng tài chạm, zoom 10× |
| 06 | [Lưu và Live Photo](06-saving-recipe-and-live-photo.md) | recipe gắn vào ảnh, Save Copy vs Save Changes |
| 07 | [Resize](07-resize-and-compression.md) | preset, preview, chạy cả mẻ |
| 07b | [Xuất ra folder](07b-export-to-files.md) | Export… ra Files/ổ ngoài/server đã lưu, một Form, màn File Name, trùng tên, preset dùng chung với sheet xuất server |
| 07c | [Xuất ra folder: chạy mẻ và AC](07c-export-acceptance-criteria.md) | sáu chỗ đã chốt, tiến độ, iCloud cuốn chiếu, đường hỏng, 15 AC |
| 09 | [Màn rộng](09-wide-screen-and-batch-editing.md) | rail + panel + canvas, cột ngắn, History trong panel |
| 09b | [Sửa nhiều ảnh](09b-batch-editing-and-reference.md) | nháp theo ảnh, Sync, Save All, Reference View |
| 10 | [Copy / Paste edits](10-copy-paste-edits.md) | chép "cái nhìn", không chép crop và mask |
| 11 | [Đuổi kịp Lightroom](11-parity-with-lightroom.md) | xoá vết, mask khuôn mặt, LUT, background/depth, khử nhiễu, hồ sơ ống kính |
| 12 | [Panel phone: lưới 40pt](12-phone-panel-grid.md) | panel 264, một kiểu chip/slider, accent chỉ trên Save, tiêu chí nghiệm thu của đợt làm lại panel |
| 13 | [Editor iPhone](13-iphone-editor-layout.md) | thanh 6 công cụ cố định, panel 344/264, Edit một danh sách, Transform, danh sách mask/lớp, filmstrip 56, xoay ngang, Duo màn ngoài |
| 14 | [Trao đổi preset Lightroom](14-lightroom-preset-exchange.md) | nhập .xmp/.lrtemplate/DNG, xuất .shotdexlook/.xmp/.cube, quản lý và chia sẻ look |
| 15 | [Đủ thông số Lightroom](15-lightroom-parameter-parity.md) | calibration, curve vùng, B&W mixer, Upright, Remove, Red Eye, thông số riêng của mask, Lens Blur |
| 16 | [Nguồn sửa ống kính](16-lens-correction-sources.md) | ba slider độ mạnh, dữ liệu nhúng trong RAW → Lensfun → Apple, làm mới dữ liệu mỗi bản phát hành |
| 17 | [iPad và Duo theo design 30/9](17-wide-design.md) | ảnh + cột cố định 280/260 hoặc panel dưới 400, băng nút nổi, công cụ ở chân cột, Duo màn ngoài dùng dải 84, Duo trong xoay dọc; thay 09 §3–7 và 13d §3 |
| 18 | [Cảm giác sửa như Lightroom](18-editing-feel-like-lightroom.md) | nháp khi kéo/nét khi thả, histogram thưa, giữ để xem look, lớp cháy, Snapshot, nút chia đôi |

## Quy tắc chung

- **Ảnh không bao giờ bị chrome đè**, và không có gì nổi trên ảnh — trừ card histogram.
- **Preview không hạ độ phân giải để chạy mượt**; mượt đến từ tần số khung.
- **Cái gì thuộc về một khung hình cụ thể thì không được chép sang ảnh khác** — crop, mask, markup. Lát cắt
  này dùng chung cho Copy Edits, Sync Look và preset My Looks.
- **Một ngón là vẽ, hai ngón là zoom/pan** ở mọi bề mặt có nét vẽ.
- Lõi render nằm ở `ShotDexKit`, dùng chung với extension sửa ảnh
  ([EX-01](../../03-extensions-and-integrations/EX-01-shotdexkit-and-edit-extension.md)).
- Phân tầng (model / domain / data / UI): [BD-01](../../01-basic-design/BD-01-system-architecture.md).

## Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
