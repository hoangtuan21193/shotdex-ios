# FS-24.14b — Tiêu chí nghiệm thu (2/4): thư viện nhạc, player, Statistics

`FS-24.14b` · AC-38…AC-69 · dữ liệu test: [14 đầu file](14-acceptance-criteria.md) · cập nhật 2026-10-16

Bộ nhạc `/Music` (30 file, sine, tag ghi sẵn): 10 FLAC 16/44.1 có Vorbis comment + bìa nhúng (album `22, A Million`),
10 MP3 ID3v2.4, 8 M4A AAC (1 album compilation 4 nghệ sĩ), 1 OGG, 1 M4P giả có cờ bảo vệ; thêm 2 WAV cắt từ một sine liền
cho gapless; `Holocene.lrc` (UTF-8) và `Kyoto.lrc` (Windows-1258).

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-38 | WebDAV `/Music` bộ 30 file | Add a Source › Folder › `/Music` | ≤ 20 s: 28 bài; album `22, A Million` 10 bài đúng số bài; hàng nguồn `2 files can't be played` → OGG `Format not supported`, M4P `Protected by Apple Music` | ⚠️ chưa có — `MusicScanTests.folderSource` + `scripts/music-add-folder.json` |
| AC-39 | 28 file trên WebDAV | quét lần đầu | mỗi file đọc ≤ 384 KB (256 KB đầu + 128 KB cuối) + một khối bìa khi bìa nằm ngoài; không file nào đọc hết | ⚠️ chưa có — `MusicTagReaderTests.readsHeadAndTailOnly` |
| AC-40 | FLAC có Vorbis comment `TITLE=Holocene`, `TRACKNUMBER=3`, bìa 600×600 | đọc tag | title, số bài, artist, album đúng; bìa có | ⚠️ chưa có — `MusicTagReaderTests.flacVorbisAndPicture` (A9: bộ đọc khối metadata FLAC tự viết; spike S-M1 Đi 2026-10-16; thêm AC-135…137) |
| AC-41 | `03 - Holocene.flac` không tag trong thư mục `22, A Million` | quét | title `Holocene`, số bài 3, album `22, A Million`, artist `Unknown Artist` | ⚠️ chưa có — `MusicTagReaderTests.fallbackFromNames` |
| AC-42 | album M4A cờ compilation, 4 nghệ sĩ | duyệt Albums | một album dưới `Various Artists`, 8 bài; Artists có cả 4 nghệ sĩ | ⚠️ chưa có — `MusicLibraryQueriesTests.compilationGroups` |
| AC-43 | Plex giả có thư viện Music 50 bài | Add a Source › Plex Server › chọn Music | 50 bài với tên/bìa của Plex; 0 lần đọc file để lấy tag | ⚠️ chưa có — `PlexTests.musicLibrary` |
| AC-44 | Files có `a.flac`, `b.mp3` | + › Add Music Files… chọn cả hai, rồi chọn lại `a.flac` | hai bài chép vào máy, có ✓; bản trong Files nguyên; lần hai không chép trùng | ⚠️ chưa có — `MusicImportTests.copiesOnce` |
| AC-45 | 3 bài từ NAS Home và Files | New Playlist `Road Trip`, thêm 3, kéo bài 3 lên đầu, vuốt bỏ bài 2 | playlist 2 bài đúng thứ tự; dòng phụ `2 songs · 2 sources`; Delete playlist → 2 bài vẫn trong thư viện | ⚠️ chưa có — `MusicPlaylistStoreTests.crud` |
| AC-46 | thư mục import cũ của Video Studio có 4 file + manifest tên | mở app bản mới (migration) | 4 bài nguồn Files, ✓, title theo manifest khi không tag; thư mục cũ đã xoá; panel Music của Video Studio liệt kê chúng | ⚠️ chưa có — `MusicMigrationTests.importsVideoStudioMusic` |
| AC-47 | Video Studio, bài stream `Holocene`, bài Kept `Reckoner` | panel Music | `Reckoner` thêm được làm track; `Holocene` có nút Keep on iPhone, chưa thêm được tới khi ✓ | ⚠️ chưa có — `VideoMusicPanelTests.onlyOnDeviceSongs` |
| AC-48 | nguồn thôi liệt kê 1 bài stream, 1 bài Kept | quét lại xong (không rỗng, không lỗi) | bài stream ẩn, còn dòng 30 ngày; bài Kept ở lại có nhãn; quét lỗi giữa chừng không ẩn gì | ⚠️ chưa có — `MusicScanTests.disappearedSongs` |
| AC-49 | album 10 bài, đang phát bài 2 | Play Next bài X; Add to Queue bài Y | Up Next: X, bài 3…10, Y | ⚠️ chưa có — `MusicQueueTests.playNextAndAddToQueue` |
| AC-50 | đang phát bài 4/10 | Shuffle bật rồi tắt | bài 4 không đổi; tắt → Up Next là 5…10 | ⚠️ chưa có — `MusicQueueTests.shuffleKeepsCurrent` |
| AC-51 | bài cuối, Repeat Off / All / One | bài hết | Off: dừng ở đầu bài cuối, mini player còn; All: về bài 1; One: phát lại bài đó | ⚠️ chưa có — `MusicQueueTests.repeatModes` |
| AC-52 | 2 WAV liền nhau trong hàng đợi | nối bài | khoảng lặng ≤ 10 ms (đo trên mẫu âm lấy từ đầu ra) | ⚠️ chưa có — `MusicGaplessTests.wavJoin` |
| AC-53 | đang phát bài stream SMB giả | đưa app xuống nền (`simctl` mở app khác) 120 s | giờ đã qua tăng 120 ± 2 s; bài kế nối được | ⚠️ chưa có — `scripts/music-background.json`; khoá máy 10 phút: máy thật; đường phát theo kết quả spike S-M2 (A10) |
| AC-54 | đang phát | gửi lệnh từ xa Next, Pause, kéo tua tới 1:30 | đúng bài kế; dừng; giờ 1:30 ± 0,5 s; thông tin Now Playing hệ thống có tên, nghệ sĩ, album, bìa, thời lượng | ⚠️ chưa có — `MusicRemoteCommandTests.handlesCommands` |
| AC-55 | đang phát | ngắt âm thanh bắt đầu, rồi kết thúc kèm "được tiếp tục" | dừng; phát tiếp | ⚠️ chưa có — `MusicSessionTests.interruptionResumes` |
| AC-56 | đang phát qua tai nghe | đường ra cũ biến mất (rút tai nghe) | Pause | ⚠️ chưa có — `MusicSessionTests.routeLossPauses`; máy thật |
| AC-57 | hàng đợi 3 bài stream + 2 bài Kept xen kẽ, tắt NAS giả | phát từ đầu | bài stream bị bỏ qua, mờ `Not available offline`; 2 bài Kept phát; chỉ còn stream → `Can't reach NAS Home. Kept songs still play.` | ⚠️ chưa có — `MusicQueueTests.skipsUnreachable` |
| AC-58 | Sleep Timer 5 min, bài dài 10 min | chờ | ở 5:00 âm lượng giảm 10 s rồi Pause, hàng đợi giữ; End of Song → Pause đúng cuối bài | ⚠️ chưa có — `SleepTimerTests.fadesThenPauses` (đồng hồ giả) |
| AC-59 | `Holocene.lrc` dòng `[02:10.00]` | ở 1:05 mở Lyrics; chạm dòng 02:10 | dòng 1:05 đậm; tua tới 2:10 ± 0,2 s | ⚠️ chưa có — `LyricsTests.syncedLineAndSeek` |
| AC-60 | `Kyoto.lrc` Windows-1258 | mở Lyrics | chữ có dấu đọc đúng (`Xin chào`); bài không lời → nút mờ, VoiceOver `Lyrics, not available` | ⚠️ chưa có — `LyricsTests.legacyEncoding` |
| AC-61 | hàng đợi 12 bài, bài 4 ở 1:23, Shuffle bật | giết app, mở lại | mini player bài 4, **đang dừng** ở 1:23 ± 1 s; Up Next và Shuffle giữ | ⚠️ chưa có — `MusicQueueStoreTests.restoresPaused` |
| AC-62 | đang phát nhạc | mở phim Dune và phát; đóng phim | nhạc Pause khi phim phát; đóng phim nhạc vẫn dừng | ⚠️ chưa có — `AudioOwnerTests.movieTakesOver` |
| AC-63 | phim Dune đang phát | đọc thông tin Now Playing hệ thống | tên `Dune: Part Two`, poster, thời lượng 2:46:00; lệnh Next tắt, lùi/tới 10 s bật | ⚠️ chưa có — `MovieNowPlayingTests.infoAndCommands` |
| AC-64 | đang phát nhạc ở 1:00 | mở một dự án Video Studio; rồi đóng Video Studio | nhạc Pause ≤ 0,5 s khi vào (D1, [06 §7](06-music-player.md)); đóng Video Studio: nhạc vẫn dừng ở 1:00 ± 0,5 s, mini player còn với nút `Play` | ⚠️ chưa có — `AudioOwnerTests.videoStudioPauses` |
| AC-65 | 3 bài Kept, server giả tắt | phát 60 s | 0 yêu cầu mạng từ app | ⚠️ chưa có — `scripts/music-offline-play.json` + `log stream` |
| AC-66 | bài 200 s; bài 600 s | phát 99 s / 100 s bài đầu; 240 s bài sau | 99 s không thành lượt, 100 s thành lượt; 240 s thành lượt; giờ nghe = tổng giây phát | ⚠️ chưa có — `PlayCountTests.thresholds` |
| AC-67 | lượt nghe giả: FLAC 48, ALAC 22, AAC 18, MP3 12; NAS 70, Plex 30 | Music › Statistics, This Year | thẻ Format `FLAC 48%`…; By source `NAS Home 70%`; Top artists đúng thứ tự; màu chỉ từ `ChartPalette` | ⚠️ chưa có — `MusicStatisticsQueriesTests.cards` + script |
| AC-68 | 0 lượt nghe | mở Statistics | `No Listening Yet` + câu hướng dẫn | ⚠️ chưa có — `scripts/music-stats.json` 02 |
| AC-69 | `Holocene` có 64 lượt | xoá nguồn chứa bài | Most played vẫn `Holocene 64`, By source có `NAS Home · Removed` | ⚠️ chưa có — `MusicStatisticsQueriesTests.keepsHistoryAfterRemoval` |

**Chưa chứng minh được:** AC-38…69 — chưa có code. AC-53 (khoá 10 phút), AC-56 cần máy thật.
