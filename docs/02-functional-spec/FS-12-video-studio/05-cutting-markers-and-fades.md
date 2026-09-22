# FS-12.05 — Cắt, marker, snapping và fade

`FS-12.05` · `Domain/Video/VideoTimelineMath.swift` · `VideoTransitionSheet` · cập nhật 2026-09-22

**Một câu:** những thao tác của một trang cắt thật — và chỗ nào cần nam châm thì mới đặt nam châm.

## 1. Quy tắc

- **Slider không được hứa cái timeline không cấp.**
- Marker ghim vào **thước thời gian**, không ghim vào clip.
- **Fade khác transition**: transition là thoả thuận giữa hai clip hàng xóm; fade là việc riêng của một clip.
- Marker **không bao giờ tới compositor** — nó là thứ người dựng nhìn, không phải thứ bản xuất ghi ra.

## 2. Độ dài transition

Là **sheet**, không phải dialog: chip các kiểu + slider Duration + **Apply to All** + một dòng nói
**timeline thật sự cấp bao nhiêu**.

- Độ dài transition tồn tại từ đầu mà **không UI nào chỉnh được** — dialog cũ chỉ chọn kiểu, và một dialog
  không chứa nổi slider. Trên iOS 26 nó còn vẽ thành popover và **giấu mất nút huỷ**
  ([BD-04](../../01-basic-design/BD-04-design-language.md)).
- Độ chồng lấn bị chặn ở **nửa clip ngắn hơn**, nên slider hứa 2s trên clip 0,6s là slider nói dối — dòng
  thông tin kia nói con số thật.

## 3. Trim to Playhead

**Trim Start / End to Playhead**, đặt bên trái hàng transport.

Thao tác cắt hay dùng nhất không phải "đặt hai đầu" mà là **"bỏ đoạn lấy đà"** hoặc **"bỏ đuôi"**.

Ảnh tĩnh thì dời thời lượng; video thì dời cửa sổ trim, **quy đổi qua tốc độ clip** — thời gian cục bộ chạy
theo tốc độ còn cửa sổ trim thì không.

## 4. Marker

Thời điểm + màu (bảng **5 màu cố định**) + ghi chú.

- **Ghim vào thước, không vào clip** — cắt một shot không được kéo theo mọi ghi chú.
- Chấm trên dải tổng quan, chạm để nhảy tới. Transport có add / prev / next.
- Nút add **đổi thành "đổi màu"** khi playhead đã nằm trên một marker (dung sai 0,5s), thay vì chồng hai
  chấm lên một pixel.

## 5. Snapping

Kéo nhạc hoặc caption thì dính vào mép clip, marker, playhead và hai đầu project. Ngưỡng **8pt ngón tay**
quy ra giây theo mức zoom hiện tại, nên cảm giác như nhau ở mọi mức phóng.

**Vì sao không có "khép khoảng trống khi xoá clip"**: lane video ở đây **không thể có khoảng trống** — clip
xếp nối đuôi theo thời lượng, xoá một cái là tự khép. Thứ nằm tự do được là nhạc và caption, nên đó mới là
chỗ cần nam châm.

## 6. Fade hai đầu clip

- Kẹp ở **nửa clip mỗi đầu** để hai fade không bao giờ cắt nhau và để lại một shot không bao giờ hiện đủ.
- Clip đang chọn vẽ nêm mờ + nút tròn để kéo.
- Đi cùng đường "recipe tươi" với hiệu ứng theo clip (kéo nút **không** dựng lại composition), và **áp
  sau** hiệu ứng: fade một khung đã blur là đúng, blur một khung đã fade là sai.

## 7. Preview look thật

Tab Effects từng hiện 49 look bằng **49 glyph giống hệt nhau**. Nay render đúng khung dưới playhead qua
từng filter, cỡ ô, ở mức ưu tiên nền, cache tới khi playhead sang clip khác.

## 8. Tiêu chí nghiệm thu

Xem [README](README.md).
