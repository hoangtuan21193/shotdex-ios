# ux-flow — luồng người dùng qua các màn (không chạy app; mọi thứ đọc từ code + board)

Quy ước: "APP" = lỗi nằm ở code Swift; "BOARD" = chỉ board vẽ sai. Mục nào phụ thuộc hành vi lúc chạy mà tôi không quan sát được thì ghi **chưa xác nhận** kèm thứ cần quan sát.
Các quyết định đã có trong docs/ mà tôi phản đối thì nói rõ là phản đối.

### UX-01 Resize: "Delete Originals" bật sẵn, nút chính không nói, xong thì đóng im lặng
- Màn / thiết bị: Compress (Resize) · PH, IP, DI, DC
- Mức: nên sửa (cao nhất — đây là thao tác xoá ảnh gốc hàng loạt)
- Ở đâu: APP (ShotDex/Features/Editing/CompressionScreen.swift:181-196 nút; :122-124 đóng thẳng; CompressionController.swift:48 mặc định; :151 `finishedCleanly`) · BOARD (PH_Compress vẽ toggle Delete Originals TẮT, code mặc định BẬT)
- Vấn đề: nhấn "Resize 8 Photos" / "Save to Photos" (nhãn y hệt dù toggle bật hay tắt). Với toggle bật (mặc định), sau khi lưu xong Photos hiện hộp xoá hệ thống cho cả 8 bản gốc mà người dùng không được báo trước ở nút. Nếu iCloud Photos bật, bản gốc bị xoá khỏi mọi thiết bị — hộp xác nhận của Upload sheet có nói câu này (ServerUploadSheet.swift:63-65), Resize thì không. Khi chạy sạch, màn tự `dismiss()` (docs FS-03.07 §5 cố ý bỏ summary) nên người dùng quay về lưới/album mà không có một dòng nào nói "đã lưu 8 bản, tiết kiệm 41 MB, 8 bản gốc ở Recently Deleted"; bản mới nằm xen cạnh bản gốc cùng ngày nên không thấy đâu là bản nào. Mục đích của công cụ là tiết kiệm dung lượng mà kết quả đó không được nói ra.
- Đề xuất: (1) khi toggle bật, nhãn nút đổi thành "Resize 8 Photos and Delete Originals" (hoặc dòng phụ 12pt dưới nút "Originals go to Recently Deleted"), tốn thêm 1 dòng ~16pt; (2) khi `finishedCleanly`, vẫn dismiss nhưng hiện toast/banner 3s trên lưới: "8 resized copies saved · 41 MB freed · Originals in Recently Deleted"; (3) tôi phản đối mặc định BẬT trong FS-03.07 §2 ("compress thường là thay thế"): mặc định an toàn là TẮT, vì bản copy luôn lưu được còn xoá thì chỉ tắt được ở bước sau hệ thống — nếu giữ BẬT thì ít nhất hai điều (1)(2) là bắt buộc. Chi phí: sửa chuỗi + một toast, không đụng pipeline.
- Bằng chứng: PH_Compress.png, DI_Compress.png; CompressionController.swift:48,151-158; docs/02-functional-spec/FS-03-photo-editor/07-resize-and-compression.md §2, §5.

### UX-02 Viewer: xoá/yêu thích thất bại thì không có gì xảy ra
- Màn / thiết bị: Viewer, Compare · tất cả thiết bị
- Mức: nên sửa (silent no-op — lỗi lặp lại nhiều nhất của app theo brief)
- Ở đâu: APP (PhotoDetailScreen.swift:1244-1256 `toggleFavorite` có `catch { }` rỗng; :1262-1285 `deleteCurrentPhoto` `catch { return }` gộp "người dùng huỷ" với "lỗi"; CompareScreen.swift:533-548 `performDelete` cũng `catch` rỗng)
- Vấn đề: chạm trái tim mà PhotoKit từ chối (quyền ghi, ảnh iCloud đang đồng bộ) → tim không đổi, không thông báo. Chạm thùng rác, hộp hệ thống hiện rồi hết, ảnh vẫn còn → người dùng không phân biệt được "tôi bấm Huỷ" và "app hỏng". Lưới (LibraryScreen.swift:391-403) và Duplicates làm đúng: tách `.userCancelled` khỏi lỗi thật rồi hiện alert.
- Đề xuất: dùng chung `AssetActionsCoordinator.perform` (đã có alert "Couldn't Update Photos" + lọc userCancelled, AssetActionsCoordinator.swift:268-281) cho cả ba chỗ thay vì ba bản copy `catch` riêng. Chi phí: nhỏ, xoá code thay vì thêm.
- Bằng chứng: các dòng trên; PhotoDetailScreen comment ":1261 User cancelled the system confirm, or the change failed — leave the viewer as is".

### UX-03 Support: gửi thất bại thì không thấy lỗi (chưa xác nhận)
- Màn / thiết bị: Support → Report a Bug / Request a Feature · PH, IP, DI, DC
- Mức: nên sửa
- Ở đâu: APP (SupportComposeScreen.swift:132-143; SupportScreen.swift:46-52)
- Vấn đề: lỗi mạng đặt vào `model.error`, mà alert đó gắn vào `SupportScreen` — tức màn nằm DƯỚI sheet soạn thư. Comment ở :139 tự ghi "the alert belongs to the screen underneath". SwiftUI không present alert của view cha khi sheet con đang mở, nên người dùng bấm Send, spinner quay, rồi nút Send hiện lại, không có chữ nào. Họ vừa gõ một báo cáo dài; đây là chỗ không được im lặng. **Cần quan sát:** tắt mạng trên sim, gửi một ticket, xem alert có hiện không (và có hiện sau khi sheet đóng không).
- Đề xuất: giữ lỗi trong chính `SupportComposeScreen` (alert hoặc dòng đỏ trong Form footer, kèm "Try Again" = Send) — `onSend` trả về `SupportError?` thay vì `Bool`. Cùng chỗ: Send bị tắt khi tiêu đề < 4 ký tự hoặc nội dung < 10 ký tự (:122-125) mà không nói điều kiện; thêm footer "Add a few more words" khi nút tắt và trường đã có chữ.
- Bằng chứng: SupportComposeScreen.swift:132-143; SupportModel.swift:66-85.

### UX-04 Duplicates ▸ Merge All Groups: ghi vào thư viện trước khi người dùng xác nhận, lỗi bị nuốt, và áp được cho Series
- Màn / thiết bị: Duplicates · PH, IP, DI, DC
- Mức: nên sửa
- Ở đâu: APP (DuplicatesModel.swift:300-349 `mergeAll`/`adoptMetadata`; DuplicatesScreen.swift:99-104 menu)
- Vấn đề: docs §8 nói "Merge không tự xoá — chỉ đánh dấu", nhưng `adoptMetadata` đã `performChanges` ghi favorite / vị trí / **ngày chụp sớm nhất** lên bản giữ lại ngay lúc bấm, trước nút đỏ "Delete N Photos". Người dùng bấm Merge, thấy thanh đỏ, rồi Clear Selection hoặc huỷ hộp xoá hệ thống → thư viện đã bị đổi ngày/vị trí mà không có gì nói và không đảo lại được trong app. `try?` (dòng 326) nuốt lỗi nên "chép xong mới đánh dấu" thực ra đánh dấu cả khi chép hỏng, trái với bất biến docs mô tả. Ở tab **Series** (loạt tư thế, docs §6 nói "thường là giữ vài tấm") menu vẫn bật và giữ đúng một khung/loạt. Không có phản hồi nào cho thấy đã đánh dấu bao nhiêu nhóm: các thẻ nằm ngoài màn hình, chỉ có thanh đỏ hiện lên.
- Đề xuất: (1) tắt "Merge All Groups" khi `strictness == .series`; (2) dời `adoptMetadata` về sau xác nhận xoá (làm trong `deleteMarked` ngay trước `deleteAssets`) hoặc đổi tên "Mark Smaller Copies in All Groups" nếu chỉ đánh dấu; (3) nếu giữ ghi trước, dùng `try` và dừng nhóm đó khi lỗi; (4) sau khi merge, scroll tới nhóm đầu và hiện toast "Marked 19 photos in 12 groups". Tôi không phản đối quyết định "Merge" của docs, chỉ phản đối chuyện ghi sớm.
- Bằng chứng: DuplicatesModel.swift:300-349; docs/02-functional-spec/FS-06-collections/06-duplicates.md §6, §8.

### UX-05 Duplicates: có thể đánh dấu cả nhóm, và đổi tab Exact/Similar/Series lặng lẽ làm rơi dấu
- Màn / thiết bị: Duplicates · PH, IP, DI, DC
- Mức: nên sửa
- Ở đâu: APP (DuplicatesModel.swift:249-255 `toggleMark`; :149-164 `apply` chạy `intersection(liveIds)`; :45-51 `strictness.didSet` → `loadCache`)
- Vấn đề: (a) chạm hết mọi ô của một nhóm → "Delete 3 Photos" xoá sạch mọi bản của ảnh đó; thanh đỏ chỉ ghi tổng, không nói nhóm nào đã hết ảnh. (b) Đổi tab → `loadCache` → `apply` cắt `markedForDeletion` về các id có trong tab mới. Đánh dấu 6 ảnh ở Similar, sang Exact xem thử, trở lại: dấu đã mất và số trên thanh đỏ tụt, không lời nào. (c) Chạm ô = đánh dấu xoá, không có đường mở ảnh to ngoài Compare; với nhóm Series > 4 khung người dùng đành đánh dấu theo hình 100pt.
- Đề xuất: (a) khi một nhóm sắp bị đánh dấu hết, ô cuối bật viền vàng + footer thẻ "All copies marked — nothing will be kept" (hoặc chặn chạm cuối, hint "Keep at least one"); (b) giữ `markedForDeletion` nguyên khi đổi tab (chỉ lọc lúc xoá, vì id vẫn hợp lệ) hoặc ghi trên thanh "N marked in other tabs"; (c) giữ nguyên "Compare là đường chính" của docs §7 nhưng cho Compare mở với số ảnh bất kỳ (kiểm tra `CompareScreen` với nhóm lớn) — ngoài phạm vi ở đây.
- Bằng chứng: PH_Duplicates.png (thanh đỏ chỉ có tổng); DuplicatesModel.swift như trên.

### UX-06 Thành công im lặng ở hầu hết hành động hàng loạt; chỉ Hide và Copy có toast
- Màn / thiết bị: Library chọn nhiều (LibrarySelect), Album, Viewer · PH, IP, DI, DC
- Mức: nên sửa
- Ở đâu: APP (AssetActionsCoordinator.swift:68 `toastMessage` chỉ gán ở :136 và :220; AddToCollectionSheet.swift:105-137 `dismiss()` không kèm gì; LibraryScreen.swift:649-675 Duplicate; AdjustLocationSheet.swift ~:88-97 "Remove Location")
- Vấn đề: sau Add to Collection sheet đóng, mất selection (`onAdded: stopSelecting`, LibraryScreen.swift:216-219) — không có dòng "Added 12 to Trip 2025", không nói trùng bao nhiêu (PhotoKit coi thêm lại là no-op nên "đã có sẵn" không bao giờ hiện). Duplicate thì ngược lại: giữ selection (có lý do trong comment) nhưng cũng không nói gì; bản sao cùng ngày nằm kề bản gốc, người dùng không biết đã tạo hay chưa. Favorite hàng loạt, Adjust Date & Time, Adjust Location: sheet đóng, không toast. "Remove Location" áp NGAY cho cả lô (tiêu đề "Adjust 12 Photos" nhưng nút không nêu số) và không hỏi, không toast. Với Hide (UX-07) và Copy toast có, Favorite/Date/Location thì không: cùng một coordinator, hai quy tắc.
- Đề xuất: một toast chung dùng `ActionToast` sẵn có, 2.5s, sau mọi `perform` thành công: "Added 12 to Trip 2025", "Duplicated 12 photos", "Favorited 12", "Date moved 3 days earlier", "Location removed from 12 photos". Với Add to Collection thêm nút "Show" mở album. "Remove Location" đổi nhãn thành "Remove Location from 12 Photos" khi batch. Chi phí: ~6 chuỗi và 1 hàm; không thêm dialog (đây là hành động rẻ, không cần xác nhận — nhưng bản Remove Location hàng loạt nên thêm toast có Undo vì không có cách khôi phục trong app).
- Bằng chứng: AssetActionsCoordinator.swift:96-260; PH_LibrarySelect.png (menu có Favorite / Adjust Date / Adjust Location).

### UX-07 Hide là cửa một chiều: không hỏi, ảnh biến mất, toast không nói tìm lại ở đâu
- Màn / thiết bị: Library chọn nhiều, Viewer · PH, IP, DI, DC
- Mức: nên sửa
- Ở đâu: APP (SelectionBarViews.swift:352-362 `role: .destructive`, nhánh "Unhide"; AssetActionsCoordinator.swift:128-140)
- Vấn đề: docs FS-01.06 đã ghi Hide ghi được nhưng không đọc lại được nên app không có Hidden/Unhide — tôi không phản đối quyết định đó. Hệ quả chưa ai xử lý: bấm Hide là 12 ảnh biến khỏi lưới, album, thống kê ngay (không hộp xác nhận), toast 1.6s "12 Photos Hidden" mà không nói chúng ở "Hidden" trong app Photos, và nhánh "Unhide" (`allHidden`) gần như không bao giờ chạm tới vì ảnh ẩn không đọc được. Người dùng nghĩ ảnh bị xoá.
- Đề xuất: đổi toast thành "12 photos hidden · Find them in Photos › Hidden" (kéo dài tới 4s, 2 dòng), kèm nút "Undo" trong 6s nếu `performChanges` với `PHAsset` còn cầm trong tay vẫn dùng được (**chưa xác nhận** — cần thử trên máy thật: Hide rồi gọi `setHidden(false, for: assets)` bằng đối tượng cũ). Xoá nhánh Unhide chết hoặc để nó đi kèm một chú thích. Chi phí: chuỗi + 1 closure.
- Bằng chứng: docs/02-functional-spec/FS-01-library/06-multi-select.md dòng 109; docs FS-06.01 dòng 99.

### UX-08 Lần chạy đầu: Statistics và Duplicates báo "No Indexed Photos" trong lúc đang index và bảo người dùng tự đi index
- Màn / thiết bị: Statistics, Duplicates · PH, IP, DI, DC (first-run, 55k ảnh có thể mất hàng giờ)
- Mức: nên sửa
- Ở đâu: APP (StatisticsScreen.swift:137-142; DuplicatesScreen.swift:225-230; `isIndexing` đã truyền vào StatisticsScreen:13 nhưng chỉ dùng cho Insights :185; StatisticsModel.load() chỉ chạy lúc `.task`)
- Vấn đề: người dùng vừa cấp quyền, chuyển sang tab Statistics và đọc "Statistics appear after your library has been indexed" (không tiến độ, không số liệu một phần, không nói đang chạy). Duplicates còn nói "Index your library from the Library tab" — trong khi indexing tự chạy, không có nút nào để "index". Nếu ở lại tab khi index xong, số liệu không tự làm mới (model chỉ nạp ở `.task`) — **chưa xác nhận**, cần quan sát: để Statistics mở lúc index chạy tới 100%.
- Đề xuất: khi `isIndexing`, thay empty state bằng cùng thẻ tiến độ của Library ("Reading photo and video info · 34% — Statistics fill in as photos are read") và vẫn vẽ các biểu đồ trên phần đã đọc, kèm nhãn "Partial · 34% read"; làm mới model theo `indexProgress`/khi `isIndexing` đổi true→false. Duplicates: đổi chữ thành "ShotDex is still reading your library (34%). Duplicates can be found once it finishes." và một nút "Show Progress" nhảy về tab Library. Chi phí: ~1 view dùng chung + một `onChange`.
- Bằng chứng: PH_Statistics.png (board vẽ trạng thái đã có số liệu, không vẽ first-run); LibraryScreen.swift:796-835 là nơi tiến độ đã được làm tốt.

### UX-09 Mục menu bị tắt mà không cho biết lý do; mục khác thì biến mất
- Màn / thiết bị: Library chọn nhiều · PH, IP, DI, DC
- Mức: nên sửa
- Ở đâu: APP (SelectionBarViews.swift:230-234 Collage `.disabled(!supportedCounts.contains(...))`; :163-164 `.disabled(selectionCount < 2)` của Compare; LibraryScreen.swift:585-587 Paste Edits chỉ có khi `editClipboard.hasContent`)
- Vấn đề: chọn 12 ảnh, "Create Collage" xám — không nói giới hạn 2–9 (CollageTemplateCatalog.supportedCounts). Paste Edits làm ngược: hàng biến mất khi clipboard rỗng, trong khi FS-01.09 §2 (và Combine Photos) quy ước "dim, never vanish" để hàng còn nói được nó làm gì. Bản thân "Copy Edits" đã bị bỏ khỏi editor (canvas decisions 30/9), nên người dùng không bao giờ biết có Paste Edits.
- Đề xuất: hàng menu hai dòng (UploadToServerMenuRow dùng cùng kỹ thuật, SelectionBarViews.swift:445-460): "Create Collage" + phụ "Pick 2–9 photos"; Paste Edits luôn hiện, xám, phụ "Copy edits from a photo first". Chi phí: 0 pt layout (menu hệ thống), 3 chuỗi.
- Bằng chứng: PH_LibrarySelect.png, DI_LibrarySelect.png; CollageTemplateCatalog.swift:31.

### UX-10 Một thứ, nhiều tên: Collection / Album / Your Albums / My Albums
- Màn / thiết bị: Collections, AlbumDetail, menu chọn nhiều, AddToCollectionSheet · tất cả
- Mức: nên sửa
- Ở đâu: APP (SelectionBarViews → PhotoCommand.addToCollection "Add to Collection"; AddToCollectionSheet.swift:49 section "Your Albums", :31-38 "New Album…", alert "Couldn't Add to Collection" :90; menu "Remove from Album" SelectionBarViews.swift:365; AlbumsScreen.swift:281 "My Albums"; PhotoWidgetPickers "Choose Album")
- Vấn đề: người dùng chọn "Add to Collection", thấy hộp tên "Add to Collection" nhưng các hàng là "Your Albums" và nút "New Album…"; ở tab Collections cùng nhóm đó tên "My Albums"; lệnh đối ứng là "Remove from Album". "Collections" là tên tab (gom Albums + Places + Utilities), còn album là một mục trong đó; dùng nó cho lệnh thêm vào *một album* sai nghĩa.
- Đề xuất: lệnh là "Add to Album" (khớp "Remove from Album", "New Album…", "Choose Album", và Photos); "Collections" chỉ dành cho tab. Sửa `PhotoCommand.addToCollection` title + sheet title + alert; "Your Albums" → "My Albums". (Đã có agent copy-consistency lo chuỗi; tôi nêu vì đây là cặp lệnh đối ứng trong cùng một menu.)
- Bằng chứng: PH_LibrarySelect.png ("Add to Collection" cạnh nhóm Remove from Album ở album); PhotoCommand.swift:44.

### UX-11 Upload: câu hỏi "Replace / Keep Both / Skip" có công tắc áp-cho-tất-cả nằm DƯỚI các nút trả lời
- Màn / thiết bị: ServerUpload (conflict) · PH, IP, DI, DC
- Mức: nên sửa
- Ở đâu: APP (ServerUploadSheet.swift:396-402)
- Vấn đề: thứ tự đọc là Replace → Keep Both → Skip → "Apply to Remaining Conflicts". Người dùng chạm Replace (ghi đè file trên server) ngay khi thấy, rồi mới thấy công tắc; muốn "áp cho tất cả" phải bật công tắc TRƯỚC rồi mới bấm nút — thứ tự ngược với vị trí. Nếu họ bật xong bấm Replace, mọi xung đột sau đều bị ghi đè không hỏi.
- Đề xuất: đặt công tắc ngay dưới hai ảnh So sánh, trên ba nút; nhãn "Do this for all remaining conflicts"; khi bật, nút Replace đổi thành "Replace All" (đỏ) và Skip thành "Skip All". Chi phí: đổi thứ tự 2 Section, không thêm chiều cao.
- Bằng chứng: ServerUploadSheet.swift:395-407; PH_ServerUpload.png.

### UX-12 Uploaded to Server: nút "giải phóng dung lượng" — mục đích của màn — nằm trong ⋯ và không nói được bao nhiêu MB
- Màn / thiết bị: UploadedToServer · PH, IP, DI, DC
- Mức: gợi ý
- Ở đâu: APP (UploadedToServerScreen.swift:62-73 menu ⋯; :80 alert)
- Vấn đề: người dùng tải 4 GB RAW lên NAS rồi vào màn này để dọn máy, thấy hai danh sách và một ⋯. Hành động chính bị giấu; số "Delete 214 from This Device" không cho biết giải phóng bao nhiêu GB. Mục Delete tắt xám khi `deletable.isEmpty` mà không nói tại sao (ảnh chỉ upload một phần xem ở sheet kết quả, không ở đây). Sau khi xoá xong cũng không có phản hồi (mục biến mất).
- Đề xuất: một hàng đầu danh sách "Free Up Space — 214 photos · ~4.2 GB" (nút đỏ nhạt, mở cùng alert) dưới dòng chú thích "Verified on a server"; tắt thì ghi lý do ("Nothing fully verified yet"); sau khi xoá toast "214 photos moved to Recently Deleted". Số byte lấy từ `fileSize` đã index. Chi phí: ~56pt một hàng.
- Bằng chứng: UploadedToServerScreen.swift:56-76; PH_UploadedToServer.png.

### UX-13 Sheet upload: xoá ảnh sau upload không có phản hồi, mục Delete biến mất
- Màn / thiết bị: ServerUpload (kết quả) · tất cả
- Mức: gợi ý
- Ở đâu: APP (ServerUploadModel.swift:387-401 `deleteUploaded` đặt `deletableAssetIds = []`; ServerUploadSheet.swift:236-249)
- Vấn đề: sau khi người dùng xác nhận xoá, dòng đầu vẫn nói "Uploaded 214 photos…", nút xoá biến mất, không có chữ "214 moved to Recently Deleted". Cũng không có chỗ nói chuyện gì xảy ra nếu hộp hệ thống bị huỷ (nút vẫn đó — đúng). Selection của lưới vẫn giữ id đã xoá.
- Đề xuất: thay Section Delete bằng một dòng xám "214 photos moved to Recently Deleted" (có biểu tượng tick) sau khi thành công. Chi phí: một state `deletedCount`.
- Bằng chứng: ServerUploadModel.swift:387-401.

### UX-14 Settings: "Re-index Library" một chạm, không nói tốn bao lâu; "Clear Index" không nói hệ quả với Statistics/Duplicates
- Màn / thiết bị: Settings · PH, IP, DI, DC
- Mức: gợi ý
- Ở đâu: APP (SettingsScreen.swift:437-441 nút Re-index không xác nhận; :960-964 alert Clear Index)
- Vấn đề: ở 55k ảnh, đọc lại từ đầu là hàng giờ trên cellular/iCloud (docs/_intents về WiFi stall). Có Cancel và có tiến độ nên tôi không đòi hộp xác nhận (hành động huỷ được, hộp là thừa). Nhưng nhãn không nói quy mô; alert Clear Index chỉ nói "reads again the next time" — không nói Statistics, Duplicates, bộ lọc sẽ trống tới khi xong (UX-08).
- Đề xuất: dòng phụ dưới Re-index: "Reads all 54,971 photos again. Takes a while; you can keep using ShotDex." Alert Clear Index thêm câu: "Statistics and filters stay empty until indexing finishes." Chi phí: 2 chuỗi.
- Bằng chứng: SettingsScreen.swift:425-442, 958-965.

### UX-15 Ô tìm kiếm trống lần đầu: gợi ý "Try:" lẫn tiếng Việt vào UI tiếng Anh
- Màn / thiết bị: Search · PH, IP, DI, DC
- Mức: gợi ý
- Ở đâu: APP (SearchSuggestionsScreen.swift:208)
- Vấn đề: chuỗi "Try: Fukuoka · f > 1.2 · ISO trên 3200 · trước 2020 · 85mm" — "trên", "trước" là từ khoá tiếng Việt của parser, lại hiện cho người dùng tiếng Anh; "Fukuoka" là nơi chốn của tác giả. Đây là dòng duy nhất dạy cú pháp tìm kiếm ở lần chạy đầu.
- Đề xuất: ví dụ theo ngôn ngữ giao diện ("ISO over 3200 · before 2020"), và "Fukuoka" thay bằng chuỗi lấy từ nơi/máy ảnh có thật trong thư viện khi đã index (code ngay phía trên đã làm vậy cho suggestions). Chi phí: 1 chuỗi localized.
- Bằng chứng: SearchSuggestionsScreen.swift:204-211.

### UX-16 Form kết nối server: có thể Lưu mà chưa Test; "Test Connection" nằm cuối form, dưới danh sách máy tìm thấy
- Màn / thiết bị: ServerForm · PH, DI, DC (form dài, 669pt trên Duo)
- Mức: gợi ý
- Ở đâu: APP (FileServerFormScreen.swift:151-153 Found servers đứng đầu form; :208-223 Test; :247-249 Save chỉ cần `canSave` + password) · BOARD (PH_ServerForm chồng danh sách "File Servers" lên form — lỗi vẽ board, không phải app)
- Vấn đề: Save ở thanh trên đủ để lưu mà không thử kết nối; Test Connection ở đáy sau 6 section. Với 5 máy tìm thấy (board), Name/Host bị đẩy xuống ~380pt. Người dùng nhập xong, bấm Save (đã ở tầm ngón cái) và chỉ biết sai host khi upload thất bại ở bước sau — trong chính sheet Upload (ServerUploadSheet khi `onSaved` chọn kết nối này).
- Đề xuất: khi Save mà `test == .idle`, chạy test ngầm và chỉ cảnh báo nếu lỗi ("Couldn't reach nas.local — Save Anyway / Edit"), vì NAS offline vẫn là trường hợp hợp lệ để lưu. Hoặc thu gọn "Servers Found" còn 3 hàng + "Show More". Chi phí: một alert, không đổi layout.
- Bằng chứng: FileServerFormScreen.swift:150-250; PH_ServerForm.png.

### UX-17 Compare mở từ Library: chạm ảnh = đánh dấu xoá; từ Duplicates: xoá 1 ảnh là thoát cả màn
- Màn / thiết bị: Compare · PH, IP, DI, DC
- Mức: gợi ý
- Ở đâu: APP (CompareScreen.swift:453-475 hint, :512-530 `deleteMarked` → `dismiss()` khi `didDelete`)
- Vấn đề: người vào Compare từ chế độ chọn của Library để so độ nét sẽ chạm/chụm; một cú chạm đánh dấu ảnh để xoá (có hint "Tap a photo to mark it for deletion" nhưng chỉ tới khi đánh dấu đầu tiên). Từ Duplicates với nhóm 4 ảnh: đánh dấu 1, bấm Delete → màn đóng dù còn 3 ảnh đang so sánh dở.
- Đề xuất: khi `onDeleteMarked` trả `true`, chỉ đóng nếu còn < 2 thẻ (như nhánh `performDelete` ở :543); chạm mở chế độ so sánh/zoom, đánh dấu bằng biểu tượng thùng rác ở góc thẻ — nhưng đây là quyết định thiết kế của FS-01.08 ("cả thẻ là control"), tôi chỉ phản đối phần đóng sớm.
- Bằng chứng: CompareScreen.swift:512-548; PH_Compare.png.

### UX-18 Upload: rời app là dừng — người dùng có 40 GB RAW chỉ nhận một dòng chú thích
- Màn / thiết bị: ServerUpload · PH
- Mức: gợi ý
- Ở đâu: APP (ServerUploadSheet.swift:51-55 `.background → model.cancel()`; :312-316 footer "Keep ShotDex open")
- Vấn đề: thiết kế đã được ghi (iOS cho nền vài giây, nửa file RAW vô dụng) và có "Upload Remaining" để tiếp tục, nên khôi phục được. Chỗ thiếu: lúc bấm Upload đã không nói lô này ước tính bao lâu (có `secondsLeft` ở progress nhưng chưa có ở prepare), và khi quay lại app sau cuộc gọi, kết quả "not uploaded yet" là nơi duy nhất báo.
- Đề xuất: ở footer prepare thêm "~42 GB · about 1 h 10 min on this network" sau khi đã đo tốc độ 1 file đầu; khi bị đẩy xuống nền, hiện local notification "Upload paused — open ShotDex to continue (118 of 340 sent)". Chi phí: 1 notification (cần quyền; app hiện không xin quyền thông báo ở chỗ này — cân nhắc).
- Bằng chứng: ServerUploadSheet.swift:51-55.

### UX-19 Lỗi BOARD cần sửa trước khi board làm bằng chứng
- Màn / thiết bị: Duplicates, Compress, ServerForm, Statistics, LibrarySelect · PH (các DI/DC tương tự)
- Mức: gợi ý
- Ở đâu: BOARD
- Vấn đề: (a) PH_Duplicates còn nguyên `{{c.title}}`, `{{p.c1}}`, `{{p.c2}}` (chưa điền dữ liệu) và vẽ nút "Delete 2 Photos" xám như đang disabled trong khi code là nút đỏ `.borderedProminent` đang bật. (b) PH_Compress vẽ "Delete Originals" TẮT, code mặc định BẬT (CompressionController.swift:48) — board che mất đúng điểm UX-01. (c) PH_ServerForm chồng danh sách File Servers lên form. (d) PH_Statistics: biểu đồ mất thanh, hàng cuối đè thanh tab. (e) PH_LibrarySelect: menu ⋯ đè lên lưới và chữ "54,0xx Photos, 1,204 Videos" chồng lên hàng "Hide". Không có board nào vẽ trạng thái first-run/đang index/rỗng của Statistics, Duplicates (Not Scanned Yet / Scanning N of M / No Duplicates), Collections, Trips — nên các trạng thái UX-08 không có chỗ kiểm.
- Đề xuất: vẽ lại 4 board trên và thêm artboard cho: Statistics đang index, Duplicates "Scanning 4,200 of 55,000" + Cancel, Duplicates rỗng, ServerUpload "File Already Exists", UploadedToServer rỗng. Chi phí: 5 artboard.
- Bằng chứng: PH_Duplicates.png, PH_Compress.png, PH_ServerForm.png, PH_Statistics.png, PH_LibrarySelect.png.

## Đã kiểm tra và thấy ổn (không có phát hiện)
- Indexing 55k: có token ở toolbar (% + popover), thẻ chi tiết với Cancel, trạng thái chờ Wi-Fi/Use Cellular và đếm ngược iCloud retry (LibraryScreen.swift:759-1060) — đủ tiến độ + huỷ.
- Duplicates quét: Scanning N of M + Cancel, ghi sau mỗi lô nên huỷ giữa chừng không mất (DuplicatesModel.swift:184-216).
- Resize đang chạy: scrim nuốt chạm, tiến độ, Cancel có xác nhận "Remove Copies", huỷ lúc tải iCloud không hỏi (CompressionScreen.swift:274-340).
- Quyền ảnh: Not Determined → Onboarding; Denied → Open Settings; Restricted có chữ; Limited có banner + Manage (LibraryScreen.swift:70-83, 1219-1262, FS-09 §3).
- Xoá Album, xoá kết nối server, Settings destructive: đều có xác nhận nói rõ ảnh không bị ảnh hưởng.
