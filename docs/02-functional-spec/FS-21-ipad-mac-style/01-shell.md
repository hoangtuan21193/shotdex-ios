# FS-21.01 — Khung app iPad: sidebar, toolbar, inspector

`FS-21.01` · gốc app + nhánh màn rộng của mọi màn · board `Main`, `IP_LibrarySelect`, `IP_MenuBar` · cập nhật 2026-10-04

**Một câu:** một cửa sổ ba vùng — sidebar 320 trái, nội dung giữa, inspector 360 phải — với toolbar 44 ở trên,
dựng từ sidebar và toolbar của hệ thống.

## 1. Khung (ngang 1376×1032)

| Vùng | Số đo |
|---|---|
| Lề trên | 24pt trống cho status bar hệ thống; hàng toolbar bắt đầu ở y 24 |
| Sidebar | nổi, cách mép 8, rộng **320**, bo 22; nội dung bắt đầu ở x 344 |
| Nội dung | x 344 → 1360 (1016pt) khi inspector đóng; cuộn **dưới** toolbar |
| Inspector | rộng **360**, bám mép phải, cao hết cửa sổ; nội dung còn x 344 → 1000 (656pt) |
| Sheet · popover | form sheet ≤ **700×640** giữa cửa sổ, nền mờ sau · popover ≤ **400×560** có mũi tên về nút mở nó |

- Chữ theo kiểu chữ hệ thống ở cỡ mặc định: thân 17, phụ 15 / 13, tiêu đề mục 20 đậm vừa, tiêu đề lớn 28 đậm;
  sàn 11 (nhãn định dạng trên ô, trục biểu đồ). Số thay đổi dùng chữ số đều bề rộng.
- Nút và ô nhập cao 44, bo 12; segmented cao 36. Không nút nào trên toolbar thấp hơn 44.

## 2. Sidebar

| Nhóm | Hàng |
|---|---|
| (không tiêu đề) | All Photos · Favorites · Videos · RAW · Recently Added |
| **Sources** `+` | từng nguồn: Photos Library, thư mục, ổ ngoài (nút Eject), server — trạng thái theo [FS-19](../FS-19-photo-sources/README.md) |
| **Collections** `+` | On This Day · Albums › (mở ra danh sách phẳng) · các smart album |
| **Utilities** | On This iPad · Statistics · Duplicates · Collages · Video Projects · On Server — bấm tiêu đề nhóm mở trang Utilities: card Statistics trên cùng, rồi Library · Create · Elsewhere (`IP_Utilities`, 2026-10-24; Places và Trips đã gỡ khỏi app) |

- Hàng cao **44**, nhãn 17, icon 22 màu accent, số đếm 15 màu phụ bên phải; tiêu đề nhóm 15 đậm vừa. Tối đa 2 cấp.
- Đầu sidebar: **Hide Sidebar** trái, **Settings** (gear) phải. Chân: trạng thái index — "Up to date · indexed
  2 min ago", đang chạy thì tiến độ ([BD-03.04](../../01-basic-design/BD-03-metadata-indexing-flow/04-progress-and-background.md)).
  Sidebar ẩn thì tiến độ lên dòng phụ toolbar ([01b §2](01b-windows-and-access.md)).
- Thẻ nhớ đang cắm là một hàng trong nhóm Sources; chạm mới mở màn nhập — không tự mở, không banner ([FS-20](../FS-20-card-ingest/README.md)).
- Chạm một hàng = đổi nội dung, không đẩy màn. Hàng đang chọn nền xám, không accent.
- Nhận kéo-thả: ảnh thả lên một album thường → thêm vào album; thư mục từ Files thả lên Sources → thêm nguồn
  (FS-19). Smart album, Utilities, hàng Library không nhận: không sáng lên khi kéo qua.
- `+` của Collections mở menu New Album · New Smart Album; `+` của Sources mở sheet Add a Source (FS-19).

## 3. Toolbar

- Trái: Show/Hide Sidebar (chỉ khi sidebar ẩn), Back/Forward khi có lịch sử, tiêu đề 20 + dòng phụ 13
  ("54,027 photos · 1,204 videos", "5 selected · 68.4 MB").
- Phải: **≤ 3 cụm viên kính** + ô tìm kiếm + **một** hành động nổi bật ở mép phải. Hành động nổi bật không bao giờ
  là xoá; Delete là nút icon đỏ trong cụm.
- Viên kính cao 44, nút 44 rộng, glyph 20, khoảng giữa cụm 12. Nút icon có nhãn VoiceOver đúng tên lệnh.
- Library: `[Grid · List · Filter and Sort]` `[Share · Show Inspector]` `[Search]` **Select**.

## 4. Inspector

- Chỗ cho "thông tin của thứ đang chọn": ảnh (Viewer), lựa chọn nhiều ảnh (Library), tuỳ chọn của
  công cụ (Collage, Resize, Export, Combine). Không có tiêu đề "Photo Info" và Done — đóng bằng nút toolbar.
- Hàng 44, nhãn 17, giá trị 15, slider núm 28. Mở inspector ở Library: lưới bớt một cột theo mật độ đã lưu — ở mật
  độ mặc định 7 → 6 ([01b §1](01b-windows-and-access.md) về số cột).
- Nhớ mở/đóng **theo từng màn**, như luật nhớ lần cuối của Photo Info ([FS-02.03b](../FS-02-photo-detail/03b-info-inspector.md) §2).

## 5. Chọn nhiều

- **Select** (nút chữ) vào chế độ chọn; nút thành **Done**. Chạm ô = chọn/bỏ; kéo hai ngón hoặc kéo con trỏ = chọn
  cả dải. Nhấn giữ một ô vẫn mở menu ngữ cảnh, không vào chế độ chọn ([FS-01.06](../FS-01-library/06-multi-select.md) §1).
- Toolbar khi chọn: `[Grid · List · Filter]` **Compare** · **Edit** `[Share · ⋯ · Delete]` Hide Inspector · Done.
  Menu ⋯ giữ đúng danh sách của FS-01.06 §3 (thêm Select All · Favorite · Adjust Date and Time… · Adjust Location…).
- Inspector tự mở khi có ≥ 1 ảnh: số ảnh, khoảng ngày, dung lượng, nguồn, máy/ống, keyword chung, sao, cờ, Favorite.
- Con trỏ: **⌘-chạm hoặc ⇧-chạm một ô khi chưa chọn gì** vào chế độ chọn với đúng ô đó (như Files trên iPad). Đang chọn:
  ⌘-chạm bật/tắt một ô, ⇧-chạm chọn cả dải từ ô chọn cuối. Chạm thường bằng con trỏ vẫn mở ảnh như ngón tay.

## 6. Menu nhấn giữ và chuột phải

- Nhấn giữ (ngón) và chuột phải (trackpad) mở **cùng một** menu ngữ cảnh của hệ thống: hàng ~44, chữ 17, không cột
  phím tắt, ẩn lệnh không dùng được, ≤ 12 hàng + menu con. Board vẽ menu mờ đục kiểu Mac; `design-parity` so theo nhãn.

## 7. Bàn phím

- Có bàn phím: thanh menu iPadOS 26 (vuốt xuống từ đỉnh, hoặc giữ ⌘ để xem bảng phím tắt) có các menu **ShotDex ·
  File · Edit · View · Image · Go · Window · Help**, nội dung đúng board `IP_MenuBar`.
- Phím tắt lấy bảng chuẩn của MAC_STYLE v2 §Shortcuts: ⌘F Search · ⌘1/⌘2 Grid/List · ⇧⌘L Filter and Sort… ·
  ⌃⌘S sidebar · ⌥⌘I inspector · ⌘E Edit · ⌥⌘C Compare · ⌘I Get Info · ⌘R/⌥⌘R xoay · ⌘⌫ Delete.
- Phím trần giữ như hôm nay: 0–5 sao, P/X/U cờ, "." Favorite, Esc đóng, ←/→ lật ảnh, Z phóng (Cull). Mới: Space =
  Quick Look ảnh đang chọn trong lưới — đường tắt của chạm mở Viewer, không phải chức năng mới.
- **I trần** bật/tắt inspector ở mọi màn có inspector (giữ luật phím I của FS-02.03b §2); **⌥⌘I** làm cùng việc
  (bí danh theo Mac); **⌘I** mở Get Info (form sheet 700×640). Ba phím, hai việc, không phím nào đổi nghĩa.
- Bảng phím Editor dùng chung với Mac (FS-18) khi có bàn phím.
- Không legend phím trên màn nào ngoài bảng phím tắt của hệ thống.

## 8. Con trỏ và Pencil

- Hover chỉ thêm vùng sáng; không lệnh nào cần hover. Nút icon có tooltip tên lệnh khi rê con trỏ.
- Kéo bằng con trỏ trên lưới = chọn dải (như kéo hai ngón). Pencil = ngón tay, trừ trong Editor và Video Studio.

