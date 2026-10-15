# FS-24.04 — Tab Movies: Movies · TV Shows · Clips

`FS-24.04` · tier B · mã hiện có: `Features/Movies/MoviesScreen.swift` · board iPhone `PH_Movies` · iPad `IP_Movies` · Duo
`DI_MoviesHome`, `DC_MoviesHome`, `DI_Movies` / `DC_Movies` (See All) · Mac `MAC_MoviesHome` · cập nhật 2026-10-16

**Một câu:** thư viện phim FS-23 thôi là một ô trong Utilities của ảnh và thành tab riêng, chia ba kệ Movies · TV Shows ·
Clips; mọi thứ FS-23 làm được (nguồn, stream, Keep, player, phụ đề, dịch, Plex, trang chi tiết) giữ nguyên.

**Thay FS-23:** chỉ FS-23.01 §1 (lối vào), §4 (màn Movies → trang chủ có kệ, lưới cũ là See All) và chữ Download → Keep
([09](09-keep-on-device.md)). Các phần 02–08 của FS-23 không đổi.

## 1. Đầu tab

- Leading ⚙. Trailing **⋯** (Grid/List · Sort By › Recently Added · Select) và **+** (Add a Source… · Add Movie Files…).
- Ô **Search Movies** (tên, năm, tên file, `S02E04`; offline; luật FS-23.01 §4) — chỉ tìm trong Movies.
- Chip một hàng cuộn ngang: **All · Movies · TV Shows · Clips · Unwatched · On This iPhone**. All = trang chủ có kệ; chip khác
  = lưới phẳng FS-23.01 §4 đã lọc.

## 2. Trang chủ (chip All)

Thứ tự cố định; kệ rỗng thì không vẽ (trừ Utilities, Sources).

1. Thẻ gợi ý **Review** (§3), chỉ khi có video để gợi ý và chưa bị bỏ qua.
2. **Continue Watching** — phim/tập/clip đã xem > 1 phút và < 95% (FS-23.02 §2), mới xem trước, tối đa 10; thẻ ngang có
   ảnh khung, tên, `S03E04 · 22 min left` / `Clip · 12 min left`. Chạm = phát tiếp (không qua trang chi tiết).
3. **Movies** (See All) — poster 2:3 kéo ngang; dưới poster tên + năm, hoặc `Keeping 45%`, `Paused · 12%`.
4. **TV Shows** (See All) — một thẻ mỗi bộ: `3 seasons · NAS Home`; chạm mở trang bộ: mùa › tập, tập đã xem có dấu.
5. **Clips** (See All) — thẻ 16:9: tên, `NAS Home · 18:20`.
6. **Utilities** — lưới 2 cột: **On This iPhone** · **Watch History** · **Subtitles** · **Convert** · **Extract Audio** ·
   **Recently Added**. Không có Statistics cho Movies (người dùng 15/10).
7. **Sources** — nguồn có phim: NAS Home · Plex — Living Room · Files · Add Source…; offline thì mờ.

- Mọi nguồn mạng không tới được: dòng chân trên Sources "Away from home: NAS Home and Plex can't be reached. Kept items (✓)
  still play." — không banner chặn trên đầu.
- Dòng tổng ở cuối khi cuộn hết (FS-23.01 §4): `128 movies · 14 shows · 36 clips · 3 on this iPhone (21.4 GB) · 48 GB free`.

## 3. Phân loại Movies · TV Shows · Clips

| Thứ tự xét | Loại |
|---|---|
| người dùng đã đặt bằng **Show As** (A8) | loại đã đặt — luật bên dưới không xét nữa |
| Plex: loại do Plex gắn (movie / episode) | Movie / TV Show |
| tên file có `SxxEyy` hoặc `1x04` | TV Show (gom bộ theo tên trước mã tập) |
| tên file có năm 1900–2099 tách riêng (`Dune.Part.Two.2024…`) | Movie |
| còn lại; video chuyển từ Photos; file Add Movie Files… không năm | Clip |

- **Chốt 2026-10-16 (A8):** sửa loại sai bằng **Show As › Movie · TV Show · Clip** trong menu phim (dấu ✓ ở loại hiện tại).
  Lưu ở cột "loại do người dùng đặt" của bảng phim ([12 §2](12-data.md)); lần quét không bao giờ ghi đè cột đó. Phim chuyển kệ
  ngay (≤ 0,5 s), không quét lại. Chọn TV Show cho file không có mã tập: thành một bộ riêng tên theo tên hiện, một tập
  (`S01E01` ngầm); chọn lại loại gốc = xoá giá trị đã đặt, về luật. Board: menu phim `PH_Movies` · `IP_Movies` · `DI_Movies` · `MAC_Movies` (tweak `showAs`); Duo ngoài không có Show As.

**Thẻ Review** — "12 videos look downloaded" · "In Photos, no camera info" · **Review** · ✕ (bỏ qua tới khi có video mới).
- Đếm: video trong Photos **không** có hãng/đời máy quay trong metadata đã index, dài ≥ 60 s, không phải screen recording.
- Review mở danh sách có ô chọn (mặc định chọn hết), nút **Move to Movies**: chép file gốc vào kho Movies thành Clip đã
  Keep (cần iCloud thì tải trước, có tiến độ, OriginalDownloadLine); chép xong mới hỏi xoá ở Photos.
- **Chốt 2026-10-16 (D5):** chép xong thì **hỏi mỗi lần** bằng hộp xoá **của hệ thống** (yêu cầu xoá của PhotoKit — chữ do iOS
  viết, nghĩa `Delete 12 videos from Photos?`); ShotDex **không** vẽ thêm hộp hỏi riêng của mình trước đó. Delete → video vào
  Recently Deleted của Photos (hệ thống giữ 30 ngày), bản trong Movies ở lại. Cancel/Don't Allow → giữ cả hai bản, không hỏi
  lại cho đợt đó; thẻ Review không gợi ý lại những video đã chuyển.
  - Chỉ đưa vào hộp xoá những video **đã chép xong và đọc lại đúng cỡ** trong kho Movies; video lỗi, đang chờ iCloud hay bị
    Cancel không bao giờ nằm trong yêu cầu xoá (số trong hộp = số đã chép xong).
  - Màn Review và hộp xoá: board iPhone `PH_MoviesReview` · iPad `IP_MoviesReview` · Duo `DI_MoviesReview` / `DC_MoviesReview` · Mac `MAC_MoviesReview` (tweak `deleteDialog`, `copying`).

## 4. Utilities của Movies

| Ô | Mở |
|---|---|
| On This iPhone | lưới phim/tập/clip đã Keep + đang Keep, dòng tổng dung lượng ([09](09-keep-on-device.md)) |
| Watch History | danh sách theo lần xem cuối, mỗi hàng `Watched Oct 12 · 47:12 of 2:46:00`; vuốt = Remove from History (không đổi chỗ đang xem); Clear History… (alert) |
| Subtitles | mọi phụ đề đã nhập / chia sẻ / dịch, nhóm theo phim; Delete một file; tổng dung lượng |
| Convert | [10 §1](10-convert-extract-audio.md) |
| Extract Audio | [10 §2](10-convert-extract-audio.md) |
| Recently Added | lưới theo ngày thêm, 30 ngày gần nhất |

Board: Watch History iPhone `PH_WatchHistory` · iPad `IP_WatchHistory` · Duo `DI_WatchHistory` / `DC_WatchHistory` · Mac `MAC_WatchHistory`; Subtitles iPhone `PH_Subtitles` · iPad `IP_Subtitles` · Duo `DI_Subtitles` / `DC_Subtitles` · Mac `MAC_Subtitles`; trang TV Show iPhone `PH_TVShow` · iPad `IP_TVShow` · Duo `DI_TVShow` / `DC_TVShow` · Mac `MAC_TVShow`; trang phim iPhone `PH_MovieDetail` · iPad `IP_MovieDetail` · Duo `DI_MovieDetail` / `DC_MovieDetail` · Mac `MAC_MovieDetail`; Convert, Extract Audio xem [10](10-convert-extract-audio.md).

## 5. Menu phim và Duo ngoài

- Menu phim (board `PH_Movies` tweak item): **Play** · **Keep on iPhone** `3.2 GB` / **Remove from iPhone** (D6) · **Mark as Watched** ·
  **Audio & Subtitles…** · **Show As ›** (A8) · **Rename** · **Convert…** · **Extract Audio…** · Retry Keep (khi lỗi) · Remove from
  Movies (file chép thẳng).
  Convert…, Extract Audio… trong menu là lối vào thứ hai của ô Utilities — có trên menu phim `PH_Movies`, `IP_Movies`, `DI_Movies`, `MAC_Movies`.
- Duo ngoài: không có **+**, ⋯ chỉ View/Sort, menu không có Rename/Remove/Show As/Convert/Extract (FS-23.02 §4).
