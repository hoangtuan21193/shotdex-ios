# FS-05.02 — Chữ, token và kiểu

`FS-05.02` · `Domain/Editing/OverlayTokenResolver.swift` · `TextOverlayLayout.swift`
· `Features/Editing/EditorInlineTextEditor.swift` · cập nhật 2026-09-24

**Một câu:** token EXIF thay giá trị theo từng ảnh, gõ chữ ngay trên ảnh, và toán đặt chữ nằm ở **một** hàm.

## 1. Quy tắc

- Giá trị token lấy từ **metadata đã index** (đã qua chuẩn hoá tên máy) — **không** đọc lại EXIF.
- Cụm nào mà **mọi** token trong đó đều rỗng thì **bỏ cả cụm**, kể cả chữ dẫn nhập.
- Khi giải font phải **kiểm tra lại tên**: hệ thống không báo lỗi, nó **âm thầm trả về một font khác**.
- **Không dùng ô chọn màu của hệ thống** — sheet của nó che đúng tấm ảnh đang cần soi để chọn màu.

## 2. Token EXIF

Chữ chứa được `{camera}` `{lens}` `{focal}` `{aperture}` `{shutter}` `{iso}` `{date}` `{filename}`, và giá
trị được thay **theo từng ảnh lúc render** — nên một preset đã lưu đọc ra "Shot on Canon EOS R6 · 85mm ·
f/1.2" trên mọi ảnh nó được dán vào.

Phần khó không phải thay chữ, mà là **ảnh thiếu giá trị**:

| Luật | Chi tiết |
|---|---|
| Cắt cụm theo dấu phân cách **trước** | thay ngây thơ sẽ ra "Canon EOS R6 ·  · 85mm" trên ảnh không có tag ống kính |
| Cụm rỗng → bỏ cả cụm | "Shot on {camera}" mất luôn chữ "Shot on" |
| Dấu phân cách luôn đúng | `·` `•` `\|` `,` |
| Dấu có điều kiện | `-` `–` `—` `/` **chỉ khi có khoảng trắng hai bên**, để "1/500" hay "sun-drenched" không bị cắt |
| Token lạ | giữ nguyên như chữ thường |
| Dòng không có token | đi thẳng qua — dòng trắng người dùng cố ý gõ vẫn còn |
| Dòng thay xong ra rỗng | mất hẳn |

## 3. Gõ chữ ngay trên ảnh

Kiểu Snapseed — **không** phải một sheet trượt từ dưới che mất ảnh.

- ＋Text tạo một lớp rỗng rồi mở luôn ô gõ; mục nội dung trong phần chi tiết cũng mở ô này.
- Một lớp phủ toàn khung: ảnh **mờ đi** phía sau, ô nhập lớn căn giữa (căn lề theo đúng lớp đang sửa), bàn
  phím bật sẵn.
- **Cancel · Done** ngang tai thỏ, giống hàng trên của chế độ vẽ.
- Dải **chip token** ghim ngay trên bàn phím; khi chuỗi có token thì có dòng xem trước "ON THIS PHOTO" hiện
  giá trị thật.
- Xác nhận thì ghi vào lớp và đóng ô (một bước hoàn tác). **Huỷ một lớp vừa tạo mà chưa gõ gì thì bỏ luôn
  lớp**, để danh sách không còn một dòng "Empty text".

## 4. Toán đặt chữ — một hàm, ba chỗ dùng

Viết bằng thư viện chữ và đồ hoạ nền, **không dùng UIKit** — nếu không, nó sẽ nằm sau UIKit và renderer
trong framework dùng chung không gọi được.

- Một hàm quy đổi giữa cỡ trong công thức và cỡ pixel thật.
- Phép đặt chữ đưa tâm khối chữ lên điểm neo rồi **xoay quanh chính điểm neo đó** — xoay quanh góc hộp thì
  kéo một lớp đã nghiêng sẽ trượt khỏi chỗ người dùng đặt.
- Góc phải **lấy dấu âm** vì hệ toạ độ vẽ ngược chiều: số độ dương phải đọc là **chiều kim đồng hồ trên màn
  hình**, đúng chiều tay nắm xoay.
- Viền chữ dùng độ dày **âm** (dương sẽ ra chữ rỗng ruột); bóng không phải thuộc tính của chữ nên đi qua lớp
  đồ hoạ với độ lệch dọc âm.

## 5. Font

- Công thức lưu **tên PostScript + họ font**; ô chọn trả về một họ thì phải giải ra một kiểu chữ cụ thể
  trước khi lưu.
- Khi giải font, so **ngược lại tên thật** của font vừa nhận; thiếu kiểu chữ thì lùi về **cùng họ** trước
  khi lùi về font hệ thống, và báo ra để panel gắn nhãn **"Unavailable"**. Công thức sống lâu hơn máy đã tạo
  ra nó; font đổi thầm mà không nói là thứ tệ nhất.
- Dùng **ô chọn font của hệ thống**, không phải một danh sách tự dựng: nó tìm kiếm được, xem trước mỗi kiểu
  chữ bằng chính typeface đó, nhận cả font do app khác cài và font tải về, và không phải bảo trì khi hệ
  thống ship họ font mới.
- Có hàng **RECENT** (6 kiểu chữ): với cả danh sách font của máy, **tìm lại đúng kiểu chữ cho ảnh sau** mới
  là phần chậm, không phải chọn lần đầu.

## 6. Màu

Hàng màu 40pt: 6 ô màu · vạch ngăn · ô **custom** (vòng hue, lõi là màu custom hiện tại).

- Chạm ô custom: vùng thông số đổi thành bảng màu **ngay trong panel, panel không đổi chiều cao** — hàng đầu
  `‹ · Color · mã hex · ống hút`, hàng **Recent** (6 màu, chỉ sống trong phiên sửa), rồi ba slider **Hue ·
  Saturation · Brightness** có rãnh màu. Bảng này miễn lưới 40pt (36 · 32 · 36×3). `‹` quay lại.
- Ống hút lấy màu từ **chính tấm ảnh đang sửa**.
- 6 ô màu giữ bộ hôm nay: **4 mức xám + 2 màu** — màu hay dùng cho watermark.

## 7. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
