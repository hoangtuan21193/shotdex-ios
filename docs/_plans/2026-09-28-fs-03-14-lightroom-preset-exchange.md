# Kế hoạch — Trao đổi preset Lightroom và chia sẻ look (FS-03.14)

| Trường | Giá trị |
|---|---|
| Đặc tả | [`FS-03.14`](../02-functional-spec/FS-03-photo-editor/14-lightroom-preset-exchange.md) + [14a](../02-functional-spec/FS-03-photo-editor/14a-import-and-report.md) · [14b](../02-functional-spec/FS-03-photo-editor/14b-lightroom-mapping.md) · [14c](../02-functional-spec/FS-03-photo-editor/14c-export-share-receive.md) — 33 AC |
| Intent | [2026-09-27-lightroom-preset-exchange](../_intents/2026-09-27-lightroom-preset-exchange.md) (accepted) |
| Quyết định | [`.planboard/editor-specs-decisions/DECISIONS.md`](../../.planboard/editor-specs-decisions/DECISIONS.md) — D20, D34–D50 |
| Quyết định lệch | [`.planboard/plans-deviations/DECISIONS.md`](../../.planboard/plans-deviations/DECISIONS.md) — E6–E9 |
| Liên quan | [13d §1](../02-functional-spec/FS-03-photo-editor/13d-presets-batch-devices.md) (chỗ đặt ô Import, menu giữ lâu — AC-38/39) · [FS-03.15](../02-functional-spec/FS-03-photo-editor/15-lightroom-parameter-parity.md) (thông số preset đổ vào; trường WB tuyệt đối E7 cùng vùng model) · [FS-03.04 §2](../02-functional-spec/FS-03-photo-editor/04-raw-and-render-graph.md) (WB của RAW) |
| Ngày | 2026-09-28 |
| Trạng thái | **nháp — chờ duyệt**; 4 dòng ⚠️ đã chốt 2026-09-28 (E6–E9, §3.1) |

## 1. Hiểu đúng chưa

Người chụp chuyển từ Lightroom mang được thư viện preset sang: một ô **Import XMP Preset** nhận nhiều file
`.xmp` / `.lrtemplate` / DNG có preset / `.shotdexlook` / `.cube` một lần, đọc phòng thủ (trần kích thước, không
DTD, không chạy Lua), quy đổi từng thẻ `crs:` về slider ShotDex theo bảng 14b, và **nói thật** từng preset sang
được bao nhiêu (✓/≈/✕ kèm lý do). Look của mình rời máy thành đúng một file `.shotdexlook` (hoặc `.xmp` / `.cube`
gần đúng) qua menu giữ lâu **Rename · Share · Export As · Delete** trên mọi ô, và về máy khác bằng AirDrop / Files /
"Open in ShotDex" hoặc extension mới **"Add to ShotDex"** (chỉ chép byte vào hộp thư App Group). Kho look chuyển
từ `UserDefaults` sang file JSON trong Application Support (D34). **Ship trước FS-03.15** (D36): thẻ chưa có chỗ
đặt thành dòng ✕ "…isn't in ShotDex yet", file preset gốc được giữ cạnh look để bản sau quy đổi lại (D35).

Tóm tắt khớp đặc tả. Một chỗ lệch với lời giao việc: đặc tả §5 ghi **bộ đọc preset/look nằm trong app, không vào
`ShotDexKit`** — extension "Add to ShotDex" chỉ kiểm cỡ + chép byte (D43), nên kế hoạch **không** thêm bộ đọc nào vào
kit. Ngoại lệ duy nhất sau chốt E7: cặp trường WB Kelvin / Tint tuyệt đối cho RAW vào model recipe và decoder RAW của
kit (task 17).

## 2. Đối chiếu AC ↔ code

Đã mở: `LookPresetStore.swift`, `EditorToolPanels.swift`, `EditClipboard.swift`, `ImportedLUTStore.swift`,
`LUTRendering.swift`, `CubeLUT.swift`, `LUTImportMessage.swift`, `LossyDecoding.swift`, `PhotoEditingModels.swift`,
`PhotoColorModels.swift`, `PhotoCurveModels.swift`, `PhotoRenderService.swift` (RAW WB, `applyLook`),
`PhotoEditorScreen.swift` (Save Look), `EditorChromeModel.swift` (UndoToast), `AssetActionsCoordinator.swift`
(ActionToast), `ShotDexApp.swift`, `AppDependencies.swift`, `ShotDex/Info.plist`, `ShotDex.entitlements`,
`PrivacyInfo.xcprivacy` (app + share), `ShotDexShare/{Info.plist,ShotDexShare.entitlements,ShareViewController.swift}`,
`WidgetShared/WidgetSharedContainer.swift`, `PropfindParser.swift`, `project.pbxproj` (targets), `LookPresetStoreTests.swift`.

Hiện trạng chung: kho look là `[LookPreset]` JSON trong `UserDefaults` (`LookPresetStore.swift:42-57`, `:111-113`,
khoá `SettingsKeys.swift:101`), `LookPreset` chỉ có `id/name/recipe/createdAt` (`LookPresetStore.swift:11-23`) — không
nguồn, không mã lượt nhận, không file gốc. Không có bộ đọc XMP/Lua/DNG-preset, không bộ ghi `.xmp`/`.cube`, không
định dạng `.shotdexlook`, không khai báo loại tài liệu (`Info.plist:61-75` chỉ có `asset-identifier`), `.onOpenURL`
chỉ nhận link widget (`ShotDexApp.swift:70-81`). Vì vậy gần như mọi AC là ❌.

### 2.1 Chung (14 §9)

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-0.1 | ❌ | không có đường nhập/xuất nào; mẫu `URLProtocol` chặn mạng có ở `WebDAVFileClientTests.swift:8` | test đăng ký `URLProtocol` ghi mọi request, nhập `.xmp` + xuất `.shotdexlook`, khẳng định 0 request |

### 2.2 Nhập và báo cáo (14a)

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-a1 | ❌ | không có bộ đọc XMP; ô duy nhất trong My Looks là Save Current (`EditorToolPanels.swift:107`, bản rộng `:214-270`) | `LightroomXMPReader` + `LightroomMapping` (Exposure, HSL); ô Import XMP Preset; nhãn "Imported" |
| AC-a2 | ❌ | không có | `LightroomTemplateReader` (bộ tách token hằng số, không chạy Lua) |
| AC-a3 | ❌ | không có; ImageIO đã dùng ở `ExifReader` (đọc metadata không giải mã) | `PresetDNGReader`: `CGImageSourceCopyMetadataAtIndex` → XMP → cùng bộ đọc; seam đếm giải mã |
| AC-a4 | ❌ | mẫu `XMLParser` có ở `PropfindParser.swift:18` (không chặn DTD/độ sâu) | `SafeXMLReader` (từ chối `<!DOCTYPE`, entity, lồng > 64) + câu lỗi có bước tiếp |
| AC-a5 | ❌ | `ImportedLUTStore.add` đọc cả file thành `String` **không** kiểm cỡ (`ImportedLUTStore.swift:74`) | `PresetImportLimits` kiểm `fileSizeKey` trước khi mở; áp cả cho `.cube` |
| AC-a6 | ❌ | không có lượt nhập nhiều file | `PresetImporter` gom kết quả từng file; `PresetImportReport` dòng đầu "N looks added · M skipped" |
| AC-a7 | ❌ | không có | thẻ lạ → dòng ≈ "Unknown setting X — ignored" |
| AC-a8 | ❌ | không có | XMP không có namespace `crs:` → ✕ "This XMP has no Lightroom edit settings" |
| AC-a9 | ❌ | Save Current ghi đè khi trùng tên (`LookPresetStore.swift:72-79`) — giữ nguyên; nhập thì chưa có đường | `LookPresetStore.addImported`: hậu tố " 2"; trùng tên + nội dung → ✕ "Already in My Looks" (D50) |
| AC-a10 | ❌ | nhập `.cube` có sẵn nhưng bộ chọn riêng, một file (`EditorToolPanels.swift:342-349`, `ImportedLUTStore.swift:70-87`) | `PresetImporter` rẽ `.cube` sang `ImportedLUTStore.add` (tái dùng), báo "Added to LUTs" |
| AC-a11 | ❌ | không có | nhập chạy trong `Task` huỷ được; kho chỉ ghi khi cả lượt xong |
| AC-a12 | ❌ | kho trong `UserDefaults`, không chỗ để file gốc (`LookPresetStore.swift:48`, `:112`) | kho JSON + thư mục trong Application Support (D34), trường `originalPresetFile`; Delete xoá cả bản chép (D35) |

### 2.3 Quy đổi Lightroom → ShotDex (14b)

Đích quy đổi đã có đủ cho các dòng ✓ của 14b §2: `PhotoAdjustments` (`PhotoEditingModels.swift:569`, Exposure ±2
EV `:549`, `blackPoint` hiện là "Blacks" `EditorAdjustmentCatalog.swift:223`), Color Mixer 8 dải và Color Grading
4 bánh + blending/balance (`PhotoColorModels.swift`), curve 4 kênh (`PhotoCurveModels.swift:47-51`), đủ film look
Fujifilm/Mono/Vivid (`PhotoEditingModels.swift:187-245`).

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-b1 | ⚠️ → ❌ chốt E6 | `EditorSyncScope.look` áp look bằng cách **thay toàn bộ** `adjustments`/`color`/`curve` (`EditClipboard.swift:95-107`); `LookPreset` luôn giữ đủ lát cắt (`LookPresetStore.swift:20`). Chốt theo spec: look nhập chỉ đổi thông số preset có ghi (14b §1, AC-b1 đã sửa) | **lưu tập thông số đã đặt cùng look nhập**: `LookPreset.namedSettings: Set<LookSettingKey>?` (nil = look ShotDex, thay đủ lát cắt như hôm nay); `LightroomMapping` điền tập đó; `EditorSyncScope.look` có nhánh thưa chỉ ghi các khoá trong tập; `.shotdexlook` mang tập đó (14c §1). Rồi `CameraProfileMap` khớp theo tên |
| AC-b2 | ❌ | không có | profile không khớp → Original + dòng ≈ nêu tên |
| AC-b3 | ❌ | dải Exposure ±2 có sẵn (`PhotoEditingModels.swift:549`) | kẹp + dòng ≈ nêu giá trị gốc và giá trị đặt |
| AC-b4 | ❌ | lát cắt look đã bỏ crop (`LookPresetStore.swift:20`) | nhóm `HasCrop`/`Crop*` → ✕ "Crop stays with each photo" |
| AC-b5 | ⚠️ → ❌ chốt E7 | `rawTemperature`/`rawTint` là **độ lệch tương đối** so với As Shot, ±4000 K / ±150 (`PhotoRenderService.swift:1127-1134`); không có trường Kelvin tuyệt đối. Chốt: **thêm** trường tuyệt đối cho RAW, `Temperature`/`Tint` map đúng số (14b §2 và AC-b5 đã sửa: map, không bỏ) | **sửa model trong `ShotDexKit`** (task 17): `PhotoAdjustments.rawWhiteBalanceKelvin: Double?` · `rawWhiteBalanceTint: Double?` (public, decode khoan dung); decoder đặt thẳng `neutralTemperature`/`neutralTint` khi có, bỏ qua độ lệch; slider WB của RAW hiện Kelvin thật. Rồi `LightroomMapping` map (task 18) |
| AC-b6 | ❓ | — | chờ câu treo 2 (RGBTable giải mã được không); không đoán. Nếu thử nghiệm thất bại → dòng ✕ "The profile's colour table isn't in the file" (đã có trong 14b §4) và AC đổi theo |
| AC-b7 | ❌ | không có | thẻ "✕ tới FS-03.15" → ✕ "…isn't in ShotDex yet" (D36) |
| AC-b8 | ❌ | lát cắt look đã bỏ mask (`LookPresetStore.swift:20`) | nhóm `MaskGroupBasedCorrections`… bỏ trọn, kể cả Exposure trong mask; dòng ✕ (D37) |

### 2.4 Xuất, chia sẻ, nhận, menu (14c)

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-c1 | ❌ | `LookPreset` đã `Codable` (`LookPresetStore.swift:11`) nhưng không có định dạng file; LUT chỉ lưu id (`PhotoEditingModels.swift:1183-1187`) | `LookFileCodec` schema v1, nhúng chữ `.cube` khi `lutID` trỏ LUT đã nhập (D47) |
| AC-c2 | ❌ | không có | `schemaVersion > 1` → ✕ "Made with a newer ShotDex — update the app to add it" |
| AC-c3 | ❌ | không có | `LookXMPWriter` (chiều ngược 14b) + sheet xuất có câu giải thích và dòng "not affiliated…" (D38, D40) |
| AC-c4 | ❌ | có `applyAdjustments`/`applyLook` công khai (`PhotoRenderService.swift:1208`, `:1870`), chưa có bộ ghi `.cube` | `LookCubeBaker`: ảnh lưới 33³ qua phần theo-từng-pixel → ghi chữ `.cube` |
| AC-c5 | ❌ | menu giữ lâu chỉ có "Delete Look"/"Delete LUT" (`EditorToolPanels.swift:180`, `:401`, `:427`); ô preset có sẵn không có menu (`:475-497`) | menu bốn mục trên mọi ô, Delete ẩn với preset có sẵn (D20); cả nhánh phone (`:99`) và rộng (`:190`) |
| AC-c6 | ⚠️ → ❌ chốt E8 | `rename` nhận cả tên đã có — hai ô trùng tên (`LookPresetStore.swift:85-92`); chưa có UI gọi nó. Chốt theo spec: từ chối, gợi ý hậu tố "(2)" (14c §3 đã ghi) | **sửa code**: `rename` trả lỗi `.nameTaken(suggestion:)` (không phân biệt hoa thường, bỏ qua chính nó), gợi ý "‹tên› (2)", "(3)"… số nhỏ nhất còn trống |
| AC-c7 | ⚠️ → ❌ chốt E9 | Toast có Undo duy nhất sống **trong editor** và tắt sau **3 s** (`EditorChromeModel.swift:11-14`, `:173-181`); toast toàn app (`AssetActionsCoordinator.swift:361-376`) không có nút. `.onOpenURL` chỉ nhận link widget (`ShotDexApp.swift:70-81`); không khai loại tài liệu (`Info.plist:61-75`). Chốt theo spec: banner cấp app, mọi màn, Undo ~4 s (14 §5, 14c §4 đã ghi) | **banner cấp app** (task 30): mở rộng `ActionToast` thêm một nút hành động (Undo / Details) và thời lượng ~4 s, host ở `RootTabView` trên mọi tab và trên editor; rồi (task 31) khai UTType + document types, nhánh file URL ở `onOpenURL` |
| AC-c8 | ❌ | không có mã lượt nhận; `ImportedLUTStore.delete` có sẵn (`ImportedLUTStore.swift:89-95`) | `receiveID` trên look và LUT nhúng; Undo gỡ cả lượt; xoá bản chép trong hộp thư (D44) |
| AC-c9 | ❌ | không có target; App Group `group.com.hoangtuan.shotdex` đã có ở app + widget (`ShotDex.entitlements:10-13`, `WidgetSharedContainer.swift:11`) | target mới "Add to ShotDex" + hộp thư chờ App Group; app rút hộp thư lúc mở/active |
| AC-c10 | ❌ | extension ảnh hiện tại không có App Group, chỉ nhận ảnh (`ShotDexShare/Info.plist:11-12`, `ShotDexShare.entitlements:4`) — giữ nguyên (D42) | extension mới kiểm `fileSize` trước khi chép, trần 16 MB/file, hộp thư 50 file / 50 MB |
| AC-c11 | ❌ | phụ thuộc khai báo loại xuất (chưa có) | không thêm code ngoài AC-c7; chứng minh thủ công hai máy |
| AC-c12 | ❌ | không có | codec chỉ ghi trường §1; test khẳng định không khoá ảnh nào và < 10 KB |

**Đếm:** ✅ 0 · ❌ 32 (4 trong đó là ⚠️ đã chốt: b1, b5, c6, c7) · ⚠️ còn mở 0 · ❓ 1 (b6) = 33. Số AC không đổi.

### 3.1 Các dòng ⚠️ — đã chốt 2026-09-28

Quyết định lệch: `.planboard/plans-deviations/DECISIONS.md`.

| # | Dòng | Câu đã hỏi | Chốt | Hệ quả trong plan |
|---|---|---|---|---|
| E6 | AC-b1 (14b §1) | look nhập: thẻ vắng về 0 (như look ShotDex) hay giữ giá trị trên ảnh? | **chỉ đổi thông số preset có ghi**; look ShotDex tự lưu giữ như hôm nay | `LookPreset.namedSettings` lưu cùng look nhập (task 2), nhánh áp thưa (task 15) |
| E7 | AC-b5 | thêm Kelvin/Tint tuyệt đối cho RAW hay bỏ qua với ✕? | **thêm trường tuyệt đối cho RAW**, slider hiện Kelvin thật | task 17 mới (model kit + decoder + slider), task 18 map |
| E8 | AC-c6 | Rename sang tên đã có: từ chối hay cho trùng? | **từ chối**, gợi ý hậu tố "(2)" | task 1 sửa code |
| E9 | AC-c7 | banner cấp app Undo ~4 s hay toast editor 3 s? | **banner cấp app**, mọi màn | task 30 mới (component), task 31 nhận file |

## 4. Tái dùng — không làm lần hai

| Có sẵn | Ở đâu | Dùng cho |
|---|---|---|
| `CubeLUTParser` (2…64, 1D→3D, domain) | `ShotDexKit/Render/CubeLUT.swift:37-133` | `.cube` trong lượt nhập (AC-a10), LUT nhúng trong `.shotdexlook` (AC-c1/c8), kiểm lại file `.cube` vừa nướng (AC-c4). **Không viết bộ đọc thứ hai** (14a §2) |
| `ImportedLUTStore.add/delete` + `ImportedLUTFiles` + `LUTTableCache.forget` | `ImportedLUTStore.swift:70-95`, `LUTRendering.swift:10-30`, `:39` | thêm LUT từ lượt nhập / file nhận; Undo lượt nhận. Thêm một biến thể `add(text:name:)` cho bảng nhúng, cùng file |
| `LUTImportMessage.text(for:)` | `LUTImportMessage.swift:15-44` | lý do ✕ cho `.cube` hỏng trong báo cáo — không viết câu mới |
| `LossyArray` / `decodeLossyArrayIfPresent` | `ShotDexKit/Models/LossyDecoding.swift:13-44` | kho look JSON mới (một look hỏng chỉ mất nó), mảng curve point trong `.shotdexlook` |
| Lát cắt look `EditorSyncScope.look` / `EditClipboard.look(of:)` | `EditClipboard.swift:68-107` | chuẩn hoá mọi look nhập/nhận — một định nghĩa "look" duy nhất |
| Luật tên của Save Current (trim, trắng → từ chối, không phân biệt hoa thường) | `LookPresetStore.swift:63-72`, `:101-109` | tên look nhập, hậu tố trùng tên, Rename |
| `PhotoRenderService.applyAdjustments` / `applyLook` | `PhotoRenderService.swift:1208`, `:1870` | nướng `.cube` (AC-c4) và so sai lệch trong test |
| Mẫu `XMLParser` + delegate | `ShotDex/Domain/ServerUpload/PropfindParser.swift:18-90` | khung `SafeXMLReader` (thêm chặn DTD, độ sâu) |
| App Group + mẫu "file dùng chung hai target" | `WidgetSharedContainer.swift:11-19`, `ShotDex.entitlements:10-13` | vị trí hộp thư chờ, cùng group id; một file nguồn dùng chung app + extension như `WidgetShared/` |
| `ActionToast` (toast toàn app) | `AssetActionsCoordinator.swift:361-376` | banner cấp app (E9): thêm nút hành động + ~4 s, không bịa component thứ ba; `UndoToast` của editor (`EditorChromeModel.swift:11-14`) giữ nguyên |
| `PhotoAdjustments` + decoder RAW WB | `ShotDexKit/Models/PhotoEditingModels.swift:612-660`, `ShotDexKit/Render/PhotoRenderService.swift:1127-1134` | trường WB tuyệt đối (E7) — thêm cạnh `rawTemperature`/`rawTint`, cùng chỗ kẹp 2 000…50 000 K / ±150 |
| Luồng extension của `ShotDexShare` (UIViewController + SwiftUI, `NSItemProvider`) | `ShotDexShare/ShareViewController.swift:12-38` | khuôn cho extension "Add to ShotDex" |
| `StubWebDAVProtocol` | `ShotDexTests/WebDAVFileClientTests.swift:8` | test chặn mạng AC-0.1 |

## 5. Chỗ nào trong code

**Tầng nhận logic:** mọi bộ đọc, bảng quy đổi, codec, báo cáo, trần kích thước, tên, bộ nướng cube → **Domain**
(thuần, test được, không SwiftUI). Kho look, kho LUT, hộp thư → **Data**. Sheet, menu, banner, model trạng thái
nhập → **Features**. `ShotDexKit` **không nhận bộ đọc nào** (14 §5: extension chỉ chép byte); thay đổi kit duy nhất là
cặp trường WB tuyệt đối của E7 (model + decoder, `public`). Look là dữ liệu
người dùng → file riêng trong Application Support, **không** chạm `photo_metadata`/GRDB.

| Tầng | File | Đụng gì | Mới / sửa |
|---|---|---|---|
| Domain | `ShotDex/Domain/Editing/LookPresetStore.swift` | kho JSON file (D34) + thư mục `Looks/` (file gốc, thumbnail); `LookPreset` + `source` (`.shotdex`/`.imported`), `receiveID`, `originalPresetFile`, `namedSettings` (E6); `addImported` (hậu tố/trùng nội dung), `rename` từ chối trùng + gợi ý "(2)" (E8), `removeReceive(id)`, tên đổi cho preset có sẵn (AC-c5); đọc một lần khoá `UserDefaults` cũ rồi xoá (không phải lớp tương thích — chỉ không vứt look trên máy dev) | sửa |
| Domain | `ShotDex/Domain/Editing/LookExchange/LookFileCodec.swift` | `.shotdexlook` v1: định danh `com.hoangtuan.shotdex.look`, schema, tên, nguồn, ngày, lát cắt look, chữ `.cube` nhúng | mới |
| Domain | `…/LookExchange/PresetImportLimits.swift` | bảng trần 14a §2 là dữ liệu (5 MB, 16 MB, 200 MB, 500, XML 64, Lua 32) | mới |
| Domain | `…/LookExchange/SafeXMLReader.swift` | `XMLParser` không DTD/entity, lồng ≤ 64, trả cây thuộc tính + phần tử `crs:` | mới |
| Domain | `…/LookExchange/LightroomXMPReader.swift` | XMP → `LightroomSettings` (thẻ, tên preset, khoá `$$$/…` → tên file) | mới |
| Domain | `…/LookExchange/LightroomTemplateReader.swift` | `.lrtemplate`: tokenizer bảng Lua **chỉ hằng số**, lồng ≤ 32; biểu thức → lỗi cả preset | mới |
| Domain | `…/LookExchange/PresetDNGReader.swift` | ImageIO metadata-only (`kCGImageSourceShouldCache=false`), seam đếm giải mã cho test | mới |
| Domain | `…/LookExchange/LightroomMapping.swift` + `LightroomMappingTable.swift` | thẻ → slider, hệ số tuyến tính là **bảng dữ liệu** (14b §1), kẹp, nhóm bỏ (crop/retouch/HDR/mask), "not in ShotDex yet" (D36), PV cũ | mới |
| Domain | `…/LookExchange/CameraProfileMap.swift` | tên profile → `PhotoFilter` (14b §3) | mới |
| Domain | `…/LookExchange/CreativeProfileDecoder.swift` | RGBTable → `CubeLUT` — **chỉ sau khi câu treo 2 có kết quả** (❓) | mới, có điều kiện |
| Domain | `…/LookExchange/PresetImportReport.swift` | ✓/≈/✕ theo preset, dòng lý do, dòng đầu; nhãn chữ cho VoiceOver | mới |
| Domain | `…/LookExchange/PresetImporter.swift` | rẽ theo loại file, huỷ được, gom tất cả rồi mới ghi (AC-a11), ≤ 500 preset/lượt | mới |
| Domain | `…/LookExchange/LookXMPWriter.swift` · `LookCubeBaker.swift` · `LookFileName.swift` · `LookExportNotes.swift` | ghi `.xmp`; nướng 33³; tên file an toàn; câu "X doesn't carry into…" | mới |
| Domain | `ShotDex/Domain/Editing/EditClipboard.swift` | `EditorSyncScope.look` nhánh thưa: chỉ ghi khoá trong `namedSettings` (E6); look ShotDex giữ nhánh thay đủ | sửa |
| Kit | `ShotDexKit/Models/PhotoEditingModels.swift` · `ShotDexKit/Render/PhotoRenderService.swift` | `rawWhiteBalanceKelvin` / `rawWhiteBalanceTint` tuyệt đối (optional, `public`, decode khoan dung); decoder đặt thẳng `neutralTemperature`/`neutralTint` khi có (E7) — **vùng của FS-03.15** | sửa |
| Features | `ShotDex/Features/Editing/EditorAdjustmentCatalog.swift` (dòng RAW White Balance) | slider WB của RAW hiện Kelvin thật; kéo slider ghi trường tuyệt đối (E7) | sửa |
| Data | `ShotDex/Data/Sources/ImportedLUTStore.swift` | `add(text:name:receiveID:)`, kiểm cỡ trước khi đọc, `removeReceive(id)` | sửa |
| Data | `ShotDex/Data/Sources/LookInbox.swift` | hộp thư app (bản chép từ `onOpenURL`, xoá sau nhập — D44) + rút hộp thư App Group khi launch/active | mới |
| Shared (app + extension) | `LookInboxShared/LookInboxLocation.swift` | group id, tên thư mục chờ, trần 16 MB / 50 file / 50 MB — một nguồn cho hai tiến trình, như `WidgetShared/` | mới |
| Features | `ShotDex/Features/Editing/EditorToolPanels.swift` | ô **Import XMP Preset** cạnh Save Current (`:107`, bản rộng `:214-270`); nhãn "Imported"; menu bốn mục thay "Delete" (`:180`, `:401`, `:427`) và thêm cho ô có sẵn (`:475`) | sửa |
| Features | `…/Editing/LookExchangeModel.swift` | `@Observable`: tiến độ "Reading 120 of 500", Cancel, xuất ra file tạm cho share sheet, rename | mới |
| Features | `…/Editing/LookImportReportSheet.swift` · `LookExportSheet.swift` · `LookRenameAlert` | sheet `[.medium, .large]` (DESIGN.md §10.4); sheet xuất với dòng mất mát + hai dòng XMP | mới |
| Features | `…/Editing/PhotoEditorScreen.swift` | gắn file importer đa file, các sheet; cạnh alert Save Look (`:700-711`) | sửa |
| App | `ShotDex/App/ShotDexApp.swift` | nhánh file URL trong `.onOpenURL` (`:70-81`), rút hộp thư App Group khi `.active` (`:35`) | sửa |
| App | `ShotDex/App/AppDependencies.swift` | nối `LookInbox`, `LookExchangeModel`; kho look khởi tạo trước khi nhập (`:82`, `:239`) | sửa |
| App | `ShotDex/App/RootTabView.swift` / `AssetActionsCoordinator.swift` | banner cấp app (E9): `ActionToast` thêm nút hành động + ~4 s, host trên mọi tab và trên editor | sửa |
| Plist | `ShotDex/Info.plist` | `UTExportedTypeDeclarations` + `com.hoangtuan.shotdex.look` (conforms `public.data`, `public.content`, **không** `public.json`); `UTImportedTypeDeclarations` `com.hoangtuan.shotdex.imported.{xmp,lrtemplate,cube}`; `CFBundleDocumentTypes`; `LSSupportsOpeningDocumentsInPlace` = NO | sửa |
| Domain | `ShotDex/Domain/Editing/LUTImportMessage.swift:13` | `cubeType` dùng loại đã khai | sửa |
| Target mới | `ShotDexAddLook/` (tên hiển thị "Add to ShotDex") | `AddLookViewController.swift` (kiểm cỡ + `loadFileRepresentation` chép luồng, không nạp `Data`), `Info.plist` (activation rule SUBQUERY chỉ `com.hoangtuan.shotdex.look`, ≤ 50), `ShotDexAddLook.entitlements` (App Group), `PrivacyInfo.xcprivacy`; **không** link `ShotDexKit` | mới |
| Project | `ShotDex.xcodeproj/project.pbxproj` | target mới + embed vào app + membership của `LookInboxShared/` | sửa (rủi ro §7) |
| Test | `ShotDexTests/` | `LookExchangeOfflineTests`, `LightroomXMPReaderTests`, `LightroomTemplateReaderTests`, `PresetDNGReaderTests`, `PresetImportLimitsTests`, `PresetImportReportTests`, `PresetImportTests`, `LookPresetStoreTests` (thêm ca), `CameraProfileMapTests`, `LightroomMappingTests`, `CreativeProfileTests`, `LookFileCodecTests`, `LookExportXMPTests`, `LookExportCubeTests`, `LookInboxTests`, `RawWhiteBalanceTests` (E7), `AppBannerTests` (E9); fixture tự viết trong `ShotDexTests/Fixtures/Presets/` | mới/sửa |
| UI script | `ShotDexUITests/scripts/` | `looks-import-report.json`, `looks-export-xmp.json`, `looks-context-menu.json` | mới |

## 6. Thứ tự task

Mỗi task một commit `feat(FS-03.14): AC-x …`, test đi kèm, `/build` sau mỗi commit, đụng UI thì `/screens`.
Không có ✅ nên không có pha "khoá bằng test". Luật ✅ → ⚠️ → ❌ áp như sau: bốn câu ⚠️ **đã được trả lời** (E6–E9,
§3.1); ⚠️ nào không phụ thuộc gì (c6) làm đầu tiên, ⚠️ còn lại làm ngay khi phần nền của nó có (b1, b5 sau bộ đọc
XMP; c7 sau codec). Chốt E7 thêm task 17 (trường WB trong kit), chốt E9 thêm task 30 (banner cấp app): **33 → 35 task**.

**D36 — ship trước FS-03.15:** task 14 biến mọi dòng "✕ tới FS-03.15/16" của 14b §2 thành ✕ "…isn't in ShotDex
yet"; không task nào ở đây thêm thông số mới cho renderer, **trừ task 17** (WB tuyệt đối cho RAW, chốt E7) — task này
chạm model recipe của `ShotDexKit`, cùng vùng FS-03.15 đang sửa, nên báo agent làm FS-03.15 trước khi commit. Khi FS-03.15 thêm slider, chỉ bảng
`LightroomMappingTable` đổi, và file gốc giữ theo AC-a12 cho phép quy đổi lại (nút quy đổi lại ngoài v1).

**Tiền đề:** 14b còn là bản nháp — câu treo 3 (danh sách thẻ Lightroom 13–15) chưa có kết quả `lightroom-parity`.
Chạy agent đó **trước task 7**; tên thẻ nào đổi thì sửa 14b trong commit của task đó.

| # | Pha | Task | AC | Test kèm theo (chứng minh) |
|---|---|---|---|---|
| 1 | A · Kho look | Rename từ chối tên đã có, gợi ý "‹tên› (2)" (chốt E8) | AC-c6 | `LookPresetStoreTests.renameRefusesATakenName` (khẳng định cả tên gợi ý) |
| 2 | A | Kho JSON trong Application Support + thư mục `Looks/`; trường nguồn/`receiveID`/file gốc/`namedSettings` (E6); Delete xoá bản chép; đọc một lần khoá cũ | AC-a12 | `LookPresetStoreTests.keepsOriginalPresetBesideLook` (+ các test cũ của `LookPresetStoreTests` chạy trên kho file) |
| 3 | A | `addImported`: hậu tố, trùng tên + nội dung → ✕, không bao giờ ghi đè | AC-a9 | `LookPresetStoreTests.importNeverOverwritesAUserLook` |
| 4 | B · `.shotdexlook` | `LookFileCodec` v1 + LUT nhúng + `namedSettings` | AC-c1 | `LookFileCodecTests.roundTripIsExact` |
| 5 | B | schema mới hơn bị từ chối có lý do | AC-c2 | `LookFileCodecTests.newerSchemaIsRefusedWithReason` |
| 6 | B | file chia sẻ không mang ảnh, < 10 KB | AC-c12 | `LookFileCodecTests.sharedFileCarriesNoImage` |
| 7 | C · Bộ đọc | `SafeXMLReader` + `LightroomXMPReader` + khung `LightroomMapping` (Exposure, HSL) + `PresetImportReport` | AC-a1 (phần Domain) | `LightroomXMPReaderTests.exposureAndRedHueMap` |
| 8 | C | XML hỏng → ✕ có bước tiếp | AC-a4 | `LightroomXMPReaderTests.malformedXMLGivesNextStep` |
| 9 | C | sidecar không có `crs:` | AC-a8 | `LightroomXMPReaderTests.sidecarWithoutSettingsIsNotAPreset` |
| 10 | C | thẻ lạ thành dòng ≈ | AC-a7 | `PresetImportReportTests.unknownTagsAreListedNotFatal` |
| 11 | C | kẹp ngoài dải | AC-b3 | `LightroomMappingTests.exposureBeyondRangeIsClampedAndReported` |
| 12 | C | crop không bao giờ vào look | AC-b4 | `LightroomMappingTests.cropIsNeverImported` |
| 13 | C | mask không bao giờ vào look (D37) | AC-b8 | `LightroomMappingTests.masksAreNeverImported` |
| 14 | C | thẻ chưa có chỗ đặt → ✕ "…isn't in ShotDex yet" (D36) | AC-b7 | `LightroomMappingTests.missingTargetsAreSkippedWithAReason` |
| 15 | C | look thưa (chốt E6): `LightroomMapping` điền `namedSettings`, `EditorSyncScope.look` nhánh thưa; camera profile → film look | AC-b1 | `CameraProfileMapTests.fujiNamesMapToTheSameLook` + `EditClipboardTests.importedLookLeavesUnnamedSettingsAlone` |
| 16 | C | profile lạ → Original + ≈ | AC-b2 | `CameraProfileMapTests.unknownProfileFallsBackToOriginal` |
| 17 | C | **mới (chốt E7)** — trường WB tuyệt đối cho RAW trong `ShotDexKit` (`PhotoAdjustments` + decoder `PhotoRenderService`) + slider RAW WB hiện Kelvin; **chạm model kit, vùng FS-03.15** | (nền cho AC-b5) | `RawWhiteBalanceTests.absoluteKelvinOverridesTheAsShotOffset` + `RawWhiteBalanceTests.jpegIgnoresAbsoluteWhiteBalance` |
| 18 | C | map `Temperature`/`Tint` → trường tuyệt đối | AC-b5 | `LightroomMappingTests.absoluteWhiteBalanceIsRAWOnly` |
| 19 | C | `.lrtemplate` chỉ hằng số | AC-a2 | `LightroomTemplateReaderTests.readsSettingsAsData` (+ `functionCallsAreRejected` của 14a §6) |
| 20 | C | DNG: chỉ gói XMP, 0 lần giải mã | AC-a3 | `PresetDNGReaderTests.readsXMPWithoutDecodingPixels` |
| 21 | C | trần kích thước trước khi đọc | AC-a5 | `PresetImportLimitsTests.oversizedFileIsRefusedUnread` |
| 22 | C | creative profile RGBTable → LUT — **chỉ làm nếu thử nghiệm câu treo 2 đạt**; không đạt thì sửa AC-b6 thành dòng ✕ và test khẳng định dòng đó | AC-b6 ❓ | `CreativeProfileTests.rgbTableBecomesALUT` |
| 23 | D · Luồng nhập | `PresetImporter` đa file + ô Import XMP Preset + sheet báo cáo + nhãn "Imported" | AC-a6 (+ phần UI của AC-a1) | `PresetImportReportTests.oneBrokenPresetOnlyLosesItself` + `looks-import-report.json` |
| 24 | D | `.cube` trong cùng lượt → tab LUTs | AC-a10 | `PresetImportReportTests.cubeFilesGoToLUTs` |
| 25 | D | Cancel không thêm gì | AC-a11 | `PresetImportTests.cancelAddsNothing` |
| 26 | D | nhập + xuất không gọi mạng | AC-0.1 | `LookExchangeOfflineTests.importAndExportNeedNoNetwork` |
| 27 | E · Xuất & menu | menu bốn mục trên mọi ô, Delete ẩn với preset có sẵn, Share một `.shotdexlook` | AC-c5 | `looks-context-menu.json` (dump nhãn menu trên ô Golden / Velvia / LUT) |
| 28 | E | `LookXMPWriter` + sheet xuất `.xmp` | AC-c3 | `LookExportXMPTests.writesCrsAndDropsFilmLook` + `looks-export-xmp.json` |
| 29 | E | `LookCubeBaker` + dòng mất mát | AC-c4 | `LookExportCubeTests.bakesColourOnly` |
| 30 | F · Nhận | **mới (chốt E9)** — banner cấp app: `ActionToast` thêm nút hành động (Undo / Details) + ~4 s, host ở `RootTabView` trên mọi tab và trên editor | (nền cho AC-c7, c8, c9) | `AppBannerTests.actionBannerStaysAboutFourSeconds` + chụp Library và editor |
| 31 | F | khai UTType + document types; `onOpenURL` file → chép vào hộp thư → nhập → banner cấp app; khởi động lạnh nhập một lần | AC-c7 | `LookInboxTests.coldLaunchFileIsImportedOnce` + `xcrun simctl openurl` + `Tools/sim-shot` (ui-drive không mở được file) |
| 32 | F | Undo gỡ cả lượt nhận (look + LUT nhúng), xoá bản chép | AC-c8 | `LookInboxTests.undoRemovesTheWholeReceive` |
| 33 | F | target "Add to ShotDex" + hộp thư App Group + rút lúc mở app | AC-c9 | `LookInboxTests.pendingFilesImportOnLaunch` + chạy extension trên simulator (Files → Share) |
| 34 | F | trần trong extension, chép luồng, đo bộ nhớ đỉnh | AC-c10 | `LookInboxTests.extensionRefusesOversizedFiles` + Instruments (Allocations) trên máy thật |
| 35 | F | máy không cài ShotDex nhận file | AC-c11 | thủ công hai máy thật; ghi kết quả vào cột chứng minh 14c |

## 7. Rủi ro và đánh đổi

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| **`project.pbxproj` dùng chung với agent khác** — target mới, embed, membership, entitlements đều chạm file này; xung đột gộp hoặc ghi đè lẫn nhau | cao | task 33 là **commit riêng chỉ chứa** thay đổi pbxproj + thư mục `ShotDexAddLook/`; báo agent kia trước khi sửa; objectVersion 77 dùng synchronized group (`project.pbxproj:144`) nên file mới trong thư mục có sẵn **không** chạm pbxproj — mọi file Domain/Features của task 1–32 đặt trong thư mục đã đồng bộ. Stage đường dẫn cụ thể, không `git add -A` / `stash` / `checkout --` (memory "two agents, one checkout") |
| Entitlement App Group cho extension mới — cần App ID mới có group trong provisioning | trung bình | group đã có cho app + widget (`ShotDex.entitlements:10-13`, `ShotDexWidget.entitlements:5-8`), chỉ thêm App ID `com.hoangtuan.shotdex.addlook`; bản không có group → `containerURL` nil → extension báo "Open ShotDex to add it" thay vì im lặng |
| Bản khai riêng tư cho target mới | trung bình | `PrivacyInfo.xcprivacy` riêng; extension dùng `fileSizeKey` (không phải required-reason) — nếu dùng ngày file để dọn hộp thư thì khai `C617.1`; thêm mục vào `/release-check`; agent `privacy-manifest` |
| Khai UTType sai — ShotDex không hiện trong "Open in…", hoặc cướp `.xmp`/`.cube` của app khác | trung bình | định danh riêng `com.hoangtuan.shotdex.imported.*` (D46), vai trò `Viewer`, rank `Alternate`; không khai zip/DNG (14a §1); kiểm bằng `simctl openurl` + Files trên máy |
| XML độc (XXE, billion laughs, đệ quy) | thấp khi có chặn | quét byte tìm `<!DOCTYPE`/`<!ENTITY` **trước** `XMLParser`; `shouldResolveExternalEntities=false`; đếm độ sâu ≤ 64 trong delegate; test riêng |
| `.lrtemplate` là mã Lua | trung bình | không có interpreter; tokenizer chỉ nhận chuỗi/số/bool/bảng; bất kỳ định danh không phải khoá, `..`, `(` → ✕ cả preset |
| Trần kích thước (16 MB `.shotdexlook`, 5 MB `.xmp`/`.lrtemplate`, 200 MB DNG) | thấp | kiểm `URLResourceValues.fileSize` trước khi mở; `.cube` đi qua cùng kiểm (hôm nay đọc không kiểm, `ImportedLUTStore.swift:74`); bảng là dữ liệu, đo lại trên bộ preset thật trước `/verify` (D49) |
| DNG 25 MB trong test — fixture không commit được, không dùng file của Adobe | trung bình | test tự dựng một TIFF/DNG tối thiểu có tag XMP (700) bằng mã; không ảnh có mặt người (memory); seam đếm giải mã chứng minh 0 lần |
| Bộ nhớ extension | thấp | extension không link kit, không phân tích; `loadFileRepresentation` chép luồng vào hộp thư, không nạp `Data`; đích < 30 MB (AC-c10), trần hệ thống ~120 MB (NF-02 §3 dòng 36); agent `memory-leak` |
| Khởi động lạnh: `onOpenURL` tới trước khi banner có chỗ hiện | trung bình | kho look nạp đồng bộ trong `AppDependencies.live()` (`ShotDexApp.swift:12`); `LookInbox` xếp hàng kết quả, banner đọc hàng khi `RootTabView` xuất hiện; test "nhập đúng một lần" |
| Chuyển kho look sang file (D34) | thấp | app chưa phát hành — không cần migration; đọc khoá `UserDefaults` cũ một lần rồi xoá chỉ để không mất look trên máy dev; kho mới đọc bằng `LossyArray`; agent `data-migration` kiểm luật "dữ liệu người dùng không vào `photo_metadata`" |
| Rename preset có sẵn (AC-c5 "Velvia: Rename") — `PhotoFilter.displayName` là enum cố định | trung bình | tên đổi lưu trong kho look (bảng `filter → tên`), chỉ panel Presets đọc; **nơi khác vẫn hiện tên gốc** (tóm tắt chỉnh sửa, Copy/Sync) — nêu cho `challenger`; nếu người dùng thấy lệch thì mở `REVIEW_QUEUE.md` |
| `lensCorrection` mặc định 1.0 (`PhotoEditingModels.swift:617`) — mọi look xuất `.xmp` đều ghi `LensProfileEnable=1` | trung bình | chấp nhận đúng như 14c §1 (Lens Correction bật → ghi); ghi vào test AC-c3 để hành vi là có chủ ý |
| Tài liệu picker không lái được bằng `Tools/ui-drive` | trung bình | cờ launch chỉ-DEBUG nạp sẵn fixture vào `PresetImporter` cho script `looks-import-report.json`; AC-c7 dùng `simctl openurl` |
| Concurrency lượt nhập 500 file | trung bình | đọc/quy đổi trong `Task` rời main actor, `Task.checkCancellation()` giữa file, ghi kho trên main actor một lần; agent `swift-concurrency` |
| **Trường WB tuyệt đối trong kit (E7) va với FS-03.15** — agent khác đang sửa `PhotoAdjustments`/decoder; thêm trường `public` là đổi API kit mà widget/share extension cũng link | trung bình | task 17 commit riêng, chỉ model + decoder + test; báo agent FS-03.15 trước; trường optional + decode khoan dung (`LossyDecoding`), nil = hành vi hôm nay; agent `extension-boundary` |
| **Look thưa (E6) đi qua Copy/Sync**: look nhập áp bằng `EditorSyncScope.look` nhánh thưa, look ShotDex nhánh thay đủ — hai hành vi cùng tên "look" | trung bình | `namedSettings == nil` là look ShotDex (một nhánh mặc định); test cả hai nhánh ở task 15; `challenger` xem ở §8 |
| Thiết bị: sheet báo cáo trên Duo trong (669 pt) và cover 466 pt; menu giữ lâu trên iPad | thấp | `[.medium, .large]`, danh sách cuộn; chụp cả 4 lớp thiết bị |

## 8. Phản biện (điền sau khi chạy `challenger`)

| Phản đối | Trả lời / thay đổi |
|---|---|
| … | … |

Điểm nên đưa cho `challenger`: rename preset có sẵn (§7), 35 commit cho một tính năng, giữ file gốc (D35) có đáng
thêm một thư mục, E6 (look thưa có phá mô hình "look = lát cắt" của FS-03.10 không), E7 (slider WB RAW đổi từ độ lệch
sang Kelvin thật).

## 9. Cách chứng minh là xong

- **Test:** mọi tên ở cột "Test kèm theo" §6 xanh trong `/test`; mỗi AC xong thì sửa cột "Chứng minh bằng" của
  14/14a/14b/14c từ "chưa có" sang tên test thật trong cùng commit.
- **Màn hình phải chụp** (`/screens`, iPhone 17 iOS 26.5 **và** 18.6 — không có nhánh `#available` nhưng chạy cả hai;
  iPad 13" ngang + dọc; Duo trong 951×669 và cover 466×678 qua `Tools/sim-shot`):
  My Looks với ô Import XMP Preset + look nhãn "Imported" (phone shelf và panel rộng) · sheet báo cáo ở `.medium`
  và `.large` có đủ ✓/≈/✕ + dòng lý do mở ra · "Reading 120 of 500" + Cancel · menu giữ lâu trên Golden / Velvia /
  LUT và Export As ▸ ba dòng · alert Rename bị từ chối · sheet xuất `.xmp` (dòng mất mát + hai dòng Adobe) · sheet
  xuất `.cube` · banner cấp app nhận look (Undo, và "N added · M skipped" + Details) trên Library, Statistics và trong
editor · slider WB của RAW hiện Kelvin trước/sau khi áp look nhập · sheet
  extension "Added. Open ShotDex to use it." · VoiceOver đọc dòng báo cáo có chữ trạng thái.
- **Máy thật:** AC-c9 (extension từ Messages), AC-c10 (Instruments bộ nhớ đỉnh), AC-c11 (hai máy, một máy chưa cài).
- **Tài liệu phải cập nhật** (14 §10): FS-03.02 §9 (menu bốn mục, kho JSON) · EX-03 và NF-03 §1, §4 (extension
  "Add to ShotDex" có App Group; "Save to ShotDex" giữ quyền tối thiểu) · dòng điều khoản "chỉ chia sẻ look bạn có
  quyền chia sẻ" · 13d §1 (bỏ Manage Looks; "Export XMP Preset") · BD-02 nếu nêu chỗ lưu dữ liệu người dùng ·
  14b theo kết quả `lightroom-parity` và thử nghiệm RGBTable · FS-03.04 §2 và FS-03.15a (slider WB RAW hiện Kelvin,
trường tuyệt đối — E7) · `DESIGN.md` nếu banner cấp app (E9) cần mô tả vị trí đậu · dòng `Tiến độ` của intent sau mỗi
commit. 14/14b/14c đã sửa theo E6–E9 ngày 2026-09-28.
- **Đóng:** `/verify FS-03.14` rồi `Tools/gate`.

## 10. Agent ở giai đoạn Deploy

| Agent | Vì |
|---|---|
| `extension-boundary` | target mới, không link kit, file dùng chung app + extension, App Group; trường `public` mới trong kit (E7) |
| `privacy-manifest` | `PrivacyInfo.xcprivacy` của extension mới, required-reason nếu dọn hộp thư theo ngày |
| `data-migration` | kho look chuyển từ `UserDefaults` sang file; luật dữ liệu người dùng ngoài `photo_metadata` |
| `memory-leak` | extension < 30 MB, DNG 200 MB chỉ đọc metadata, LUT nhúng 64³ trong `.shotdexlook` |
| `swift-concurrency` | `PresetImporter` huỷ được, ghi kho trên main actor, hộp thư lúc launch/active |
| `copy-consistency` | "Import XMP Preset"/"Export XMP Preset", "Imported", câu lý do ✓/≈/✕, "Adobe" chỉ ở ba chỗ (14 §7) |
| `localization` | chuỗi mới vào `Localizable.xcstrings`, plural "N looks added · M skipped" |
| `a11y-voiceover` | dòng báo cáo có nhãn chữ, "Imported" được đọc, menu giữ lâu có tên |
| `device-layout` | sheet báo cáo và menu trên iPad, Duo trong/cover |
| `ux-reviewer` | Undo lượt nhận trên banner cấp app, Cancel = không thêm gì, không có gì im lặng |
| `test-coverage` | trường WB tuyệt đối trong kit, nhánh look thưa |
| `challenger` | trước khi duyệt (§8) |
| `/release-check` | thêm extension "Add to ShotDex" vào danh sách target |
