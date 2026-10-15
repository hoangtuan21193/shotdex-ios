# FS-24.14 — Tiêu chí nghiệm thu (1/4): khung, Photos, Movies, Search, Sources & Backup

`FS-24.14` · AC-1…AC-37 · tiếp: [14b](14b-acceptance-criteria.md) (nhạc, player, Statistics, AC-38…69) ·
[14c](14c-acceptance-criteria.md) (Keep, Convert, dữ liệu, thiết bị, AC-70…101) · [14d](14d-acceptance-criteria.md) (các quyết
định chốt 2026-10-16, AC-102…137) · cập nhật 2026-10-16

**Dữ liệu test** (không ảnh có mặt người — memory `no-face-photos-in-tests`): thư viện sim gieo 120 ảnh phong cảnh + 15 video
(12 không có thông tin máy quay, dài ≥ 60 s; 3 có); WebDAV giả (wsgidav) và SMB giả (impacket) ở 127.0.0.1 như FS-15, thư mục
`/Photos` 40 ảnh, `/Movies` 3 phim + 1 tập `The.Bear.S03E04.mkv` + 2 clip, `/Music` bộ 30 file nhạc tổng hợp bằng ffmpeg
(tiếng sine, tag ghi sẵn); Plex giả (`plex.debugPlexTV`, chỉ DEBUG) có thư viện Movies và Music. Máy: iPhone 17 26.5,
iPhone 16 18.6, iPad 27.0, Duo 27.1 (xác định bằng `id=`, memory `xcodebuild-destination-by-id`).

Mọi AC đều **chưa có code** → cột chứng minh ghi `⚠️ chưa có` kèm tên test/script đề xuất.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | cài mới, iPhone 17 26.5 | mở app | tab bar có đúng `Photos`, `Movies`, `Music` + vòng `Search`; Photos chọn sẵn, đoạn `Library`; không còn tab `Collections`, `Statistics` | ⚠️ chưa có — `scripts/hub-tabs.json` (dump) |
| AC-2 | thư viện test, 1 nguồn NAS, 1 Plex | đi hết bảng [02](02-what-moves.md) | mọi lối vào ở cột "Sau hub" mở đúng màn (mỗi hàng bảng một bước script); không lối vào nào ở cột "Hôm nay" mất | ⚠️ chưa có — `scripts/hub-move-map.json` (iPhone 26.5 + 18.6) |
| AC-3 | iPhone 16 18.6 và iPhone 17 26.5, đang phát nhạc | dump màn gốc 4 tab | tập nút giống hệt hai nhánh (3 tab + Search, ⚙, nút trailing, mini player Pause/Next) | ⚠️ chưa có — `scripts/hub-parity.json` + so dump |
| AC-4 | hàng đợi rỗng | phát `Holocene` (NAS Home) | mini player hiện ≤ 0,5 s: `Holocene` · `Bon Iver · NAS Home` · `Pause` · `Next Song`; chạm vùng chữ → Now Playing | ⚠️ chưa có — `scripts/hub-miniplayer.json` |
| AC-5 | đang phát, iPhone 18.6 và 26.5 (A2) | mở Photos › Collections › Statistics; mở Viewer; vào chế độ Select | mini player (26.5: phụ kiện tab bar) không có trong dump ở cả 3 màn trên cả hai máy; về màn gốc Collections thì có lại | ⚠️ chưa có — `scripts/hub-miniplayer.json` 02–04 |
| AC-6 | iPhone 18.6, đang phát, Library cuộn tới đáy (A1) | dump | khoảng đáy nội dung = 164pt; đáy ô lưới cuối ≤ đỉnh mini player − 8pt; đỉnh mini player ≤ đỉnh tab bar − 8pt | ⚠️ chưa có — `scripts/hub-clearance.json` |
| AC-7 | Movies cuộn 600pt | chạm Music rồi Movies; rồi chạm Movies lần nữa | lần 1 offset 600 ± 1pt; lần 2 về màn gốc, lần 3 về đầu | ⚠️ chưa có — `RootTabStateTests.reselectPopsThenScrollsTop` + script |
| AC-8 | index xong (D9) | Collections › Utilities | ô đầu `Statistics` cao 44 như các ô khác (lệch ≤ 1pt), chỉ icon + tên, không dòng phụ, có chấm NEW tới lần chạm đầu; chạm → Statistics, nút Back `Photos`, tab Photos sáng | ⚠️ chưa có — `scripts/hub-statistics.json` |
| AC-9 | cài mới | mở Collections; rồi + › Customize | thứ tự hero · Pinned · Smart · My · Shared · Media Types · Utilities · Sources; không People and Pets, Network; Customize có 2 mục đó tắt; bật People and Pets → section hiện | ⚠️ chưa có — `CollectionsLayoutTests.hubDefaults` + script |
| AC-10 | 0 ảnh Hidden, 2 Unable to Upload, 0 On Server | xem Utilities | 12 ô theo thứ tự [03 §3](03-photos-tab.md) trừ Hidden, On Server; Movies không còn trong Utilities lẫn Customize | ⚠️ chưa có — `scripts/hub-utilities.json` |
| AC-11 | 120 ảnh Photos + 40 ảnh NAS Home | Filter and sort › Source › NAS Home | lưới 40 ô; token `NAS Home` trong thanh điều kiện; Clear Filters → 160 | ⚠️ chưa có — `PhotoFilterTests.sourceFilter` + script |
| AC-12 | 5 ảnh đã Keep | Filter › Kept on iPhone | lưới đúng 5 ô; menu Filter ở Albums và Duplicates cũng có 2 hàng mới | ⚠️ chưa có — `PhotoFilterTests.keptFilter` |
| AC-13 | ổ T7 rút, thẻ nhớ cắm có 214 ảnh mới | xem Sources | ô T7 mờ 0,42 + `Offline`; ô thẻ nhớ `214 new`, chạm → màn nhập FS-20; `Add Source…` → sheet Add a Source | ⚠️ chưa có — `scripts/hub-sources-group.json` |
| AC-14 | quyền ảnh Denied | mở Photos; rồi Movies | Photos: lời giải thích + Open Settings; Movies: 3 phim WebDAV, chạm phát được | ⚠️ chưa có — `scripts/hub-denied.json` |
| AC-15 | WebDAV 3 phim, 1 tập, 2 clip; Dune xem tới 47:12 / 2:46:00 | mở Movies | Continue Watching có Dune `1:58:48 left`; kệ Movies 3, TV Shows 1 (`The Bear`), Clips 2; Utilities 6 ô, không Statistics | ⚠️ chưa có — `MovieCategoryTests.rules` + `scripts/hub-movies-home.json` |
| AC-16 | 15 video trong Photos (12 không máy quay ≥ 60 s) | Movies | thẻ `12 videos look downloaded`; Review → Move to Movies → Clips +12, file đủ byte; hộp xoá của hệ thống (D5) → Cancel giữ cả hai bản: Photos vẫn 15 video, Clips 12 | ⚠️ chưa có — `ReviewSuggestionTests.counts` + script |
| AC-17 | 1 trong 12 video chỉ có trên iCloud, máy offline | Move to Movies | 11 chép xong; 1 hàng `Waiting for iCloud`, không hộp lỗi; có mạng lại thì tự chạy tiếp | ⚠️ chưa có — `ReviewMoveTests.iCloudOnlyWaits` |
| AC-18 | Dune Kept, tắt WebDAV + Plex | mở Movies | chân Sources `Away from home: NAS Home and Plex can’t be reached. Kept items (✓) still play.`; Dune phát; phim stream mờ | ⚠️ chưa có — `scripts/hub-movies-offline.json` |
| AC-19 | bộ script FS-23 (`movies-*.json`) | chạy với lối vào là tab Movies | mọi AC FS-23 đang ✅ vẫn ✅; chữ (D6) `Download to iPhone` → `Keep on iPhone`, `Downloading` → `Keeping`, `Remove Download` → `Remove from iPhone`, `Retry Download` → `Retry Keep` | ⚠️ chưa có — sửa lối vào trong 23 script FS-23 |
| AC-20 | Duo ngoài | Movies và menu một phim | không `+`; ⋯ chỉ Grid/List, Sort; menu không Rename, Convert…, Extract Audio…, Remove | ⚠️ chưa có — `scripts/hub-duo-cover.json` + `sim-shot cover` |
| AC-21 | ảnh có nơi chụp Kyoto (238), clip `Kyoto walk in the rain`, bài `Kyoto` | Search `kyoto`, scope All | ba nhóm theo thứ tự Photos `238` · Movies `1` · Music `1`, mỗi nhóm See All | ⚠️ chưa có — `GlobalSearchTests.groupsInFixedOrder` + `scripts/hub-search.json` |
| AC-22 | scope All | gõ `Sony 85mm` | scope thành Photos; capsule `brand Sony · focal 85mm`; dòng `… photos · Sony · 85mm` | ⚠️ chưa có — `GlobalSearchTests.cameraTokensJumpToPhotos` |
| AC-23 | người dùng chọn scope Music | gõ `Sony 85mm` | scope vẫn Music; xoá hết chữ → All | ⚠️ chưa có — `GlobalSearchTests.manualScopeSticks` |
| AC-24 | tắt mọi server giả | Search `holocene` | bài Holocene có trong Music (mờ, stream); 0 yêu cầu mạng trong lúc tìm | ⚠️ chưa có — `scripts/hub-search-offline.json` + `log stream` |
| AC-25 | DB 55.000 ảnh + 3.000 bài + 200 phim (in-memory) | tìm `kyoto` scope All | ba nhóm trả về ≤ 300 ms (trung vị 10 lần) | ⚠️ chưa có — `GlobalSearchPerformanceTests.allScope` |
| AC-26 | quyền ảnh Denied | Search `kyoto` | nhóm Photos là dòng `Allow access to search your photos` + Open Settings; Movies, Music vẫn có | ⚠️ chưa có — `GlobalSearchTests.deniedPhotos` |
| AC-27 | đã tìm 3 lần ở 3 scope | mở Search | Recents 3 mục ở mọi scope; Clear → 0 | ⚠️ chưa có — `GlobalSearchTests.sharedRecents` |
| AC-28 | Movies có clip Kyoto, Music có bài Kyoto | Search Movies `kyoto` | chỉ clip; không bài nhạc | ⚠️ chưa có — `MovieSearchTests.inTabOnly` |
| AC-29 | mọi thiết bị | Settings | hàng tên `Sources & Backup`; trang theo thứ tự Sources · Browse · Backup · On this iPhone | ⚠️ chưa có — `SettingsSectionTests.sourcesAndBackupName` + script |
| AC-30 | NAS Home có thư mục ảnh, phim, nhạc | xem Sources & Backup | **một** hàng `NAS Home` · `SMB · photos, movies, music`; chi tiết 3 thư mục theo loại | ⚠️ chưa có — `SourcesPageTests.oneRowPerConnection` |
| AC-31 | NAS Home: 40 ảnh, 3 phim, 28 bài; 1 phim + 1 playlist Kept | Remove… › Remove | alert nói `40 photos, 3 movies and 28 songs`; sau gỡ phim và playlist Kept vẫn phát; nguồn trên NAS không đổi byte nào | ⚠️ chưa có — `SourceRemovalTests.keptSurvive` |
| AC-32 | Plex giả trả 401 | mở Settings › Sources & Backup | hàng Plex `Sign in to Plex again` + Sign In; bài và phim Plex đã Keep vẫn phát | ⚠️ chưa có — `PlexTests.revokedTokenMusic` |
| AC-33 | tab Music | + › Add a Source… | sheet Add a Source mở thẳng (không qua Settings) | ⚠️ chưa có — `scripts/hub-music.json` |
| AC-34 | thêm thư mục `/Music` trên NAS Home đã có | Add a Source › Folder › NAS Home | không hỏi mật khẩu; Sources & Backup vẫn một hàng NAS Home | ⚠️ chưa có — `MusicSourceTests.reusesConnection` |
| AC-35 | iPhone, bất kỳ tab | ⚙ | Settings mở toàn màn như hôm nay | ⚠️ chưa có — `scripts/hub-tabs.json` 05 |
| AC-36 | deep link phim; Share một `.flac` vào app | mở link; Share › ShotDex | phim → tab Movies trang chi tiết; `.flac` → tab Music, bài mới đứng đầu Recently Added | ⚠️ chưa có — `scripts/hub-deeplinks.json` |
| AC-37 | iPhone 17 26.5, sáng + tối | 8 board iPhone "Media hub" | `Tools/design-board compare` lệch ≤ 2pt mỗi control | ⚠️ chưa có — agent `design-parity` |

**Chưa chứng minh được:** AC-1…37 — chưa có code.
