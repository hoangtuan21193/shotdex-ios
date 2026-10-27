# FS-19.01 — Thêm thư mục và ổ ngoài

`FS-19.01` · board `MAC_AddSource` · `MAC_EmptyLibrary` · `MAC_SourceIndexing` · `IP_AddSource` · `IP_SourceIndexing`
· iPhone/Duo: chưa có board · cập nhật 2026-10-04

**Một câu:** người dùng chỉ một thư mục hoặc cả một ổ; ShotDex đọc file tại chỗ, ghép RAW+JPEG, xếp ảnh vào thư viện
theo ngày chụp ngay khi đọc, và theo dõi thư mục để file mới tự vào.

## 1. Lối thêm nguồn

| Lối | Mac | iPad | iPhone, Duo |
|---|---|---|---|
| Sidebar / nhóm Sources | nút **+** cạnh nhóm **Sources** | như Mac | nút **+** của nhóm Sources (chỗ theo board `PH_*`/`DI_*`/`DC_*`) |
| Menu | File › Add Folder or Drive… | — (không có menu bar) | — |
| Thư viện trống (D13) | ba thẻ Photos Library / Folder or Drive / Server + "or drop a folder here" | Onboarding rồi tới cùng màn trống | như iPad |
| Kéo thả | thả thư mục từ Finder lên sidebar hoặc vùng trống | kéo thư mục từ Files lên sidebar | Duo trong như iPad; iPhone không có (không chạy hai app cạnh nhau) |
| Settings › Sources | **Add Folder…** · **Connect to Server…** | **Add Folder or Drive…** · **Connect to Server…** | như iPad |

- Sheet **Add a Source** (board `MAC_AddSource` / `IP_AddSource`): ba loại, câu đầu "Photos stay where they are. Nothing
  is copied or moved, and ShotDex never edits file contents."
- Duo màn trong (board `DI_AddSource`): sheet chỉ cao 661pt, nên **Folder or Drive** và **Server** đứng cạnh nhau, và chú thích
  chân sheet đứng bên trái **Choose Folder…** trên một hàng — để thẻ "Have a memory card?" (có **Choose Card…**) không bị
  chân sheet che.
- Folder or Drive có hai ô đánh dấu, **mặc định bật**: **Include Subfolders** · **Pair RAW + JPEG as One Photo**.
- **Choose Folder…** mở bảng chọn của hệ thống (Mac: open panel; iPad, iPhone, Duo: Files, ổ USB-C ở Locations). Chọn được cả
  gốc một ổ. Thả thư mục thì bỏ qua sheet và dùng hai giá trị mặc định.
- Quyền đọc + ghi lưu thành **bookmark security-scoped** (D1). Ghi cần cho sidecar ([02](02-identity-and-sidecars.md))
  và Thùng rác ([04](04-deleting-and-duplicates.md)); thư mục chỉ đọc được vẫn thêm được (02 §5, ca chỉ đọc).
- Tên nguồn = tên thư mục (gốc ổ: tên ổ); đổi tên trong Settings › Sources. Nguồn mới xuất hiện ngay trong sidebar.
- Thư mục chọn nằm **trong** hoặc **chứa** một nguồn đã có → **từ chối**, không thêm gì: "Already part of “2026 Japan”."
  (nằm trong) · "Contains “2026 Japan”. Remove that source first to add this folder." (chứa). *Vì* cho chồng thì mọi file
  bị đọc và băm hai lần.

## 2. File nào được đọc

- Mọi định dạng ảnh và video hệ thống đọc được: RAW (CR3, ARW, RAF, NEF, DNG…), HEIC, JPEG, TIFF, PNG, MOV, MP4.
  Danh sách lấy từ bộ đọc ảnh của hệ thống, không liệt kê tay.
- Bỏ qua: file và thư mục bắt đầu bằng `.`, file `.xmp` (đọc như sidecar, không thành ảnh), và **mọi gói (package)**.
- *Vì* gói Photos Library nằm sẵn trong `~/Pictures`: đọc nó là đọc trộm kho riêng của Photos và nhân đôi nguồn Photos.
  Cùng luật cho gói preview của Lightroom và Capture One.
- Thư mục con: bật thì đọc mọi tầng; tắt thì chỉ tầng đầu. Đổi sau trong Settings › Sources → đọc lại phần chênh.

## 3. Ghép RAW + JPEG

- File RAW và JPEG/JPG/HEIC/HEIF (cả `.HIF` của Canon) **cùng tên gốc** (không phân biệt hoa thường) **trong cùng thư mục** → **một ảnh**,
  nhãn `RAW+JPG` / `RAW+HEIC` như [FS-17.01 §2b](../FS-17-import-from-server/01-browse.md).
- RAW là bản gốc (editor mở RAW); JPEG cho thumbnail và preview khi RAW chưa giải được.
- Một sidecar cho cả cặp (`<tên gốc>.xmp`, [02 §5](02-identity-and-sidecars.md)). Danh tính của cặp lấy theo file RAW.
- Tắt ghép: hai ảnh riêng. RAW giữ `<tên gốc>.xmp`; JPEG/HEIC dùng `<tên file đủ đuôi>.xmp` (ví dụ `DSC04512.JPG.xmp`).
- **Live Photo** (FS-19.07 §2): một ảnh JPEG/HEIC và một video (`.MOV`…) cùng tên gốc trong một folder, không có RAW, là
  một Live Photo — bản sao là ảnh, video là file đi kèm (`pairedPath`). Không theo công tắc ghép RAW + JPEG. Video đứng một
  mình vẫn là video. Ảnh nhỏ của ảnh không đọc từ video. Nhập từ thẻ và lưới duyệt server (FS-17) chưa ghép kiểu này.
  Lightroom không đọc file thứ hai; Bridge và Capture One đọc. Rating của ảnh này không hiện trên ảnh kia.
- Hệ quả: một JPEG đứng riêng ở nguồn khác (ví dụ trong Photos) **không** trùng danh tính với cặp — nó là ảnh khác.
- Ảnh nhập từ thẻ ([FS-20](../FS-20-card-ingest/README.md)) vào thư mục của một nguồn theo đúng các luật trên, ngay khi chép xong.

## 4. Lượt đọc đầu

1. **Liệt kê**: đếm file và tổng dung lượng, không mở file. Banner: "Adding “Client Shoots 2026” · 3,812 photos found".
2. **Đọc từng file**: EXIF (không giải mã ảnh, như [BD-03](../../01-basic-design/BD-03-metadata-indexing-flow/README.md)),
   preview nhúng làm thumbnail, **hash nhanh** ([02 §1](02-identity-and-sidecars.md)), sidecar có sẵn ([02 §4](02-identity-and-sidecars.md)).
   Hash đầy đủ chạy sau, ở nền, không giữ ảnh khỏi lưới.
3. Ảnh **vào lưới theo ngày chụp ngay khi đọc xong**, không chờ cả nguồn (board `MAC_SourceIndexing`: "64 read so far").

- Banner tiến độ trên lưới: "1,240 of 3,812 photos read · about 2 min left" + vạch % + **Pause** (iPad, iPhone, Duo
  thêm **Stop**).
  Sidebar foot giữ dòng tóm tắt khi banner bị ẩn.
- **Ước lượng thời gian**: tính từ tốc độ của **200 file gần nhất**; trước khi đủ 200 file ghi "Estimating time…". Làm tròn
  phút ("about 2 min left"), quá 60 phút ghi "about 1 h 20 min left". Không bao giờ hiện số giây.
- Pause giữ mọi file đã đọc; chạy tiếp từ điểm dừng, kể cả sau khi tắt app. Stop / Remove Source… dừng ngay khung
  hình bấm, phần đuôi dọn ở nền ([BD-03.04](../../01-basic-design/BD-03-metadata-indexing-flow/04-progress-and-background.md)).
- Nhiệt, Low Power Mode, cổng nhường cho viewer: như BD-03.03. Mac thêm **Pause Indexing on Battery Power** (bật) và
  **Prevent Sleep While Indexing**; iPad, iPhone, Duo dùng **Keep Screen Awake While Indexing** (tắt) như FS-08.02.
- Nhiều nguồn cùng chờ: đọc lần lượt theo thứ tự thêm; ổ chậm không chặn ổ nhanh — mỗi nguồn một hàng đợi.
- Số đo cần có từ spike (`/plan`): file/giây trên SSD trong, SSD USB-C, HDD, NAS gigabit. Chưa đo thì không hứa số trong UI.

## 5. Theo dõi thay đổi

| | Mac | iPad, iPhone, Duo |
|---|---|---|
| Lúc app chạy | sự kiện hệ thống file cho mọi thư mục nguồn; file mới vào lưới, file mất ra khỏi lưới | không có sự kiện cho thư mục của Files/ổ ngoài |
| Lúc mở app / về trước mặt | so kích thước + ngày sửa với lần đọc trước, chỉ đọc lại phần lệch | như Mac, mỗi lần app về trước mặt |
| Bằng tay | Re-index trên hàng nguồn (Settings) | Re-index, kéo xuống để làm mới trên lưới nguồn |

- Settings › Sources › **Index New and Changed Files**: **Automatically** (mặc định) · Manually — Manually chỉ đọc khi
  bấm Re-index. File đổi tên/di chuyển: [02 §2](02-identity-and-sidecars.md).
- File mới trong thư mục đang mở hiện trong lưới **≤ 10 giây** sau khi ghi xong (Mac). Ghi chưa xong (file đang chép,
  kích thước còn đổi) thì chờ tới khi đứng yên 2 giây rồi mới đọc.
- File biến mất: ảnh mất bản sao đó. Ảnh không còn bản sao nào thì ra khỏi lưới; dữ liệu người dùng của nó giữ
  **30 ngày** để nối lại bằng hash ([02 §2](02-identity-and-sidecars.md)).
