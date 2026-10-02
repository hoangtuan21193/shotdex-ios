# iphone-ux-review — ShotDex, iPhone 17 (402×874, một tay, dọc)

Phạm vi: board `Main` + `PH_*`, và code đứng sau. Không build, không chạy sim. Các điểm cần chạy máy mới biết chắc được đánh dấu "chưa xác nhận runtime".
Quy ước: vùng ngón cái = nửa dưới và cạnh phải; góc trên-trái gần như không với tới. Mọi con số pt lấy từ code hoặc từ `render/*.json` của board.

**Đọc trước khi dùng board:** nhiều board `PH_*` hỏng ở phía vẽ (xem PH-17), nên các nhận xét về layout dựa vào code + JSON đo, không dựa vào ảnh PNG.

---

### PH-01 Lưới → viewer: không có điểm xuất phát, và đóng viewer không đưa lưới tới ảnh vừa xem
- Màn / thiết bị: Library, Album Detail, Smart Album (mọi lưới mở `PhotoDetailScreen`) · PH
- Mức: nên sửa
- Ở đâu: APP (`Features/Library/LibraryScreen.swift:154` `fullScreenCover(item: $viewerTarget)`; `PhotoDetailScreen.swift:81` `@State var currentIndex`; không có `matchedTransitionSource` / `navigationTransition(.zoom)` nào trong cả `ShotDex/`)
- Vấn đề: chạm một tile thì viewer trượt từ đáy lên, không liên quan tới tile vừa chạm. Vuốt xuống để đóng (`handleDismissPan`, ngưỡng 140pt hoặc 900pt/s) thì ảnh co lại về hư không. Tệ hơn: `currentIndex` của viewer là state cục bộ, `PhotoViewerTarget.startIndex` cố định, và không có đường nào báo ngược cho lưới. Mở ảnh thứ 10, vuốt ngang 40 ảnh, đóng: lưới vẫn ở chỗ cũ, ảnh người dùng đang dừng ở đó nằm ngoài màn. Đây là thao tác dùng nhiều nhất của cả app, và người dùng phải tự tìm lại chỗ.
- Đề xuất: (1) khi đóng, viewer ghi asset id đang xem vào `LibraryModel`/lưới (một token kiểu `jumpToNewestToken` đã có sẵn trong `PhotoGridCollectionView.swift:47`), lưới cuộn tile đó vào màn nếu nó đang ngoài vùng nhìn, không animate nếu đã thấy. Chi phí: một token + một `scrollToItem`, không tốn pixel. (2) Phần zoom-from-tile khó hơn vì lưới là `UICollectionView` (không dùng được `matchedTransitionSource` của SwiftUI): cần `UIViewControllerAnimatedTransitioning` riêng; để sau. Nếu không làm (2), ít nhất làm (1) vì nó là lỗi trạng thái chứ không phải trang trí.
- Bằng chứng: grep `matchedTransitionSource|navigationTransition|\.zoom(` không có kết quả ngoài `UIScrollView.zoom`; grep `scrollToItem` trong `PhotoGridCollectionView.swift` chỉ có `setContentOffset` cho anchor/jump-to-newest. HIG Motion: <https://developer.apple.com/design/human-interface-guidelines/motion> (chưa fetch trong lượt này, nên phần trích HIG là chưa xác nhận).

### PH-02 Chế độ chọn: Compare / Edit / ⋯ / × đều ở hàng trên, chỉ Share và Delete ở đáy
- Màn / thiết bị: Library, Album, Smart Album · PH
- Mức: nên sửa (phản biện quyết định trong `docs/02-functional-spec/FS-01-library/06-multi-select.md` §3 "Compare và Edit nằm ở nav bar")
- Ở đâu: APP (`SelectionBarViews.swift:167-291` `SelectionToolbarItems`; `:59-85` `SelectionBottomBar`); BOARD `PH_LibrarySelect` đúng như code
- Vấn đề: doc tự viết Compare và Edit là "hai thứ người ta chọn ảnh để làm". Tức là hai động từ tần suất cao nhất của chế độ này, và chúng nằm ở góc xa nhất: Compare ở x≈30–102, y≈64–104 (góc trên-trái, ngón cái tay phải gần như không tới; tay trái thì còn tệ hơn với × ở góc phải). Thoát chế độ (×, 44pt ở góc trên-phải) là thao tác làm sau *mỗi* lượt chọn. Trong khi đáy 48pt chỉ chứa Share + Delete + pill đếm. Menu ⋯ mở từ góc trên-phải xuống, ~14 dòng (~620pt), hàng "Select All" ở dòng thứ 10.
- Đề xuất: thanh đáy thành `[Share 48] [Compare 48] [pill đếm co lại] [Edit 48] [Delete 48]`; pill rút từ "Show Selected (5・68.4MB)" xuống "5・68.4MB" để vừa: 4×48 + 4×8 = 224pt, còn 370−224 = 146pt cho pill. Không thêm chiều cao (giữ `selectionGridInset` 100pt). Nav bar còn lại ⋯ và ×. Compare/Edit đổi từ chữ sang glyph (mất "spelled out" của doc; đổi lại chạm được bằng ngón cái). Nếu không muốn đổi: tối thiểu thêm ⋯ vào thanh đáy để menu mở lên từ tay. Phá luật: doc FS-01.06 §3 ("hai nút chữ bên trái") và ý "bám Photos".
- Bằng chứng: `PH_LibrarySelect.png` (Compare/Edit/⋯/× đều y≈84); `SelectionBarViews.swift:180-202`, `:283-289`; doc dòng "Compare và Edit không nằm trong menu".

### PH-03 Compare: nút đỏ "Delete N Photos" ở góc trên-phải, sau khi cuộn cả danh sách ảnh
- Màn / thiết bị: Compare (từ Library, Duplicates) · PH
- Mức: nên sửa
- Ở đâu: APP (`CompareScreen.swift:~441-470` `topBar`, `deleteButton` 52pt cao, padding top 8; ScrollView `.padding(.top, 72)` dưới nó)
- Vấn đề: ở 1 cột trên điện thoại, 3+ ảnh = nhiều màn cuộn. Người dùng cuộn xuống, chạm đánh dấu từng ảnh, rồi phải vuốt ngược lên đầu danh sách (thanh trên nổi nên không cần cuộn, nhưng) với tay tới y≈67–119, góc phải trên, để chốt một hành động huỷ. Cùng lúc Duplicates dùng thanh đáy `deleteBar` (`DuplicatesScreen.swift` `.safeAreaInset(edge: .bottom)`), tức là cùng một việc "xoá các ảnh đã đánh dấu" nằm ở hai nơi khác nhau. Tần suất: mỗi phiên Compare/Duplicates một lần, và mức hậu quả cao (PhotoKit hỏi lại là lưới an toàn cuối, doc chọn không thêm lớp thứ hai).
- Đề xuất: đưa nút xuống đáy (thanh nổi 52pt ở `safeAreaInset(.bottom)`, cách đáy 8pt trên home indicator) như Duplicates; góc trên-phải còn hint "Tap a photo to mark it for deletion" và đếm. Chi phí: `.padding(.bottom, 24)` của ScrollView thành ~84pt, mất ~60pt cuối danh sách khi có dấu; ảnh vẫn cuộn xuyên dưới.
- Bằng chứng: `PH_Compare.png`; `CompareScreen.swift` đoạn `topBar` ("Close on the left; on the right either what a tap does, or what the taps so far add up to"); doc 08-compare dòng 48.

### PH-04 Resize: nút chính nằm cuối ScrollView, dưới nếp gập; công tắc "Delete Originals" ngay trên nó
- Màn / thiết bị: Compress (Resize N Photos) · PH
- Mức: nên sửa
- Ở đâu: APP (`Editing/CompressionScreen.swift` `formBody` → `exportButton(controller)` là phần tử cuối của `VStack` trong `ScrollView`; `primaryActionHeight` 50pt)
- Vấn đề: preview 250pt (nhiều ảnh) + Size + Quality + Format + Metadata + Delete Originals + chú thích: nút bắt đầu ở y≈835 theo `PH_Compress.json`, tức nằm dưới đường home indicator (874−34 = 840) và kết thúc ~885. Màn hình mở ra mà thấy không có nút chính; phải cuộn. Ngay trên nó là công tắc phá huỷ "Delete Originals" nằm ở vùng ngón cái, một cú trượt lệch thì xoá gốc (PhotoKit vẫn hỏi lại).
- Đề xuất: ghim nút vào `safeAreaInset(edge: .bottom)` (nền `EditorTheme.panelSolid`, 50pt + 12pt đệm, tốn ~74pt của vùng cuộn; bù lại bớt preview từ 250 xuống ~200 khi nhiều ảnh). Đẩy "Delete Originals" lên cao hơn (ngay dưới Metadata, tách khỏi nút bằng cả khối Bulk Fill) hoặc đổi sang hàng có chữ cảnh báo đỏ khi bật. Collage Export (nút cam ở đáy) và Resize nên cùng một quy tắc: nút chính ghim đáy.
- Bằng chứng: `PH_Compress.png`, `PH_Compress.json`; `CompressionScreen.swift` `formBody`.

### PH-05 Tính năng chính (lọc theo máy/ống kính) cách Library 4 chạm; menu lọc không có Camera/Lens
- Màn / thiết bị: Library · PH
- Mức: nên sửa
- Ở đâu: APP (`Shared/PhotoFilterMenu.swift:filterSection`: All Items, Favorites, Photos Only, Videos Only, Capture Kind, Advanced Filter…); doc `FS-01.05 §5` mô tả đúng như vậy nhưng không có chỗ nào quyết định loại Camera/Lens ra
- Vấn đề: lời hứa đầu tiên của Onboarding là "Find photos by camera and lens". Từ Library, đường lọc là: chạm nút lọc (góc trên-phải, x≈274,y≈84) → Advanced Filter… → sheet toàn màn → Add Condition → chọn trường Camera Brand → gõ chữ → chạm Search (lại ở trên cùng). Đường tìm kiếm ở tab Search tốt hơn nhiều (ô ở đáy, viên gợi ý máy/địa điểm), nhưng Library không chỉ tới nó, và `model.availableBodies` / `availableLenses` đã có sẵn trong `LibraryModel`.
- Đề xuất: thêm hai menu con `Camera ▸` và `Lens ▸` vào phần `Filter:` ngay sau Favorites, liệt kê tối đa 8 mục đầu của `availableBodies` / `availableLenses` (nhiều ảnh nhất trước), chọn một là bật chip. Menu nay có ~9 dòng nên cộng 2 dòng vẫn chưa tới mức menu ⋯ của chế độ chọn (14). Chi phí: không chiếm chỗ màn; phải sửa `FilterCriteria` binding (đã có hãng/thân máy/ống). Phá luật: FS-01.05 §1 "một điều kiện không hiện ở hai chỗ" (Advanced đã có), phải lập luận: đây là cửa tắt, không phải bản sao.
- Bằng chứng: `PH_Onboarding.png` (promise 1); `PhotoFilterMenu.swift`; `SearchSuggestionsScreen.swift` `suggestions` đã trộn `availableBodies.prefix(2)`.

### PH-06 Onboarding: "Continue" mở hộp thoại quyền mà màn hình không báo trước chọn gì
- Màn / thiết bị: Onboarding · PH
- Mức: nên sửa
- Ở đâu: APP (`Onboarding/OnboardingScreen.swift:21-31`: nút gọi thẳng `requestAuthorization()`, không có dòng nào giải thích bước kế tiếp); board đúng với code
- Vấn đề: người dùng đọc 4 lời hứa, chạm Continue, và nhận hộp thoại hệ thống với ba nút (tên nút chính xác của iOS chưa xác nhận: kiểu Limited / Full / Don't Allow). App chỉ đọc đủ metadata khi có Full Access (chọn Limited thì `LimitedAccessBanner` "ShotDex only analyzes the photos you selected"). Màn trước đó không nói "tiếp theo iOS sẽ hỏi, hãy chọn Allow Full Access". Board có 190pt trống (y 575–750) ngay phía trên nút. Lời hứa riêng tư ("Your photos stay on your device") lại ở dòng cuối, ngay trước nút, tốt, nhưng không nói rõ rằng quyền này chỉ để *đọc*.
- Đề xuất: thêm một dòng `.footnote` `.secondary` 2 dòng ngay trên nút: "Next, iOS asks for access to your photos. Choose Allow Full Access so every photo can be searched. ShotDex only reads them." (~36pt, lấy từ vùng trống). Cân nhắc đổi chữ nút thành "Allow Photo Access" (đúng với `requestAccessState` đã dùng chuỗi này). Nút đã ở y 750–800 (cách đáy 74pt), vùng ngón cái, giữ nguyên.
- Bằng chứng: `PH_Onboarding.png`; HIG Accessing private data <https://developer.apple.com/design/human-interface-guidelines/accessing-private-data> (chưa fetch lần này, chưa xác nhận).

### PH-07 Advanced Search: nút Search và số ảnh khớp xa nhau, cả hai xa ngón cái
- Màn / thiết bị: Advanced Search (sheet large) · PH
- Mức: nên sửa
- Ở đâu: APP (`Library/AdvancedSearchSheet.swift:73-96` toolbar `confirmationAction`; `RuleBuilderSections.swift` footer "Matches N photo." nằm *dưới* "Add Condition")
- Vấn đề: sheet `.large` bắt đầu ở y≈59; Cancel/Search ở y≈108, nhóm Media Type + Match chiếm ~250pt trước điều kiện đầu tiên (Camera Brand ở y≈420 theo board). Khi gõ "Sony" bàn phím (~336pt) chiếm đáy, vùng nhìn còn ~420pt: thấy được một điều kiện đang gõ, không thấy số ảnh khớp (footer ở cuối list) và nút Search ở góc trên-phải. Người dùng thêm điều kiện, gõ xong, phải với lên góc để áp dụng, mà không biết kết quả sẽ là 1.284 ảnh hay 0. Lối vào còn là glyph `slider.horizontal.3` 28pt nằm *trong* ô tìm kiếm (`SearchFieldAccessory.swift` `frame 28×28`) và đổi chỗ với nút xoá (x) của ô.
- Đề xuất: thanh dính đáy (trên bàn phím): nút `Search · 1,284 photos` toàn chiều ngang 50pt, nền kính; bỏ footer count và giữ "Search" top-right như cũ để không phá chuẩn. Chi phí ~62pt chiều cao list. Media Type + Match gộp một hàng (2 segmented cạnh nhau, ~44pt thay vì ~250pt) để điều kiện lên cao. Với glyph 28pt: đưa lên 44pt vùng chạm bằng `contentEdgeInsets` hoặc thêm hàng chữ "Advanced" như phiên bản title-row (đã có sẵn `AdvancedSearchButton` ở `SearchSuggestionsScreen.swift:138`, đang để nil trên iOS 26 để tránh hình bóng ở status bar).
- Bằng chứng: `PH_AdvancedSearch.png` (Camera Brand y≈420, "Matches 1284 photos" ở y≈790); `AdvancedSearchSheet.swift`; `SearchFieldAccessory.swift:~28pt button`. Quyết định có ghi: nút trong ô là chủ ý ("Known cost on iOS 26"); phản biện ở đây chỉ là kích thước vùng chạm.

### PH-08 Viewer: ảnh tĩnh không có "chạm để ẩn chrome"
- Màn / thiết bị: Viewer · PH
- Mức: gợi ý
- Ở đâu: APP (`PhotoDetailScreen.swift:showsViewerChrome` — chrome chỉ ẩn khi `isZoomed` hoặc video; `ZoomableImageView.onSingleTap` chỉ được cấp ở Compare)
- Vấn đề: ảnh đứng (portrait) trên 402×874 bị đè bởi panel thông tin ở trên (8+52pt dưới safe area) và thanh 48+12pt ở đáy, cộng với 59pt/34pt inset: ảnh không bao giờ được xem sạch trừ khi zoom. Với app của người chụp ảnh, "xem ảnh không có gì đè" là hành vi nền tảng (Photos: chạm 1 lần = đen + ẩn chrome).
- Đề xuất: single-tap trên ảnh tĩnh ẩn/hiện chrome (cùng animation opacity đã có cho video, `toggleVideoChrome`), `onSingleTap` chờ double-tap fail ~0.25s (đã `require(toFail:)`). Chi phí: trì hoãn 0.25s cho single-tap; không có tap nào khác trên ảnh tĩnh nên chẳng vỡ gì. Chưa xác nhận runtime: cần xem double-tap-zoom có bị chậm cảm nhận.
- Bằng chứng: `PH_Viewer.png`; `ZoomableImageView.swift:38-42, 108-110`.

### PH-09 Chart editor: bản xem trước nằm cuối một list 8 mục, chỉnh gì cũng không thấy ngay
- Màn / thiết bị: Edit Chart (sheet) · PH
- Mức: nên sửa
- Ở đâu: APP (`Statistics/ChartEditorSheet.swift` thứ tự: typeSection, dataSection, metricSection, seriesSection, limitSection, `RuleBuilderSections`, dateRangeSection, previewSection); sheet Date Range chồng thêm sheet nữa (`:129`)
- Vấn đề: preview chạy sống (`.onChange(of: draft) → runPreview()`), nhưng đứng cuối list. Đổi "Group by" ở y≈320 không bao giờ thấy kết quả vì preview ở dưới cả điều kiện lọc: ít nhất vài màn cuộn. Save ở góc trên-phải. Date Range là sheet thứ hai chồng lên sheet thứ nhất (Cancel/Apply nữa): hai tầng sheet cho một việc chọn hai ngày, đúng kiểu "push cải trang" của doctrine.
- Đề xuất: ghim preview 140pt trên cùng của List (`safeAreaInset(.top)` hoặc section header dính), chart cố định kích thước. Chi phí 140pt trong vùng list ~700pt. Date Range: đổi thành push trong `NavigationStack` của editor (`navigationDestination`), nút Apply giữ, Back có sẵn, bớt một lớp sheet.
- Bằng chứng: `PH_ChartEditor.png`, `PH_DateRange.png` (board vẽ chồng lên Statistics: lỗi board, xem PH-17); `ChartEditorSheet.swift` thân `List`.

### PH-10 Photo Info: bản đồ + toạ độ ở đầu, EXIF máy ảnh bị đẩy xuống dưới nếp gập của detent medium
- Màn / thiết bị: Photo Info (sheet `[.medium, .large]`) · PH
- Mức: gợi ý
- Ở đâu: APP (`MetadataPanel.swift:usefulMetadataList` — `PhotoLocationSection` (map 128pt + tên + toạ độ) đứng trước các section Camera & Lens / Exposure)
- Vấn đề: vuốt lên trên viewer mở sheet ở medium (~437pt). Trừ grabber + nav bar ~56pt, còn ~380pt; location section chiếm ~220–250pt, nên chỉ lộ ~100pt đầu của "Camera & Lens". Với app này, thứ người dùng vừa vuốt lên để xem là máy/ống/phơi sáng, không phải bản đồ. (Panel thông tin đã hiện bản tóm tắt ở trên cùng viewer, nên sheet là "xem sâu hơn", vẫn nên bắt đầu bằng EXIF.)
- Đề xuất: đảo thứ tự: Camera & Lens, Exposure lên trước; Location (map) xuống sau Exposure. Ảnh không có vị trí đã dùng `PhotoLocationUnavailableSection` nên không phải xử lý thêm. Không tốn chỗ. Chưa xác nhận runtime: cần đo chiều cao thực của section ở medium trên iPhone 17.
- Bằng chứng: `MetadataPanel.swift:~80-95, 350-365`; `PH_Metadata.png` (board vẽ lỗi nhưng thứ tự Location → Camera & Lens rõ ràng).

### PH-11 Sheet cao để làm việc nhỏ: nút xác nhận luôn rơi vào 120pt trên cùng
- Màn / thiết bị: Adjust Date & Time, Upload to Server (bước chuẩn bị), Add Connection, Smart Album editor, Video Trim · PH
- Mức: gợi ý
- Ở đâu: APP (`Shared/AdjustDateTimeSheet.swift` không đặt `presentationDetents`, mặc định large; `ServerUpload` host, `ServerForm`, `SmartAlbumEditorSheet` cũng mặc định; `Library/VideoTrimScreen.swift:48-71` Save là nút chữ 52pt-bar ở trên, không có khung 44pt)
- Vấn đề: sheet iPhone mặc định cao hết cỡ, nên Cancel/Done/Upload/Save nằm ở y≈70–110 trong khi nội dung (DatePicker đồ hoạ ~340pt; Upload prep ~480pt) chỉ chiếm nửa dưới. `PhotoDetailScreen` (Metadata) và `CustomizeCollectionsSheet`, `SaveConnectionSheet` đã dùng `[.medium, .large]` đúng chỗ; các sheet trên thì chưa. Video Trim: toàn bộ điều khiển (play, handle, Reset) ở panel đáy, riêng Save đi lên góc trên (và ghi đè bản gốc theo comment code).
- Đề xuất: Adjust Date & Time `.presentationDetents([.height(520), .large])`; Upload prep `[.medium, .large]` nếu tóm tắt "12 photos · 19 files · ~486 MB" nằm trên nút. Trim: thêm nút Save vào hàng Reset/giờ ở panel đáy (cùng hàng với `play/pause`, 44pt), giữ top-bar chỉ cho Cancel. Chi phí: không đổi layout, chỉ detent; Trim thêm một nút 44pt vào hàng đã có.
- Bằng chứng: grep `presentationDetents` (8 chỗ, không có các sheet trên); `PH_Share.png` / `PH_ServerUpload.png` (Cancel/Upload ở y≈108).

### PH-12 Compare: "Keep Only This" chỉ có trong long-press, trong khi code gọi nó là "the shortcut the screen exists for"
- Màn / thiết bị: Compare · PH
- Mức: gợi ý
- Ở đâu: APP (`CompareScreen.swift` `markAllOthers`, `.contextMenu` trên `CompareCard`; hint ở `topBar` chỉ nói "Tap a photo to mark it for deletion" và biến mất sau lần đánh dấu đầu)
- Vấn đề: 8 khung của một khoảnh khắc, giữ 1: đường nhanh là long-press → "Keep Only This". Không có dấu hiệu nào cho cử chỉ này, hint thì biến mất đúng lúc người dùng đã bắt đầu làm theo đường chậm (7 lần chạm). Doctrine: cử chỉ ẩn cần một nút đi kèm hoặc một gợi ý lần đầu.
- Đề xuất: khi có ≥ 4 ảnh và đã đánh dấu 1 ảnh, hint đổi thành "Touch and hold a photo to keep only that one" (1 dòng, cùng chỗ, 0 pt thêm). Hoặc hiện nút ⋯ nhỏ 44pt trên mỗi card mở cùng menu. Chi phí 0–44pt trên mỗi card.
- Bằng chứng: `CompareScreen.swift` comment "The shortcut the screen exists for"; `PH_Compare.png`.

### PH-13 Server Browser: Back chỉ là ‹ ở góc trên-trái; vuốt-cạnh-trái-để-quay-lại có thể đã chết
- Màn / thiết bị: Server Browser (đẩy từ Collections) · PH
- Mức: gợi ý (chưa xác nhận runtime)
- Ở đâu: APP (`ServerImport/ServerBrowserScreen.swift:40` `.navigationBarBackButtonHidden(true)` luôn, `:403-417` ‹ › ở `topBarLeading`)
- Vấn đề: `navigationBarBackButtonHidden(true)` thường kéo theo `interactivePopGestureRecognizer` ngừng hoạt động. `AlbumDetailScreen:163` ẩn Back chỉ khi đang chọn (có chủ ý, kèm `disablesBackSwipe`); Server Browser ẩn cả lúc duyệt thường, nên vuốt cạnh trái có thể không làm gì, trong khi ‹ ở góc xa nhất đi lùi theo lịch sử thư mục (và dismiss khi hết lịch sử). Cần xem trên máy: vuốt từ x=0 có pop không.
- Đề xuất: nếu xác nhận chết, gắn recogniser vuốt cạnh trái (UIScreenEdgePanGestureRecognizer) gọi cùng hàm với ‹ (`model.goBack()` rồi `dismiss()`), giống Files. Chi phí: một recogniser; tay trái tự tìm thấy ‹ ở trái còn tay phải có cử chỉ.
- Bằng chứng: `ServerBrowserScreen.swift:40, 403-417`; `Shared/BackSwipeDisabler.swift` (chứng tỏ app biết cái bẫy này); `PH_ServerBrowser.png`.

### PH-14 Tìm xong nhảy sang Library; quay lại tab Search thì ô trống
- Màn / thiết bị: Search tab → Library · PH
- Mức: gợi ý (chưa xác nhận runtime)
- Ở đâu: APP (`App/RootTabView.swift:SearchTab.onChange(of: navigation.selectedTab)` đặt `query = ""`; `SearchSuggestionsScreen.swift` `.onAppear { query = model.criteria.searchText ?? "" }`)
- Vấn đề: người dùng gõ "Sony 85mm", Search, rơi vào Library với chip. Muốn đổi thành "Sony 135mm" thì chạm tab Search: hai đoạn code trên tranh nhau, và comment ở `SearchTab` nói rõ chủ ý xoá ô để Search key không nộp chữ cũ. Nếu thứ tự là "xoá sau cùng", ô trống, người dùng phải gõ lại toàn bộ; chip trên Library vẫn dùng được (có x), nhưng chip sửa được chữ thì không.
- Đề xuất: khi quay lại tab Search, điền sẵn `criteria.searchText` rồi chọn hết (selectAll) để gõ đè là thay, như Photos. Chi phí: đổi thứ tự hai dòng + `onAppear` đặt `isFieldFocused`. Cần xem runtime thứ tự thật.
- Bằng chứng: `RootTabView.swift` khối `SearchTab` (comment "Leaving the tab empties the field...").

### PH-15 Lần tìm đầu tiên: dòng ví dụ trộn tiếng Việt vào UI tiếng Anh
- Màn / thiết bị: Search tab (thư viện chưa index, chưa có recents) · PH
- Mức: gợi ý (thuộc `copy-consistency`, ghi lại vì đây là màn lần-đầu)
- Ở đâu: APP (`SearchSuggestionsScreen.swift` trong `capsuleStack`: `Text("Try: Fukuoka · f > 1.2 · ISO trên 3200 · trước 2020 · 85mm")`)
- Vấn đề: đây đúng là màn người dùng thấy ở lần tìm đầu (không có gợi ý, không có recents). "trên", "trước" là từ khoá tiếng Việt của parser, nhưng người dùng tiếng Anh sẽ đọc nó như lỗi bản dịch, và không biết "ISO above 3200" mới là câu họ gõ.
- Đề xuất: ví dụ theo ngôn ngữ UI ("ISO above 3200 · before 2020") qua String Catalog; giữ từ khoá Việt trong parser nhưng đừng đưa ra màn tiếng Anh.
- Bằng chứng: `SearchSuggestionsScreen.swift` đoạn `Try:`.

### PH-16 Statistics → Library (drill-down): không có đường nào dẫn ngược lại chỗ vừa rời
- Màn / thiết bị: Statistics · PH
- Mức: gợi ý
- Ở đâu: APP (`App/AppNavigation.swift:122` `pendingLibraryFilter`, `RootTabView.swift:265` đặt `libraryModel.criteria` rồi đổi tab)
- Vấn đề: chạm câu Insights "41% of your photos are at 20–34mm" nhảy sang tab Library đã lọc. Để về Statistics, chạm lại tab; nhưng bộ lọc ở Library *ở lại*, nên lần sau mở Library thấy lưới thiếu ảnh cùng chip, chưa chắc nhớ vì sao. Doc FS-07 AC-9/AC-17 chỉ kiểm chip hiện ra, không kiểm lối về.
- Đề xuất: khi lọc đến từ Statistics, thêm một chip đầu tiên dạng nút "‹ Statistics" (không có x) trên thanh chip, chạm thì xoá lọc và về tab Statistics. Chi phí: một chip ~90pt trong hàng chip đã cuộn ngang, 0pt chiều cao. (Việc "người dùng bị bỏ lại ở đâu" còn thuộc `ux-reviewer`.)
- Bằng chứng: `docs/02-functional-spec/FS-07-statistics/03-acceptance-criteria.md` AC-9, AC-17.

### PH-17 BOARD: nhiều board PH vẽ hỏng (placeholder `{{...}}` chưa thay, thiếu ảnh, board chồng lên nhau)
- Màn / thiết bị: Main, PH_LibrarySelect, PH_AdvancedSearch, PH_Metadata, PH_Share, PH_Collections, PH_AlbumDetail, PH_SmartAlbum, PH_OnThisDay, PH_Creations, PH_Places, PH_Duplicates, PH_Statistics, PH_ChartEditor, PH_DateRange, PH_ServerBrowser, PH_ServerForm · PH
- Mức: nên sửa (chỉ ở board)
- Ở đâu: BOARD (code đúng)
- Vấn đề: những board này không dùng được để kiểm tra layout một tay vì:
  - lưới ảnh trống hoặc chỉ còn nhãn `{{p.ft}}`, `{{p.dur}}`, `{{p.meta}}`, `{{c.name}}`, `{{p.date}}`, `{{p.sub}}`, `{{p.badge}}`, `{{p.name}}`, `{{c.title}}`, `{{k.k}}`, `{{A.T}}`, `{{h.title}}` (template lặp chưa expand): `Main`, `PH_AlbumDetail`, `PH_SmartAlbum`, `PH_OnThisDay`, `PH_Creations`, `PH_Places`, `PH_Collections`, `PH_Duplicates`, `PH_ServerBrowser`, `PH_Collage`;
  - sheet vẽ chồng lên board nền của chính app (thanh toolbar Library/Statistics lộ ra phía sau tiêu đề sheet, tab bar đè nội dung): `PH_AdvancedSearch`, `PH_ChartEditor`, `PH_DateRange`, `PH_ServerForm`, `PH_Share`;
  - menu ⋯ của chế độ chọn đè lên dòng đếm "54,027 Photos, 1,204 Videos" và thanh đáy; `PH_Metadata` có chữ EXIF xuyên qua thanh nút của viewer; `PH_Search` bàn phím chỉ là `{{k.k}}`, `123`, `space`;
  - `PH_Onboarding` vẽ nút Continue xám nhạt như bị vô hiệu (code là `.borderedProminent` bật), `PH_Compress` nút chính cắt sát mép dưới;
  - `PH_Statistics`: biểu đồ Top Camera là khoảng trắng, hàng cuối đè dưới tab bar; `PH_Places`: nền đen, không có bản đồ.
- Đề xuất: sửa trình expand template và dựng hai lớp (nền + sheet) bằng nền đúng của board trước khi kết luận gì về layout trên PNG. Nhắc rằng `Tools/design-board compare` đo trên `*.json` nên cũng chạy trên bản hỏng này.
- Bằng chứng: các PNG ở `build/design/app/render/` kể trên.

---

## Đã kiểm, không có vấn đề (một dòng mỗi cái)
- **Viewer:** nút Close (góc trên-trái) có đường thay thế là vuốt xuống (`handleDismissPan`, 140pt/900pt/s, dọc trội); vuốt lên mở Info, trùng nút ⓘ; thanh đáy Share / ♡ⓘ Edit ⋯ / Delete nằm vùng ngón cái, `.padding(.horizontal, 20)` tránh góc bo.
- **Cạnh trái / pop:** màn đẩy (Places, Duplicates, Trips…) giữ vuốt cạnh trái; chế độ chọn ở Album Detail ẩn Back và gọi `disablesBackSwipe`, có chủ ý và có ×.
- **Cạnh dưới:** các vuốt ngang không bắt đầu trong 20pt đáy; scrubber ngày ở cạnh phải 44pt chỉ bắt chạm trên tay cầm.
- **Quy tắc ngoài phạm vi bị cắt:** màu/radius/motion constants (`design-reviewer`), kích thước chạm (`hig-components`/`device-layout`), `VoiceOver` (`a11y-voiceover`).
