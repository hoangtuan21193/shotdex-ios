# FS-23 — Movies: phim offline, phụ đề đôi, dịch phụ đề bằng AI

`FS-23` · tier A (kho) + C (player) · mã: chưa có (đề xuất `ShotDex/Features/Movies/`, `ShotDex/Domain/Movies/`,
`ShotDex/Data/Movies/`) · test: chưa có (đề xuất `ShotDexTests/Movie*Tests.swift`) · cập nhật 2026-10-14

**Một câu:** Collections › Utilities › **Movies** giữ phim người dùng chép vào ShotDex (ngoài Photos, ngoài iCloud),
phát mọi định dạng thường gặp kể cả MKV/FLV/AVI, nhận phụ đề người dùng tự tải, hiện hai phụ đề cùng lúc, và dịch
phụ đề sang thứ tiếng khác bằng AI trước khi lên máy bay.

Nguồn: [intent 2026-10-14-offline-movies](../../_intents/2026-10-14-offline-movies.md) (accepted, Q1–Q13 đã trả lời).

Board (vẽ 2026-10-14, sáng + tối): iPhone `PH_Movies` (1/5) · `PH_MoviesAdd` (2/5) · `PH_MoviePlayer` (3/5, ngang) ·
`PH_MovieSubtitles` (4/5) · `PH_MovieTranslate` (5/5) · `PH_MovieAudio` (bảng âm thanh) · `PH_MovieSubtitleAdd` (Share › chọn phim) · `PH_SettingsAI` ·
`PH_SettingsAIProvider`; iPad `IP_…` cùng bộ; Duo trong `DI_…` cùng bộ, Duo ngoài `DC_Movies` · `DC_MoviePlayer` ·
`DC_MovieSubtitles` · `DC_MovieAudio` · `DC_SettingsAI`; Mac `MAC_…` cùng bộ (Settings là tab AI). Lối vào: ô/hàng **Movies** sau Video
Projects trên `*_Collections` và sidebar iPad/Mac; hàng **AI** trên `*_Settings`.

## Các phần

| # | Phần | Trả lời |
|---|---|---|
| 01 | [Kho phim và đưa phim vào](01-library-and-import.md) | lối vào, danh sách, nguồn (server, Files, Share/AirDrop), tải, dung lượng, xoá |
| 02 | [Player](02-player.md) | engine VLCKit, định dạng, transport, bảng âm thanh (track, Audio Sync, ngôn ngữ ưu tiên), nhớ chỗ xem, thiết bị |
| 03 | [Phụ đề](03-subtitles.md) | track có sẵn, nhập file, Share/AirDrop, hai phụ đề, vị trí, cỡ chữ, lệch giờ; không tìm trên mạng |
| 04 | [Dịch phụ đề bằng AI](04-ai-translation.md) | chọn nhà cung cấp, chia đoạn, chạy dở, lưu bản dịch |
| 05 | [Dữ liệu](05-data.md) | thư mục kho, bảng phim, bảng phụ đề, Keychain |
| 06 | [Tiêu chí nghiệm thu](06-acceptance-criteria.md) | AC-1…AC-42 |

Mục AI trong Settings (dùng chung với AI Search) là FS riêng: [FS-08.07](../FS-08-settings/07-ai-providers.md).

## 1. Người dùng cần gì

- Chép vài bộ phim (1–10 GB mỗi bộ) từ NAS hay Files vào máy trước chuyến bay, xem lúc không có mạng.
- Phim không làm bẩn thư viện ảnh: không vào Photos, không lên iCloud, không ăn dung lượng iCloud.
- Xem kèm phụ đề đúng bản phim, và **hai phụ đề cùng lúc** (ví dụ tiếng Anh + tiếng Việt) để học tiếng.

## 2. Phạm vi

**Có:**
- Kho phim trong thư mục riêng của app, đánh dấu không sao lưu; nguồn: connection FS-15, app Files, Share sheet/AirDrop.
- Phát MP4, MOV, M4V, MKV, WebM, FLV, AVI, WMV, MPEG-TS; chọn track âm thanh như Infuse (ngôn ngữ, codec, kênh,
  Audio Sync, ngôn ngữ ưu tiên); nhớ chỗ đang xem.
- Phụ đề: track trong file, file SRT/ASS/SSA/VTT/zip người dùng tự tải rồi đưa vào; tối đa 2 phụ đề cùng lúc.
- Dịch một phụ đề sang ngôn ngữ khác bằng AI người dùng chọn (FS-08.07), lưu thành phụ đề thứ hai.

**Cố ý không có:**
- Tải từ link HTTP, YouTube, dịch vụ streaming; bẻ DRM — *vì ToS, bản quyền, App Store (intent câu 3).*
- Poster, tóm tắt, diễn viên lấy từ TMDB/IMDb — *vì mục đích là xem offline, không phải quản lý bộ sưu tập.*
- AI tạo phụ đề từ tiếng trong phim — *intent câu 12, làm sau.*
- Ảnh offline — *intent riêng `offline-photos`.*
- Tìm và tải phụ đề trên mạng — *vì nguồn có API chỉ cho dùng không đăng nhập khi trả phí hằng tháng (03 §6).*
- AirPlay video — *VLCKit không có AirPlay kiểu AVPlayer; trên máy bay không cần. Âm thanh vẫn theo tuyến hệ thống.*
- Hai engine (AVPlayer cho MP4, VLCKit cho phần còn lại) — *vì phụ đề tự vẽ và transport phải giống nhau mọi file.*

## 3. Ràng buộc chung

| Mặt | Ràng buộc |
|---|---|
| Riêng tư | phim, vị trí xem không rời máy; chữ phụ đề chỉ đi tới AI ngoài máy khi người dùng chọn AI đó ([NF-03](../../04-non-functional-design/NF-03-privacy-and-security.md) §2c mới) |
| Đĩa | trước khi chép: cỡ file + 1 GB phải còn trống, như FS-17.02; thiếu → báo số GB cần, không bắt đầu ([NF-02](../../04-non-functional-design/NF-02-memory-and-resources.md)) |
| Bộ nhớ | chép theo khối 1 MB, không bao giờ đọc cả phim vào RAM; mã băm chỉ đọc 64 KB đầu + 64 KB cuối |
| Dữ liệu người dùng | bảng riêng, không cột nào trong `photo_metadata` ([BD-02](../../01-basic-design/BD-02-database-design.md)) |
| Dependency | VLCKit (LGPL 2.1, đã duyệt ở intent câu 2); Acknowledgements ghi VLCKit + đường tới mã nguồn |
| Thiết bị | iPhone 402×874 · iPad 1376×1032 · Duo trong 951×669 · Duo ngoài 466×678 (chỉ phát) · Mac |
| iOS | 17 tối thiểu; iOS 26 và trước 26 làm cùng việc; Apple Translation chỉ hiện từ iOS 18 |

## 4. Đã quyết ở bước spec (người dùng, 2026-10-14)

1. Không tìm phụ đề trên mạng; người dùng tự tải rồi đưa vào ([03 §6](03-subtitles.md#6-không-tìm-phụ-đề-trên-mạng)).
2. VLCKit 4.0 alpha, ghim bản, xét lại trước khi phát hành ([02 §1](02-player.md#1-engine)).
3. Lối vào là ô **Movies** trong Utilities ([01 §1](01-library-and-import.md#1-lối-vào)).
4. Settings thêm mục thứ 10 **AI**; trên Duo trong cột mục cuộn ([FS-08.07 §1](../FS-08-settings/07-ai-providers.md#1-chỗ-đặt)).
5. AI Search không dùng cloud ([FS-08.07 §5](../FS-08-settings/07-ai-providers.md#5-ai-search)).
6. NF-03 thêm ngoại lệ thứ ba cho AI do người dùng chọn ([05 §4](05-data.md#4-riêng-tư-và-bản-khai)).
