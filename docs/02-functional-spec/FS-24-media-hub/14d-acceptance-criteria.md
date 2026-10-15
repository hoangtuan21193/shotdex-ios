# FS-24.14d — Tiêu chí nghiệm thu (4/4): các quyết định chốt 2026-10-16

`FS-24.14d` · AC-102…AC-137 · dữ liệu test: [14 đầu file](14-acceptance-criteria.md) · nguồn quyết định:
`.planboard/fs24-media-hub/DECISIONS.md` (D1–D11, A1–A18) · cập nhật 2026-10-16

AC ở đây **thêm** cho các quyết định; AC cũ đổi theo quyết định giữ số của mình (AC-5, 6, 8, 16, 19, 40, 53, 64, 77, 86, 98).
Dung lượng trống và PhotoKit giả lập bằng lớp thay được trong test (như `MovieDownloadTests.needsSizePlusOneGB`); lỗi iCloud
giả bằng nguồn tài nguyên PhotoKit giả trả lỗi theo id. Ảnh test là phong cảnh (memory `no-face-photos-in-tests`).

## Movie Audio in Background (D2)

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-102 | cài mới; iPhone 26.5, iPhone 18.6, iPad 27.0, Duo trong | Settings › Playback | có hàng công tắc `Movie Audio in Background`, **bật**; chân hàng đúng câu ở [06 §6](06-music-player.md); hàng `Clear Listening History…` dưới nó | ⚠️ chưa có — `SettingsPlaybackTests.movieAudioInBackgroundDefaultsOn` + `scripts/hub-settings-playback.json` |
| AC-103 | công tắc bật; PiP tự động của hệ thống tắt; Dune (WebDAV) đang phát ở 10:00 | đưa app xuống nền (`simctl launch` app khác) 60 s, rồi mở lại ShotDex | thông tin Now Playing hệ thống của Dune, giờ 11:00 ± 2 s; mở lại: hình hiện ở giờ đang phát ± 1 s, không tua lại 10:00; chỗ đang xem đã ghi ≥ 10:50 | ⚠️ chưa có — `scripts/movie-background-audio.json` + `MovieBackgroundAudioTests.keepsPlaying`; khoá máy: máy thật |
| AC-104 | như AC-103, app đang ở nền | lệnh từ xa Pause, Play, +10 s, Next | dừng; phát; giờ +10 ± 0,5 s; Next tắt (không làm gì) | ⚠️ chưa có — `MovieNowPlayingTests.backgroundCommands` |
| AC-105 | công tắc **tắt**; Dune phát ở 10:00 | đưa app xuống nền 60 s | phim dừng ở 10:00 ± 1 s như FS-23.02 §4; giờ Now Playing không chạy | ⚠️ chưa có — `MovieBackgroundAudioTests.offPausesLikeToday` |
| AC-106 | PiP tự động của hệ thống bật; công tắc bật, rồi tắt | rời app khi phim đang phát | cả hai lần vào **PiP** như hôm nay, không vào đường chỉ tiếng | ⚠️ chưa có — `MovieBackgroundAudioTests.pipUnchanged`; PiP: máy thật |
| AC-107 | công tắc bật, phim đang chạy chỉ tiếng ở nền | ngắt âm thanh bắt đầu, rồi kết thúc kèm "được tiếp tục"; rồi đường ra cũ biến mất | dừng; phát tiếp; dừng — cùng luật nhạc (06 §6) | ⚠️ chưa có — `MovieBackgroundAudioTests.interruptionAndRouteLoss` |

## Keep ảnh thư viện Photos — hỏi mỗi lần (D7)

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-108 | album Photos `Kyoto` 120 ảnh, chưa Keep ảnh nào | menu album › Keep on iPhone | ≤ 1 s hộp hiện; tiêu đề `Keep 120 Photos on iPhone`; ba hàng **đúng thứ tự** `Originals — full resolution (≈ X)` · `Viewing Copies — 2732 px on the long side, HEIC (≈ Y)` · `Cancel`; X = tổng cỡ tài nguyên gốc giả, Y = 120 × 1,2 MB, một chữ số thập phân | ⚠️ chưa có — `KeepPhotosTests.dialogRowsAndEstimates` + `scripts/keep-photos-dialog.json` (dump) |
| AC-109 | như AC-108, đã Keep `Kyoto` | Keep on iPhone trên album Photos thứ hai, rồi trên 1 ảnh lẻ | hộp hiện **cả hai lần** (`Keep 1 Photo on iPhone` lần sau); không có cài đặt nào nhớ lựa chọn | ⚠️ chưa có — `KeepPhotosTests.asksEveryTime` |
| AC-110 | hộp của AC-108 | chạm Cancel | 0 dòng thứ đã Keep, 0 mục hàng đợi, 0 byte trong `Kept/Photos/`, 0 yêu cầu tài nguyên PhotoKit | ⚠️ chưa có — `KeepPhotosTests.cancelKeepsNothing` |
| AC-111 | 10 ảnh Photos có sẵn trên máy, trống 20 GB | Keep › Originals, rồi chế độ máy bay | 10 file trong kho, mã băm bằng tài nguyên gốc PhotoKit; tổng byte trong ± 25% của X; Edit mở ảnh đủ cỡ gốc, Export ra file cỡ gốc, không mở `OriginalDownloadModal` | ⚠️ chưa có — `KeepPhotosTests.originalsAreByteExact` + `scripts/keep-photos-offline.json` |
| AC-112 | 10 ảnh 4032×3024 + 1 ảnh 2000×1500 | Keep › Viewing Copies | 10 file HEIC 2732×2049, 1 file 2000×1500 (không phóng to); EXIF ngày chụp, máy, ống giữ; tổng byte trong ± 25% của Y; offline Viewer mở được, VoiceOver ô `Kept on iPhone, viewing copy`; Edit offline → `OriginalDownloadModal` như hôm nay, không lỗi mới | ⚠️ chưa có — `KeepPhotosTests.viewingCopiesSizeAndExif` |
| AC-113 | trống 4,0 GB; Originals ≈ 8,2 GB, Viewing Copies ≈ 0,5 GB | chọn Originals | alert `Not enough space on this iPhone` · "Originals need about 8.2 GB plus 1 GB free; 4.0 GB is free." · `Keep Viewing Copies (0.5 GB)` · `Cancel`; 0 byte trước khi chọn; Keep Viewing Copies → bản xem vào hàng đợi; Cancel → 0 dòng | ⚠️ chưa có — `KeepPhotosTests.originalsDontFitOffersViewingCopies` |
| AC-114 | trống 1,2 GB; Viewing Copies ≈ 0,5 GB | chọn Viewing Copies | `Not enough space on this iPhone — about 0.3 GB needed.`; 0 byte, không hàng đợi; không tự chuyển bản | ⚠️ chưa có — `KeepPhotosTests.nothingFits` |
| AC-115 | 20 ảnh chỉ trên iCloud, Keep › Originals; PhotoKit giả trả lỗi ở ảnh 8 và 15 | chạy hết hàng đợi; rồi Retry Keep | 18 ✓, 2 ô `exclamationmark.icloud`; hàng đợi không dừng ở ảnh 8; không hộp lỗi; dòng `Kept 18 of 20 · 2 couldn't download`; không file dở trong kho; Retry Keep yêu cầu **đúng 2** ảnh đó, bản gốc, không hỏi lại | ⚠️ chưa có — `KeepPhotosTests.iCloudFailureMidway` |
| AC-116 | album `Kyoto` đã Keep bản xem (10 ảnh) | thêm 2 ảnh vào album, mở lại app; rồi Keep on iPhone › Originals | lần làm mới: 12 bản xem, **không** hỏi; hộp sau ghi `Keep 12 Photos on iPhone`; xong: 12 bản gốc, 0 file bản xem còn; Keep lần nữa → không hộp, menu `Kept on iPhone` | ⚠️ chưa có — `KeepPhotosTests.albumRemembersChoiceAndUpgrades` |
| AC-117 | chọn 3 ảnh NAS Home + 5 ảnh Photos | Keep on iPhone | hộp `Keep 5 Photos on iPhone`, tin nhắn `3 photos from NAS Home are always kept as originals.`; Viewing Copies → 5 HEIC + 3 bản gốc NAS; lặp lại với Cancel → 0 trong 8 | ⚠️ chưa có — `KeepPhotosTests.mixedSourcesAskOnlyForPhotos` |

## Source và Kept trong Smart Album (D8)

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-118 | iPhone 26.5 và 18.6 | menu chọn trường của New Smart Album, Advanced Search, điều kiện biểu đồ Statistics | cả ba có `Source` và `Kept on iPhone`; tập trường giống hệt nhau (lặp qua mọi trường) | ⚠️ chưa có — `SmartAlbumFieldTests.hubFieldsInEveryBuilder` |
| AC-119 | 120 ảnh Photos + 40 NAS Home; Kept: 5 ảnh NAS + 3 ảnh Photos | Smart Album *Source is NAS Home* **và** *Kept*, Save `Kept NAS`; rồi đổi sang khớp bất kỳ | `Matches 5 photos`; khớp bất kỳ `Matches 43 photos`; Filter tạm Source › NAS Home + Kept on iPhone trên Library ra **đúng** 5 ảnh đó | ⚠️ chưa có — `SmartAlbumHubRuleTests.sourceAndKept` |
| AC-120 | album `Kept NAS` 5 ảnh | Keep thêm 1 ảnh NAS; Remove from iPhone 2 ảnh; mở lại album | 6, rồi 4 — tính sống, tile Collections ghi đúng | ⚠️ chưa có — `SmartAlbumHubRuleTests.liveKeptChanges` |
| AC-121 | album `Kept NAS` | đổi tên nguồn thành `Home NAS`; rồi Remove… nguồn | album vẫn 5 ảnh sau đổi tên; sau gỡ: chip `NAS Home (removed)` (tên lúc gỡ), `Matches 0 photos`, album mở không lỗi; JSON có id nguồn lạ giải mã được | ⚠️ chưa có — `SmartAlbumRuleDecodingTests.sourceByStableId` |

## Music Statistics, lịch sử nghe (D10, D11)

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-122 | lượt nghe giả của AC-67; iPhone 17 26.5 | Music › Statistics, cuộn tới cuối | dump có **8** thẻ theo thứ tự KPI · Top artists · Format · By source · Most played · Top albums · Kept on iPhone · By month; tập tên thẻ bằng tập trên iPad 27.0 | ⚠️ chưa có — `MusicStatisticsCardTests.phoneHasEveryCard` (lặp qua mọi thẻ) + `scripts/music-stats.json` 03 |
| AC-123 | 50 lượt nghe | Settings › Playback › Clear Listening History…; rồi Cancel | alert `Clear Listening History?`, câu như [07 §3](07-music-statistics.md), nút `Clear History` (đỏ) và `Cancel`; Cancel → vẫn 50 lượt | ⚠️ chưa có — `scripts/hub-settings-playback.json` 02 + `ListeningHistoryTests.cancelKeeps` |
| AC-124 | 50 lượt nghe, 2 playlist, 3 bài Kept, đang phát bài 5, Up Next 7 bài, History 4 bài | Clear History | 0 dòng lượt nghe, History 0; Up Next 7, bài 5 vẫn phát, 2 playlist, 3 Kept nguyên; Statistics `No Listening Yet`; Recently Played, Most Played rỗng | ⚠️ chưa có — `ListeningHistoryTests.clearLeavesLibrary` |
| AC-125 | 0 lượt nghe | chạm Clear Listening History… | hàng mờ, không alert; VoiceOver đọc trạng thái không dùng được | ⚠️ chưa có — `ListeningHistoryTests.emptyRowDisabled` |

## Review video, tên lệnh, Show As (D5, D6, A8)

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-126 | như AC-16, 12 video đã chép | hộp xoá của hệ thống › Delete | Photos còn 3 video (12 vào Recently Deleted); Clips 12, phát được; thẻ Review không gợi ý lại 12 video đó | ⚠️ chưa có — `ReviewMoveTests.deleteAfterCopy` + script (một chạm tay vào hộp hệ thống) |
| AC-127 | như AC-17: 11 chép xong, 1 `Waiting for iCloud` | tới bước xoá | yêu cầu xoá chứa **đúng 11** id tài sản đã chép và đọc lại đúng cỡ; video đang chờ không bao giờ nằm trong yêu cầu | ⚠️ chưa có — `ReviewMoveTests.deleteOnlyVerifiedCopies` |
| AC-128 | ảnh, album Photos, phim, bài, album nhạc, playlist đều đã Keep; iPhone và iPad | mở menu từng thứ | lệnh ngược đều là `Remove from iPhone` (iPad: `Remove from iPad`); String Catalog không còn `Remove Download`, `Download to iPhone`, `Retry Download`, `Downloading` | ⚠️ chưa có — `KeepWordingTests.oneNameEverywhere` + dump iPad |
| AC-129 | `Kyoto.Walk.2019.mp4` (luật xếp vào Movies) | menu › Show As › Clip; quét lại nguồn; rồi Show As › Movie | ≤ 0,5 s rời kệ Movies sang Clips, menu ✓ ở Clip; quét lại vẫn Clip; chọn lại Movie → cột loại người dùng đặt về rỗng | ⚠️ chưa có — `MovieCategoryTests.showAsOverridesRules` |

## Đọc tag sau spike S-M1 (A9, A18)

Fixture: bộ `/Music` của [14b](14b-acceptance-criteria.md) thêm FLAC/MP3 có bìa 2 MB, FLAC có ID3 dán trước, FLAC/MP3 có độ dài
khối/frame khai sai, tag tiếng Việt và tiếng Nhật; FLAC ghi bằng `metaflac --no-utf8-convert` ([05 §2](05-music-library.md)).
Byte đếm qua nguồn `readRange` giả.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-135 | FLAC và MP3 (ID3v2.3, v2.4) có bìa nhúng 2 MB, trên WebDAV giả | quét tag (chưa cần bìa) | mỗi file đọc **≤ 64 KB**, không byte nào của dữ liệu ảnh; title, artist, album, số bài, năm đúng; FLAC thời lượng = tổng mẫu STREAMINFO / tần số (chính xác tới mẫu); lấy bìa sau đó: đúng cỡ ảnh, một lần đọc, khớp từng byte | ⚠️ chưa có — `MusicTagReaderTests.flacAndID3StayInBudget` |
| AC-136 | FLAC có PICTURE khai độ dài vượt file; FLAC có một Vorbis comment khai sai độ dài; MP3 có frame `APIC` khai sai | quét; rồi phát hàng đợi [file hỏng, `Holocene`] | các tag còn lại (title, artist, album, số bài) vẫn đọc được; lần quét đi tiếp các file khác; file AVFoundation không mở được vào `can't be played` lý do `Damaged file` và bị bỏ qua, `Holocene` phát | ⚠️ chưa có — `MusicTagReaderTests.corruptLengthsKeepOtherTags` + `MusicQueueTests.skipsDamaged` |
| AC-137 | FLAC (ghi `--no-utf8-convert`) và MP3 ID3v2.4 với `TITLE=Nắng ấm xa dần`, `ARTIST=宇多田ヒカル`; FLAC có ID3 dán trước `fLaC` | quét | chuỗi đọc ra **bằng từng byte** chuỗi gốc (không `#`, không U+FFFD); FLAC có ID3 dán trước vẫn đủ Vorbis comment | ⚠️ chưa có — `MusicTagReaderTests.utf8RoundTrip` |

## Khung, design, thiết bị (A1, A3, A6, A12, A14, A17)

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-130 | iPhone 18.6, hàng đợi rỗng | dump Library; phát một bài; Now Playing › ⋯ › Stop | khoảng đáy 100pt; 164pt, mini player 362×56 ở x 20 (A1, A3); về 100pt | ⚠️ chưa có — `scripts/hub-clearance.json` 02–04 |
| AC-131 | menu bài, menu phim, menu album ảnh; ô ảnh, poster, bìa đã Keep | dump + đọc tên symbol | lệnh Keep dùng `arrow.down.to.line`; dấu Kept `checkmark.circle.fill`, trên ô ảnh đứng cuối hàng glyph trạng thái; không chỗ Keep nào dùng `arrow.down.circle` (A12) | ⚠️ chưa có — agent `design-reviewer` + dump |
| AC-132 | iPhone 26.5 và Duo ngoài | Settings › Sources & Backup, cuộn hết | sau On this iPhone có Metadata, Drives and Indexing, Cache Size Limit — cùng hàng như iPad (A14) | ⚠️ chưa có — `SettingsSectionTests.sourcesPageSameOnEveryDevice` + `scripts/hub-sources-page.json` |
| AC-133 | iPad 27.0, cửa sổ rộng 900pt (sidebar phủ), đang phát | dump; mở sidebar phủ rồi đóng | mini player 360×56 giữa vùng nội dung, đáy cách mép 20; không đổi chỗ khi sidebar mở/đóng; chỉ một mini player trong dump (A17) | ⚠️ chưa có — `scripts/hub-ipad-overlay.json` + `sim-shot` |
| AC-134 | Mac | menu Controls | có mục đầu đổi tên theo trạng thái — `Pause` (Space) khi đang phát, `Play` (Space) khi đang dừng — · Next ⌘→ · Previous ⌘← · Shuffle (✓ khi bật) · Repeat › Off · All · One; khớp board `MAC_MenuBar` vẽ lại (A6) | ⚠️ chưa có — app Mac chưa có code (FS-18) |

**Chưa chứng minh được:** AC-102…137 — chưa có code. AC-103 (khoá máy), AC-106 (PiP) cần máy thật; AC-126 cần một chạm tay
vào hộp xoá của hệ thống; AC-134 chờ app Mac. Không có AC cho D3 (xin entitlement CarPlay — việc ngoài code), A4, A15, A16
(chỉ là tài liệu/cấu trúc, AC-30 và AC-90 đã phủ A15).
