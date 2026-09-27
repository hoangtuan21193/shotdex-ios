# FS-17.01 — Duyệt ảnh trên server

`FS-17.01` · `Features/ServerImport/ServerBrowserScreen.swift` · `ServerPhotoGrid` · `Domain/ServerImport/`
· cập nhật 2026-09-27

**Một câu:** folder trên server hiện như Library — folder con ở trên, lưới ảnh bên dưới, thumbnail từ preview
nhúng, chọn nhiều như Library.

## 1. Lối vào

- Collections → Utilities → thẻ **On Server** (luôn hiện, FS-17 §6). Mở màn **On Server** — chưa có connection thì
  màn trống "Add a connection to browse and download photos from your NAS or computer." + **Add Connection**:

| Section | Nội dung |
|---|---|
| Connections | mỗi connection một hàng: tên, dưới là đường dẫn folder (`FileServerRow`, FS-15.01 §2) · chạm → duyệt, mở ở **Folder của connection**; lên cha bằng menu tiêu đề (§2a) · **nhấn giữ** → Edit Connection / Delete Connection; **vuốt** → Edit, Delete (đổi 2026-09-27: trước chỉ sửa được trong Settings) |
| (không tiêu đề) | **Uploaded from This Device** · số ảnh → màn Uploaded to Server hiện có (FS-15.02 §8); ẩn khi 0 |

- Toolbar màn On Server: **+** → Add Connection (FS-15.04).

## 2. Màn duyệt — kiểu app Files

Đổi 2026-09-27 (người dùng: "giao diện menu như app File trên iOS, có back và forward"). **Một màn** cho cả lượt duyệt
một connection: mở folder là đổi nội dung tại chỗ, không đẩy một màn mới mỗi folder. Cùng màn này dùng để **chọn
folder** ở sheet upload và form connection (§5).

### 2a. Điều hướng

| Chỗ | Nội dung |
|---|---|
| Mở ra ở | **Folder của connection** (ô Folder trong form). Folder rỗng = gốc |
| Toolbar trái | **‹ Back** (`chevron.backward`) và **› Forward** (`chevron.forward`), cạnh nhau, vùng chạm 44pt. Nút Back của hệ thống ẩn |
| Back | về folder **trước đó trong lịch sử**. Đang ở đầu lịch sử → rời màn (về On Server / về bước trước) |
| Forward | đi lại folder vừa Back khỏi; mờ khi không có. Mở một folder mới sau khi Back → xoá nhánh Forward (như trình duyệt) |
| Tiêu đề | tên folder đang mở; chạm → menu các **folder cha** tới gốc (như Files), chọn một cái là đi tới đó (vào lịch sử như mở folder) |
| Gốc | SMB: tên connection, liệt kê **các folder máy tính chia sẻ** (không có chữ "share" trên màn); SFTP: "Home"; WebDAV: gốc của Path |
| Vuốt mép trái | không dùng trong màn này (như Files trên iPad) — hệ thống tắt nó khi nút Back tự vẽ; ‹ là lối ra |

- Lịch sử sống theo lượt duyệt: rời màn rồi vào lại thì bắt đầu mới. Mỗi folder đã liệt kê được giữ trong lượt,
  Back/Forward không liệt kê lại (kéo xuống để làm mới).

### 2b. Nội dung

- **Folder và ảnh luôn cùng một kiểu** (người dùng 2026-09-27: không được ảnh là lưới mà folder là list). Folder
  đứng trước, rồi ảnh.
- **Icons** (mặc định): **một lưới** chung, cùng hình học lưới Library (số cột theo độ rộng và mật độ đã lưu, khoảng
  cách, pinch đổi cột) — DESIGN.md §lưới, không token mới. Ô folder vuông cùng cỡ ô ảnh: nền placeholder của lưới,
  glyph `folder.fill` lớn màu tint ở giữa, tên folder `.caption` dưới glyph (1 dòng, cắt giữa) — cùng bố cục ô ảnh
  không có preview. Ô file khác (Show All Files) cùng bố cục với glyph `doc`.
- **List**: mọi mục là hàng 60pt — ô vuông 44pt bên trái (thumbnail ảnh, hoặc glyph `folder.fill` / `doc` trên nền
  placeholder; bo `r-sm`), tên, dòng phụ (ảnh: `ngày sửa · dung lượng`, cặp RAW+JPEG tổng dung lượng + nhãn
  `RAW+JPG`; folder: ngày sửa nếu server trả), cuối hàng: dấu In Library (ảnh) hoặc chevron (folder).
- Chỉ **file ảnh**: đuôi thuộc `UTType.image` và ImageIO đọc được (lấy từ `CGImageSourceCopyTypeIdentifiers`, không
  liệt kê tay). File khác, video: ẩn, trừ khi bật **Show All Files** (§2c). File và folder bắt đầu bằng `.`: luôn ẩn.
  Dòng cuối, bỏ phần bằng 0: "3 folders · 12 photos · 2 other files hidden" ("2 other files" khi Show All Files bật;
  folder chỉ có folder con thì không có "0 photos").
- **Ghép cặp**: file RAW và file JPEG/JPG/HEIC/HEIF cùng tên gốc (không phân biệt hoa thường) trong cùng folder →
  **một mục**, nhãn `RAW+JPG` / `RAW+HEIC`; thumbnail lấy từ file không-RAW.
- Nhãn định dạng trên ô: cùng kiểu nhãn Library (`RAW`, `JPG`, `HEIC`, `PNG`, `TIFF`, `DNG`…).
- Dấu **In Library** (glyph `checkmark.circle.fill` nhỏ góc dưới-trái, VoiceOver "In Library") khi ảnh đã có (FS-17
  §4).

### 2c. Menu ⋯ (toolbar phải)

Thứ tự theo menu ⋯ của Files:

| Nhóm | Mục |
|---|---|
| 1 | **Select** · **New Folder** |
| 2 | **Icons** / **List** (chọn một, có icon `square.grid.2x2` / `list.bullet`) |
| 3 | **Sort By ▸** Name · Date Taken · Date Modified · Size — mục đang chọn có chevron chiều; chọn lại mục đang chọn là **đảo chiều** (như Files) |
| 4 | **View Options ▸** Show All Files (công tắc, mặc định tắt) |

- Icons/List, Sort By + chiều, Show All Files **nhớ theo connection**.
- **New Folder**: hỏi tên, tạo trong folder đang mở, rồi **mở luôn** folder đó (vào lịch sử). Tên: không rỗng, không
  chứa `/`, không bắt đầu bằng `.`. Trùng folder đã có → mở folder đó, không báo lỗi. Ở gốc SMB: mờ (không tạo được folder
  chia sẻ từ đây).
- **Show All Files** bật: file không phải ảnh hiện dạng icon tài liệu (`doc`) + tên, **mờ**, không mở, không chọn được;
  vẫn Rename/Delete được (§4b).
- Sort:

  | Lựa chọn | Nguồn | Khi chọn |
  |---|---|---|
  | **Name** (mặc định) | tên file, so kiểu Finder (`IMG_2` trước `IMG_10`) | tức thì |
  | **Date Taken** | EXIF `DateTimeOriginal` đọc từ đoạn đầu file (cùng lượt đọc với thumbnail, §3) | đọc EXIF **cả folder** (không chỉ ô đang hiện), thanh "Reading dates… 120 of 500" trên lưới, **sắp lại một lần** khi đọc xong — không nhảy ô từng cái; file không có EXIF dùng ngày sửa |
  | **Date Modified** | ngày sửa file server trả khi liệt kê | tức thì |
  | **Size** | dung lượng (cặp: tổng) | tức thì |

  Chiều mặc định: tăng dần với Name, giảm dần (mới/lớn trước) với ba cái còn lại — như Files. Ngày chụp đã đọc được
  cache cùng thumbnail (khoá FS-17 §4), mở lại folder không đọc lại. Ảnh ghép cặp lấy ngày của file không-RAW, thiếu thì
  của RAW. Folder luôn ở trên, sắp theo tên.

| Trạng thái | Hiển thị |
|---|---|
| đang liệt kê | spinner giữa màn |
| folder rỗng / không có ảnh | "No photos in this folder." (+ folder con nếu có) |
| lỗi nối | câu lỗi FS-15.01 §3 + **Try Again**; ‹ vẫn dùng được |
| đang tải thumbnail | ô xám cùng màu placeholder của Library + nhãn định dạng hiện ngay |
| không lấy được thumbnail | ô có icon định dạng lớn + tên file |

## 3. Thumbnail

Thứ tự thử, dừng ở bước đầu tiên ra ảnh ≥ 320 px cạnh dài (ảnh nhỏ hơn giữ làm tạm, tiếp tục thử). Cặp RAW+JPEG
thử **file RAW trước** — đoạn đầu RAW rẻ hơn tải trọn JPEG.

1. Đọc **256 KB đầu** file (range read).
2. ImageIO trên đoạn đó (JPEG/HEIC có EXIF thumbnail, NEF, DNG iPhone) — **trừ PNG/GIF/BMP/WebP chưa đọc trọn**: ImageIO
   trả về phần ảnh đã giải mã (dải trên, còn lại trong suốt) như thể thumbnail; đo được: ô trống với PNG 1 MB; rồi tách **JPEG nhúng có đủ byte** — tìm điểm
   kết thúc bằng cách đi qua marker, vì ImageIO gọi một JPEG bị cắt là "complete" khi mới đọc header; chọn JPEG nhỏ
   nhất mà ≥ 320 px.
3. RAF: đọc JPEG preview theo con trỏ ở byte 84–91 của header nếu ≤ 8 MB.
4. RAW khác: đọc tiếp tới **1 MB**.
5. File **không phải RAW** và ≤ 25 MB → tải trọn, ImageIO thumbnail.
6. Không được → icon định dạng.

Đo 2026-09-26 (một file mỗi hãng, raw.pixls.us + CR3 Canon R6 II): NEF 640 px, PEF/DNG Pentax 720 px, DNG iPhone 400
px trong 256 KB; CR3 1620 px, ARW 1616 px, ORF 3200 px, RW2 trong 1 MB; RAF 4416 px qua con trỏ (5.7 MB). Mười file
đều ra thumbnail ≥ 320 px.

- **Ngày chụp** (Date Taken) đọc từ 64 KB đầu: EXIF qua ImageIO; không được (CR3, RAF, PEF, ARW, RW2) thì chuỗi ngày
  EXIF đầu tiên trong đoạn đó — máy ảnh ghi DateTime và DateTimeOriginal bằng nhau; đúng cả 10 file mẫu.
- Kết quả thu về 400 px (cạnh dài), lưu cache đĩa (FS-17 §4). Mở lại folder: thumbnail từ cache, không đọc mạng.
- Chỉ làm cho ô **đang hiện**; cuộn qua thì huỷ. **Một lệnh tới server một lúc** mỗi connection — phiên SMB của
  SMBClient không an toàn khi hai lệnh chạy song song, và mạng mới là giới hạn (đổi từ "tối đa 4 luồng" lúc làm).
- Một connection dùng chung cho liệt kê + thumbnail của cả lượt duyệt; rời màn On Server thì đóng.

## 4. Chọn nhiều, sửa trên server

### 4a. Chọn nhiều

- ⋯ → **Select** → chế độ chọn giống Library: chạm để chọn/bỏ, vuốt để chọn dải, **Select All** / **Deselect All**
  (trái toolbar, như Files; phải là **Done**), số đã chọn ở tiêu đề. Ảnh ghép cặp = một lựa chọn. Folder và file không
  phải ảnh không chọn được và hiện mờ trong lúc chọn; menu tiêu đề tắt.
- Thanh dưới: **Import to Library** (`arrow.down.circle`; có số: "Import 3 to Library") và **Delete** (`trash`, đỏ) — cả hai mờ khi 0. Ảnh "In Library" chọn được nhưng
  sheet tải về mặc định bỏ qua chúng (FS-17.02 §1).
- Không ở chế độ chọn: chạm ô → xem lớn (preview nhúng, fit màn hình), tên, dung lượng, ngày sửa, camera/ống kính
  nếu EXIF đọc được từ đoạn đầu; nút **Import to Library** cho riêng tấm đó (FS-17 §6).

### 4b. Nhấn giữ — Rename, Delete

| Mục | Menu |
|---|---|
| folder | Open · Rename · Delete |
| ảnh | Import to Library · Rename · Delete |
| file khác (Show All Files) | Rename · Delete |
| folder chia sẻ ở gốc SMB | Open (không đổi tên, không xoá được) |

- **Rename**: hộp có ô tên điền sẵn **tên không đuôi**; đuôi giữ nguyên. Cặp RAW+JPEG đổi **cả hai file** cùng tên gốc
  mới. Tên: luật như New Folder; trùng tên có sẵn → "An item named “X” already exists." và không đổi gì.
- **Delete**: luôn hỏi — "Delete “A.CR3” from <connection>?" / "Delete the folder “2024” and everything in it?" / "Delete
  N photos from <connection>?", câu phụ: "It's deleted from the server, not moved to a trash, and can't be undone." Nút
  đỏ **Delete** + Cancel. Cặp RAW+JPEG xoá cả hai. Folder xoá **đệ quy** (mọi file và folder con).
- Xoá hỏng một phần (quyền, rớt mạng): dừng ở mục hỏng, báo câu lỗi FS-15.01 §3, liệt kê lại folder — thứ đã xoá không
  hiện lại.
- **Ảnh trong Photos không bị đụng.** Nhưng lịch sử upload là bằng chứng "đã có trên server" để FS-15.02 §7 đề nghị
  xoá khỏi máy — file bị xoá trên server thì bằng chứng hết đúng: **xoá các dòng lịch sử upload** trỏ tới đường dẫn đó
  (folder: mọi đường dẫn bên dưới), của mọi connection cùng giao thức + host + cổng. Rename thì **sửa đường dẫn** trong
  lịch sử upload và lịch sử tải về, để dấu In Library và luật xoá vẫn đúng. Lệch về phía an toàn: khớp thừa chỉ làm bớt
  ảnh được đề nghị xoá.

Tên nút đổi 2026-09-27 (người dùng: "download không biết là về đâu", chốt **Import to Library**): ảnh luôn vào thư
viện; chọn thêm album nằm trong sheet (FS-17.02 §1).

## 5. Chế độ chọn folder

Cùng màn §2, mở từ sheet upload (FS-15.02 §2a) và từ form connection (FS-15.04 §3, §5):

- Ảnh và file hiện **mờ**, có thumbnail, không mở, không chọn; folder mở được. Không có Select, không Rename/Delete.
  ⋯ còn New Folder, Icons/List, Sort By, View Options.
- Thanh dưới: nút lớn **Choose “<tên folder>”** (gốc SFTP: "Choose Home"). Ở gốc SMB: mờ, kèm câu "Open one of the
  shared folders first."
- ‹ ở đầu lịch sử quay về màn gọi mà không đổi gì.
