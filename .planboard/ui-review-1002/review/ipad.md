# ipad — review iPad 13" (1376×1032 ngang; kiểm thêm 1032×1376 dọc khi nói tới độ rộng canvas)

Đã đọc: DESIGN.md §10.1c–f (luật màn rộng), CLAUDE.md, 36 board `IP_*`, và code của từng màn được nêu. Không chạy sim (brief: chỉ đọc). Chỗ nào cần quan sát runtime thì ghi "chưa xác nhận".

Quy ước "Ở đâu": APP = lỗi nằm trong code; BOARD = chỉ board vẽ sai/thiếu.
Nhận xét chung: dự án đã làm tốt phần lớn "iPad nghiêm túc" cho Editor, Collage, Settings (split view), Statistics (2–3 cột), lưới ảnh (hover highlight, drag, context menu trong UICollectionView), Collections (tile 132→192). Các finding dưới đây là những màn **còn ở dạng điện thoại phóng to** hoặc **chưa có đường bàn phím**.

---

### IP-01 Photo Info trong Viewer là sheet che ảnh; iPad cần inspector đứng cạnh ảnh
- Màn / thiết bị: Viewer → Photo Info · IP (cả ngang lẫn dọc)
- Mức: nên sửa
- Ở đâu: APP (`Features/Library/PhotoDetailScreen.swift:356-362` — `.sheet(isPresented: $isMetadataPresented)` với `.presentationDetents([.medium, .large])`)
- Vấn đề: ở regular width `.medium/.large` bị bỏ qua, sheet thành form/page sheet ~700×850 giữa màn (xem `IP_Metadata.png`: cột 340–1040, ảnh còn lại hai dải 340pt mỗi bên bị làm mờ). Người dùng đang soi EXIF để so với ảnh — ảnh bị che hơn nửa và không vuốt sang ảnh kế được khi sheet mở (sheet modal chặn pager). Với nhiếp ảnh gia đây là hành động lặp lại nhất trong Viewer. Ngoài ra nội dung sheet là lưới 2 cột nhãn/giá trị 700pt, đọc dở vì phải kéo cuộn (Capture Settings bị cắt ở đáy board).
- Đề xuất: ở `horizontalSizeClass == .regular` thay sheet bằng **inspector cột phải 340–380pt** (`.inspector(isPresented:)` iOS 17+ hoặc HStack tự dựng như `EditorSidebar`), cột này nằm sát cạnh phải (ngón cái cầm máy với tới). Pager co lại còn ~1000pt, vẫn dư. Nút ⓘ và phím `I` (đã có) bật/tắt cột; vuốt sang ảnh khác thì cột đổi nội dung theo, không đóng. Tốn: chiều rộng (đang dư), không tốn chiều cao. Giữ nguyên sheet trên compact. `onSwipeUp` (dòng ~237) vẫn mở cột. Không phá luật DESIGN nào (tier không áp dụng cho màn này); §10.1c ("nhiều nội dung hơn") ủng hộ.
- Bằng chứng: `IP_Metadata.png`, `IP_Viewer.png`; HIG Modality ("Use a sheet to ... a task that the user finishes and dismisses" — Photo Info không phải việc cần "xong") https://developer.apple.com/design/human-interface-guidelines/modality (chưa fetch lại trong phiên này, coi là chưa xác minh trích dẫn).

### IP-02 Library không có đường lọc theo máy/ống kính ngay trên iPad; "Advanced Filter…" là sheet 700pt rồi mới thấy kết quả
- Màn / thiết bị: Library, AdvancedSearch · IP
- Mức: nên sửa (gợi ý nếu coi là ngoài phạm vi đợt này)
- Ở đâu: APP (`Features/Shared/PhotoFilterMenu.swift:40-100` — chỉ Favorites/Photos/Videos/Capture Kind + "Advanced Filter…"; `Features/Library/AdvancedSearchSheet.swift` — sheet)
- Vấn đề: giá trị cốt lõi của ShotDex là lọc theo camera/lens/tiêu cự/ISO, nhưng trên iPad nó nằm sau menu `≡` → "Advanced Filter…" → sheet 700×840 (`IP_AdvancedSearch.png`) có đếm "Matches 1284 photos" ngay trong sheet nhưng lưới bị che; bấm Search mới thấy ảnh, muốn chỉnh ISO 800→1600 phải mở lại. Lưới ở 1376pt có 13 cột, dư hẳn một cột 320pt mà không tốn gì.
- Đề xuất: ở regular width, thêm **cột lọc bên phải (inspector 320pt) toggle từ nút filter trên toolbar**, chứa đúng `RuleBuilderSections` (đã dùng chung cho Smart Album và Chart editor) + các toggle nhanh của `PhotoFilterMenu`. Áp dụng **trực tiếp, debounce ~300ms**, lưới đổi theo; "Save as Smart Album" là nút ở chân cột. Cùng cột đó dùng lại được ở AlbumDetail/SmartAlbum (FS-06.09 đã tách phạm vi). Tốn: ~320pt chiều rộng lưới (13 → 10 cột, ô vẫn ~100pt theo §10.1c); effort vừa vì `RuleBuilderSections` và `matchCount` đã có. Sidebar kiểu Photos (điều hướng) thì **không** đề xuất — tab bar nổi trên cùng đã làm việc đó; cái thiếu là bộ lọc, không phải điều hướng. Phải nói rõ: đề xuất này mâu thuẫn FS-01.05 §5 ở chỗ Advanced loại trừ quick filter (mutually exclusive) — cột mới cần quyết định hai thứ cùng bật được hay không.
- Bằng chứng: `IP_AdvancedSearch.png`, `IP_Library.png`; code dòng nêu trên.

### IP-03 Duplicates: mỗi nhóm một thẻ rộng 1344pt, ~80% rỗng; nút Delete trải 1320pt ở đáy
- Màn / thiết bị: Duplicates · IP
- Mức: nên sửa
- Ở đâu: APP (`Features/Duplicates/DuplicatesScreen.swift:57-62` — `ForEach(model.groups)` trong một cột; `:304` `GridItem(.adaptive(minimum: 100))`; `:235-263` `deleteBar` full-width)
- Vấn đề: nhóm 2–4 ảnh (case phổ biến nhất) là 2–4 ô vuông ~100pt trong thẻ 1344pt → 230–460pt có nội dung, còn lại trống; màn dài gấp 3–4 lần cần thiết, và ô 100pt là quá nhỏ để chọn "ảnh nào nét hơn" — việc duy nhất màn này tồn tại để làm (phải bấm Compare). Nút "Delete N Photos" 1320×50 nằm chính giữa đáy: xa cả hai ngón cái, và là nút phá hủy duy nhất, to nhất màn.
- Đề xuất: ở regular, **master–detail**: cột trái 360pt danh sách nhóm (thumbnail dải + "3 Photos · ~12 MB"), pane phải hiển thị nhóm đang chọn với ô **to (~300pt, 2–4 cột)** kèm EXIF dòng dưới mỗi ô (kích thước, ngày — dữ liệu đã có trong `DuplicateMember`), tức là tích hợp luôn Compare. Phương án rẻ: `LazyVGrid` 2–3 cột thẻ nhóm (`adaptive(minimum: 420)`) và ô minimum 140. Nút Delete: ghim vào **cột phải/đáy pane phải, rộng ≤ 360pt, sát cạnh phải**. Tốn: effort vừa; không tốn chiều cao.
- Bằng chứng: `IP_Duplicates.png` (khung board bị hỏng — xem IP-16 — nhưng nút Delete và dải Segmented trải full width là thật, khớp code); code dòng nêu trên.

### IP-04 Trips: thẻ cover 1344×160 (tỉ lệ 8.4:1) một cột
- Màn / thiết bị: Trips · IP
- Mức: nên sửa
- Ở đâu: APP (`Features/Places/TripsScreen.swift:35-52` `LazyVStack` một cột, `:86` `static let height: CGFloat = 160`, `:108` `.frame(maxWidth: .infinity)`)
- Vấn đề: đây chính là "phone layout blown up" mà §10.1d cấm nói rõ ("một banner đơn độc tỉ lệ cố định không đủ điều kiện"): cover là ảnh để *nhận ra chuyến đi* nhưng 8.4:1 chỉ còn một dải ảnh đen lẫn cây; tên chuyến và ngày dính mép trái cách số liệu 1300pt. Trips không có trong danh sách đóng của §10.1d (chỉ `AlbumTileMetrics`) nên chưa được hưởng ngoại lệ.
- Đề xuất: `LazyVGrid(columns: [.adaptive(minimum: 320, maximum: 440)])` ở regular → 3 cột 430pt, và `height` 160 → **~240 ở regular** (tỉ lệ ≈ 16:9 gần hơn). Đây là *thêm nội dung* (3 chuyến/hàng) chứ không phóng to. Cover request đã dùng `ActiveDisplay.size.width × height` (dòng ~131) — đổi thành width của cột để khỏi tải ảnh gấp 3 cần thiết. Phải thêm "Trips" vào danh sách đóng §10.1d nếu cho cover to lên theo trục dọc; hoặc giữ 160 và chỉ chia cột (không cần sửa luật).
- Bằng chứng: `IP_Trips.png` (khung cover 1344×~160 thật, placeholder `{{p.title}}` là lỗi board), code.

### IP-05 Search: thẻ Recents vuông 437×437 chiếm 43% chiều cao, ảnh thu nhỏ 320px bị phóng gần 3×
- Màn / thiết bị: Search · IP
- Mức: nên sửa
- Ở đâu: APP (`Features/Library/SearchSuggestionsScreen.swift:178-183` `GridItem(.flexible())` × 3, `:333` `.aspectRatio(1, .fit)`, `:~322` `thumbnailPixels = 320`)
- Vấn đề: 3 cột flexible trên 1376pt cho thẻ (1376−40−24)/3 ≈ **437pt**, chiều cao cũng 437 (`IP_Search.png`: y 244→681), trong khi chữ trong thẻ là `.footnote` 13pt. Ảnh thumbnail xin 320px (comment: "a third of the widest phone at 2×") nên trên iPad 2× hiển thị cần ~874px → mờ ~2.7×. Thẻ chỉ có vai trò "nhắc lại truy vấn" nhưng ăn gần nửa màn, đẩy các gợi ý/kết quả xuống.
- Đề xuất: ở regular dùng `GridItem(.adaptive(minimum: 150, maximum: 200))` (hoặc cố định 180pt) và tăng `maximumCards` 3 → 6 (iPad dư chỗ — "nhiều hơn chứ không to hơn", §10.1c); `thumbnailPixels` đổi theo cạnh thật (`side * scale`). Tốn: không gì; thêm 3 truy vấn gần đây.
- Bằng chứng: `IP_Search.png`; code dòng nêu trên.

### IP-06 Compress: cột 700pt giữa màn, preview 250–320pt, nút Save nằm giữa — nên là 2 pane
- Màn / thiết bị: Compress (Resize) · IP
- Mức: nên sửa
- Ở đâu: APP (`Features/Editing/CompressionScreen.swift:117` `maximumFormWidth = 700`, `:147-148` `previewHeight = assets.count == 1 ? 320 : 250`, `:180-192` nút full-width trong cột)
- Vấn đề: tranh luận trực tiếp với quyết định trong code (comment dòng 130-137: "một segmented control kéo dài 1032pt là ba chữ cách nhau một bàn tay"). Đúng về form, nhưng cách chữa (cột 700 giữa) để lại hai dải đen 338pt mỗi bên và **preview chỉ 660×250 trong màn 1032pt cao** — màn này tồn tại để người ta *xem thử chất lượng/kích thước*, và preview là thứ duy nhất được thu nhỏ. Nút "Resize 8 Photos" nằm giữa màn: không ngón cái nào với tới, và khi có nhiều ảnh nó ở cuối cuộn (`IP_Compress.png`: y=770–820, nhưng form 8 ảnh + giải thích có thể dài hơn).
- Đề xuất: ở regular, `HStack`: **preview/gallery trái chiếm phần còn lại (~900×900)**, **cột điều khiển phải 400pt** (Size/Quality/Format/Metadata/Delete Originals) với **nút Resize ghim ở đáy cột phải**, cạnh phải = tầm ngón cái. Đây thoả §10.1d điều kiện 1 (preview *là* nội dung) nên được to lên, và thêm được zoom 100% để thấy nén. Tốn: không tốn chiều cao (màn 1032 đủ), effort vừa (formBody tách được sẵn thành hai nửa); không đụng phone. Cần ghi vào §10.1d nếu muốn dùng danh nghĩa "cover là nội dung".
- Bằng chứng: `IP_Compress.png`; code dòng nêu trên.

### IP-07 CollageExport: bảng điều khiển trải 1344pt — nhãn "Size" cách control 1100pt; preview 534pt
- Màn / thiết bị: CollageExport · IP
- Mức: nên sửa
- Ở đâu: APP (`Features/Collage/CollageExportScreen.swift` — không có nhánh regular nào; bảng ở dòng ~160-250, nút Save `:247-248` full width)
- Vấn đề: `IP_CollageExport.png`: nhãn Size/Quality/Format/EXIF ở x=33, control ở x=1165–1343; slider Quality dài 1215pt (kéo chính xác 1–100 trên 1215pt là cực kỳ nhạy: ~12pt/nấc, tốt, nhưng dò hàng ngang từ nhãn sang giá trị "90" mất cả màn); "Save to Photos" 1344pt. Preview chỉ 534×534 trong 1032 cao.
- Đề xuất: giống IP-06: preview trái lớn, bảng phải 400pt, nút Save đáy cột phải. Hoặc rẻ hơn: giới hạn bảng + nút ở `maxWidth: 520` canh **phải**. Tốn: không có.
- Bằng chứng: `IP_CollageExport.png`; `CollageExportScreen.swift:91,247`.

### IP-08 Collage inspector tab Layout: UI dải ngang của điện thoại nhét vào cột 320×700 và để trống 700pt
- Màn / thiết bị: Collage · IP
- Mức: nên sửa
- Ở đâu: APP (`Features/Collage/CollagePanelViews.swift:20-60` — counter row 44 + aspect row 34 + `templateStrip` là `ScrollView(.horizontal)` 74pt; `CollageMetrics.swift:119` `templateCellSize` = 68 ở regular)
- Vấn đề: sidebar của Collage đã đúng hướng (cột phải, `EditorLayoutMetrics` kiểu Lightroom), nhưng tab Layout dùng nguyên 3 hàng của panel đáy điện thoại: chỉ thấy **4 template** (68pt) trong dải cuộn ngang, 0 preset hiện đủ, chân cột trống ~700pt (`IP_Collage.png` y=215→945). Hàng cuộn ngang trong một cột dọc là kiểu gesture khó phát hiện (cả với con trỏ không có wheel ngang).
- Đề xuất: ở `usesRegularToolChrome`, đổi `templateStrip` thành `LazyVGrid` 4 cột × N hàng (68pt, spacing 8) cuộn dọc; aspect chip thành `LazyVGrid` 2 hàng; presets đứng đầu như cũ. Hiện hết template mà không cuộn ngang. Tốn: 0 chiều rộng thêm, effort nhỏ (đổi container).
- Bằng chứng: `IP_Collage.png`; code dòng nêu trên.

### IP-09 Chart editor: Preview là section cuối cùng của List
- Màn / thiết bị: ChartEditor · IP
- Mức: nên sửa
- Ở đâu: APP (`Features/Statistics/ChartEditorSheet.swift:102-124` — `previewSection` cuối `List`, `:282-292`)
- Vấn đề: người dùng chỉnh "Group by / Measure / Show top 5 / Date range" nhưng thấy kết quả chỉ khi cuộn qua Conditions + Date Range (`IP_ChartEditor.png` dừng ở "This Year" cắt dở, chưa tới Preview). Sheet 700×~900 không có chỗ cho cả hai. Preview live đã có (`runPreview` `:152`) — chỉ bị đặt sai chỗ.
- Đề xuất: ở regular, sheet rộng hơn (`.presentationSizing(.page)` hoặc `.form`) với `HStack`: form trái 380pt, **Preview ghim phải 420pt** (không cuộn theo List). Trên compact giữ nguyên hoặc ghim Preview ở đầu List. Tốn: effort nhỏ; không tốn chiều cao.
- Bằng chứng: `IP_ChartEditor.png`; code dòng nêu trên.

### IP-10 Bàn phím: Esc/←/→ thiếu ở mọi full-screen cover trừ Editor, Collage, Video Studio; ⌘A/⌘F không có
- Màn / thiết bị: Viewer, Compare, Compress, VideoTrim, Slideshow, Library · IP
- Mức: nên sửa
- Ở đâu: APP (grep `keyboardShortcut` toàn `ShotDex/`: chỉ `SelectionBarViews.swift:46` `.cancelAction`, `PhotoDetailScreen.swift:674-732`, Editor, Collage, VideoStudio)
- Vấn đề: DESIGN/CLAUDE nhấn "màn rộng = Magic Keyboard + trackpad" (grid đã có hover; code còn ghi chú "photographer with a Magic Keyboard"). Nhưng:
  - Viewer (`fullScreenCover`): **không Esc** để đóng (nút ✕ ở góc trên-trái, xa nhất với tay), **không ←/→ để chuyển ảnh** (UIPageViewController, không có `UIKeyCommand`; `.leftArrow/.rightArrow` ở `:1628-1635` chỉ là step frame video), không Space cho slideshow/play.
  - CompareScreen (`:430` ✕), Compression (Cancel), VideoTrim (`:52` Cancel), Slideshow (`:80` ✕), CollageExport: không `.cancelAction`.
  - Library: "Select All" chỉ có trong menu ⋯ (`SelectionBarViews.swift:305`), không ⌘A; không ⌘F tới Search; Delete trong Viewer là phím ⌫ trần (`:732`, `.delete`) — cần xác nhận hệ thống có hỏi lại không (chưa xác nhận).
- Đề xuất: `.keyboardShortcut(.cancelAction)` trên nút đóng của 5 màn trên (rẻ); Viewer: ←/→ chuyển ảnh trên `PhotoPager` (UIKeyCommand hoặc `.onKeyPress` iOS 17), Space = play/pause video đang hiện; Library: ⌘A khi đang Select, ⌘F focus Search; ⌘I thay cho `I` trần nếu muốn tránh gõ nhầm. Tốn: nhỏ.
- Bằng chứng: các dòng đã nêu; `IP_Viewer.png`.

### IP-11 Statistics: chia thẻ theo `index % count` làm một cột chỉ toàn KPI, hai cột kia dài gấp 2–3
- Màn / thiết bị: Statistics · IP
- Mức: gợi ý
- Ở đâu: APP (`Features/Statistics/StatisticsScreen.swift:190-240` — `charts(_:inColumn:of:)` `offset % count`)
- Vấn đề: `IP_Statistics.png`: cột giữa chỉ có "Total Photos & Videos" và "Slow Shutter" (hai số lớn) và hết ở y≈470, trong khi cột 1 và 3 chạy quá 1000pt. Với bộ chart mặc định (2 KPI luân phiên với bar chart) cho ra một cột "xương sống rỗng". DESIGN §10.1c cố ý chọn round-robin để giữ thứ tự đọc, nhưng kết quả thực là mất cân đối chính khi KPI ở cùng index mod 3.
- Đề xuất: giữ thứ tự đọc nhưng xếp theo **cột đang ngắn nhất** (greedy, dùng chiều cao ước lượng theo kind: KPI ≈ 130, bar ≈ 40 + 32·rows, line ≈ 260), hoặc ghép các KPI liền nhau thành một hàng 2 ô. Cần thảo luận vì trái chữ §10.1c "dealt round-robin". Tốn: effort nhỏ; không đổi edit mode.
- Bằng chứng: `IP_Statistics.png` (nội dung biểu đồ trống là lỗi vẽ board, bố cục cột thì thật).

### IP-12 Onboarding: nút Continue 1320pt chạy hết đáy, nội dung nằm cụm trên cùng
- Màn / thiết bị: Onboarding · IP
- Mức: nên sửa (nhỏ)
- Ở đâu: APP (`Features/Onboarding/OnboardingScreen.swift:19-26` nút `.frame(maxWidth: .infinity)` + `.padding(.horizontal, 28)`; `:30-60` pitch trong ScrollView không căn giữa)
- Vấn đề: `IP_Onboarding.png`: 4 lời hứa gom ở y=190–420 trong cột ~700, nút Continue 1320×50 ở y=922 — hơn 500pt trống giữa hai thứ phải đọc liền nhau, và nút bấm duy nhất của màn đầu tiên ở giữa đáy, chỉ với được bằng cả bàn tay. Đây cũng là màn dẫn tới hộp thoại xin quyền Photos.
- Đề xuất: ở regular giới hạn `maxWidth: 480`, canh giữa **cả pitch lẫn nút thành một khối** theo chiều dọc (đưa nút lên ngay dưới lời hứa thứ tư, hoặc `frame(minHeight: proxy.size.height)` cho pitch). Tốn: không.
- Bằng chứng: `IP_Onboarding.png`.

### IP-13 Viewer: thanh thông tin trên cùng là một Button dài 1280pt cho một dòng chữ 12pt
- Màn / thiết bị: Viewer · IP
- Mức: gợi ý
- Ở đâu: APP (`Features/Library/PhotoDetailScreen.swift:1079-1101` `GlassPanel` + `Spacer()` ở HStack; được đặt trong `HStack` full-width ở `:250-259`)
- Vấn đề: `IP_Viewer.png` y=32–83, x=77–1359: toàn bộ thanh là vùng bấm mở Photo Info, nội dung chỉ rộng ~270pt ở mép trái, icon cloud/cảnh báo RAW ở mép phải cách 1000pt. Nó che 51pt đỉnh ảnh, tức ~5% chiều cao — và dải ảnh dưới nó bị mờ kính toàn chiều ngang. Rủi ro: vô tình chạm mở sheet khi đang cầm ở cạnh.
- Đề xuất: ở regular, `frame(maxWidth: 520, alignment: .leading)` cạnh nút ✕ (như iPhone về tỉ lệ); nếu làm IP-01 thì bấm vào nó bật inspector. Tốn: không.
- Bằng chứng: `IP_Viewer.png`.

### IP-14 Con trỏ: thẻ Collections, Trips, thẻ Statistics, nút kính trước iOS 26 không có `.hoverEffect`
- Màn / thiết bị: Collections, Trips, Statistics, Viewer · IP
- Mức: gợi ý (chưa xác nhận runtime)
- Ở đâu: APP (`grep hoverEffect` → chỉ `Features/Editing/*` và `Features/Collage/*`; `App/Glass/GlassIconButton.swift:14-16` `.buttonStyle(.plain)`; `Features/Albums/AlbumsScreen.swift:312-647` ~15 `.buttonStyle(.plain)`; `ChartCard.swift:203` Button drill)
- Vấn đề: hàng tile ảnh có `hoverStyle = .highlight` (PhotoGridCollectionView `:2028`) — tức dự án đã xác nhận pointer là nhu cầu thật — nhưng mọi thứ làm bằng SwiftUI `Button.plain` ngoài Editor/Collage có thể không sáng khi con trỏ đi qua (iOS 26 `glassEffect(.interactive())` thì có; nhánh pre-26 thì chưa chắc). Cần chạy trên iPad với trackpad để xác nhận: nếu `.plain` không phát hiệu ứng, 15+ chỗ trên.
- Đề xuất: thêm `.hoverEffect(.highlight)` trên `AlbumCoverTile`, `TripCard`, `drillButton`, `GlassIconButton` nhánh `#unavailable(iOS 26)` (và `.lift` cho thẻ cover). Tốn: 1 dòng mỗi chỗ.
- Bằng chứng: grep nêu trên; doctrine ipad-ux-review: "absence on a custom control is a finding".

### IP-15 Chuột phải: `⋯` của ChartCard và thẻ Trips không có `contextMenu`; Viewer không có menu trên ảnh
- Màn / thiết bị: Statistics, Trips, Viewer · IP
- Mức: gợi ý
- Ở đâu: APP (`Features/Statistics/ChartCard.swift:251-254` — Menu Edit/Duplicate/Delete không có contextMenu tương ứng; `TripsScreen.swift:41-48` — thẻ không có contextMenu trong khi AlbumsScreen có pin cho Trips `:626`; `PhotoDetailScreen.swift` — không `contextMenu` trên ảnh)
- Vấn đề: lưới ảnh, Albums, Duplicates, Creations đều có `contextMenu` → right-click chạy; ba chỗ trên thì không, nên cùng một khái niệm hai hành vi.
- Đề xuất: `.contextMenu` lặp lại đúng các hàng của `⋯` trên ChartCard (Edit/Duplicate/Delete) và thẻ Trips (Open, Share cover… tối thiểu Pin); Viewer: contextMenu trên ảnh với Copy / Share / Favorite / Info (đúng bộ Photos). Tốn: nhỏ.
- Bằng chứng: các dòng nêu trên.

### IP-16 Nhiều board IP chưa dựng xong (template `{{...}}`, lưới trống) nên không duyệt được mật độ trên iPad
- Màn / thiết bị: Library, LibrarySelect, Collections, Trips, Duplicates, AlbumDetail, SmartAlbum, OnThisDay, Places, Creations, ServerBrowser, Collage (khung trắng) · IP
- Mức: nên sửa (board)
- Ở đâu: BOARD (`build/design/app/render/IP_*.png`)
- Vấn đề: placeholder `{{p.title}}`, `{{p.dur}}`, `{{c.name}}`, `{{p.meta}}` chưa được thay; lưới ảnh Library trống toàn màn (chỉ 1 ô lỗi ở góc dưới trái) nên **không thể đối chiếu 13 cột × ô ~100pt** (§10.1c) hay hàng Collections/hero 260pt; `IP_Places` là nền đen trống; `IP_Duplicates` có chip tab bar gạch chân và `{{c.title}}` đè lên nút Back. Hai board Settings dùng hai kiểu sidebar khác nhau (`IP_Settings`: capsule xám đặc 296pt; `IP_ServerList`: nền trắng bo, icon trần) trong khi code (`SettingsLayout.swift`/§10.1f) chỉ có một `List(selection:)`. Biểu đồ trong `IP_Statistics` cũng trống (khoảng trắng ở vị trí bar chart).
- Đề xuất: sửa renderer để thay biến ảnh/ chuỗi (hoặc dựng dữ liệu mẫu), vẽ lại 3 board quan trọng nhất cho iPad (Library lưới đầy, Collections, Duplicates) trước khi ai đó dựa vào chúng để duyệt design parity. Sửa hai board Settings về một kiểu sidebar.
- Bằng chứng: `IP_Library.png`, `IP_Collections.png`, `IP_Places.png`, `IP_Duplicates.png`, `IP_Settings.png` vs `IP_ServerList.png`, `IP_Statistics.png`.

---

## Đã kiểm, không thành finding (để người sửa khỏi dò lại)
- **Settings (split view 320pt sidebar)**, **Support/SupportThread**, **CompressionPresets**: dùng `NavigationSplitView` theo §10.1f; detail column rộng ~760pt với hàng settings chuẩn — đúng cho form. Không đề xuất đổi.
- **Sheet 700pt** của AdvancedSearch, SmartAlbumEditor, Upload to Server: là form dạng "xong rồi đóng" — sheet đúng ở đây (trừ IP-02/IP-09 là khi người dùng *làm việc lặp* trong sheet). Không cần inspector.
- **Tier-D Collage/Editor sidebar ở cạnh phải**: đúng hướng ngón cái; hover/keyboard đã có.
- **Library chọn nhiều**: Share (trái dưới) và Delete (phải dưới) ở hai góc đáy là vị trí đúng cho hai ngón cái; "Show Selected" giữa đáy là hành động phụ nên chấp nhận.
- **VideoTrim**: dải trim 1344pt, tay cầm cách đáy ~66pt, không sát cạnh hệ thống; cạnh 16pt/trái-phải cần chạy thật để chắc không thua gesture cạnh (chưa xác nhận), không đưa vào finding.
- Chuyển động ở iPad (khoảng cách lớn gấp 3 điện thoại): không có bằng chứng từ board/code; cần quan sát runtime transition push của Collections → AlbumDetail trên 1376pt trước khi nói gì.
