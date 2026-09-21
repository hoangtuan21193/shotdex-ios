# FS-08 — Settings

| Trường | Giá trị |
|---|---|
| Mã tài liệu | `FS-08` |
| Loại | Đặc tả chức năng (機能仕様書) |
| Phạm vi | Màn Settings: hiển thị, index, camera chưa biết, thông báo, quyền riêng tư; **bố cục theo size class** (một cột ở compact, `NavigationSplitView` ở regular) và **tìm kiếm theo hàng**. |
| Nguồn gốc | `spec.md` §7.5 (bản trước khi tách) · [intent 2026-09-21-ipad-settings-layout](../_intents/2026-09-21-ipad-settings-layout.md) |
| Mã nguồn | ShotDex/Features/Settings/ · ShotDex/Features/Support/ · ShotDex/App/SettingsSheet.swift |
| Test | `ShotDexTests/SettingsLayoutTests.swift` (10) · `SettingsSearchTests.swift` (12) · `SettingsNavigationTests.swift` (10) |
| Cập nhật | 2026-09-22 |

> **Ghi chú biên tập.** Nội dung dưới đây tách nguyên văn từ `spec.md`, không viết lại, để không mất chi tiết nào trong lúc chia tài liệu. Tham chiếu `§x.y` đã được đổi thành liên kết tới tài liệu tương ứng.

---

## Nội dung chính

- Photo Library
- Notifications
- Display
- Widgets
- People and Pets
- Sharing
- Export
- Camera Database
- Support
- Privacy
- Playback
- Library Size

(**Appearance** — dãy swatch accent — **đã bỏ**, xác nhận 2026-09-21: không còn ở
`SettingsScreen.swift`, và `AppAccentTheme.swift` không được file `.swift` nào tham chiếu.
Mô tả chi tiết bên dưới giữ lại như **ghi chú lịch sử**, không phải hành vi hiện tại.
⚠️ Cùng drift này còn ở `DESIGN.md`, `BD-04` và `FS-01/06-multi-select` — thuộc phạm vi
`/spec-sync`, không sửa trong lượt này.)

---

Mở bằng nút gear (`gearshape`) top-left của Library/Albums/Statistics. **Từ 2026-09-21 là màn hình đầy đủ** (`fullScreenCover` + `NavigationStack`, title `.inline`, nút **Done** bên phải), không còn bottom sheet `presentationDetents([.medium, .large])`: Settings đã lên mười section cộng bốn trình sửa widget, mà một trình sửa widget là cái preview phải kéo và pinch — một sheet mà cùng ngón tay đó kéo tuột xuống là sai vật chứa.

**`fullScreenCover` phải gắn TRƯỚC `overlay` selection và `.animation(...)` của `RootTabView`** (cả nhánh iOS 26 lẫn legacy). Gắn sau chúng thì SwiftUI **crash SIGBUS** ngay lúc present, trong vòng lặp `HostPreferencesTransform` → `SheetBridge.present`.

- **Photo Library**: permission status, Manage photo access, **Continue Indexing (N)** (chỉ hiện khi `unfinishedCount() > 0`, chạy qua `LibraryModel.continueIndexing()` nên progress/cancel dùng chung UI index), Re-index library, toggle "Use Cellular Data for Indexing" (mặc định tắt; footer giải thích streaming vài trăm KB/item, Wi-Fi luôn được phép), toggle "Keep Screen Awake While Indexing" (mặc định tắt), index progress, last indexed time, và hàng **"Indexed Photos and Videos"** = `completedCount() of rowCount()` (`12,495 of 54,971`, gọn lại còn một số khi đã đọc hết; đang có run thì lấy `indexProgress` cho số sống vì count DB chỉ refresh ở hai đầu run). Hàng này **không được** dùng row count: fast pass ghi placeholder cho mọi asset trong vài giây nên `rowCount()` = cỡ thư viện ngay từ run đầu — hàng "Indexed Photos" cũ hiện đúng số đó nên luôn đọc thành 100% dù mới index 23%.
  - **Continue Indexing key theo `unfinishedCount()`, KHÔNG theo `retryableCount()`**: run bị dừng giữa chừng để phần còn lại ở `pendingRead`, nên count retryable = 0 và Settings chỉ còn mỗi Re-index Library — vứt hàng chục nghìn read đã xong để đọc lại từ đầu đúng lúc user chỉ cần "chạy tiếp" (bug thực tế). `continueIndexing()` refresh count rồi gọi `resumeUnfinishedWork(manual: true)` — cùng đường chọn run rẻ nhất với auto-retry và "Use Cellular": mọi row chưa đọc đều là `pendingICloud`/`error` thì `reindexIncomplete`, còn lại (có `pendingRead`, row version-bump) thì incremental run.
  - **Mỗi nút index là một row riêng, `.disabled(isIndexing)` khi đang chạy** (`indexControls`); row progress (`indexProgressRow`) nằm dưới chúng và mang `.transaction { $0.animation = nil }`. Trước đó nút bị **thay** bằng stack progress: tập row của Section đổi, `List` animate diff nên bấm Re-index thấy cả sheet trượt/nhảy thay vì chỉ dòng vừa bấm phản hồi — và gộp cả khối vào một row thì hai nút dính chung một dòng. Disable thay vì ẩn cũng chính là phản hồi cho cú bấm: run thủ công set `isIndexing` **đồng bộ** nên row xám ngay frame đó, và row disabled không thể bị bấm dồn để start run hai lần
  - **Keep Screen Awake While Indexing**: khi bật, trong lúc index chạy màn hình không tự tắt (`UIApplication.isIdleTimerDisabled`). Sau 1 phút không chạm, **hạ `ActiveDisplay.screen?.brightness` xuống 0** để tiết kiệm pin (không phủ overlay đen — nội dung app vẫn hiển thị, chỉ tối đi); chạm lại khôi phục độ sáng đã lưu và reset bộ đếm. Trước đây dùng overlay đen full-screen + `DimIndexProgressView` (vòng progress lớn, comet arc, network readout) trong một `UIWindow` riêng — **đã bỏ hết**: giờ chỉ chỉnh brightness, không vẽ gì lên màn. **Đánh đổi**: auto-brightness của iOS có thể đẩy giá trị lên lại khi ánh sáng môi trường đổi; chấp nhận để không che UI. Brightness **luôn được khôi phục** khi chạm (wake), khi deactivate, và khi app vào background nên không bao giờ kẹt tối (`restoreBrightness` lưu giá trị trước khi dim). **Bộ đếm reset suốt cả gesture, không chỉ lúc chạm đầu**: `ActivityRecognizer` giữ trạng thái `.possible` và báo activity ở cả `touchesBegan` lẫn `touchesMoved` (chỉ `.failed` khi gesture kết thúc để re-arm) — kéo/giữ/zoom liên tục dài hơn 1 phút không bao giờ bị dim giữa lúc đang thao tác (bug cũ: recognizer `.failed` ngay ở `touchesBegan` nên mất hết `touchesMoved`, chỉ lần chạm đầu được tính). iOS không có API đọc thời gian Auto-Lock của hệ thống nên 1 phút là hằng số cố định (`ScreenAwakeCoordinator.idleDimDelay`), không có setting riêng. Chỉ có hiệu lực khi cả setting bật lẫn đang index; index xong / tắt setting / app vào background thì khôi phục idle timer + độ sáng. **Low Power Mode** (`PowerMonitor` quan sát `NSProcessInfoPowerStateDidChange` + `UIDevice.batteryStateDidChange`, wired ở `AppDependencies`, observe bởi `LibraryModel.handlePowerChange`): vào LPM → **stop** run đang chạy (`cancelIndexing`) và **không** giữ màn sáng/dim cho các run tự động (để màn ngủ theo hệ thống); LPM cũng chặn mọi auto-index (`startIndexing`/`reindexIncompleteAssets` guard `manual || !isLowPowerMode`). User vẫn **start index bằng tay** được trong LPM — run thủ công (`isManualIndexRun`) vẫn giữ màn sáng + dim như thường (gate keep-awake = `keepScreenAwake && isIndexing && (!isLowPowerMode || isManualIndexRun)`). **Cắm sạc trong LPM** → auto-resume index (`resumeIndexingForCharger`, là ngoại lệ auto-start duy nhất trong LPM, chạy không giữ màn sáng). Do `ScreenAwakeCoordinator` (`@MainActor`, app layer) điều khiển; bắt chạm toàn màn hình qua `IdleActivityReporterView` (gesture recognizer gắn lên window, không nuốt touch) reset bộ đếm, gắn tại `RootTabView` cho cả 2 path iOS
- **Notifications**: toggle **"Daily On This Day Reminder"** (mặc định tắt) + `DatePicker(.hourAndMinute)` **"Remind Me At"** (mặc định 09:00, lưu minutes-since-midnight). Xem [§7.3](FS-06-collections/README.md) cho phần schedule.
  - **Quyền chỉ xin khi user bật toggle** (`requestAuthorization(options: [.alert, .sound])`). Bị từ chối — kể cả đã từ chối từ trước trong Settings hệ thống, khi đó request trả về ngay không prompt — thì **toggle bật lại về tắt** thay vì lưu một preference không bao giờ bắn được, và section hiện hàng "Notifications: Denied" + nút "Open Settings" (giống cách section Photo Library xử lý denied). Quyền bị revoke sau đó: iOS tự ngừng giao, và `refresh()` còn clear luôn pending set nên lần re-grant sau không bắn lại một tuần cũ.
  - Picker giờ **debounce 500ms** trước khi reschedule: wheel `.hourAndMinute` publish mỗi detent, mỗi refresh là 7 query + 7 lần `add`, không debounce thì một cú scroll tốn hàng chục lần reschedule.
  - Giữ 2 nguồn default cho giờ notify khớp nhau: `@AppStorage` hiện 540, và scheduler phải tự spell out 540 qua `object(forKey:)` nil-check vì `UserDefaults.integer(forKey:)` trả **0** cho key chưa ghi — đọc thẳng sẽ schedule lúc nửa đêm trên máy mới cài trong khi UI hiện 09:00.
  - Notification bắn lúc app đang mở vẫn hiện banner (`willPresent` → `[.banner, .list, .sound]`): nó là lời mời vào xem một ngày cụ thể, vẫn dùng được giữa session và vẫn tap được.
- **Appearance**: hàng **"Accent Color"** = **dãy swatch hình tròn bấm trực tiếp** (Amber / Sand / Green / iOS Default), KHÔNG phải `Picker` menu — với màu sắc thì bản thân màu là toàn bộ câu trả lời, menu giấu hết chúng sau một tap. Mỗi swatch là `Button` `.borderless` (bắt buộc trong `List`: không có nó cả row thành một button và mọi swatch bắn cùng lúc), circle 32pt / hit 44pt, swatch đang chọn có checkmark trắng (kèm shadow đen để đọc được trên Sand nhạt) + hairline `primary.opacity(0.12)` cho swatch nhạt không mất viền; `LabeledContent` bên trên hiện tên màu đang chọn. Lưu raw value của `AppAccentTheme` ([§3](../01-basic-design/BD-04-design-language.md)); value chưa ghi hoặc không nhận ra (build cũ từng có màu khác) fallback về **`.amber`** (= `AppAccentTheme.default`) qua `AppAccentTheme.resolved`. Đổi màu **áp dụng ngay dưới sheet đang mở** vì root view giữ cùng `@AppStorage` key. Photo Editor cũng đổi theo (`EditorTheme.accent` đọc `AppAccentTheme.stored` từ `UserDefaults` — token static nên không lấy từ environment; editor chỉ dựng sau khi Settings đóng nên không có gì cần refresh), riêng **`EditorTheme.histogramBlue` viết cứng blue** vì kênh blue của histogram RGB phải là blue bất kể accent
- **Display**: chip File Type Badge góc trên-trái thumbnail (mặc định bật) + metadata dưới thumbnail — toggle từng field (ISO, aperture, shutter, focal, megapixels, file size); Focal Length Style (Actual / Equivalent); grid density không phải toggle — chỉ dòng chú thích hướng dẫn pinch trên grid
- **Widgets** (2026-09-21): section **một hàng** — **Photo Widget** → `PhotoWidgetDesignsScreen`, value là tên design khi chỉ có một, "N designs" khi nhiều hơn. On This Day không có cài đặt
  - **`PhotoWidgetDesignsScreen`** là danh sách design: mỗi hàng là tên + một dòng phụ "những gì nó mang — nguồn ảnh"; `Add Design` đẩy thẳng vào màn cài đặt của design vừa tạo (không bắt người dùng đi tìm hàng mới hiện ra); rename/duplicate qua context menu, xoá qua swipe. **Xoá cái cuối cùng bị từ chối**: widget đã đặt phải có gì đó để đọc. `EditButton` để sắp lại thứ tự
  - **Màn hình một cột, preview ghim trên cùng** (2026-09-21): `PhotoWidgetSettingsScreen` không còn là `List` có preview trong Section — nó là `VStack { previewHeader; Divider; List }`. Preview là thứ mọi hàng bên dưới đang sửa, **và là bề mặt để kéo/pinch**, nên nó không được cuộn ra khỏi ngón tay
  - **Mỗi thành phần đặt riêng (2026-09-21)**: `PhotoWidgetComponent` (time / date / weather / calendar) và `PhotoWidgetSettings.componentAnchors` — chạm một dòng trên preview để **chọn** (viền nét đứt + 4 chấm góc, hint đổi theo), kéo dòng đó đi **một mình**, pinch để đổi cỡ chính dòng đó. Thành phần **cùng vị trí thì vẫn xếp chồng thành một khối** (`PhotoWidgetLayout.groups`), nên widget chưa ai sắp xếp trông y như cũ; kéo một cái ra thì những cái còn lại được **ghim tại chỗ** chứ không trôi theo
  - **Chạm trúng từng dòng, không phải cả khối** (sửa 2026-09-21 sau phản hồi "chọn khó"): hit-test cũ chạy trên *nhóm* và trả dòng đầu, nên chạm vào ngày lại chọn đồng hồ và không cách nào với tới dòng dưới. Nay mỗi dòng tự báo frame qua `PhotoWidgetComponentFrames` (PreferenceKey, đo trong coordinate space `photoWidgetFace`) và `PhotoWidgetHitTest` (thuần, có test) chọn: trong vùng thì lấy dòng **nhỏ hơn** khi chồng nhau, ngoài vùng thì lấy dòng gần nhất trong **10pt**, xa hơn thì bỏ chọn
  - **Chọn không cần nhắm**: hàng **chip tên thành phần** ngay dưới thanh chuyển cỡ (**Photo** · Time · Date · Weather · Calendar) — nhắm vào một dòng chữ trên preview 158pt là cách chọn tệ, chip chọn đúng thứ đó mà không phải nhắm, và cũng là danh sách widget gồm những gì. Chip **Photo** chính là "không chọn dòng nào" đặt tên ra: luật "không chọn gì thì kéo/pinch ăn vào ảnh" đúng nhưng vô hình, và đó cũng là đường quay về ảnh mà không phải mò khe hở giữa hai dòng chữ. Capsule cao 32pt nhưng **nút cao 44pt** (`AppTheme.Size.minTouch`, đo bằng dump thấy 32 nên sửa); quá năm chip hoặc cỡ chữ lớn thì hàng chip **cuộn ngang** (`ViewThatFits`) chứ không bị cắt
  - **Chọn một dòng thì cuộn thẳng tới Arrangement** (2026-09-21, tham khảo Widgy): Arrangement là section **thứ bảy**, nên chọn khối thời tiết trên preview 158pt xong thì `nudgePad` và thanh cỡ của chính nó nằm dưới năm section không liên quan, không có gì báo là chúng tồn tại. Nay `optionsList` bọc trong `ScrollViewReader`, `arrangementSection` mang `.id("arrangement")`, và `onChange(of: selectedComponent)` cuộn tới — **chỉ khi đi từ `nil` sang có chọn**; bỏ chọn (chạm vào ảnh) thì không giật list đi đâu cả. Widgy gọi đúng việc này là "Quick Assignment: Assign directly from Preview"; panel History của editor trong app đã làm cùng kiểu
  - **"Stack Everything Together" và "Reset Photo Framing" là `role: .destructive`** (2026-09-21): hai nút này xoá sạch mọi vị trí/cỡ đã kéo tay (`resetComponentAnchors`) hoặc mọi pha/zoom ảnh (`photoScale`/`photoOffset*` về 0), mà trước đó vẫn màu xanh như nút thường — trong khi `Remove Photo` ngay cùng màn đã là đỏ. **Không thêm `confirmationDialog`**: kéo lại được trong vài giây, mức mất mát thấp hơn hẳn `Remove Photo` (mất nguồn ảnh, phải mở lại picker) mà chính nó cũng chỉ dùng `role` chứ không hỏi lại
  - **Bàn phím mũi tên + thanh cỡ cho dòng đang chọn**: 4 mũi tên bước 5% khoảng trống cộng nút về giữa (`nudgePad`), và `componentScales` — **mọi dòng đều đổi cỡ được** (trước đó hai slider chỉ với tới giờ và dòng phụ, khối thời tiết và lịch không có cỡ riêng). Về đúng 100% thì **xoá khỏi file** thay vì lưu 1.0
  - **Swatch "Smart" — màu chữ đo theo ảnh, từng dòng một** (2026-09-21, tham khảo "Smart Color" của Widgy): `WidgetTextColor.smartHex = "smart"` lưu thay cho hex, vì màu chưa quyết được cho tới khi đo xong ảnh dưới chữ. `PhotoWidgetLumaGrid` (`WidgetShared/PhotoWidgetLuma.swift`, thuần, có test) vẽ ảnh **một lần** xuống context 16×16 rồi lấy luma Rec.709 từng ô — đúng kỹ thuật `CoverTitleScrim` dùng cho cover album, nhưng là **lưới** thay vì một pixel, vì widget đặt chữ ở đâu là do người dùng kéo, dải đáy cố định không còn trả lời được. `PhotoWidgetImageLayer.normalizedImageRect(for:in:aspectRatio:scale:offsetX:offsetY:)` là **phép nghịch** của cái layer vẽ ra (fill → `scaleEffect` → offset theo slack), nên biết ô chữ đang nằm lên phần nào của ảnh thật. Mỗi **khối** hỏi riêng (`PhotoWidgetArrangedFace.smartColor(forRect:)`) — đồng hồ kéo lên trời sáng và ngày để trên vách đá tối cần hai câu trả lời ngược nhau, một màu cho cả hai chính là chỗ swatch cố định thua. Ngưỡng `smartCrossover = 0.62`, **không** phải điểm hoà 0.18 của tương phản thuần: chữ luôn có shadow hoặc scrim nên trắng đi xa hơn nhiều. `photoDimming` nhân vào luma (ảnh dim 60% là nền tối dù pixel gốc sáng). Không có ảnh thì Smart = trắng
  - **Hàng swatch: 9 ô, lưới 3 cột, đĩa Smart chẻ chéo trắng/đen** (gradient hai chặng cứng — không phải blend, vì swatch đại diện một *lựa chọn giữa hai màu*, dải xám ở giữa đọc thành màu thứ ba). Nút swatch từng đo được **38pt** dù đã `.frame(minHeight: 44)`: frame đặt *ngoài* `Button`, mà `.buttonStyle(.plain)` chỉ nhận chạm ở chỗ label vẽ — frame + `contentShape` phải nằm **trong** label. 4 cột thì Purple đứng lẻ một hàng, nên 3 cột × 3 hàng
  - **Lưới luma chỉ dựng khi người dùng chọn Smart** (`measuresLuma` truyền vào `Payload.image`, cache key kèm cờ đó): widget extension trả giá cho mọi lượt nó không cần, mà swatch cố định thì không bao giờ hỏi câu này
  - **Đường gióng khi kéo** (`PhotoWidgetSnapping`, thuần, có test): hút vào **giữa**, vào **mép**, và vào **thẳng hàng với thành phần khác**; ngưỡng 6% khoảng trống. Giữa và thẳng hàng thì vẽ đường vàng, mép thì không (biên widget đã tự thấy)
  - **`PhotoWidgetArrangedFace` là bố cục dùng chung** cho widget và preview: cùng một phép tính origin từ anchor + kích thước đo được, nên một dòng không thể nằm hai chỗ khác nhau giữa hai bên
  - **Ảnh nền bám tay kể cả ở 1×**: `PhotoWidgetImageLayer.slack(in:aspectRatio:scale:)` tính phần thừa **theo tỉ lệ ảnh thật**, không chỉ theo zoom — ảnh 3:2 trong ô vuông đã bị cắt ~39pt mỗi bên trước khi zoom, và đó chính là phần hai ngón tay kéo ra xem được. Trước đây pan ở 1× không làm gì cả
  - **Một ngón, một việc — quyết ngay lúc chạm xuống** (sửa 2026-09-21 sau phản hồi "vẫn loạn quá"): trước đó `PhotoWidgetPreview` gắn **hai** `DragGesture` song song (một cho chữ, một "hai ngón" cho ảnh) — nhưng `DragGesture.simultaneously(with: MagnifyGesture)` nhận **một ngón** cũng đủ, nên mỗi cú kéo vừa dời dòng chữ vừa trượt ảnh nền dưới nó cùng lúc (đo được bằng `Tools/ui-drive`: một swipe làm khung ảnh dịch 101pt). Nay **một** `DragGesture` duy nhất, hit-test lúc ngón chạm xuống: trúng một dòng thì **chọn và kéo dòng đó**, trúng nền thì **bỏ chọn và kéo ảnh**. Pinch vẫn theo cùng luật đó (có dòng đang chọn thì đổi cỡ dòng, không thì phóng ảnh tới `maximumPhotoScale = 3`), và **trong lúc pinch thì drag của dòng chữ tạm ngưng** (`isPinching`) — tâm hai ngón luôn trôi, một dòng vừa đổi cỡ vừa trượt đi là đúng cái "hai việc một lúc" vừa bỏ; ảnh nền thì **giữ cả hai**, vì phóng ảnh và chọn phần ảnh còn lại vốn là một động tác. Anchor là phân số 0…1 của phần không gian trống — thay hẳn 5 vị trí góc cũ — và **widget vẽ đúng cùng công thức** qua `Anchor.offset(in:contentSize:inset:)` + `PhotoWidgetImageLayer`, cả hai nằm trong `WidgetShared`
  - **Cử chỉ giữ state cục bộ, chỉ commit khi nhả tay**: ghi vào store mỗi frame đẩy một thay đổi observable trở lại chính view đang tự đo mình, và SwiftUI **crash SIGBUS trong vòng lặp preference** (`HostPreferencesTransform`). `liveAnchor`/`livePhotoScale`/`livePhotoOffset` vẽ trong lúc kéo, `onEnded` mới gọi store
  - **Chuyển cỡ preview** (`PhotoWidgetPreviewFamily`: Small 158×158, Medium 329×158, Large 329×345) bằng segmented ngay dưới preview, đúng point size iOS dùng trên máy 6.1"
  - **Chọn nguồn ảnh**: Photo mở `PHPickerViewController` (lưới ảnh thật, đọc thư viện ngoài tiến trình app); Album mở **lưới cover dùng chung `AlbumCoverTile` của tab Collections** (2026-09-21) thay cho danh sách chữ — cùng câu hỏi "cái nào đây" thì cùng câu trả lời, tên nằm **trên** ảnh, scrim đo theo độ sáng dải dưới (`CoverTitleScrim`), kèm `.searchable` khớp **bỏ dấu và bỏ hoa/thường** đúng như picker ngoài Home Screen
  - Các section bên dưới: Background, Time and Date, Calendar, Weather, Typeface, Colour, **Arrangement** (đọc vị trí chữ ra chữ, "Centre the Text", mức zoom, "Reset Photo Framing"). Calendar và Weather **không còn bị chặn theo kind** — mỗi cái mở đầu bằng một toggle (`Show Calendar` / `Show Weather`) và phần còn lại hiện theo toggle đó
  - Một design mới bật sẵn **giờ + ngày**, tắt thời tiết và lịch — đúng cái người ta đặt nhiều nhất, và hai cái kia cách một toggle
  - **`anchor` thay `placement`**: file cũ còn khoá `placement` (5 góc) và **chỉ được đọc, không bao giờ ghi lại** (`PhotoWidgetSettings.anchor(forLegacyPlacement:)` + `encode(to:)` tự viết) — người dùng từng đặt chữ ở góc nào thì lần kéo đầu bắt đầu từ đó
  - Lưu bằng `PhotoWidgetSettingsStore` (`@Observable`, trong `AppDependencies`) ghi **JSON trong App Group**, debounce 400ms, `saveNow()` khi rời màn; đổi nguồn ảnh thì re-render và reload đúng kind
- **Export**: NavigationLink **Compression Presets**; luôn hiện bốn preset built-in và cho tạo/sửa/xoá custom preset `{name, Fill/Fit, width, height, quality, JPEG/HEIC}`. Custom preset lưu JSON local trong `UserDefaults`, không sync.
- **Camera Database**: Unknown Cameras (danh sách camera chưa resolve, mở mapping thủ công tại đây), Reset Custom Mappings
- **Privacy**: giải thích local processing, Clear local metadata index

(Section "Statistics" với toggle "Focal Lengths as FF Equivalent" đã bỏ — focal actual vs FF equivalent nay là lựa chọn dimension per-chart trong dashboard, xem [§7.4](FS-07-statistics.md).)
- Lưu bằng `UserDefaults` (`@AppStorage`); key mới `index.keepScreenAwake` (registry `SettingsKeys.keepScreenAwake`), `notifications.onThisDay` + `notifications.onThisDayMinutes` (`SettingsKeys.onThisDayNotificationsEnabled` / `.onThisDayNotifyMinutes`), `export.compressionPresets` (`SettingsKeys.compressionPresets`), `display.accentTheme` (`SettingsKeys.accentTheme`)

**Playback** (2026-09-19): toggle **View Full HDR** (`SettingsKeys.viewFullHDR`, **mặc định tắt**) đặt `UIImageView.preferredImageDynamicRange = .high` cho ảnh trong viewer. Tắt sẵn có lý do: một khung HDR đứng cạnh chrome tiêu chuẩn làm chrome trông xám, và trên vài màn hình thì chói. Và toggle **Autoplay Videos** (`SettingsKeys.autoplayVideos`, mặc định bật). Tắt thì video chờ bấm play; **tạm dừng khi rời trang thì không phải tuỳ chọn** — trang đã trôi đi luôn phải dừng. Loop vẫn là nút trên chính player, không đưa vào Settings.

**Library Size** (2026-09-19): `LibraryQueries.storageTotals()` cộng `fileSize` của bảng `photo_metadata`. `knownCount < totalCount` (pass nhanh ghi row trước khi pass EXIF điền bytes) thì in kèm `~` vì con số mới là sàn.

---

## Bố cục theo bề rộng cửa sổ (2026-09-21)

Nguồn: [intent 2026-09-21-ipad-settings-layout](../_intents/2026-09-21-ipad-settings-layout.md).
Hôm nay Settings là **một `List` phẳng trải hết bề ngang ở mọi thiết bị**: đo trên
`iPad Pro 13-inch (M5)` ngang 1376×1032pt, hàng **Access** để nhãn ở x≈40pt và giá trị
"Full Access" ở x≈1339pt — cách nhau ~1250pt; hàng **Use Cellular Data for Indexing** để
~1025pt trống giữa chữ và công tắc; footer chạy một dòng ~1310pt. Đó là layout điện thoại
bị phóng to, đúng thứ [`DESIGN.md` §10.1c](../../DESIGN.md) cấm.

### Hai bố cục, một nguồn nội dung

Chuẩn để bắt chước là **Settings của iPadOS**, theo quyết định của người dùng
(2026-09-21). Số đo lấy từ chính nó, không phải đoán — chụp `com.apple.Preferences` trên
hai máy ảo:

- `iPad Pro 11-inch (M4)` / iOS 18.6, **dọc 834×1210**
  ([ảnh](assets/2026-09-21-ipados-settings-11in-portrait.png)): đã là split view, sidebar
  rộng **320pt**, detail chiếm phần còn lại. Tức iPadOS **không** đợi tới 900pt — 834pt
  dọc vẫn hai cột.
- `iPad Pro 13-inch (M5)` / iOS 26.5, **ngang 1376×1032**
  ([ảnh](assets/2026-09-21-ipados-settings-13in-landscape.png)): sidebar **~320pt** (trên
  26 là tấm kính nổi, thụt vào khỏi mép), detail pane 1044pt nhưng **nội dung chỉ rộng
  844pt** — `List(.insetGrouped)` tự chừa ~98pt mỗi bên khi pane rộng, không cần hằng số
  riêng.

| | Compact layout | Wide layout |
|---|---|---|
| Điều kiện | `horizontalSizeClass == .compact` | `horizontalSizeClass == .regular` |
| Vật chứa | `NavigationStack` → `List(.insetGrouped)` (như hôm nay, §10.1) | `NavigationSplitView` — sidebar danh sách nhóm + detail |
| Màn con | push chồng trong stack | mở **trong detail pane** |
| Thiết bị rơi vào | mọi iPhone (402×874), Duo ngoài (466×678), iPad Slide Over | iPad 11" dọc (834×1210) và ngang, iPad 13" dọc (1032) và ngang (1376), iPad Split View 1/2, **Duo trong (951×669)** |

**Ngưỡng là size class, không phải một con số pt** — đây là chỗ spec đi khác intent
(intent chốt 900pt) sau khi đo Settings của iPadOS: 900pt sẽ để iPad 11" dọc ở lại layout
điện thoại trong khi máy bên cạnh nó, cùng bề rộng đó, đang chạy hai cột. Đổi lại, iPad
Split View 1/2 trên 13" (688pt, vẫn regular) cũng vào split và detail chỉ còn ~368pt —
chấp nhận, vì đó đúng là điều Settings hệ thống làm ở cùng bề rộng.

Hàm quyết định vẫn là một hàm **thuần, có test**
(`SettingsLayout.usesSplitView(horizontalSizeClass:)`), không phải một `if` nằm trong
`body` — để AC-1/AC-2 chứng minh được mà không cần dựng bốn máy ảo.

**Danh sách nhóm chỉ có một nguồn**: `SettingsSection: CaseIterable`. Cả hai bố cục dựng
từ `allCases` — luật [NF-05 §37](../04-non-functional-design/NF-05-device-and-os-compatibility.md)
"điện thoại có đủ mọi chức năng của iPad", và lý do đúng ra là đã có: danh sách viết tay
theo thiết bị là cách cả hàng Color lẫn transport row từng biến mất.

### Sidebar gồm những gì

Chín mục, theo đúng thứ tự đọc của bố cục compact hiện tại, gộp lại cho vừa một màn
669pt (Duo trong) mà không phải cuộn:

| # | Mục sidebar | Ký hiệu | Gom section nào của bố cục compact |
|---|---|---|---|
| 1 | Photo Library | `photo.stack` | Photo Library (quyền, index, các công tắc index) + Library Size + Privacy |
| 2 | Notifications | `bell` | Notifications |
| 3 | Widgets | `square.grid.2x2` | Widgets → `PhotoWidgetDesignsScreen` |
| 4 | Display | `text.below.photo` | Thumbnail Metadata |
| 5 | Playback | `play.rectangle` | Playback |
| 6 | People and Pets | `person.2` | Subject Scan (header trên màn đã là "People and Pets", nên sidebar dùng đúng chữ đó) |
| 7 | Sharing and Export | `square.and.arrow.up` | Sharing + Export (Compression Presets) |
| 8 | Camera Database | `camera` | Camera Database |
| 9 | Support | `questionmark.circle` | `SupportScreen` — **mới vào sidebar**, trước là `NavigationLink` cuối danh sách |

Ký hiệu chỉ xuất hiện ở **sidebar**; bố cục compact vẫn là section có header chữ, không có
hàng điểm-đến để đeo icon. Mọi ký hiệu trên đều có từ iOS 15 nên không cần nhánh
`#available`; `.symbolRenderingMode(.hierarchical)`, màu accent, không dùng nền bo tròn
kiểu Settings hệ thống (ShotDex không có bộ icon màu riêng cho từng mục và một dãy chín ô
xám sẽ ồn hơn là giúp).

**Library Size** và **Privacy** không phải mục riêng: Library Size là hai hàng số đọc
xong là thôi nên nằm cuối **Photo Library**; Privacy là đoạn giải thích cộng nút phá huỷ
"Clear local metadata index" nên nằm cuối **Photo Library** luôn, đúng luật §10.1 "hành
động phá huỷ ở section cuối".

Chín mục này **đã chốt** (người dùng, 2026-09-21) — không phải 12 mục 1-1 với section hiện
có, cũng không gộp mạnh còn sáu.

**Bề rộng sidebar = 320pt**, đo từ Settings của iPadOS ở cả 834pt dọc lẫn 1376pt ngang.
**Số đo sau khi làm** (2026-09-22): iPad 11" dọc / iOS 18.6 ra đúng **320pt**; iPad 13"
ngang / iOS 26.5 ra **350pt** vì sidebar ở 26 là tấm kính nổi thụt vào khỏi mép (hàng
sidebar `x=26 w=288`, detail bắt đầu ở `x=350`). Không ép lại: đó là hình dạng của nền
tảng ở phiên bản đó, và `.navigationSplitViewColumnWidth` đã nhận đúng con số.
Đặt tên trong `AppTheme.Size` (`settingsSidebarWidth = 320`, dùng qua
`.navigationSplitViewColumnWidth(min:ideal:max:)` 280/320/360) chứ không gõ số trong file
feature — [`DESIGN.md` §6](../../DESIGN.md) cấm hằng số rời. Ở bề rộng nhỏ nhất còn vào
split (Split View 1/2 trên 13", 688pt) thì detail còn 368pt, vẫn trên sàn 320pt.

**Nội dung trong detail phải tự giới hạn** — sửa lại sau khi đo (2026-09-22). Giả định cũ
là `List(.insetGrouped)` tự chừa lề trong pane rộng; nó **không**: đo trên iPad 13" ngang,
hàng detail rộng **1006pt** và "Access" đứng cách "Full Access" khoảng 900pt, tức vẫn là
màn điện thoại kéo giãn. Nay hàng bị giữ ở
`AppTheme.Size.settingsDetailContentMaxWidth` = **840** và canh giữa, nền xám nhóm trả về
cho cả pane (`scrollContentBackground(.hidden)` + `background`), đo lại còn **800pt**.

`DESIGN.md` **đã được sửa trong cùng lượt này** (người dùng duyệt 2026-09-21): thêm
**§10.1f — màn cài đặt ở regular width dùng `NavigationSplitView`** và thêm
`settingsSidebarWidth` vào bảng §6. (Mã `§10.1d` và `§10.1e` đã có chủ — cover và hero
của Collections — nên mục mới là `§10.1f`.)

### Tìm kiếm trong Settings

Có **ở cả hai bố cục** — `.searchable` trên sidebar ở wide, trên `List` ở compact. Luật
"điện thoại có đủ mọi chức năng của iPad"
([NF-05 §37](../04-non-functional-design/NF-05-device-and-os-compatibility.md)) không cho
phép Search chỉ có trên iPad.

- **Tìm theo hàng, không theo mục.** Chín cái tên mục thì lọc chín cái tên là vô dụng:
  người ta gõ "ISO", "cellular", "HDR" — tên của **một hàng** nằm sâu bên trong. Nguồn
  đối sánh là `SettingsSearchIndex`: mỗi mục khai báo nhãn của các hàng nó chứa, khai
  ngay cạnh `SettingsSection` để không có hàng nào bị bỏ quên.
- **Đối sánh bỏ dấu và bỏ hoa/thường**, cùng cách picker album đã làm
  (`.searchable` + so khớp đã chuẩn hoá) — "hdr" khớp "View Full HDR".
- **Kết quả là danh sách hàng**, mỗi dòng: nhãn hàng + tên mục chứa nó ở dòng phụ. Chạm
  một kết quả thì mở mục đó và **cuộn tới hàng** (`ScrollViewReader`, cùng kỹ thuật
  `arrangementSection` đã dùng ở `PhotoWidgetSettingsScreen`), rồi **nháy nền hàng đó
  1,2 giây** để mắt bắt được nó trong một màn dài.
- **Không tìm được thì hiện `ContentUnavailableView.search(text:)`**, không phải một danh
  sách rỗng.
- Search **không nhớ** truy vấn giữa hai lần mở Settings.

> **Giá phải trả, ghi rõ:** `SettingsSearchIndex` là bản sao thứ hai của các nhãn hàng —
> đổi chữ ở một hàng mà quên sửa index thì tìm không ra. Giảm rủi ro bằng cách để index
> và hàng **dùng chung hằng chuỗi** (`String(localized:)` một chỗ, hai nơi đọc), và AC-17
> đối chiếu số lượng.

### Hành vi

- **Mục mặc định khi mở**: Photo Library. **Không nhớ** mục đã chọn giữa hai lần mở
  Settings — không thêm key `UserDefaults` cho một trạng thái điều hướng.
- **Done** nằm ở toolbar **sidebar** (`.confirmationAction`), đóng toàn bộ Settings từ bất
  kỳ mục nào — `fullScreenCover` không có swipe để đóng nên Done là lối ra duy nhất, y như
  hôm nay.
- **Lối vào không đổi**: vẫn `fullScreenCover` gắn ở `RootTabView` **trước** `overlay`
  selection và `.animation(...)` của cả hai nhánh iOS ([RootTabView.swift:215](../../ShotDex/App/RootTabView.swift#L215),
  [:295](../../ShotDex/App/RootTabView.swift#L295)) — gắn sau là SIGBUS trong
  `HostPreferencesTransform`, đã ghi ở phần trên của tài liệu này. `NavigationSplitView`
  thay `NavigationStack` **bên trong** cover, không đụng thứ tự modifier bên ngoài.
- **Màn con có stack riêng**: Support có `SupportThreadScreen`/`SupportComposeScreen` push
  tiếp, Camera Database có màn mapping. Mỗi detail pane là một `NavigationStack` riêng, và
  **Back trong detail quay về màn trước của chính mục đó**, không nhảy về sidebar.
- **`PhotoWidgetSettingsScreen` lấy trọn detail pane** và giữ nguyên cấu trúc
  `VStack { previewHeader; Divider; List }` cùng toàn bộ luật cử chỉ "một ngón, một việc"
  đã chốt ở phần trên — bố cục mới không được đưa nó vào một vật chứa kéo-để-đóng.
- **Đổi bề rộng lúc đang mở** (xoay máy, Stage Manager, gập/mở Duo): bố cục đổi theo ngay,
  **mục đang xem được giữ** — rơi về compact thì mục đó là màn đang push trên stack, lên
  wide thì nó là mục đang chọn ở sidebar.
- **Bố cục compact không đổi một dòng nào** so với hôm nay: cùng thứ tự section, cùng
  `List(.insetGrouped)`, cùng mọi hàng.

**Appearance đã bỏ** (người dùng xác nhận 2026-09-21): dãy swatch accent không còn trong
code và không dựng lại — phần mô tả "Appearance" ở mục "Nội dung chính" phía trên là drift
của tài liệu, gỡ trong cùng lượt sửa này. Sidebar chỉ có **Display**.

**Ngoài phạm vi bản này** (cố ý): không đổi thứ tự hay tên section; không đổi nội dung
hàng nào; không đụng `ImportScreen` — việc bỏ Import là
[intent riêng](../_intents/2026-09-21-remove-import-entry-point.md); không đụng bố cục các
màn khác.

---

## Tiêu chí nghiệm thu

> Phạm vi bảng này là **bố cục theo bề rộng** (mục ngay trên). Các mục còn lại của FS-08
> (index, notifications, widget, playback…) vẫn **chưa có tiêu chí nghiệm thu** — xem
> [README — Lộ trình](../README.md#7-lộ-trình-hoàn-thiện).

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | `horizontalSizeClass == .regular` | gọi `SettingsLayout.usesSplitView(horizontalSizeClass:)` | trả `true` | ✅ `SettingsLayoutTests.regularWidthUsesSplitView` |
| AC-2 | `horizontalSizeClass == .compact`, và `nil` (chưa xác định) | gọi `SettingsLayout.usesSplitView(horizontalSizeClass:)` | trả `false` cho cả hai — `nil` rơi về bố cục một cột, không đoán | ✅ `SettingsLayoutTests.compactAndUnknownUseList` |
| AC-3 | iPad 13" ngang 1376×1032, Settings đóng | chạm nút gear ở Library | có sidebar bên trái và detail "Photo Library" bên phải; **hàng trong detail rộng ≤ 860pt** (trước: 1006pt, với "Access" cách "Full Access" ~900pt) | ✅ `ShotDexUITests/scripts/ipad-settings-split.json` — đo được: hàng sidebar `x=26 w=288`, detail bắt đầu `x=350`, hàng detail `x=453 w=800`; [ảnh](assets/2026-09-22-settings-split-ipad13-landscape.png) |
| AC-3b | iPad 11" **dọc** 834×1210 (iOS 18.6, nhánh pre-26) | mở Settings | vẫn là split view, **không** rơi về một cột — cùng hành vi với Settings của iPadOS ở đúng bề rộng đó | ✅ [ảnh](assets/2026-09-22-settings-split-ipad11-portrait.png) — sidebar đo được **320pt**, đủ 9 mục, detail là Photo Library |
| AC-4 | iPhone 402×874 | mở Settings | vẫn đúng **12 section** theo thứ tự Photo Library → Privacy, không có sidebar | ⚠️ một nửa: thứ tự được khoá bằng `SettingsLayoutTests.compactOrderIsUnchangedFromBeforeTheSplitView`, và [ảnh iPhone 16 Pro](assets/2026-09-22-settings-compact-iphone16.png) cho thấy bố cục một cột. **Không có dump "trước khi sửa"** — lượt chụp baseline chết giữa chừng ba lần (xem Rủi ro) |
| AC-4b | iPad 13", Settings mở ở Slide Over (compact width) | chụp màn | bố cục một cột, không sidebar — cùng hành vi với Settings của iPadOS ở Slide Over | ⚠️ chưa có — `Tools/ui-drive` không dựng được Slide Over; chứng minh bằng AC-2 cộng một ảnh chụp tay |
| AC-5 | `SettingsSection.allCases` | dựng danh sách mục cho cả hai bố cục | hai danh sách chứa **cùng một tập** `SettingsSection`, không mục nào chỉ có ở một bên | ✅ `SettingsLayoutTests.bothLayoutsCoverEverySection` |
| AC-6 | Duo **màn trong** 951×669, Settings mở ở mục Photo Library | chụp màn | sidebar hiện **cả 9 mục không phải cuộn** (mục cuối "Support" có `maxY` ≤ 669 − safe area đáy) | `Tools/sim-shot` trên Duo + dump từ `ShotDexUITests/scripts/duo-settings.json` ⚠️ chưa có |
| AC-7 | iPad 13" ngang, Settings mở | chọn "Support" ở sidebar rồi mở một thread | thread hiện **trong detail pane** (origin.x ≥ bề rộng sidebar), sidebar vẫn thấy cả 9 mục; bấm Back về danh sách Support, **không** về Photo Library | `ShotDexUITests/scripts/ipad-settings-support.json` + dump ⚠️ chưa có |
| AC-8 | iPad 13" ngang, mục Widgets → một design | kéo dòng giờ trên preview đi 40pt | anchor của **đúng dòng đó** đổi, ảnh nền dịch **0pt**, và preview vẫn nằm trong detail pane (không bị cuộn ra khỏi khung) | `ShotDexUITests/scripts/ipad-settings-widget.json` + dump ⚠️ chưa có |
| AC-9 | iPad 13" **dọc** 1032×1376, đang ở mục Camera Database | xoay sang ngang 1376×1032 | vẫn bố cục split và **vẫn đang ở Camera Database** | `ShotDexUITests/scripts/ipad-settings-rotate.json` (`orientation` + `Tools/sim-shot`, không dùng `screenshot` của driver) ⚠️ chưa có |
| AC-10 | iPad 13", cửa sổ Stage Manager rộng ~1200pt (regular), đang ở mục Display | thu cửa sổ xuống cỡ Slide Over (compact) | rơi về một cột và **Display là màn đang hiện** (push trên stack), Back đưa về danh sách 12 section | ⚠️ chưa có — `Tools/ui-drive` không đổi được cỡ cửa sổ Stage Manager; cần chứng minh bằng test trên hàm thuần + một ảnh chụp tay |
| AC-11 | Quyền ảnh `.limited`, iPad 13" ngang | mở Settings | detail "Photo Library" hiện hàng Access = "Limited Access" kèm nút "Manage" trong pane, không hàng nào bị đẩy ra ngoài bề rộng detail | `ShotDexUITests/scripts/ipad-settings-limited.json` + ảnh ⚠️ chưa có |
| AC-12 | iPad 13" ngang, Settings mở ở mục bất kỳ | bấm **Done** ở toolbar sidebar | toàn bộ Settings đóng, quay về tab đang mở trước đó | ✅ `ShotDexUITests/scripts/ipad-settings-split.json` — dump sau Done còn 8 cell và không còn `settings.sidebar.*` |
| AC-13 | iPad 13" ngang, cỡ chữ `.accessibility1` | mở Settings | không nhãn nào trong sidebar bị cắt (`…`), mọi hàng sidebar cao ≥ 44pt | `ShotDexUITests/scripts/ipad-settings-a11y.json` + dump ⚠️ chưa có |
| AC-14 | VoiceOver bật, iPad 13" ngang | quét qua sidebar | mỗi mục đọc ra tên mục và trait `.isSelected` cho mục đang chọn; detail pane có heading đúng tên mục | ⚠️ chưa có |
| AC-15 | Settings mở | gõ `hdr` vào ô Search | kết quả có đúng hàng **"View Full HDR"** kèm dòng phụ "Playback"; gõ `HDR` và `hdr` cho cùng kết quả | ✅ `SettingsSearchTests.matchesRowLabelCaseInsensitively` + `resultsCarryTheOwningSectionAsSubtitle`, và [ảnh trên iPhone](assets/2026-09-22-settings-search-iphone16.png) |
| AC-16 | iPhone 402×874, Settings mở | gõ một từ vào ô Search rồi chạm kết quả | màn cuộn tới đúng hàng đó, ô tìm kiếm đóng lại (bàn phím không che), và hàng nháy nền 1,2s | ⚠️ hai phần ba: cuộn đo được (`settings.row.useCellularData` dịch từ y=428 lên y=374 trong dump `phone16-search`), đóng ô tìm kiếm thấy trong [ảnh](assets/2026-09-22-settings-search-result-opened-iphone16.png); **cú nháy chỉ chứng minh ở tầng model** (`SettingsNavigationTests.theFlashLightsUpImmediatelyAndClearsItself`) — chưa bắt được trên ảnh, xem Rủi ro |
| AC-17 | `SettingsSearchIndex` và các section thật | đếm số nhãn hàng ở hai nơi | mỗi `SettingsSection` có số mục index **bằng** số hàng nó dựng; không section nào thiếu index | ✅ `SettingsSearchTests.everySectionIsIndexed` + `eachSectionIndexesEveryRowItDraws` (bảng vàng 38 hàng) + `everyRowLabelProducesExactlyOneEntry` |
| AC-18 | Settings mở ở bất kỳ bố cục nào | gõ `zzzz` (không khớp gì) | hiện `ContentUnavailableView.search`, không phải danh sách rỗng | `ShotDexUITests/scripts/ipad-settings-search-empty.json` + ảnh ⚠️ chưa có |
| AC-19 | iPad 13" ngang, Settings mở | chụp sidebar | cả 9 mục có ký hiệu SF Symbols đúng bảng trên, mỗi hàng cao ≥ 44pt | ✅ `ShotDexUITests/scripts/ipad-settings-split.json` — dump ảnh có đủ 9 `settings.sidebar.*`, hàng cao **53pt**; `SettingsLayoutTests.everySidebarItemHasItsOwnSymbol` |

**Đã chứng minh (2026-09-22):** AC-1, AC-2, AC-3, AC-3b, AC-5, AC-12, AC-15, AC-17, AC-19
đầy đủ; AC-4 và AC-16 một phần (xem cột chứng minh). Chưa chạm tới: AC-6 (Duo), AC-7
(Support), AC-8 (widget preview), AC-9 (xoay), AC-11 (`.limited`), AC-13 (cỡ chữ
accessibility), AC-18 (empty state trên màn), cộng ba cái không có đường tự động là AC-4b,
AC-10, AC-14.

**Hai chỗ chứng minh còn hở, nói thẳng:**
1. **Dump "trước khi sửa" của AC-4 không có.** Ba lượt `Tools/ui-drive` đầu tiên chết:
   lượt một mất kết nối với app khi `dump` đi qua cả cây (`text: "all"` — cùng cái bẫy
   `.any` đã ghi cho Video Studio), hai lượt sau bị giết vì hai lượt driver chạy chồng
   nhau xoá `ShotDexUITests/Resources/driver-script.json` của nhau. Thứ tự section được
   khoá bằng test thay thế; **một lượt driver chỉ được chạy một lần một**, và script iPad
   không được mở đầu bằng `orientation` (bước đó treo hơn 9 phút trên máy ảo này — đặt máy
   sẵn hướng cần chụp rồi mới chạy).
2. **Cú nháy 1,2s chưa bắt được trên ảnh.** Model có test; nhưng mọi đường chụp ở đây
   (`Tools/sim-shot`, `dump` của driver, công cụ MCP) mất hơn một giây để trả về, nên
   khung hình luôn rơi sau khi nháy đã tắt. Muốn ảnh thì phải quay video (`simctl io
   recordVideo`) và cắt khung — máy này chưa có `ffmpeg`.

**Chưa chứng minh được:** các tiêu chí liệt kê ở trên — chưa có `SettingsLayoutTests` lẫn
`SettingsSearchTests`, chưa có script `Tools/ui-drive` nào cho Settings, và AC-4b (Slide
Over), AC-10 (Stage Manager) cùng AC-14 (VoiceOver) không có đường tự động chứng minh: hai
cái đầu chứng minh bằng hàm thuần cộng một ảnh chụp tay, AC-14 bằng một lượt quét tay có
ảnh. Việc viết chúng thuộc giai đoạn Build/Test, không phải Design.

---

## Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| `NavigationSplitView` là cấu trúc điều hướng **duy nhất** kiểu này trong app — chưa có tiền lệ nội bộ để sao chép | Giới hạn ở Settings trong bản này; nếu nó chạy tốt thì mới bàn tới màn khác |
| `fullScreenCover` chứa split view có thể đụng lại bug SIGBUS `HostPreferencesTransform` từng gặp | Giữ nguyên thứ tự modifier ở `RootTabView`; AC-3/AC-12 mở và đóng Settings ở cả hai nhánh iOS |
| Duo trong chỉ cao 669pt: sidebar 9 mục cộng toolbar có thể vẫn phải cuộn ở cỡ chữ lớn | AC-6 đo ở cỡ chữ mặc định, AC-13 đo ở `.accessibility1`; cuộn được là chấp nhận ở cỡ accessibility, không chấp nhận ở cỡ mặc định |
| Ngưỡng theo size class đưa cả **Split View 1/2 trên iPad 13" (688pt)** vào split, detail còn ~368pt — hẹp hơn nhiều bố cục khác trong app | Đúng điều Settings hệ thống làm ở cùng bề rộng; sàn 320pt vẫn giữ. Nếu đo thấy hàng bị cắt thì hạ `min` của `navigationSplitViewColumnWidth` xuống 280 trước khi nghĩ tới ngưỡng pt |
| Gom section (Sharing+Export, và Privacy/Library Size vào Photo Library) làm người quen bố cục cũ mất dấu một hàng | Bố cục compact **không đổi**; việc gom chỉ tồn tại ở sidebar. Search (AC-15/16) là đường tắt cho ai không nhớ hàng nằm ở mục nào |
| `SettingsSearchIndex` là bản sao thứ hai của nhãn hàng — đổi chữ mà quên sửa index thì tìm không ra | Index và hàng dùng chung hằng chuỗi; AC-17 đối chiếu số lượng mỗi section |
