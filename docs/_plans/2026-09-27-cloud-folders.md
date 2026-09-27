# Plan — On Local Network / On Cloud (FS-17.05)

Ngày: 2026-09-27 · Spec: FS-17.05, AC-45…51 · Trạng thái: **đã duyệt** — người dùng chọn hướng qua câu hỏi 2026-09-27
(tên hai mục, qua app Files, cả upload); làm liền.

## 1. Đối chiếu

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-45 | ⚠️ | `AlbumsScreen.swift` hàng "On Server" luôn hiện, chưa có On Cloud | đổi tên + hàng mới + màn On Cloud |
| AC-46 | ❌ | `FileServer.TransferProtocol` chỉ smb/sftp/webdav | case `.files`, cột `bookmark` (v25) |
| AC-47, 48, 50 | ❌ | — | `FilesFolderClient` trên `FileManager` + `NSFileCoordinator`, giữ trong folder |
| AC-49 | ⚠️ | `ServerBrowserModel.title(for:)` gốc = tên connection đã đúng; menu tiêu đề tính từ `""` | gốc là folder đã chọn vì đường dẫn tương đối — chỉ cần test |
| AC-51 | ❌ | — | trình chọn folder `UIDocumentPickerViewController` |

## 2. Tái dùng

Toàn bộ màn duyệt, `ServerBrowseSession`, luồng upload, `SaveConnectionSheet`/`ConnectionSaver`, `FileServerRow`,
Network shortcuts — client mới chỉ là một `RemoteFileClient` nữa.

## 3. Task

1. `.files` + migration v25 (`bookmark` blob) + các switch giao thức — AC-46.
2. `FilesFolderClient` + thumbnail QuickLook + bỏ đọc EXIF khi file chưa tải — AC-47, 48, 50.
3. Utilities: On Local Network, On Cloud, Add Cloud Folder → Save Connection — AC-45, 49, 51.
4. Ảnh + test toàn bộ.

## 4. Rủi ro

- Security scope: phải `startAccessingSecurityScopedResource` quanh mọi lệnh; bookmark stale → xin chọn lại.
- Tải cloud: `NSFileCoordinator` đọc có thể chờ app dịch vụ tải file — chỉ khi Import/Upload kiểm, không khi vẽ lưới.
- Simulator không có Dropbox/Google Drive: thử bằng On My iPhone; dịch vụ thật chỉ kiểm được trên máy thật.

## 5. Agent

`data-migration` (v25), `privacy-manifest` (file timestamp/disk-space API), `ux-reviewer`.
