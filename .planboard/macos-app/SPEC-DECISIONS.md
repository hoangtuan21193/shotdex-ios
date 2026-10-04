# Quyết định cho các ⚠️ CẦN QUYẾT của spec (hỏi trong chat 2026-10-04)

## FS-19
- iPhone/Duo có đủ nguồn thư mục/ổ USB-C và server được index (giữ luật "phone có mọi tính năng iPad") — cần board PH/DI/DC.
- Hash: nhanh trước (kích thước + 3×64 KB), hash đầy đủ chạy nền trước khi gộp bản sao.
- Hash chỉ phần dữ liệu ảnh (bỏ khối metadata).
- Ảnh Photos tham gia hash: đọc luồng bản gốc (kể cả tải iCloud), băm xong bỏ, không lưu file — không tăng dung lượng ổ; mỗi ảnh chỉ-iCloud tải trọn một lần (PhotoKit không đọc theo đoạn).
- Khoá ảnh: id nội bộ mới + bảng bản sao (Photos asset / file / file NAS trỏ về id).
- Cờ trong .xmp: Reject = sao −1, Pick = trường riêng ShotDex.
- Xung đột: bên đổi sau cùng thắng; hai bản sao khác sidecar lúc index → sidecar mới hơn thắng rồi ghi cho bản kia.
- Bản sao offline: ghi khi online lại theo giá trị hiện tại.
- Album: album riêng của ShotDex chứa mọi nguồn, album Photos vẫn hiện.
- Xoá ảnh nhiều bản sao: chỉ bản trong nguồn đang xem; ở All Photos hộp xác nhận liệt kê từng bản để chọn, mặc định không đụng bản backup.
- Nơi không có Thùng rác: xoá hẳn sau hộp thoại đỏ thứ hai.
- Recipe: DB theo id + vùng ShotDex trong sidecar.
- Đọc rating máy ảnh/XMP nhúng với ảnh file (ảnh Photos vẫn theo FS-01.12).
- Develop settings Lightroom: chỉ khi người dùng ra lệnh (Import Lightroom Edits qua FS-03.14b).
- Dữ liệu mồ côi giữ 30 ngày.
- Ảnh ẩn: mục Hidden trong Collections.
- Gói 16 điểm nhỏ: theo mặc định (từ chối thư mục chồng nguồn; JPEG có `<tên>.JPG.xmp` khi tắt ghép; Keep Photos | Hide Its Photos; placeholder cloud không tự tải, không tính thống kê; cache có trần; cache ở Application Support loại khỏi backup; gộp hai cache; thứ tự mở bản sao ổ trong → Photos có sẵn → ổ ngoài → server → iCloud; bỏ Backup Source; sửa câu Lightroom/RAW; server không quét theo giờ; sửa board MAC_Duplicates; Merge file chỉ rating/cờ/keyword; favorite file = DB + sidecar; cờ dùng chung bảng Cờ; iPad bỏ Import to Library, Save to Photos là lệnh xuất).

## FS-18
- Rời ảnh Photos khi chưa Done (◀, Esc, ảnh khác, đóng cửa sổ, ⌘Q): **tự Done**.
- Editor dưới 1100: thu gọn (tool switch thành icon, inspector đè lên ảnh khi mở); cửa sổ không tự nở.
- Collage, Resize, Combine Photos mở trong cửa sổ chính như Editor; ⌥⌘O mở cửa sổ riêng.
- **macOS 15 trở lên, chỉ Apple silicon** → bản Mac có nhánh trước Liquid Glass (như iOS trước 26).
- Kiểm thử: target unit test macOS + UI test macOS có driver JSON (mở rộng Tools/ui-drive cho Mac).
- NF-05: Mac được có cách thao tác riêng (menu, phím, cửa sổ, kéo thả) miễn mọi việc vẫn làm được trên iPhone/iPad.
- Kéo ảnh ra Finder: bản đã chỉnh nếu có, không thì gốc; giữ ⌥ để lấy gốc.
- Thả file ảnh lẻ lên cửa sổ: hỏi — thêm thư mục chứa nó làm nguồn, hoặc chép vào Photos.
- Gói 13 điểm nhỏ theo mặc định: Save as Copy `<tên> (edited).jpg` cạnh gốc / vào Photos, Combine lưu cạnh khung đầu, trùng tên ` (2)`; đầu nhóm ngày có trên Mac (DESIGN §10.2 ngoại lệ màn rộng); Move N Rejected… lên toolbar Cull; Get Info nhiều ảnh sửa chung, ô khác nhau "Mixed"; phím Video A/B/T/N giữ và thêm vào FS-12.17b; "." = Favorite, ←/→ lùi-tiến; một bảng phím Editor chung Mac + iPad có bàn phím; tên lệnh "Move N Rejected…" khi file đi Thùng rác, menu cùng chữ với nút; viết mục Mac vào DESIGN.md trước /plan; vùng bấm Mac theo chuẩn con trỏ (≥ 20×16), NF-06 ghi ngoại lệ; popup Source ở Statistics là bộ lọc tạm, biểu đồ có điều kiện Source riêng giữ điều kiện của nó; thêm trục Giờ trong ngày và Thứ trong tuần vào FS-07.01 mọi thiết bị; Widgets không có trên Mac bản đầu, Privacy → pane Sources.

## FS-21
- Bố cục theo điểm cố định: < 700 bố cục iPhone · 700–1099 sidebar lớp phủ · ≥ 1100 sidebar ghim.
- iPad trước iPadOS 26: sidebar/toolbar hệ thống của iPadOS 17/18 (không giả kính).
- Editor iPhone: đổi tên công cụ theo (Adjust/Crop), giữ bố cục iPhone.
- Viewer theo sáng/tối ở mọi thiết bị.
- Gói 13 điểm nhỏ theo mặc định: ⌘/⇧-chạm bằng con trỏ khi chưa chọn → vào chế độ chọn với ô đó; I trần bật/tắt inspector, ⌘I Get Info, ⌥⌘I inspector; số cột theo mật độ đã lưu + pinch (7/6 là mặc định); sidebar ẩn → dòng phụ toolbar hiện tiến độ index; board dọc nút 44; List mode, Print, Go to Date, Keep All N, Rotate, đổi kiểu biểu đồ thêm vào iPhone qua ⋯, New Window/Activity là ngoại lệ nền tảng (NF-05); đầu nhóm ngày có trên màn rộng; Recents dạng hàng trong popover gợi ý (sửa FS-01.03b phần iPad); trang album theo board, sửa DESIGN §10.1d/e; Settings "Photo Library" → "Sources" mọi thiết bị; Collage thêm giữ-xem-gốc, ⋯ Discard, khay ảnh chưa đặt vào board; công cụ tầng D dọc dùng cột inspector như Editor, vẽ board trước /plan; câu chào "Your photos stay where they are" mọi thiết bị, Continue 320 trên iPad.

## FS-20
- Lối vào: hàng thẻ trong sidebar nhóm Sources, chạm mới mở; không tự mở, không banner.
- Đọc thẻ: cả hai — khung truy cập máy ảnh của hệ thống + chọn ổ một lần nhớ bằng bookmark.
- "Đã nhập": lịch sử nhập (tên gốc + byte + giờ chụp) hiện ngay, hash chạy nền tinh chỉnh; ảnh đã nhập bị xoá ở đích lại thành New.
- Gói 5 điểm theo mặc định: chép video (MP4/MOV) + WAV kèm ảnh, bỏ THM/file hệ thống máy; một bộ token tên chung Import + Export, sửa cả 07b; .xmp tắt vẫn ghi cho lượt nhập có preset; iPad ra nền: iPadOS 26 xin chạy tiếp, trước 26 dừng như Stop + Import Remaining; iPhone và Duo có nhập thẻ, vẽ board PH_/DI_/DC_Ingest.

## FS-01.08c Compare
- Bỏ nút Sync Zoom and Pan, luôn đồng bộ ở mọi máy — sửa board iPad/Mac.
- Reject trong Compare mở từ Duplicates ghi cờ thật (còn sau khi đóng) — sửa 08 §2 + DESIGN §9.
- Mac Survey: Delete N Photos trên toolbar trước Edit như iPad; Keep Only This ở menu chuột phải + menu Photo; ⌘⌫ — sửa board MAC_Compare.
- Gói 6 điểm theo mặc định: segmented cờ iPad 44pt; iPhone/Duo đang phóng một ngón kéo ảnh, chỉ ở Fit vuốt đổi candidate; Survey > 6 thu ô tới cỡ tối thiểu rồi cuộn; 0 Reject → Delete mờ; trộn nguồn → một hộp liệt kê từng đích (Photos vẫn qua hộp hệ thống); 2-Up từ một ảnh → Candidate = ảnh kế trong lưới.
- Theo FS-19: thư mục iPad không Thùng rác → xoá hẳn sau hộp đỏ thứ hai; cờ ảnh file/NAS ở bảng Cờ chung, Reject = sao −1 trong .xmp.

## Vòng dọn (sau khi agent áp quyết định)
- Save as Copy mọi thiết bị: `<tên> (edited).jpg`, trùng thêm ` (2)`; nút iOS đổi thành "Save as Copy" (FS-03.06).
- Tên lệnh xoá Reject theo đích ở mọi nơi (Cull, Compare, mọi thiết bị): Move N… (có file vào Thùng rác) · Delete N… (chỉ Photos / xoá hẳn) · Hide N… (chỉ NAS).
- NF-05: lệnh Mac có thì iOS cũng có — popup Color Space (FS-03.04/07b), Advance After (FS-01.12b), ô Sync theo nhóm (FS-03.09b) sang iPhone/iPad.
- Giữ mọi số/luật agent tự đặt: cache 2/5/10/25/50 GB (Mac 25, iOS 5); hash đầy đủ nền, gộp khi khớp; hộp xoá chỉ tick bản đang mở; New Album theo nguồn; Local Network/Cloud Folders dẫn tới nguồn; rating file ở bảng riêng; Clear index giữ id+hash; Survey tối thiểu nửa ô; huỷ hộp hệ thống chỉ bỏ phần Photos; auto-Done không đổi không ghi, lỗi ở lại; `<khung đầu> (Panorama).jpg`; Resize → Pictures › ShotDex Resized; Show Filter Bar đường tắt; Duo trong lưới phẳng; Adjust/Crop cả Duo; pane Sources bỏ thẻ Your library; khay Collage ẩn khi rỗng; AC index ≤ 2 s, Viewer nền sáng > 0,9.

## Schema FS-19 (sau review data-migration 2026-10-04)
- Id ảnh: ảnh Photos có sẵn giữ chuỗi localIdentifier làm id; ảnh mới (file/NAS) lấy UUID. Không viết lại bảng vệ tinh, UserDefaults, widget. Migration chỉ tạo photos/copies/sources, backfill từ hợp assetId của MỌI bảng (kể cả ảnh chưa index ở .limited).
- photo_metadata: một dòng mỗi ảnh, điền từ bản sao chính; không thêm cột sourceId/hidden vào nó.
- File bị ghi đè ảnh khác khi bản sao khác còn ảnh cũ: tách — bản đổi nhận id mới, mang bản chép dữ liệu người dùng.
- Gộp: một transaction, luật từng bảng — trường một giá trị (sao, cờ, tiêu đề, caption, recipe) bên đổi sau cùng thắng (cần timestamp); tập hợp (keyword, album, ẩn) hợp lại; dấu chờ sidecar trỏ sang id thắng; bảng bí danh id thua → id thắng.
- Chủ dữ liệu: bảng ShotDex giữ sao/favorite/keyword cho ảnh có cả bản Photos lẫn file, đẩy sang Photos qua đường chờ ghi.
- Đi kèm: bảng recipe mới (có updatedAt); khoá Duplicates (strictness, sourceId, photoId) + duplicate_scan_state có sourceId; hash ở bảng riêng có (algo, version), UNIQUE(algo, fullHash) khi có, index thường cho fastHash; bản sao có id bền, UPSERT trên UNIQUE(sourceId, relPath chuẩn NFC + case-fold), không FK cascade; ẩn ảnh = mọi bản sao ẩn; dọn 30 ngày loại trừ server_uploads, server_downloads, lịch sử nhập thẻ; FS-01.12 AC-9 đổi theo luật 30 ngày; sweep neo vào bảng photos thay photo_metadata; filter keyword đọc cả hai bảng; widget cần bộ nạp ảnh file; index copies(sourceId, photoId), copies(photoId, online), photos(orphanedAt) partial.

## Planboard mac-ipad-v2 (2026-10-04)
Một vòng, 10 câu + 32 mục Claude tự quyết. Chi tiết: `.planboard/mac-ipad-v2/DECISIONS.md`.

**Chọn khác đề xuất (3):**
- **Q1** Hide trên ảnh có bản Photos và bản file/NAS → hai lệnh riêng **Hide in Photos** · **Hide in ShotDex Only**; "Hide" trơn chỉ khi ảnh nằm ở một nơi (FS-19.04 §3, AC-73).
- **Q4** iPhone/Duo ngoài: so sánh **chỉ** từ chế độ chọn ≥ 2 ảnh — không "Compare with Next", không nút trên Viewer Single; màn rộng giữ 2-Up từ Single (FS-01.08c §2, §7, AC-26).
- **Q10** Kiểm cần máy thật (Mac macOS 15, iPhone, ổ T7, thẻ/đầu đọc/máy ảnh) → bỏ qua, ghi "chưa kiểm (cần máy thật)": FS-18 AC-14/44/62/63/65, FS-20 AC-20 + phần thật của AC-10/27; FS-19 không đo M1–M3; không máy ảo, không script tay.

**Đồng ý mặc định (7 câu):**
- Q2 Nhập thẻ xong: banner "You can remove … now", công tắc Eject chỉ hiện khi nhả được.
- Q3 Giữ Pause khi nhập thẻ: dừng sau file đang chép, Resume chạy tiếp (FS-20 thêm AC-28).
- Q5 Lưới iPad/Mac mặc định 7 cột, 6 khi mở inspector.
- Q6 Nhấn giữ rồi kéo ảnh, không cần Select (cả iPhone).
- Q7 Editor iPad: inspector 360 cố định bên phải, giữ ghim ảnh tham chiếu.
- Q8 iPad: Viewer mở trong cửa sổ, sidebar gọi lại được; Settings giữ cover.
- Q9 Universal Purchase, cùng bundle id `com.hoangtuan.shotdex`.

**Đồng ý mặc định (32 mục tự quyết):**
- A1 Pipeline mới `SourceIndexPipeline` cho thư mục + NAS; `IndexPipeline` PhotoKit giữ nguyên.
- A2 Hash phần dữ liệu ảnh: JPEG, HEIC, CR3, DNG, ARW, NEF, TIFF; định dạng khác băm cả file.
- A3 Bảng riêng sao/keyword ảnh file; `photo_recipes` cho mọi bản sao, Done trên bản Photos ghi thêm vào Photos.
- A4 `.xmp`: chỉ vá mục ShotDex quản, còn lại giữ từng byte.
- A5 Ảnh hiện khi còn ≥ 1 bản sao xem được; tính lúc truy vấn, đo 55k.
- A6 Cache preview tự chứa, bỏ preview trước; gộp cache NAS cũ; 5 GB iOS, 25 GB Mac.
- A7 Tên lệnh xoá theo đích (Move/Delete/Hide N…); giữ "Delete N from This Device"; huỷ hộp Photos chỉ giữ phần Photos.
- A8 Một `IndexEstimate` cho Photos và nguồn, làm tròn phút.
- A9 Áp chốt cũ vào tài liệu: dấu giữ 30 ngày, Save to Photos thay Import to Library, Duplicates theo nguồn, Merge file chỉ sao/cờ/keyword, album ShotDex mọi nguồn.
- A10 Sửa AC-33 (trần byte), AC-66 (widget + Recents); thêm AC-69…72.
- A11 Chép → đọc lại so SHA-256 → đổi tên; dùng lại writer Export.
- A12 Chạy nền iOS 26 dùng chung với tải NAS; `backupPath` nhớ qua lần mở.
- A13 Thẻ dạng ổ đọc kiểu ổ, máy ảnh USB qua ImageCaptureCore; thẻ cắm hiện trong 2 s.
- A14 Nhóm ngày theo ngày file rồi tinh theo EXIF; ảnh nhập vào ổ đang rút vẫn Imported.
- A15 Mẫu tên mặc định `{date}_{originalNumber}`; chip Text chèn chữ thường.
- A16 Compare là chế độ của Viewer; `WindowClass` chung.
- A17 Compare chỉ ghi cờ Reject thật; dấu Duplicates nâng thành Reject.
- A18 Một bộ định tuyến xoá cho Cull, Compare, Duplicates; lỗi → banner + Try Again.
- A19 iPad Compare dùng chrome Viewer tới khi có toolbar FS-21; theo sáng/tối của Viewer.
- A20 Sidebar hệ thống (`NavigationSplitView`); inspector 360 / sheet khi hẹp; iPhone, Duo giữ tab bar.
- A21 Một `CommandCatalog` cho toolbar, ⋯, menu nhấn giữ, menu bar; Mac dùng lại.
- A22 `ToolInspectorLayout` chung cho Collage, Resize, Combine, Editor.
- A23 "Adjust Date & Time…", "Adjust Location…"; giữ pill "Keep All N Photos".
- A24 Panel chỉnh ảnh iPhone giữ 264, sửa tài liệu.
- A25 `/spec FS-21` thêm AC cho Trips, Places, trang album, Duplicates, Combine, Cull, cắt video, phím . và Space trước khi làm.
- A26 Target `ShotDexMac` riêng, chung Domain/Data; kiểu khung/lệnh ở `Domain/Shell/`.
- A27 `PlatformImage` typealias; `MacTheme` chỉ Mac.
- A28 AppKit cho lưới, ảnh phóng to, timeline; `Table` cho ⌘2.
- A29 Undo qua `UndoManager` của cửa sổ (`UndoRegistrar`).
- A30 13 màn Mac không AC: `design-parity` + AC FS gốc; AC mới chỉ cho Activity và Support.
- A31 Phím Viewer một luật mọi thiết bị: "." = Favorite, ←/→ lùi tiến.
- A32 Sửa số liệu FS-18 05 §1 theo số đo thật.
