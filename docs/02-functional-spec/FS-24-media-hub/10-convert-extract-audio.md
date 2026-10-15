# FS-24.10 — Convert và Extract Audio (Movies › Utilities)

`FS-24.10` · tier A (sheet chọn) · mã: chưa có · board: ô **Convert**, **Extract Audio** trên `PH_Movies`/`IP_Movies`/`DI_MoviesHome`/
`MAC_MoviesHome`; sheet Convert iPhone `PH_Convert` · iPad `IP_Convert` · Duo `DI_Convert` / `DC_Convert` · Mac `MAC_Convert` (tweak `progress`); sheet Extract Audio iPhone `PH_ExtractAudio` · iPad `IP_ExtractAudio` · Duo `DI_ExtractAudio` / `DC_ExtractAudio` · Mac `MAC_ExtractAudio` (tweak `custom`, `progress`) · cập nhật 2026-10-16

**Một câu:** đổi một phim/clip người dùng có sang MP4 để lưu vào Photos, gửi đi hay thu nhỏ bản giữ trên máy; và tách
tiếng của nó thành một bài trong Music (playlist From Movies), dùng được làm nhạc nền Video Studio.

## 1. Convert

- Vào: ô Convert (chọn một hay nhiều phim/clip) hoặc menu phim › Convert…. Chỉ file **trên máy** (Kept hoặc chép thẳng);
  phim stream → nút **Keep on iPhone First** trong sheet.
- Sheet Convert (board `*_Convert`), mặc định đánh dấu ●:

| Mục | Lựa chọn |
|---|---|
| Format | ● **MP4 · H.264** (mọi máy mở được) · MP4 · HEVC (nhỏ hơn ~40%) |
| Size | ● Original · 1080p · 720p (không phóng to bản nhỏ hơn) |
| Audio | track đang chọn của phim (FS-23.02 §3b) · AAC stereo 192 kbps |
| Then | ● **Save to Photos** · Share… · **Replace Kept Copy** (chỉ phim đã Keep; thay file trong kho để lấy lại chỗ) |

- Dòng ước tính dưới bảng: `About 2.1 GB · 48 GB free` (mono-digit). Cần ước tính + 1 GB trống, thiếu → câu như Keep, không bắt đầu.
- MP4/MOV/M4V: đọc–ghi bằng AVFoundation, phần cứng mã hoá. MKV/AVI/FLV/WebM/WMV/TS: AVFoundation không đọc được.
  **Chốt 2026-10-16 (A13):** giải mã bằng bộ giải mã phim đang có (VLCKit, FS-23) rồi mã hoá bằng AVFoundation; spike **S-M3**
  trước `/plan` phải chứng minh VLCKit 4 alpha đưa được khung hình + tiếng ra ngoài với tốc độ ≥ 1× trên iPhone 15. Spike hỏng
  thì quay lại hỏi người dùng (PLAN: đi chệch quyết định là dừng và hỏi); phương án lùi đã biết là v1 chỉ nhận MP4/MOV/M4V,
  file khác hàng mờ + `This format can't be converted yet.` Intent ghi "MKV/AVI qua VLCKit nên chậm hơn".
- Tiến độ: dòng trong On This iPhone + thẻ ở đầu trang chủ Movies `Converting Dune · 34% · about 6 min left`; một việc
  một lúc, việc sau xếp hàng.
- Rời app: iOS 26 chạy tiếp bằng tác vụ xử lý tiếp tục (như FS-22.02 §3); trước 26 dừng và **làm lại từ đầu** khi mở
  app (bộ ghi MP4 không nối tiếp được), dòng ghi `Keep ShotDex open to finish`.
- **Cancel** (thẻ, hoặc dòng tiến độ): dừng ≤ 1 s, xoá file dở, file gốc không đổi.
- Replace Kept Copy chỉ thay file gốc sau khi bản mới ghi xong và đọc lại được; hỏng giữa chừng thì bản cũ nguyên vẹn.
  Chỗ đang xem, phụ đề rời, bản dịch giữ; track âm thanh khác (nếu có) mất — sheet ghi rõ `Other audio tracks are removed.`
- Phụ đề không nung vào hình ở v1 (Save to Photos không mang phụ đề) — *board chưa có lựa chọn này.*
- File có DRM (m4v iTunes cũ): `This video is protected and can't be converted.`

## 2. Extract Audio

- Vào: ô Extract Audio (chọn phim/clip) hoặc menu phim › Extract Audio…. Cùng luật "chỉ file trên máy" như Convert.
- Sheet (board `*_ExtractAudio`): **Track** (khi có > 1 track tiếng) · **Range** ● Whole Movie · Custom (Start, End, bước 1 s) ·
  **Name** (mặc định tên phim/clip). Nút chính **Extract**.
- Định dạng ra: track AAC → chép nguyên không mã hoá lại (nhanh, không mất chất); codec khác → AAC 256 kbps M4A.
- Kết quả: một bài trong thư viện Music, nguồn Files, đã Keep; tag: title = Name, artist = `From Movies`, album = tên phim,
  ảnh bìa = poster/khung 10%; tự thêm vào playlist **From Movies** (tạo khi chưa có). Dùng ngay được trong Video Studio.
- MKV/AVI…: cùng đường A13 và cùng spike S-M3 ở §1.
- Cancel, hết chỗ, rời app: như Convert. Phim không có track tiếng: ô mờ `This video has no sound.`

## 3. Pháp lý

- Chỉ file người dùng đã có trong Movies; không có ô dán link, không tải từ YouTube/dịch vụ streaming (intent, Constraints).
- Kết quả ở lại trên máy; không gửi đi đâu trừ khi người dùng chọn Share….
