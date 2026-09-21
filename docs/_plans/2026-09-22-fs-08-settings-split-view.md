# FS-08 — Settings: split view, search, icons

## Context

Settings hôm nay là **một `List(.insetGrouped)` phẳng trải hết bề ngang ở mọi thiết bị**. Đo trên iPad Pro 13" ngang 1376×1032: hàng **Access** để nhãn ở x≈40pt và giá trị "Full Access" ở x≈1339pt — cách nhau ~1250pt; hàng "Use Cellular Data for Indexing" để ~1025pt trống giữa chữ và công tắc. Đó là layout điện thoại bị phóng to, thứ `DESIGN.md` §10.1c cấm, và là màn duy nhất trong app còn sót lại như vậy (Statistics, lưới ảnh, Collections, editor đều đã có nhánh regular width).

Nguồn: [intent 2026-09-21-ipad-settings-layout](../../Project/shotdex-ios/docs/_intents/2026-09-21-ipad-settings-layout.md) → spec [FS-08](../../Project/shotdex-ios/docs/02-functional-spec/FS-08-settings.md) (21 AC) → `DESIGN.md` §10.1f + §6 (đã sửa).

Kết quả mong muốn: ở regular width, Settings là `NavigationSplitView` giống Settings của iPadOS — sidebar 9 mục có icon và ô Search, detail pane mang nội dung; ở compact **không đổi một dòng nào**.

Quyết định đã chốt (người dùng): ngưỡng là **size class**, không phải số pt (iPadOS split ngay ở iPad 11" dọc 834pt) · sidebar **320pt** · 9 mục · Support vào sidebar · Search ở **cả hai** bố cục, tìm theo **nhãn hàng** · mỗi mục một SF Symbol · thu cửa sổ khi đang ở Photo Library thì **về thẳng danh sách 12 section**, không push · AC-7 chứng minh bằng thread **gieo sẵn**.

---

## Kiến trúc

**Một chủ sở hữu state.** `SettingsScreen` giữ nguyên toàn bộ `@AppStorage`/`@State` và 12 thân section, **trong cùng file**, và tự chọn vật chứa. Lý do: `destructiveAlerts` và 12 section đều `private` (file-scoped); tách section sang file khác buộc ~25 thuộc tính thành `internal`. `settingsSheet` mất `NavigationStack` (nếu giữ sẽ thành `NavigationStack { NavigationSplitView }`).

**Hai enum, không phải một:**
- `SettingsSection` — 9 mục sidebar, thứ tự sidebar, mỗi case có `displayName` + `systemImage` + `groups: [SettingsGroup]`.
- `SettingsGroup` — 12 nhóm nội dung đang có, **thứ tự compact hôm nay**.

Một enum 9 mục sẽ đảo thứ tự compact (Library Size và Privacy nhảy lên sau Photo Library) và làm hỏng AC-4. Hai enum + một ánh xạ toàn phần giữ được "một nguồn cho mỗi bố cục" mà không viết tay danh sách theo thiết bị (NF-05 §37). AC-5 thành một phép so sánh tập hợp thuần.

**Quyết định bố cục là hàm thuần** `SettingsLayout.usesSplitView(horizontalSizeClass:)` — testable (AC-1/AC-2) và là **công tắc tắt**: một `return false` đưa mọi máy về layout hôm nay mà không đụng view nào.

---

## Files

**Tạo mới** (project là file-system synchronized, objectVersion 77 — không cần sửa `project.pbxproj`):

| File | Nội dung |
|---|---|
| `ShotDex/Features/Settings/SettingsLayout.swift` | `usesSplitView(horizontalSizeClass:)`, `selection(afterExpanding:)`, `path(afterCollapsing:)`. Thuần. |
| `ShotDex/Features/Settings/SettingsSection.swift` | `SettingsSection` (9) + `SettingsGroup` (12) + ánh xạ. |
| `ShotDex/Features/Settings/SettingsRowLabel.swift` | Một case cho mỗi hàng tìm được; `text: LocalizedStringResource`, `section`, `availability`. |
| `ShotDex/Features/Settings/SettingsSearchIndex.swift` | Suy ra từ `SettingsRowLabel.allCases` — **không phải danh sách thứ hai**. `results(for:)`, `entries(in:)`. |
| `ShotDex/Features/Settings/SettingsSearchResultsList.swift` | Danh sách kết quả + `ContentUnavailableView.search`. |
| `ShotDex/Features/Settings/SettingsNavigation.swift` | `@Observable`: `selection`, `compactPath`, `query`, `pendingScrollTarget`, `flashedRow`. Đặt tên theo `App/AppNavigation.swift`. |
| `ShotDexTests/SettingsLayoutTests.swift`, `SettingsSearchTests.swift`, `SettingsNavigationTests.swift` | swift-testing. |
| `ShotDexUITests/scripts/*.json` (10 script) + `ShotDexUITests/baselines/phone-settings-before.json` | |

**Sửa:**

| File | Sửa gì |
|---|---|
| `ShotDex/App/Theme/AppTheme.swift` (`enum Size`, sau :53) | `settingsSidebarWidth = 320`, `settingsSidebarWidthMin = 280`, `settingsSidebarWidthMax = 360`; `Motion.searchFlashDuration = 1.2` |
| `ShotDex/App/SettingsSheet.swift:29-35` | bỏ `NavigationStack`; sửa doc comment :20-28 |
| `ShotDex/Features/Settings/SettingsScreen.swift` | phần lớn công việc — xem dưới |
| `DESIGN.md` §6 và §11 | tên hai token anh em của sidebar + `searchFlashDuration` |
| `docs/02-functional-spec/FS-08-settings.md` | cột "chứng minh bằng" của 21 AC |

**Cố ý KHÔNG sửa:** `ShotDex/App/RootTabView.swift` — **không một dòng nào**. Thứ tự modifier quanh `settingsSheet` (:218, :296) là thứ đã từng gây SIGBUS; một commit có `RootTabView.swift` trong `git diff --stat` là sai theo cấu trúc. Cũng không đụng `CameraDatabaseScreen`, `PhotoWidgetDesignsScreen`, `PhotoWidgetSettingsScreen`, `CompressionPresetsScreen`, `SupportScreen` — cả năm đều dựa vào `NavigationStack` của tổ tiên, và thiết kế cho mỗi detail pane một stack riêng nên không cái nào phải đổi. Nếu một trong năm cái đó cần sửa thì thiết kế vật chứa sai.

---

## SettingsScreen: cách 12 section dùng lại cho cả hai bố cục

12 computed property (`photoLibrarySection` :127 … `privacySection` :543) **giữ nguyên từng byte**. Thêm một dispatcher:

```
@ViewBuilder private func group(_ group: SettingsGroup) -> some View {
    switch group { case .photoLibrary: photoLibrarySection; … }   // 12 nhánh, không AnyView
}
```

- compact: `List { ForEach(SettingsGroup.allCases) { group($0) } }`
- detail pane: `List { ForEach(item.groups) { group($0) } }` + `.navigationTitle(item.displayName)`

Không `AnyView`: xoá kiểu sẽ mở lại lỗi row-diff animation đã ghi ở `SettingsScreen.swift:176-191`. Nếu build chậm thì chẻ `group(_:)` làm hai, không erase.

**Ngoại lệ Support**: ở wide, detail của mục Support **là** `SupportScreen` (AC-7 mong đợi danh sách thread ngay đó). Compact giữ nguyên section thứ 12 với `NavigationLink("Support")`.

**Sáu modifier vòng đời gắn trên gốc, ngoài cả hai vật chứa**: `destructiveAlerts`, hai `.task`, hai `.onChange`, `fullScreenCover` của Import. Lý do từng cái:
- `destructiveAlerts` — ba trigger nay nằm ở hai pane khác nhau; gắn theo pane thành ba bản sao và alert chết khi đổi pane.
- `.task(id: isIndexing)` — ba `COUNT(*)` trên 55k dòng; theo pane sẽ chạy lại mỗi lần bấm sidebar **và** để "Continue Indexing (N)" đứng số cũ.
- `.onChange(of: isOnThisDayReminderEnabled)` — handler xin quyền rồi **lật toggle về** khi bị từ chối; theo pane thì đổi pane sẽ huỷ task và lưu một preference không bao giờ bắn được.
- `.onChange(of: onThisDayNotifyMinutes)` — debounce 500ms bị huỷ khi đổi pane.
- Import cover — trình bày từ gốc mới phủ cả cửa sổ; trong một cột của split view nó sẽ bị bó theo cột.

Hai `.task` cấp section (`storageSection` :478, `subjectScanSection` :307) đi theo pane của chúng — trên iPad thành lười hơn. Đó là thay đổi hành vi có chủ ý, ghi vào commit message.

---

## Điều hướng detail

**Mỗi pane một `NavigationStack`, `.id(selection)`**, không dùng path chung: Settings không có `navigationDestination(for:)` nào; path chung sẽ phải dựng bảng định tuyến 5 đích qua 4 file.

`@State columnVisibility: NavigationSplitViewVisibility = .all` (không dùng `.constant(.all)` — mời gọi vòng lặp update), `.navigationSplitViewStyle(.balanced)`.

Hai thứ **bắt buộc** phải có stack thật trong pane:
- `SensorMappingScreen` dùng `dismiss()` để **pop** sau khi Save (`CameraDatabaseScreen.swift:52,113`). Không có stack trong pane thì Save đóng luôn cả màn Settings.
- `PhotoWidgetDesignsScreen` khai `.navigationDestination(item:)` (:68) — không có stack thì Add Design không push gì.

Sidebar: `List(SettingsSection.allCases, selection:)` (cho trait `.isSelected` của AC-14 miễn phí) · `Label` + `Image(systemName:).symbolRenderingMode(.hierarchical)` màu accent, **không** ô bo tròn màu kiểu Settings hệ thống · `.navigationSplitViewColumnWidth(min:ideal:max:)` từ token · **Done chỉ ở toolbar sidebar**, dùng chung một `private var doneToolbarItem: some ToolbarContent`.

Detail **không** tự đặt `frame(maxWidth:)` — `List(.insetGrouped)` trong pane rộng tự chừa lề (đo trên Settings hệ thống: pane 1044pt → nội dung 844pt).

---

## Chuyển compact ↔ regular

`SettingsNavigation` giữ `selection` + `compactPath`; `SettingsScreen` giữ nó bằng `@State` nên sống qua việc đổi vật chứa.

Compact là `NavigationStack(path:)` + `.navigationDestination(for: SettingsSection.self)`; màn được push mang Done riêng.

```
.onChange(of: SettingsLayout.usesSplitView(horizontalSizeClass:)) { _, isSplit in
    if isSplit { selection = .selection(afterExpanding: compactPath); compactPath = [] }
    else       { compactPath = .path(afterCollapsing: selection) }
}
```

`path(afterCollapsing:)` **trả mảng rỗng khi `selection == .photoLibrary`** (quyết định của người dùng): thu cửa sổ khi đang ở Photo Library thì về thẳng danh sách 12 section, không phải bấm Back. Mục khác vẫn push. Luật này nằm trong hàm thuần nên AC-10 chứng minh được không cần Stage Manager.

---

## Search

**Không có danh sách nhãn thứ hai.** `SettingsRowLabel` là enum khai một lần; index **suy ra** từ `allCases`. Nhãn là `LocalizedStringResource` (không phải `String` — sẽ bind nhầm overload `StringProtocol` và mất localization; không phải `LocalizedStringKey` — không đọc ngược ra để chuẩn hoá được). Khoá catalog giữ nguyên byte, nên **diff mong đợi trên `Localizable.xcstrings` là rỗng** — đó là bước kiểm của commit refactor. Đã xác nhận `"ISO"`, `"View Full HDR"`, `"Use Cellular Data for Indexing"`, `"Access"`, `"Support"`, `"Resize Presets"` đều đã có trong catalog (1225 khoá).

**Hàng có điều kiện**: index **tĩnh**, khai mọi hàng có thể xuất hiện, **không bao giờ đọc state runtime** — đó là thứ giữ nó thuần và test được không cần `AppDependencies`. Chống no-op im lặng bằng `Availability` (`.always`, `.whenLimitedAccess`, `.whenPhotoAccessDenied`, `.whenNotificationsDenied`, `.whenIndexingUnfinished`, `.whileIndexing`, `.afterFirstIndex`, `.whenScanned`, `.whenScanIncomplete`): kết quả nào không phải `.always` hiện thêm một dòng `.caption` giải thích *"Shown only when photo access is Limited"*. Hàng hai nhãn ("Find People and Pets" / "Scan Again") là hai entry cùng section, cùng anchor. Loại trừ: header, footer, "Cancel" trong progress row, các dòng số tiến độ — luật loại trừ ghi trong doc comment để bảng vàng của AC-17 kiểm được.

**Đối sánh**: dùng lại `WidgetAlbumCatalog.normalized(_:)` (`WidgetShared/WidgetAlbumCatalog.swift:47-52`) — chính nó đang phục vụ một `.searchable` khác **trong cùng thư mục Settings** (`PhotoWidgetPickers.swift:112-116`). Thêm normalizer thứ tư là đúng thứ `component-consistency` quét. `contains` chứ không `hasPrefix` ("cellular" phải trúng giữa chuỗi). Bảng `(normalized, entry)` resolve một lần vào `static let`.

**UI**: `.searchable` đặt **trong** closure sidebar của `NavigationSplitView` (gắn ngoài thì ô tìm rơi xuống thanh của detail), `placement: .navigationBarDrawer(displayMode: .always)`; ở compact gắn trên `settingsList`. Query khác rỗng thì **thay** nội dung list bằng `SettingsSearchResultsList` (không dùng `.searchSuggestions` — không mang nổi subtitle + dòng availability). Precedent: `PhotoWidgetPickers.swift:74`.

**Cuộn và nháy**: một modifier làm cả ba việc —
```
.settingsRow(_ label:, flashing:) → .id(label)
  + .listRowBackground(flashing ? accent.opacity(0.18) : .clear).animation(AppTheme.Motion.standard, value:)
  + .accessibilityIdentifier(flashing ? "settings.row.\(raw).flashing" : "settings.row.\(raw)")
```
Hậu tố `.flashing` biến "hàng có nháy không" từ chuyện nhìn ảnh thành **một dòng trong dump**. `ScrollViewReader` bọc `List`, theo đúng cách `PhotoWidgetSettingsScreen.swift:291-314` làm. Tiêu thụ target qua `consumeScrollTarget()` (trả một lần rồi nil) trong `.onChange` **và** `.task(id: section)` — vì `.id(item)` dựng lại pane sau khi target được đặt. Nháy tắt bằng `.task(id: flashedRow)` ngủ `searchFlashDuration`.

**Chạm kết quả**: compact → `query = ""`, `pendingScrollTarget = label`, **không push** (spec: compact không đổi). Wide → `selection = entry.section` + target + `query = ""`.

**Không nhớ query**: `SettingsNavigation` tạo trong closure nội dung của `fullScreenCover`, mỗi lần mở là một instance mới — cũng là cách "mặc định Photo Library, không nhớ" thành đúng.

---

## Định danh accessibility cần thêm

App hiện chỉ có 4 (toàn Video Studio, dạng `area.item`, luôn kèm comment nói vì sao nhãn không đủ). Ba nhóm mới đạt cùng chuẩn đó:

| Định danh | Vì sao nhãn không đủ | AC |
|---|---|---|
| `settings.sidebar.<case>` (9 cái) | "Support" vừa là mục sidebar, vừa là tiêu đề detail, vừa là header section thứ 12; predicate của driver là `label ==[c] OR BEGINSWITH[c]` nên không phân biệt được | AC-6, AC-7, AC-9, AC-19 |
| `settings.row.<case>` / `.flashing` | biến cú nháy thành số đo | AC-16, AC-15 |
| `settings.search.results` | phân biệt "hiện empty state" với "list rỗng" | AC-18 |

Không cần định danh mới: AC-3, AC-3b, AC-4, AC-8, AC-12, AC-13.

---

## Thứ tự commit

**Commit 0 phải chạy trước mọi thay đổi code** — baseline không lấy lại được sau đó.

| # | Commit | Nội dung | Chứng minh |
|---|---|---|---|
| 0 | `test(settings): baseline the phone dump` | chạy `phone-settings.json` trên iPhone 17 với code hôm nay; lưu `ShotDexUITests/baselines/phone-settings-before.json` | nửa "trước" của AC-4 |
| 1 | `feat(theme): settings sidebar + search flash tokens` | 4 token vào `AppTheme`; `DESIGN.md` §6/§11 | — |
| 2 | `feat(settings): pure layout decision` | `SettingsLayout.swift` + `SettingsLayoutTests` (doc comment nói rõ công tắc tắt) | AC-1, AC-2 |
| 3 | `feat(settings): one source for the section list` | `SettingsSection` + `SettingsGroup` + `group(_:)`; compact chạy bằng `SettingsGroup.allCases`. Không đổi giao diện. Dump điện thoại phải **trùng baseline** | AC-4, AC-5 |
| 4 | `refactor(settings): one constant per row label` | `SettingsRowLabel`; 12 section đọc hằng. **Kiểm: `git diff Localizable.xcstrings` rỗng** | — |
| 5 | `feat(settings): the search index` | `SettingsSearchIndex` + `SettingsSearchTests` | AC-15, AC-17 |
| 6 | `feat(settings): screen owns its container (compact only)` | `settingsSheet` bỏ stack; `SettingsScreen` gói `NavigationStack`; 6 modifier lên gốc; sửa `#Preview`. **Commit nhạy cảm SIGBUS** — mở/đóng Settings trên cả iOS 26 và pre-26, cả hai call site, cộng Import và ba alert. Cũng là chỗ **kiểm `horizontalSizeClass` trong `fullScreenCover` trên iPad** trước khi xây tiếp | — |
| 7 | `feat(settings): split view at regular width` | `splitLayout`, sidebar có icon, `detailRoot(for:)` + ngoại lệ Support, stack mỗi pane `.id(item)` | AC-3, AC-3b, AC-6, AC-11, AC-12, AC-19 |
| 8 | `feat(settings): scroll to a row and flash it` | `SettingsNavigation`, `.settingsRow(_:flashing:)`, `SettingsNavigationTests` | nửa logic AC-16, AC-10 |
| 9 | `feat(settings): search both layouts` | `.searchable` hai chỗ, `SettingsSearchResultsList`, empty state | AC-15, AC-16, AC-18 |
| 10 | `feat(settings): size-class transition` | `compactPath`, `navigationDestination(for:)`, cầu `onChange`, Done trên màn push | AC-9, AC-10 |
| 11–13 | `test(settings): ui-drive …` | 10 script (split, 11" portrait, search, phone search, empty, support, widget, rotate, duo, a11y) | AC-3…AC-19 |
| 14 | `docs(FS-08): manual proof` | ảnh Slide Over / Stage Manager / VoiceOver vào `docs/02-functional-spec/assets/`; thay mọi ⚠️ bằng đường dẫn | AC-4b, AC-10, AC-14 |

Commit 1–5 an toàn, không phụ thuộc kết quả commit 6.

---

## Rủi ro

| Rủi ro | Xử lý |
|---|---|
| **SIGBUS (a)** — cover gắn sau overlay/`.animation` (`RootTabView.swift:215-217, 294-295`) | Diff không chạm `RootTabView.swift`. **Không** thêm `.animation`/`.transition` quanh nhánh vật chứa — animate một cú đổi vật chứa điều hướng đúng hình dạng của lỗi cũ. Cần thì `.transaction { $0.animation = nil }` |
| **SIGBUS (b)** — view tự đo mình rồi ghi store mỗi frame (lỗi `liveAnchor` cũ) | Bề rộng sidebar đặt bằng `.navigationSplitViewColumnWidth`, **không** `GeometryReader` + `PreferenceKey`. "320±4pt" của AC-3 kiểm từ dump bên ngoài app |
| `horizontalSizeClass` đọc **bên trong** `fullScreenCover` có thể trả `.compact` trên iPad → split không bao giờ hiện | **Kiểm đầu tiên ở commit 6**, trên iPad 11" dọc 834pt, trước khi xây sidebar. Nếu sai thì sửa bằng presentation trait, **không** quay về ngưỡng pt (spec đã bác) |
| `NavigationSplitView` đầu tiên trong app (repo hiện không có cái nào) | Phạm vi chỉ Settings. Chụp iPad 13" ngang, iPad 11" dọc, Duo trong (`Tools/sim-shot`), iPhone, cả hai nhánh iOS |
| `.id(item)` dựng lại `SupportModel` mỗi lần quay về Support, chạy lại `refresh()` | Chấp nhận (nó vốn refresh on appear); soi ảnh xem có nháy spinner |
| Split View 1/2 trên 13" (688pt) cũng vào split, detail còn ~368pt | Đúng điều Settings hệ thống làm. Hàng bị cắt thì hạ `min` xuống 280 trước khi nghĩ tới ngưỡng pt |
| `switch` 12 nhánh làm chậm type-check | Đo bằng `/build` mỗi commit; chẻ `group(_:)` làm hai, không `AnyView` |
| 11 lượt ui-drive × 3–6 phút | ~40–60 phút wall clock; commit 11–13 chạy tuần tự không cần trông |

---

## Kiểm chứng

**Mỗi commit**: `/build` (iPhone 17) + `/test` nếu chạm Domain/Tests.

**Unit test** (swift-testing, `struct … { @Test func behaviourSentence() }`):
- `SettingsLayoutTests` — `.regular` → true; `.compact` và `nil` → false; ánh xạ 9↔12 phủ đúng tập, không nhóm nào hai lần; thứ tự sidebar khớp bảng FS-08.
- `SettingsSearchTests` — "hdr"/"HDR"/" HDR " cho cùng một kết quả `View Full HDR` + subtitle "Playback"; bỏ dấu; "cellular" trúng giữa chuỗi; query rỗng → `[]`; "zzzz" → `[]`; mọi section đều có entry; **bảng vàng số entry mỗi section** (Photo Library 14 · Notifications 4 · Widgets 1 · Display 8 · Playback 2 · Subject Scan 4 · Sharing and Export 2 · Camera Database 2 · Support 1 = 38), mỗi số kèm comment `SettingsScreen.swift:NNN`; mọi hàng có điều kiện đều có `explanation`.
- `SettingsNavigationTests` — chọn kết quả thì đặt selection + target + xoá query; `consumeScrollTarget()` trả một lần; `searchFlashDuration == 1.2`; phiên mới bắt đầu ở Photo Library, query rỗng; selection sống qua một cú lật `usesSplitView`.

**ui-drive** — mọi script iPad/Duo: sau `orientation`, thay `screenshot` bằng `wait 12` rồi host bắn `Tools/sim-shot`; số đo lấy từ **dump** (frame của XCUITest vẫn đúng), ảnh chỉ để nhìn.

| Script | Máy | AC | Điểm mấu chốt |
|---|---|---|---|
| `phone-settings.json` | iPhone 17 | AC-4 | 12 header đúng thứ tự, không có cell sidebar; so với baseline |
| `ipad-settings-split.json` | iPad 13" | AC-3, AC-19, AC-12 | sidebar 320±4; `x("Full Access") − x("Access") ≤ 860`; 9 cell ≥44pt có icon; sau Done không còn `settings.sidebar.*` |
| `ipad11-settings-portrait.json` | iPad 11" (18.6) | AC-3b | vẫn split ở 834pt |
| `ipad-settings-search.json` | iPad 13" | AC-15 | kết quả + subtitle; mở ra ở detail (`origin.x ≥ 320`); "HDR" = "hdr" |
| `phone-settings-search.json` | iPhone 17 | AC-16 | `wait 0.4` → dump có `settings.row.useCellularData.flashing`; `wait 2` → dump chỉ còn `settings.row.useCellularData` |
| `ipad-settings-search-empty.json` | iPad 13" | AC-18 | staticText của `ContentUnavailableView`, 0 cell kết quả |
| `ipad-settings-support.json` | iPad 13" | AC-7 | **gieo sẵn một thread trước khi chạy**; màn push có `origin.x ≥ 320`, 9 cell sidebar còn nguyên, Back về danh sách Support |
| `ipad-settings-widget.json` | iPad 13" | AC-8 | kéo 40pt: frame dòng giờ đổi, frame ảnh nền **y hệt** giữa hai dump |
| `ipad-settings-rotate.json` | iPad 13" | AC-9 | xoay xong vẫn split, vẫn ở Camera Database |
| `duo-settings.json` | Duo (inner) | AC-6 | `settings.sidebar.support` có `y+height ≤ 669 − safe area` |
| `ipad-settings-a11y.json` | iPad 13" | AC-13 | launch với `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityM`; chiều cao từ dump, **chữ có bị cắt hay không phải đọc từ ảnh** — nói rõ như vậy trong báo cáo, vì dump trả nhãn accessibility đầy đủ, không bao giờ thấy "…" |

**Thủ công** (lưu vào `docs/02-functional-spec/assets/`): AC-4b Slide Over (một cột → kéo rộng lại → vẫn đúng mục đang chọn) · AC-10 Stage Manager 1200pt → ~375pt với mục **Display** (không phải Photo Library) → Back về danh sách · AC-14 VoiceOver quay `xcrun simctl io … recordVideo`, đối chiếu 9 tên đọc ra với bảng FS-08, mục đang chọn đọc "selected", Done đọc "Done, button".

**Cuối cùng**: `/verify FS-08` — mọi AC phải trỏ tới một test hoặc một artifact, không còn ⚠️.
