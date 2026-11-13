# FS-21.04 — Tiêu chí nghiệm thu

`FS-21.04` · kịch bản `ShotDexUITests/scripts/fs21-*.json` (chưa có) · cập nhật 2026-10-04

Máy: iPad Pro 13" iOS 26.5 (mặc định) và iOS 18.6 khi AC ghi. Thư viện mẫu 55,231 mục (54,027 ảnh + 1,204 video),
album "Iceland 2026" 212 ảnh, smart album "Night ISO 3200+" 2,411 ảnh; ảnh test không có mặt người.
Ảnh chụp bằng `Tools/sim-shot` (bắt buộc sau bước xoay). iPhone: iPhone 17 iOS 26.5 khi AC ghi.

## 1. Khung, sidebar, toolbar

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | ngang 1376×1032, thư viện mẫu | mở app | không tab bar; sidebar x 8–328 (320), mỗi hàng cao 44; toolbar từ y 24 cao 44; 4 nhóm: 5 hàng Library, Sources, Collections, 8 hàng Utilities (On This iPad đứng đầu) | ⚠️ chưa có — `design-parity` `Main` (đề xuất `fs21-shell.json`) |
| AC-2 | như AC-1, đang ở All Photos | chạm hàng Statistics | nội dung là Statistics, không có Back; sidebar không đổi, hàng Statistics mang trạng thái chọn | ⚠️ chưa có (`fs21-shell.json`) |
| AC-3 | như AC-1 | chạm Hide Sidebar | sidebar biến mất, mép trái nội dung ≤ 16pt, toolbar có Show Sidebar; chạm nó → sidebar về x 8–328 | ⚠️ chưa có |
| AC-4 | Library, mật độ mặc định, inspector đóng, lưới 7 cột | chạm Show Inspector | inspector rộng 360 ±1 bám mép phải (x 1016); lưới nằm trọn trong x 344–1000, 6 cột; đóng lại → 7 cột | ⚠️ chưa có |
| AC-5 | Library | dump toolbar | ≤ 3 cụm + ô search + đúng 1 nút nổi bật (Select); mọi nút ≥ 44×44; mọi nút chỉ có icon mang nhãn khác rỗng | ⚠️ chưa có |
| AC-6 | sidebar có Add Source, New Album, Show Albums, Eject | dump | khung chạm mỗi nút ≥ 44×44 dù glyph vẽ 32/28 | ⚠️ chưa có |
| AC-7 | Library cuộn tới ảnh thứ 600 | mở ảnh đó, chạm Back | về lưới, ô ảnh 600 thấy trọn, sidebar hiện lại như lúc mở | ⚠️ chưa có (`fs21-viewer.json`) |

## 2. Chọn nhiều, menu, bàn phím, con trỏ

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-8 | Library, 0 ảnh chọn | chạm Select rồi chạm 5 ô | dòng phụ "5 selected · …"; toolbar có Compare · Edit · Share · ⋯ · Delete · Done, không còn Select; inspector mở, tiêu đề "5 Photos" | ⚠️ chưa có — `design-parity` `IP_LibrarySelect` |
| AC-9 | đang chọn 5 ảnh | chạm Done | 0 ô chọn; toolbar về như AC-5; inspector về trạng thái trước Select | ⚠️ chưa có |
| AC-10 | Library, không ở chế độ chọn | nhấn giữ một ô 0,6 s | menu ngữ cảnh mở, không vào chế độ chọn, menu không có cột phím tắt | ⚠️ chưa có |
| AC-11 | chọn 5 ảnh | mở ⋯ | các dòng đúng thứ tự FS-01.06 §3 + Select All · Favorite · Adjust Date and Time… · Adjust Location…; Hide ở nhóm cuối | ⚠️ chưa có |
| AC-12 | bàn phím ngoài, Library | bấm ⌘F | ô search trên toolbar có con trỏ, bàn phím ảo không hiện | ⚠️ chưa có — `Tools/ui-drive` chưa có bước phím |
| AC-13 | bàn phím ngoài, sidebar hiện | bấm ⌃⌘S hai lần | lần 1 sidebar ẩn, lần 2 hiện lại | ⚠️ chưa có — như AC-12 |
| AC-14 | bàn phím ngoài, chọn 1 ảnh 2★ | bấm 4 | ô và inspector ghi 4★ trong ≤ 1 s (FS-01.12) | ⚠️ chưa có — như AC-12 |
| AC-15 | bàn phím ngoài | giữ ⌘ 1 s | bảng phím tắt hệ thống có 8 menu ShotDex · File · Edit · View · Image · Go · Window · Help, phím khớp `IP_MenuBar` | ⚠️ chưa có — kiểm tay + ảnh |
| AC-16 | trackpad | chuột phải một ô | menu có đúng tập dòng như AC-10 | ⚠️ chưa có — kiểm tay |

## 3. Kéo-thả lên sidebar

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-17 | ảnh A không thuộc "Iceland 2026" (212) | kéo A, thả lên hàng Iceland 2026 | hàng sáng nền khi A lướt qua; sau thả số đếm 213; mở album có A | ⚠️ chưa có — `Tools/ui-drive` chưa có bước kéo-thả |
| AC-18 | "Iceland 2026" 212 ảnh, đang chọn 3 ảnh ngoài album | kéo một trong ba, thả lên Iceland 2026 | số đếm 215; cả 3 ảnh trong album | ⚠️ chưa có — như AC-17 |
| AC-19 | ảnh A | kéo A lướt qua hàng "Night ISO 3200+" và Statistics rồi thả | hai hàng không sáng; số 2,411 giữ nguyên; A không đổi | ⚠️ chưa có — như AC-17 |

## 4. Bề rộng cửa sổ và xoay

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-20 | app ở Split View 1/3 (compact) | mở app | bố cục iPhone: tab bar Library · Collections · Statistics + Search, không sidebar, không inspector | ⚠️ chưa có — simctl không dựng Split View; kiểm tay |
| AC-21 | bề rộng 699 · 700 · 1099 · 1100 | gọi hàm chọn bố cục | 699 → bố cục iPhone; 700 → sidebar phủ, inspector sheet; 1099 → sidebar phủ; 1100 → sidebar ghim, inspector cột | ⚠️ chưa có — test thuần |
| AC-21b | cửa sổ 1376×1032 · 1210×834 · 1032×1376 · 834×1210 · 688×1032 | gọi hàm chọn bố cục | ghim · ghim · phủ · phủ · bố cục iPhone; chiều cao không đổi kết quả | ⚠️ chưa có — test thuần |
| AC-22 | Stage Manager ~1200pt, đang ở Statistics | thu cửa sổ về 650pt | bố cục iPhone, tab Statistics đang mở, cùng chỗ cuộn | ⚠️ chưa có — driver không đổi cỡ cửa sổ |
| AC-23 | Library ngang, chọn 5 ảnh, inspector mở | xoay sang dọc | inspector thành sheet dưới có Done, vẫn "5 Photos", 5 ô vẫn chọn; sidebar ẩn | ⚠️ chưa có — `Tools/ui-drive` + burst `Tools/sim-shot` |
| AC-24 | như AC-23 sau khi xoay | xoay về ngang | sheet đóng, cột 360 mở lại, cùng lựa chọn | ⚠️ chưa có — như AC-23 |
| AC-25 | dọc 1032×1376 | chạm Show Sidebar, rồi chạm vào lưới | sidebar phủ 320 có nền mờ sau, lưới không dịch; chạm lưới → sidebar đóng, không mở ảnh nào | ⚠️ chưa có |
| AC-26 | Viewer ngang, inspector mở | xoay sang dọc | Info là sheet dưới cao 576 có Done, cùng ảnh (thay số của FS-02.03b AC-7) | ⚠️ chưa có — `IPP16_InfoKeywords` |

## 5. iOS trước 26 và truy cập

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-27 | iOS 18.6 ngang | mở app, dump sidebar + toolbar | không tab bar; tập nhãn nút và hàng **bằng** dump AC-1 trên 26.5 | ⚠️ chưa có — agent `ios26-parity` |
| AC-27b | iOS 18.6 ngang 1376×1032 | mở app, dump + `Tools/sim-shot` | sidebar là sidebar hệ thống: x 0, rộng 320 ±1, cao bằng cửa sổ (không lề 8, không bo 22); nav bar thường cao 44 không viên kính; mỗi hàng 44 | ⚠️ chưa có — `ios26-parity` + ảnh |
| AC-28 | iOS 18.6, chọn 3 ảnh | mở ⋯ | cùng dòng, cùng thứ tự như 26.5 | ⚠️ chưa có |
| AC-29 | VoiceOver bật, ngang | quét sidebar | mỗi hàng đọc "tên, số đếm"; hàng đang chọn đọc trạng thái chọn; Albums đọc thu gọn/mở rộng; Eject T7 RAW Archive là phần tử riêng | ⚠️ chưa có — dump nhãn + kiểm tay |
| AC-30 | ổ T7 RAW Archive rút ra, VoiceOver bật | focus hàng T7 | đọc thêm "offline" | ⚠️ chưa có |
| AC-31 | cỡ chữ Accessibility 3 | mở Library | không nhãn sidebar nào cắt "…"; hàng cao theo chữ, ≥ 44; sidebar vẫn 320 | ⚠️ chưa có |
| AC-32 | cỡ chữ Accessibility 3 | mở Viewer, inspector mở | nhãn và giá trị xuống dòng, không chồng, không tràn 360 | ⚠️ chưa có |

## 6. Từng màn

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-33 | Editor ngang, 1 ảnh RAF | mở editor | toolbar có Adjust · Crop · Mask · Heal · Markup và Save cuối phải; inspector 360; không băng đĩa nổi | ⚠️ chưa có — `design-parity` `IP1_Edit` |
| AC-34 | Editor ngang, Exposure +0,65 | chạm Save | sheet Save Edit rộng 600 giữa màn có Save Changes · Save Copy; chưa chọn thì ảnh gốc không đổi | ⚠️ chưa có — `IP12_Save` |
| AC-35 | Editor dọc | mở editor | inspector vẫn là cột bên phải, không sheet; PASS `IPP1_Edit` | ⚠️ chưa có |
| AC-36 | Settings, chế độ sáng và tối | chạm gear | Settings chiếm cửa sổ, sidebar 320 có Done; ảnh 0 pixel amber; công tắc bật màu xanh hệ thống | ⚠️ chưa có — `design-parity` `IP_Settings` |
| AC-37 | Settings mở từ hàng Duplicates | chạm Done | về Duplicates, cùng chỗ cuộn | ⚠️ chưa có |
| AC-38 | danh sách lệnh ⋯ chọn nhiều, menu ngữ cảnh ô, ⋯ Viewer, menu bar | dựng cho bố cục iPad và iPhone | hai bên cùng một tập, trừ đúng 2 ngoại lệ New Window và Activity | ⚠️ chưa có — test thuần |
| AC-39 | Resize 8 ảnh, Delete Originals tắt | gạt Delete Originals | nút toolbar đổi ngay "Resize 8 Photos" → "Resize 8 Photos and Delete Originals", thấy không cuộn | ⚠️ chưa có — `IP_Compress` |
| AC-40 | Xuất collage ngang | mở Export | Share… và Save to Photos trên toolbar; không nút nào ghim đáy; inspector 360 | ⚠️ chưa có — `IP_CollageExport` |
| AC-41 | Advanced Search có nháp 1 điều kiện | chạm ngoài form sheet | sheet vẫn mở, hiện Discard Changes? | ⚠️ chưa có |
| AC-42 | cài mới, quyền Photos chưa hỏi | chạm Continue; rồi Add Photos Library; chọn Limited | sau Continue: thư viện trống 3 thẻ, chưa có hộp quyền; sau Add: hộp quyền; sau Limited: banner Limited Access + Manage | ✅ 2026-11-13 — `EmptyLibraryView.swift`, `OnboardingScreen.swift`; Duo inner + iPhone 26.5 + iPad: Continue không hỏi quyền, 3 thẻ, hộp quyền chỉ khi Add Photos Library (`ShotDexUITests/scripts/fs21-onboarding*.json`); nhánh Limited dùng banner sẵn có, chưa chụp lại |
| AC-43 | Statistics ngang, 7 biểu đồ | mở | 3 cột rộng 328 ±1; Insights rộng 1016 | ⚠️ chưa có — `IP_Statistics` |

## 7. Từ các quyết định 2026-10-04

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-44 | trackpad, Library, chưa ở chế độ chọn | ⌘-chạm ô thứ 3; làm lại với ⇧-chạm | vào chế độ chọn, đúng 1 ô chọn, dòng phụ "1 selected · …", toolbar có Done; ảnh không mở | ⚠️ chưa có — driver không có phím bổ trợ; kiểm tay |
| AC-45 | trackpad, đang chọn ô 3 | ⇧-chạm ô 10; rồi ⌘-chạm ô 5 | sau ⇧: 8 ô 3…10 chọn; sau ⌘: 7 ô, ô 5 bỏ | ⚠️ chưa có — như AC-44 |
| AC-46 | bàn phím ngoài, Viewer ngang, inspector mở | bấm I; I; ⌥⌘I; ⌘I | inspector đóng; mở; đóng; form sheet Get Info 700×640 mở, inspector không đổi | ⚠️ chưa có — `Tools/ui-drive` chưa có bước phím |
| AC-47 | dọc 1032×1376, sidebar ẩn, index đang chạy | nhìn toolbar Library; mở sidebar | dòng phụ là tiến độ index (BD-03.04), không phải "54,027 photos · …"; sidebar mở → dòng phụ về số đếm, tiến độ ở chân sidebar | ⚠️ chưa có — dump dòng phụ |
| AC-48 | ngang, index đang chạy | chạm Hide Sidebar; chờ index xong | dòng phụ hiện tiến độ; xong → về "54,027 photos · 1,204 videos" trong ≤ 2 s | ⚠️ chưa có |
| AC-49 | Library ngang, mật độ mặc định, inspector đóng | pinch mở rộng một nấc; mở inspector; đóng mở lại app | số cột < 7; mở inspector → ít cột hơn nữa; sau khi mở lại cùng mật độ, cùng số cột | ⚠️ chưa có — `Tools/ui-drive` pinch + dump |
| AC-50 | Library ngang, sắp theo ngày | dump lưới | có đầu nhóm "Monday, September 28 · Kyoto · 48 photos"; cùng thư viện trên iPhone 17: 0 đầu nhóm | ⚠️ chưa có — `design-parity` `Main` |
| AC-51 | 8 câu Recents | chạm ô search trống | popover rộng 400 ±1 có các câu Recents dạng hàng + Clear Recent Searches; 0 thẻ Recents trên trang | ⚠️ chưa có — `IP_Search` |
| AC-52 | chế độ sáng, iPad và iPhone 17 | mở Viewer, mở inspector / Info | nền vùng ảnh và inspector sáng (độ sáng điểm nền > 0,9); chế độ tối → nền tối | ⚠️ chưa có — `Tools/sim-shot` hai chế độ |
| AC-53 | iPhone 17 và iPad | mở Settings | mục đầu tên "Sources"; 0 hàng tên "Photo Library" trong cây Settings; pane không có thẻ Your library | ⚠️ chưa có — dump |
| AC-54 | iPhone 17, editor 1 ảnh | dump dải công cụ | có "Adjust", "Crop"; 0 nhãn "Edit", "Transform"; panel vẫn cao 246 | ⚠️ chưa có — `design-parity` canvas iPhone |
| AC-55 | iPhone 17 | mở ⋯ Library; mở ⋯ Viewer | Library có Grid / List và Go to Date…; Viewer có Rotate Counterclockwise, Rotate Clockwise, Print… | ⚠️ chưa có — dump menu |
| AC-56 | iPhone 17, Duplicates nhóm 3 ảnh; Statistics thẻ donut | mở ⋯ nhóm; ⋯ thẻ, đổi kiểu | nhóm có "Keep All 3 Photos"; thẻ vẽ cột, còn sau khi mở lại app | ⚠️ chưa có — dump menu + ảnh |
| AC-57 | Collage ngang, 6 ảnh, 4 ô | mở; giữ Before and After 1 s; mở ⋯ | panel trái có 2 ảnh chưa đặt; khi giữ thấy bản gốc, thả về; ⋯ có Discard. 0 ảnh chưa đặt → không panel trái | ⚠️ chưa có — `design-parity` `IP_Collage` |
| AC-58 | Resize 8 ảnh, dọc 1032×1376 | mở | inspector là cột 360 ±1 bên phải, không sheet; "Resize 8 Photos" trên toolbar | ⚠️ chưa có — `IPP23_Compress` (chưa vẽ) |
| AC-59 | dọc 1032×1376, Editor và Viewer | dump toolbar | mọi nút toolbar ≥ 44×44 | ⚠️ chưa có — `design-parity` `IPP1_Edit` |
| AC-60 | cài mới, iPad và iPhone 17 | mở app | thẻ chào có "Your photos stay where they are"; iPad: Continue rộng 320 ±1, cao 50 | ✅ 2026-11-13 — iPad dump: Continue 320 rộng; cao 48→50 (padding 7) sau lần đo, chưa đo lại |

**Chưa chứng minh được:** AC-1…AC-60 (kể cả AC-21b, AC-27b) — chưa có code. AC-12…AC-16, AC-17…AC-19, AC-20, AC-22,
AC-44…AC-46 cần năng lực driver chưa có (phím, phím bổ trợ, kéo-thả, Split View, đổi cỡ cửa sổ) hoặc kiểm tay.
