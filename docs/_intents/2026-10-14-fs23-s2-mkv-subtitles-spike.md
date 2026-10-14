# Spike S2: lấy phụ đề chữ nằm trong file MKV

| Trường | Giá trị |
|---|---|
| Cho | plan [2026-10-14-fs23-movies](../_plans/2026-10-14-fs23-movies.md) mốc 0, spike S2 · spec FS-23.03 §3, AC-23, AC-53, AC-55 |
| Ngày | 2026-10-14 |
| Máy đo | MacBook Pro M1 Max, SSD trong, macOS 27, Swift 6 `-O` — **chưa đo trên iPhone, chưa đo qua NAS thật** |
| Code | Swift package dòng lệnh trong scratchpad (~350 dòng), **không giữ lại**; cấu trúc ghi ở §5 cho task 24 |
| Kết luận | **Đi, tự đọc EBML.** VLCKit không xuất được phụ đề chữ kèm giờ. Bộ đọc tự viết lấy đúng 100 % SRT và ASS từ file ffmpeg và mkvmerge (cả nén zlib). Cả hai trình đóng gói đều ghi **Cues cho track phụ đề**, nên chỉ cần đọc các khối phụ đề: phim 3 GB, 3 giờ → **0,5 MB, 1,2 s cache lạnh**. Người dùng chốt lại (14/10): phim stream cũng trích khi có Cues |

## 1. VLC không làm được việc này

Đọc danh sách module trong `VLCKit.framework` 4.0.0-a25 (iOS arm64):

- có `stream_out/es`, `stream_out/transcode` (cả `spu.c`), mux `mp4`, `ts`, `ps`, `avi`, `ogg`, `asf`;
- **không có** bộ ghi phụ đề chữ (SRT/ASS/WebVTT) và không có mux MKV. `es` ghi ra phần ruột của khối, **mất giờ**.
  Đi vòng (transcode sang `tx3g` trong MP4 rồi đọc bằng AVFoundation) thì VLC phải chạy hết phim — không đáng.
- Có `libass`, `subsdec`, `subsvtt`, `substtml`, `freetype`, `avcodec/subtitle.c` (PGS), `spudec` (VobSub): VLC **vẽ**
  được mọi loại track trong file. Đó là đường cho phim stream không trích được (AC-55) và cho track ảnh (AC-23).

## 2. File thử

| File | Cách tạo | Đặc điểm |
|---|---|---|
| `ff.mkv` 165 MB, 10 phút | ffmpeg 9.0.2 | SRT tiếng Anh 120 dòng; ffmpeg đặt **CRC-32 trước Timecode** trong mỗi Cluster |
| `mm.mkv` | mkvmerge 102.0 từ `ff.mkv` + `vi.ass` | SRT (en) + ASS (vi, có `{\an8}`, `{\i1}`, dấu tiếng Việt), BlockGroup có BlockDuration, tiếng có lacing |
| `mm-zlib.mkv` | như trên, `--compression …:zlib` cho 2 track phụ đề | ContentCompression zlib |
| `big.mkv` 2,97 GB, 3 giờ | mkvmerge nối `mm.mkv` 18 lần | 2 160 dòng mỗi track, 3 114 Cluster, 394 198 khối |
| `movtext.mp4` | ffmpeg `-c:s mov_text` | track chữ trong MP4 |

## 3. Đúng

Bộ đọc xuất SRT/ASS rồi so với file gốc (giờ bắt đầu, giờ kết thúc, chữ từng dòng):

| File | Quét cả file | Theo Cues |
|---|---|---|
| `ff.mkv` | SRT khớp 120/120 | khớp (sau khi sửa: Timecode không phải con đầu tiên của Cluster) |
| `mm.mkv` | SRT + ASS khớp | SRT + ASS khớp |
| `mm-zlib.mkv` | SRT + ASS khớp | SRT + ASS khớp |
| `big.mkv` | 2 160 + 2 160 | trùng từng byte với bản quét, dòng cuối `02:59:55,357` |

ASS giữ được `{\an8}{\i1}` để parser của task 5 xử lý (AC-22). Track ASS lấy phần đầu (`[Script Info]`, `[V4+ Styles]`) từ
`CodecPrivate`, dòng sắp theo `ReadOrder`.

## 4. Tốn bao nhiêu (phim 3 GB, 3 giờ, 2 track phụ đề)

Mỗi lần đo chép file mới bằng `ditto --nocache` để không trúng cache đĩa của Mac, đọc với `F_NOCACHE`.

| Cách | Thời gian | Byte đọc | Số lần đọc |
|---|---|---|---|
| **Theo Cues**, mỗi lần đọc đúng chỗ cần | **1,22 s** | **0,55 MB (0,02 %)** | 15 169 |
| Theo Cues, gom theo khối 4 KB | 0,79 s | 35 MB (1,2 %) | 8 644 |
| Quét tuần tự cả file, khối 1 MB | 1,17 s | 2,95 GB (99,5 %) | 2 815 |
| Quét nhảy, chỉ đọc đầu mỗi phần tử | 11,8 s | 12,9 MB (0,44 %) | 404 758 |
| (cache nóng) theo Cues | 0,018 s | | |

- Phim **trên máy**: Cues trước; không có Cues cho track thì quét tuần tự khối 1 MB (SSD đọc tuần tự rẻ; iPhone chậm
  hơn Mac — ước 2–4 s cho 3 GB, chưa đo). Không dùng cách quét nhảy.
- Phim **stream**: chỉ theo Cues — mỗi dòng phụ đề cần một lần đọc khối (~200 B) và một lần đọc đầu Cluster để lấy giờ
  gốc (dùng `CueTime` + `CueDuration` thì bớt được). Một track 3 giờ ≈ 2 000–4 000 lần đọc nhỏ: ~3 s ở 1 ms/lần (LAN),
  ~10–20 s ở 3–5 ms/lần (Wi-Fi). **Chưa đo trên NAS thật** — task 24 đo; quá 15 s thì dừng và lùi về AC-55.
- Không có Cues cho track phụ đề: quét qua mạng là đọc cả file → không làm (AC-55).

## 5. Cấu trúc cho task 24

- `MatroskaSubtitleReader` ở **Domain**, thuần, đọc qua một nguồn byte `(offset, length) -> bytes`: file trên máy, hoặc
  `RemoteFileClient.readRange` khi stream (SFTP: khối ≤ 128 000, xem báo cáo S1).
- Phần tử cần: EBML header, Segment, SeekHead (tìm Tracks/Cues khi Cues nằm cuối file), Info (TimecodeScale), Tracks
  (TrackNumber, TrackType 0x11, CodecID, Language/LanguageBCP47, Name, CodecPrivate, ContentEncodings → ContentCompression
  algo 0 zlib / 3 header-strip), Cues (CueTime, CueTrack, CueClusterPosition, CueRelativePosition, CueDuration), Cluster
  (Timecode, SimpleBlock, BlockGroup → Block, BlockDuration). Bỏ qua CRC-32 và Void ở mọi chỗ.
- Codec chữ: `S_TEXT/UTF8` → SRT, `S_TEXT/ASS`/`S_TEXT/SSA` → ASS (`CodecPrivate` + dòng), `S_TEXT/WEBVTT` → WebVTT.
  `S_HDMV/PGS`, `S_VOBSUB` → không trích, VLCKit vẽ.
- zlib của Matroska có header 2 byte; framework `Compression` cần deflate trần → bỏ 2 byte đầu.
- Khối phụ đề có lacing: chưa gặp; gặp thì bỏ khối đó và ghi log.
- Cluster cỡ "không biết" (file ghi trực tiếp): đọc tới phần tử cấp 1 kế tiếp.
- Test: fixture nhỏ (vài giây, ffmpeg + mkvmerge + zlib) trong `ShotDexTests/Fixtures`, so với SRT/ASS gốc.

## 6. MP4 và PGS

- **MP4/M4V/MOV có track chữ (mov_text)**: `AVAssetReader` đọc thẳng (track kiểu `sbtl`, 120 dòng, 40 ms, giờ đúng). Không
  cần VLC, không cần parser riêng. Chỉ cho phim trên máy (AVFoundation không đi qua client NAS của ShotDex).
- **PGS**: ffmpeg không có bộ mã PGS (chỉ `dvdsub`), nên chưa tạo được file thử. VLCKit có bộ giải PGS (`avcodec`). AC-23
  cần một file PGS thật có giấy phép dùng thử — còn treo.

## 7. Việc kéo theo

| Chỗ | Đổi |
|---|---|
| FS-23.03 §3 | đã sửa: stream trích qua Cues; không có Cues → như cũ |
| AC-53 | sửa: stream có Cues → Primary + Secondary + dịch trong ≤ 15 s, đọc < 2 MB |
| AC-55 | mới: không có Cues → chỉ Primary, nhãn `In File (Download to use as Secondary or translate)` |
| plan task 24 | `MatroskaSubtitleReader` + mov_text + đo trên NAS thật |
| Chưa biết | NAS thật, iPhone thật, file MKV từ HandBrake/MakeMKV (có Cues cho phụ đề không), file PGS thật |
