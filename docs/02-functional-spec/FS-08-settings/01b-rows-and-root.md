# FS-08.01b — Trang gốc, kiểu hàng và thẻ thư viện

`FS-08.01b` · `Features/Settings/SettingsScreen.swift` · `SettingsRowLabel.swift` · board `PH_/IP_/DI_/DC_Settings`
trên canvas ShotDex App Screens · cập nhật 2026-10-03 · duyệt trên canvas 2026-10-03

**Một câu:** Settings đọc như Settings của Mochi — một dòng nói màn này để làm gì, một thẻ trạng thái thư viện, rồi
các nhóm mà **mỗi hàng nói giá trị hiện tại của nó**, không phải một danh sách dài phải cuộn để tìm.

## 1. Trang gốc

| Phần | Nội dung |
|---|---|
| Tiêu đề | **Settings** cỡ lớn, dưới là một dòng phụ: "How ShotDex reads, shows and shares your photos" |
| Tìm kiếm | ô Search ngay dưới dòng phụ (luật tìm theo hàng giữ nguyên, [01 §5](01-layout-and-search.md)) |
| Thẻ **Your library** (gánh luôn các hàng Indexed Photos and Videos, Last Indexed, Re-index cũ của FS-08.02) | "55,231 photos · 1,204 videos · indexed" · một vạch tiến độ · "Up to date · 2 min ago" (đang index: "Reading photo info · 64%") · nút chữ **Re-index**; bo `r-lg` |
| Nhóm | tên viết thường như câu: Library and viewing · Sharing and export · Widgets and notifications · Help |
| Chân trang | "ShotDex 1.0 (24)" giữa + một câu nói những thứ khác nằm ở đâu (Collections, Statistics) |

- Ở bố cục **hẹp** trang gốc là danh sách **mục**: chạm một hàng mở trang của mục đó (chồng lên). Thay luật cũ
  "bố cục hẹp không đổi một dòng nào": danh sách dài một trang đã là chỗ người ta cuộn đi tìm một công tắc.
- Các nhóm của bố cục hẹp và cột mục của bố cục rộng dựng từ **cùng một danh sách mục**, cùng biểu tượng,
  cùng dòng giá trị — một nguồn, hai cách xếp.

| Nhóm | Hàng (mở trang) | Dòng giá trị |
|---|---|---|
| Library and viewing | Sources (FS-19, board `PH_SettingsSources`) | quyền + điều kiện index ("Full Access · indexing on Wi-Fi only") |
| | Display | các thông số hiện trên ô lưới ("ISO, aperture, focal length, file type") |
| | Playback | "Autoplay on · Full HDR off" |
| | AI | "Subtitles: Claude · Search: Apple Intelligence" / "Not set up" ([07](07-ai-providers.md)) |
| | People and Pets | "41,870 of 55,231 photos scanned" |
| | Camera Database | "6 cameras need a sensor format" / "Every camera is known" |
| Sharing and export | Metadata When Sharing | mức mặc định + "each share can change it" |
| | Resize Presets | "4 built-in · 3 custom" |
| | File Servers | tên 2 kết nối đầu + "and N more" / "None yet" |
| Widgets and notifications | Widgets | "Photo widget · 3 designs" |
| | Notifications | "On This Day reminder at 9:00 AM" / "Off" |
| Help | Support | "No account needed" — không đếm reply chưa đọc: đếm cần gọi server support mỗi lần mở Settings, trái NF-03 |

## 2. Kiểu hàng

- Mỗi hàng: **ô biểu tượng** bo 10 · tiêu đề `.body` · **một** dòng giá trị `.subheadline` màu phụ · chevron. Ô
  36pt ở hàng trang gốc và trang mục, **28pt** ở cột mục của bố cục rộng (hàng 44pt, giá trị ngắn đặt bên phải:
  "76%", "6 unknown", "3 designs", "9:00 AM", "1 reply").
- Màu ô theo **từng mục** (mỗi mục một màu hệ thống, như board), glyph màu đó bản tương phản cao, nền cùng màu 14% (sáng) /
  24% (tối). Không dùng accent amber — accent chỉ cho trạng thái do ShotDex vẽ (DESIGN §10.6).
- Thay luật cũ "chỉ cột mục mới có biểu tượng, không có nền bo tròn": dòng giá trị là phần làm hàng có ích, ô
  màu là phần làm mắt tìm ra nhóm; cả hai cùng có ở mọi bề rộng.
- Hàng trong trang mục (Access, Use Cellular Data…) dùng cùng kiểu: ô + tiêu đề + dòng giá trị; công tắc và số
  đứng bên phải thay chevron. Hàng phá huỷ: chữ đỏ, ô đỏ, **không chevron** (mở alert, không mở trang).
- Dòng giá trị **là trạng thái thật**, đọc cùng nguồn với màn con — không phải câu mô tả cố định.

## 3. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh |
|---|---|---|---|---|
| AC-1 | iPhone 17, thư viện 55,231 ảnh đã index | mở Settings | thấy tiêu đề, dòng phụ, Search, thẻ Your library ghi đúng số ảnh/video, 4 nhóm tên viết thường; không thấy hàng công tắc nào ở trang gốc | ⚠️ chưa có (`settings-root.json`) |
| AC-2 | như AC-1 | chạm hàng Photo Library | trang Photo Library chồng lên, có Back "Settings", hàng Access ghi "Full Access" | ⚠️ chưa có |
| AC-3 | Use Cellular Data bật | quay về trang gốc | dòng giá trị Photo Library đổi thành "Full Access · indexing on Wi-Fi and cellular" | ⚠️ chưa có |
| AC-4 | đang index 64% | mở Settings | thẻ ghi "Reading photo info · 64%", vạch dài 64% ±2 | ⚠️ chưa có |
| AC-5 | iPad 13" ngang | mở Settings | cột mục 320pt, mỗi mục có ô 28pt + giá trị ngắn bên phải; trang Photo Library bên phải có thẻ Your library ở đầu | ⚠️ chưa có |
| AC-6 | quyền `.limited` | mở Settings | dòng giá trị Photo Library ghi "Limited Access", thẻ Your library ghi số ảnh nhìn thấy | ⚠️ chưa có |
| AC-7 | VoiceOver, trang gốc | focus hàng Resize Presets | đọc "Resize Presets, 4 built-in, 3 custom, button" — ô biểu tượng không đọc riêng | ⚠️ chưa có |
| AC-8 | gõ "cellular" vào Search ở trang gốc | chạm kết quả | mở trang Photo Library, cuộn tới hàng Use Cellular Data và nháy 1,2 s ([01 §5](01-layout-and-search.md)) | ⚠️ chưa có |
| AC-9 | chế độ tối | mở Settings | ô biểu tượng nền 24%, chữ đạt 4.5:1, không có màu amber nào | ⚠️ chưa có |
