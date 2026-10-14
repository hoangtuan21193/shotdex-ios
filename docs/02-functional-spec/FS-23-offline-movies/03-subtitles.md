# FS-23.03 — Phụ đề

`FS-23.03` · tier A (bảng) trên player · board `PH_MovieSubtitles` (4/5), `PH_MovieSubtitleAdd` (Share › chọn phim) — chưa vẽ
· cập nhật 2026-10-14

**Một câu:** mỗi phim có một danh sách phụ đề (trong file, nhập tay, tải về, dịch ra); người dùng đặt một cái làm
**chính**, một cái làm **phụ**, chọn vị trí, cỡ, màu, lệch giờ.

## 1. Phụ đề của một phim đến từ đâu

| Nguồn | Nhãn trong danh sách | Ai vẽ |
|---|---|---|
| track chữ trong file (MKV, MP4) | `English · In File` | ShotDex, nếu trích được (§3) |
| track ảnh trong file (PGS, VobSub) | `English · In File (Image)` | VLCKit |
| file cạnh phim lúc chép (01 §3) | `English · From Server` / `From Files` | ShotDex |
| Import File… (Files: srt, ass, ssa, vtt, zip) | `English · Imported` | ShotDex |
| Share sheet / AirDrop (§5) | `English · Shared` | ShotDex |
| dịch bằng AI (04) | `Tiếng Việt · Translated (Claude)` | ShotDex |

## 2. Bảng phụ đề

Là phần dưới của bảng **Audio & Subtitles** (02 §3b) — máy ngang: bảng bên phải 372pt, phim vẫn chạy và phụ đề dồn
vào phần hình còn thấy; máy dọc: sheet nửa màn.

- Hai dòng **Primary** và **Secondary**, mỗi dòng một menu: Off · mọi phụ đề ở §1. Secondary mặc định Off.
- Menu của dòng Secondary có thêm **Translate…** (04, mờ khi chưa có phụ đề chữ nào) và **Import File…** (§5) —
  không còn hai nút riêng.
- **Position** (chỉ hiện khi Secondary bật): `Primary Bottom, Secondary Top` · `Both Bottom, Secondary Above`
  *(mặc định)* · `Both Bottom, Secondary Below`.
- Mỗi dòng có **Size** (50–200%, mặc định chính 100%, phụ 85%), **Color** (White · Yellow · Light Gray · Cyan;
  mặc định chính White, phụ Yellow), **Sync** (−10,0…+10,0 s, bước 0,1 s, thay đổi thấy ngay).
- Phụ đề chính, phụ, vị trí, cỡ, màu, lệch giờ **nhớ theo từng phim**; cỡ/màu/vị trí mới nhất thành mặc định cho
  phim mới.
- Phim mới: Primary tự chọn phụ đề có ngôn ngữ đầu tiên trong **Subtitle Languages** (Settings › Playback, mặc định
  ngôn ngữ máy + English); không có → Off.
- Màu phụ đề là **lựa chọn nội dung**, không phải token giao diện: 4 màu cố định, ghi vào DESIGN.md mục player.

## 3. Định dạng và giới hạn

- Chữ: SRT, ASS/SSA, WebVTT. Giữ nghiêng, đậm, xuống dòng; bỏ hiệu ứng, font, toạ độ của ASS — trừ dòng ASS
  đặt ở đỉnh khung thì giữ ở đỉnh.
- Mã chữ tự nhận (UTF-8, UTF-16, Windows-1258, Windows-1252, GB18030, Shift-JIS…); sai thì ⋯ › **Encoding** chọn
  tay, nhớ theo phụ đề.
- **Track chữ trong file** (người dùng chốt 14/10): phim **trên máy** (đã Download hoặc chép thẳng) → trích ra file
  phụ đề ngay khi tải xong, dùng được làm Primary, Secondary và để dịch. Phim **đang stream** → không trích (phải đọc
  cả file qua mạng); track đó do VLCKit vẽ, chỉ làm được Primary, không đôi, không dịch — menu ghi `In File (Download
  to use as Secondary or translate)`.
- **Track ảnh** (PGS, VobSub): VLCKit vẽ, đúng chỗ file đặt, không đổi cỡ/màu; chỉ làm được Primary, Secondary vẫn
  là phụ đề chữ của ShotDex. Không dịch được (cần OCR — ngoài phạm vi).

## 4. Vẽ

- Đặt theo **khung phim**, không theo màn: Fit thì nằm trong khung, Fill thì trong phần nhìn thấy. Bề rộng tối đa
  90% khung; cỡ 100% = chữ cao 5% chiều cao khung.
- Chữ có viền tối 2 px + bóng, không nền — đọc được trên cả cảnh trắng.
- Hai phụ đề cùng đáy: cách nhau 8 pt, không bao giờ đè nhau; chrome đang hiện thì cụm đáy nâng lên trên kính
  transport, chrome ẩn thì hạ về.
- Cue chồng giờ trong cùng một phụ đề: hiện cả hai, cue sau ở trên.

## 5. Đưa phụ đề vào

Người dùng tự tìm và tải phụ đề (trang phụ đề trên web, app khác) rồi đưa vào ShotDex; **ShotDex không tìm
phụ đề trên mạng** (§6).

| Lối | Cách |
|---|---|
| cạnh phim lúc chép | tự động (01 §3) |
| Import File… trong bảng phụ đề | bảng chọn tài liệu của hệ thống: srt, ass, ssa, vtt, zip; chọn nhiều; gắn vào phim đang mở |
| Share sheet / AirDrop | app khai các loại file phụ đề; nhận file → sheet `Add Subtitle to…` liệt kê phim (phim vừa xem đứng đầu, phim có tên khớp tên file được đánh dấu) → chọn một |

- Zip: lấy mọi file phụ đề bên trong, bỏ file khác; zip không có phụ đề nào → `No subtitles in this file.`
- Ngôn ngữ: đọc từ đuôi tên (`.en`, `.vi`, `.vie`, `English`); không có thì đoán từ nội dung; sai thì ⋯ ›
  **Language** sửa tay.
- File không đọc được → `ShotDex can't read this subtitle file.`; không gắn gì.
- Cùng nội dung đã gắn vào phim đó → không thêm lần hai.

## 6. Không tìm phụ đề trên mạng

Người dùng chốt 2026-10-14 ở bước spec: bỏ. *Vì:* mọi nguồn có API (OpenSubtitles, SubDL) chỉ cho dùng không đăng
nhập khi app trả phí hằng tháng; không trả phí thì mỗi người phải tự đăng nhập — cả hai đều bị từ chối.
