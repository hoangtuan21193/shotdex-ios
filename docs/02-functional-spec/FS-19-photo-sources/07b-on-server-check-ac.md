# FS-19.07b — Ảnh Photos đã có trên server: spike và tiêu chí nghiệm thu

`FS-19.07b` · quy tắc: [07](07-on-server-check.md) · cập nhật 2026-10-25

## 1. Spike trên máy thật (đo trước, chốt AC sau)

Simulator không có iCloud thật, Optimize Storage hay lịch chạy nền thật — bốn câu này chỉ máy thật trả lời. Mỗi spike
là một build thử (không ship) ghi số vào `docs/_intents/2026-10-24-smart-album-on-nas.md` mục Open questions.

| # | Câu hỏi | Cách đo | Đạt khi | Quyết định phụ thuộc |
|---|---|---|---|---|
| S1 | iCloud **đầy** + Optimize Storage bật: tải bản gốc chỉ-iCloud qua PhotoKit có chạy không, lỗi gì? | iPhone thật, tài khoản iCloud đầy; tải 50 ảnh + 5 video 4K chỉ-iCloud, ghi kết quả, thời gian, mã lỗi | ≥ 54/55 tải được | §4 giữ nguyên; không đạt → mục đó thành `Can't download from iCloud`, không chặn cả lượt |
| S2 | Photos có giữ bản gốc vừa tải trong bộ nhớ của nó không (máy đầy dần)? | đo dung lượng trống trước/sau tải 10 GB bản gốc rồi xoá file tạm; đo lại sau 1 giờ và 24 giờ | trống giảm ≤ 1 GB sau 24 giờ | không đạt → thêm ngưỡng dừng theo GB đã tải mỗi lượt, `⚠️` mới |
| S3 | Một đêm cắm sạc, tác vụ nền được bao nhiêu phút, băm được bao nhiêu GB? | bật kiểm 20.000 mục, để máy cắm sạc qua đêm, đọc log tiến độ sáng hôm sau; iOS 26.5 và iOS 18 | ghi số; không có ngưỡng đạt/hỏng | dòng ước lượng thời gian ở §8; có cần nhắc "Keep ShotDex open" không |
| S4 | Băm video 4K 3 GB đọc luồng: bộ nhớ đỉnh, thời gian, nhiệt? | Instruments trên iPhone 17, 3 video 4K | bộ nhớ tăng ≤ 64 MB so với lúc nghỉ; không bị hệ thống giết | không đạt → giảm khối đọc, chỉ băm video khi cắm sạc |

## 2. Tiêu chí nghiệm thu

Thư viện thử: không ảnh có mặt người. Server thử: WebDAV cục bộ (công thức FS-22 trong memory `backup-fs22`).

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-74 | nguồn `NAS Home` ở gốc `iCloud Photo/`; 100 mục Photos đã kiểm xong; 40 có bản trong `Shared/`, 25 chỉ trong `Tuấn/` | lưu album: Source is Photos Library **và** Source is NAS Home · Folder `Shared` | *Matches 40 photos*; chip `Source: NAS Home › Shared` | ⚠️ chưa có — đề xuất `OnServerRuleTests.folderScope` |
| AC-75 | như AC-74 | đổi Folder thành trống (cả nguồn) | *Matches 65 photos* | ⚠️ chưa có — `OnServerRuleTests.wholeSource` |
| AC-76 | 1 ảnh trong album AC-74; script dời file từ `Shared/2025/a.HEIC` sang `Shared/x/b.HEIC` | app ra nền rồi về trước mặt | ảnh vẫn trong album; 0 lần đọc nội dung file `b.HEIC` (hash nhanh + cỡ nối danh tính) | ⚠️ chưa có — `ServerSourceIndexerTests.renameKeepsIdentity` |
| AC-77 | Live Photo, trên `Shared/` chỉ có `IMG_1.HEIC`, thiếu `IMG_1.MOV` | đếm album **is** và **is not** của Shared | không có trong **is**; có trong **is not** | ⚠️ chưa có — `OnServerRuleTests.livePhotoNeedsVideo` |
| AC-78 | ảnh RAW+JPEG, cả `.ARW` và `.JPG` trên `Shared/` | đếm album **is** | có trong **is** | ⚠️ chưa có — `OnServerRuleTests.rawPairBothFiles` |
| AC-79 | trên `Shared/` có bản JPEG nén lại (byte khác) của một HEIC trong Photos | đếm album **is** | không có trong **is** | ⚠️ chưa có — `OnServerRuleTests.recompressedIsNotPresent` |
| AC-80 | 100 mục Photos, 30 đã băm đủ, 70 chưa | mở album **is not** của Shared | 70 mục chưa băm không có mặt; dòng `Checking · 30 of 100` | ⚠️ chưa có — `OnServerRuleTests.uncheckedInNeither` + `ui-drive` `on-server-album.json` |
| AC-81 | kiểm đang chạy, 500/1.000 mục đã băm | giết app, mở lại | lượt tiếp bắt đầu ở mục 501; 0 mục trong 500 bị đọc lại | ⚠️ chưa có — `PhotosHashTests.resumesAfterKill` (bộ đọc giả đếm số lần đọc) |
| AC-82 | 3 mục chỉ-iCloud, máy còn trống 12 GB | lượt băm chạy | mỗi lúc ≤ 1 file tạm trong thư mục tạm; file tạm xoá ngay sau khi băm; 3 mục có hash | ⚠️ chưa có — `PhotosHashTests.oneTempFileAtATime` |
| AC-83 | còn trống 2,5 GB, mục kế là video 1 GB | lượt băm tới mục đó | dừng, không tải; dòng `Waiting for space` | ⚠️ chưa có — `PhotosHashTests.waitsForSpace` |
| AC-84 | NAS có 1.000 file, 40 có hash nhanh trùng file gốc Photos | lượt băm server | đúng 40 file được đọc trọn | ⚠️ chưa có — `ServerSourceIndexerTests.fullHashOnlyCandidates` |
| AC-85 | Backup đẩy 10 ảnh vào `Shared/` (nằm trong nguồn) | Backup xong, mở album **is** | 10 ảnh có mặt; 0 lần đọc lại 10 file đó từ NAS | ⚠️ chưa có — `BackupRunnerTests.recordsServerCopyHash` |
| AC-86 | connection có job Backup *Only on Wi‑Fi* bật, máy đang dùng di động | lượt kiểm đến lúc chạy | không lệnh nào tới server, không tải iCloud; dòng `Waiting for Wi‑Fi` | ⚠️ chưa có — `OnServerScheduleTests.followsBackupJob` |
| AC-87 | album AC-74; script xoá `Shared/2025/c.HEIC` | app về trước mặt | ảnh rời album **is**, vào **is not**; ô lưới mất glyph "trên server" | ⚠️ chưa có — `ui-drive` `on-server-album.json` |
| AC-88 | album 20 mục; sau lượt so cuối, script xoá 2 file trên NAS | Select All → Delete → xác nhận | 18 mục vào Recently Deleted; alert nêu 2 mục "no longer on NAS Home", 2 mục còn trong Photos | ⚠️ chưa có — `DeletionServiceTests.reverifiesServerCopy` |
| AC-89 | như AC-88 nhưng server tắt | Delete → xác nhận | 0 mục bị xoá; alert "Can't reach NAS Home. Nothing was deleted." | ⚠️ chưa có — `DeletionServiceTests.unreachableDeletesNothing` |
| AC-90 | hộp xác nhận xoá từ album AC-74 | mở hộp | có câu "They move to Recently Deleted. iCloud space is freed after Recently Deleted is emptied." | ⚠️ chưa có — ảnh chụp |
| AC-91 | ảnh có bản ở `Shared/2025/a.HEIC` | mở Photo Info | mục On Server có dòng `NAS Home` / `iCloud Photo/Shared/2025/a.HEIC`; mục Uploaded to Server vẫn như cũ | ⚠️ chưa có — ảnh chụp iPhone, iPad, Duo trong |
| AC-92 | quyền Photos `.limited`, 50 mục được cấp | mở album **is** | chỉ 50 mục được kiểm; dòng tiến độ có "Only photos ShotDex can access are checked." | ⚠️ chưa có |
| AC-93 | iPhone 402×874, iOS 26.5 và 18.6 | thêm điều kiện Source = NAS Home, chạm Folder, chọn `Shared` | dòng Folder ghi `Shared`; số khớp cập nhật; khớp board `PH_SmartAlbumEditor` (khi vẽ) ± 2pt | ⚠️ chưa có — `Tools/design-board compare` |
| AC-94 | connection không có job Backup, máy đang dùng di động, *Use Cellular Data for Indexing* bật | lượt kiểm đến lúc chạy | không lệnh nào tới server; dòng `Waiting for Wi‑Fi` | ⚠️ chưa có — `OnServerScheduleTests.noJobMeansWiFiOnly` |
| AC-95 | ảnh có bản Photos + bản NAS; script đã xoá file NAS sau lượt so cuối | xoá ảnh từ **Library** (không phải album) | ảnh không bị xoá; alert "no longer on NAS Home" | ⚠️ chưa có — `DeletionServiceTests.reverifiesFromLibrary` |
| AC-S1…S4 | spike §1 | — | số đo ghi vào intent | ⚠️ cần máy thật |

**Chưa chứng minh được:** cả bảng — tính năng chưa có code.
