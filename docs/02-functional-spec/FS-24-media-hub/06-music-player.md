# FS-24.06 — Player nhạc: hàng đợi, gapless, hẹn giờ, lời bài, lock screen

`FS-24.06` · tier A (Now Playing theo sáng/tối) · mã: chưa có (đề xuất `ShotDex/Data/Music/` cho phát, `Features/Music/`
cho màn) · board: mini player trên mọi board gốc; Now Playing iPhone `PH_NowPlaying` · iPad `IP_NowPlaying` · Duo `DI_NowPlaying` / `DC_NowPlaying` · Mac `MAC_NowPlaying`; Up Next iPhone `PH_UpNext` · iPad `IP_UpNext` · Duo `DC_UpNext` (Duo trong: pane phải của `DI_NowPlaying`) · Mac `MAC_UpNext`; Lyrics iPhone `PH_Lyrics` · iPad `IP_Lyrics` · Duo `DI_Lyrics` / `DC_Lyrics` · Mac `MAC_Lyrics`; Sleep Timer iPhone `PH_SleepTimer` · iPad `IP_SleepTimer` · Duo `DI_SleepTimer` / `DC_SleepTimer` · Mac `MAC_SleepTimer` · cập nhật 2026-10-16

**Một câu:** nhạc phát liên tục khi chuyển tab, khoá máy hay chuyển app; điều khiển được từ mini player, Now Playing,
lock screen, Control Center và tai nghe; bài nối nhau không khoảng lặng, có hẹn giờ tắt và lời bài.

## 1. Engine

- **AVFoundation** (intent câu 5). Một player cho cả hàng đợi; bài kế được nạp trước để nối không khoảng lặng.
- Bài trên NAS: AVFoundation không mở `smb://`/`sftp://`. ShotDex đọc byte bằng chính kết nối FS-15 và đưa cho player theo
  khối 1 MB có tua (như phim, FS-23.02 §1); player không thấy mật khẩu. Plex: URL HTTP của Plex, token ở header.
- **Chốt 2026-10-16 (A10):** cầu byte cho AVFoundation là đường mới (phim dùng VLCKit) → spike **S-M2** trước `/plan`: phát
  FLAC 24-bit qua SMB giả, tua, nối bài, AirPlay, khoá máy. Spike hỏng thì dự phòng theo thứ tự: chép bài vào cache tạm trước
  khi phát (trễ ≈ thời gian tải một bài), rồi mới tới chỉ phát bài đã Keep với nguồn SMB/SFTP — chọn cái nào ghi vào báo cáo
  spike, AC-53/AC-92 đổi theo.
- Bài đã Keep hoặc chép thẳng: đọc từ máy, **0 yêu cầu mạng**.

## 2. Hàng đợi

- Phát một album, playlist, danh sách bài, kết quả tìm = hàng đợi mới bắt đầu ở bài đã chạm; dòng `Playing from 22, A Million`.
- **Play Next** chèn sau bài hiện tại; **Add to Queue** thêm cuối phần người dùng tự thêm (như app Music).
- Up Next: kéo để sắp lại, vuốt để bỏ, **Clear** (bỏ mọi bài sau bài hiện tại). History: 50 bài đã phát gần nhất.
- **Shuffle**: trộn phần còn lại, bài đang phát giữ nguyên; tắt Shuffle trả thứ tự gốc từ bài hiện tại.
- **Repeat**: Off → All → One (một nút xoay vòng). Hết hàng đợi với Off: dừng ở đầu bài cuối, mini player còn.
- Hàng đợi, bài, vị trí, Shuffle, Repeat lưu lại; mở lại app = trạng thái **đã dừng** tại đúng chỗ (không tự phát).
- Bài stream của nguồn không tới được: bị **bỏ qua** khi tới lượt, dòng mờ trong Up Next kèm `Not available offline`.
  Cả hàng đợi không phát được → dừng, Now Playing ghi `Can't reach NAS Home. Kept songs still play.`

## 3. Gapless và chuyển bài

- Bài kế bắt đầu đọc trước khi bài hiện tại còn **30 s**; với nguồn mạng, đọc trước tối đa 8 MB.
- Album gapless (WAV, FLAC, ALAC, AAC có thông tin độ trễ mã hoá): khoảng lặng giữa hai bài **≤ 10 ms** đo trên file test.
  MP3 không có thẻ gapless: không hứa, khoảng lặng do bộ mã hoá giữ nguyên.
- Không crossfade ở v1 (đi ngược gapless; không có trên board).

## 4. Hẹn giờ tắt (Sleep Timer)

- Lựa chọn: Off · 5 · 15 · 30 · 45 · 60 min · **End of Song**. Đang chạy: nút ghi giờ còn lại (`23:41`), mono-digit.
- Hết giờ: âm lượng giảm dần trong 10 s rồi Pause (không Stop — hàng đợi giữ). Khoá máy, chuyển app không làm lệch giờ.
- Người dùng bấm Pause trước giờ: timer huỷ. Không nhớ qua lần mở app sau.

## 5. Lời bài (Lyrics)

- Nguồn theo thứ tự: `.lrc` cùng tên cạnh bài (có giờ) → lời nhúng trong tag (có giờ nếu SYLT, không thì chữ thường).
  Không tìm lời trên mạng (giấy phép lời bài; riêng tư). Plex: không lấy lời ở v1.
- Có giờ: dòng hiện tại đậm, tự cuộn giữ ở 1/3 trên; chạm một dòng = tua tới giờ của dòng. Không giờ: cuộn tay.
- Bài không lời: nút Lyrics mờ, VoiceOver đọc `Lyrics, not available`. Ô **Lyrics** ở Utilities liệt kê bài có lời.
- `.lrc` mã khác UTF-8 (Windows-1258, Shift-JIS): đoán mã như phụ đề phim (FS-23.03), chữ có dấu đọc đúng.

## 6. Lock screen, Control Center, tai nghe

- Thông tin Now Playing hệ thống: tên, nghệ sĩ, album, bìa, thời lượng, giờ đã qua, tốc độ — cập nhật khi đổi bài, tua, dừng.
- Lệnh từ xa: Play · Pause · Play/Pause · Next · Previous (≤ 3 s đầu bài = bài trước, sau đó = về đầu bài) · kéo thanh tua.
- Tai nghe rút ra / AirPods tháo cả hai: **Pause**. Cuộc gọi, Siri, báo thức: Pause; hệ thống báo được tiếp tục thì phát tiếp.
- **Phim cũng có Now Playing** (intent): khi phim phát (trong app hoặc PiP) lock screen hiện tên phim, poster, thời
  lượng; lệnh Play/Pause, tua, lùi/tới 10 s; không Next. Đóng player = xoá thông tin.
- **Chốt 2026-10-16 (D2):** Settings › Playback thêm công tắc **Movie Audio in Background**, **mặc định bật**. Chân hàng:
  "When you lock iPhone or switch apps, the movie keeps playing its sound. Picture in Picture is unchanged."
  - **Bật:** khoá máy hoặc chuyển app khi phim đang phát (không vào PiP) → phim **chạy tiếp chỉ tiếng**: hình tạm tách khỏi
    player, giờ phim đi tiếp, lock screen/Control Center có Now Playing của phim với lệnh như trên (Play/Pause, tua, ±10 s,
    không Next). Mở lại app → hình nối đúng giờ đang phát (lệch ≤ 1 s), không tua lại. Ngắt âm thanh (cuộc gọi, Siri, tai
    nghe rút) xử lý như nhạc (§6). Chỗ đang xem vẫn ghi mỗi 10 s (FS-23.02 §2).
  - **Tắt:** phim **dừng** khi rời app như FS-23.02 §4 hôm nay.
  - **PiP không đổi:** người dùng đã bật PiP tự động của hệ thống, hoặc bấm nút PiP → vào PiP như hôm nay, công tắc không
    xét. Mac không có công tắc này (cửa sổ player Mac không bị treo khi app ở nền).
  - FS-23.02 §4 trỏ về đây; công tắc lưu ở kho cài đặt mặc định ([12 §3](12-data.md)).

## 7. Một chủ âm thanh

| Đang phát nhạc thì… | Hành vi |
|---|---|
| mở phim (FS-23) | nhạc Pause; đóng phim không tự phát lại nhạc |
| chạm phát video trong Viewer (có tiếng) | nhạc Pause; video tự phát không tiếng thì nhạc không đổi |
| vào Video Studio | nhạc **Pause** (D1, bên dưới) |
| app khác phát (Podcasts, YouTube) | hệ thống ngắt nhạc ShotDex; ShotDex không tự giành lại |

- **Chốt 2026-10-16 (D1):** mở Video Studio (vào một dự án) thì nhạc **tự Pause** — dựng video cần nghe đúng tiếng của dự án.
  Ra khỏi Video Studio nhạc **không** tự phát lại; mini player còn, người dùng bấm Play.

## 8. Now Playing toàn màn

- Nội dung tối thiểu (để vẽ board): bìa lớn · tên · `nghệ sĩ — album` · nguồn · thanh tua (đã qua / còn lại, mono-digit) ·
  Previous / Play-Pause / Next · Shuffle · Repeat · AirPlay (bộ chọn đường ra của hệ thống) · Lyrics · Up Next · Sleep Timer ·
  ⋯ (Keep on iPhone / Remove from iPhone · Add to Playlist… · Go to Album · Go to Artist · **Stop**). Kéo xuống để đóng.
- iPad/Mac: Now Playing là sheet/cửa sổ phụ; Duo trong: bìa trái, Up Next/Lyrics phải (rộng dư, cao thiếu).
- **Chốt 2026-10-16 (A11):** board Now Playing, Up Next, Lyrics, Sleep Timer vẽ trên **cả 4 canvas** trước `/plan` (PLAN 2.1) —
  đã vẽ 2026-10-16, tên board ở dòng đầu phần này.

## 9. Cố ý không có

CarPlay — **Chốt 2026-10-16 (D3):** xin entitlement CarPlay audio với Apple **ngay** (duyệt mất vài tuần), nhưng bản đầu **không**
làm CarPlay; việc xin là việc ngoài code, không có AC. · EQ · crossfade · tốc độ phát nhạc · scrobble Last.fm.
