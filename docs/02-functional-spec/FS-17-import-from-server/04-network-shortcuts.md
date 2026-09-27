# FS-17.04 — Folder trên server trong Collections (Network)

`FS-17.04` · `Features/Albums/AlbumsScreen.swift` · `Features/ServerImport/NetworkShortcut*.swift`
· `Data/Database/ServerShortcutStore.swift` · cập nhật 2026-09-27

**Một câu:** folder nào trên server cũng thêm được thành một ô trong mục **Network** của Collections; chạm là mở
màn duyệt server đúng folder đó.

Nguồn: [intent](../../_intents/2026-09-27-network-shortcuts.md).

## 1. Thêm

- Màn duyệt server (chế độ duyệt, không phải chọn folder), ⋯ nhóm 1: **Add to Collections** — thêm folder đang mở.
  Folder đã có ô → mục đó thành **Remove from Collections**.
- Nhấn giữ một ô folder: thêm **Add to Collections** (hoặc Remove…) sau Open.
- Không có ở gốc SMB (chỉ là danh sách folder chia sẻ). Gốc SFTP/WebDAV thêm được.
- Tên ô mặc định: tên folder (gốc: tên connection). Trùng (connection, đường dẫn) → không thêm lần hai.
- Không ghi gì lên server.

## 2. Mục Network trong Collections

- Một section mới **Network**, sau **Shared Albums**, trước **Media Types**; chỉ hiện khi có ít nhất một ô; ẩn/xếp
  lại được như các section khác (Customize).
- Hàng ô cuộn ngang, cùng `AlbumCoverTile` với My Albums (vuông `r-lg`, tên trên dải dưới), theo thứ tự thêm (mới
  nhất cuối).
- Bìa: ảnh đầu tiên của folder lúc mở ô gần nhất, thu nhỏ lưu trên máy (không đọc mạng khi vẽ Collections). Chưa có
  → nền placeholder + glyph `folder`.
- Góc trên-phải bìa: glyph `externaldrive.connected.to.line.below` trong đĩa tối nhỏ — nói đây là folder trên server,
  không phải album. VoiceOver: "<tên>, folder on <connection>".
- Connection bị xoá → ô của nó mất theo.

## 3. Mở

- Chạm ô → đẩy màn duyệt server (FS-17.01 §2) của connection đó, mở ở folder của ô. Lịch sử bắt đầu ở đó; menu tiêu
  đề đi lên cha được như thường. Mọi luật màn duyệt giữ nguyên: ⋯ kiểu Files, Rename/Delete trên server có hỏi,
  **Import to Library** là lối sang Photos.
- Không có menu album (không Edit, Compress, Share album) — debate 2026-09-27 trong intent.
- Mở xong và folder có ảnh → cập nhật bìa bằng thumbnail ảnh đầu theo thứ tự đang xếp.
- Server không tới được → màn duyệt báo lỗi FS-15.01 §3 + Try Again, như khi vào từ On Server.

## 4. Nhấn giữ ô trong Collections

| Mục | Làm gì |
|---|---|
| **Rename** | hộp đổi tên ô (không đổi tên folder trên server); tên rỗng không nhận |
| **Remove from Collections** | bỏ ô ngay, không hỏi (không mất gì — thêm lại được); folder trên server không bị đụng |

## 5. Dữ liệu

Bảng `server_shortcuts` (migration v24): `id`, `serverId` (FK `file_servers`, xoá theo connection), `path`, `name`,
`coverJPEG` (blob ≤ ~40 KB, cạnh dài 320 px), `createdAt`; duy nhất (`serverId`, `path`). Rename/Delete folder trên
server qua ShotDex sửa/xoá `path` của ô trùng hoặc nằm dưới (cùng luật FS-17.01 §4b).

## 6. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-31 | connection NAS, folder `photos/Trip` | ⋯ → Add to Collections; rồi mở ⋯ lại | 1 dòng `server_shortcuts` (NAS, `photos/Trip`, tên `Trip`); ⋯ giờ là Remove from Collections; thêm lần hai không tạo dòng mới | `ServerShortcutStoreTests.addIsIdempotent` + `ServerBrowserModelTests.shortcutToggle` |
| AC-32 | gốc SMB; gốc SFTP | ⋯ | gốc SMB không có Add to Collections; gốc SFTP có, tên ô = tên connection | `ServerBrowserModelTests.shortcutToggle` |
| AC-33 | 0 ô; rồi 2 ô | mở Collections | 0: không có mục Network; 2: mục Network sau Shared Albums, 2 ô theo thứ tự thêm, glyph server góc trên-phải | `ServerShortcutStoreTests.orderedByCreation` + ảnh `scripts/network-shortcuts.json` |
| AC-34 | ô `Trip` | chạm | màn duyệt mở ở `photos/Trip` của NAS; menu tiêu đề có `photos`, NAS | ảnh `scripts/network-shortcuts.json` |
| AC-35 | ô chưa có bìa, folder có 3 ảnh | mở ô, quay lại Collections | ô có bìa là thumbnail ảnh đầu; tắt server → bìa vẫn hiện | `ServerShortcutStoreTests.coverIsStored` + ảnh |
| AC-36 | ô `Trip` | nhấn giữ → Rename "Chọn lọc"; rồi Remove from Collections | tên ô đổi, folder trên server không đổi; Remove → ô mất, không hỏi, folder còn | `ServerShortcutStoreTests.renameAndRemoveLeaveServerAlone` + ảnh |
| AC-37 | connection NAS có 2 ô | xoá connection | 2 ô mất | `ServerShortcutStoreTests.deletingConnectionRemovesShortcuts` |
| AC-38 | ô trỏ `photos/Trip` | trong ShotDex đổi tên folder `Trip` → `Holiday`; rồi xoá `photos` | ô trỏ `photos/Holiday`; xoá `photos` → ô mất | `ServerShortcutStoreTests.followsRenameAndDelete` |
| AC-39 | mở ô | xem ⋯ | là ⋯ kiểu Files (Select, New Folder, Icons/List, Sort By, View Options, Remove from Collections) — không Edit/Compress | ảnh `scripts/network-shortcuts.json` |
| AC-40 | iOS 26.5, 18.6, iPad | Collections có 2 ô | hàng ô cùng kích thước ô My Albums, không bị cắt | ảnh ⚠️ chưa có |
