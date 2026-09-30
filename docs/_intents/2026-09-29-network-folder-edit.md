# Intent: Sửa và dùng ảnh trong folder On Local Network / On Cloud như ảnh trong album

| Trường | Giá trị |
|---|---|
| Tác giả | hat.tuan@karabiner.tech |
| Ngày | 2026-09-29 |
| Trạng thái | accepted — người dùng 2026-09-29: "ok tên file theo đề xuất, accepted" |
| Tiến độ | **đang làm** (2026-09-30) — task 1/22, 1/23 AC xanh (AC-59), plan [2026-09-30-network-folder-edit](../_plans/2026-09-30-network-folder-edit.md) |
| Nguồn | phản hồi người dùng (2026-09-29) |
| Spec sinh ra từ đây | [FS-17.06](../02-functional-spec/FS-17-import-from-server/06-edit-and-export.md) |

## Problem — vấn đề

Người chụp để ảnh trên NAS hoặc Dropbox/Drive (FS-17.04 ô Network, FS-17.05 On Cloud). Mở folder đó ra, họ chỉ làm
được đúng một việc với ảnh: **Import to Library**. Muốn sửa một tấm, họ phải import cả tấm vào Photos, sửa, rồi tự
upload lại. Ảnh gốc giờ nằm ở hai nơi, còn library trên máy thì đầy thêm những ảnh họ không định giữ ở đó.

Bằng chứng trong code hôm nay:

- Menu nhấn giữ một ảnh trên server chỉ có Import to Library, Rename và Delete
  (`Features/ServerImport/ServerBrowserScreen.swift:276-304`). Màn xem một ảnh (`ServerPhotoViewer`, cùng file :793)
  chỉ có Import to Library.
- Ảnh trong album thường có Share, Edit, Paste Edits, Combine, Collage, Video, Resize, Export EXIF, Copy…
  (`Features/Library/SelectionBarViews.swift:200-340`). Không mục nào mở được cho ảnh trên server.
- Mọi đích của các lệnh đó chỉ nhận `PHAsset`: editor (`Features/Editing/PhotoEditorScreen.swift:23`),
  collage (`Features/Collage/CollageScreen.swift:11`), video (`Features/VideoStudio/VideoStudioScreen.swift:13`).
  Ảnh không nằm trong Photos thì không vào được.

**Quyết định cũ bị thay.** Intent [network-shortcuts](2026-09-27-network-shortcuts.md) (debate 2026-09-27) đã
chốt *không* làm menu album cho folder mạng, với ba lý do: (1) Delete cùng tên mà hậu quả khác, (2) Compress ghi đè
bản gốc, (3) Edit không có chỗ lưu rõ ràng. Ngày 2026-09-29 người dùng đổi hướng. Intent này trả lời lý do (3) bằng
bước hỏi nơi lưu lúc xuất, trả lời (2) bằng cách không bao giờ tự ghi đè, và giữ nguyên lý do (1): Delete trên server
vẫn là lệnh kiểu Files, có hỏi xác nhận, không đổi tên thành lệnh album.

## Proposed outcome — kết quả mong muốn

Người dùng đã chốt ngày 2026-09-29:

- **Menu.** Ảnh trong folder On Local Network / On Cloud, lúc nhấn giữ, lúc chọn nhiều ảnh và lúc xem một ảnh, có
  những lệnh làm được trên file: **Edit, Share, Paste Edits, Combine Photos, Create Collage, Create Video, Resize,
  Export EXIF (CSV), Copy**, cộng **Import to Library** đang có. Những lệnh chỉ có nghĩa với Photos thì không có:
  Adjust Date & Time, Adjust Location, Add to Collection, Duplicate, Favorite, Hide. Rename / Delete / New Folder giữ
  nguyên cách của Files.
- **Sửa trực tiếp.** Bấm Edit thì bản gốc được tải về máy làm bản tạm, rồi mở editor như với ảnh trong library. Người
  dùng thấy tiến độ tải. Bản gốc trên server chưa bị động tới.
- **Xuất thì hỏi nơi lưu**, mỗi lần. Có bốn nơi, chọn được một hay nhiều:
  1. folder gốc của ảnh trên server/cloud;
  2. thư viện Photos của máy;
  3. một connection/folder khác đã lưu (Local Network hoặc Cloud), duyệt tới folder muốn lưu;
  4. share sheet.
- **Bản gốc khi xuất về server/cloud: hỏi mỗi lần.** Mặc định là ghi file mới cạnh bản gốc. Chọn "Thay bản gốc"
  thì phải xác nhận thêm một lần, vì bản cũ mất vĩnh viễn.
- **Lưu tạm ngắn nhất có thể.** Xuất xong thì bản tạm và phần chỉnh sửa (recipe) bị xoá. Một đích lỗi thì giữ lại
  để Retry (chốt khi soạn spec). Lần sau mở lại tấm đó là
  sửa từ đầu.

## Affected users and systems — phạm vi ảnh hưởng

- **Màn hình:** màn duyệt server (FS-17.01) trong cả hai lối vào: ô Network (FS-17.04) và On Cloud (FS-17.05);
  `ServerPhotoViewer`; chế độ chọn nhiều ảnh trên server; editor, collage, video studio, combine, resize; sheet xuất
  mới; sheet upload (FS-15), dùng lại cho đích 1 và 3.
- **Thiết bị:** iPhone · iPad · Duo trong · Duo ngoài. Menu và sheet xuất phải có mặt ở mọi thiết bị
  ([[phone-has-every-ipad-feature]]).
- **Tầng code:** Features (ServerImport, Editing, Collage, VideoStudio, Creations, ServerUpload). Chỗ nặng nhất là
  editor/collage/video hôm nay chỉ nhận `PHAsset`, nên cần một nguồn ảnh không phải PHAsset. Data: bản tạm trên đĩa.
  ShotDexKit: render từ file (có thể đã được, cần kiểm).
- **Dữ liệu đã lưu:** không cần migration nếu recipe chỉ sống tới lúc xuất. Kho recipe hôm nay đặt theo `assetId`
  thì phải tách hẳn cho ảnh server, để ảnh server không lẫn vào đó.
- **Tài liệu phải sửa ở bước Design:** FS-17.04 §"Không có menu album", FS-17.01 (menu), FS-15 (upload làm đích xuất).

## Constraints — ràng buộc

- **Không tự ghi đè bản gốc trên server.** Mọi lần thay bản gốc đều phải xác nhận rõ.
- **Delete trên server vẫn là xoá thật**, vẫn hỏi xác nhận như hiện nay, không nằm chung nhóm với lệnh album.
- Connection chỉ đọc (`canEdit == false`) hoặc folder cloud không ghi được: đích 1 phải tắt kèm lý do, không được
  thành một lệnh bấm vào mà không có gì xảy ra.
- Bản tạm có thể là RAW 50–100 MB, có khi là cả loạt. Phải kiểm dung lượng trống trước khi tải, như sheet download
  (FS-17.02) đang làm. Tải phải huỷ được.
- Một connection chỉ chạy một lệnh server tại một thời điểm (`ServerBrowseSession` + `AsyncGate`).
- File trên cloud đi qua app Files (security-scoped bookmark), không gọi API Dropbox/Google (intent cloud-folders).
- Không thêm dependency. Không token/màu mới (DESIGN.md). Giữ được cả nhánh iOS 26 lẫn pre-26.
- Không test bằng ảnh có mặt người ([[no-face-photos-in-tests]]).

## Open questions — câu hỏi còn treo

Không còn câu nào. Người dùng đã trả lời các câu dưới đây ngày 2026-09-29, lần nào cũng chọn phương án đề xuất:

1. **Rời editor mà chưa xuất:** hỏi "Discard edits?" lúc rời. Discard thì xoá bản tạm. App bị kill thì bản tạm
   mồ côi được dọn ở lần mở app sau.
2. **Collage / Video / Combine / Resize** đi qua cùng sheet xuất bốn nơi. Một nguồn ảnh chỉ có một cách lưu.
3. **Share và Copy** tải bản gốc, dùng lại tiến độ tải của Edit. Export EXIF chỉ đọc phần đầu file, như lúc vẽ
   thumbnail.
4. **Chọn nhiều ảnh rồi Edit** nằm trong đợt này: chạy qua cả loạt như FS-03.09b, cả loạt hỏi nơi lưu một lần.

5. **Tên file mới** khi xuất về server: `<tên gốc>_edited.<đuôi>` như FS-15.02 §3 (đổi từ `-edited` khi soạn spec,
   người dùng chốt 2026-09-29), trùng thì ` (2)`. Định
   dạng theo cài đặt xuất của editor (JPEG/HEIC). Không bao giờ ghi ra RAW.

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
