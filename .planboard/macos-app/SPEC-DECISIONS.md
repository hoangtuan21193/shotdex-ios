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
