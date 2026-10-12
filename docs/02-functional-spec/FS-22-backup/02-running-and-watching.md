# FS-22.02 — Chạy và theo dõi

`FS-22.02` · board `PH_Backup` (1/5, dòng trạng thái) · `PH_BackupRunning` (5/5) · dùng lại `ServerUploadSession`,
`PhotoKitOriginalFetcher`, `NetworkMonitor`, `ScreenAwakeCoordinator`, `BackgroundIndexService` · cập nhật 2026-10-12

**Một câu:** job không có nút "chạy" — nó luôn theo dõi nguồn; mọi lần phát hiện file chưa có trong sổ thì chép ngay
nếu điều kiện (Wi‑Fi, sạc, đích với tới được) cho phép, và màn hình nói thật đang chờ gì.

## 1. Phát hiện file mới

| Lúc | Photos Library | Nguồn thư mục/ổ/server (FS-19) |
|---|---|---|
| App đang mở | sự kiện đổi thư viện của Photos; gom 5 s rồi so | quét lại mỗi 5 phút + khi màn Backup hiện |
| App về trước mặt, khởi động | so từ mốc thay đổi đã lưu của job | lượt quét FS-19.01 §5 rồi so |
| Nền | lượt làm mới nền ngắn (§3) so từ mốc | lượt làm mới nền quét nguồn server; thư mục Files/ổ ngoài: không quét được ở nền |
| Back Up Now | so toàn bộ nguồn với sổ | quét toàn bộ rồi so |

- "So" = danh sách mục của nguồn trừ các mục đã có trong sổ của job (`uploaded` hoặc `found`). Một truy vấn, không đọc đích.
- Mốc thay đổi của Photos hết hạn hay không đọc được → so toàn bộ, không báo lỗi. *Vì mốc chỉ để nhanh, sổ mới là thật.*
- Mục mới đang được ghi (cỡ file còn đổi) chờ đứng yên 2 s như FS-19.01 §5.
- Mục đã chép rồi bị sửa (ngày sửa/cỡ đổi): bản gốc Photos không chép lại; bản sửa (khi bật) và file FS-19 đổi nội dung
  được chép thêm một bản theo luật Keep Both, bản cũ ở đích giữ nguyên.
- Mục bị xoá ở nguồn: không làm gì ở đích; dòng sổ giữ nguyên.

## 2. Chép một file

Theo đúng FS-15.02 §4: tải bản gốc vào thư mục tạm (iCloud nếu cần, theo luồng) → dò trùng tên + cỡ ở folder đích
([01 §5](01-jobs-and-organize.md#5-tên-file-và-trùng-tên)) → ghi `<tên>.shotdex-part` → đọc lại, so SHA-256 → đổi tên
thật → ghi sổ trong cùng một transaction với dòng lịch sử upload FS-15 → xoá file tạm.

- **Không làm đầy máy** (người dùng 2026-10-12): bản gốc đầy đủ tải về thư mục tạm, đẩy lên, kiểm SHA-256, rồi **xoá
  ngay** trước khi sang file sau — trên máy không bao giờ có quá 1 file của Backup. Đầu mỗi lượt xoá sạch thư mục tạm
  (file sót của lượt bị giết). Trước khi tải: còn trống trừ cỡ file < 2 GB → `Waiting for Storage`, không tải.
- Bản tải từ iCloud qua Photos có thể được Photos giữ lại trong bộ đệm của nó; bộ đệm đó do iOS (Optimize Storage) tự
  dọn, app không xoá được — ghi ở README §4.
- Một job một file một lúc; nhiều job chạy lần lượt theo thứ tự trong danh sách. *Vì một NAS nhà, một đường Wi‑Fi.*
- Folder đích chưa có thì tạo theo từng tầng; danh sách tên + cỡ của mỗi folder đích liệt kê một lần mỗi lượt chạy.
- Sổ ghi **sau** khi đổi tên thật thành công. iOS giết app giữa chừng → lần sau file đó chép lại từ đầu, `.shotdex-part`
  cũ bị ghi đè; không tên thật nào trỏ tới file chưa kiểm.
- Lỗi một file (iCloud không tải được, file nguồn không đọc được, SHA-256 lệch 2 lần): ghi sổ `failed` + lý do, sang file
  sau. Mỗi lượt chạy thử lại file `failed` tối đa 3 lần, rồi nằm trong **N Files Not Copied** (5/5) tới khi bấm Retry.

## 3. Chạy nền

| Nhánh | App đang mở | Rời app |
|---|---|---|
| iOS 26+, bắt đầu từ thao tác người dùng (Start, Resume, Back Up Now, Retry) | chạy | xin tác vụ xử lý tiếp tục như FS-15.02b; hệ thống vẽ tiến độ `Backing up to <connection>`; chạy tới hết hàng đợi hoặc bị dừng |
| iOS 26+, phát hiện tự động (§1) | chạy | dừng ở file đang làm; chờ lượt nền §3b |
| trước iOS 26 | chạy; **Keep Screen On** trong 5/5 (mặc định tắt, board tweak `ios18`) giữ màn sáng như FS-15.02 §6 | dừng ở file đang làm; chờ lượt nền §3b |

**§3b. Lượt nền do iOS chọn giờ** (mọi nhánh):
- Làm mới nền ngắn (khoảng 30 s): phát hiện file mới (§1), đẩy những file ≤ 25 MB còn kịp, xin tiếp một lượt xử lý dài.
- Xử lý nền dài: đòi có mạng; đòi sạc khi job bật Only While Charging. Chạy hàng đợi tới khi hệ thống báo hết giờ.
- Hai mã tác vụ mới khai cạnh mã index nền trong Info.plist. iOS không hứa giờ chạy; màn hình không bao giờ hứa "ngay".

**§3c. Đích WebDAV, nguồn Photos, iOS 26.1+: phần mở rộng tải nền của Photos** (quyết định 2026-10-12, Q-B1)
- Target mới, điểm mở rộng `com.apple.photos.background-upload`. iOS tự gọi nó khi có ảnh mới, kể cả app đã đóng;
  nó tạo việc tải lên một yêu cầu HTTP PUT tới connection WebDAV, hệ thống đẩy giúp.
- Chỉ bật khi: quyền Photos **đầy đủ**, có ít nhất một job Photos → WebDAV. Hết job như vậy → tắt. SMB/SFTP và nguồn FS-19
  vẫn đi §3b.
- Phần mở rộng PUT vào `<tên>.shotdex-part`, không vào tên thật. Lượt chạy kế của app (mở, nền §3b) đọc lại, so SHA-256
  rồi đổi tên và ghi sổ — luật "không tên thật nào trỏ tới file chưa kiểm" giữ nguyên.
- Việc hỏng: lượt kế của app chép lại bằng đường thường (§2), không thử lại trong phần mở rộng quá 1 lần.
- Organize, Only on Wi‑Fi, Only While Charging áp như đường thường. Mật khẩu WebDAV đọc qua nhóm Keychain chung
  app + phần mở rộng; phần mở rộng không mở database ghi, chỉ đọc bảng job (trần bộ nhớ extension, EX-01).
- Trạng thái 1/5 khi phần mở rộng đang đẩy: `3 New · Uploading in Background`.

**§3d. Chép bù không do người dùng bấm** (Q-B2, đã chấp nhận): lượt so lúc mở app không xin được tác vụ xử lý tiếp tục.
Khi hàng đợi còn > 20 file, 5/5 ghi "Leave ShotDex open to finish faster."; **Back Up Now** vẫn xin được.

## 4. Dừng và chạy tiếp

- **Pause** (1/5, 5/5): dừng ở file đang làm, xoá `.shotdex-part` nếu còn kết nối; job ngừng theo dõi tới **Resume**.
- iOS dừng (hết giờ nền, hệ thống bấm dừng): như Pause nhưng job vẫn theo dõi; lượt sau tự chạy tiếp. Dòng trạng thái
  `Paused` + "iOS stopped ShotDex at 812 of 2,940. Resumes from there." tới lượt kế.
- 5/5 chỉ có **Pause** (bỏ Stop — hai nút cùng một việc). Không có "huỷ job" ngoài Delete Job.
- 5/5 có dòng `Watching · new photos back up as they appear` dưới nút Pause: job vẫn theo dõi sau lượt này.
- Mất Wi‑Fi khi Only on Wi‑Fi bật → dừng ở file đang làm, trạng thái `Waiting for Wi‑Fi`; có Wi‑Fi lại → tự chạy tiếp.
- Đích không với tới (lỗi kết nối) → `Can't Reach <connection>`, thử lại ở lượt phát hiện kế; lỗi mật khẩu → dừng hẳn,
  nút **Edit Server** mở form FS-15.01. Đích báo hết chỗ → `<connection> Is Full`, dừng hẳn, nút Retry.
- Máy còn trống trừ cỡ file sắp tải < 2 GB → `Waiting for Storage`, không tải thêm (§2).

## 5. Trạng thái hiển thị

| Trạng thái (1/5 dòng 1) | Dòng 2 | Nút | 5/5 |
|---|---|---|---|
| `Watching · Up to Date` | `4,118 items · checked 2 min ago` | — | vòng 100%, "Up to date. New photos back up as they appear." |
| `Backing Up · 34%` (lượt đầu, sổ rỗng lúc bắt đầu) | `1,204 of 3,580 · 18.4 of 52.1 GB · about 40 min left` | Pause | như board 5/5 |
| `3 New · Uploading` (lượt sau) | `1 of 3 · 48 MB of 1.4 GB` | Pause | như board, tiêu đề vòng `3 new` |
| `Waiting for Wi‑Fi` | `12 new · Only on Wi‑Fi is on` | — | câu + đếm |
| `Waiting to Charge` | `12 new · Only While Charging is on` | — | câu + đếm |
| `Can't Reach NAS Home` | `12 new · will try again` | Retry | lỗi + Retry |
| `Source Offline` | `T7 RAW Archive isn't connected` | — | câu |
| `Paused` | lý do (người dùng / iOS, có số) | Resume | Resume thay Pause |
| `NAS Home Is Full` · `Waiting for Storage` | số GB cần | Retry | câu |

- Quyền Photos `.limited`: job chỉ thấy và chép các mục được cho phép; dòng 2 thêm "Limited Access". Quyền bị từ chối →
  trạng thái `No Photos Access` + nút **Open Settings**.
- Mỗi thay đổi trạng thái hiện trên 1/5 trong ≤ 1 s khi màn đang mở.
