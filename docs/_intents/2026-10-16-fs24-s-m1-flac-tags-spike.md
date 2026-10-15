# Spike S-M1: đọc tag và ảnh bìa FLAC — AVFoundation hay tự đọc khối metadata

| Trường | Giá trị |
|---|---|
| Cho | FS-24 [README §4](../02-functional-spec/FS-24-media-hub/README.md) spike S-M1 · [05 §2](../02-functional-spec/FS-24-media-hub/05-music-library.md) "Đọc tag" · quyết định A9 trong `.planboard/fs24-media-hub/DECISIONS.md` (mặc định: tự đọc) |
| Ngày | 2026-10-16 |
| Máy đo | MacBook Pro M1 Max, macOS 27.0.1, Xcode 27.1; simulator iPhone 17 **iOS 26.5** (CLI chạy bằng `xcrun simctl spawn`). **Chưa đo iOS 27 sim, chưa đo máy thật, chưa đo NAS thật** — macOS 27 dùng cùng bộ AVFoundation với iOS 27 nên coi là bằng chứng gần đúng cho iOS 27 |
| File thử | tự tạo, CC0: sóng sin 5 s (ffmpeg `sine`), ảnh bìa là `testsrc2`/nhiễu màu (không có người). FLAC bằng `flac`/`metaflac` 1.5.0, MP3 bằng `lame` + ID3v2.3/2.4 tự ghi, M4A AAC/ALAC bằng ffmpeg và `afconvert`, WAV/AIFF có RIFF INFO / chunk `ID3`. 14 FLAC ca biên + 1 000 FLAC cho phép đo (782 MB) |
| Code | `probe.swift` (dump AVFoundation, đếm byte qua `AVAssetResourceLoader`), `flacparse.swift` (bản thử bộ đọc FLAC), `mkfix.py` (tạo file) — trong scratchpad của phiên, **không vào repo** |
| Kết luận | **Đi (tự đọc FLAC, A9 giữ nguyên)** — nhưng **không phải** vì AVFoundation đọc sai chữ: trên file lành, AVFoundation đọc đủ Vorbis comment (UTF-8 Việt/Nhật, nhiều ARTIST, LYRICS/UNSYNCEDLYRICS) và ảnh bìa. Lý do là **byte qua mạng** (AVFoundation đọc trọn ảnh bìa trước khi trả tag: TB 734 KB/file so với 8–67 KB) và **độ bền** (một độ dài hỏng làm mất hết tag hoặc cả file). MP3/M4A/AIFF: AVFoundation đủ cho tag. WAV INFO: iOS 26.5 không trả gì |

## 1. AVFoundation trả gì, theo trường và định dạng

`AVURLAsset.load(.metadata)`; ✓ = đúng giá trị, kể cả UTF-8 tiếng Việt/Nhật. Ô có hai ý là macOS 27 / iOS 26.5 khi khác nhau.

| Trường | FLAC (Vorbis) | MP3 ID3v2.3 | MP3 ID3v2.4 | M4A AAC/ALAC (iTunes) | WAV RIFF INFO | WAV / AIFF chunk `ID3` |
|---|---|---|---|---|---|---|
| title | ✓ `vorb/TITLE` | ✓ `TIT2` | ✓ | ✓ `©nam` | ✓ `info-title` / **✗ (0 item)** | ✓ |
| artist | ✓, **nhiều ARTIST = nhiều item** | ✓ `TPE1` | **chỉ giá trị đầu** (2 giá trị NUL-tách → 1) | ✓ `©ART` | ✓ / ✗ | ✓ |
| album | ✓ | ✓ `TALB` | ✓ | ✓ `©alb` | ✗ (`IPRD` bị bỏ) | ✓ |
| album artist | ✓ `ALBUMARTIST` (không commonKey) | ✓ `TPE2` | ✓ | ✓ `aART` | — | ✓ |
| số bài / số đĩa | chuỗi thô `3`, `3/12`, `07`; `TRACKTOTAL`/`DISCTOTAL` riêng | chuỗi `3/12` | chuỗi | `trkn`/`disk` **8 byte nhị phân** (phải tự giải) | ✗ (`ITRK` bị bỏ) | chuỗi |
| năm | ✓ `DATE` (commonKey creationDate), chuỗi thô `2021-05-04` | `TYER` (không commonKey) | `TDRC` | `©day` | ✗ (`ICRD` bị bỏ) | `TYER` |
| thể loại | ✓, nhiều GENRE = nhiều item | `TCON` | ✓ | `©gen` | ✓ / ✗ | ✓ |
| compilation | ✓ `COMPILATION` | `TCMP` | ✓ | `cpil` int8 | — | ✓ |
| lời bài | ✓ `LYRICS` **và** `UNSYNCEDLYRICS` (khoá giữ nguyên) | ✓ `USLT` UTF-16 | ✓ `USLT` UTF-8 | ✓ `©lyr` | — | ✓ `USLT` |
| ảnh bìa | ✓ `METADATA_BLOCK_PICTURE` = byte ảnh; **không có type/MIME/mô tả/cỡ**; 2 ảnh (Back rồi Front) → trả **1** ảnh, đúng Front | ✓ `APIC` (JPEG) | ✓ | ✓ `covr` | — | ✓ |
| `.commonMetadata` | **rỗng (0)** dù item có commonKey — phải lọc `.metadata` | 5 item | 5 | 5 | 0 | 5 |
| thời lượng `AVAsset.duration` | 5,000 / **5,016 s** (iOS làm tròn lên khối 4 096 mẫu) | 5,000 / **5,042** | | 4,975 (ffmpeg) · 5,000 (afconvert) | 5,000 | 5,000 |
| số bit, tần số | `mFormatFlags` 1 = 16 bit, 3 = 24 bit (không tài liệu); 96 kHz ✓ | | | ALAC flags 1 | `mBitsPerChannel` 16 ✓ | ✓ |

Khoá viết thường (`album=`, `tracknumber=`) được AVFoundation đổi thành hoa — ổn. Không có ca nào AVFoundation đọc sai chữ
UTF-8 (xem §6: lần đầu tưởng có, hoá ra lỗi ở công cụ tạo file).

## 2. FLAC ca biên: AVFoundation và bộ đọc tự viết

| File | AVFoundation (macOS 27 = iOS 26.5) | Bộ đọc tự viết |
|---|---|---|
| 16/44,1 đủ tag + bìa 24 KB | ✓ 14 item | ✓ |
| 24/96 + `UNSYNCEDLYRICS` + bìa PNG | ✓ | ✓ 96 000 Hz, 24 bit, 480 000 mẫu |
| bìa PNG 5 MB | ✓ (nạp cả 5 262 254 byte vào RAM khi đọc tag) | ✓ chỉ ghi vị trí; bìa đọc riêng 1 lần khi cần |
| UTF-8 Việt + Nhật, 2 ARTIST, 2 GENRE, mô tả ảnh `Bìa trước 表紙` | ✓ (mô tả ảnh không trả) | ✓ cả mô tả ảnh |
| không tag, không ảnh | ✓ chỉ VENDOR | ✓ |
| 2 ảnh, Back trước Front | 1 ảnh = Front | ✓ cả hai, chọn type 3 |
| PICTURE 2 MB đứng **trước** VORBIS_COMMENT | ✓ nhưng đọc 2,16 MB trước khi có tag | ✓ 2 lần đọc |
| ID3v2 dán trước `fLaC` (một số tagger làm vậy) | **chỉ thấy ID3, mất hết Vorbis comment** | ✓ bỏ qua ID3, đọc Vorbis |
| số comment khai 1 000, thật có 12 | ✓ 12 | ✓ 12 + cảnh báo |
| độ dài comment đầu tiên hỏng (0x7FFFFFF0) | **mất hết comment** (còn VENDOR + ảnh) | mất comment từ chỗ hỏng; giữ phần trước + cảnh báo |
| độ dài khối PICTURE = 16 MB (vượt file) | **lỗi -11849 cho mọi thuộc tính**; `AVAudioFile` cũng không mở được ('dta?') → file không phát được | ✓ đủ tag, cảnh báo, bỏ ảnh |
| 2 byte UTF-8 hỏng trong ARTIST | **ARTIST bị bỏ im lặng** | ✓ giữ, byte hỏng thành U+FFFD |
| file cụt (hết metadata + 20 KB tiếng) | ✓ | ✓ |

## 3. Byte đọc mỗi file — chuyện của NAS

Đếm byte AVFoundation xin qua một `AVAssetResourceLoaderDelegate` trả dữ liệu theo khối 32 KB, 2 ms/khối (giả một NAS
~16 MB/s), dừng khi AVFoundation huỷ yêu cầu — tức là đúng đường AVFoundation sẽ đi khi đọc qua cầu byte `readRange`.
Bộ đọc tự viết đếm byte thật nó xin.

**1 000 FLAC** (40 % bìa 24 KB, 30 % bìa JPEG 2 MB, 10 % 24/96 bìa PNG 44 KB, 10 % không tag, 10 % UTF-8, 1 % bìa 5 MB;
tổng 782 MB):

| Cách | Byte/file TB | Trung vị | Lớn nhất | Lần đọc/file | Cả 1 000 file |
|---|---|---|---|---|---|
| AVFoundation `.metadata` qua resource loader | **734 169** | 65 538 | 5 308 418 | — | **734 MB (94 % thư viện)** |
| Tự đọc, lần đọc đầu 4 KB | **7 782** | 8 192 | 8 192 | 1,90 | 7,8 MB |
| Tự đọc, đầu 8 KB | 11 878 | 12 288 | 12 288 | 1,90 | 11,9 MB |
| Tự đọc, đầu 16 KB | 20 070 | 20 480 | 20 480 | 1,90 | 20 MB |
| Tự đọc, đầu 64 KB | 66 805 | 65 536 | 69 632 | 1,31 | 67 MB |
| Tự đọc, đầu 256 KB (đúng ngân sách spec) | 166 717 | 102 467 | 266 240 | 1,31 | 167 MB |

Lần đọc thứ hai (khi có) là 4 KB để lấy đầu khối sau ảnh bìa. Lấy bìa 5 MB sau đó: thêm đúng 5 262 254 byte, 1 lần đọc,
`cmp` khớp từng byte với ảnh gốc.

Định dạng khác, cũng qua resource loader:

| File | Cỡ | AVFoundation đọc | Ghi chú |
|---|---|---|---|
| MP3 ID3v2.3, bìa 24 KB | 147 KB | 32 KB | |
| MP3 5 phút, `APIC` 2 MB | 11,7 MB | **2,1 MB** | ID3 nằm liền ở đầu, nhưng bìa nằm trong ID3 |
| M4A 5 phút, `moov` cuối, `covr` 2 MB | 7,0 MB | **2,2 MB** (5 yêu cầu: đầu, rồi nhảy tới `moov`) | |
| M4A 5 phút, `moov` đầu (faststart) | 7,0 MB | 2,2 MB | |
| WAV + chunk `ID3` ở cuối | 907 KB | 72 KB (32 KB đầu + 38 KB cuối) | |

Ở **mọi** định dạng, AVFoundation đọc ảnh bìa nhúng cùng lúc với tag — không có cách bảo nó bỏ qua. Spec hiện viết "≤ 256 KB
đầu + ≤ 128 KB cuối, ảnh bìa vượt phần đã đọc → đọc riêng một khối": với FLAC tự đọc thì đúng; với MP3/M4A qua AVFoundation
thì **không giữ được** khi bìa lớn.

## 4. Tốc độ (file trên SSD, cache ấm — đo CPU, không phải mạng)

| Cách | macOS 27 | iOS 26.5 sim |
|---|---|---|
| Tự đọc FLAC, 1 000 file | 0,035–0,043 ms/file (lần chạy lạnh đầu: 0,13–0,22 ms) | 0,043–0,052 ms/file |
| AVFoundation `.metadata`, 1 000 file | 2,05–2,19 ms/file | 1,06–1,09 ms/file |

Qua NAS thời gian do số lần đi-về quyết định: tự đọc là 1–2 lần đọc/file; AVFoundation là 1–5 yêu cầu cộng thời gian
truyền trọn ảnh bìa (2 MB ở 16 MB/s ≈ 125 ms/file → thư viện 5 000 bài có bìa 2 MB ≈ 10 phút chỉ để đọc tag, so với vài chục
giây).

## 5. Gapless — AVFoundation cho thấy gì

| Thông tin | AVFoundation |
|---|---|
| `iTunSMPB` (M4A do `afconvert`/iTunes) | có trong `.metadata`: `itlk/com.apple.iTunes.iTunSMPB` = ` 00000000 00000840 0000026C 0000000000035D54 …` (priming 2 112, padding 620, 220 500 mẫu) |
| Edit list priming (M4A do ffmpeg) | không là metadata; `AVAudioFile.length` = 220 500 (đã cắt), `AVAsset.duration` = 4,975 s |
| Header LAME/Xing (MP3) | không là metadata. macOS 27: `duration` 5,000 s, `AVAudioFile` 220 500. **iOS 26.5: `duration` 5,042 s nhưng `AVAudioFile` 220 500** — tức là bộ giải mã có cắt, chỉ con số thời lượng của asset thì không |
| MP3 không header Xing | 5,042 s, 222 336 frame ở cả hai — không cắt được, đúng như mong đợi |
| FLAC | STREAMINFO tổng mẫu chính xác; iOS 26.5 báo `duration` 5,016 s (làm tròn lên khối) |

Đủ để nói: thời lượng hiển thị nên lấy từ STREAMINFO (FLAC, bộ tự đọc) và `AVAsset.duration` cho phần còn lại (sai ≤ 50 ms,
không đáng kể cho UI). Nối bài gapless thật là việc của S-M2 (phải nghe/đo trên `AVQueuePlayer`), spike này không kết luận.

## 6. Bẫy khi tạo file thử: `metaflac` và locale

Lần chạy đầu cho thấy AVFoundation trả `H## N###i m##a thu` — tưởng là AVFoundation thay mọi byte ngoài ASCII bằng `#`.
Bộ đọc tự viết cho **cùng** kết quả: chính file đã chứa `#`. Shell của agent có `LANG` rỗng, và `metaflac --set-tag` đổi
chữ từ "locale" (C) sang UTF-8, thay ký tự không biểu diễn được bằng `#`. Tạo lại với `--no-utf8-convert` thì cả hai đọc
đúng. **Fixture có chữ ngoài ASCII trong test FS-24 phải tạo với `--no-utf8-convert` (hoặc `LC_ALL=en_US.UTF-8`) và test
phải so với chuỗi gốc**, nếu không test xanh trên dữ liệu đã hỏng.

## 7. Bản thử bộ đọc FLAC

132 dòng (không tính CLI), không thư viện ngoài:

- Nguồn byte là `read(offset, length)` — thay bằng `RemoteFileClient.readRange` là xong; một "cửa sổ" chỉ đọc thêm khi byte
  cần nằm ngoài phần đã có.
- Bỏ qua ID3v2 dán trước `fLaC` (có cờ footer). Duyệt khối tới cờ `last`, trần 128 khối; khối nào khai độ dài vượt file thì
  dừng, giữ những gì đã đọc, ghi cảnh báo.
- STREAMINFO: tần số, số kênh, số bit, tổng mẫu → thời lượng chính xác.
- VORBIS_COMMENT: kiểm từng độ dài với cuối khối, số comment khai sai không làm treo/cấp phát lớn, khoá đổi hoa, giá trị
  UTF-8 khoan dung (byte hỏng → U+FFFD), giữ nhiều giá trị cùng khoá theo thứ tự.
- PICTURE: chỉ đọc phần cố định (type, MIME, mô tả, rộng, cao) và ghi `offset + length` của dữ liệu ảnh; chọn type 3
  (Front), không có thì ảnh đầu. Ảnh đọc sau, một lần.
- SEEKTABLE, PADDING, APPLICATION, CUESHEET: nhảy qua, không đọc.
- Chưa làm (không cần cho v1): `METADATA_BLOCK_PICTURE` base64 trong comment (kiểu Ogg), CUESHEET, ReplayGain (có sẵn trong
  comment, chỉ là đọc thêm khoá).

## 8. Spec nên viết gì

Thay ô ⚠️ CẦN QUYẾT ở [05 §2](../02-functional-spec/FS-24-media-hub/05-music-library.md) bằng:

> - **FLAC: ShotDex tự đọc khối metadata** (STREAMINFO, VORBIS_COMMENT, PICTURE) — *vì AVFoundation đọc trọn ảnh bìa trước
>   khi trả tag (đo: TB 734 KB/file qua mạng so với 8 KB), một độ dài khối hỏng làm mất hết tag hoặc cả file, FLAC có ID3
>   dán trước thì mất hết Vorbis comment* (spike S-M1, 2026-10-16). Lần đọc đầu 8 KB, đọc thêm chỉ khi khối cần nằm ngoài;
>   ảnh bìa ghi vị trí, tải một lần **mỗi album** khi cần cache (không mỗi bài). Khoá: `TITLE`, `ARTIST` (nhiều giá trị →
>   nối `, `), `ALBUM`, `ALBUMARTIST`/`ALBUM ARTIST`, `TRACKNUMBER` (`3`, `03`, `3/12`) + `TRACKTOTAL`/`TOTALTRACKS`,
>   `DISCNUMBER` + `DISCTOTAL`/`TOTALDISCS`, `DATE` (lấy 4 số đầu làm năm), `GENRE`, `COMPILATION`, `LYRICS`, rồi
>   `UNSYNCEDLYRICS`. Thời lượng, tần số, số bit từ STREAMINFO.
> - **MP3, M4A/ALAC, AIFF, WAV có chunk ID3: AVFoundation** (`load(.metadata)`, lọc theo `identifier`; **không dùng
>   `.commonMetadata`** — rỗng với FLAC, thiếu album artist/năm/số bài với mọi định dạng). Tự giải `trkn`/`disk` (8 byte:
>   số ở byte 2–3, tổng ở 4–5). ID3v2.4 nhiều giá trị chỉ lấy được giá trị đầu — chấp nhận.
> - **WAV chỉ có RIFF INFO**: iOS 26.5 không trả gì → tên bài từ tên file như "Thiếu tag". (Tuỳ chọn: tự đọc `LIST/INFO`,
>   ~30 dòng.)
> - Qua mạng với các định dạng đi AVFoundation, ngân sách "≤ 256 KB đầu + ≤ 128 KB cuối" **không giữ được khi bìa nhúng
>   lớn**: AVFoundation đọc cả bìa (đo: MP3/M4A có bìa 2 MB → 2,1–2,2 MB). Hoặc chấp nhận (quét một lần, cache theo
>   `modificationDate` + cỡ), hoặc thêm bộ đọc ID3v2 riêng (định dạng mở, cùng kiểu với FLAC) — ⚠️ CẦN QUYẾT.
> - File AVFoundation không mở được (đo: FLAC có khối PICTURE khai sai độ dài — tag đọc được, phát thì không) vào danh sách
>   `N files can't be played` cùng lý do `Damaged file`.

## 9. Việc kéo theo

| Chỗ | Đổi |
|---|---|
| FS-24.05 §2 | thay ô ⚠️ như §8; thêm ⚠️ mới về bìa lớn trong MP3/M4A qua mạng |
| `.planboard/fs24-media-hub/DECISIONS.md` A9 | đã chứng minh: "Tự đọc khối metadata FLAC — S-M1 2026-10-16: byte qua mạng 734 KB → 8 KB/file, bền với khối hỏng" |
| plan FS-24 | task bộ đọc FLAC (~150 dòng + test) trong app target (không cần vào `ShotDexKit`); test từ 14 ca ở §2, fixture tạo bằng `--no-utf8-convert`, **không** ảnh có người |
| plan FS-24 | đọc tag MP3/M4A qua cùng cầu byte của S-M2 (`AVAssetResourceLoader` + `readRange`) — nếu S-M2 chọn cách khác thì phải đo lại §3 |
| Chưa biết | iOS 27 sim/máy thật (macOS 27 là đại diện), NAS thật (độ trễ mỗi lần đọc), file FLAC thật từ EAC/dBpoweramp/foobar/Mp3tag (thứ tự khối, PADDING lớn, ảnh nhiều MB), Vorbis comment kiểu Ogg (`METADATA_BLOCK_PICTURE` base64), 200 file thật như README §4 đề ra — spike này dùng file tự tạo |
