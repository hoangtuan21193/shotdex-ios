# FS-23.07 — Plex trong mạng nhà

`FS-23.07` · tier A · board `PH_PlexSignIn` · cập nhật 2026-10-14

**Một câu:** thêm máy chủ Plex làm nguồn của Movies bằng tài khoản Plex của người dùng; phim Plex stream bản gốc
khi ở nhà, tải bản gốc kèm poster và thông tin để xem offline, chỗ đang xem đồng bộ với Plex.

Quyết định: [planboard movies-library](../../../.planboard/movies-library/DECISIONS.md) D4, D5, A3, A4, A6.

## 1. Đăng nhập

- + › Add a Source… › **Plex Server** → màn `Sign In to Plex`: mã 4 ký tự to (`K7Q2`) · "Go to plex.tv/link on any
  device and enter this code." · nút **Open plex.tv/link** (mở Safari trên máy này) · Cancel. Mã hết hạn → tự lấy mã mới.
- Đăng nhập xong → danh sách máy chủ của tài khoản, máy chủ trong mạng nhà lên đầu, kèm `On this network`; chọn
  một → chọn thư viện (mặc định mọi thư viện Movies và TV Shows) → **Add**.
- Đây là tài khoản Plex của người dùng, không phải tài khoản ShotDex. Token ở Keychain, chỉ trên máy này. Máy chủ của
  người khác chia sẻ dùng `accessToken` riêng của máy chủ đó (plex.tv cấp trong danh sách máy chủ).
- Gỡ: Settings › Sources › Plex › **Sign Out** — xoá token, phim stream biến khỏi Movies, phim đã tải ở lại.

## 2. Stream

- Phát **bản gốc** (direct play) qua mạng nhà; không nhờ Plex chuyển mã. Ưu tiên địa chỉ trong mạng nhà; chỉ có địa
  chỉ ngoài Internet thì vẫn phát nếu tới được (qua Plex relay hay VPN của người dùng).
- **Chọn đường** (spike S3): thử cùng lúc mọi đường plex.tv đưa, đường trong mạng nhà trước, lấy đường trả lời đầu tiên;
  nhớ đường đó cho lần sau. Trong nhà: `https://…plex.direct` (chứng chỉ thật, hệ thống tự tin), không được thì
  `http://<IP LAN>:32400` khi máy chủ cho phép. Không dựa vào cờ `publicAddressMatches` để đoán "đang ở nhà" — đo thật thì
  nó báo sai. Relay là đường cuối: chậm và chập chờn.
- Byte phim đi qua cùng đường đọc của ShotDex như phim trên NAS (02 §1), token nằm trong header — VLC không thấy token.
- **Phim có nhiều bản** (người dùng chốt 14/10): chạm là phát bản nét nhất.
- Phụ đề rời của Plex (file `.srt`… cạnh phim trên máy chủ) có trong bảng Audio & Subtitles như phụ đề cạnh phim.

## 3. Tải về

- Menu phim › Keep on iPhone tải **bản gốc**; trước khi tải hiện cỡ (`18.4 GB`) trong menu; thiếu chỗ → như
  01 §6. Chọn chất lượng nhỏ hơn: không có trong bản này (cần Plex Pass và máy chủ chuyển mã).
- Phim có nhiều bản: Keep on iPhone mở danh sách các bản, mỗi dòng độ phân giải + cỡ (`4K · 54.3 GB`,
  `1080p · 8.1 GB`), nét nhất ở trên; phim một bản thì như trên (người dùng chốt 14/10).
- Tải kèm: poster, ảnh nền, năm, mô tả, thể loại, thời lượng, phụ đề rời — offline vẫn đủ trên Grid và trong menu.

## 4. Đồng bộ với Plex

- Chỗ đang xem và dấu đã xem đồng bộ **hai chiều** khi tới được máy chủ: xem dở trên TV mở iPhone xem tiếp, và ngược lại.
- Xem offline: ghi lại trên máy, gửi lên khi tới lại được máy chủ; trùng thì lấy lần xem mới nhất.
- Phim bị xoá trên Plex: bản đã tải ở lại, nhãn `Removed from Plex`, Remove from iPhone vẫn dùng được (chữ theo FS-24.09, D6).

## 5. Lỗi

| Lỗi | Hiển thị |
|---|---|
| máy chủ không tới được | phim Plex mờ như 01 §3; Settings › Sources dòng `Mac Studio — Can't reach` |
| token hết hiệu lực / đổi mật khẩu Plex | `Sign in to Plex again` + nút Sign In ở Settings › Sources; phim đã tải vẫn phát |
| file trên máy chủ không còn | `This movie is no longer on Mac Studio.` |
