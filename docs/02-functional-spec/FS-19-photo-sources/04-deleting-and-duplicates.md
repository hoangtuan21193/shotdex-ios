# FS-19.04 — Xoá, ẩn, ảnh trùng và thống kê

`FS-19.04` · board `MAC_Cull` · `MAC_Duplicates` · `MAC_Statistics` · mục Hidden: `PH_Hidden`, `MAC_Hidden` · hộp xoá hẳn: `PH_DeletePermanent` · hộp chọn bản sao: `PH_DeleteCopies`
board · cập nhật 2026-10-04

**Một câu:** xoá đi tới đúng thùng rác của nơi chứa — Photos vào Recently Deleted, file vào Thùng rác, NAS chỉ ẩn (D6),
nơi không có Thùng rác thì xoá hẳn sau hộp thứ hai — chỉ đụng bản sao của nguồn đang xem; Duplicates gom trong một
nguồn, Statistics đếm mỗi ảnh một lần (D7).

## 1. Xoá theo nơi chứa

| Bản sao nằm ở | Xoá thành | Lấy lại |
|---|---|---|
| Photos Library | Recently Deleted của Photos (hộp hỏi của hệ thống vẫn bật) | trong Photos, 30 ngày |
| Thư mục / ổ trên Mac | Thùng rác của macOS | Finder › Put Back |
| Thư mục trên iPad, iPhone, Duo (On My iPad/iPhone, iCloud Drive) | Recently Deleted của Files | app Files |
| Nơi không có Thùng rác (ổ USB-C trên iPad/iPhone/Duo, vài ổ exFAT/FAT, share mạng gắn bằng Finder) | **xoá hẳn** sau hộp đỏ thứ hai | không lấy lại được |
| Server (NAS) là nguồn | **không xoá** — chỉ **Hide** trong ShotDex | Unhide (§3) |

- File ảnh đi vào Thùng rác **cùng file JPEG ghép cặp và sidecar `.xmp`** của nó — Put Back trả về đủ bộ, và lượt so lệch
  nối lại danh tính bằng hash ([02 §2](02-identity-and-sidecars.md)).
- Câu cam kết đi kèm mọi hộp xoá: "ShotDex never edits file contents."
- **Ảnh nhiều bản sao** (Photos + T7 + NAS): xoá trong một nguồn chỉ đụng **bản sao ở nguồn đó**; ảnh ở lại với các bản kia.
- Xoá từ **All Photos** (hay album, smart album, Cull không lọc nguồn): hộp xác nhận liệt kê **từng bản sao** có ô đánh
  dấu — "T7 RAW Archive › RAW/2026-09-27", "Photos Library", "NAS Home (hide)". Mặc định chỉ bật **bản đang dùng để mở**
  (đầu thứ tự ở [02 §3](02-identity-and-sidecars.md)); các bản còn lại là **backup**, mặc định tắt. Nhiều ảnh: một hàng
  mỗi nguồn với số ảnh, cùng luật mặc định. Không ảnh nào có ≥ 2 bản sao → không có phần chọn, hộp như §2.
- **Nơi không có Thùng rác**: sau hộp thường, hộp đỏ thứ hai — tiêu đề "Delete 12 Photos Permanently?" (như
  [FS-01.08c §6](../FS-01-library/08c-compare-viewer-mode.md)), lời "“SD_BACKUP” has no Trash. These files can't be
  recovered.", nút **Delete Permanently** (chữ đỏ) · **Cancel**. Cancel → không file nào bị xoá.

## 2. Hộp xác nhận

Board `MAC_Cull` (Move 120 Rejected…), `MAC_Duplicates` (Move 2 Photos…). Tiêu đề đếm **ảnh**, lời đếm **theo nơi đến**:

| Phần | Chữ |
|---|---|
| Tiêu đề | "Move 120 rejected photos?" (Cull) · "Move 5 photos?" (lưới, Duplicates) |
| Lời | "84 go to the Trash, 30 to Recently Deleted. 6 on NAS Home can't be deleted from ShotDex and will be hidden." |
| Dòng phụ | "ShotDex never edits file contents." |
| Nút | **Cancel** · **Move** (bordered, chữ đỏ — nút phá huỷ không bao giờ là nút nổi bật) |

- Phần nào bằng 0 thì bỏ khỏi câu. iPad, iPhone, Duo: "the Trash" thành "Recently Deleted in Files".
- **Toàn bộ là ảnh NAS** → tiêu đề "Hide 6 photos?", lời "Files on NAS Home stay on the server; ShotDex hides them.", nút
  **Hide**. Không chữ "delete" nào.
- **Toàn bộ là ảnh Photos** → bỏ hộp của ShotDex, chỉ còn hộp của hệ thống (như iOS, [FS-01.12b §3](../FS-01-library/12b-culling-pass.md)).
- Thứ tự khi trộn (planboard mac-ipad-v2 A7, như [FS-01.08c §6](../FS-01-library/08c-compare-viewer-mode.md)): bấm Move →
  file vào Thùng rác, ẩn phần NAS, **rồi phần Photos** qua hộp của hệ thống. Cancel ở đó → **chỉ phần Photos ở lại** (vẫn
  Rejected); phần khác đã chạy. *Vì* hộp của ShotDex đã là bước xác nhận cho file và NAS; hộp hệ thống chỉ hỏi về Photos.
- Có phần xoá hẳn: hộp thứ hai hiện **trước** hộp Photos; Cancel ở đó → không gì chạy.
- Chuyển file hỏng một phần (quyền, ổ rút ra): dừng, báo "Couldn't move 3 files to the Trash" kèm lý do của lỗi đầu; phần đã
  chuyển giữ nguyên; dấu Rejected của 3 ảnh còn lại không mất.
- Xong: banner "Moved 84 files to the Trash and 30 photos to Recently Deleted. Hid 6 photos on NAS Home." Không Undo trong app.
- Tên lệnh theo đích, mọi thiết bị, cả Cull lẫn Compare: có file đi Thùng rác (kể cả khi trộn) → **Move N Rejected…** /
  **Move N Photos…**; chỉ ảnh Photos hoặc chỉ thư mục không có Thùng rác → **Delete N Rejected…** / **Delete N Photos**;
  chỉ ảnh NAS → **Hide N Rejected…** / **Hide N Photos**. `copy-consistency` duyệt bộ tên này.

## 3. Hide và mục Hidden

**Lệnh Hide theo nơi ảnh nằm** (planboard mac-ipad-v2 Q1, 2026-10-04) — cùng chữ ở ⋯ của Viewer, menu nhấn giữ /
chuột phải, ⋯ của chế độ chọn và menu **Photo** trên Mac (một nguồn lệnh, FS-21 K5):

| Ảnh có | Lệnh | Làm gì |
|---|---|---|
| chỉ bản Photos | **Hide** | như hôm nay: asset vào album Hidden của Photos (ẩn trên mọi máy qua iCloud) |
| chỉ bản file / NAS | **Hide** | ShotDex đánh dấu ẩn mọi bản sao; file không bị sửa |
| bản Photos **và** bản file / NAS | hai dòng, không có "Hide" trơn: **Hide in Photos** · **Hide in ShotDex Only** | xem dưới |

- **Hide in Photos** — bản Photos vào album Hidden của Photos (như Hide hôm nay), ShotDex đánh dấu ẩn mọi bản sao còn
  lại. Ảnh rời ShotDex **và** app Photos trên mọi máy.
- **Hide in ShotDex Only** — ShotDex đánh dấu ẩn **mọi** bản sao, kể cả bản Photos; Photos không bị đổi gì, ảnh vẫn hiện
  trong app Photos.
- "Hide" trơn chỉ có khi ảnh nằm ở **một** nơi — không có gì để chọn. Nhiều ảnh: hai dòng hiện khi ≥ 1 ảnh trong lựa chọn
  có cả hai loại bản sao; Hide in Photos áp phần Photos cho ảnh có bản Photos, ảnh chỉ file/NAS thì ShotDex ẩn.
  `copy-consistency` duyệt bộ chữ.
  Code: `AssetActionsCoordinator.hideCommands(ids:)` / `hide(_:ids:)` qua `HideService` (chia lô 500 id) — viewer ⋯,
  menu nhấn giữ (`PhotoTileContextMenu`), ⋯ chọn nhiều (`SelectionBarViews`). Hộp xác nhận ở viewer: Hide in ShotDex
  Only và Hide của ảnh chỉ-file nói "Unhide it in Collections › Hidden"; Hide in Photos / Hide của ảnh Photos giữ câu
  album Hidden của Photos. Ảnh ẩn rời viewer như khi xoá. Board iPhone `PH39_ViewerMenuSources`.
- Hide trong màn duyệt một nguồn NAS (và phần NAS của lệnh xoá Reject, §1–§2) chỉ đánh dấu **bản sao ở nguồn đó** — không
  đổi.
- Ảnh **ẩn khi và chỉ khi mọi bản sao của nó ẩn** ([05 §3](05-data.md)); ảnh còn bản sao
  không ẩn ở nguồn khác thì vẫn ở lưới, chỉ rời màn duyệt của NAS.
- Ảnh ẩn rời lưới, tìm kiếm, smart album, album, Statistics. Dấu ẩn là dữ liệu người dùng, sống qua index lại.
- Xem lại ở mục **Hidden** trong Collections (cùng chỗ với Utilities): lưới các ảnh ShotDex đã ẩn, tiêu đề "6 Hidden
  Photos", chọn → **Unhide** (bỏ ẩn mọi bản sao của ảnh). Mục chỉ hiện khi có ≥ 1 ảnh ẩn.
- Mục này **không** chứa album Hidden của Photos — app bên thứ ba không đọc được nó ([FS-06.01](../FS-06-collections/01-tabs-tokens-and-album-management.md)).
  Ảnh ẩn bằng **Hide in Photos** có trong mục nhờ các bản file/NAS ShotDex đã ẩn; Unhide trả các bản đó về lưới, còn bản
  Photos chỉ bỏ ẩn được trong app Photos.
- File bị xoá ngay trên NAS (bởi máy khác) → lượt so thấy mất → bản sao mất; ảnh hết bản sao thì mồ côi theo luật 30 ngày ([02 §2](02-identity-and-sidecars.md)).

## 4. Duplicates — chỉ trong một nguồn (D7)

- Mọi nhóm (Exact, Similar, Series) **chỉ gồm ảnh của cùng một nguồn**; kết quả quét trùng lưu theo từng nguồn. Một ảnh có bản sao ở A và B có thể nằm trong nhóm
  của A **và** nhóm của B; đánh dấu nó trong nhóm của B chỉ xoá **bản sao ở B**.
- Bản sao giống hệt ở nguồn khác **không bao giờ** được đề nghị xoá. Câu trên board: "Groups stay inside one source. An
  identical copy in another source is the same photo (matched by content hash): it is counted once and never offered for
  deletion."
- Hai file giống hệt **trong cùng nguồn** là một ảnh có hai bản sao ở đó → hiện như nhóm Exact "2 identical copies of
  DSC04512.ARW · both on T7 RAW Archive". Move 1 → bản sao bị đánh dấu vào Thùng rác; ảnh ở lại với bản còn lại.
- Popup **Source** trên toolbar Duplicates lọc nhóm theo nguồn. Thanh dưới: "2 photos marked in 2 groups · ~55.6 MB" +
  dòng "Photos Library items go to Recently Deleted · folder and drive files go to the Trash · NAS files can only be hidden".
- Dấu xoá, cổng "giữ ít nhất một", thu gọn nhóm, sắp xếp: giữ nguyên [FS-06.06](../FS-06-collections/06-duplicates.md) /
  [06b](../FS-06-collections/06b-duplicates-marks-merge-delete.md).
- Nhóm Exact cùng hash **không** có dòng khác biệt sao/sửa (cùng ảnh thì chung rating, chung recipe) — chỉ khác
  **đường dẫn**. Board `MAC_Duplicates` sửa theo.
- **Merge** với ảnh file chỉ thừa hưởng **sao, cờ, keyword** — ghi vào database và sidecar. Favorite, vị trí, ngày chụp
  sớm nhất (FS-06.06b §2) chỉ áp khi ảnh giữ là ảnh Photos.
- Favorite của ảnh file nằm ở database **và** vùng ShotDex của sidecar ([05 §2](05-data.md)).

## 5. Statistics — đếm một lần (D7)

- Mỗi **ảnh** đếm một lần, dù có bao nhiêu bản sao. Ảnh offline vẫn đếm. Ảnh ẩn (§3) không đếm.
- Popup **Source**: "All Sources" đếm một lần; chọn một nguồn → ảnh có bản sao ở nguồn đó. Ảnh có bản sao ở T7 và NAS
  hiện trong cả hai; tổng các nguồn có thể lớn hơn All — chú thích cạnh popup: "Each photo counted once across sources"
  (board `MAC_Statistics`).
- Chỗ giữ chỗ chưa tải từ cloud không đếm ([01b §4](01b-offline-access-and-cache.md)). Ảnh của ổ đang Hide Its Photos không đếm.
- Hai file mới có hash nhanh trùng, chưa băm đầy đủ: tạm đếm hai; gộp xong thì đếm một ([02 §1](02-identity-and-sidecars.md)).
