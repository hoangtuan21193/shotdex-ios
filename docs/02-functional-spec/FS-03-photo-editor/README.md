# FS-03 — Photo Editor

`FS-03` · tier D · `ShotDex/Features/Editing/` · `Domain/Editing/` · render core ở `ShotDexKit`
· cập nhật 2026-09-22

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
| 05 | [Mask cục bộ](05-local-masks.md) | hai tầng UI, bảy loại vùng, guide, overlay đỏ |
| 05b | [Vẽ mask và zoom](05b-mask-painting-and-zoom.md) | cỡ cọ theo màn hình, trọng tài chạm, zoom 10× |
| 06 | [Lưu và Live Photo](06-saving-recipe-and-live-photo.md) | recipe gắn vào ảnh, Save Copy vs Save Changes |
| 07 | [Resize](07-resize-and-compression.md) | preset, preview, chạy cả mẻ |
| 09 | [Màn rộng](09-wide-screen-and-batch-editing.md) | rail + panel + canvas, cột ngắn, History trong panel |
| 09b | [Sửa nhiều ảnh](09b-batch-editing-and-reference.md) | nháp theo ảnh, Sync, Save All, Reference View |
| 10 | [Copy / Paste edits](10-copy-paste-edits.md) | chép "cái nhìn", không chép crop và mask |

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
