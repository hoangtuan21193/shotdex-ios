# Spike S3: Plex trong mạng nhà

| Trường | Giá trị |
|---|---|
| Cho | plan [2026-10-14-fs23-movies](../_plans/2026-10-14-fs23-movies.md) mốc 0, spike S3 · spec FS-23.07, AC-47…51, AC-56 |
| Ngày | 2026-10-14 |
| Máy chủ | Plex Media Server 1.43 trên Windows, cùng mạng LAN với Mac đo; người dùng là chủ máy chủ, không có Plex Pass trong phép đo |
| Máy đo | MacBook Pro M1 Max qua Wi-Fi; Python `urllib` + Swift `URLSession` (cấu hình như app) — **chưa đo từ iPhone, chưa đo khi ở ngoài nhà** |
| Dữ liệu thật | 178 phim + 141 series; chỉ ghi số tổng hợp, không ghi tên phim, IP public, token |
| Code | script trong scratchpad, **không giữ lại** |
| Kết luận | **Đi.** Đăng nhập bằng mã, danh sách máy chủ, thư viện, phát bản gốc bằng Range, poster, ghi/đọc chỗ đang xem đều chạy trên Plex thật bằng API công khai, không cần Plex Pass. Kiểm thêm cho S2: 27/27 MKV có phụ đề chữ đều có Cues cho mọi track phụ đề chữ |

## 1. Đăng nhập bằng mã

- `POST https://plex.tv/api/v2/pins?strong=false` với `X-Plex-Product`, `X-Plex-Client-Identifier` (UUID cố định
  mỗi máy), `X-Plex-Device-Name` → mã **4 ký tự**, `expiresIn` **900 s**, 1,9 s.
- Người dùng nhập ở plex.tv/link; app hỏi lại `GET /api/v2/pins/{id}` mỗi 2 s → có `authToken` (20 ký tự). Lần đo:
  63 s, 23 lần hỏi.
- Tài khoản có thêm một thiết bị (tên lấy từ `X-Plex-Device-Name`); gỡ ở plex.tv › Authorized Devices. Mã hết hạn → tạo
  mã mới (FS-23.07 §1 đã ghi).

## 2. Máy chủ và đường kết nối

`GET https://clients.plex.tv/api/v2/resources?includeHttps=1&includeRelay=1&includeIPv6=1` (0,36 s) → 1 máy chủ,
`owned=true`, `accessToken` trùng token người dùng (máy chủ của mình), 4 đường:

| Đường | `local` | URLSession, 5 lần | Ghi chú |
|---|---|---|---|
| `https://192-168-…plex.direct:32400` | ✓ | **200 · 23–39 ms** | chứng chỉ thật, hệ thống tự tin; lần đầu ~1 s vì phân giải DNS plex.direct |
| `https://10-5-…plex.direct:32400` | ✓ | hết giờ 6 s ×5 | địa chỉ của một card mạng khác trên máy chủ — plex.tv vẫn báo `local` |
| `https://<IP public>…plex.direct:32499` | — | hết giờ ×5 | từ trong nhà không quay vòng ra IP public được (router không NAT loopback) |
| relay `https://…plex.direct:8443` | — | hết giờ ×5 (curl: 1 lần lỗi chứng chỉ, 1 lần 200) | chập chờn; relay của Plex còn giới hạn băng thông |
| `http://<IP LAN>:32400` (không có trong danh sách) | — | **200 · 11–19 ms** | được vì máy chủ không bắt HTTPS (`httpsRequired=false`); ATS của app đã có `NSAllowsLocalNetworking` |

- `publicAddressMatches=false` dù Mac đang ở cùng nhà → **không dùng cờ này để đoán "đang ở nhà"**.
- Chọn đường: thử **song song**, đường `local` trước, lấy đường trả lời đầu tiên, nhớ lại cho lần sau; hết giờ ngắn
  (~3 s) cho mỗi đường. Cách này thắng cả hai đường chết trong danh sách mà không bắt người dùng chờ 6 s mỗi đường.

## 3. Thư viện

- `/library/sections` 20 ms: 1 thư viện phim (agent Plex Movie), 1 thư viện series.
- `/library/sections/{id}/all?type=1` trang 200 mục: 178 phim trong **119 ms, 430 KB JSON** → lấy theo trang, chỉ giữ
  trường cần.
- Container: MKV 226, MP4 103, MPEG-TS 2. Codec hình: HEVC 165, H.264 165. Cỡ file: trung vị **4,5 GB**, lớn nhất **87,7 GB**.
- **Không phim nào nhiều phần** (part) — để chưa xử lý, ghi log nếu gặp.
- **10/178 phim có nhiều bản** (`Media` > 1, vd 1080p + 4K) → người dùng chốt (14/10): Play bản nét nhất, Download mở
  danh sách bản kèm cỡ (FS-23.07 §2–3, AC-56).
- Tập phim không có `year` (82 mục) — Grid ghi `S01E04` như spec.
- Một phim (`/library/metadata/{key}`) có đủ thứ Grid/List/menu cần: `title`, `year`, `summary`, `Genre`, `duration`,
  `thumb`, `art`, `viewOffset`, `viewCount`, `Media/Part` (`key`, `size`, `container`, `file`), `Stream` (mỗi track tiếng
  và phụ đề kèm `languageCode`; phụ đề rời có `key` riêng).

## 4. Phát và tải bản gốc

| Phép thử (phim 4K 54 GB) | HTTP LAN | HTTPS plex.direct |
|---|---|---|
| `Range: bytes=0-1023` | 206, `Accept-Ranges: bytes`, 67 ms | 206, 69 ms |
| 4 KB cuối file | 206, 17 ms | 206, 48 ms |
| 64 MB giữa file | **217 Mb/s** | **227 Mb/s** |
| không token | 401 | 401 |
| token ở query `?X-Plex-Token=` | 206 | 206 |
| `?download=1` | 206 + `Content-Disposition` | như trên |

- Đủ cho 4K remux (60–80 Mb/s) qua Wi-Fi của Mac; iPhone chưa đo.
- **Token đi header, không đi URL.** VLC không đặt được header tuỳ ý, nên đưa URL cho VLC là phải nhét token vào query →
  token vào log của VLC. Thay vào đó Plex dùng **cùng đường đọc như NAS** (báo cáo S1, cách C): một nguồn byte gọi
  `URLSession` với Range + header, đưa vào `VLCMedia(stream:)`. Một đường cho mọi nguồn; VLC không thấy token.
- Tải về: cùng URL part, `URLSession` nền nhận header trong `URLRequest` → hợp với AC-54 (Plex tải nền).
- Poster: `/photo/:/transcode?width=480&height=720&url=<thumb>` **64 KB** (240×360: 21 KB), ảnh gốc 1,1 MB → Grid lấy
  bản 480×720, giữ trong `Caches/MovieArt`.

## 5. Đồng bộ chỗ đang xem (đã hỏi người dùng trước khi ghi)

- Đọc: `viewOffset` (ms), `viewCount`, `lastViewedAt` trong metadata; 30 phim đang dở, 119 đã xem.
- Ghi: `GET /:/timeline?ratingKey=…&key=/library/metadata/…&state=stopped&time=<ms>&duration=<ms>&identifier=com.plexapp.plugins.library`
  → **200, 55 ms**; đọc lại thấy vị trí mới ngay. Ghi trả vị trí cũ → đúng, `viewCount` không đổi.
- Hệ quả thấy được: `lastViewedAt` đổi → phim nhảy lên đầu Continue Watching của Plex. Đồng bộ chỉ được gửi khi người
  dùng thật sự xem (không gửi lại vị trí cũ chỉ để "giữ cho khớp").
- Đánh dấu đã xem / chưa xem (`/:/scrobble`, `/:/unscrobble`): **chưa thử** để khỏi đổi dữ liệu người dùng — task 33 thử
  trên Plex giả.

## 6. Kiểm thêm cho S2 trên phim thật

30 MKV lấy rải trong thư viện, chỉ đọc đầu file + Tracks + Cues bằng Range:

| | Số |
|---|---|
| file có phụ đề chữ | 27 |
| file mà **mọi** track phụ đề chữ đều có Cues | **27** |
| file có phụ đề chữ nhưng không track nào có Cues | 0 |
| file có phụ đề ảnh | 11 |
| track: `S_TEXT/UTF8` / `S_HDMV/PGS` / `S_TEXT/ASS` / `S_VOBSUB` | 267 / 25 / 3 / 4 |
| byte đọc để biết có trích được không (đầu + Tracks + Cues) | trung vị 366 KB, tối đa 1,5 MB, 0,23 s |

Kết luận S2 (trích qua Cues khi stream) đứng được trên phim ngoài đời. Có file PGS thật để thử AC-23 trên máy chủ này.

## 7. Việc kéo theo

| Chỗ | Đổi |
|---|---|
| FS-23.07 §1–3 | đã sửa: `accessToken` theo máy chủ, chọn đường song song, đường đọc chung, nhiều bản |
| AC-56 | mới: nhiều bản — Play bản nét nhất, Download chọn bản |
| plan task 30–31 | chọn đường song song; nguồn byte URLSession Range + `VLCMedia(stream:)`; trang 200 mục |
| plex.tv giả cho test | ghi lại hình dạng JSON của `pins`, `resources`, `sections/all`, `metadata` (đã có ở đây) |
| Chưa biết | ở ngoài nhà (đường Internet, relay), máy chủ được chia sẻ (`allowSync`, `accessToken` riêng), iPhone thật, phim nhiều phần |
