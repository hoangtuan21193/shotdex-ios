# Spike S1: VLCKit 4 và phát phim từ NAS

| Trường | Giá trị |
|---|---|
| Cho | plan [2026-10-14-fs23-movies](../_plans/2026-10-14-fs23-movies.md) mốc 0, spike S1 · spec FS-23.02 §1, AC-3, AC-28 |
| Ngày | 2026-10-14 |
| Máy đo | MacBook Pro M1 Max, Xcode 27.1, simulator iPhone 17 iOS 26.5 — **chưa đo trên máy thật, chưa đo trên NAS thật** |
| Server thử | trên chính Mac, chạy cho simulator ở 127.0.0.1: SMB impacket (cổng 4451, có mật khẩu), SFTP asyncssh (2222, host key ed25519), WebDAV wsgidav HTTPS tự ký (8443, Basic) |
| Phim thử | 10 phút 720p H.264 2 Mb/s, 2 track tiếng AAC (eng, vie), 1 track SRT, tạo bằng ffmpeg từ `testsrc2` (không có mặt người). Hai bản: MKV 165 MB có Cues ở **cuối file** (byte 165 005 450), MP4 158 MB có `moov` ở **cuối file** |
| Code | harness tạm trong app target + `ShotDexTests`, **không giữ lại** |
| Kết luận | **Đi.** VLCKit 4.0.0-a25 build được cho sim và máy, chỉ vào app target. Phát từ NAS **qua client có sẵn của ShotDex** chạy được trên cả SMB, SFTP, WebDAV: ~2,1 s tới khi phát, tua 50 % ~3,2 s. Không dùng URL `smb://`/`sftp://`/`https://` của VLC |

## 1. Gói, cỡ app, build

| Đo | Trước | Sau | Ghi chú |
|---|---|---|---|
| Gói SPM | — | `github.com/videolan/vlckit` tag `4.0.0-a25`, zip 922 MB, giải nén 2,7 GB | một xcframework cho 9 nền tảng; tải + giải nén lần đầu **5 phút 43 s**, sau đó nằm trong `~/Library/Caches/org.swift.swiftpm` |
| Slice iOS | — | `VLCKit.framework` **động**, nhị phân 45 MB (arm64) | 239 MB thư mục là vì có dSYM |
| App Release, máy thật, chưa ký | 192 MB | **235 MB** (+44 MB) | `Frameworks/VLCKit.framework` 43 MB |
| Nén zip `-9` (gần cỡ tải về) | 107 MB cả app | VLCKit thêm **~19 MB** | chưa phải báo cáo App Thinning — AC-28 vẫn cần báo cáo đó |
| App Debug, simulator | 401 MB | 497 MB (+96 MB) | slice sim gồm arm64 + x86_64 |
| Build không đổi gì (sim) | 7,7 s | 5,5–5,7 s | không chậm thêm: VLCKit là nhị phân, không biên dịch |
| Build Release máy sạch | 356 s | 330 s | trong khoảng dao động |
| Extension, `ShotDexKit` | — | không link VLCKit (`otool -L` 5 extension + kit: 0) | đúng ranh giới `extension-boundary` |

Chưa chạy `Tools/gate` trọn bộ hai lần: phần test không đổi, chỉ app cài vào sim nặng thêm 96 MB. Lượt gate đầu tiên trên
một máy/checkout mới mất thêm ~6 phút tải gói.

**Giấy phép.** `COPYING.txt` là LGPL 2.1; framework động nên người dùng thay được thư viện — đủ điều kiện LGPL khi kèm
ghi công và mã nguồn VLCKit (task 35).

**Privacy manifest.** VLCKit **không có** `PrivacyInfo.xcprivacy`. Nó gọi `stat`/`fstat`/`lstat`/`fstatat` (FileTimestamp),
`fstatfs` (DiskSpace), `NSUserDefaults` (UserDefaults) — manifest của app đã khai ba nhóm này — và `mach_absolute_time`
(**SystemBootTime**, app **chưa khai**). Task 35 phải thêm `NSPrivacyAccessedAPICategorySystemBootTime` · `35F9.1` và
chạy agent `privacy-manifest`.

## 2. Bốn cách cho VLC đọc phim trên NAS

Mỗi ca: mở, chờ tới khi phát qua giây thứ 1,5, tua `position = 0.5`, chờ giờ chạy qua 5:01,5.

| Cách | SMB có mật khẩu | SFTP | WebDAV HTTPS tự ký |
|---|---|---|---|
| **A. URL của VLC** (`smb://` + `:smb-user/:smb-pwd`, `sftp://` + `:sftp-user/:sftp-pwd`, `https://`) | ✗ libsmb2 lỗi với server thử: `Unexpected size of Error reply. Expected 9, got 8` | ✗ TCP nối được, bắt tay SSH hỏng: `Impossible to open the connection` | chỉ chạy khi trả lời **hộp thoại riêng của VLC** "Insecure site — Accept certificate temporarily" rồi hộp đăng nhập HTTP |
| **B. Cầu nối HTTP Range ở 127.0.0.1**, đọc bằng `RemoteFileClient.readRange` | ✓ 2,13 s | ✓ 2,08 s | ✓ 2,43 s |
| **C. `VLCMedia(stream:)`**: một `InputStream` tua được, đọc bằng `RemoteFileClient.readRange` | ✓ 2,23 s | ✓ 2,13 s | ✓ 2,54 s |
| Đối chứng: file trên máy | 2,13 s · tua 3,4 s | | |

Cách A thua ngay cả khi server thật chạy được, vì VLC giữ **mô hình tin cậy riêng**: SFTP đọc `~/.ssh/known_hosts`
(không phải host key người dùng đã tin trong ShotDex), HTTPS hỏi bằng hộp thoại của VLC (không phải dấu vân tay đã lưu),
SMB có bản libsmb2 riêng khác `SMBClient` đã chạy với NAS thật từ FS-15. Mật khẩu cũng phải đưa vào tùy chọn media của VLC.

Cách B và C dùng lại nguyên kết nối, mật khẩu Keychain, host key và chứng chỉ người dùng đã tin; VLC **không bao giờ thấy
mật khẩu**. Log mức debug của VLC không chứa mật khẩu ở mọi ca (đã quét chữ `secret`).

## 3. Tua trong MKV qua mạng — cái bẫy và cách chữa

Lần chạy đầu, cả B và C (và A-WebDAV) tua MKV mất **28–31 s**; MP4 chỉ 3,3 s. Log VLC:

```
seek request to 50.00%
seek: preroll{ track: 1, pts: 0, fpos: 1093 ... }          ← quay về cụm đầu tiên
seek: preroll{ req: 300010501, start-pts: 1, start-fpos: 1093 }
end of video preroll                                        ← 25 s sau
```

Nguyên nhân (đọc `modules/demux/mkv/matroska_segment_seeker.cpp`): demux MKV ghi điểm Cues ở mức **QUESTIONABLE** và chỉ
kiểm lại chúng khi luồng là **fast-seekable**. File trên máy là fast-seekable; HTTP và `imem` (callback) thì không
(`imem-access.c` trả `STREAM_CAN_FASTSEEK = false`). Không kiểm được → Cues bị bỏ → VLC giải mã từ đầu phim tới 5:00.

Chữa: tùy chọn media **`:demux=mkv_trusted`** (module con có sẵn trong VLC, tin Cues ngay). Kết quả:

| Cách | Tua 50 % | Byte đọc từ lúc mở tới khi tua xong |
|---|---|---|
| B, SMB, `mkv_trusted` | **3,23 s** | 50 MB (cầu nối gửi 1 yêu cầu Range mới ở byte 80 239 666) |
| C, SMB, `mkv_trusted` | **3,14 s** | 42 MB |
| C, SFTP, `mkv_trusted` | 3,23 s | 38 MB |
| C, WebDAV, `mkv_trusted` | 3,24 s | 42 MB |
| C, SMB, MP4 `moov` ở cuối | 3,14 s | 40 MB |

Chỉ đặt `mkv_trusted` cho `.mkv`/`.mka`/`.mk3d`/`.webm`. File có Cues hỏng thì tua sai chỗ: khi đó mở lại không có tùy chọn
(VLC tự quét) — task 17 phải có đường lùi này.

## 4. Chọn C

B và C nhanh như nhau. Chọn **C** cho task 17:

- không mở cổng TCP nào trên máy (cầu nối B nghe ở 127.0.0.1 — app khác trên máy cũng gọi tới được, phải thêm token);
- không phải tự viết HTTP (header, Range, 416, HEAD, nhiều kết nối song song);
- một lớp ~100 dòng: `read` chặn luồng input của VLC bằng semaphore trong khi `readRange` chạy, tua qua
  `NSStreamFileCurrentOffsetKey`; một lệnh tới server một lúc (như trình duyệt FS-17).

Giới hạn của C phải nhớ: VLCKit báo cỡ luồng là "không biết" (`UINT64_MAX`) nên VLC tự tua ra cuối để dò; một
`InputStream` đã đóng không mở lại được → mỗi lần mở (phát, lấy khung hình poster) tạo luồng mới. AVI có `idx1` ở cuối và
TS chưa thử qua C (task 16, AC-12). Nếu C vướng, B là đường lùi đã chứng minh.

## 5. Phát hiện ngoài lề

- **`SFTPFileClient.readRange` treo** khi xin một lần ≥ 256 000 byte (128 000 trả về trong 2 ms; 256 000 không bao giờ trả
  và bỏ qua huỷ). Code hiện tại xin tới `chunk * 8` = 256 000 → mọi đọc dài qua SFTP (ảnh xem trước lớn ở FS-17, và phim)
  sẽ treo. Spike đã đọc theo khối 128 000. Đã tách thành việc riêng (chip "Fix SFTP readRange hang"); task 17 phụ thuộc nó.
- Throughput trên loopback: SMB ~12 MB/s qua cầu nối khối 1 MB, đủ cho phim 2 Mb/s; phim 4K remux 60–80 Mb/s cần đo trên NAS thật.
- `player.audioTracks` / `textTracks` của VLCKit 4 trả đủ 2 track tiếng có tên ngôn ngữ (`Track 1 - [English]`) và track SRT
  trong MKV, qua cả đường C — đủ cho bảng Audio (AC-15, 39) và cho S2.

## 6. Việc kéo theo

| Chỗ | Đổi |
|---|---|
| plan task 16 | thêm gói VLCKit `exactVersion 4.0.0-a25` vào app target (spike đã gỡ ra, để checkout của phiên khác không phải tải 922 MB trước khi cần) |
| plan task 17 | `RemoteMovieStream` (cách C) thay `RangeStreamServer`; `:demux=mkv_trusted` cho họ Matroska + đường lùi; khối SFTP ≤ 128 000 |
| plan task 35 | ghi công LGPL + `SystemBootTime 35F9.1` trong manifest |
| FS-23.02 §1 | cỡ thêm đã đo (bản thô), cách đọc từ NAS |
| AC-28 | vẫn cần báo cáo App Thinning trên máy có ký — số ở mục 1 là đo thô |
| Chưa biết | NAS thật (Synology/QNAP, SMB3 mã hoá), phim 4K, máy thật, AVI/TS qua C, Plex (đi URL HTTP thẳng của Plex — S3) |
