# Plan: FS-15 — connection trong menu, chọn folder, folder theo ngày tuỳ chọn

| | |
|---|---|
| Spec | [FS-15](../02-functional-spec/FS-15-server-upload/README.md) — AC-1, AC-14, AC-17…AC-23 |
| Intent | [2026-09-24-local-network-upload](../_intents/2026-09-24-local-network-upload.md) — phản hồi người dùng 2026-09-26 |
| Ngày | 2026-09-26 |
| Duyệt | người dùng chọn cả 4 phương án đề xuất (menu con, nhớ folder + duyệt, Date Folders nhớ theo connection lần đầu tắt, tên không bắt buộc tự đánh số); lệnh "auto" giữ từ 2026-09-24 |

## Đối chiếu AC ↔ code

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 | ⚠️ lệch | `ServerUploadPath.swift:12` luôn chia ngày | thêm tham số `usesDateFolders` |
| AC-14 | ⚠️ lệch | `ServerUploadModel.reloadServers` chọn server dùng lần trước | chọn theo connection của menu; lần trước chỉ là dự phòng |
| AC-17 | ❌ | — | nhánh phẳng trong `ServerUploadPath` |
| AC-18 | ❌ | `FileServerDraft.normalized` chỉ lấy host khi trống | `FileServerNaming.uniqueName` + gọi trong `FileServerStore.save` |
| AC-19 | ❌ | `file_servers` không có cột nhớ | migration `v20-fileServerUploadOptions`: `uploadFolder`, `usesDateFolders`; `markUsed` ghi kèm |
| AC-20 | ❌ | `SelectionBarViews.swift:258` một nút | `ServerUploadMenu.row(for:)` (Domain) + `FileServerCatalog` (@Observable) + view menu con |
| AC-21 | ❌ | `PresentServerUploadAction` chỉ mang id ảnh | `ServerUploadTarget` đi theo request tới model |
| AC-22 | ❌ | `RemoteFileClient` chỉ liệt kê file | `folderNames(in:)` trên SMB/SFTP/fake; `RemoteFolderBrowser` + màn duyệt |
| AC-23 | ❌ | — | trạng thái lỗi + Try Again trong `RemoteFolderBrowser` |

## Tái dùng

`FileServerRow` (dòng phụ giao thức · vị trí), `RemoteFileError` (câu lỗi), `ServerUploadPath.normalizedFolder/join`,
`InMemoryRemoteFileClient` (thêm lỗi lúc nối), `RemoteFileClientFactory`.

## File đổi

| Tầng | File |
|---|---|
| Domain | `ServerUploadPath` · mới `FileServerNaming`, `ServerUploadMenu`, `RemoteFolderListing` · `RemoteFileClient` (+`folderNames`) |
| Data | `AppDatabase` (v20) · `FileServer` · `FileServerStore` · `SMBFileClient` · `SFTPFileClient` |
| Features | mới `FileServerCatalog`, `RemoteFolderBrowser`, `RemoteFolderScreen` · `ServerUploadModel` · `ServerUploadSheet` · `FileServerFormScreen` · `FileServerListScreen` · `SelectionBarModel/Views` · Library / AlbumDetail / SmartAlbumDetail · `RootTabView` · `AppDependencies` · `ShotDexApp` |
| Test | `ServerUploadPathTests`, mới `FileServerNamingTests`/`ServerUploadMenuTests`/`RemoteFolderBrowserTests`, `ServerUploadStoreTests`, `ServerUploadModelTests`, fakes |
| UI script | `server-upload-setup/sftp-conflict.json` (Add Connection), mới `server-upload-menu.json` |

## Task (mỗi task một commit)

1. docs: spec + plan (commit này).
2. AC-1/AC-17 đường dẫn phẳng + AC-18 tên + AC-19 cột nhớ (Domain + Data + test).
3. AC-22/AC-23 liệt kê folder trên client + `RemoteFolderBrowser` + test.
4. AC-20/AC-21/AC-14 menu con, request mang connection, sheet có Folder/Date Folders/màn duyệt, chữ "Connection".
5. ui-drive trên SMB/SFTP giả lập, cập nhật cột chứng minh, dòng Tiến độ.

## Rủi ro

- Migration thêm cột có `DEFAULT` — không đụng dữ liệu cũ, không cần đường lùi. `photo_metadata` không đổi.
- Menu con trong `ToolbarItem` Menu: đọc `FileServerCatalog` qua environment tuỳ chọn (không có thì về một dòng).
- SFTP: Citadel trả `longname`/`permissions` để biết là folder — kiểm cả hai.
- Duyệt folder mở kết nối thứ hai song song lúc đang đẩy? Không: duyệt chỉ ở bước chuẩn bị.

## Agent ở Deploy

`data-migration` (v20), `swift-concurrency` (browser task), `copy-consistency` (Connection vs Server), `ios26-parity`.
