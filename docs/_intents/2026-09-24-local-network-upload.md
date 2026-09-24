# Intent: Đẩy ảnh gốc lên file server riêng (SMB/SFTP), rồi dọn máy

| Trường | Giá trị |
|---|---|
| Tác giả | hat.tuan@karabiner.tech |
| Ngày | 2026-09-24 |
| Trạng thái | accepted — theo lệnh người dùng 2026-09-24 "chạy spec … plan rồi code auto luôn" |
| Tiến độ | **đang làm** (2026-09-24) — task 1/10, 2/16 AC xanh (AC-1, AC-2) |
| Nguồn | phản hồi người dùng |
| Spec sinh ra từ đây | [FS-15 — Upload lên file server](../02-functional-spec/FS-15-server-upload/README.md) |

## Problem — vấn đề

Người chụp đổ RAW vào iPhone/iPad (chụp ProRAW, hoặc nhập từ thẻ nhớ qua Photos) và máy đầy rất nhanh:
một file RAW 25–80 MB, một buổi chụp vài trăm file là vài chục GB. Bản lưu lâu dài của họ nằm trên
**một máy trong mạng nhà** — NAS, máy Mac/PC chia sẻ thư mục qua SMB, SFTP hoặc FTP.

Hôm nay ShotDex **không có đường nào đưa ảnh tới đó**. Người dùng phải:

1. rời ShotDex, mở Files (chỉ nói chuyện được với SMB) hoặc một app FTP/SFTP bên thứ ba;
2. chọn lại đúng những tấm RAW đã chọn trong ShotDex — mà ở ngoài kia không còn bộ lọc body/lens/ngày/RAW
   của ShotDex;
3. chờ tải xong, tự đối chiếu xem tấm nào lên đủ;
4. quay về Photos xoá tay từng lô — và đoán xem xoá tấm nào thì an toàn.

Bước 4 là chỗ rủi ro thật: xoá nhầm một tấm chưa lên server là mất ảnh. Không có gì nối "đã lên server"
với "được phép xoá khỏi máy".

Bằng chứng trong code:

- Không có client mạng nào: `grep` `NWConnection`, `URLSession` upload, SMB/SFTP/FTP trong `ShotDex/` ra rỗng.
- Xoá đã có sẵn và đi qua PhotoKit: `PhotoLibraryService.deleteAssets`
  ([PhotoLibraryService.swift:961](../../ShotDex/Data/Sources/PhotoLibraryService.swift:961)), gọi từ
  `AssetActionsCoordinator.delete` ([AssetActionsCoordinator.swift:230](../../ShotDex/App/AssetActionsCoordinator.swift:230)) —
  ảnh sang **Recently Deleted**, PhotoKit tự hiện hộp xác nhận.
- Đọc bản gốc RAW đã có đường: `PHAssetResourceManager.writeData`
  ([PhotoDragItem.swift:117](../../ShotDex/Features/Shared/PhotoDragItem.swift:117)); nhận diện RAW qua
  `UTType.rawImage` ([PhotoEditingService.swift:18](../../ShotDex/Data/Sources/PhotoEditingService.swift:18)).

## Proposed outcome — kết quả mong muốn

- **Settings có danh sách file server** (một hoặc nhiều — ví dụ NAS nhà + máy studio): mỗi server có giao
  thức (SMB/SFTP), địa chỉ, tài khoản, thư mục đích. Khai một lần, có nút thử kết nối, báo rõ khi sai mật
  khẩu / không thấy máy / không có quyền ghi.
- Người dùng chọn ảnh ở Library hoặc trong album, bấm **⋯ → Upload**. Hộp xác nhận hỏi **mỗi lần**: đẩy
  lên server nào (mặc định là server dùng lần trước) và đẩy file nào (chỉ RAW / mọi bản gốc RAW + JPEG /
  gốc + bản đã sửa). Luôn là **file gốc** — không nén, không mất EXIF.
- Trên server, ảnh xếp theo **ngày chụp**: `<thư mục đích>/2026/2026-09-24/IMG_1234.DNG`.
- **Trùng tên trên server thì hỏi**, hiện **hai ảnh cạnh nhau** (tấm trên máy / tấm trên server) với Ghi đè /
  Giữ cả hai / Bỏ qua, và công tắc "Áp cho các tấm trùng còn lại" để lô 30 tấm trùng không thành 30 lần hỏi.
- Có tiến độ thật (bao nhiêu tấm, bao nhiêu GB, còn bao lâu), huỷ được, và **dừng giữa chừng không để lại
  file hỏng nửa vời trên server**.
- "Nguyên vẹn" nghĩa là **nội dung khớp** (checksum), không chỉ dung lượng khớp.
- Xong lô, app **hỏi ngay**: "Đã lên server N tấm (X GB). Xoá khỏi iPhone để giải phóng dung lượng?" —
  chỉ đề nghị xoá những tấm **đã khớp checksum trên server**; tấm lỗi không bao giờ nằm trong danh sách
  xoá. Người dùng biết trước là ảnh sang Recently Deleted và dung lượng về khi nào.
- Bấm "Không" thì vẫn xoá sau được: album **"Uploaded to Server"** gom mọi tấm đã lên **ít nhất một** server,
  grid có dấu nhỏ trên tấm đó, và chi tiết ảnh ghi đã lên server nào, lúc nào.
- **Ngoài phạm vi** (người dùng bỏ, 2026-09-24): đẩy thẳng từ thẻ nhớ / ổ cứng cắm ngoài. Chỉ đẩy từ thư
  viện Photos.

## Affected users and systems — phạm vi ảnh hưởng

- **Người dùng**: thợ ảnh chụp RAW, có NAS hoặc máy tính chia sẻ thư mục trong LAN. Người không có server
  thì không thấy gì thay đổi ngoài một mục Settings.
- **Màn hình**: Settings (danh sách server + form server — `FS-08`), menu ⋯ của chế độ chọn
  (`SelectionOverlay`, dùng chung 4 màn — Library và album), hộp xác nhận upload, hộp so sánh trùng tên,
  màn/khay tiến độ, hộp hỏi xoá, album "Uploaded to Server", dấu trên grid, dòng lịch sử upload trong
  chi tiết ảnh.
- **Thiết bị**: iPhone, iPad, Duo (trong + ngoài).
- **Tầng code**: Data/Sources (client giao thức, đọc resource gốc), Domain (hàng
  đợi, đối chiếu đã-lên-server, luật được-phép-xoá), Features (Settings, tiến độ, hỏi xoá), App
  (`AppDependencies`). Không đụng ShotDexKit, không đụng extension.
- **Dữ liệu đã lưu**: cần lưu danh sách server (mật khẩu → Keychain), server dùng lần trước, và một **bảng
  lịch sử upload** (tấm nào đã lên, lên server nào, đường dẫn nào, checksum, lúc nào) — đó là dữ liệu do người dùng tạo, **không được** nằm trong
  `photo_metadata` (indexer ghi đè cả dòng). Bảng mới → migration mới.
- **Tài liệu**: `NF-03` (lời hứa quyền riêng tư), `OV-01` (danh sách "cố ý không có"), `OV-02` (dependency),
  `FS-08` (Settings), có thể `FS-10` (xem ràng buộc).

## Constraints — ràng buộc

- **Lời hứa "photos never leave your device" ([NF-03 §1](../04-non-functional-design/NF-03-privacy-and-security.md))
  đang viết tuyệt đối trừ đúng một ngoại lệ (tin nhắn hỗ trợ).** Tính năng này là ngoại lệ thứ hai và phải
  được ghi vào NF-03 cùng lúc — cả câu chữ trên Onboarding/Settings. Chỉ gửi tới địa chỉ **người dùng tự
  khai**, không bao giờ tới máy chủ của ShotDex; không có tài khoản ShotDex.
- **Chỉ một thư viện bên thứ ba: GRDB** ([OV-02](../00-overview/OV-02-platform-and-technology.md)) —
  **luật này được nới** (người dùng chọn SMB + SFTP cho v1, cả hai qua thư viện trong app, 2026-09-24): iOS
  không có client SMB hay SFTP lập trình được, nên cần thêm thư viện; OV-02 sửa cùng lúc. Thư viện nào cũng phải có **giấy phép hợp
  App Store** (nhiều thư viện SMB là LGPL/GPL — loại) và bản khai quyền riêng tư của nó. FTP không nằm trong
  v1 (`URLSession` đã bỏ FTP).
- **Không bao giờ xoá một tấm chưa được xác minh trên server.** Xoá luôn đi qua PhotoKit (hộp xác nhận hệ
  thống + Recently Deleted), không có đường xoá thẳng.
- **iCloud Photos**: xoá trên iPhone = xoá trên iCloud và mọi thiết bị khác. Câu hỏi xoá phải nói điều đó
  khi iCloud Photos đang bật.
- **Optimize iPhone Storage**: bản gốc RAW có thể chỉ nằm trên iCloud — phải tải về trước rồi mới đẩy lên
  server, không được lấy nhầm bản proxy (xem luật "local non-degraded = maybe proxy" đã gặp ở grid).
- **Giữ quyết định FS-10** ("ShotDex là app đọc thư viện, không phải app quản lý file"): không duyệt file,
  không có lối từ ổ ngoài — upload chỉ là một hành động lên ảnh **đã có trong thư viện**.
- **NF-03 thêm ngoại lệ thứ hai** (người dùng đồng ý, 2026-09-24) — sửa cùng lúc với tính năng.
- **Quyền Local Network** (`NSLocalNetworkUsageDescription`) — hộp hỏi quyền của hệ thống, phải xuất hiện
  đúng lúc (khi thử kết nối lần đầu), không phải lúc mở app.
- Không đọc cả file RAW vào RAM (đẩy theo luồng) — bài học HEIC trong
  [panorama spike](2026-09-23-panorama-stitch-spike.md).
- **Checksum tốn gần gấp đôi thời gian**: xác minh nội dung nghĩa là đọc lại file từ server sau khi ghi
  (trừ khi giao thức cho server tự tính hash — spike trả lời). Tiến độ và ước lượng thời gian phải tính cả
  bước này.
- **Preview ảnh trùng trên server** nghĩa là tải file đó về và giải mã (RAW 25–80 MB qua mạng). Chỉ tải khi
  thật sự trùng, giải mã ra thumbnail theo luồng, không giữ cả file trong RAM.
- **Server ngoài mạng nhà cũng được** (không chặn địa chỉ). Vì thế SFTP **bắt buộc xác minh host key** lần đầu
  — hiện dấu vân tay của server để người dùng xác nhận — và báo động nếu dấu vân tay đổi.
- **Upload chạy khi app ở trước.** Trong lúc đẩy, tắt tự khoá màn hình; phải bật lại ở **mọi** lối ra — xong,
  huỷ, lỗi, rời màn, app ra nền. Ra nền giữa chừng thì lô dừng sạch (không để file nửa vời), quay lại tiếp
  được.
- Nhánh iOS 26 và pre-26 của thanh chọn / Settings đều phải có hành động này.

## Open questions — câu hỏi còn treo

Đã trả lời hết (2026-09-24):

| Câu | Trả lời |
|---|---|
| Giao thức v1 | **SMB và SFTP**, cả hai qua thư viện trong app, một form host/user/pass chung |
| Ổ ngoài / thẻ nhớ | **bỏ** |
| NF-03 | **thêm ngoại lệ thứ hai** — chỉ tới server người dùng tự khai |
| Chạy nền | **không** — giữ ShotDex mở, tắt tự khoá màn hình khi đang đẩy |
| Lối vào | chọn ảnh ở Library / album → **⋯ → Upload** |
| Loại file | **hỏi mỗi lần** đẩy: chỉ RAW / mọi bản gốc / gốc + bản đã sửa |
| Số server | **nhiều**; lúc đẩy mặc định là server dùng lần trước, đổi được trên hộp xác nhận |
| Thư mục trên server | **theo ngày chụp** `YYYY/YYYY-MM-DD/<tên gốc>` |
| Trùng tên | **hỏi**, hiện 2 ảnh cạnh nhau; Ghi đè / Giữ cả hai / Bỏ qua + "Áp cho các tấm trùng còn lại" |
| Kiểm đã lên đủ | **checksum** (so nội dung) |
| Hỏi xoá | **ngay khi xong lô** + album "Uploaded to Server" + dấu trên grid để xoá sau |
| Đã lên đâu | lên **ít nhất một** server là tính; chi tiết ảnh ghi server nào, lúc nào |
| Server ngoài mạng nhà | **được**; SFTP xác minh host key lần đầu |
| Thử trên máy thật | **dùng Mac đang code**: bật File Sharing (SMB) + Remote Login (SFTP) |

Không còn câu treo từ phía người dùng. Việc còn lại là của spike ở giai đoạn Design: chọn thư viện SMB và SFTP
(giấy phép hợp App Store, Swift Concurrency), đo tốc độ đẩy + checksum trên LAN thật bằng iPhone và Mac này.

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
