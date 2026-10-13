# FS-23.06 — Tiêu chí nghiệm thu

`FS-23.06` · cập nhật 2026-10-14

Phim test: clip tổng hợp 2–5 phút (khung test pattern, tiếng sine — **không mặt người**) dựng bằng ffmpeg ở mỗi
định dạng, lưu ngoài repo như RAW fixtures; một clip 3,2 GB cho đường dài. Server giả: WebDAV (wsgidav) và SMB
(impacket) ở 127.0.0.1 như FS-15. AI giả: máy chủ HTTP cục bộ chuẩn OpenAI trả JSON ghi sẵn.

## 1. Bảng

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | Collections, kho rỗng | mở Utilities | ô **Movies** đứng sau Video Projects, giá trị `0`; chạm → `No Movies` + **Add Movies** | ⚠️ chưa có (`scripts/movies-flow.json`) |
| AC-2 | WebDAV giả có `Dune.2024.2160p.x265.mkv` (310 MB) + `Dune.2024.2160p.x265.en.srt` + `.vi.srt` | From a Server… › chọn file › Add 1 Movie | kho có 1 phim tên `Dune (2024)`, cỡ khớp byte, 2 phụ đề `English · From Server`, `Tiếng Việt · From Server`; Primary = ngôn ngữ đầu của Subtitle Languages | ⚠️ chưa có (`MovieImportTests.sidecarSubtitlesComeAlong`) |
| AC-3 | trình duyệt FS-17 thường, thư mục có 3 ảnh + 1 `.mkv` | giữ lâu `.mkv` | menu có **Add to Movies**; ở duyệt ảnh, `.mkv` không mở bằng chạm như ảnh (FS-17.01 giữ nguyên) | ⚠️ chưa có |
| AC-4 | Files có `clip.flv` | From Files… chọn | file được **sao chép** vào `Movies/<id>/`; bản trong Files còn nguyên | ⚠️ chưa có (`MovieImportTests.filesPickerCopies`) |
| AC-5 | Share sheet của app Files với `clip.webm` | chọn ShotDex | Movies mở tại `clip`; hệ thống không đưa ra extension chia sẻ ảnh | ⚠️ chưa có |
| AC-6 | kho đã có `clip.mp4` | thêm lại đúng file đó từ server khác | `Already in Movies`, 0 byte chép | ⚠️ chưa có (`MovieImportTests.sameHashNotCopiedTwice`) |
| AC-7 | máy trống 3,5 GB, phim 3,2 GB | Add | `Not enough space on this device — about 0.7 GB needed.`; 0 byte chép; hàng đợi dừng | ⚠️ chưa có (`MovieImportTests.needsSizePlusOneGB`) |
| AC-8 | đang chép phim 3,2 GB, tới 1,1 GB thì tắt server giả | bật lại server, Retry | `Can't Reach …` lúc tắt; chép tiếp từ 1,1 GB, tổng byte đọc từ server ≤ 3,2 GB + 1 MB | ⚠️ chưa có (`MovieCopyTests.resumesFromBytesOnDisk`) |
| AC-9 | đang chép, app bị giết | mở lại | hàng tiếp tục chép từ byte đã có; không còn `.part` mồ côi | ⚠️ chưa có (`MovieCopyTests.resumesAfterKill`) |
| AC-10 | 2 phim trong kho | đọc thuộc tính thư mục kho + thư viện Photos | `Movies/` đánh dấu không sao lưu; số tài sản trong Photos không đổi trước/sau khi thêm | ⚠️ chưa có (`MovieStoreTests.excludedFromBackup`) |
| AC-11 | phim 310 MB có 3 phụ đề, 1 bản dịch | Delete › Delete | thư mục `Movies/<id>` không còn; 4 dòng phụ đề xoá; dung lượng trống tăng ≥ 310 MB; file trên server còn | ⚠️ chưa có |
| AC-12 | clip mỗi loại mp4, m4v, mov, mkv, webm, flv, avi, wmv, ts | phát mỗi clip 5 s | cả 9 tới `sẵn sàng`, giờ đã qua ≥ 4 s, có tiếng | ⚠️ chưa có (`scripts/movies-formats.json`) |
| AC-13 | file `.mkv` hỏng phần đầu | phát | `Can't Play This Movie` + một dòng lý do + Close; không nháy đen im lặng | ⚠️ chưa có |
| AC-14 | phim 2:00:00 đã xem tới 47:12 | mở lại | phát từ 47:12 ± 1 s; nhãn `Resumed at 47:12 · Start Over` 5 s; Start Over → 0:00 | ⚠️ chưa có (`MoviePlaybackModelTests.resumeAndStartOver`) |
| AC-15 | MKV 2 track âm thanh (EN AC3 5.1, VI AAC) | Audio › Tiếng Việt | đổi track không dừng phim (giờ không lùi); mở lại phim vẫn track VI | ⚠️ chưa có |
| AC-16 | khoá chạm bật | chạm đúp nửa phải | giờ không đổi; chỉ hiện nút mở khoá | ⚠️ chưa có |
| AC-17 | chế độ máy bay (sim: mạng tắt) | phát 60 s | 0 yêu cầu mạng từ app trong 60 s | ⚠️ chưa có (`scripts/movies-offline.json` + log mạng) |
| AC-18 | Primary EN, Secondary VI, cả 3 vị trí | chụp ở 00:01:05 (cue cả hai cùng hiện) | Top/Bottom: VI trên đỉnh khung; Secondary Above: VI cách EN 8 pt phía trên; Secondary Below: ngược lại; không đè nhau | ⚠️ chưa có (`SubtitleLayoutTests.threePositions` + ảnh) |
| AC-19 | chrome đang hiện, hai phụ đề cùng đáy | chụp | đáy cụm phụ đề ≥ 8 pt trên mép trên kính transport; chrome ẩn → cụm hạ về | ⚠️ chưa có |
| AC-20 | phụ đề sớm 2,0 s | Sync +2,0 s | cue `00:01:05,000` hiện ở giờ phim 00:01:07,0 ± 0,1 s; mở lại phim giữ +2,0 | ⚠️ chưa có (`SubtitleTimelineTests.delayShiftsCues`) |
| AC-21 | SRT tiếng Việt mã Windows-1258 | nhập | chữ có dấu đọc đúng (`Xin chào`), không ký tự lạ | ⚠️ chưa có (`SubtitleDecoderTests.vietnameseWindows1258`) |
| AC-22 | ASS có `{\i1}`, `{\pos(…)}`, `{\an8}` | vẽ | nghiêng giữ, `pos` bỏ, dòng `an8` ở đỉnh khung | ⚠️ chưa có (`SubtitleParserTests.assKeepsItalicAndTop`) |
| AC-23 | MKV có track PGS + SRT tiếng Việt ngoài | Primary PGS, Secondary VI | cả hai hiện; Translate… không liệt kê PGS ở From | ⚠️ chưa có |
| AC-24 | file 310 MB biết trước mã băm | tính mã băm | đúng 16 hex mong đợi; đọc ≤ 128 KB | ⚠️ chưa có (`MovieHashTests.matchesReference`) |
| AC-25 | app Files có `Dune.vi.srt`, kho có `Dune (2024)` và 3 phim khác | Share › ShotDex | sheet `Add Subtitle to…`, `Dune (2024)` được đánh dấu khớp tên; chọn → phim có `Tiếng Việt · Shared` | ⚠️ chưa có |
| AC-26 | `subs.zip` chứa `a.en.srt`, `b.vi.ass`, `readme.txt` | Import File… | gắn 2 phụ đề EN, VI; `readme.txt` bỏ; zip chỉ có `.txt` → `No subtitles in this file.` | ⚠️ chưa có (`SubtitleImportTests.zipTakesSubtitlesOnly`) |
| AC-27 | toàn bộ luồng Movies (thêm, phát, phụ đề, dịch trên máy) | ghi log mạng | 0 yêu cầu tới dịch vụ phụ đề nào; yêu cầu mạng chỉ tới server FS-15 và nhà cung cấp AI đã chọn | ⚠️ chưa có |
| AC-28 | build Release | báo cáo App Thinning cho iPhone 17 | ghi cỡ thêm của VLCKit vào 02 §1 (thay "chưa đo") | ⚠️ chưa có |
| AC-29 | SRT 1.380 cue, AI giả trả đúng số cue | Translate | 1.380 cue, giờ bắt đầu/kết thúc từng cue bằng bản gốc; Secondary tự bật | ⚠️ chưa có (`SubtitleTranslatorTests.keepsTimingAndCount`) |
| AC-30 | AI giả trả thiếu 1 cue ở khối 3 | Translate | khối 3 thử lại 1 lần rồi dịch từng cue; kết quả vẫn 1.380 cue | ⚠️ chưa có (`SubtitleTranslatorTests.wrongCountFallsBackPerCue`) |
| AC-31 | đang dịch 412/1.380 | Cancel, mở lại Translate cùng lựa chọn | `Continue (412 of 1,380)`; chỉ gửi các khối từ cue 413 | ⚠️ chưa có (`SubtitleTranslatorTests.resumesAfterCancel`) |
| AC-32 | chưa cài nhà cung cấp, sim iOS 26.5 không Apple Intelligence | Translate… | Using có Apple Translation; xoá nó khỏi danh sách giả lập → `Set Up AI` + Open AI Settings mở Settings › AI | ⚠️ chưa có |
| AC-33 | Using = Claude | nhìn sheet | dòng "… will be sent to Anthropic."; key không xuất hiện trong log khi gọi | ⚠️ chưa có |
| AC-34 | iPhone thật iOS 18+, gói EN→VI đã tải, máy bay | Translate bằng Apple Translation 200 cue | xong không mạng; 200 cue tiếng Việt | ⚠️ chưa có — cần máy thật (không chạy trên Simulator) |
| AC-35 | Duo ngoài | mở Movies | danh sách, chạm phát được; không có +, Delete, Rename; gập/mở giữ phim, giờ ± 1 s, phụ đề | ⚠️ chưa có — Duo |
| AC-36 | iPhone 17 26.5 + iPhone 16 18.6, sáng + tối | Movies, player, bảng phụ đề, Find, Translate | cùng nút, cùng hành động ở hai nhánh; khớp board ≤ 2 pt (`Tools/design-board compare`) | ⚠️ chưa có — board chưa vẽ |
| AC-37 | VoiceOver bật, player | quét các nút | đọc `Subtitles: English and Vietnamese`, `Audio: English AC3 5.1`, thanh tua bước 10 s | ⚠️ chưa có |
| AC-39 | MKV 5 track: EN TrueHD 7.1 (Default), EN AC3 5.1, EN Commentary AAC Stereo, VI AAC Stereo, JA AC3 5.1 | mở bảng Audio | 5 hàng đúng thứ tự file, mỗi hàng ngôn ngữ · tên · codec · kênh, `Default` ở hàng 1, ✓ ở track đang phát | ⚠️ chưa có (`MovieAudioTrackLabelTests.fiveTracks`) |
| AC-40 | Audio Languages = Tiếng Việt, English; phim mới có EN + VI | mở phim lần đầu | phát track VI; Audio Languages = Original → phát track `Default` | ⚠️ chưa có (`MovieTrackChoiceTests.preferredAudioLanguage`) |
| AC-41 | tiếng sớm 0,30 s | Audio Sync −0,30 s | độ lệch đo được giữa tiếng và hình ≤ 0,05 s; mở lại phim giữ −0,30 s | ⚠️ chưa có (`MoviePlaybackModelTests.audioSyncPersists` + đo trên máy) |
| AC-42 | track 7.1, đường ra tai nghe stereo | phát | có tiếng đủ kênh trộn xuống stereo; dòng chân `Playing as stereo on …` | ⚠️ chưa có — cần máy thật |
| AC-38 | Mac | Space, ←, F, ⌘W | phát/dừng, lùi 10 s, toàn màn, đóng | ⚠️ chưa có — app Mac chưa có code |

**Chưa chứng minh được:** tất cả — chưa có code. AC-34 cần máy thật; AC-35 cần Duo; AC-38 chờ app Mac (FS-18).
