# Plan — màn duyệt kiểu Files, Connect As, bỏ Share

Ngày: 2026-09-27 · Spec: FS-17.01 §2, §4b, §5 + FS-17.03 AC-19…29 · FS-15.01 §3a, FS-15.02 §2a, FS-15.04 §3, §5 +
FS-15.03 AC-22, 23, 42…48 · Trạng thái: **đã duyệt** (2026-09-27)

Nguồn: yêu cầu người dùng 2026-09-27 (đổi hành vi đã có → bắt đầu từ `/spec`, PROCESS.md §4). Quyết định đã chốt
qua câu hỏi: gộp Share vào Folder · bước Connect As · menu ⋯ đủ bốn nhóm (Select/New Folder/Sort, Icons/List,
Rename/Delete, Show All Files) · picker folder upload dùng chung màn · folder và ảnh cùng một kiểu (Icons: một lưới;
List: toàn hàng).

## 1. Đối chiếu AC ↔ code

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| 17/AC-19 lịch sử ‹ › | ❌ | `OnServerScreen.swift` đẩy một `ServerFolderRoute` mỗi folder; stack Collections là `NavigationPath` ẩn kiểu (`RootTabView.swift:195`) nên không bắt được folder vừa pop | một màn/lượt duyệt + `BrowseHistory` thuần |
| 17/AC-20 menu tiêu đề | ❌ | — | `BrowseHistory.ancestors` + `toolbarTitleMenu` |
| 17/AC-21 Icons/List đồng bộ | ❌ | `ServerBrowserScreen.swift:139` folder luôn là hàng trên lưới | lưới chung với ô folder; chế độ List mới; nhớ theo connection |
| 17/AC-22 Sort Size + chiều kiểu Files | ⚠️ một phần | `ServerFolderSort.swift:5` chỉ 3 lựa chọn, mặc định luôn tăng dần | thêm `.size`, `defaultAscending`, chọn lại = đảo chiều |
| 17/AC-23 Show All Files | ❌ | `ServerFolderListing` chỉ giữ `hiddenFileCount` | giữ `others: [RemoteEntry]` |
| 17/AC-24 New Folder | ⚠️ | có ở `RemoteFolderBrowser.createFolder` (`RemoteFolderBrowser.swift:48`), `validatedName` cho qua tên `.x` | chuyển vào model mới; chặn tên chấm; mờ ở gốc SMB |
| 17/AC-25 Rename | ❌ | `RemoteFileClient.move` có sẵn cho cả 3 client | model + sửa đường dẫn lịch sử |
| 17/AC-26 Delete đệ quy + bỏ bằng chứng | ❌ | `remove` chỉ xoá file (SMB `deleteFile`, SFTP `remove`) | `removeEmptyDirectory` mỗi client + `removeTree` mặc định đi đệ quy (WebDAV: DELETE một lệnh); store xoá dòng lịch sử theo host |
| 17/AC-27 xoá dừng ở lỗi đầu | ❌ | — | cùng task AC-26 |
| 17/AC-28 chế độ chọn folder | ❌ | picker cũ `RemoteFolderScreen.swift` chỉ liệt kê folder | `mode: .chooseFolder` |
| 17/AC-29 ảnh hai nhánh iOS + iPad | ❌ | — | script `server-files-browser.json` |
| 15/AC-22, 23 | ⚠️ đổi | `RemoteFolderBrowserTests` khoá hành vi picker cũ | viết lại trên model mới, xoá `RemoteFolderBrowser`/`RemoteFolderScreen` |
| 15/AC-42 Connect As | ❌ | `FileServerFormScreen.swift:297` chạm chỉ `fill()` rồi focus Username | `ConnectAsModel` + màn |
| 15/AC-43 sai mật khẩu | ❌ | — | cùng task |
| 15/AC-44 Connect Using | ❌ | hiện là `Menu` trên hàng (`FileServerFormScreen.swift:285`) | picker trong Connect As |
| 15/AC-45 Choose… lỗi dưới hàng Folder | ⚠️ | hàng Share có `shareError` (`FileServerFormScreen.swift:365`) | chuyển sang hàng Folder |
| 15/AC-46 migration v23 | ❌ | v22 ở `AppDatabase.swift:508` | migration chỉ dữ liệu (không đổi schema → không xoá DB dev) |
| 15/AC-47 tách đường dẫn SMB | ❌ | `SMBFileClient.connect` nối đúng `server.share` (`SMBFileClient.swift:31`) | `SMBPath` thuần + client đổi share trong phiên |
| 15/AC-48 upload qua đường dẫn gộp | ❌ | — | script, sau khi client xong |

## 2. Tái dùng

`ServerFolderModel` (listing, thumbnail, date, In Library, selection) giữ nguyên, mỗi folder một cái, model mới cache
chúng theo đường dẫn · `ServerBrowseSession` (một lệnh một lúc) · `ServerPhotoCell` · `GridDensity` / `PhotoGridLayout`
· `FileServerConnectionCheck` (Connect = hai bước đầu) · hộp Trust sẵn có của form · `ServerDownloadSheet`.

## 3. File đổi

| Tầng | File | Đổi |
|---|---|---|
| Domain | `ServerImport/BrowseHistory.swift` (mới) | back/forward/open/jump, ancestors |
| Domain | `ServerImport/ServerFolderListing.swift` | `others`, `ServerBrowserItem` (folder/photo/file) theo thứ tự |
| Domain | `ServerImport/ServerFolderSort.swift` | `.size`, `defaultAscending` |
| Domain | `ServerUpload/SMBPath.swift` (mới) | tách share/phần còn lại |
| Domain | `ServerUpload/RemoteFolderListing.swift` | chặn tên bắt đầu `.` |
| Domain | `ServerImport/ServerHistoryPaths.swift` (mới) | đổi tiền tố / khớp dưới folder |
| Data | `AppDatabase.swift` | v23 gộp share |
| Data | `SMBFileClient.swift` | gốc = danh sách share, đổi share trong phiên, `removeEmptyDirectory` |
| Data | `SFTPFileClient.swift`, `WebDAVFileClient.swift`, `RemoteFileClient.swift` | `removeEmptyDirectory`, `removeTree` |
| Data | `ServerUploadStore.swift`, `ServerDownloadStore.swift`, `FileServerStore.swift` | đổi/xoá đường dẫn theo host |
| Features | `ServerImport/ServerBrowserModel.swift` (mới) | lịch sử, cache folder model, chế độ, Icons/List, Show All Files, New Folder/Rename/Delete |
| Features | `ServerImport/ServerBrowserScreen.swift` | viết lại toolbar, lưới chung, List, nhấn giữ, thanh Download/Delete, thanh Choose |
| Features | `ServerImport/OnServerScreen.swift` | một route mỗi connection |
| Features | `ServerUpload/ServerUploadSheet.swift` | picker = màn mới chế độ chọn; xoá `RemoteFolderBrowser`, `RemoteFolderScreen` |
| Features | `ServerUpload/FileServerFormScreen.swift` | bỏ hàng Share, hàng Folder + Choose…, lỗi dưới hàng |
| Features | `ServerUpload/ConnectAsScreen.swift` + `ConnectAsModel.swift` (mới) | Connect As |
| Features | `FileServerRow` | dòng phụ `host/folder` |
| Test | mới: `BrowseHistoryTests`, `SMBPathTests`, `ServerBrowserModelTests`, `ServerBrowserEditTests`, `ConnectAsModelTests`, `FolderChooserTests`; sửa: `ServerFolderSortTests`, `ServerFolderListingTests`, `DatabaseTests`, fake `InMemoryRemoteFileClient`; xoá: `RemoteFolderBrowserTests` (thay bằng `ServerBrowserModelTests`) |
| Docs | FS-15, FS-17 (đã sửa ở commit spec), DESIGN.md icon list nếu thêm glyph |

## 4. Thứ tự task (một AC nhóm = một commit)

1. Domain thuần: `BrowseHistory`, `SMBPath`, sort Size, listing `others`, tên chấm — 17/AC-19, 20, 22, 23, 24(phần tên), 15/AC-47.
2. Migration v23 — 15/AC-46.
3. Client SMB đổi share trong phiên + `removeEmptyDirectory`/`removeTree` ba client + fake — nền cho 15/AC-48, 17/AC-26.
4. Store: đổi/xoá đường dẫn lịch sử theo host — 17/AC-25, 26 (phần dữ liệu).
5. `ServerBrowserModel`: lịch sử, chế độ, Icons/List, New Folder, Rename, Delete — 17/AC-21, 24, 25, 26, 27, 28.
6. `ServerBrowserScreen` viết lại + `OnServerScreen` — màn; ảnh iPhone 26.5.
7. Picker upload dùng màn mới, xoá picker cũ — 15/AC-22, 23.
8. Form: bỏ Share, Folder + Choose…, lỗi dưới hàng — 15/AC-45.
9. Connect As — 15/AC-42, 43, 44.
10. Script `server-connect-as.json` + `server-files-browser.json`, chụp iPhone 26.5, iPhone 18.6, iPad — 15/AC-42…48, 17/AC-29.
11. `/verify FS-15 FS-17`.

## 5. Rủi ro

- **Dữ liệu**: v23 đổi đường dẫn lịch sử. Sai tiền tố = mất dấu In Library và ảnh không được đề nghị xoá (lệch an
  toàn, không mất ảnh). Test trên dữ liệu v22 dựng tay. Không đường lùi — app chưa phát hành (CLAUDE.md).
- **Xoá trên server** là thao tác không lấy lại được: luôn hộp xác nhận, đệ quy dừng ở lỗi đầu, test với fake.
  Không bao giờ đụng PhotoKit trong luồng này (AC-26 khẳng định không có lệnh PhotoKit).
- **Bằng chứng upload**: quên xoá dòng lịch sử khi xoá file = FS-15.02 §7 có thể đề nghị xoá ảnh khỏi máy trong khi
  server không còn bản — lỗi mất dữ liệu nghiêm trọng nhất của luồng. AC-26 khoá lại.
- **SMB đổi share** trong một phiên: SMBClient giữ một tree id; đổi share = `disconnectShare` + `connectShare`. Đo trên
  impacket trước khi dựng màn.
- **Concurrency**: mọi lệnh vẫn qua `ServerBrowseSession.perform`; cache folder model không giữ Task sau khi rời màn.
- **Vuốt mép trái** mất trong màn duyệt (nút Back tự vẽ). Đã ghi trong FS-17.01 §2a; muốn giữ thì phải đổi sang đẩy
  màn, và Forward không làm được với `NavigationPath` hiện tại.
- **Thiết bị**: Duo không chụp được ở lượt này (như các AC trước); iPad form không điền được bằng ui-drive (nhãn
  "Password" trùng) — AC-42 chỉ có iPhone.

## 6. Agent ở giai đoạn Deploy

`data-migration` (v23, xoá lịch sử) · `swift-concurrency` (model, session) · `ux-reviewer` (xoá, Connect As) ·
`ios26-parity` (toolbar ‹ ›) · `hig-components` (menu ⋯, title menu, context menu).
