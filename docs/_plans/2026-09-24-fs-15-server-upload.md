# Kế hoạch — Upload lên file server (FS-15)

| Trường | Giá trị |
|---|---|
| Đặc tả | `docs/02-functional-spec/FS-15-server-upload/` |
| Ngày | 2026-09-24 |
| Trạng thái | đã duyệt — người dùng lệnh "plan rồi code auto luôn" (2026-09-24) |

## 1. Hiểu đúng chưa

Chọn ảnh → ⋯ → Upload to Server → chọn server + loại file → mỗi file: chép ra đĩa tạm (tính SHA-256), ghi
`.shotdex-part`, đọc lại tính SHA-256, khớp thì đổi tên + ghi lịch sử. Xong lô đề nghị xoá **chỉ** asset có
đủ mọi file gốc trên server. Server khai trong Settings (SMB/SFTP, nhiều cái, mật khẩu ở Keychain).

## 2. Đối chiếu AC ↔ code

Tính năng mới hoàn toàn: không AC nào đã đạt. Không có dòng ⚠️ lệch.

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1, AC-2 | ❌ | không có dựng đường dẫn / chọn resource | Domain thuần + test |
| AC-3…AC-6 | ❌ | không có client mạng nào | phiên upload trên một giao diện client; server giả trong test |
| AC-7…AC-9 | ❌ | — | luật trùng tên trong Domain; phiên gọi ra một người quyết định |
| AC-10 | ❌ | — | luật "được xoá" thuần trên lịch sử |
| AC-11, AC-12 (store) | ❌ | `AppDatabase.swift:425` là migration cuối (v18) | v19: 2 bảng; Keychain chưa ai dùng |
| AC-12 (UI) | ❌ | Utilities ở `AlbumsScreen.swift:527`; dấu lưới ở `PhotoGridCollectionView.swift` (`applyStatusBadges`) | hàng mới mở `PhotoListScreen`; cell nhận một tập id |
| AC-13 | ❌ | — | kiểm host key trong client SFTP, luật so khớp thuần |
| AC-14 | ❌ | ⋯ dựng ở `SelectionBarViews.swift:166`, closure ở `SelectionBarModel.swift` | thêm một closure, 3 màn gán |
| AC-15 | ❌ | `ScreenAwakeCoordinator.beginHold/endHold` đã có (`ScreenAwakeCoordinator.swift:62`) | **tái dùng**, không tự đụng idle timer |
| AC-16 | ❓ | cần máy thật | để `/verify` |

## 3. Tái dùng

- Giữ màn sáng: `ScreenAwakeCoordinator` (đếm hold, sống qua nền).
- Lưới ảnh từ danh sách id: `PhotoListScreen` / `PhotoListModel`.
- Hàng Utilities: `CollectionListRow`. Sheet đi qua `AssetActionHost` (`AssetActionsCoordinator.swift:291`).
- File tạm: tiền tố mới trong `TemporaryWorkspace` để lượt dọn lúc khởi động xoá được.
- Chép resource gốc: `PHAssetResourceManager.writeData` như `PhotoDragItem.swift:117`.

## 4. File đổi

| Tầng | File | Mới / sửa |
|---|---|---|
| Domain | `Domain/ServerUpload/ServerUploadPath.swift` · `ServerUploadPlan.swift` · `ServerUploadConflict.swift` · `ServerUploadEligibility.swift` · `ServerUploadSession.swift` · `RemoteFileClient.swift` (giao diện) · `HostKeyTrust.swift` | mới |
| Data | `Data/Database/FileServerStore.swift` · `ServerUploadStore.swift` · migration v19 · `Data/Sources/FileServer/SMBFileClient.swift` · `SFTPFileClient.swift` · `KeychainPasswordStore.swift` · `AssetOriginalExporter.swift` | mới |
| Features | `Features/ServerUpload/` (danh sách, form, sheet upload, model) · `SettingsScreen` · `SettingsRowLabel` · `SettingsSearchIndex` · `SelectionBarModel/Views` · Library/Album/SmartAlbum screens · `AlbumsScreen` · `PhotoGridCollectionView` · `MetadataPanel` | mới + sửa |
| App | `AppDependencies` · `AssetActionsCoordinator` · `TemporaryWorkspace` · Info.plist (Local Network) · project (2 gói SPM) | sửa |

## 5. Thứ tự task (một task = một commit)

| # | Task | AC | Test |
|---|---|---|---|
| 1 | Domain: đường dẫn + chọn file theo loại | AC-1, AC-2 | `ServerUploadPathTests`, `ServerUploadPlanTests` |
| 2 | v19 + hai store + Keychain | AC-11, AC-12 (query) | `ServerUploadStoreTests` |
| 3 | Phiên upload + client giả: ghi part → đọc lại → đổi tên, huỷ, rớt mạng | AC-3…AC-6 | `ServerUploadSessionTests` |
| 4 | Trùng tên: Keep Both, Apply to remaining, trùng SHA | AC-7…AC-9 | `ServerUploadConflictTests` |
| 5 | Luật được xoá | AC-10 | `ServerUploadEligibilityTests` |
| 6 | Gói SPM + client SMB/SFTP thật + host key | AC-13 | `FileServerHostKeyTests` |
| 7 | Settings: danh sách, form, Test Connection | (FS-15.01) | build + ảnh |
| 8 | ⋯ → sheet upload, tiến độ, hold màn sáng, hỏi xoá | AC-14, AC-15 | `ServerUploadModelTests` + ảnh |
| 9 | Utilities row, dấu lưới, dòng Photo Info | AC-12 | ảnh |
| 10 | Tài liệu: NF-03, OV-02, BD-02, FS-08, FS-06.01, FS-01.06, FS-02.03, DESIGN §8 | — | — |

## 6. Rủi ro

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| Agent khác đang sửa `project.pbxproj` và String Catalog chưa commit | cao | chỉ commit hunk của mình (`git apply --cached`), không `add -A` |
| API của Citadel/SMBClient khác mong đợi | vừa | client thật nằm sau giao diện; phiên và test không phụ thuộc gói |
| Duo 669pt: sheet thành toàn màn | chắc | nội dung sheet là `Form` cuộn được |
| Concurrency: phiên chạy ngoài main, UI trên main | vừa | phiên là `actor`; model `@MainActor` nhận sự kiện; kiểm huỷ ở mỗi khối |
| Bản gốc chỉ trên iCloud | vừa | `writeData` với mạng bật; lỗi → file lỗi, không dừng lô |

## 7. Chứng minh

- Test: 7 suite ở bảng trên. Màn chụp: Settings (rỗng, có server, form), sheet (chuẩn bị, tiến độ, kết quả),
  Utilities, lưới có dấu — iPhone 26.5 + 18.6; iPad; Duo trong.
- Agent Deploy: `data-migration`, `swift-concurrency`, `photokit-guard`, `privacy-manifest`, `ios26-parity`.
