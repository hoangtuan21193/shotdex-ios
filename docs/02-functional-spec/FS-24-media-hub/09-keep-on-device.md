# FS-24.09 — Keep on iPhone: một nút offline cho ảnh, album, phim, clip, playlist

`FS-24.09` · mã: chưa có cho ảnh và nhạc; phim dùng hàng đợi tải FS-23.01 §6 · board `PH_Movies` (menu), `Main` (Filter),
`PH_HubSources` (Kept on iPhone), `MAC_ContextMenu`; hộp Keep ảnh iPhone `PH_KeepPhotos` · iPad `IP_KeepPhotos` · Duo `DI_KeepPhotos` / `DC_KeepPhotos` · Mac `MAC_KeepPhotos`; trang Kept iPhone `PH_Kept` · iPad `IP_Kept` · Duo `DI_Kept` / `DC_Kept` · Mac `MAC_Kept` (tweak `remove`); phim iPhone `PH_MovieDetail` · iPad `IP_MovieDetail` · Duo `DI_MovieDetail` / `DC_MovieDetail` · Mac `MAC_MovieDetail` · cập nhật 2026-10-16

**Một câu:** nguồn chỉ là nơi file nằm; muốn mang theo khi không có mạng thì chạm **Keep on iPhone** trên bất cứ thứ gì —
một ảnh, một album, một phim, một clip, một playlist — và nhìn dấu ✓ là biết thứ gì dùng được offline.

## 1. Tên theo thiết bị

`Keep on iPhone` · `Keep on iPad` · `Keep on Mac`; bộ lọc `Kept on iPhone`; ô Utilities `On This iPhone`. Mọi chỗ ghi
"iPhone" trong FS-24 đọc theo thiết bị như FS-23.01 §4.

- **Chốt 2026-10-16 (D6):** lệnh ngược là **Remove from iPhone** (`Remove from iPad`, `Remove from Mac` theo thiết bị), đối
  xứng với Keep, **cùng một tên** cho ảnh, album, phim, bài, album nhạc, playlist. Chữ FS-23 `Remove Download` / `Download to
  iPhone` / `Retry Download` / `Downloading` đổi thành `Remove from iPhone` / `Keep on iPhone` / `Retry Keep` / `Keeping`
  ([FS-23.01 §5–§6](../FS-23-offline-movies/01-library-and-import.md)). Lệnh ngược vẽ trên board `*_Kept` (tweak `remove`) của cả 4 canvas.

## 2. Keep làm gì với từng loại

| Thứ | Keep chép gì | Ở đâu |
|---|---|---|
| Phim, tập, clip | file gốc + phụ đề cạnh + poster (FS-23.01 §6) | `Movies/<id>/` như FS-23.05 |
| Bài, album nhạc, playlist | file gốc + ảnh bìa + `.lrc` cạnh | `Music/<id>` (Application Support, không sao lưu) |
| Ảnh của nguồn thư mục, ổ, server (FS-19) | file gốc + sidecar | `Kept/Photos/` (Application Support, không sao lưu) |
| Ảnh trong thư viện Photos (iCloud Photos) | người dùng chọn **mỗi lần** (D7, bên dưới): bản gốc, hoặc bản xem 2732 px HEIC | `Kept/Photos/` (Application Support, không sao lưu) |
| Album | mọi ảnh của album **theo album**: ảnh thêm vào album sau này cũng được Keep ở lần làm mới kế | |

### 2a. Ảnh của thư viện Photos — hỏi mỗi lần (Chốt 2026-10-16, D7)

PhotoKit không cho app ghim bản gốc ở lại máy, nên ShotDex chép vào kho của mình. **Không có cài đặt mặc định**: **mỗi** lần
chạm Keep on iPhone trên thứ có ảnh của thư viện Photos (một ảnh, nhiều ảnh đang chọn, một album Photos), app hỏi bằng hộp
xác nhận (`confirmationDialog`; iPad/Mac: popover từ nút đã chạm):

| Thứ tự | Hàng | Làm gì |
|---|---|---|
| tiêu đề | `Keep 412 Photos on iPhone` (`Keep 1 Photo on iPhone`; theo thiết bị) | số = ảnh Photos **chưa có bản gốc** trong kho ShotDex |
| 1 (đầu) | **Originals — full resolution (≈ 8.2 GB)** | chép tài nguyên gốc (HEIC/JPEG/RAW, kèm phần sửa của Photos nếu có) qua PhotoKit, cho tải iCloud |
| 2 | **Viewing Copies — 2732 px on the long side, HEIC (≈ 0.5 GB)** | dựng bản 2732 px cạnh dài (ảnh nhỏ hơn giữ cỡ, không phóng to), HEIC, giữ EXIF |
| 3 | **Cancel** | không giữ gì, không xếp hàng gì |

- **Cỡ ≈** tính trước khi mở hộp, ≤ 1 s cho 1.000 ảnh: Originals = tổng cỡ tài nguyên gốc PhotoKit báo; Viewing Copies = số
  ảnh × trung bình 1,2 MB (ảnh nhỏ hơn 2732 px tính theo cỡ gốc). Một chữ số thập phân, đơn vị GB/MB như Finder, mono-digit.
  Sai số với byte thật sau khi Keep ≤ 25%.
- **Thứ đã Keep nhớ bản đã chọn**: album Photos Keep ở bản nào thì ảnh thêm vào album sau này được Keep ở **cùng bản** ở lần
  làm mới kế, không hỏi lại (hỏi là cho một lần chạm, không phải cho mỗi ảnh mới).
- **Đã Keep rồi**: ảnh đang giữ bản xem mà chọn Originals → thay bằng bản gốc (bản xem xoá sau khi bản gốc ghi xong); ảnh
  đang giữ bản gốc mà chọn Viewing Copies → giữ bản gốc, không hạ cấp. Cỡ ≈ chỉ tính phần sẽ chép thêm. Mọi ảnh đều đã giữ
  bản gốc → không hỏi, menu ghi `Kept on iPhone` (không còn gì để chọn).
- **Lẫn nguồn**: thứ đang chọn có cả ảnh nguồn FS-19 (thư mục, ổ, NAS) → hộp chỉ đếm ảnh Photos, dòng tin nhắn
  `3 photos from NAS Home are always kept as originals.`; Cancel huỷ **cả** lượt (kể cả ảnh NAS).
- **Bản xem dùng được gì khi offline**: Viewer, Compare, Slideshow, Share **bản xem** (Share sheet ghi rõ `Viewing copy · 2732 px`).
  Edit, Export bản gốc, Copy Original: cần bản gốc → đi đường tải bản gốc iCloud hiện có (`OriginalDownloadModal`); không mạng
  thì thẻ đó báo như hôm nay, không có lỗi mới.
- **Không đủ chỗ** (luật §4: cần byte chưa có + 1 GB): kiểm **sau** khi chọn, trước khi xếp hàng.
  Originals không đủ mà Viewing Copies đủ → alert `Not enough space on this iPhone` · "Originals need about 8.2 GB plus 1 GB
  free; 4.0 GB is free." · **Keep Viewing Copies (0.5 GB)** · **Cancel**. Cả hai không đủ → câu §4 `Not enough space on this
  iPhone — about 1.3 GB needed.`, không bắt đầu gì. Không bao giờ tự đổi bản mà không hỏi.
- **iCloud hỏng giữa chừng**: mỗi ảnh là một mục trong hàng đợi; ảnh đã xong giữ ✓. Ảnh iCloud không phản hồi/trả lỗi:
  `exclamationmark.icloud` trên ô, hàng đợi **đi tiếp** ảnh khác, không có hộp lỗi; xong lượt thì album/lựa chọn ghi
  `Kept 380 of 412 · 32 couldn't download` + **Retry Keep** (thử lại đúng 32 ảnh đó, cùng bản đã chọn, không hỏi lại). Không
  mạng ngay từ đầu: `Waiting for iCloud` (§4), tự chạy khi có mạng. Ảnh dở không để lại file (PhotoKit không tải nối được: ảnh
  đó tải lại từ đầu).
- Một file thuộc nhiều thứ đã Keep (bài trong 2 playlist, ảnh trong 2 album) chỉ lưu **một bản**, tính dung lượng một lần.
- Keep không đổi gì ở nguồn và không vào Photos, iCloud, Files.

## 3. Trạng thái và dấu

| Trạng thái | Hiển thị |
|---|---|
| Kept | `checkmark.circle.fill` tròn tối góc trên phải poster/bìa; ô lưới ảnh: cuối hàng glyph trạng thái (A12, dưới); hàng bài: ✓ trước thời lượng |
| Keeping | mờ 50% + thanh cam; dưới tên `Waiting…` rồi `Keeping 45%`; album/playlist: `Keeping 12 of 48` |
| Paused | `Paused · 12%` + dòng lý do (`NAS Home unreachable`, `iPhone storage is full`) |
| không Keep | không dấu |

- **Chốt 2026-10-16 (A12):** icon Keep khác icon Lưu về Photos / Import to Library (`arrow.down.circle(.fill)`, DESIGN §8):
  lệnh **Keep on iPhone** = `arrow.down.to.line`; dấu **Kept** = `checkmark.circle.fill`. Đã thêm vào từ điển icon DESIGN §8.
  Icon của **Remove from iPhone** chưa nằm trong A12 — `xmark.circle` (đã dùng trên board `*_Kept`). Trên ô lưới ảnh, dấu Kept
  đứng **cuối** hàng glyph trạng thái (sau RAW không đọc được, iCloud, đã lên server), trắng 10 semibold như các glyph đó; ảnh
  giữ bản xem dùng cùng dấu, khác ở VoiceOver `Kept on iPhone, viewing copy`.

## 4. Hàng đợi, dung lượng, hỏng

- Một hàng đợi chung cho mọi loại; một file một lúc; khối 1 MB vào `.part` (luật tải FS-23.01 §6 cho mọi loại, kể cả tải
  nền Plex/WebDAV và `Keep ShotDex open to finish` cho SMB/SFTP).
- Trước khi bắt đầu một Keep: cần (byte chưa có trên máy) + 1 GB trống. Thiếu → `Not enough space on this iPhone — about
  3.2 GB needed.`, không bắt đầu gì.
- Hết chỗ giữa chừng (còn < 1 GB): hàng đợi dừng, mục đang chép `Paused · iPhone storage is full`; phần đã xong giữ.
- Nguồn không tới được: `Paused · NAS Home unreachable`; tới lại được thì chạy tiếp từ byte đã có, không cần chạm.
- Ảnh Photos chỉ có trên iCloud mà không mạng: `Waiting for iCloud` (không lỗi); iCloud không phản hồi → `exclamationmark.icloud` như DESIGN §8.
- **Stop Keeping** (menu mục đang chép): huỷ, xoá `.part`, trạng thái về không Keep. Trên album/playlist nó gỡ cả phần đã
  chép xong — một lệnh, một kết quả; mục đã được Keep riêng từ trước thì ở lại.
- Quyền ảnh `.limited`: Keep album chỉ chép ảnh app thấy được; dòng phụ `Kept 120 of 120 photos you shared`.
- ShotDex không bao giờ tự xoá thứ đã Keep khi máy đầy (NF-02).

## 5. Gỡ và đếm dung lượng

- **Remove from iPhone** (D6): alert 2 nút `Remove from iPhone?` · "It stays on NAS Home. This frees 6.1 GB." · Remove · Cancel.
  Giữ chỗ đang xem, phụ đề đã dịch, lượt nghe. File chép thẳng (Files) không có lệnh này — chỉ **Remove from Movies/Music** (xoá hẳn, alert).
- Mục Kept nằm trong album/playlist đã Keep: không có Remove riêng, menu ghi `Kept with “Road Trip”`.
- Settings › Sources & Backup › **Kept on iPhone**: `41.2 GB · 3 albums, 6 movies, 1 playlist`; trang chi tiết nhóm theo loại
  (Photos · Movies · Music), mỗi hàng tên + cỡ + Remove; chân: `48 GB free on this iPhone`. Cỡ tính bằng byte thật trên đĩa.
- Ô **On This iPhone** ở Utilities mỗi tab: chỉ loại của tab đó.
- Ảnh Photos đã Keep: hàng chi tiết ghi bản (`412 photos · originals · 8.1 GB`, `120 photos · viewing copies · 0.1 GB`);
  Remove chỉ xoá bản trong kho ShotDex, không đụng ảnh trong Photos/iCloud.
