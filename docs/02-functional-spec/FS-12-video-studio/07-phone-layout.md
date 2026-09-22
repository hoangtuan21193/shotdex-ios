# FS-12.07 — Bố cục trên điện thoại

`FS-12.07` · `Features/VideoStudio/` (top band, timeline, transport) · `Domain/Video/TimelineLaneLayout.swift`
· cập nhật 2026-09-22

**Một câu:** **điện thoại có đủ mọi chức năng của iPad** — chỉ hình dạng và đường vào là khác.

## 1. Quy tắc

- Mọi công cụ toàn cục dựng từ **một danh sách duy nhất**, dùng chung với desk chrome — thêm một công cụ là
  cả hai bên cùng có.
- **Playhead cố định giữa vùng lane**; timeline cuộn dưới nó.
- Cột glyph bên trái **không được nhận chạm** — bất cứ thứ gì nhận chạm ở đó nuốt luôn cú kéo dọc để lộ lane.
- Cử chỉ trên timeline đi qua UIKit: cử chỉ SwiftUI **chết** trong nội dung host bên trong một scroll view.

## 2. Ba tầng

`hàng lệnh nổi` → `preview 221` → `transport 40/44` → `timeline 248` → `toolbar 62` → `bottom bar 50`.

- **Hàng lệnh nổi hai bên đảo**: trái là Undo · Redo · **giữ-để-xem-bản-gốc**; phải là ô đọc `1080p · 30`
  (chạm mở cài đặt xuất) + ⋯. Không còn nút chữ Cancel/Export.
- "Xem bản gốc" **tước look** (filter, adjustments, overlay) ở tầng rẻ nhất, thả tay là khôi phục —
  **không đụng recipe**.
- **Preview** nền đen, nút play tròn 56 ở giữa khi dừng; nội dung fit trong vùng.
- **Transport**: play · `0:03.0 / 0:06.0` · **vừa khung**. Không có nút zoom — pinch để zoom.

## 3. Timeline lane động

- **Cuộn ngang = scrub** (haptic mỗi giây) · **cuộn dọc = lộ lane khuất** (khoá hướng để kéo chéo không làm
  cả hai) · **pinch = zoom** (mặc định 55pt/giây, dải 20–160) · phát thì tự trôi.
- Thước thời gian **nằm ngoài vùng cuộn** nên đứng yên khi cuộn dọc. Cột glyph **trôi theo offset dọc** của
  chồng lane.
- Chiều cao nội dung là **hằng số tự tính**; ghim vào khung nhìn sẽ **cắt mất lane thứ 5** thay vì cho cuộn.
- **Xếp lane tự động kiểu CapCut** (thuần, có test): chia khoảng tham lam, sắp theo `(bắt đầu, kết thúc,
  id)` nên **kết quả chỉ phụ thuộc tập item, không phụ thuộc thứ tự mảng** — lane không nhảy khi recipe đổi
  thứ tự.
  - Overlay (chữ **và** sticker) xếp **trên** lane video, nhạc xếp **dưới**; item trùng thời gian đẩy xuống
    lane mới, **không giới hạn số lane**; hai cửa sổ chạm nhau thì dùng chung lane.
  - Chiều cao: overlay 34 · video 66 · nhạc 40.
  - **Lane Bộ lọc đã bỏ** — filter vốn áp toàn video, giờ là công cụ toàn cục. Kéo dọc để đổi lane thủ công
    **chưa làm**.
- Băng nhạc vẽ **dạng sóng thật cắt theo trim**, cache **theo file** nên hai track cùng bài chỉ decode một
  lần. Băng overlay có **nhãn dính mép trái** khi băng bắt đầu ngoài vùng nhìn.
- Lane rỗng = nút gạch đứt `+ Text` / `+ Music`; cuối lane Video là nút `+`; ô chuyển cảnh 22×22 giữa hai clip.
- **Trim đầu nhạc dời hai giá trị trong một bước undo** để phần đuôi không xê dịch.
- Trim clip vẫn đi qua slider Duration, **không** có tay nắm trên clip.

## 4. Overlay chỉnh trực tiếp trên preview

- Chữ và sticker vẽ **live trên player**, và **preview không bake overlay** (export thì có). Nhờ vậy sửa
  overlay chỉ đổi recipe và vẽ lại lớp phủ — **không dựng lại bản dựng khung hình**, nên không giật, không
  bóng ma.
- Cử chỉ giống photo editor: **một ngón chạm chọn + kéo dời** (ngưỡng 4pt, snap tâm + haptic + đường gióng),
  **hai ngón pinch scale + xoay** (mốc 45°). Một cử chỉ = một bước undo. Chạm vùng trống = bỏ chọn.
- Nhiều chữ/sticker cùng lúc; thứ tự mảng là thứ tự lớp.

## 5. Bốn thứ trước đây chỉ desk mới có

| Thứ | Đường trên điện thoại |
|---|---|
| **Transport đầy đủ** | hàng hẹp 40pt dưới khung: bốn nút bước hình nằm ngoài (đầu · lùi 1 khung · tiến 1 khung · cuối) vì đó là thứ bấm lặp lại; timecode ở giữa **không bao giờ bị cắt**; còn lại vào menu tràn ⋯ (Split · Freeze · Trim to Playhead · marker · Loop · **Snap to Edits** · Fit Timeline · **Tracks** · Delete Clip) |
| **Snap to Edits** | lần đầu có UI — trước đó là thuộc tính mặc định bật, không chỗ nào tắt được, trên **cả hai** loại máy |
| **Lock / Mute từng track** | submenu **Tracks** trong menu tràn, một mục con mỗi lane, đặt tên bằng đúng badge của track header (`V1 · Video`, `A1 · Music`) — vì cột glyph của phone không được nhận chạm |
| **Preview filter thật** | ô 62pt + tên, dùng chung renderer với tab Effects của pool |
| **Đồng hồ đo mức** | thanh nằm ngang ở đầu panel Volume, cùng thang dB và cùng ngưỡng với cột meter của desk — chỉ đổi trục |

- **Không có nút play trong hàng transport**: khung hình đã có nút play 56pt khi dừng, chạm vào khung là
  pause — hai nút play trong 375pt là thừa một.
- **Hàng hẹp này cũng dùng trên desk khi sân khấu bị bóp** (ngưỡng 780pt): iPad 13" mở **cả** media pool
  **lẫn** inspector thì sân khấu còn 756pt, trong khi hàng desk đủ 16 nút cần 780 — một nút bị đẩy hẳn ra
  ngoài mép. Duo màn trong cũng rơi vào diện này ngay khi mở pool.
- Có test tính vừa máy nhỏ nhất còn chạy iOS 17.

## 6. Bug đã sửa đáng ghi

Hàng công cụ của điện thoại từng được **viết tay** nên thiếu mục **Color**, trong khi menu của desk sinh từ
danh sách đầy đủ. Kết quả: **toàn bộ tầng màu — de-log, primaries, curve, color mixer, LUT, power window và
cả scope — không có đường nào mở được trên iPhone.**

Nay hai bên cùng một nguồn, và test **duyệt danh sách chứ không đếm số**, nên lần sau thêm công cụ mà quên
một hàng là đỏ ngay.

## 7. Tiêu chí nghiệm thu

Xem [README](README.md).
