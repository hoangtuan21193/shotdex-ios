# FS-24.07 — Music › Statistics

`FS-24.07` · tier A · board iPhone `PH_HubMusicStats` · iPad `IP_MusicStats` · Duo `DI_MusicStats` / `DC_MusicStats` · Mac
`MAC_MusicStatistics` · cập nhật 2026-10-16

**Một câu:** thống kê thói quen nghe từ lịch sử phát trên máy — nghe bao nhiêu giờ, nghệ sĩ nào, định dạng gì, từ nguồn
nào — như Statistics của ảnh nói body nào, lens nào.

## 1. Lối vào và khung

- Music › Utilities › **Statistics** (ô đầu); push trong tab Music, ⚙ thành **‹ Music**. Movies không có Statistics.
- Đầu màn: segmented **This Year | All Time** (mặc định This Year). Thẻ dùng `ChartCard`, màu theo `ChartPalette` (DESIGN §3.4):
  một chuỗi → accent quiet/emphasis; không màu mới.

## 2. Thẻ (thứ tự board iPhone)

| Thẻ | Nội dung | Ví dụ board |
|---|---|---|
| KPI | giờ đã nghe (làm tròn giờ) · số lượt nghe · số bài khác nhau | `214 h listened` · `3,812 plays · 1,104 different songs this year` |
| Top artists | 5 nghệ sĩ nhiều lượt nhất, thanh ngang, số lượt | Bon Iver 312 |
| Format | tỉ lệ **lượt nghe** theo codec (FLAC, ALAC, AAC, MP3, WAV) | FLAC 48% |
| By source | tỉ lệ lượt nghe theo nguồn (bài Keep tính theo nguồn gốc) | NAS Home 70% |
| Most played | 5 bài nhiều lượt nhất | Holocene 64 |

- iPad, Duo trong, Mac thêm (board `IP_MusicStats`): **Top albums** · **Kept on iPad** (số bài, GB) · **By month** (cột theo tháng).
- **Chốt 2026-10-16 (D10):** điện thoại có **đủ 8 thẻ** như iPad (NF-05 §1.1, memory `phone-has-every-ipad-feature`): Top albums ·
  Kept on iPhone · By month nằm dưới năm thẻ trên, một cột, cuộn dọc. Danh sách thẻ dựng từ **một** kiểu liệt kê mọi thẻ,
  không viết tay theo thiết bị. Board `PH_HubMusicStats`, `IP_MusicStats`, `DI_/DC_MusicStats`, `MAC_MusicStatistics` đều vẽ đủ 8 thẻ.
- Chạm một hàng nghệ sĩ/bài/album → mở nghệ sĩ/bài/album trong Music. Chạm một nguồn hay định dạng → danh sách bài đã lọc.

## 3. Đếm lượt nghe

- Một **lượt** = phát liên tục ≥ 50% bài hoặc ≥ 4 phút, cái nào tới trước; tua không tính phần bị nhảy. Lặp One = mỗi vòng một lượt.
- Giờ đã nghe = tổng thời gian âm thanh thật sự phát (không tính Pause), mọi lượt kể cả lượt chưa đủ ngưỡng.
- Lịch sử chỉ trên máy này (không đồng bộ Plex ở v1); bảng riêng ([12](12-data.md)). Xoá bài khỏi thư viện giữ lượt nghe
  (tên, nghệ sĩ ghi kèm lượt) để Statistics không đổi quá khứ.
- **Chốt 2026-10-16 (D11):** Settings › Playback có hàng **Clear Listening History…** (chữ đỏ, kiểu hàng phá huỷ). Chạm → hỏi
  lại bằng alert: `Clear Listening History?` · "Recently Played, Most Played and Music Statistics start over on this iPhone.
  Your songs, playlists and kept music stay." · **Clear History** (đỏ) · **Cancel**.
  - Clear History xoá **mọi** dòng bảng lượt nghe và phần **History** của hàng đợi; **không** đụng bài, playlist, thứ đã Keep,
    Up Next, bài đang phát. Statistics về `No Listening Yet`.
  - Cancel: không đổi gì. Chưa có lượt nghe nào: hàng mờ, không mở alert.
  - Không hoàn tác được (alert đã nói); lịch sử chỉ trên máy nên không có gì để đồng bộ xoá ở Plex.

## 4. Trạng thái

| Trạng thái | Hiển thị |
|---|---|
| chưa nghe bài nào | `No Listening Yet` · "Statistics appear after you play some music." |
| This Year rỗng nhưng All Time có | thẻ KPI `0 h listened this year` + nút chuyển All Time |
| nguồn đã gỡ | vẫn hiện tên nguồn cũ trong By source, nhãn `Removed` |
