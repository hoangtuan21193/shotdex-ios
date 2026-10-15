# FS-24.14c — Tiêu chí nghiệm thu (3/4): Keep, Convert, Extract Audio, dữ liệu, thiết bị

`FS-24.14c` · AC-70…AC-101 · dữ liệu test: [14 đầu file](14-acceptance-criteria.md) · tiếp: [14d](14d-acceptance-criteria.md) · cập nhật 2026-10-16

Dung lượng trống giả lập bằng lớp đọc dung lượng thay được trong test (như `MovieDownloadTests.needsSizePlusOneGB`).

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-70 | playlist 48 bài stream, tổng 412 MB, trống 20 GB | Keep on iPhone | ≤ 0,5 s hiện `Keeping 0 of 48`; xong: mọi bài ✓, dòng phụ `48 songs · on iPhone, 412 MB`; Kept on iPhone tăng 412 MB ± 1 MB | ⚠️ chưa có — `KeepQueueTests.playlist` + `scripts/keep-playlist.json` |
| AC-71 | trống 1,2 GB, cần 412 MB | Keep on iPhone | `Not enough space on this iPhone — about 0.2 GB needed.`; 0 byte đọc | ⚠️ chưa có — `KeepQueueTests.needsSizePlusOneGB` |
| AC-72 | đang Keep, bài 20/48 xong, trống tụt dưới 1 GB | tiếp tục | hàng đợi dừng, `Paused · iPhone storage is full`; 20 bài ✓ ở lại | ⚠️ chưa có — `KeepQueueTests.pausesWhenFull` |
| AC-73 | đang Keep bài 30 MB, tới 11 MB thì tắt NAS giả | bật lại NAS | `Paused · NAS Home unreachable`; tự tiếp từ 11 MB, tổng byte đọc ≤ 30 MB + 1 MB | ⚠️ chưa có — `KeepQueueTests.resumesFromBytes` |
| AC-74 | bài A đã Keep riêng; playlist chứa A đang Keep 10/48 | Stop Keeping | 9 bài vừa chép bị gỡ, `.part` xoá; A vẫn ✓ | ⚠️ chưa có — `KeepQueueTests.stopKeepsPriorKeeps` |
| AC-75 | bài A trong 2 playlist đều Keep | đếm dung lượng; rồi bỏ Keep một playlist | A tính một lần; file A còn tới khi playlist kia cũng bỏ | ⚠️ chưa có — `KeptFileStoreTests.refCounted` |
| AC-76 | album 40 ảnh NAS Home | Keep on iPhone, rồi tắt NAS | 40 bản gốc + sidecar trong kho; mở ảnh full-res, Edit, Export đều được (không mờ) | ⚠️ chưa có — `KeepPhotosTests.sourceOriginals` + script |
| AC-77 | album Photos 10 ảnh, 3 chỉ có trên iCloud, máy offline | Keep on iPhone › Originals (D7) | 7 ✓; 3 `Waiting for iCloud`, không lỗi; có mạng → ✓ | ⚠️ chưa có — `KeepPhotosTests.iCloudOnlyWaits` ([09 §2a](09-keep-on-device.md)) |
| AC-78 | quyền `.limited` 120 ảnh, album 300 ảnh | Keep album | chỉ 120 ảnh chép; dòng `Kept 120 of 120 photos you shared` | ⚠️ chưa có — `KeepPhotosTests.limitedAccess` |
| AC-79 | Dune Kept 6,1 GB, xem tới 47:12 | Remove from iPhone › Remove | alert `Remove from iPhone?` · "It stays on NAS Home. This frees 6.1 GB."; trống tăng ≥ 6,1 GB; mở lại phát từ 47:12 | ⚠️ chưa có — `MovieDownloadTests.removeKeepsProgress` (đổi chữ) |
| AC-80 | đã Keep ảnh, bài, phim | đọc thuộc tính thư mục + đếm tài sản Photos | `Music/`, `Kept/`, `Movies/` không sao lưu; số tài sản Photos không đổi | ⚠️ chưa có — `KeptStorageTests.excludedFromBackup` |
| AC-81 | 5 GB đã Keep | hệ thống báo thiếu bộ nhớ / dung lượng thấp | 0 file Keep bị xoá | ⚠️ chưa có — `KeptStorageTests.neverAutoDeletes` |
| AC-82 | clip MP4 4K 60 s đã Keep | Convert › MP4 · H.264 · 1080p › Save to Photos | Photos +1 video 1920×1080, thời lượng 60 ± 0,1 s, cỡ ≤ 1,2 × ước tính | ⚠️ chưa có — `MovieConvertTests.h264To1080pSaves` |
| AC-83 | Convert đang 30% | Cancel | dừng ≤ 1 s; không file dở; file gốc mã băm không đổi | ⚠️ chưa có — `MovieConvertTests.cancelCleansUp` |
| AC-84 | ước tính 2,1 GB, trống 2,5 GB | Convert | `Not enough space on this iPhone — about 0.6 GB needed.`; không bắt đầu | ⚠️ chưa có — `MovieConvertTests.needsSpace` |
| AC-85 | Dune Kept, Replace Kept Copy · HEVC | giết app ở 50%; rồi chạy lại tới xong | lần giết: file cũ nguyên, phát được; xong: file mới nhỏ hơn, chỗ xem 47:12 giữ, sheet đã ghi `Other audio tracks are removed.` | ⚠️ chưa có — `MovieConvertTests.replaceIsAtomic` |
| AC-86 | `clip.mkv` đã Keep | Convert › MP4 | (A13) ra MP4 phát được, tốc độ chuyển ≥ 1× thời gian thực trên iPhone 15 (giải mã VLCKit, mã hoá AVFoundation) | ⚠️ chưa có — `MovieConvertTests.mkvThroughVLC` sau spike S-M3; spike hỏng → hỏi lại người dùng, AC viết lại |
| AC-87 | clip MP4 có track AAC 3:00 | Extract Audio › Whole Movie | bài M4A 180 ± 0,05 s, cùng bitrate gốc (không mã hoá lại); title tên clip, artist `From Movies`; playlist From Movies `1 track`; thêm được vào Video Studio | ⚠️ chưa có — `ExtractAudioTests.aacPassthrough` |
| AC-88 | clip 5:00 | Extract Audio › Custom 1:00–3:30 | bài 150 ± 0,05 s | ⚠️ chưa có — `ExtractAudioTests.customRange` |
| AC-89 | clip không track tiếng; phim stream | mở Extract Audio | clip: `This video has no sound.`; stream: nút `Keep on iPhone First` | ⚠️ chưa có — `ExtractAudioTests.guards` |
| AC-90 | schema trước và sau migration hub | so cột `photo_metadata` và khoá ngoại | cột y hệt; không bảng mới nào trỏ tới `photo_metadata` | ⚠️ chưa có — `AppDatabaseMigrationTests.hubLeavesPhotoMetadata` |
| AC-91 | 2 playlist, 50 lượt nghe, 3 Keep, hàng đợi 12 bài | quét lại nguồn nhạc (mọi bài đổi ngày sửa) | 4 bảng người dùng không đổi dòng nào | ⚠️ chưa có — `MusicScanTests.rescanLeavesUserData` |
| AC-92 | bài WAV 600 MB trên SMB giả | phát 60 s | bộ nhớ app tăng < 50 MB; không đọc quá vị trí phát + 8 MB | ⚠️ chưa có — `MusicStreamTests.boundedBuffer` |
| AC-93 | iPad 27.0 ngang, sidebar ghim | Photos › Albums › `Kyoto`, đổi Movies, đổi lại Photos | `Kyoto` vẫn chọn, chỗ cuộn giữ; mini player ở chân sidebar 304×56 | ⚠️ chưa có — `scripts/hub-ipad.json` + `sim-shot` |
| AC-94 | iPad cài mới | sidebar Photos | Pinned có On This Day · All Photos · Favorites · Videos · RAW · Recently Added | ⚠️ chưa có — `scripts/hub-ipad.json` 02 |
| AC-95 | Duo trong, đang phát | dump Library, Movies Home, Search | rail 68pt có 3 tab + Search; tổng khối không cuộn ≤ 334pt ở cả 3 màn | ⚠️ chưa có — `scripts/hub-duo-inner.json` + `sim-shot inner` |
| AC-96 | Duo ngoài, đang phát | Music | mini player 350×52 nằm trọn trong cột 382 (không dưới rail 84pt); không `+` | ⚠️ chưa có — `scripts/hub-duo-cover.json` 02 |
| AC-97 | Duo đang phát nhạc ở 1:00 | gập rồi mở máy | nhạc không dừng; giờ liên tục (lệch ≤ 1 s so với đồng hồ) | ⚠️ chưa có — cần gập tay trong Simulator.app |
| AC-98 | Mac | Go › Music (⌥⌘8), Keep on Mac trên 3 ảnh Photos › Originals, Space | mở Music; hộp `Keep 3 Photos on Mac` hiện (D7); 3 ảnh ✓; Space phát/dừng nhạc khi không có ô nhập | ⚠️ chưa có — app Mac chưa có code (FS-18) |
| AC-99 | VoiceOver bật | quét mini player, Now Playing | `Now Playing: Holocene, Bon Iver`, `Pause`, `Next Song`; thanh tua điều chỉnh bước 10 s; Shuffle đọc trạng thái `On`/`Off` | ⚠️ chưa có — agent `a11y-voiceover` + dump |
| AC-100 | cỡ chữ AX5, iPhone 18.6 | màn gốc 4 tab | nhãn tab bỏ, icon còn; tên bài trong mini player không bị cắt dọc; Utilities 1 cột | ⚠️ chưa có — `scripts/hub-ax5.json` |
| AC-101 | 4 canvas, mọi board "Media hub" | `design-board compare` với dump | mọi board lệch ≤ 2pt (iPad, Duo bằng `sim-shot`) | ⚠️ chưa có — agent `design-parity` |

**Chưa chứng minh được:** AC-70…101 — chưa có code. AC-97 cần gập tay; AC-98 chờ app Mac.
