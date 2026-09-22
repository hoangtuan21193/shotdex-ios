# FS-05 — Markup

`FS-05` · tier D · `Features/Editing/EditorTextPanel.swift` · `EditorDrawingCanvas.swift`
· `ShotDexKit` (render overlay và nét vẽ) · `Domain/Editing/TextOverlayLayout.swift` · cập nhật 2026-09-22

**Một câu:** đặt chữ, ảnh, hình và nét vẽ lên trên ảnh — và **token EXIF** là lý do tab này thuộc về **app
này** chứ không phải một app markup bất kỳ.

## Các phần

| # | Phần | Trả lời |
|---|---|---|
| 01 | [Bốn loại lớp và Draw](01-layers-and-draw.md) | chữ · ảnh · hình · kính lúp · lớp vẽ tay |
| 02 | [Chữ, token và kiểu](02-text-tokens-and-styling.md) | token EXIF, gõ trên ảnh, font, màu, toán đặt chữ |
| 03 | [Cử chỉ, render và preset](03-canvas-gestures-and-render.md) | bản vẽ sống trên ảnh, một/hai ngón, thứ tự render, lưu preset |

## Quy tắc

- **Công thức giữ mẫu chữ, còn renderer nhận chuỗi đã thay giá trị.** Có **một** chỗ duy nhất làm phép thay
  đó, và mọi đường render đều đi qua nó; công thức lưu vào ảnh vẫn là `{camera}`. Vì thế lệnh lưu nhận **hai
  công thức**: một để gắn vào ảnh, một để vẽ pixel.
- **Một bộ toán hình học, ba nơi dùng**: renderer nướng pixel, bản vẽ sống trên ảnh, và test. Bản vẽ sống
  lệch dù chỉ một chút thì chữ sẽ **nhảy** đúng lúc bỏ chọn và bản nướng tiếp quản.
- **Hình học theo cùng quy ước với nét cọ**: tâm tính theo tỉ lệ của ảnh **sau khi cắt**, còn kích thước là
  phần trăm **cạnh ngắn** — nên một lớp hiện y hệt ở bản xem trước 768px và ở bản xuất đầy đủ.
- **Không nâng phiên bản công thức**; khối markup bỏ hẳn khi rỗng, mọi khoá đều tuỳ chọn, và chỉ ghi phần
  **khác mặc định của loại lớp đó**.
- **Cử chỉ trên lớp markup không được chạy vòng render** — xem [03](03-canvas-gestures-and-render.md).

## Bốn loại lớp + một lớp vẽ

| Loại | Nội dung |
|---|---|
| **chữ** | nội dung, font bất kỳ đang cài, cỡ, màu, độ mờ, viền, bóng, nhiều dòng + căn lề, xoay, vị trí |
| **ảnh** | một ảnh PNG trong suốt chọn từ thư viện, có độ mờ, cỡ, xoay, vị trí |
| **hình** | chữ nhật · elip · bong bóng thoại · mũi tên · đường thẳng |
| **kính lúp** | vòng tròn phóng chính ảnh bên dưới |
| **nét vẽ** | một lớp vẽ tay, ghép **dưới** mọi lớp khác |

Tab tên **Markup** (cũ là "Text") — nó thêm được cả ảnh và nét vẽ, không chỉ chữ.

## Model

**Một** kiểu dữ liệu lớp + một nhãn loại, không phải một kiểu liệt kê hai dạng dữ liệu: danh sách xử lý hai
loại như một, và thêm một trường là một dòng.

- Hình dùng **bề ngang** (phần của cạnh ngắn) cộng **tỉ lệ cao trên rộng**, nên một con số mô tả được hộp
  tỉ lệ bất kỳ; độ dày nét cũng theo cạnh ngắn nên hình giữ tỉ lệ khi đổi cỡ.
- Bề rộng tối đa của khối chữ tính theo **chiều ngang** — giới hạn xuống dòng là "chạy ngang được bao xa".
- Nét vẽ lưu ở **dạng vector** kèm kích thước khung lúc vẽ, không phải ảnh bẹt: mở lại vẽ tiếp được, và
  renderer vẽ **sắc ở đúng độ phân giải xuất**.

## Panel — danh sách lớp

- Đầu danh sách là **bốn nút thêm rời nhau**: ＋Text · ＋Image · ＋Shape · ＋Draw, mỗi nút một dấu `+` accent.
  Cố ý **không** phải một dải chọn chế độ — dải liền đọc thành "đang chọn chế độ nào", trong khi mỗi lần
  chạm thực ra **tạo** một lớp. **＋Shape là một menu**: 5 kiểu + kính lúp = 7 mục tiêu trên hàng 375pt thì
  quá chật.
- **Presets** tách riêng ở tiêu đề danh sách — nó mở thư viện preset chứ không thêm lớp.
- Mỗi dòng là một **thẻ**: tay nắm kéo bên trái, ô icon, tên + mô tả phụ, **con mắt** và mũi tên bên phải.
- **Chạm thẻ = mở phần chi tiết** · con mắt = ẩn/hiện (theo id nên không đổi lớp đang chọn) · **vuốt trái =
  xoá** · **giữ rồi kéo = đổi thứ tự** (không dùng menu giữ-lâu vì nó xung đột với kéo).
- Dòng đặt tên bằng **chữ đã thay giá trị**; lớp ảnh mất file thì mô tả phụ ghi **"Missing file"**.
- Lớp vẽ cũng là một dòng (dưới cùng, không kéo được).
- Danh sách hiển thị **ngược** với thứ tự vẽ, vì renderer vẽ từ dưới lên.

## Chi tiết một lớp — thứ tự mục

**TEXT** (nội dung → mở ô gõ trên ảnh · font → sheet · **một hàng** gộp đậm/nghiêng và căn lề) → **FILL**
(màu, cỡ, độ mờ) → **OUTLINE & SHADOW** (chung một mục vì cùng tồn tại cho một lý do: chữ trắng trên trời
sáng) → **LAYOUT** (bề rộng, giãn dòng, giãn chữ) → **PLACEMENT** (xoay, dịch ngang, dịch dọc, đổi thứ tự).

Mọi slider lưu dạng phân số nhưng hiển thị ra phần trăm.

## Lịch sử

"Added Text" · "Added Image" · "Applied Preset" · "Deleted Text" · "Reordered Layers"; một lớp đổi thì đặt
tên theo **chữ của chính nó** ("Shot on Canon · Color") — một lịch sử toàn bước "Text" thì không đọc được
trên ảnh có ba dòng chữ. Nét vẽ có nhãn riêng.

Font và màu vừa dùng là **trạng thái của công cụ** (lớp mới thừa hưởng), không phải một chỉnh sửa của ảnh.

## Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
