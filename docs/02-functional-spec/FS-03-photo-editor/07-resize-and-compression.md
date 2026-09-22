# FS-03.07 — Resize

`FS-03.07` · `Features/Editing/CompressionScreen.swift` · `CompressionPresetStore` · cập nhật 2026-09-22

**Một câu:** thu nhỏ và nén ảnh, một tấm hoặc cả mẻ — và tên gọi phải giống nhau ở mọi lối vào.

## 1. Quy tắc

- **Tên hiển thị là "Resize", không phải "Compress"** ở mọi chỗ: nav title, nút bulk, alert lỗi, dòng
  trạng thái, và cả **Settings → Export → Resize Presets**. Lối vào ở hai menu đã tên là Resize; một màn
  tự đổi tên trên đường vào đọc như công cụ khác.
- **Màn không nhớ lựa chọn phiên trước.**
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

## 4. Màn hình

- **Form giới hạn 700pt và căn giữa ở regular width**: kéo segmented Format ra hết 1032pt của iPad thì ba
  chữ cách nhau cả gang tay. iPhone hẹp hơn mức trần nên không đổi gì.
- **Preview**: một ảnh thì kéo được điểm neo crop; nhiều ảnh thì thành **carousel vuốt ngang** để duyệt
  lại đúng các ảnh đã chọn, kèm pill `i / N`.
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
- Trong lúc chạy: **modal giữa màn hình** (scrim đen phủ kín, nuốt chạm) với spinner + thanh tiến độ +
  `Processing N of M`, mọi control dưới bị tắt. Bật Delete Originals thì modal đổi chữ thành
  *"Deleting originals…"* rồi mới đóng.
- **Cancel** dừng mẻ và xoá mọi bản copy đã tạo **trong chính mẻ đó**; xoá không hết thì summary báo lỗi
  thay vì tuyên bố đã rollback.
- **Chạy sạch thì bỏ qua màn summary**, đóng thẳng — summary chỉ hiện khi có việc cần báo (thất bại, huỷ,
  rơi về JPEG, lỗi xoá). Trên summary **không có nút Cancel**, chỉ Done.

## 6. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
