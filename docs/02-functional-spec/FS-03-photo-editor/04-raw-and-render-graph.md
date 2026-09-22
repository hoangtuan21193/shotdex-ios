# FS-03.04 — RAW và render graph

`FS-03.04` · `ShotDexKit/PhotoRenderService.swift` · cập nhật 2026-09-22

**Một câu:** một renderer chung cho preview, lưu, nén và ước lượng — và preview **không bao giờ hạ độ
phân giải** để chạy cho mượt.

## 1. Quy tắc

- **Không hạ độ phân giải khi đang kéo.** Mục đích của live preview là *nhìn để quyết định*; ảnh mềm đi là
  mất đúng cái đó.
- Độ mượt đến từ **tần số, không từ độ phân giải**: recipe nặng vẽ **ít frame mỗi giây**, không vẽ ảnh nhỏ
  hơn.
- Kích thước render **đóng băng suốt một cú kéo** — đổi size giữa chừng là resample khác, ở 800% đọc ra
  thành ảnh rung.
- Không decode lại nguồn ở từng sự kiện: giữ một bản preview đã decode trong bộ nhớ và chạy lại graph từ đó.
- Nguồn không decode/render/encode được thì **giữ phiên và báo lỗi**, không tạo asset rỗng.

## 2. RAW

- Nhận theo UTI RAW và **chỉ cho sửa khi decode được trên chính thiết bị đó**; không thì báo rõ format
  không được hỗ trợ.
- Asset RAW+JPEG đưa picker chọn RAW hay JPEG làm nguồn.
- Nguồn RAW mở thêm bốn thứ trong Adjust: **White Balance · Noise Reduction (luminance + color) · RAW
  Sharpening · Lens Correction**. Không phải RAW thì bốn mục này **không hiện**.
- Bốn thứ đó đi qua decoder RAW; phần còn lại dùng graph chung.
- Output giữ color profile gốc tốt nhất có thể (Display P3 / Adobe RGB / sRGB). **Không có picker color
  space.**

## 3. Preview

| Lúc nào | Kích thước render |
|---|---|
| Đang kéo slider / crop / mask | **đúng kích thước ảnh đang hiển thị** × scale màn |
| Điều chỉnh RAW (đổi chính bản decode) | bản nháp 768px, trần cứng riêng |
| Vừa thả tay | render lại **2400px** |
| Save | full resolution |

- 1024px cố định của bản cũ **thấp hơn** kích thước hiển thị của mọi điện thoại hiện đại — nên mỗi cú kéo
  trông như ảnh bị giảm độ phân giải rồi nét lại lúc thả tay.
- Thay đổi rời rạc dùng debounce/latest-wins; kéo liên tục dùng vòng render chỉ giữ recipe mới nhất.
- **Histogram lấy mẫu 256px ngoài render path**, dùng percentile clipping + perceptual scaling để vùng
  shadow/midtone vẫn đọc được khi ảnh có một peak trắng lớn.

## 4. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
