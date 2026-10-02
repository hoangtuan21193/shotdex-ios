# HIG Components review (slug `hig`)

Phạm vi: tier A/B/C (Library, Search, Collections, Statistics, Settings, các sheet, màn server, Duplicates, Support). Tier D (editor, collage, video studio, compare) bỏ qua, trừ khi có vấn đề target/clipping/confirm.

Trang HIG đã fetch (nội dung đọc từ `developer.apple.com/tutorials/data/design/human-interface-guidelines/<page>.json` vì trang HTML render bằng JS): tab-bars, toolbars, search-fields, menus, sheets, alerts, action-sheets, lists-and-tables, pickers, segmented-controls. Mọi trích dẫn HIG dưới đây lấy từ bản đó (URL gốc: `https://developer.apple.com/design/human-interface-guidelines/<page>`).

Ghi chú về board: các PNG board trong `build/design/app/render/` là bản vẽ thô (template chưa điền như `{{p.ft}}`, `{{c.name}}`, `{{k.k}}`, nút kính vẽ thành đĩa xám, sheet vẽ đè lên toolbar của màn bên dưới). Mọi lỗi nhìn thấy trên board đều là lỗi BOARD, không phải APP; các finding dưới đây vì vậy dựa vào code và chỉ dùng board để đối chiếu. Xem HIG-20.

Đã kiểm tra và sạch (không có finding): bộ ba alert xác nhận phá hủy trong `SettingsScreen.swift` (đã là `.alert` có Cancel, nút ghi rõ hậu quả); `ServerUploadSheet` (Cancel/Upload/Done đúng chỗ, alert "Stop Uploading?" có cặp nút hợp lý, `interactiveDismissDisabled` khi đang upload); tách nhóm toolbar bằng `ToolbarSpacer(.fixed)` ở Library/Selection; tab bar iOS 26 dùng `TabView` + `Tab(role: .search)` đúng kiểu hệ thống; sheet có `Cancel` trái / `Save|Apply|Search` phải ở AdvancedSearch, SmartAlbumEditor, ChartEditor, DateRange, ServerForm, CompressionPresetEditor.

---

### HIG-01 Ba màn server vẫn xác nhận xóa bằng `.confirmationDialog`
- Màn / thiết bị: File Servers, On Server, On Cloud · PH, IP, DI, DC
- Mức: nên sửa
- Ở đâu: APP (`ShotDex/Features/ServerUpload/FileServerListScreen.swift:59`, `ShotDex/Features/ServerImport/OnServerScreen.swift:99`, `ShotDex/Features/ServerImport/OnCloudScreen.swift:130`) và DESIGN.md §11 (dòng "Xác nhận phá hủy: `.confirmationDialog`")
- Vấn đề: Đúng cái bẫy mà `DESIGN.md` §10.5 và `SettingsScreen.swift:945` đã ghi lại: trên iOS 26 `confirmationDialog` vẽ thành popover và ẩn nút `.cancel`, chỉ còn nút đỏ "Delete Connection" / "Remove". Settings, Photo Editor, Video Studio, Collage đều đã đổi sang `.alert`; ba chỗ này sót. Cả hai đoạn trong DESIGN.md đang mâu thuẫn nhau (§10.5 cấm, §11 vẫn bắt dùng), nên người viết màn mới sẽ tiếp tục chọn sai. HIG action sheet nói "A SwiftUI confirmation dialog includes a Cancel button by default", nên nếu dialog thực sự không hiện Cancel thì nó đang vi phạm chính HIG; điều này cần xác nhận lại bằng một ảnh chụp swipe-Delete trên iPhone iOS 26.5 (tôi chưa chụp, chỉ dựa vào đo của dự án).
- Đề xuất: Đổi ba chỗ sang `.alert(title, isPresented:, presenting:)` với `Button("Cancel", role: .cancel)` + `Button("Delete Connection", role: .destructive)`, giữ nguyên message. Sửa DESIGN.md §11 thành "alert 2 nút" để khớp §10.5. Giữ `confirmationDialog` ở `ServerExportSheet.swift:74` ("Choose a Connection"): đó là lựa chọn không phá hủy, đúng chỗ của action sheet. Chi phí: 3 chỗ x ~10 dòng, không đổi layout.
- Bằng chứng: HIG "Use an action sheet — not an alert — to offer choices related to an intentional action" và "A SwiftUI confirmation dialog includes a Cancel button by default" (https://developer.apple.com/design/human-interface-guidelines/action-sheets); `REVIEW_QUEUE.md` dòng 8 đã xếp đúng lỗi này của Settings là blocker.

### HIG-02 "Merge All Groups" ghi ngày/vị trí/yêu thích vào Photos mà không hỏi
- Màn / thiết bị: Duplicates · PH, IP, DI, DC
- Mức: nên sửa
- Ở đâu: APP (`ShotDex/Features/Duplicates/DuplicatesScreen.swift:100-104`, `DuplicatesModel.swift:300-331`)
- Vấn đề: Một dòng trung tính trong menu ⋯ ("Merge All Groups", không `role: .destructive`, không confirm) chạy `adoptMetadata` cho mọi nhóm: `PHAssetChangeRequest` ghi `isFavorite`, `location` và **`creationDate`** (lấy ngày sớm nhất) lên ảnh giữ lại trong thư viện thật của người dùng, rồi đánh dấu mọi bản còn lại để xóa. Ngày chụp bị đổi là thay đổi không có nút hoàn tác (Photos có "Revert" nhưng người dùng không biết nó vừa xảy ra). Tên "Merge" không nói rằng ảnh bị ghi đè metadata, và màn không nói số nhóm sẽ bị đụng tới.
- Đề xuất: Trước khi chạy, hiện `.alert("Merge 12 Groups?")`: message "ShotDex keeps the best photo in each group, copies the earliest date, a location and Favorite from the others onto it, and marks the rest for deletion. Nothing is deleted until you tap Delete." Nút `Merge` (không đỏ, vì chưa xóa) + `Cancel`. Ít tốn nhất: một alert, một biến @State.
- Bằng chứng: HIG "when people take an uncommon destructive action that they can't undo, it's important to display an alert in case they initiated the action accidentally" (https://developer.apple.com/design/human-interface-guidelines/alerts); code ở trên.

### HIG-03 Nút Advanced Search nhét vào ô search bằng hack UIKit, thay mất nút Clear
- Màn / thiết bị: Search tab và Search sheet · PH, DI, DC (iPad trước mắt dùng toolbar)
- Mức: nên sửa
- Ở đâu: APP (`ShotDex/Features/Library/SearchFieldAccessory.swift:122-150`, dùng ở `ShotDex/App/RootTabView.swift:533-537` và `:601-605`)
- Vấn đề: Một `Timer` 0.6 s lặp lại để quét mọi `UIWindow` tìm `UISearchTextField` rồi gán `rightView = UIButton` 28x28pt. Hệ quả do chính comment trong file nêu: (1) ô search mất nút Clear (x) hệ thống ("a text field shows either its clear button or its right view, never both"); (2) trên iOS 26 một bản sao nhỏ, chết, của icon hiện ở vùng status bar ("Known cost on iOS 26"); (3) target 28x28 dưới 44; (4) phụ thuộc vào cấu trúc view nội bộ `_UITabHostedSearchContainer`, mỗi bản iOS có thể làm nó vỡ. HIG nói search field "displays a Search icon, a Clear button, and placeholder text".
- Đề xuất: Bỏ hack. Đặt Advanced Search ở chỗ nó là một lựa chọn chứ không phải một phần của ô: một hàng suggestion đầu tiên "Advanced Search…" trong `.searchSuggestions`/capsule stack (đã có sẵn `capsuleStack` cạnh ô), hoặc dùng `.searchScopes` cho Media Type và để Advanced là mục cuối. Màn Search tab đã tự vẽ title row (`SearchSuggestionsScreen.swift:117-127`), nên có chỗ cho một nút chữ "Advanced" (đã có `AdvancedSearchButton`, hiện `onAdvanced: nil` ở 26). Chi phí: mất ~1 chạm so với icon trong ô, đổi lại có Clear, hết ghost icon, hết polling.
- Bằng chứng: HIG "A search field is an editable text field that displays a Search icon, a Clear button, and placeholder text" (https://developer.apple.com/design/human-interface-guidelines/search-fields); `SearchFieldAccessory.swift:11-17,141-148`.

### HIG-04 New Chart: Save xám dù ô tên đang hiện một tên có vẻ đã điền
- Màn / thiết bị: Chart Editor (sheet) · mọi thiết bị
- Mức: nên sửa
- Ở đâu: APP (`ShotDex/Features/Statistics/ChartEditorSheet.swift:96-100` canSave, `:159` TextField, `:77` draft)
- Vấn đề: `TextField(defaultTitle, text: $title)` hiện "Camera Model" (chữ xám mờ) trong ô tên, `draft` cũng dùng `defaultTitle` khi tên trống, nhưng `canSave` đòi `!trimmedTitle.isEmpty`. Người dùng mở "New Chart", thấy mọi thứ đã có giá trị hợp lý, preview vẽ được (`previewSection` dùng `canSave`, tức là cũng trống: "Finish configuring the chart to see a preview" vì một lý do không nói ra), và nút Save không bấm được. Không có dòng nào nói "đặt tên".
- Đề xuất: Bỏ điều kiện tên khỏi `canSave` (code đã sẵn fallback `trimmedTitle.isEmpty ? defaultTitle : trimmedTitle` ở `draft`); preview và Save cùng sáng ngay khi cấu hình hợp lệ. Nếu cố ý bắt buộc đặt tên thì footer dưới ô phải nói "Enter a name to save", và placeholder đổi thành "Chart name".
- Bằng chứng: code đã trích; HIG buttons/disabled: "Show people when a menu item is unavailable" áp dụng tinh thần tương tự (menus) — control tắt phải cho biết vì sao.

### HIG-05 Collections và Statistics không có tiêu đề màn hình
- Màn / thiết bị: Collections, Statistics · PH, IP, DI, DC
- Mức: nên sửa
- Ở đâu: APP (`ShotDex/Features/Albums/AlbumsScreen.swift:116-145`, `ShotDex/Features/Statistics/StatisticsScreen.swift:51-80`: toolbar không có `navigationTitle`) · khớp với PH_Collections.png, PH_Statistics.png (thanh trên chỉ có gear và nút tròn)
- Vấn đề: Hai tab gốc không nói mình là màn nào; thứ duy nhất nói là nhãn tab bên dưới. Khi người dùng cuộn hoặc đang ở iPad/Duo, tab bar nằm xa. `DESIGN.md` §7.1 còn quy định `.largeTitle` cho "title màn hình gốc", và `docs/` không có quyết định nào bỏ title ở hai màn này (tôi đã grep FS-06/FS-07). Library thì có lý do (ngày thay chỗ title). Search tab tự vẽ "Search" cỡ largeTitle, nên chỉ Collections và Statistics bị thiếu.
- Đề xuất: `.navigationTitle("Collections")` / `.navigationTitle("Statistics")` với `.navigationBarTitleDisplayMode(.large)` (hoặc `.inline` nếu muốn giữ chiều cao, như màn Duplicates). Chi phí: ~96pt chiều cao khi chưa cuộn (large) hoặc 0 (inline). Nếu chủ ý để trống thì ghi vào DESIGN.md như một ngoại lệ có tên.
- Bằng chứng: HIG "Provide a useful title for each window. A title helps people confirm their location as they navigate your app" (https://developer.apple.com/design/human-interface-guidelines/toolbars); DESIGN.md §7.1.

### HIG-06 Menu "+" của Collections gộp "Customize" vào cùng hàng với New Album
- Màn / thiết bị: Collections · PH, IP, DI, DC
- Mức: nên sửa
- Ở đâu: APP (`ShotDex/Features/Albums/AlbumsScreen.swift:122-143`)
- Vấn đề: Nút `plus` mở menu có "New Album", "New Smart Album", rồi (sau Divider) "Customize" (sắp xếp/ẩn section). Dấu + nói "thêm", Customize không phải thêm. Accessibility label là cả một câu: "New album or smart album, or customize this tab" (nhãn dài thể hiện chính control đang gánh hai việc). Statistics cũng dùng `plus` nhưng là một nút thẳng "Add chart".
- Đề xuất: Giữ `plus` chỉ cho New Album / New Smart Album (nhãn VoiceOver: "New"). Chuyển Customize xuống cuối nội dung Collections thành một hàng "Customize & Reorder" (đúng chỗ Photos đặt) hoặc vào một menu ⋯ riêng. Chi phí: một hàng cuối trang hoặc một nút toolbar thứ hai.
- Bằng chứng: HIG "Make sure the meaning of each control is clear. Don't make people guess or experiment to figure out what a toolbar item does." (https://developer.apple.com/design/human-interface-guidelines/toolbars).

### HIG-07 Form nhập nhiều dữ liệu vuốt xuống là mất, không hỏi
- Màn / thiết bị: Smart Album Editor, Chart Editor, Add/Edit Connection, Advanced Search (sheet) · PH
- Mức: nên sửa
- Ở đâu: APP (`ShotDex/Features/Albums/SmartAlbumEditorSheet.swift:79-94`, `ShotDex/Features/Statistics/ChartEditorSheet.swift:122-148`, `ShotDex/Features/ServerUpload/FileServerFormScreen.swift:222-232`; `grep interactiveDismissDisabled` không có kết quả nào ở bốn file này)
- Vấn đề: Các sheet này có Cancel/Save nhưng vuốt xuống vẫn đóng ngay và bỏ cả bản nháp: một smart album với 4 điều kiện, một chart đã chọn xong dimension/metric/filter, hoặc một form server đã gõ host, user và password. Editor ảnh/Collage/Video Studio đã có `interactiveDismissDisabled(hasEdits)` + xác nhận; tier A thì chưa.
- Đề xuất: Theo dõi `isDirty` (so với giá trị khởi tạo) và gắn `.interactiveDismissDisabled(isDirty)`, đồng thời nút Cancel khi dirty hiện `.alert` "Discard Changes?" (Discard đỏ + Keep Editing), dùng alert chứ không `confirmationDialog` vì lý do ở HIG-01. HIG viết "use an action sheet to let them confirm" nhưng dự án đã đo action sheet tệ trên 26, nên alert 2 nút là bản thay.
- Bằng chứng: HIG "If people have unsaved changes in the sheet when they begin swiping to dismiss it, use an action sheet to let them confirm their action." (https://developer.apple.com/design/human-interface-guidelines/sheets).

### HIG-08 Sheet mở sheet (ba cặp)
- Màn / thiết bị: Chart Editor → Date Range; Advanced Search → Save as Smart Album; Upload to Server → Add Connection → Save Connection · PH
- Mức: nên sửa
- Ở đâu: APP (`ChartEditorSheet.swift:129`, `AdvancedSearchSheet.swift:112`, `ServerUploadSheet.swift:43` và `FileServerFormScreen.swift:267`)
- Vấn đề: Mỗi cặp là một `.sheet` trong một `NavigationStack` đã nằm trong sheet. Đóng sheet trên cùng đưa về sheet dưới chứ không về màn gốc, và ở cặp thứ ba thành ba tầng. Upload tự mở form (`ServerUploadSheet.swift:41`) ngay khi không có server, nên người dùng bấm Upload từ Library và gặp hai sheet chồng nhau.
- Đề xuất: Đổi thành `push` trong chính `NavigationStack` của sheet: Date Range thành một hàng "Custom Range…" đẩy `DateRangePickerSheet` (đã là một View có toolbar); Save as Smart Album đẩy `SmartAlbumEditorSheet`; Add Connection đẩy `FileServerFormScreen` (nó đã tự có `NavigationStack(path:)` nên cần bỏ stack lồng hoặc hạ thành nội dung). Chi phí: trung bình, vì form server có stack riêng.
- Bằng chứng: HIG "Display only one sheet at a time from the main interface… If something people do within a sheet results in another sheet appearing, close the first sheet before displaying the new one." (https://developer.apple.com/design/human-interface-guidelines/sheets).

### HIG-09 Vài control nhỏ hơn 44pt trong form tier A
- Màn / thiết bị: Rule builder (Advanced Search, Smart Album Editor, Chart Editor), Statistics cards · PH
- Mức: nên sửa
- Ở đâu: APP (`ShotDex/Features/Albums/SmartAlbumRuleRow.swift:44-66` menu field/operator và nút xóa; `:128` chip gợi ý; `ShotDex/Features/Statistics/ChartCard.swift:251-261` và `InsightsCard.swift:39-48` nút ⋯)
- Vấn đề: Số đo từ code, không từ máy: token field/operator = `.subheadline` + padding dọc 6 = khoảng 32pt cao; nút xóa điều kiện = `minus.circle.fill` `.title3` không có frame (~28pt); chip gợi ý = `.footnote` + padding dọc 5 = khoảng 28pt; nút `ellipsis.circle` `.title3` trên mỗi card chart/insights ~28pt, nằm sát mép card. Hai nút cạnh nhau (xóa điều kiện cạnh menu operator) dễ bấm nhầm trong một List row vốn còn có swipe-delete.
- Đề xuất: Thêm `.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())` cho nút xóa và nút ⋯ (giữ glyph nhỏ, mở rộng vùng chạm); token menu và chip giữ hình 32pt nhưng thêm `padding(.vertical, 6)` vô hình qua `contentShape`. DESIGN.md §6 đã đặt "chiều cao chạm tối thiểu 44" cho tier A/B/C.
- Bằng chứng: DESIGN.md §6; HIG (buttons) chuẩn 44x44pt; dòng `.padding(.vertical, 6)` ở `SmartAlbumRuleRow.swift:75`.

### HIG-10 Xóa chart không xác nhận, không hoàn tác
- Màn / thiết bị: Statistics · PH, IP
- Mức: nên sửa
- Ở đâu: APP (`ShotDex/Features/Statistics/ChartCard.swift:254` menu "Delete"; `StatisticsModel.swift:168-181`)
- Vấn đề: "Delete" (role destructive) trong menu ⋯ của card xóa ngay hàng DB (`chartStore.delete`) và biến mất khỏi list. Một chart là cấu hình do người dùng dựng (dimension, metric, filter, scope), không tái tạo được bằng một chạm. Menu đặt Delete ngay dưới Duplicate, cách "Edit" một hàng; ở edit mode thì có dấu trừ đỏ hai bước nên an toàn hơn.
- Đề xuất: Hoặc alert "Delete "Top Camera"?" (Delete đỏ + Cancel), hoặc xóa mềm với banner Undo 5 s (app đã có `AppBanner`). Undo hợp tinh thần HIG hơn ("avoid alerts for common, undoable actions") và ít ma sát hơn.
- Bằng chứng: HIG alerts, câu đã trích ở HIG-02.

### HIG-11 Alert hiện ngay khi mở app: "Saving was interrupted"
- Màn / thiết bị: Library · mọi thiết bị
- Mức: gợi ý
- Ở đâu: APP (`ShotDex/Features/Library/LibraryScreen.swift:178-200`)
- Vấn đề: `.task` của Library bật alert nếu `PanoramaSaveRecord.interrupted` có giá trị, tức là một cửa sổ modal ngay lúc người dùng vừa mở app. Câu chữ cũng sai ngữ pháp với số nhiều ("^[1 photo](inflect) were being joined" ra "1 photo were").
- Đề xuất: Chuyển sang `AppBanner` có nút "Try Again" hoặc một hàng cố định trong Library ("Panorama of 6 photos wasn't saved · Try Again · Dismiss"), tự mất khi người dùng xử lý. Nếu giữ alert thì sửa "was/were" bằng chuỗi inflect đầy đủ.
- Bằng chứng: HIG "Avoid showing an alert when your app starts." (https://developer.apple.com/design/human-interface-guidelines/alerts).

### HIG-12 Tiêu đề alert lỗi chung chung, và quy tắc DESIGN.md §11 đẩy chúng ra
- Màn / thiết bị: Library, Album Detail, Smart Album Detail, Duplicates · mọi thiết bị
- Mức: gợi ý
- Ở đâu: APP (`LibraryScreen.swift:234`, `AlbumDetailScreen.swift:100`, `SmartAlbumDetailScreen.swift:160`: "Something Went Wrong"; `DuplicatesScreen.swift:126`: "Duplicates Error") và DESIGN.md §11 ("Lỗi: `.alert` với tiêu đề danh từ (`Compression Error`)")
- Vấn đề: Message là `error.localizedDescription` thô, tiêu đề không nói việc nào hỏng; ba màn khác nhau dùng cùng một tiêu đề. DESIGN.md §11 đang ép dùng kiểu "<Nơi> Error", ngược với HIG ("Avoid writing a title that doesn't convey useful information — like "Error""). Cùng codebase đã có tiêu đề đúng kiểu: "Couldn't Delete Photos", "Couldn't Save Connection", "Couldn't Save Folder".
- Đề xuất: Mỗi alert đặt tên theo việc hỏng ("Couldn't Add to Album", "Couldn't Scan for Duplicates") bằng cách truyền tên hành động cùng lỗi; sửa DESIGN.md §11 thành "Couldn't <việc>". Chi phí: cần mỗi chỗ gọi cung cấp tên việc.
- Bằng chứng: HIG "Write a title that clearly and succinctly describes the situation… avoid writing a title that doesn't convey useful information — like "Error"" (https://developer.apple.com/design/human-interface-guidelines/alerts).

### HIG-13 Tiêu đề ngày của Library dài hơn 15 ký tự và tranh chỗ với token Indexing
- Màn / thiết bị: Library · PH (402pt), DC (382pt)
- Mức: gợi ý (cần ảnh chụp để chốt)
- Ở đâu: APP (`ShotDex/Features/Library/LibraryScreen.swift:1112-1125` principal; `:1128-1135` token Indexing)
- Vấn đề: Title là "September 30, 2026" (18 ký tự, `.headline`). Khi indexing chạy, leading có gear + token "Indexing 42%" (HStack có `fixedSize`, rộng ~110pt), trailing có Filter + Select. Cộng sơ bộ: gear ~44 + token ~120 + title ~170 + filter ~44 + Select ~72 = ~450pt trên màn 402pt (và 382pt trên Duo cover), nên hệ thống sẽ cắt hoặc ẩn title. Tôi chưa thấy điều đó ở runtime. Cần ảnh chụp Library iPhone 17 + Duo cover **đang indexing** và **tên tháng dài** ("September", "November") để biết.
- Đề xuất: Nếu bị cắt: rút title thành "Sep 30, 2026" khi `isIndexing`, hoặc chuyển token Indexing vào hàng thứ hai (dưới title như dòng phụ) thay vì leading. HIG đặt ngưỡng 15 ký tự.
- Bằng chứng: HIG "keep the title under 15 characters long so you leave enough room for other controls" (https://developer.apple.com/design/human-interface-guidelines/toolbars).

### HIG-14 Nút "Cancel" của scan Duplicates có `role: .destructive`
- Màn / thiết bị: Duplicates · mọi thiết bị
- Mức: gợi ý
- Ở đâu: APP (`ShotDex/Features/Duplicates/DuplicatesScreen.swift:206`)
- Vấn đề: Hủy một lần quét không phá hủy dữ liệu nào, nhưng nút ra đỏ, cùng màu với "Delete 2 Photos" ngay dưới cùng màn. Đỏ mất nghĩa "cẩn thận ảnh sẽ mất".
- Đề xuất: Bỏ `role: .destructive`; để nút thường (tint mặc định hoặc `.primary`).
- Bằng chứng: HIG "Use the destructive style to identify a button that performs a destructive action" (alerts); HIG action-sheets: "Destructive: The button destroys user data or performs a destructive action in the app" (https://developer.apple.com/design/human-interface-guidelines/action-sheets).

### HIG-15 Trạng thái "đã vote" ở Support chỉ khác bằng màu
- Màn / thiết bị: Support · PH, IP
- Mức: nên sửa
- Ở đâu: APP (`ShotDex/Features/Support/SupportScreen.swift:225-243`)
- Vấn đề: Nút vote là `arrowtriangle.up.fill` + số; đã vote thì `foregroundStyle(accent)`, chưa vote thì `.secondary`. Cùng glyph, cùng độ đặc, chỉ đổi màu amber/xám. Người mù màu hoặc ở chế độ Increase Contrast nhìn không ra. VoiceOver có đổi label nhưng trait chọn không được gắn. DESIGN.md §13 đã cấm đúng điều này ("Không truyền đạt thông tin chỉ bằng màu").
- Đề xuất: Chưa vote = `arrowtriangle.up` (viền), đã vote = `arrowtriangle.up.fill`; thêm `.accessibilityAddTraits(isVoted ? .isSelected : [])`.
- Bằng chứng: DESIGN.md §13; HIG buttons/toggle: trạng thái phải nhìn thấy được bằng hình dạng chứ không chỉ màu.

### HIG-16 Một icon `slider.horizontal.3` cho năm việc khác nhau
- Màn / thiết bị: Viewer (Edit), Search (Advanced Search), Filter menu (Advanced Filter…), Collections + menu (Customize), Server browser (View Options) · mọi thiết bị
- Mức: gợi ý
- Ở đâu: APP (`PhotoDetailScreen.swift:701,709`, `RootTabView.swift:534`, `PhotoFilterMenu.swift:85`, `AlbumsScreen.swift:138`, `ServerBrowserScreen.swift:525`)
- Vấn đề: DESIGN.md §3 "Một hành động — một chỗ, cùng icon". Ngược lại ở đây: một icon, năm hành động. "Edit" trong viewer đáng ra là hành động nổi nhất của màn, lại giống hệt nút lọc.
- Đề xuất: Edit giữ `slider.horizontal.3` (Photos dùng đúng glyph này; từ điển §8 thêm dòng Edit). Advanced Search/Advanced Filter đổi sang `line.3.horizontal.decrease.circle` hoặc dùng chữ "Advanced" (đã có `AdvancedSearchButton`); Customize đổi sang `rectangle.3.group` hoặc chữ. Chi phí: đổi 4 chỗ, thêm 1 dòng vào từ điển.
- Bằng chứng: HIG "Prefer simple, recognizable symbols for items instead of text" và "Make sure the meaning of each control is clear" (toolbars); DESIGN.md §1.3, §8.

### HIG-17 Search tab: kết quả diễn giải là capsule thường, không phải token; bàn phím bật ngay che trang gợi ý
- Màn / thiết bị: Search · PH
- Mức: gợi ý
- Ở đâu: APP (`ShotDex/Features/Library/SearchSuggestionsScreen.swift:262-276` interpretationCapsule, `RootTabView.swift:200-216` `.tabViewSearchActivation(.searchTabSelection)`)
- Vấn đề: (a) Query "Sony 85mm" được app phân tích thành "brand Sony · focal 85mm" nhưng chỉ hiện làm một capsule chữ phẳng phía trên ô; người dùng không sửa/xóa được từng điều kiện mà phải gõ lại. HIG có component đúng cho việc này (token). (b) Search tab theo kiểu "standard tab" (có landing page với Recents/gợi ý) nhưng `searchTabSelection` bật ô tìm và bàn phím ngay khi vào tab, nên landing page bị bàn phím ăn mất và buộc app tự đếm số capsule vừa chỗ (`suggestionLimit`, `capsuleRowHeight 52`). HIG tách hai kiểu: standard (landing page) và button (bàn phím ngay).
- Đề xuất: Cân nhắc (a) `searchable(tokens:)` cho brand/focal/ISO để mỗi điều kiện là token sửa được (tốn: đổi mô hình `SearchService.preview`); (b) chọn một kiểu: hoặc giữ bàn phím bật ngay (kiểu button, bỏ landing page cố giữ chỗ) hoặc bỏ auto-activate để Recents hiện đủ. Quyết định (b) cần ảnh chụp; lý do hiện tại (mục `isFieldActive` ở comment) là người dùng phàn nàn "chạm đầu tiên không làm gì".
- Bằng chứng: HIG "Choose the standard tab style to provide suggestions, promote discovery, and encourage exploration." / "Choose the button appearance to help people quickly find what they need." và "Use tokens to filter by common search terms or items" (https://developer.apple.com/design/human-interface-guidelines/search-fields).

### HIG-18 Server Browser: Back hệ thống bị ẩn thay bằng chevron, và hai nút "chính" cạnh nhau ở iPad
- Màn / thiết bị: Server Browser · PH (Back), IP, DI (toolbar chọn)
- Mức: gợi ý
- Ở đâu: APP (`ShotDex/Features/ServerImport/ServerBrowserScreen.swift:40` `.navigationBarBackButtonHidden(true)`, `:403-418` Back/Forward, `:366-402` toolbar chọn ở regular width)
- Vấn đề: (a) Back là `chevron.backward` tự vẽ cùng `chevron.forward`, kèm lịch sử trong màn: hợp lý như Files, nhưng `navigationBarBackButtonHidden(true)` thường cũng vô hiệu cử chỉ vuốt từ mép trái; tôi chưa kiểm vuốt-back trên máy. (b) Khi đang chọn ở regular width, trailing có Share, Delete (đỏ), `Import N to Library` (borderedProminent), ⋯ và `Done` (semibold): hai thứ giống chính. Ngoài ra chữ "Import 12 to Library" dài có thể đẩy tiêu đề "N Selected" (đã có comment về chuyện "N Selec…").
- Đề xuất: (a) Giữ nút tự vẽ nhưng bật lại edge-swipe, hoặc dùng Back hệ thống khi lịch sử trống và chỉ tự vẽ khi có thư mục cha. (b) Chỉ một nút nổi: "Import" (prominent, trailing cuối); "Done" đổi thành `xmark` giống Library selection (`SelectionToolbarItems`), như DESIGN.md §10.6 đã chọn.
- Bằng chứng: HIG "Use the standard Back and Close buttons… If you create a custom version of either, make sure it still looks the same, behaves as people expect"; "Use the .prominent style for key actions such as Done or Submit… Only specify one primary action, and put it on the trailing side" (https://developer.apple.com/design/human-interface-guidelines/toolbars).

### HIG-19 Các chỗ nhỏ khác (gộp)
- Màn / thiết bị: Resize Presets, Filter menu, Selected Items, Customize · PH
- Mức: gợi ý
- Ở đâu: APP
- Vấn đề / Đề xuất:
  - `ShotDex/Features/Settings/CompressionPresetsScreen.swift:147`: `Slider` Quality không có nhãn trong chính slider (nhãn nằm ở `LabeledContent` riêng), VoiceOver đọc chỉ "80%". Thêm `.accessibilityLabel("Quality")`. (Slider Dim Photo ở `PhotoWidgetSettingsScreen.swift:366` đã làm đúng.)
  - `ShotDex/Features/Shared/PhotoFilterMenu.swift:55-70`: "All Items / Photos Only / Videos Only" là ba `Toggle` loại trừ nhau (mutually exclusive). Dùng `Picker` inline để có checkmark chọn một chuẩn của hệ; Toggle gợi ý bật nhiều.
  - `ShotDex/Features/Library/SelectedItemsSheet.swift:92`: mọi ô đều có label "Selected photo", VoiceOver không phân biệt được các ô. Đưa tên/ngày/giờ vào label.
  - `ShotDex/Features/Albums/CustomizeCollectionsSheet.swift:41-43`: chỉ có `Done`, không có Cancel/Back; thay đổi áp dụng tức thì nên chấp nhận được, nhưng HIG khuyên cặp đôi. Đổi nhãn thành "Close" hoặc dùng `xmark` để không hứa "xác nhận".
  - `ShotDex/Features/Settings/SettingsScreen.swift:438`: "Re-index Library" bắt đầu đọc lại toàn bộ thư viện (hàng nghìn ảnh iCloud) chỉ bằng một chạm, không xác nhận. Hủy được qua nút Cancel trong hàng tiến trình, nên chỉ ở mức gợi ý: thêm footnote nói "mất vài giờ" hoặc alert.
  - `ShotDex/Features/Library/SearchSuggestionsScreen.swift:208`: chuỗi hướng dẫn "Try: Fukuoka · f > 1.2 · ISO trên 3200 · trước 2020 · 85mm" trộn tiếng Việt ("trên", "trước") vào một chuỗi tiếng Anh, hiện cho mọi ngôn ngữ ở trạng thái rỗng. Nếu parser thực sự nhận cả hai tiếng thì để ví dụ theo locale; nếu không thì bỏ phần tiếng Việt khỏi chuỗi gốc.
- Bằng chứng: HIG pickers/menus/sheets (Done luôn cặp với Cancel hoặc Back, https://developer.apple.com/design/human-interface-guidelines/sheets); DESIGN.md §13.

### HIG-20 Board vẽ sai (không phải lỗi app)
- Màn / thiết bị: PH_AdvancedSearch, PH_ChartEditor, PH_LibrarySelect, PH_Search, PH_Duplicates, Main · PH
- Mức: gợi ý
- Ở đâu: BOARD
- Vấn đề: (1) PH_AdvancedSearch.png và PH_ChartEditor.png vẽ sheet đè lên chrome của màn bên dưới: nút Cancel/Save đè lên gear/Select/+ cũ, và tab bar vẫn hiện bên trong sheet. Một sheet thật che kín (hoặc dimmed) cả hai. (2) PH_LibrarySelect.png: menu ⋯ kéo dài xuống đè lên dòng "54,027 Photos, 1,204 Videos" và chồng lên caption "Show Selected (5・68.4MB)"; menu thật mở dưới nút ⋯ trong khoảng ~14 hàng, không đè bottom bar. (3) Nhiều chỗ còn `{{p.ft}}`, `{{c.name}}`, `{{k.k}}`, `{{p.meta}}` (template chưa điền), nút kính vẽ thành đĩa xám; PH_Duplicates.png vẽ bar "Delete 2 Photos" đè lên tab bar (code: bar nằm trong `safeAreaInset`, tab bar iOS 26 tự chừa). (4) PH_Search.png vẽ bàn phím trống ("{{k.k}}").
- Đề xuất: Sửa board trước khi dùng làm nguồn đối chiếu parity: điền template, bỏ chrome nền khi vẽ sheet, vẽ menu theo chiều cao thật.
- Bằng chứng: các PNG đã nêu trong `/Users/hoangtuan/Project/shotdex-ios/build/design/app/render/`.
