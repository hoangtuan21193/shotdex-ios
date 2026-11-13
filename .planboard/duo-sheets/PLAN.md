# Form dài trên màn trong của Duo — plan thực thi

> Chốt ngày 2026-11-11, sau 1 vòng · nguồn: .planboard/duo-sheets/plan.json · DUO_LOOP hàng 3b (kéo theo 4, 7, 10, 40, 41)

## Nguyên tắc
- Làm theo thứ tự; mỗi task xong thì tick và chạy phần "Kiểm tra".
- Cần đi chệch một quyết định đã chốt: dừng lại, hỏi người dùng.
- Chỉ màn trong của Duo (`\.isDuoInner`) đổi; iPhone, iPad, màn ngoài của Duo giữ nguyên (A1).
- Ảnh chụp: Duo inner phải đang mở. Sim boot ở trạng thái gập và không có lệnh mở màn trong — cần người dùng mở máy trong Simulator một lần trước bước 3.

## Việc cần làm

### 1. Cách mở
- [ ] **1.1 Đo `.presentationSizing(.page)` trên Duo màn trong** — thử trên Advanced Search
  - Theo: D1 (toàn màn, hai cột)
  - Xong khi: biết khung `.page` rộng bao nhiêu trên 951×669. ≥ 860 và vẫn vuốt đóng được → dùng nó; không thì `.fullScreenCover`.
  - Kiểm tra: `Tools/ui-drive` + dump frame của sheet
- [ ] **1.2 Modifier dùng chung "form toàn màn trên Duo"** — `ShotDex/Features/Shared/SizeMeasurement.swift` (cạnh `AdaptiveFormColumns`)
  - Theo: D1, A1, A3, A4
  - Xong khi: `.sheet` ở nơi khác giữ nguyên; trên `.duoInner` mở toàn màn; thanh trên cùng cách góc ≥ 32pt (`CompareLayout.duoInnerTopInset`); cột cuộn không chạy dưới vạch home.
  - Kiểm tra: `/build`

### 2. Áp cho từng màn
- [ ] **2.1 Advanced Search** — nơi trình bày `AdvancedSearchSheet` (`ShotDex/Features/Library/`)
- [ ] **2.2 Sửa Smart Album** — nơi trình bày `SmartAlbumEditorSheet` (`ShotDex/Features/Albums/`)
- [ ] **2.3 Add Connection** — `ShotDex/Features/ServerUpload/FileServerListScreen.swift` (`.sheet(item: $editing)`), và các nơi khác mở `FileServerFormScreen`
- [ ] **2.4 Upload to Server** — nơi trình bày `ServerUploadSheet`
- [ ] **2.5 New Backup** — `ShotDex/Features/Backup/BackupListScreen.swift:47`
- [ ] **2.6 Photo Info ba cột** — `ShotDex/Features/Library/PhotoDetailScreen.swift` (mở toàn màn), `ShotDex/Features/Library/MetadataPanel.swift` (chú thích + từ khoá đầu cột trái)
  - Theo: D2 (ba cột toàn màn)
  - Xong khi (mỗi màn 2.1–2.6): trên Duo màn trong form hai cột (Photo Info ba cột) hiện hết không cần cuộn với dữ liệu sim; Cancel/nút chính bấm được; iPhone/iPad không đổi.
  - Kiểm tra: `/build`; với 2.6 thêm test nếu đổi logic sắp cột trong `MetadataPanel`
- Không đổi (A2): Add a Source, Caption & Keywords, Save Edit, bảng chọn khoảng ngày (mở trên sheet khác).

### 3. Kiểm chứng và board
- [ ] **3.1 Chụp từng màn trên Duo màn trong** (`Tools/ui-drive` + `Tools/sim-shot … inner`), so với board: `DI_AdvancedSearch`, `DI_SmartAlbumEditor`, `DI_ServerForm`, `DI_ServerUpload`, `DI_BackupNew`, `DI_Metadata`
  - Xong khi: `Tools/design-board compare` không còn lệch > 2pt ngoài dữ liệu mẫu; board nào lệch thì sửa board theo app (A5).
- [ ] **3.2 Board Photo Info** — thêm chú thích/từ khoá vào `DI_Metadata`, bỏ `DI15_InfoKeywords`; publish canvas Duo
- [ ] **3.3 Tài liệu** — `DESIGN.md` §10.1c: trên Duo màn trong form hai cột mở toàn màn; FS liên quan nếu nhắc cách mở
- [ ] **3.4 DUO_LOOP** — đóng 3b, 4 (nếu vẫn là sheet trên sheet thì ghi rõ), 7, 10 (editor), 40, 41 với hash

## Ngoài phạm vi
- Màn ngoài của Duo, iPhone, iPad.
- Các hàng blocked khác của DUO_LOOP (2b, 3c, 8b, 10b, 13, 13b, 15, 20b, 22b, 26b, 30b, 38b, 5).
