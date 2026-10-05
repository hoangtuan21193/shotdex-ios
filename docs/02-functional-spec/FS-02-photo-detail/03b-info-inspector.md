# FS-02.03b — Photo Info ở màn rộng: cột bên phải

`FS-02.03b` · `Features/Library/PhotoDetailScreen.swift` · `MetadataPanel.swift` · cập nhật 2026-10-02
· nguồn [intent ui-review-1002](../../_intents/2026-10-02-ui-review-1002.md) (V3)

**Một câu:** trên cửa sổ ngang đủ rộng, Photo Info là một cột đứng cạnh ảnh, để người chụp đọc EXIF mà vẫn
thấy trọn tấm ảnh và vẫn lật được sang ảnh kế.

## 1. Khi nào là cột, khi nào là sheet

| Cửa sổ | Photo Info |
|---|---|
| rộng ≥ 700pt, cao ≥ 600pt **và** rộng > cao — iPad ngang 1376×1032, Duo trong 951×669, Split View / Stage Manager khi qua cả ba ngưỡng | **cột bên phải** |
| mọi cửa sổ khác — iPhone 402×874, iPad dọc 1032×1376, Duo ngoài 466×678, Split View hẹp | sheet có Done ([03](03-info-panel-and-metadata.md) §3) |

- Cùng ngưỡng với sidebar của editor (DESIGN §10.3): một cột tiêu **bề rộng**, thứ chỉ cửa sổ ngang mới dư.
- Đo theo **cửa sổ thật**, không theo idiom hay size class ([NF-05](../../04-non-functional-design/NF-05-device-and-os-compatibility.md) luật 3).
- Đổi kích thước giữa chừng (xoay iPad, kéo vạch Split View) mà Info đang mở → Info **vẫn mở**, chỉ đổi hình
  dạng: cột thành sheet hoặc ngược lại, cùng ảnh, cùng vị trí cuộn đầu.

## 2. Cột

- Rộng **360pt cố định** (K10), không kéo đổi, bám mép phải cửa sổ, cao hết cửa sổ; nền theo viewer (luôn tối).
  Con số là một token mới ở DESIGN §6, không viết literal trong màn.
- Nội dung, thứ tự section và luật dựng **y hệt sheet** ([03](03-info-panel-and-metadata.md) §3–§7): dựng ngay
  từ dữ liệu đã index, đọc bổ sung từ file chỉ cho trang đang hiện.
- Đầu cột: tiêu đề **Photo Info** và nút **Done** bên phải — cùng nhãn với sheet. *Vì cùng một hành động ở hai
  bố cục thì cùng nhãn (luật "một control, một chất liệu" của DESIGN.md), và lúc phóng chrome ẩn thì Done là lối đóng duy nhất nhìn thấy.*
- Mở / đóng: nút Info, phím I, vuốt lên trên ảnh (mở), Done (đóng). Info là nút bật/tắt.
- **Nhớ lần cuối** (K11): cột mở hay đóng được lưu như một tuỳ chọn **của máy**
  ([FS-01.07](../FS-01-library/07-state-restoration.md)), không theo scene; mở viewer lần sau ở cửa sổ đủ
  rộng thì cột theo đúng trạng thái đó. Cửa sổ hẹp mở viewer thì **không tự bật sheet**, kể cả khi lần cuối cột
  đang mở. *Vì một sheet tự bật che ảnh người dùng vừa chạm vào.*

## 3. Ảnh và chrome khi cột mở

- Ảnh co vào phần còn lại và **vẽ lại vừa khung**, không có pixel nào nằm dưới cột. Ảnh 3:2 ngang:

| Cửa sổ | Cột đóng | Cột mở (cột 360pt) |
|---|---|---|
| iPad 1376×1032 | 1376×917 | 1016×677 |
| Duo trong 951×669 | 951×634 | 591×394 |

- Nút X, bảng tóm tắt (≤ 520pt, [03](03-info-panel-and-metadata.md) §2) và thanh đáy nằm **trong vùng ảnh**,
  không chạy dưới cột; thanh đáy căn giữa vùng ảnh.
- Pager vẫn lật ngang trong vùng ảnh; vuốt xuống vẫn đóng viewer (cột đi cùng).
- Phóng: chrome ẩn như [01](01-pager-and-image-loading.md) §3, **cột ở lại**. Video xem toàn màn thì cột ẩn,
  thoát toàn màn thì cột hiện lại.

## 4. Lật trang khi cột mở

- Cột ở lại, nội dung đổi sang ảnh mới **trong khung hình đầu sau khi lật xong**, bằng dữ liệu đã index.
- Đọc file, tra địa chỉ và Shutter Count của trang cũ **bị huỷ** khi rời trang; tra địa chỉ dùng cache theo
  toạ độ ([03](03-info-panel-and-metadata.md) §4), nên một loạt ảnh cùng chỗ không gọi lại dịch vụ.
- Ảnh chỉ có trên iCloud, máy mất mạng: cột vẫn dựng từ index, Shutter Count ghi lý do, không vòng quay chặn
  cả cột.

## 5. Thiết bị, iOS, trợ năng

- iOS 26 và trước 26: cột của hệ thống có từ iOS 17, không rẽ nhánh; chỉ chất liệu nút khác như phần còn lại
  của viewer.
- VoiceOver: cột là một vùng riêng, đọc sau thanh đáy của viewer. Cỡ chữ trợ năng: một cột trường như sheet.
- Duo ngoài và iPhone không bao giờ thấy cột.

Board: `IP_Viewer`, `DI_Viewer` (thêm trạng thái cột mở), `IP_Metadata`, `DI_Metadata` (đổi từ sheet thành cột).

## 6. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | (V3, K10) iPad 1376×1032 iOS 26.5, ảnh 6000×4000 | bấm Info | không có sheet; cột rộng 360pt bám mép phải; khung ảnh trong dump nằm trọn trong x 0–1016pt | ⚠️ chưa có |
| AC-2 | (V3, K10) Duo trong 951×669 | bấm Info | cột rộng 360pt; X, bảng tóm tắt, Share, Delete đều có mép phải ≤ 591pt; Done ở đầu cột | ⚠️ chưa có |
| AC-3 | (V3) iPad dọc 1032×1376 | bấm Info | sheet có Done, không có cột | ⚠️ chưa có |
| AC-4 | (V3) cột mở ở ảnh A (Sony, 85mm), ảnh B kế là Fujifilm 23mm | vuốt sang B | cột vẫn mở; Camera & Lens ghi Fujifilm 23mm ở khung hình đầu sau khi lật xong; 0 lượt đọc file của A còn chạy | ⚠️ chưa có |
| AC-5 | (V3) cột mở, iPad có bàn phím | bấm I | cột đóng, khung ảnh rộng lại 1376pt | ⚠️ chưa có |
| AC-6 | (V3) cột mở | pinch phóng 3× | X và thanh đáy ẩn; cột còn; bấm Done trong cột thì cột đóng | ⚠️ chưa có |
| AC-7 | (V3) iPad ngang, cột mở | xoay sang dọc | Info vẫn mở dưới dạng sheet có Done, cùng ảnh | ⚠️ chưa có — `Tools/ui-drive` + burst `Tools/sim-shot` (bước orientation) |
| AC-8 | (V3) ảnh chỉ có trên iCloud, máy mất mạng, cột mở | lật tới ảnh đó | cột hiện Camera & Lens, Exposure từ index; Shutter Count ghi lý do; không vòng quay nào chặn cả cột quá 350 ms | ⚠️ chưa có |
| AC-9 | (V3) video 30 s, cột mở | vào xem toàn màn rồi thoát | trong lúc toàn màn không thấy cột; thoát ra thì cột hiện lại với thông tin track hình và tiếng | ⚠️ chưa có |
| AC-10 | (V3) iPad iOS 18.6 ngang | bấm Info | cột hiện như AC-1, có Done | ⚠️ chưa có |
| AC-11 | (K11) iPad ngang, cột đang mở | đóng viewer, mở một ảnh khác | viewer mở ra với cột đã mở; làm lại với cột đóng thì viewer mở ra không có cột | ⚠️ chưa có |
| AC-12 | (K11) cột đang mở lúc đóng viewer; app bị tắt hẳn rồi mở lại | mở một ảnh | cột vẫn mở (tuỳ chọn còn sau khi khởi động lại) | ⚠️ chưa có |
| AC-13 | (K11) lần cuối cột mở; iPad dọc 1032×1376 | mở một ảnh | không có sheet tự bật; bấm Info thì sheet có Done hiện | ⚠️ chưa có |
