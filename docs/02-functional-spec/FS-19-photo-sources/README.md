# FS-19 — Nguồn ảnh: thư mục, ổ ngoài và server

`FS-19` · tier A (thêm nguồn, Settings › Sources) + B (lưới, sidebar) · mã: chưa có (đề xuất `ShotDex/Features/Sources/`)
· test: chưa có · cập nhật 2026-10-04

**Một câu:** trên mọi thiết bị, một thư viện gộp ba loại nguồn — Photos, thư mục/ổ ngoài, server — đọc tại chỗ,
nhận diện ảnh bằng hash nội dung, ghi rating/keyword ra sidecar `.xmp`, và **không bao giờ sửa nội dung file ảnh**.

Nguồn: [intent Mac](../../_intents/2026-10-04-macos-app.md) · [intent iPad](../../_intents/2026-10-04-ipad-mac-style.md)
· quyết định D1, D3–D7 ở [DECISIONS](../../../.planboard/macos-app/DECISIONS.md) · đáp án spec 2026-10-04 ở
[SPEC-DECISIONS](../../../.planboard/macos-app/SPEC-DECISIONS.md).

## Các phần

| # | Phần | Trả lời |
|---|---|---|
| 01 | [Thêm thư mục và ổ](01-folders-and-drives.md) | thêm nguồn, thư mục con, ghép RAW+JPEG, lượt đọc đầu, ước lượng thời gian, theo dõi thay đổi |
| 01b | [Offline, quyền, cloud, cache](01b-offline-access-and-cache.md) | ổ rút ra/cắm lại, bookmark hết hạn, file chỉ có trên cloud, cache preview, hết đĩa |
| 02 | [Danh tính và sidecar](02-identity-and-sidecars.md) | hash nhanh rồi đầy đủ, ảnh Photos, đổi tên/di chuyển, dữ liệu mồ côi, bản sao, đọc + ghi `.xmp`, xung đột, recipe |
| 03 | [Server là nguồn](03-servers-as-sources.md) | index như thư mục, thumbnail, tải bản gốc khi mở, upload, Save to Photos thay Import to Library |
| 04 | [Xoá, ẩn, ảnh trùng, thống kê](04-deleting-and-duplicates.md) | D6 xoá theo nơi chứa, ảnh nhiều bản sao, nơi không Thùng rác, Hide in Photos · Hide in ShotDex Only, mục Hidden, D7 Duplicates, đếm một lần |
| 05 | [Dữ liệu](05-data.md) | id ảnh, bảng bản sao/hash/recipe/bí danh, luật gộp và tách, dọn 30 ngày, test phải có |
| 06 | [Tiêu chí nghiệm thu](06-acceptance-criteria.md) | AC-1…AC-73 |

Board: Mac `MAC_AddSource` · `MAC_SourceIndexing` · `MAC_SettingsSources` · `MAC_SettingsServers` · `MAC_ServerBrowser`
· `MAC_Duplicates` · `MAC_Cull` · `MAC_EmptyLibrary` · `MAC_GetInfo` (`docs/design/mac/project/`). iPad `IP_AddSource` ·
`IP_SourceIndexing` · `IP_Settings` · `IP_ServerList` · `IP_ServerForm` · `IP_ServerBrowser` (`docs/design/ipad/project/`).
iPhone `PH_Sources` · `PH_AddSource` · `PH_SettingsSources` · `PH_ServerList` · `PH_ServerForm` · `PH_ServerBrowser` ·
`PH_Hidden` · `PH_DeleteCopies` · `PH_DeletePermanent` (`docs/design/iphone/project/`); Duo cùng bộ tên `DI_*` (trong) và
`DC_*` (ngoài) (`docs/design/duo/project/`); iPad thêm `IP_Hidden` · `IP_DeleteCopies` · `IP_DeletePermanent`; Mac
`MAC_Hidden` · `MAC_DeleteCopies` (vẽ 2026-10-04).

## 1. Người dùng cần gì

- Ảnh RAW/JPEG của người chụp nằm trong thư mục, trên SSD gắn ngoài và trên NAS — phần lớn không nằm trong Photos.
- Họ muốn lọc theo body/lens/thông số, xem thống kê, chấm sao và sửa **trên chính những file đó**, không phải nhập vào
  Photos trước, và chắc chắn file gốc không bị đụng.
- Rating và keyword phải theo file sang Lightroom, Capture One, Bridge — nên nằm trong sidecar, không chỉ trong app.

## 2. Phạm vi

**Có (mọi thiết bị):** nguồn thư mục và ổ ngoài (Mac: open panel, kéo thả; iPad, iPhone, Duo: app Files, ổ USB-C) ·
server SMB/SFTP/WebDAV là nguồn được index · thư mục con · ghép RAW+JPEG · theo dõi thay đổi · ảnh của ổ rút ra ở lại,
mang dấu offline · danh tính bằng hash nội dung · đọc + ghi `.xmp` · xoá theo nơi chứa · Duplicates trong từng nguồn ·
album của ShotDex chứa ảnh mọi nguồn ([05 §6](05-data.md)).

**Cố ý không có:**
- Sửa nội dung file ảnh (kể cả nhúng XMP vào JPEG/DNG) — vì câu cam kết "ShotDex never edits file contents".
- Chép/chuyển file khi thêm nguồn — "Photos stay where they are. Nothing is copied or moved."
- Xoá file trên NAS — D6, chỉ Hide.
- **Import to Library** từ server — server là nguồn; ai cần ảnh trong Photos dùng lệnh xuất **Save to Photos** ([03 §4](03-servers-as-sources.md)).
- Nhập từ thẻ nhớ — D8, [FS-20](../FS-20-card-ingest/README.md); ảnh nhập xong là ảnh của một nguồn thư mục ở đây.
- Đồng bộ recipe hay rating giữa các máy ngoài đường file/sidecar/Photos — intent ghi "để sau".

## 3. Thiết bị

| Thiết bị | Hành vi |
|---|---|
| Mac (macOS 15 trở lên, chỉ Apple silicon, sandbox Mac App Store — D1) | đủ mọi phần của FS-19 |
| iPad (iPadOS 17+, nhánh 26 và trước 26 giống nhau) | đủ mọi phần; khác Mac ở theo dõi thay đổi (01 §5), Thùng rác (04 §1), không đổi chỗ cache (01b §5) |
| iPhone (iOS 17+) | **như iPad** — luật "phone có mọi chức năng của iPad, chỉ khác bố cục" (2026-09-21) |
| Duo trong 951×669 và ngoài 466×678 | như iPad; bố cục theo board `DI_*` / `DC_*` khi vẽ |

- Server trên iPhone và Duo: connection là nguồn như iPad; duyệt rồi **Import to Library** của
  [FS-17](../FS-17-import-from-server/README.md) không còn ở thiết bị nào. Upload ([FS-15](../FS-15-server-upload/README.md)) giữ nguyên.
- iPhone (và Duo ngoài): nhóm **Sources** là nhóm **cuối** của tab Collections, dưới Utilities (người dùng 2026-10-12 — đặt một lần, xem thỉnh thoảng; `AlbumsScreen`, board `PH_Sources`); hành vi không đổi theo bố cục.

## 4. Tài liệu phải sửa theo (khi FS-19 được duyệt)

| Tài liệu | Đổi gì |
|---|---|
| [BD-02](../../01-basic-design/BD-02-database-design.md) | bảng nguồn, bảng bản sao, id ảnh không phải id PhotoKit ([05](05-data.md)) — `data-migration` duyệt |
| [BD-03](../../01-basic-design/BD-03-metadata-indexing-flow/README.md) | đường index file và server: liệt kê, hash, đọc sidecar |
| [FS-01.12 §3, §7](../FS-01-library/12-rating-and-flags.md) | "Ghi sao vào file" và "không đọc sao máy ảnh" chỉ còn đúng với ảnh Photos; bảng Cờ dùng chung |
| [FS-01.12b](../FS-01-library/12b-culling-pass.md) · [FS-06.06b](../FS-06-collections/06b-duplicates-marks-merge-delete.md) | Delete Rejected / Delete thành hộp xác nhận theo nơi chứa, chọn bản sao, hộp xoá hẳn — mọi thiết bị ([04](04-deleting-and-duplicates.md)) |
| [FS-15](../FS-15-server-upload/README.md) · [FS-17](../FS-17-import-from-server/README.md) | mọi thiết bị: server là nguồn, Import to Library thành Save to Photos |
| [FS-07](../FS-07-statistics/README.md) | đếm mỗi ảnh một lần, popup Source |
| [FS-08](../FS-08-settings/README.md) · [FS-09](../FS-09-onboarding-and-permissions.md) | Settings "Photo Library" → **Sources** mọi thiết bị; lần mở đầu là thư viện trống có 3 cách thêm nguồn |
| [FS-06.01](../FS-06-collections/01-tabs-tokens-and-album-management.md) | mục **Hidden** (ảnh ShotDex ẩn, không phải album Hidden của Photos); album ShotDex cạnh album Photos |
| [FS-06.06b](../FS-06-collections/06b-duplicates-marks-merge-delete.md) | Merge với ảnh file chỉ thừa hưởng sao, cờ, keyword |
| [FS-03.14b](../FS-03-photo-editor/14b-lightroom-mapping.md) | lệnh **Import Lightroom Edits** cho ảnh file có sidecar |
| [FS-20](../FS-20-card-ingest/README.md) | SHA-256 cả file là bước kiểm bản chép; hash nội dung (phần ảnh) do nguồn tính ([02 §1](02-identity-and-sidecars.md)) |
| [NF-02](../../04-non-functional-design/NF-02-memory-and-resources.md) · [NF-03](../../04-non-functional-design/NF-03-privacy-and-security.md) | trần cache preview trên đĩa; ghi `.xmp` lên server của người dùng là dữ liệu rời máy |

## 5. Ràng buộc

| Mặt | Ràng buộc |
|---|---|
| Dữ liệu | thứ người dùng nhập **không** vào bảng metadata chính — lượt index ghi đè cả dòng ([BD-02 §1](../../01-basic-design/BD-02-database-design.md)) |
| Hiệu năng | mốc 55.231 mục; không query theo ô; mọi pass chậm resume được, huỷ tức thì, nhường theo nhiệt ([NF-01](../../04-non-functional-design/NF-01-performance.md)) |
| Bộ nhớ, đĩa | không giải mã full-res để làm thumbnail; mọi cache có trần ([NF-02](../../04-non-functional-design/NF-02-memory-and-resources.md)) |
| Riêng tư | không gì rời máy trừ tới server người dùng khai ([NF-03 §2b](../../04-non-functional-design/NF-03-privacy-and-security.md)) |
| Quyền | chỉ đọc thứ người dùng đã chọn; mọi quyền là bookmark security-scoped (D1) |
| Truy cập | trạng thái nguồn (offline, cần quyền, đang đọc) đọc được bằng VoiceOver, không chỉ bằng màu chấm |

## 6. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Hash cả file RAW trên NAS/HDD mất hàng giờ | hash nhanh lúc index, hash đầy đủ ở nền ([02 §1](02-identity-and-sidecars.md)) |
| Lightroom không đọc sidecar của JPEG/DNG/HEIC/TIFF (nó dùng XMP nhúng) | câu Settings nói "for RAW files" ([02 §5](02-identity-and-sidecars.md)) |
| App khác nhúng XMP vào file → hash đổi | nối bằng vị trí cũ ([02 §2](02-identity-and-sidecars.md)) |
| Album Photos không chứa được ảnh file | album riêng của ShotDex ([05 §6](05-data.md)) |
| Băm ảnh Photos chỉ-iCloud là tải trọn mỗi ảnh một lần | chạy nền theo luật mạng của index, không lưu file ([02 §1b](02-identity-and-sidecars.md)) |
| Spike build macOS chưa chạy (plan Mac 3.1) | số trong `/plan` lấy từ spike |
