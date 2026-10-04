# FS-19.02 — Danh tính ảnh và sidecar `.xmp`

`FS-19.02` · board `MAC_SettingsSources` · `MAC_GetInfo` · `MAC_Duplicates` · `IP_Settings` · iPhone/Duo: chưa có board
· cập nhật 2026-10-04

**Một câu:** một ảnh là **nội dung** của nó (D4) — hai file giống hệt ở hai nguồn là một ảnh, chung rating; rating, cờ,
keyword, title, caption đi vào sidecar `.xmp` cạnh mọi bản sao file (D3), file ảnh không bao giờ bị ghi.

## 1. Hash nội dung

- Mỗi ảnh có một **id** (ảnh Photos giữ id hệ thống, ảnh mới nhận id mới); mỗi file hay asset Photos mang nội dung đó
  là một **bản sao** trỏ về id ([05 §1](05-data.md)). Lưới hiện **một ô mỗi ảnh**.
- Get Info liệt kê bản sao: "2 copies · T7 RAW Archive › RAW/2026-09-27 · NAS Home › Photos/2026".
- Hash chỉ phủ **phần dữ liệu ảnh** — bỏ khối EXIF/XMP/IPTC. *Vì* app khác nhúng metadata vào JPEG/DNG không được đổi
  danh tính. Bộ băm hiểu cấu trúc từng định dạng; định dạng lạ thì băm cả file.
- Cặp RAW+JPEG lấy hash của RAW ([01 §3](01-folders-and-drives.md)). Hash ghi kèm **tên thuật toán**.

| Bước | Đọc gì | Khi | Dùng cho |
|---|---|---|---|
| **Hash nhanh** | kích thước phần ảnh + 64 KB đầu, giữa, cuối của phần đó | trong lượt đọc đầu | theo dấu đổi tên, chuyển chỗ; tìm ứng viên trùng |
| **Hash đầy đủ** | mọi byte của phần ảnh | ở nền, sau lượt đọc; file có hash nhanh trùng file khác đi trước | **gộp bản sao** thành một ảnh; nhóm Exact |

- Hai file có hash nhanh trùng nhau là **hai ảnh** tới khi cả hai có hash đầy đủ và trùng. Lệch thì ở lại hai ảnh.
- Ước lượng hash nhanh cho T7 26.107 RAW: < 1 phút SSD USB-C; 5–15 phút HDD hay NAS gigabit (giới hạn bởi số lần
  đọc rải). Hash đầy đủ ở nền: ~13 phút SSD, hàng giờ HDD/NAS — resume được, huỷ tức thì, theo luật mạng và nhiệt.

### 1b. Ảnh trong Photos

- Ảnh Photos **có** tham gia hash: đọc luồng bản gốc, băm, **bỏ byte ngay** — không ghi file nào, dung lượng đĩa không tăng.
- PhotoKit không đọc theo đoạn, nên một ảnh Photos cho cả hash nhanh và đầy đủ trong **một** lượt đọc.
- Ảnh chỉ có trên iCloud (Optimize Storage) tải trọn **một lần** để băm, theo luật mạng của index
  ([BD-03.03 §2](../../01-basic-design/BD-03-metadata-indexing-flow/03-network-thermal-and-gate.md)); không giữ bản tải.
- Ảnh Photos chưa băm là một ảnh riêng; băm xong mà trùng một file thì hai bản sao gộp về một id.

### 1c. Gộp

- Gộp chạy trong một lần, giữ id cũ hơn. Trường một giá trị (sao, cờ, favorite, title, caption, recipe): **đổi sau
  cùng thắng**. Keyword, album, bản sao ẩn: **hợp lại**. Chi tiết theo bảng ở [05 §4](05-data.md).
- Id bị gộp còn tìm được qua **bí danh** — widget hay smart album đang trỏ id đó vẫn ra ảnh.

## 2. File đổi tên, di chuyển, đổi nội dung

| Việc | Thấy bằng | Kết quả |
|---|---|---|
| Đổi tên / chuyển trong cùng nguồn (Finder, Files) | sự kiện file (Mac) · lượt so lệch (iPad, iPhone, Duo) | hash trùng → **cùng ảnh**, đổi đường dẫn bản sao; rating, recipe, cờ giữ nguyên |
| Chuyển sang nguồn khác | bản sao mất ở A, xuất hiện ở B | cùng ảnh, đổi nơi chứa |
| Sidecar đi theo | `.xmp` cùng tên gốc chuyển cùng | đọc lại sidecar ở chỗ mới |
| App khác nhúng XMP vào file | kích thước/ngày sửa lệch | hash **không đổi** (chỉ phủ phần ảnh) → cùng ảnh; đọc lại EXIF |
| App khác lưu đè điểm ảnh (cùng đường dẫn), ảnh chỉ có bản sao này | hash mới | **cùng ảnh** — nối bằng vị trí; đọc lại EXIF |
| Như trên nhưng bản sao khác vẫn giữ ảnh cũ | hash của bản này lệch các bản kia | **tách**: bản đổi thành ảnh mới, mang bản chép dữ liệu người dùng |
| Chuyển ra ngoài mọi nguồn / bị xoá ngoài ShotDex | bản sao biến mất | ảnh hết bản sao → ra khỏi lưới, thành **mồ côi** |

- Nối bằng vị trí chỉ áp khi **cùng nguồn + cùng đường dẫn** đổi byte **và** không bản sao nào khác còn nội dung cũ.
  Hai file khác vị trí có hash khác nhau thì là hai ảnh.
- **Ảnh mồ côi giữ dữ liệu người dùng 30 ngày** (rating, cờ, keyword, favorite, recipe, ẩn, album). File quay lại trong
  30 ngày (Put Back, cắm lại thẻ, thêm lại nguồn) → nối bằng hash, dữ liệu về đủ. Quá 30 ngày → xoá dòng ở mọi bảng,
  trừ lịch sử upload, tải về, nhập thẻ ([05 §5](05-data.md)).
- Đếm 30 ngày từ lúc ảnh mất bản sao cuối. Ổ chỉ **offline** thì ảnh không mồ côi — bản sao vẫn còn, chỉ không với tới.

## 3. Bản sao ở nguồn khác

- Bản sao giống hệt ở nguồn khác **không** phải ảnh trùng: một ảnh, đếm một lần (D7), rating chung (D4).
- Mở / sửa / xuất dùng bản sao online theo thứ tự: **ổ trong → Photos có bản gốc trên máy → ổ ngoài → server → iCloud**
  (Photos chỉ-iCloud, chỗ giữ chỗ cloud).
- Kiểu lưu theo bản đang mở (D16): bản file/server tự lưu; bản Photos theo Done. Recipe khoá theo id ảnh (§8) nên mọi
  bản sao thấy cùng chỉnh sửa; chỉ khi bản đang mở là bản Photos mới có lần ghi vào Photos.
- Không có hàng **Backup Source**: bản sao giống hệt vốn là một ảnh, không cần nguồn riêng để giấu nó.

## 4. Đọc `.xmp` và XMP nhúng khi index

- Tìm sidecar `<tên gốc>.xmp` (Lightroom, Capture One, Bridge) và `<tên file đủ đuôi>.xmp`; có cả hai thì lấy cái mới hơn.
- Đọc cả **XMP nhúng** và sao máy ảnh ghi vào file (Sony, Fuji) với **ảnh file**; có sidecar thì sidecar thắng. Ảnh
  Photos vẫn không đọc sao trong file ([FS-01.12 §7](../FS-01-library/12-rating-and-flags.md)).
- Trường đọc: sao 0–5 · sao −1 = **Reject** · Pick, favorite, recipe trong vùng ShotDex · keyword · title · caption ·
  creator · copyright. Không đọc nhãn màu ([FS-01.12 §3](../FS-01-library/12-rating-and-flags.md)).
- Thiết lập chỉnh ảnh của Lightroom: **không** tự đọc. Lệnh **Import Lightroom Edits** (ảnh đang chọn) quy đổi chúng thành
  recipe qua bảng [FS-03.14b](../FS-03-photo-editor/14b-lightroom-mapping.md); chỉ chạy khi người dùng bấm.

## 5. Ghi sidecar

- **Read and Write .xmp Sidecars** — Settings › Sources (Mac) / Sources › Metadata (iPad, iPhone, Duo), **mặc định bật**.
  Chân mục: "Lightroom reads these sidecars for RAW files; Capture One and Bridge read them for every format. Photos
  Library items keep their metadata in Photos."
- Ghi: sao, cờ, keyword, title, caption, favorite, recipe — sau thay đổi cuối 1 giây; ghi file tạm rồi thay. **Mọi thẻ
  khác giữ nguyên từng byte** (thiết lập Lightroom, trường Photo Mechanic). Chưa có thì tạo.
- **Reject** ghi sao −1 vào trường sao chuẩn; sao thật của ảnh ở database và vùng ShotDex, bỏ Reject thì trường chuẩn
  trở lại sao đó. **Pick**, favorite và recipe chỉ nằm trong vùng riêng của ShotDex; app khác bỏ qua.
- Ghi ra **mọi bản sao file đang online** (D4). File ảnh, kể cả JPEG, **không bao giờ** được ghi.
- Tắt: không đọc, không ghi; giá trị đã có ở lại trong ShotDex (bảng riêng, [05](05-data.md)).
- Chỗ chỉ đọc (ổ khoá ghi, share không quyền ghi, file bị khoá): thay đổi ở lại ShotDex, ảnh mang dấu chờ; dòng
  "Couldn't save .xmp for 3 photos · T7 RAW Archive is read-only" trên hàng nguồn; thử lại khi quyền đổi.

## 6. Xung đột

- ShotDex nhớ **dấu của sidecar** lúc đọc lần cuối (ngày sửa + hash). Trước mỗi lần ghi, so lại: lệch nghĩa là app khác
  vừa ghi → đọc lại trước, rồi mới ghi phần ShotDex đổi.
- Sidecar đổi bên ngoài (sự kiện file hoặc lượt so lệch) → đọc lại; lưới cập nhật không cần Re-index.
- Cùng một trường đổi ở cả hai phía: **bên đổi sau cùng thắng** — so giờ đổi trong ShotDex với ngày sửa của sidecar.
- Hai bản sao có sẵn sidecar khác nhau khi index (★2 ổ trong, ★5 T7): **sidecar mới hơn thắng**, rồi ShotDex ghi giá
  trị đó ra sidecar của bản kia.

## 7. Ghi cho bản sao đang offline

- Thay đổi khi một bản sao offline: ghi ngay ra các bản online; ảnh mang **dấu chờ** cho bản offline.
- Bản sao online lại → ghi **giá trị hiện hành** của ảnh (không phát lại từng thay đổi), so dấu sidecar như §6 trước khi ghi.
- Dấu chờ là **dữ liệu người dùng** → bảng riêng, sống qua Clear Local Metadata Index ([05 §3](05-data.md)).

## 8. Recipe nằm ở đâu

- Ảnh file và server **tự lưu** khi sửa (D16): toolbar "Edited · Saved" + Revert, không Done.
- Recipe ở **database theo id ảnh** — bản làm việc, chung mọi bản sao — **và** trong vùng ShotDex của sidecar, để đi theo
  ổ giữa các máy. Lightroom bỏ qua vùng này.
- Lúc index, recipe trong sidecar mới hơn bản database thì thắng (luật §6). Sidecar tắt → recipe chỉ ở database.
- Decode recipe vẫn khoan dung: một phần tử hỏng không kéo cả recipe (luật độ bền trong CLAUDE.md).
