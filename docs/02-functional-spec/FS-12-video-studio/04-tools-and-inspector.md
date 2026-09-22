# FS-12.04 — Bộ công cụ và inspector

`FS-12.04` · `Features/VideoStudio/` (media pool, top band, inspector) · cập nhật 2026-09-22

**Một câu:** thứ **chèn vào** lấy từ thư viện, thứ **chỉnh** nằm trong inspector — và ranh giới đó là lý do
cột công cụ dọc bị bỏ.

## 1. Quy tắc

- **Không có cột công cụ dọc trên desk window**, và cũng không có hàng công cụ ngang — nó chỉ là chính cái
  cột đó nằm xuống.
- **Chèn thì lấy từ thư viện; chỉnh thì mở inspector.** Rail cũ vẽ cả hai loại thành cùng một ô 62pt.
- **Inspector là cột nhường chỗ**: nó chỉ mở khi khung hình còn đủ rộng sau khi trừ các cột khác.
- Điện thoại **có đủ mọi công cụ** của desk, chỉ khác đường vào
  ([FS-12.07](07-phone-layout.md)).

## 2. Lệnh cũ đi đâu

| Lệnh cũ | Chỗ mới | Vì sao |
|---|---|---|
| **Add** | tab **Media** của pool + hàng **"Browse All Photos…"** | pool chỉ giữ 400 item gần nhất; bỏ ô Add mà không có hàng này là cắt đứt lối tới mọi thứ cũ hơn |
| **Sticker** | tab **Stickers** — cùng thư viện, lọc còn ảnh tĩnh, chèn ra **overlay** chứ không phải clip | rasterize giới hạn **1024px**: overlay vẽ đè ở một phần bề rộng, giữ PNG 48MP là bộ nhớ đổ vào pixel không ai thấy |
| **Music** | tab **Music** — nhạc đã nhập (sống qua phiên) + "Import from Files…" | catalog nhạc bundled rỗng có chủ đích |
| **Text** | tab **Text** — hàng "Add Text" rồi các font người dùng **thật sự đã dùng** | không có gallery title template để liệt kê, nên font gần đây là thứ có thật |
| **Filter** | tab **Effects** | cường độ vẫn là slider, và slider thuộc về inspector |
| **Ratio · Adjust · Volume · Background** | menu **Project Tools** ở top band | format và những thứ cùng loại thuộc về chrome, không thuộc cột công cụ |

**Không chép**: trang Color với node graph và scope của một NLE desktop — đó là đầu desktop-parity của nó,
sai chỗ cho một công cụ dành cho người chụp ảnh dựng clip ngắn.

## 3. Quick Adjust

Dải cao **44pt** ngay dưới khung hình: **Speed** cho clip, **Duration** cho ảnh, **Master** cho bản mix —
mỗi cái **bung slider tại chỗ**.

Nhờ vậy thao tác hay dùng nhất không phải mở panel 264pt đè lên chính cái timeline đang dùng để đánh giá
thay đổi.

Nằm sau một toggle trong viewer header và **mặc định tắt** — ảnh chụp lần đầu cho thấy để bật sẵn là ăn
thẳng 44pt của khung trên cửa sổ cao 669.

## 4. Chèn media ở đâu

Hai chế độ: **nối vào cuối**, hoặc **chèn tại playhead** (tách clip playhead đang nằm trong rồi thả media
vào đường cắt).

**Không có "đặt lên trên"** — nó cần một lane video thứ hai, mà ở đây một lane video chạy trên hai track
xen kẽ để hai clip kề nhau cùng tồn tại trong cửa sổ chuyển cảnh. Hai là con số một lane nói thật được.

## 5. Inspector

- Chỉ mở khi khung hình còn **≥ 400pt** sau khi trừ media pool và cột meter; có nút bật/tắt riêng trong
  viewer header.
- Pool và meter là thứ người dùng mở; inspector ép khung hình còn 200pt để bày điều khiển cho một clip
  người dùng **không còn nhìn thấy nữa** là cuộc đổi chác mà luật này sinh ra để từ chối.
- Năm băng của desk chrome lấy chiều cao **từ băng preview**, không lấy của timeline (có test) — timeline
  vốn chỉ nhận đúng phần lane cần.

## 6. Kết quả đo

Bỏ rail trả lại bề rộng cho khung hình: màn trong Duo **509 → 601pt**, iPad 13" ngang **934 → 1026pt**.

Compact width không đổi gì: điện thoại không có pool để dời lệnh chèn sang, nên giữ đủ 9 ô trong hàng ngang
và giữ bottom bar.

## 7. Tiêu chí nghiệm thu

Xem [README](README.md).
