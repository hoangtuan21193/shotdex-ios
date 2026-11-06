# FS-19.01b — Ổ offline, quyền truy cập, file trên cloud, cache preview

`FS-19.01b` · board `MAC_SourceIndexing` · `MAC_SettingsSources` · `IP_SourceIndexing` · `IP_Settings` · iPhone/Duo: chưa có
board · cập nhật 2026-10-04

**Một câu:** ảnh của một ổ rút ra vẫn ở trong thư viện và vẫn lọc, chấm sao được; quyền mất thì app nói cách lấy lại;
file chỉ có trên cloud không bị tải ngầm; preview có chỗ và có trần.

## 1. Trạng thái của một nguồn

| Trạng thái | Khi | Sidebar | Settings › Sources |
|---|---|---|---|
| Connected | bookmark mở được, thư mục đọc được | tên + số ảnh | "Watching for changes · indexed 2 min ago" |
| Reading | lượt đọc đang chạy | vạch nhỏ dưới tên | "1,240 of 3,812 read" |
| Offline | ổ không gắn / server không với tới | tên mờ + glyph offline | "Not connected · 26,107 photos kept" + **Locate…** |
| Needs access | bookmark không mở được, hoặc hệ thống từ chối | glyph cảnh báo | câu lý do + **Grant Access…** |

- Mỗi trạng thái có nhãn chữ cho VoiceOver ("T7 RAW Archive, offline"), không chỉ chấm màu.
- Ổ ngoài có nút **Eject** trên hàng sidebar (Mac): chờ các lệnh ghi sidecar đang bay xong rồi mới tháo ổ.
- **Hide Its Photos** đang chọn (§2) thì nguồn offline vẫn ở sidebar, mờ, với "26,107 photos hidden until connected".

## 2. Ổ rút ra và cắm lại

- **When a Drive Is Disconnected** (Settings › Sources): **Keep Photos, Marked Offline** (mặc định) · **Hide Its Photos**.
  Hide Its Photos: ảnh của ổ rời lưới, tìm kiếm, Statistics tới khi cắm lại; dữ liệu người dùng không mất. Ảnh còn bản
  sao online ở nguồn khác thì ở lại với bản đó.
- Banner trên lưới (board `MAC_SourceIndexing`): "T7 RAW Archive is offline · Its 26,107 photos stay in your library. You
  can still cull, rate, keyword and sort them; connect the drive to open originals, edit or export." · **Locate…** ·
  **Remove Source…**. Tiêu đề lưới: "55,267 photos · 1,204 videos · 26,107 offline".
- Ảnh offline: lọc, tìm, thống kê, chấm sao, cờ, keyword **được**; thay đổi metadata để lại dấu chờ cho bản offline
  ([02 §7](02-identity-and-sidecars.md)). Mở ảnh: preview đã cache. **Edit, Export, Share, kéo ra ngoài: mờ**, kèm câu
  "Connect T7 RAW Archive to edit this photo." Ảnh còn bản sao online ở nguồn khác thì mở bản đó, không mờ gì.
- Cắm lại: bookmark mở lại → Connected trong ≤ 5 giây sau khi ổ gắn; ghi sidecar của các ảnh có thay đổi chờ, theo
  **giá trị hiện hành** ([02 §7](02-identity-and-sidecars.md)); so kích thước + ngày sửa, chỉ đọc lại phần lệch.
- **Ổ rút giữa lượt đọc đầu**: không hộp lỗi. Banner đổi thành "T7 RAW Archive was disconnected · 1,240 of 3,812 read".
  1.240 ảnh đã đọc ở lại (offline); nguồn khác đọc tiếp; cắm lại thì chạy tiếp từ file 1.241, không đọc lại.
- Mac (2026-11-07): một nguồn offline → banner đầy đủ trên lưới; nhiều nguồn → một dòng "2 sources offline: A, B",
  bấm tên mở nguồn đó kèm banner của nó. Ô ảnh không còn bản nào mở được mang glyph ổ góc phải; dòng phụ "· N offline"
  đếm đúng những ảnh đó. Remove Source… nói rõ: ảnh có bản ở nguồn khác ở lại, rating/edit giữ 30 ngày, không xoá gì trên ổ/server.
- **Locate…** (Mac): bảng chọn mở ở chỗ cũ; không làm khi đang có lượt đọc khác; thư mục chọn chứa < 20% trong 50 file
  nguồn đã biết → hỏi "This Folder Doesn’t Look Like “…”" (Use This Folder / Cancel) trước khi đổi.
- **Locate…**: mở bảng chọn để chỉ chỗ mới của thư mục (ổ đổi tên, thư mục bị chuyển). Chọn xong → đọc lại kiểu so lệch;
  ảnh có hash trùng giữ nguyên danh tính và dữ liệu ([02 §1](02-identity-and-sidecars.md)).
- **Remove Source…**: hỏi "Remove “T7 RAW Archive”? Its 26,107 photos leave ShotDex. Nothing on the drive is deleted." ·
  Remove · Cancel. Ảnh còn bản sao ở nguồn khác thì ở lại với bản sao đó. Ảnh hết bản sao thành mồ côi, giữ dữ liệu
  30 ngày ([02 §2](02-identity-and-sidecars.md)) — thêm lại nguồn trong 30 ngày thì rating, cờ, recipe về đủ.

## 3. Bookmark hết hạn, quyền bị thu

- Bookmark không mở được (thư mục đổi tên khi app tắt, ổ format lại, iPad/iPhone/Duo: app cung cấp file thu quyền) →
  Needs access.
- Câu trên hàng: "Choose the folder again in Files to let ShotDex read it." (iPad, iPhone, Duo) / "ShotDex needs permission to read this
  folder." (Mac) + **Grant Access…**. Ảnh ở lại, offline, tới khi người dùng chọn lại.
- Grant Access… mở bảng chọn ở chỗ cũ nếu còn. Chọn xong → đọc so lệch; hash giữ danh tính, nên **không mất rating, recipe,
  cờ**, không sinh ảnh trùng.
- Người dùng chọn một thư mục khác hẳn (0 hash trùng trong 200 file đầu): hỏi "This folder has different photos. Add it as
  a new source?" — không âm thầm thay nguồn cũ.

## 4. File chỉ có trên cloud

iCloud Drive (Optimize Mac Storage), Dropbox, OneDrive, Google Drive qua Finder/Files: file có thể là **chỗ giữ chỗ**
chưa tải về máy.

- Lượt index **không bao giờ** làm hệ thống tải file về. Đọc thử mà thấy là chỗ giữ chỗ → bỏ qua phần đọc nội dung.
- Thứ biết được không cần tải: tên, kích thước, ngày sửa, và thumbnail nếu app cung cấp tự trả (như [FS-17.05 §3](../FS-17-import-from-server/05-cloud-folders.md)).
- Không có byte thì không có hash, không có EXIF. Chỗ giữ chỗ hiện thành **ô có glyph cloud** (tên, ngày sửa, thumbnail
  nếu có), **không** vào bộ lọc thông số và **không** đếm trong Statistics tới khi tải. Dòng đếm của lưới thêm "· 412 in the cloud" (chân lưới trên iPhone/Duo; dòng phụ thanh công cụ trên iPad/Mac).
- Mở một chỗ giữ chỗ = người dùng chủ động → tải **đúng file đó**, có tiến độ và Cancel.
- Hàng nguồn có lệnh **Download 412 Files (9.8 GB)…**, hỏi trước khi tải, nói rõ dung lượng; hết chỗ thì không bắt đầu.

## 5. Cache thumbnail và preview

| | Thumbnail | Preview đầy màn |
|---|---|---|
| Cỡ | 400px cạnh dài, từ preview nhúng trong file | 2400px, khi người dùng mở ảnh |
| Ước lượng | ~40 KB/ảnh → ~2,2 GB cho 55.231 mục | ~1 MB/ảnh ([NF-02 §2](../../04-non-functional-design/NF-02-memory-and-resources.md)) |
| Giữ | kể cả ổ offline, tới khi vượt trần (bỏ sau preview) | **Keep Full-Size Previews: For 30 Days** (theo lần mở cuối) |

- Settings › Sources › Previews: **Preview Cache** "18.4 GB on Macintosh HD · thumbnails and full-size previews" +
  **Clear Cache** · **Cache Size Limit** · **Change Location…** (Mac) · **Keep Full-Size Previews** · **Keep Previews of
  Disconnected Drives** (bật; tắt thì xoá preview đầy màn của ổ khi nó rút ra, giữ thumbnail).
- **Một cache** cho mọi nguồn — thumbnail và preview của thư mục, ổ, server (server không có cache riêng, [03 §5](03-servers-as-sources.md)).
- **Cache Size Limit**: 2 · 5 · 10 · 25 · 50 GB; mặc định **25 GB** trên Mac, **5 GB** trên iPad, iPhone, Duo. Vượt
  trần → bỏ preview đầy màn mở lâu nhất trước; hết preview mới bỏ thumbnail dùng lâu nhất. Thumbnail của 55.231 mục
  (~2,2 GB) vừa trần nhỏ nhất ngoài 2 GB.
- Chỗ mặc định: **Application Support** của app, **loại khỏi sao lưu** (Time Machine, iCloud Backup). *Vì* thư mục
  Caches bị hệ thống xoá ngầm khi thiếu chỗ — mất thumbnail của ổ offline, thứ không dựng lại được tới khi cắm.
- Change Location… ra ổ ngoài: chuyển cache sang đó; ổ đó rút ra thì quay về tạo thumbnail mới ở chỗ mặc định.
- iPad, iPhone, Duo: không có Change Location…; cache nằm trong app, cùng trần và cùng luật bỏ.

## 6. Hết chỗ trên đĩa

- Ghi cache thất bại vì hết chỗ → **dừng ghi preview**, lượt đọc metadata vẫn chạy; dòng "Not enough space for previews ·
  free up space on Macintosh HD" ở sidebar foot. Ảnh thiếu thumbnail hiện ô xám + nhãn định dạng.
- Ghi sidecar thất bại vì hết chỗ → ảnh mang dấu chờ ([02 §7](02-identity-and-sidecars.md)), không mất thay đổi.
- Tải bản gốc từ server hay từ cloud: kiểm chỗ trống **trước** khi tải; không đủ thì không bắt đầu.
- Không bao giờ xoá file của người dùng để lấy chỗ; chỉ xoá cache của chính ShotDex.
