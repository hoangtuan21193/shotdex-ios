# FS-03.07 — Resize

`FS-03.07` · `Features/Editing/CompressionScreen.swift` · `CompressionPresetStore` · cập nhật 2026-10-02

Nguồn intent: [2026-10-02-ui-review-1002](../../_intents/2026-10-02-ui-review-1002.md) — D4, H1, Z1, Q8.

**Một câu:** thu nhỏ và nén ảnh, một tấm hoặc cả mẻ — và tên gọi phải giống nhau ở mọi lối vào.

## 1. Quy tắc

- **Tên hiển thị là "Resize", không phải "Compress"** ở mọi chỗ: nav title, nút bulk, alert lỗi, dòng
  trạng thái, và cả **Settings → Export → Resize Presets**. Lối vào ở hai menu đã tên là Resize; một màn
  tự đổi tên trên đường vào đọc như công cụ khác.
- **Màn không nhớ lựa chọn phiên trước.**
  Ngoại lệ: watermark (cấu hình và bật/tắt) được nhớ, chung với mọi lối xuất ([FS-05.04 §5](../FS-05-markup/04-watermark-on-export.md)).
- **Không có ô nhập dung lượng đích** — chỉ chất lượng và kích thước pixel.
- Crop mode chỉ **Fill** hoặc **Fit**, **không có Stretch**.
- Xoá bản gốc thất bại là **non-fatal**: bản nén đã lưu rồi.

## 2. Mặc định

| Mục | Mặc định |
|---|---|
| Quality | **80%**, dải 10–100 |
| Format (nguồn JPEG/HEIC) | **Same as Original** |
| Format (nguồn RAW) | **JPEG** — RAW luôn xuất ảnh tĩnh JPEG/HEIC |
| Include Metadata | bật |
| **Delete Originals** | **bật** |

Xoá bản gốc đi qua đường xoá của hệ thống nên Photos tự hỏi xác nhận và ảnh rơi vào Recently Deleted; chỉ
xoá những ảnh nén thành công. Xoá không được thì summary ghi *"Originals couldn't be deleted"*.

## 3. Preset

Built-in: **Original** · **4K** = cạnh dài 3840px · **2048px** = cạnh dài tối đa 2048px · **1080px** =
cạnh dài 1080px.

Đúng theo nghĩa đó: 4K và 1080 **có thể phóng to** ảnh nhỏ, còn 2048 là **trần, không phóng to**.

Settings → Export cho thêm/sửa preset `{tên, width, height, Fill/Fit, quality, format}`.
Slider Quality của màn sửa preset có tên cho VoiceOver: đọc *"Quality, 80%"*, không chỉ con số (Q8).

## 4. Màn hình

Board: `PH_Compress` · `IP_Compress` · `DI_Compress` · `DC_Compress` · `*_CompressionPresets` (Q8).

- **Hai pane khi cửa sổ rộng ≥ 700pt, cao ≥ 600pt và rộng hơn cao** (iPad ngang, Duo trong 951×669) (Z1):
  preview trái lấy phần còn lại; cột phải rộng 400pt gồm các tuỳ chọn cuộn được và nút chính ghim đáy cột.
  - Nút chính luôn nằm trọn trong cửa sổ, trên vùng an toàn đáy, không cần cuộn. Preview cao hết pane trái.
  - Cửa sổ thấp (cao dưới 720pt, [NF-05 §4](../../04-non-functional-design/NF-05-device-and-os-compatibility.md))
    vẫn giữ hai pane; preview không có chiều cao cố định, nút chính ghim đáy cột phải và thấy được ở 669pt.
  - *Vì* ở Duo trong 669pt, cột một hàng đẩy nút xuống 130–230pt dưới đáy.
- **Mọi cửa sổ khác** (iPhone, iPad dọc, Split View, Duo ngoài): một cột, form tối đa 700pt căn giữa, nút chính
  **ghim trên home indicator**; nội dung cuộn chừa đúng chiều cao nút để mục cuối không bị che.
- **Nút chính nói hết việc nó làm** (D4): Delete Originals bật → *"Resize 8 Photos and Delete Originals"* (một
  ảnh: *"Resize and Delete Original"*); tắt → *"Resize 8 Photos"* / *"Save to Photos"*. Đổi chữ ngay khi gạt công tắc.
- Chữ và glyph trên nền amber của nút là **đen** (8.9:1), như glyph active của tầng D (DESIGN §9); nút mờ thì chữ dim.
- **Preview**: một ảnh thì kéo được điểm neo crop; nhiều ảnh thì thành **carousel vuốt ngang** để duyệt
  lại đúng các ảnh đã chọn, kèm pill `i / N`.
- **Watermark** ([FS-05.04](../FS-05-markup/04-watermark-on-export.md)): hàng 44pt giữa Metadata và Delete Originals,
  giá trị là tên preset, `Off`, hoặc `None` mờ khi chưa có preset; chạm mở màn Watermark. Bật dấu thì Delete Originals
  tắt, mờ, dòng phụ *"Originals are kept when you add a watermark."*; preview 320pt và từng trang carousel vẽ dấu bằng
  đúng bộ raster của bản xuất. Cấu hình dấu được nhớ (ngoại lệ có ghi ở §1).
- **Fit** giữ trọn ảnh trong khung; **Fill** crop đúng kích thước. Một ảnh cho kéo neo để chọn vùng crop;
  cả mẻ dùng crop giữa cố định.
- Ước lượng dung lượng: encode một bản preview nhỏ rồi scale theo số pixel đích, debounce khi kéo Quality.
  **Là ước lượng, và màn ghi rõ có thể lệch nhẹ** so với bản full-res.
- Tên file ra: basename gốc + `_SHOTDEX_COMPRESSED_N`; bộ đếm này **tách riêng** với bộ đếm của Save Copy.
- Kết quả là asset mới, giữ color profile gốc tốt nhất có thể; xuất từ album thì thêm lại album đó.
  Live Photo ra ảnh tĩnh.

## 5. Chạy cả mẻ

- Lối vào: tile **Resize & Compress** trong chế độ chọn của Library, album, smart album và On This Day.
  Hoạt động từ **1 ảnh**, **không giới hạn trên**. Chỉ ảnh được đưa vào mẻ.
- Xử lý **tuần tự** để kiểm soát bộ nhớ; lỗi một ảnh thì tiếp tục ảnh khác.
- **RAW iOS chưa đọc được** ([FS-03.04b §4](04b-unsupported-raw.md)): RAW-only vào danh sách lỗi của lượt chạy,
  không tạo file từ bản xem trước; **cặp** RAW+JPEG mà RAW không đọc được thì làm từ JPEG của cặp. Preview của màn
  lấy ảnh **đọc được đầu tiên** trong mẻ, không báo lỗi cả màn vì ảnh đầu là RAW hỏng.
- Trong lúc chạy: **modal giữa màn hình** (scrim đen phủ kín, nuốt chạm) với spinner + thanh tiến độ +
  `Processing N of M`, mọi control dưới bị tắt. Bật Delete Originals thì modal đổi chữ thành
  *"Deleting originals…"* rồi mới đóng.
- **Cancel** dừng mẻ và xoá mọi bản copy đã tạo **trong chính mẻ đó**; xoá không hết thì summary báo lỗi
  thay vì tuyên bố đã rollback.
- **Chạy sạch thì màn ở lại, không đóng** (D4, H1, K25). Toast 3 s trên màn Resize:
  *"8 saved · 41 MB freed · Originals in Recently Deleted"*; vùng nút ghim đổi thành **Share 8 Photos** + **Done**.
  Chỉ Done đóng màn; các tuỳ chọn mờ đi, không chạy lại được mẻ đó.
  - Delete Originals tắt: toast chỉ *"8 saved to Photos"*. Số MB ≤ 0 (bản copy lớn hơn gốc): bỏ cụm *freed*.
  - MB freed = tổng dung lượng bản gốc vừa xoá − tổng dung lượng bản copy, theo cỡ file đã index; ảnh chưa
    biết cỡ thì không tính, không biết cỡ ảnh nào thì bỏ cụm *freed*. Đơn vị theo locale (MB, GB).
  - VoiceOver đọc chữ của toast một lần khi nó hiện.
  - *Vì* nút Share trên một banner sống 4 s thì người resize để gửi đi phải đua với đồng hồ, VoiceOver không với kịp.
- **Share N Photos** (H1) mở share sheet với đúng các bản copy vừa lưu của lượt này, theo mức metadata mặc định của
  Settings như mọi lối Share ([FS-08.06 §4](../FS-08-settings/06-share-metadata-privacy.md)). N = số bản copy còn tồn tại.
  Đóng share sheet thì về lại màn Resize, chưa đóng.
- **Summary** chỉ hiện khi có việc cần báo (thất bại, huỷ, rơi về JPEG, lỗi xoá hay người dùng từ chối hộp xoá của
  Photos). Trên summary **không có nút Cancel**: có bản copy thì Share N Photos + Done, không có thì chỉ Done.

## 6. Tiêu chí nghiệm thu

Chỉ phủ phần D4 · H1 · Z1 · Q8 (2026-10-02); các luật khác của file này chưa có AC.
Mẻ mẫu **M** = 8 HEIC 24MP, mỗi ảnh 6,0 MB đã index, preset 2048px, Quality 80%, ước lượng mỗi bản copy 0,9 MB.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | (D4) mẻ M, Delete Originals bật như mặc định | mở Resize trên iPhone 402×874 | nút chính đọc *Resize 8 Photos and Delete Originals*, không bị cắt chữ; chữ đen trên amber | ⚠️ chưa có — `Tools/ui-drive` dump nhãn nút |
| AC-2 | (D4) như AC-1 | gạt Delete Originals tắt | nút đổi ngay thành *Resize 8 Photos*; một ảnh thì *Save to Photos* | ⚠️ chưa có |
| AC-3 | (D4) mẻ M, Delete Originals bật | chạy, chạm Delete ở hộp của Photos | không có summary; màn Resize vẫn mở với toast 3 s *8 saved · 41 MB freed · Originals in Recently Deleted* và hai nút Share 8 Photos + Done; 8 bản gốc nằm trong Recently Deleted | ⚠️ chưa có — cần script `resize-clean-run.json` + `Tools/sim-shot` bắn trong 3 s |
| AC-4 | (D4) mẻ M, Delete Originals tắt | chạy xong | toast *8 saved to Photos*, không có cụm *freed*; 8 bản gốc còn trong thư viện | ⚠️ chưa có |
| AC-5 | (D4) mẻ M, Delete Originals bật | chạy, chạm Don't Allow ở hộp của Photos | summary ghi 8 saved và bản gốc không bị xoá; có Share 8 Photos + Done, không có toast *freed* | ⚠️ chưa có |
| AC-6 | (D4) 1 JPEG 0,4 MB, preset 4K (phóng to, bản copy 2,1 MB), Delete Originals bật | chạy xong | toast *1 saved · Originals in Recently Deleted*, không có số MB âm | ⚠️ chưa có |
| AC-7 | (H1) lượt chạy sạch của AC-3, sau khi toast đã tắt | chạm Share 8 Photos | share sheet mở với đúng 8 file là 8 bản copy mới (tên `_SHOTDEX_COMPRESSED_N`), không file nào là bản gốc; đóng share sheet thì màn Resize vẫn mở | ⚠️ chưa có |
| AC-8 | (H1) mẻ M, 2 ảnh lỗi (RAW iOS không đọc được) | chạy xong | summary có Share 6 Photos; share sheet nhận 6 file | ⚠️ chưa có |
| AC-9 | (H1) mẻ M đang chạy ở ảnh 4/8 | chạm Cancel → Cancel Export and Remove Copies | summary chỉ có Done, không có nút Share; 0 bản copy còn trong thư viện | ⚠️ chưa có |
| AC-10 | (H1) quyền `.limited`, mẻ 3 ảnh trong vùng được chọn | chạy xong, chạm Share 3 Photos | share sheet nhận 3 bản copy | ⚠️ chưa có |
| AC-11 | (Z1) iPad 13" ngang 1376×1032 và Duo trong 951×669, mẻ M | mở Resize | hai pane: preview trái, cột phải rộng 400pt; mép dưới nút chính ≤ mép trên vùng an toàn đáy, không cuộn | ⚠️ chưa có — `Tools/ui-drive` dump + `Tools/sim-shot inner` cho Duo |
| AC-12 | (Z1) iPhone 402×874 và Duo ngoài 466×678, mẻ M | mở Resize, chưa cuộn | một cột; nút chính nằm trọn trên home indicator; cuộn tới cuối thì mục Delete Originals không bị nút che | ⚠️ chưa có |
| AC-13 | (Z1) iPad 13" dọc 1032×1376, và Split View 1/2 688pt | mở Resize | một cột form ≤ 700pt căn giữa, nút ghim đáy — không phải hai pane | ⚠️ chưa có |
| AC-14 | (Z1) Duo trong, Resize đang mở hai pane | gập sang Duo ngoài | còn một cột, nút ghim đáy, preset và Quality đã chọn không đổi | ⚠️ chưa có — simctl không có lệnh gập, chụp tay |
| AC-15 | (Q8) VoiceOver bật, Settings → Export → Resize Presets → sửa một preset 80% | đưa con trỏ tới slider Quality | VoiceOver đọc *Quality, 80%* | ⚠️ chưa có — `Tools/ui-drive` dump nhãn slider = Quality |
| AC-16 | (D4, K25) lượt chạy sạch của AC-3, Share 8 Photos + Done đang hiện | chạm Done | màn Resize đóng, về lưới nơi mở nó; không còn toast hay nút Share nào | ⚠️ chưa có |

Mọi AC Z1 và H1 chạy trên cả iOS 26.5 và 18.6.
