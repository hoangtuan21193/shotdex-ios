# Kế hoạch — Settings Mac đủ 6 pane (FS-18.04 §3)

| Trường | Giá trị |
|---|---|
| Đặc tả | [FS-18.04 §3](../02-functional-spec/FS-18-mac-app/04-other-screens.md) · AC-59, AC-67…AC-80 ở [FS-18.06](../02-functional-spec/FS-18-mac-app/06-acceptance-criteria.md) |
| Intent | [2026-11-04-mac-settings-panes](../_intents/2026-11-04-mac-settings-panes.md) |
| Ngày | 2026-11-04 |
| Trạng thái | đang làm — S0, S1, S3–S5, S8 xong, S2 và S7 một phần (AC-71 chờ `MacSidebar.swift`) (loop: [MAC_SETTINGS_LOOP.md](MAC_SETTINGS_LOOP.md)) |

## 1. Hiểu đúng chưa

Settings Mac hôm nay có một pane (General › Indexing + Background). Làm đủ 6 pane theo board: General, AI, Sources,
Editing, Servers, Cameras. Hàng có tính năng thật thì chạy. Hàng Mac chưa có tính năng thì hiện mờ, chữ phụ
"Available in a later version": cả pane AI, cả pane Editing, 4 hàng General, 4 hàng Sources. Tiến độ index hiện ở
Sources › Index và ở chân sidebar; chân sidebar không còn bị khung Common Photos che.

## 2. Đối chiếu AC ↔ code

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-59 6 pane, 720, ≤640, tên pane | ❌ | `ShotDexMac/Settings/MacSettingsWindow.swift:9-13` một `Tab` General, `.frame(width: 720)`, không cap cao | TabView 6 tab, mỗi pane cuộn trong ≤ 640 |
| AC-67 badge + chọn trường trên ô | ❌ | `ShotDexMac/Library/MacPhotoGrid.swift:258-261` badge luôn hiện; `:292-300` `exifLine` cứng ISO·mm·f; key iOS `display.showISO…` đọc ở `PhotoGridCollectionView.swift:2684-2698` (file không vào Mac); `SettingsKeys.swift:37` `display.showFileType` | đưa lựa chọn trường thành Domain `ThumbnailInfoFields` (đọc key chung, thêm File Name, Capture Time); `exifLine` dùng nó |
| AC-68 Full-Frame Equivalent | ❌ | `MacPhotoGrid.swift:296` in tiêu cự gốc; toán `Domain/EquivalentFocalLength.swift:4-18`; key `display.focalStyleEquivalent` chỉ là chuỗi trong `SettingsScreen.swift:33` | thêm hằng `SettingsKeys`, ô Mac tính tương đương bằng `SensorLookup` đã có ở `MacDependencies.swift:100-102` |
| AC-69 hàng mờ | ❌ | không có pane AI/Editing; General thiếu 4 hàng | một view hàng mờ dùng chung cho mọi pane |
| AC-70 Sources › Index tiến độ | ❌ | `LibraryModel.indexProgress` (`LibraryModel.swift:171`, `IndexProgress` ở `IndexPipeline.swift:6`) có sẵn, Mac không đọc | Domain `IndexStatusLine` (chữ + phân số) dùng cho cả Index và chân sidebar |
| AC-71 chân sidebar xếp chồng | ❌ | `ShotDexMac/MacSidebar.swift:92-108` `busyFooter` thay hẳn dòng index; chỉ "Indexing…" | VStack: index (số + thanh) trên, Common Photos dưới |
| AC-72 Remove giữ file | ⚠️ một nửa | `SourceStore.remove` (`SourceStore.swift:50-62`) đúng nghĩa, có test iOS; Mac không có nút | nút + hộp hỏi; khoá bằng test store |
| AC-73 Add Folder + thả, không trùng | ❌ | `SourcesModel.addFolder` (`SourcesModel.swift:72`), `FolderSourceRunner.swift:20-29`; Mac không có `NSOpenPanel`, không có `dropDestination` | panel + drop; chống trùng theo bookmark/đường dẫn ở `SourcesModel` (Domain test) |
| AC-74 .xmp sidecar | gỡ | cull đã bỏ (L2) | không làm; board Sources bỏ hàng `.xmp` và câu Lightroom/Capture One |
| AC-75 pin, chặn ngủ | ❌ | `LibraryModel.swift:771,796` chỉ dừng ở Low Power; `MacIndexActivity` (`MacDependencies.swift:226-240`) luôn giữ `.idleSystemSleepDisabled`; dò pin có ở `MacBackupFormSheet.swift:146-151` | Domain `IndexPowerPolicy` (pin/sạc/LowPower → chạy/dừng); key `index.pauseOnBattery`, `index.preventSleep` (key iOS `SettingsKeys.swift:41` dùng lại nếu cùng nghĩa) |
| AC-76 giới hạn cache | ❌ | `PreviewCachePolicy.limitChoices` (`Domain/Shared/PreviewCachePolicy.swift:9-17`), không lưu; `RemoteThumbnailCache.standard` (`RemoteThumbnailCache.swift:53-58`) lấy limit mặc định; `trim()` `:112` | key `previews.limitGB`; `standard` đọc key; đổi limit thì `trim()`; một limit (L1) |
| AC-77 Delete Connection | ⚠️ một nửa | `FileServerStore.delete` (`FileServerStore.swift:92-106`) xoá server + mật khẩu, **không** gọi `SourceStore.remove` cho nguồn trên server đó (❓ có FK cascade không — kiểm ở task) | bảng Connections + Delete; xoá nguồn của nó trước |
| AC-78 Local Network | ❌ | trạng thái từ chối ở `MacServerFormSheet.swift:156-157`; không có URL `Privacy_LocalNetwork` | hàng + nút; cần máy thật để chứng minh |
| AC-79 Cameras | ❌ | backend có (`SensorFormat.swift`, `MetadataStore.customMappings`), UI iOS `CameraDatabaseScreen.swift` không vào Mac | pane Cameras mới theo `MAC_CameraDatabase`; đếm máy chưa rõ dùng hàm iOS đang gọi ở `SettingsScreen.swift:1417` |
| AC-80 Clear Index giữ dữ liệu người dùng | ⚠️ một nửa | `MetadataStore.deleteAll` (`MetadataStore.swift:424-440`) giữ sao, cờ, dấu; Mac không có nút; cần gọi lại `startIndexing(fullReindex:manual:)` (`LibraryModel.swift:756`) | nút + hỏi lại; test store khoá "album và sao còn" |

**Không có target test Mac.** Mọi logic đặt ở Domain/Data dùng chung (Mac biên dịch cả `ShotDex/` trừ danh sách loại),
test trong `ShotDexTests` (chạy trên simulator iOS). Tên test ghi ở AC (`MacThumbnailInfoTests`…) sẽ là suite trong
`ShotDexTests` thử phần dùng chung đó. Phần view Mac chứng minh bằng ảnh `Tools/mac-shot` với `-ShotDexDemoLibrary`
(không bao giờ chụp thư viện thật) và một arg DEBUG mới `-ShotDexSettingsPane <tên>` để mở thẳng pane.

## 3. Tái dùng

`SourcesModel` (add/read/rescan) · `SourceStore.remove/setWhenUnplugged` · `FolderSourceAccess` (Grant Access) ·
`MacServerFormSheet` + noti `.macAddServer` (Add/Edit/Test Connection) · `FileServerStore.delete` ·
`RemoteThumbnailCache.trim/removeAll` · `PreviewCachePolicy` · `EquivalentFocalLength` + `SensorLookup` ·
`MetadataStore.deleteAll` · `LibraryModel.indexProgress/startIndexing` · `MacIndexingSettings` (giữ nguyên, nằm trong
General) · `MacStatusDotLabelStyle` · `MacTheme` token. Không tạo token màu mới.

## 4. File đổi

| File | Tầng | Đụng gì |
|---|---|---|
| `docs/design/mac/project/MAC_Settings*.dc.html`, `MAC_SourceIndexing.dc.html`, `MAC_CameraDatabase.dc.html` | design | hàng mờ, chân sidebar xếp chồng, tiến độ ở Index |
| `ShotDex/Domain/Settings/ThumbnailInfoFields.swift` (mới) | Domain | trường trên ô + tiêu cự tương đương |
| `ShotDex/Domain/Indexing/IndexStatusLine.swift` (mới) | Domain | chữ + phân số tiến độ |
| `ShotDex/Domain/Indexing/IndexPowerPolicy.swift` (mới) | Domain | pin/sạc/Low Power |
| `ShotDex/Core/Utils/SettingsKeys.swift` | Core | `focalStyleEquivalent`, `pauseIndexOnBattery`, `previewCacheLimitGB` (đọc chung, iOS không đổi nghĩa) |
| `ShotDex/Data/Sources/FileServer/RemoteThumbnailCache.swift` | Data | `standard` đọc limit đã lưu |
| `ShotDex/Data/Database/FileServerStore.swift` | Data | Delete gỡ nguồn trên server trước (nếu chưa cascade) |
| `ShotDexMac/Settings/MacSettingsWindow.swift` | Mac | 6 tab, cap cao |
| `ShotDexMac/Settings/MacGeneralThumbnails.swift`, `MacSourcesSettings.swift`, `MacServersSettings.swift`, `MacCamerasSettings.swift`, `MacDimmedSettingsRow.swift` (mới) | Mac | các pane |
| `ShotDexMac/Library/MacPhotoGrid.swift` | Mac | badge theo key, dòng EXIF theo `ThumbnailInfoFields` |
| `ShotDexMac/MacSidebar.swift` | Mac | chân xếp chồng — **phiên khác đang sửa file này**, làm task này sau khi họ commit |
| `ShotDexMac/MacDependencies.swift` | Mac | ghép People and Pets, chính sách pin |
| `ShotDexTests/…` | test | một suite mỗi task |
| `Localizable.xcstrings` | — | **phiên khác đang sửa**; chuỗi mới tự vào catalog lúc build, commit sau khi họ xong |

## 5. Thứ tự task (một task = một commit)

| # | Task | AC | Test / chứng minh |
|---|---|---|---|
| S0 | Board: hàng mờ ở General/AI/Editing/Sources, Index có tiến độ, chân sidebar xếp chồng; bỏ hàng `.xmp` (Sources) và limit riêng (Servers); publish canvas | — | render + nhìn |
| S1 | Khung 6 pane + hàng mờ dùng chung; AI, Editing toàn mờ | AC-59, AC-69 | ảnh 6 pane sáng + tối |
| S2 | Tiến độ index: `IndexStatusLine`, Sources › Index, chân sidebar xếp chồng | AC-70, AC-71 | `MacIndexSummaryTests` + ảnh |
| S3 | General › Thumbnails: badge, trường, tiêu cự tương đương | AC-67, AC-68 | `MacThumbnailInfoTests` + ảnh lưới demo |
| S4 | Sources: bảng nguồn, Remove (hỏi), Re-index, Grant Access, Manage Access | AC-72 | `MacSourcesSettingsTests.removeKeepsFiles` |
| S5 | Sources: Add Folder… + thả folder, chống trùng | AC-73 | `MacSourcesSettingsTests.addFolderOnce` |
| S7 | Sources: pin, chặn ngủ, Place Names, People and Pets | AC-75 | `PowerPolicyTests.batteryPausesIndex` |
| S8 | Sources: Preview Cache (dung lượng, Clear, limit) | AC-76 | `PreviewCachePolicyTests.limitTrims` |
| S9 | Sources: Index summary, Re-index Library, Clear Local Metadata Index | AC-80 | `MacSourcesSettingsTests.clearKeepsUserData` |
| S10 | Servers: bảng Connections, Delete, phần cache của server + Clear | AC-77 | `MacServersSettingsTests.deleteConnection` + SMB ảo |
| S11 | Servers: Local Network Access | AC-78 | ảnh; chứng minh đủ cần máy thật |
| S12 | Cameras pane + Review Unknown Cameras | AC-79 | `MacCameraSettingsTests` |
| S13 | `/verify`, `design-parity` từng board | tất cả | báo cáo |

Mỗi task: build iOS + ShotDexMac, test liên quan (không cả bộ, không `Tools/gate`), ảnh sáng + tối so board, cột
"Chứng minh bằng" trong FS-18.06, dòng Tiến độ intent.

## 6. Rủi ro

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| Phiên khác đang sửa `MacSidebar.swift`, `Localizable.xcstrings`, `project.pbxproj` | cao | S2 phần sidebar làm sau khi họ commit; file mới vào target Mac bằng `Tools/mac-membership` thay vì sửa tay pbxproj; commit đúng đường dẫn |
| Delete Connection để lại nguồn mồ côi | vừa | kiểm FK ở S10, test trước |
| Clear Index xoá nhầm dữ liệu người dùng | thấp | `deleteAll` đã giữ; thêm test album + sao |
| Đổi limit cache làm iOS đổi theo | thấp | key chỉ đọc khi có giá trị; iOS không ghi |
| Chụp lộ thư viện thật (ảnh có mặt người) | vừa | chỉ chụp với `-ShotDexDemoLibrary` hoặc pane cố định |
| Chặn ngủ khi tắt "Prevent Sleep" làm index bị App Nap | vừa | giữ `.userInitiated`, chỉ bỏ `.idleSystemSleepDisabled` |

Agent ở giai đoạn Deploy: `design-parity` (mọi board Settings), `swift-concurrency` (S7, S8), `data-migration` (S9,
S10 — xoá dữ liệu), `copy-consistency` (chuỗi mới), `a11y-voiceover` (bảng, hàng mờ).

## 7. Đã chốt (2026-11-04)

- **L1:** một cache, một limit — limit chỉ ở Sources; Servers ghi phần của server + Clear Cache.
- **L2:** cull đã bỏ — bỏ hàng `.xmp` sidecar khỏi board và spec, AC-74 gỡ.

## 8. Cách chứng minh là xong

- Test: các suite ở mục 5 trong `ShotDexTests`.
- Ảnh (`Tools/mac-shot`, `-ShotDexDemoLibrary`): 6 pane sáng + tối; Sources lúc đang index và lúc xong; chân sidebar có
  cả index và Common Photos; lưới với 2 bộ trường; Cameras lọc Unknown.
- Tài liệu: FS-18.06 cột chứng minh; FS-18.04 §3 nếu L1/L2 đổi; intent Tiến độ; `docs/design/README.md` nếu thêm board.
