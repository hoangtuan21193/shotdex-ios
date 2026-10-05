# FS-11b — Collage: màn xuất

`FS-11b` · phần tiếp của [FS-11](FS-11-collage.md) · `Features/Collage/CollageExportScreen.swift` · cập nhật 2026-10-02

Nguồn intent: [2026-10-02-ui-review-1002](../_intents/2026-10-02-ui-review-1002.md) — Z1, H1, Z2.

**Một câu:** chọn cỡ, chất lượng, định dạng, rồi lưu vào Photos hoặc lưu và gửi đi ngay — nút chính luôn thấy.

Board: `PH_CollageExport` · `IP_CollageExport` · `DI_CollageExport` · `DC_CollageExport`.

## 1. Nội dung

Màn xuất toàn màn: nền là chính ảnh ghép đã làm mờ và tối, bản xem trước thật, và một thẻ kính chứa 5 hàng —
**Size (Fit/2K/4K/Max) · Quality 0–100 · Format JPEG/HEIC · Keep EXIF of first photo · dung lượng ước tính**.
Nút `Save to Photos` cao 50, chữ đen trên amber. Dưới nó là nút phụ **Share…** cao 44 (H1).

## 2. Bố cục (Z1)

- **Hai pane khi cửa sổ rộng ≥ 700pt, cao ≥ 600pt và rộng hơn cao** (iPad ngang, Duo trong 951×669): bản xem
  trước trái lấy phần còn lại; cột phải rộng 400pt chứa thẻ kính, Save to Photos và Share…, nút ghim đáy cột.
  - Cùng ngưỡng và cùng bề rộng cột với Resize ([FS-03.07 §4](FS-03-photo-editor/07-resize-and-compression.md)).
  - Save to Photos và Share… nằm trọn trên vùng an toàn đáy, không cần cuộn.
  - Cửa sổ thấp (cao dưới 720pt, [NF-05 §4](../04-non-functional-design/NF-05-device-and-os-compatibility.md)) vẫn
    giữ hai pane; bản xem trước không có chiều cao cố định, khối nút ghim đáy cột phải và thấy được ở 669pt.
- **Mọi cửa sổ khác** (iPhone, iPad dọc, Split View, Duo ngoài): một cột như hiện tại; bản xem trước co lại trước,
  khối nút **ghim trên home indicator**, không bao giờ bị đẩy xuống dưới đáy.
- Thanh trên (đóng · tiêu đề Export) giữ nguyên ở cả hai bố cục.

## 3. Lưu và chia sẻ

- **Save to Photos**: lưu → index → thêm vào album người dùng **`ShotDex Collages`** (tạo nếu chưa có) → báo cho
  lưới → mở từ Library thì mở ảnh mới trong viewer, từ album thì đóng màn.
- Tên album là `ShotDex Collages` chứ không phải `Collages`: tab Collections đã có hàng Utilities `Collages` là
  *project mở lại được*. Album `Collages` do bản cũ tạo vẫn được nhận và ghi tiếp nếu còn.
- **Share…** (H1): lưu y như Save to Photos (album, Creations), rồi mở share sheet với ảnh mới, theo mức metadata
  mặc định của Settings ([FS-08.06 §4](FS-08-settings/06-share-metadata-privacy.md)). Đóng share sheet thì màn đi tiếp
  như Save: mở ảnh mới hoặc đóng.
  - *Vì* công thức collage chỉ được lưu khi xuất (FS-06.01b): share từ file tạm thì mất collage sau khi gửi (K26).
- Tải bản gốc của ô hỏng (iCloud, không mạng): không lưu gì, không mở share sheet; hiện Retry · Cancel như Save.
- **Collage làm từ ảnh server** ([FS-17.06 §5b](FS-17-import-from-server/06-edit-and-export.md)): chỉ một nút
  `Export…` (sheet xuất đã có đích Share), không có Share…; file render vào thư mục tạm của lượt, không lưu vào
  Photos, không vào album, không ghi Creations. Ảnh library vẫn thêm được qua picker; kéo thả từ app khác bị tắt.

## 4. Tiêu chí nghiệm thu

Collage mẫu **C** = 4 ảnh HEIC 24MP trên thiết bị, mẫu 2×2, tỉ lệ 4:5, Size 4K, JPEG, Quality 90.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | (Z1) iPad 13" ngang 1376×1032, collage C | mở Export | hai pane: xem trước trái, cột phải rộng 400pt; mép dưới Share… ≤ mép trên vùng an toàn đáy | ⚠️ chưa có — `Tools/ui-drive` dump |
| AC-2 | (Z1) Duo trong 951×669, collage C | mở Export | hai pane như AC-1; cả 5 hàng của thẻ, Save to Photos và Share… thấy được không cần cuộn | ⚠️ chưa có — `Tools/sim-shot inner` |
| AC-3 | (Z1) iPhone 402×874 và Duo ngoài 466×678, collage C | mở Export | một cột; mép dưới Share… ≤ 874 − 34 (iPhone), nằm trái rail 84pt (Duo ngoài) | ⚠️ chưa có |
| AC-4 | (Z1) iPad 13" dọc 1032×1376 và Split View 1/2 688pt | mở Export | một cột, không phải hai pane | ⚠️ chưa có |
| AC-5 | (H1, K26) collage C mở từ Library | chạm Share… | ảnh mới được lưu vào Photos và album `ShotDex Collages` **trước** khi share sheet mở; share sheet nhận đúng 1 ảnh 4:5 là asset đó | ⚠️ chưa có |
| AC-6 | (H1) như AC-5, share sheet đang mở | đóng share sheet không chọn đích | ảnh mới vẫn trong thư viện và album; viewer mở ảnh mới | ⚠️ chưa có |
| AC-7 | (H1) collage C, 1 ô là ảnh chỉ trên iCloud, máy không mạng | chạm Share… | không có ảnh mới, không mở share sheet; hiện lỗi tải kèm Retry · Cancel | ⚠️ chưa có — script `icloud-collage.json` thêm bước Share… |
| AC-8 | (H1) collage 3 ảnh từ NAS | mở Export | chỉ có nút `Export…`, không có Share… | ⚠️ chưa có |
| AC-9 | (Z2) iPad 13" ngang, collage 4 ảnh, 1 preset đã lưu, tab Layout | chụp inspector | khung mẫu là lưới 4 cột, ô 66pt, khe 8pt, preset ở ô đầu; không có dải cuộn ngang | ⚠️ chưa có — `Tools/ui-drive` dump khung từng ô |
| AC-10 | (Z2) iPhone 402×874, cùng collage | chụp panel Layout | vẫn dải cuộn ngang cao 74pt, ô 52pt | ⚠️ chưa có |
| AC-11 | (Z2) iPad 13" ngang, lưới khung mẫu | chạm ô mẫu thứ 3 | mẫu đó áp lên khung dựng, ô đó viền accent; một lần Undo trả về mẫu cũ | ⚠️ chưa có |

Mọi AC chạy trên cả iOS 26.5 và 18.6.
