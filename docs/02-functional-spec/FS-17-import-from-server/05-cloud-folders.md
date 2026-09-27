# FS-17.05 — On Local Network và On Cloud (folder qua app Files)

`FS-17.05` · `Features/ServerImport/OnCloudScreen.swift` · `Data/Sources/FileServer/FilesFolderClient.swift`
· `Features/Albums/AlbumsScreen.swift` · cập nhật 2026-09-27

**Một câu:** Utilities tách thành **On Local Network** (NAS/máy tính) và **On Cloud** (một folder bất kỳ của Dropbox,
Google Drive, OneDrive, iCloud Drive… chọn qua app Files); folder cloud duyệt, Import, upload như một connection.

Nguồn: [intent](../../_intents/2026-09-27-cloud-folders.md).

## 1. Utilities

| Hàng | Glyph | Mở |
|---|---|---|
| **On Local Network** (thay "On Server") | `server.rack` | màn On Server hiện nay, tiêu đề **On Local Network**: connection SMB/SFTP/WebDAV + Uploaded from This Device |
| **On Cloud** | `icloud` | màn On Cloud (§2) |

Cả hai luôn hiện, kể cả khi chưa có gì — màn trống nói nó dùng để làm gì.

## 2. Màn On Cloud

- Rỗng: "Browse and import photos from Dropbox, Google Drive, OneDrive or iCloud Drive, and upload to them. The
  service's app must be installed." + nút **Add Cloud Folder**.
- Có: section **Cloud Folders**, mỗi hàng: tên, dưới là đường dẫn trong dịch vụ (`FileServerRow`); chạm → màn duyệt
  (FS-17.01) ở folder đó; nhấn giữ/vuốt → **Rename** / **Remove** (bỏ khỏi ShotDex, không xoá gì trong cloud). Toolbar
  **+** = Add Cloud Folder. Hàng **Uploaded from This Device** như On Local Network.
- **Add Cloud Folder** → trình chọn folder của hệ thống (Files). Chọn xong → hộp **Save Connection** (FS-15.04 §3 bước
  4) với Name = tên folder và công tắc Add to Collections; Save → lưu.
- Folder cloud được lưu như một connection giao thức **Files**: bookmark security-scoped của folder, không host/mật
  khẩu. Bookmark hết hạn/folder không còn → màn duyệt báo "ShotDex can't open this folder anymore. Add it again." + nút
  **Add Again**.

## 3. Duyệt và thao tác

- Cùng màn FS-17.01: lịch sử ‹ ›, menu tiêu đề **chỉ lên tới folder đã chọn** (gốc = folder đó, không ra ngoài),
  Icons/List, Sort, Show All Files, New Folder, Rename, Delete (có hỏi), Import to Library, ô Collections.
- Thumbnail: hỏi hệ thống (QuickLook) — dịch vụ tự trả thumbnail, **không tải trọn file**. Ảnh chỉ có trên cloud vẫn
  hiện ô; không có thumbnail → icon định dạng.
- **Date Taken** với ảnh chưa tải về máy: dùng ngày sửa (đọc EXIF phải tải cả file).
- Import to Library: tải file qua app của dịch vụ (NSFileCoordinator), kiểm như FS-17.02.
- Dung lượng ở footer: không có (dịch vụ không trả qua Files).

## 4. Upload

- Folder cloud có trong **Upload to ▸** như connection khác; luồng FS-15.02 giữ nguyên (ghi `.shotdex-part`, đọc lại
  kiểm SHA-256, đổi tên). File được giao cho app của dịch vụ, nó tự đồng bộ lên cloud sau — ShotDex kiểm bản nằm trong
  folder của dịch vụ trên máy.

## 5. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-45 | chưa có connection nào | mở Utilities | có **On Local Network** và **On Cloud**; mỗi màn trống có câu giải thích + nút thêm | ảnh `scripts/cloud-folders.json` |
| AC-46 | folder cục bộ `Cloud/Trip` chọn qua bookmark | lưu | dòng connection giao thức `files`, `bookmark` khác nil, không mật khẩu trong Keychain; đọc lại bookmark ra đúng folder | `FilesFolderClientTests.bookmarkRoundTrip` ✅ |
| AC-47 | folder có `a.JPG`, `b.CR3`, `x/`, `.hidden` | liệt kê qua client Files | 2 ảnh + 1 folder, dot file ẩn; New Folder/Rename/Delete/upload `.part`→tên thật chạy trên đĩa | `FilesFolderClientTests.listsAndEdits` + `.uploadVerifiesAndRenames` |
| AC-48 | đường dẫn `..` hoặc tuyệt đối | client Files | bị từ chối (không ra ngoài folder đã chọn) | `FilesFolderClientTests.staysInsideTheFolder` |
| AC-49 | folder cloud | mở menu tiêu đề | gốc là folder đã chọn, không có cấp trên | `ServerBrowserModelTests.cloudRootIsThePickedFolder` |
| AC-50 | folder cloud trong Upload to ▸ | đẩy 2 ảnh | 2 file trong folder, SHA-256 khớp, không `.shotdex-part` | `FilesFolderClientTests.uploadVerifiesAndRenames` + ảnh |
| AC-51 | iOS 26.5 + 18.6 | Add Cloud Folder bằng On My iPhone (thay Dropbox trên simulator) | trình chọn hiện, chọn folder → Save Connection → hàng mới, duyệt thấy ảnh | ảnh `scripts/cloud-folders.json`; Dropbox/Google Drive thật ⚠️ chỉ máy thật |
