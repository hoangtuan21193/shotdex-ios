# FS-23.02 — Player

`FS-23.02` · tier C (chrome kính trên nền phim đen) · board `PH_MoviePlayer` (3/5) — chưa vẽ · cập nhật 2026-10-14

**Một câu:** phát phim toàn màn bằng VLCKit, cùng bộ từ và cùng transport với video trong Photos (FS-02.02), thêm
track âm thanh, phụ đề, chỗ đang xem.

## 1. Engine

- **VLCKit** cho mọi phim trong kho (intent câu 2). FS-02.02 §1 "không thêm thư viện player" thu lại thành luật
  cho **video trong Photos**; video trong Photos vẫn đi AVPlayer.
- Phụ đề **không để VLCKit vẽ**: ShotDex đọc phụ đề và tự vẽ lớp chữ khớp giờ của player (03 §4). Vì thế phụ đề
  đôi, vị trí, cỡ chữ làm được với mọi bản VLCKit. Ngoại lệ: phụ đề **dạng ảnh** (PGS, VobSub) chỉ VLCKit vẽ được,
  nên chỉ hiện được **một** và đúng chỗ file đặt (03 §3).
- Giải mã phần cứng (VideoToolbox) cho H.264/HEVC; codec khác giải bằng CPU.
- Bản: **VLCKit 4.0 alpha** (4.0.0a25, 30/9/2026; người dùng chốt 2026-10-14) — gói SPM chính thức, có PiP trên
  iOS và macOS. Ghim đúng bản, bọc sau một lớp Data để đổi được; xét lại bản ổn định trước khi phát hành.
- Cỡ app thêm (đo thô ở spike S1, 14/10): **+44 MB** khi cài (framework động 43 MB), **~19 MB** khi tải về; gói SPM
  922 MB là mọi nền tảng + simulator, không vào app. Số chính thức lấy từ báo cáo App Thinning — AC-28.
- **Phim trên NAS**: VLC không tự mở `smb://`/`sftp://`/`https://`. ShotDex đọc file bằng chính kết nối FS-15 (mật khẩu
  Keychain, host key và chứng chỉ người dùng đã tin) và đưa byte cho VLC qua một luồng tua được; VLC không thấy mật
  khẩu, không có hộp thoại riêng. MKV/WebM mở với Cues được tin để tua qua mạng ~3 s (không thì VLC giải mã lại từ đầu);
  Cues hỏng thì mở lại kiểu thường. Plex dùng URL HTTP của Plex (07 §2). Spike:
  [2026-10-14-fs23-s1-vlckit-spike](../../_intents/2026-10-14-fs23-s1-vlckit-spike.md).

## 2. Mở và trạng thái

| Trạng thái | Hiển thị |
|---|---|
| đang mở | nền đen, vòng quay sau 350 ms (như FS-02.02 §2) |
| sẵn sàng | khung hình đầu đã vẽ, chrome hiện 3 s rồi mờ đi |
| lỗi | thẻ cảnh báo `Can't Play This Movie` + lý do một dòng (`The video format HEVC 12-bit isn't supported.`) + **Close** |

- Mở toàn màn (không phải sheet): kéo xuống không đóng; đóng bằng ✕ trên trái hoặc Esc / ⌘W.
- **Chỗ đang xem**: đã xem > 1 phút và < 95% → mở tại chỗ đó, nhãn `Resumed at 47:12 · Start Over` trong 5 s.
  Vị trí ghi mỗi 10 s, lúc dừng, lúc đóng, lúc rời app.
  Tới 95% hoặc hết phim → đánh dấu **đã xem** (mất khỏi lọc Unwatched), lần sau mở từ đầu. Độ dài player đọc được
  ghi lại cho phim mà lúc quét chưa biết độ dài (MKV, AVI…).
- Đang phát thì màn không tự tắt; dừng hoặc đóng thì trả lại hẹn giờ tắt màn của hệ thống.
- Phát phim không gọi mạng nào (chế độ máy bay không đổi gì).

## 3. Transport

Giữ đúng bộ của FS-02.02 §3–§4 (cụm giữa + kính hai hàng, giờ đơn cách, một hẹn giờ ẩn 3 s, mờ chứ không chèn).

| Chỗ | Nội dung |
|---|---|
| trên | ✕ · tên phim (một dòng, cắt giữa) · nút PiP |
| giữa | −10 s / phát-dừng / +10 s, 56 / 68 / 56 pt |
| hàng 1 | phát-dừng · đã qua · thanh tua · còn lại |
| hàng 2 (44 pt mỗi nút) | tốc độ · **Audio & Subtitles** · Fit/Fill · khoá chạm |

- Tốc độ: 0.5 · 0.75 · 1 · 1.25 · 1.5 · 2×; nhớ theo từng phim.
- **Audio & Subtitles**: mở **một** bảng (§3b) — phần Audio ở trên, phần Subtitles (03 §2) ở dưới (planboard D8).
- **Fit/Fill**: vừa khung (có viền đen) ↔ lấp khung (cắt mép); pinch ra/vào làm cùng việc.
- **Khoá chạm**: chạm màn chỉ hiện nút mở khoá — để trên máy bay chạm nhầm không tua. Mac không có (không có chạm).
- Cử chỉ: chạm bật/tắt chrome; chạm đúp nửa trái/phải = −10 s/+10 s; kéo thanh tua có ảnh khung xem trước khi
  engine cung cấp được, không thì chỉ giờ.

## 3b. Bảng Audio & Subtitles — phần Audio

Một bảng cho cả tiếng và phụ đề: máy ngang = bảng phải 372pt (cuộn), dọc = sheet nửa màn; phim vẫn chạy. Mở cả từ
menu phim › Audio & Subtitles…. Phần Audio trước, phần Subtitles sau (03 §2).

- Danh sách **mọi track âm thanh** của file. Mỗi hàng: ngôn ngữ (tên bằng chính thứ tiếng đó) · tên track nếu file có
  (`Commentary`, `Director's Cut`) · codec · số kênh (`Stereo`, `5.1`, `7.1`) · nhãn `Default` cho track file đặt
  mặc định. Track đang phát có dấu ✓.
- Chạm một hàng → đổi track **không dừng phim**, giờ không lùi; không đóng bảng (để nghe thử).
- **Audio Sync**: −5,00…+5,00 s, bước 0,05 s, nghe thấy ngay; nhớ theo từng phim.
- Dòng chân: đường ra hiện tại (`Playing as stereo on AirPods Pro`, `5.1 on HomePod`) — track nhiều kênh hơn
  đường ra thì được trộn xuống, không lỗi. Codec máy không giải được (hiếm) → hàng mờ + `Not supported on this
  device`.
- Phim mới: chọn track có ngôn ngữ đầu tiên trong **Audio Languages** (Settings › Playback, mặc định `Original` =
  track `Default` của file); không khớp → track `Default`. Track chọn nhớ theo từng phim.
- Cố ý không có: file âm thanh rời bên ngoài, tăng giọng nói / chế độ ban đêm — *làm sau nếu cần.*

## 4. Hướng màn và thiết bị

- iPhone: khung phim xoay 90° trong giao diện khi máy dọc mà phim ngang — đúng cách FS-02.02 §8, không gọi API xoay.
- iPad, Duo trong: phim lấp cửa sổ, cả dọc lẫn ngang; Split View/Stage Manager co theo cửa sổ.
- Duo ngoài (466×678, rail 84pt): **chỉ phát**. Movies hiện danh sách, chạm để phát; không có **+**, ⋯, Delete, Rename
  (Stop Copying và Retry vẫn có). Player xoay 90° như iPhone: phim 678×381 lấp cột 382pt, rail thành dải transport;
  bảng phụ đề là nửa dưới của khung đã xoay (233pt).
  Gập/mở máy giữa lúc phát: giữ phim, vị trí, phụ đề.
- Mac: cửa sổ player riêng; transport là thanh kính hiện khi rê chuột, −10/phát/+10 nằm trong thanh, không nút tròn
  nổi trên hình (MAC_STYLE); Space phát/dừng, ←/→ 10 s, F toàn màn, ⌘W đóng. Bàn phím iPad dùng cùng phím.
- Rời app khi đang phát: sang PiP nếu người dùng đã bật PiP tự động của hệ thống, không thì dừng (không phát nền tiếng).

## 5. Truy cập

- Mọi nút có nhãn VoiceOver (`Audio and Subtitles: English AC3 5.1, English and Vietnamese subtitles`); thanh tua là
  control điều chỉnh được, mỗi bước 10 s.
- Chữ phụ đề theo cỡ chữ người dùng chọn trong bảng phụ đề, không theo Dynamic Type (đè lên hình).
