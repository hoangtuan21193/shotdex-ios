# FS-24.02 — Cái gì dời đi đâu (không mất chức năng nào)

`FS-24.02` · mã hiện có: `RootTabView.swift`, `Features/Albums/AlbumsScreen.swift` (Collections, Utilities ở dòng 634–811),
`Features/Movies/MoviesScreen.swift`, `Features/Settings/`, `Features/VideoStudio/VideoMusicPanel.swift` · cập nhật 2026-10-16

**Một câu:** luật "chỉ thêm, không bỏ" (người dùng 15/10) đọc thành bảng: mọi lối vào có trong code hôm nay có một chỗ
mới, và AC-2 của [14](14-acceptance-criteria.md) đi hết bảng này trên mọi thiết bị.

## 1. Khung và tab

| Hôm nay (code) | Sau hub | Ghi chú |
|---|---|---|
| Tab **Library** | Photos › **Library** | Filter and sort, Select, lưới, mọi menu giữ nguyên; Filter thêm **Source ›** và **Kept on iPhone**; hai trường này cũng là luật Smart Album (D8) |
| Tab **Collections** | Photos › **Collections** | segmented dưới tiêu đề; + menu New Album · New Smart Album · Customize giữ |
| Tab **Statistics** | Photos › Collections › Utilities › **Statistics** (ô đầu) | màn Statistics không đổi; có nút Back thay ⚙; ô như mọi ô Utilities, không số tóm tắt (D9, [03 §3](03-photos-tab.md)) |
| Tab **Search** (chỉ ảnh) | tab **Search** chung | cú pháp ảnh, capsule diễn giải, Advanced Search giữ ([08](08-search.md)) |
| ⚙ Settings góc trái | ⚙ góc trái **mỗi** tab | |

## 2. Collections

| Hôm nay | Sau hub |
|---|---|
| Hàng hero On This Day | giữ, đầu Collections |
| Pinned | giữ |
| **People and Pets** | **không** trong bố cục mặc định; còn trong Customize (bật lại được); quét ở Settings › People and Pets giữ |
| Smart Albums · My Albums · Shared Albums | giữ, thứ tự Pinned → Smart → My → Shared |
| **Network** (thư mục server ghim) | **không** trong bố cục mặc định; còn trong Customize. Thư mục server thêm làm **nguồn** hiện ở nhóm Sources |
| Media Types (có Bursts) | giữ |
| Utilities | lưới 2 cột icon + tên, không số đếm ([03 §3](03-photos-tab.md)) |
| Sources (nhóm cuối, chỉ khi > 1 nguồn) | giữ cuối; **luôn** hiện ở hub (có ô Add Source…) |

## 3. Utilities của Photos

| Hôm nay | Sau hub |
|---|---|
| — | **Statistics** (ô đầu, mới ở chỗ này) |
| Backup | Photos › Utilities **và** Settings › Sources & Backup |
| Duplicates · Places · Trips · Collages · Video Projects | giữ, cùng thứ tự |
| **Movies** | **tab Movies** (ô bỏ khỏi Utilities; Customize không còn mục Movies) |
| Local Network · Cloud | Photos › Utilities **và** Settings › Sources & Backup › Browse |
| Hidden · Unable to Upload (chỉ khi có ảnh) | giữ, cùng điều kiện |
| Uploaded to Server (vào từ Local Network/Cloud) | thêm ô **On Server** trong Utilities trên mọi thiết bị (người dùng 15/10) |
| — | **On This iPhone** (ảnh, album đã Keep — [09](09-keep-on-device.md)) |

## 4. Movies (FS-23)

| Hôm nay | Sau hub |
|---|---|
| Collections › Utilities › Movies | tab **Movies**, trang chủ có kệ ([04](04-movies-tab.md)); lưới FS-23.01 §4 là **See All** của kệ Movies |
| Search, chip All · On This iPhone · Unwatched | Search Movies + chip **All · Movies · TV Shows · Clips · Unwatched · On This iPhone** |
| ⋯ Grid/List · Sort · Select | giữ |
| + Add a Source… · Add Movie Files… | giữ |
| Download to iPhone / Remove Download / Retry Download | đổi tên **Keep on iPhone** / **Remove from iPhone** / **Retry Keep** (D6, [09](09-keep-on-device.md)) |
| `Downloading 45%` | `Keeping 45%` (board `PH_Movies`) |
| Collections chưa cấp quyền ảnh: nút Open Movies | không cần nữa: tab Movies không phụ thuộc quyền ảnh |
| Settings › Sources nhóm Movie Sources (FS-23.01 §2) | Settings › Sources & Backup, mỗi nguồn ghi loại media ([11](11-settings-sources-backup.md)) |

## 5. Settings và Video Studio

| Hôm nay | Sau hub |
|---|---|
| Settings › Sources | đổi tên **Sources & Backup** trên mọi thiết bị; thêm Browse, Backup, Kept on iPhone |
| Settings › People and Pets, Playback, AI, … | giữ nguyên; Playback **thêm** hai hàng: công tắc **Movie Audio in Background** (D2) và **Clear Listening History…** (D11) — [06 §6](06-music-player.md), [07 §3](07-music-statistics.md) |
| Video Studio › Music › My Music (file import riêng) | thư viện Music chung ([05 §5](05-music-library.md)) |
| Câu chân trang Settings nói Collections, Statistics ở đâu | sửa theo chỗ mới |

## 6. iPad sidebar (FS-21.01 §2, chưa có code)

| FS-21.01 §2 | Sau hub |
|---|---|
| All Photos · Favorites · Videos · RAW · Recently Added | mục **Pinned** mặc định của Photos (người dùng 15/10); bỏ ghim được |
| Sources | nhóm Sources cuối mỗi tab của sidebar |
| Collections (On This Day · Albums › · smart album) | Photos: Collections · On This Day (trong Pinned) · Albums › |
| Utilities (Statistics … On Server) | Photos › Utilities (như §3) |

## 7. Không đổi

Viewer, editor, Compare, Cull, Collage, Video Studio, Share, Export, widget, Shortcuts, extension: không đổi đường vào ngoài
chỗ tab chứa chúng. Lệnh nào hôm nay đi qua tab Collections thì giờ đi qua Photos › Collections.
