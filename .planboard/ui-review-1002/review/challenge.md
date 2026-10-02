# Phản biện bản review gộp (merged.md, 88 mục) — 2026-10-02

Nhãn: **KEEP** giữ nguyên · **DOWNGRADE** giữ nhưng hạ mức/dời lùi · **DROP** bỏ · **REPLACE** làm bản rẻ hơn (ghi rõ bản nào).
Đã mở lại code/docs ở: DuplicatesModel/Screen, FS-06.06 §8, MetadataPanel + sheet ở PhotoDetailScreen, CompareScreen:808 + FS-01.08 §6,
CompressionScreen + FS-03.07, ShareLevelRow + FS-08.06, ServerUploadSheet + FS-15 README:41, SearchFieldAccessory, DESIGN §10.5/§11/§317,
ChartCard/ChartStore, SearchSuggestionsScreen:208. Mục nào ghi "chưa kiểm" thì phán đoán dựa trên merged.md và docs.

Ba nhận xét chung trước khi vào bảng:
1. Bản review đo mọi thứ bằng **ảnh render tĩnh mùa sáng**; 59/88 mục chưa ai mở code, ~20 mục là "runtime" trên Duo mà simulator không gập được. Sửa mù theo những mục đó là rủi ro lớn hơn lợi ích.
2. Cả bản gộp có xu hướng đổi **tài liệu đã chốt có lý do** (FS-01.06 §3, FS-15 "không chạy nền", FS-01.08 "cả thẻ là control", §10.1c round-robin) chỉ vì một reviewer thấy lạ. Mình giữ khi lý do còn đứng, bỏ khi lý do không bao phủ ca mới.
3. Tám mục "đáng làm" thật sự rẻ (S) và không đụng quyết định nào: M-14, M-10, M-26, M-58, M-59, M-07, M-16, M-45(chỉ ghim nút). Phần còn lại phải trả giá bằng quyết định hoặc M/L.

## 1. An toàn khi xoá & hàng loạt
| M-ID | Verdict | Lý do |
|---|---|---|
| M-01 | REPLACE (blocker còn đứng cho Similar/Series) | Có thật (`mergeAll` ghi `isFavorite/location/creationDate` ngay, `DuplicatesModel.swift:300-330`, `try?` nuốt lỗi) và Merge chạy cả ở Series (menu chỉ tắt khi `isBusy||groups.isEmpty`). Nhưng FS-06.06 §8 chủ ý "chép trước, xoá sau" vì độ bền; dời `adoptMetadata` vào giao dịch xoá cần lưu danh sách chờ chép qua đổi tab/huỷ, phức tạp hơn lợi ích. Bản rẻ: (1) chỉ cho Merge ở Exact, ẩn ở Similar/Series (ở đó dời ngày là sai thật); (2) một `.alert` có số nhóm + "Nothing is deleted until you tap Delete"; (3) bỏ `try?`. Ở Exact, "ngày sớm nhất + favorite" là lành tính, đúng việc Photos Merge làm. |
| M-02 | REPLACE | "Delete Originals bật" là mặc định có chủ ý (FS-03.07 §2, "compressing is normally a replace") và hộp xoá hệ thống của PhotoKit vẫn chặn. Không đổi mặc định. Làm: nhãn nút thành "Resize N Photos and Delete Originals" khi bật + toast 3s "N saved · X MB freed · originals in Recently Deleted" (FS-03.07 §5 "chạy sạch thì đóng thẳng" sửa một dòng). Cùng lượt sửa chữ trắng trên amber (M-79, `CompressionScreen.swift:187`). Dời công tắc: bỏ, 0 giá trị. |
| M-03 | REPLACE | Mất dấu khi đổi tab/Back là thật (`apply` cắt `markedForDeletion` theo `liveIds`, `DuplicatesModel.swift:162`). Bản rẻ: giữ dấu trong bộ nhớ qua đổi tab (chỉ lọc theo live lúc xoá) + chặn/ cảnh báo khi cả nhóm bị đánh dấu hết. **DROP** phần lưu `UserDefaults`/bảng: thêm một kho dữ liệu người dùng cho trạng thái nháp, chưa ai đòi. |
| M-04 | DOWNGRADE | Caption bị cắt ("6000 × 4000 · La…") và thiếu huy hiệu là thật; làm phần (a): hàng glyph 12pt (favorite, đã chỉnh, RAW) + thứ tự keeper ưu tiên đã chỉnh/favorite. Phần "trong album" (fetch collection theo ô) và hợp nhất album đảo FS-06.06 §8 và là M, dời lại. |
| M-05 | DOWNGRADE | Xoá chart không hỏi là thật nhưng chart tạo lại được trong 30 giây và Statistics đã có edit mode với nút xoá đỏ. Làm khi rảnh, `AppBanner` Undo, không phải trước khi ship. |
| M-06 | KEEP | Đổi thứ tự hai Section; Replace ghi đè file trên server mà công tắc "áp cho mọi xung đột" nằm sau nút. Rẻ, thật. |
| M-07 | KEEP | DESIGN §10.5 (dòng 344) cấm, §11 (dòng 365) vẫn bắt dùng: tài liệu tự mâu thuẫn, và trên iOS 26 mất nút Cancel ở đúng thao tác xoá kết nối. Đổi 3 chỗ + sửa §11. |
| M-08 | REPLACE | Chỉ sửa chữ toast Hide ("12 photos hidden · Find them in Photos > Hidden", 4s). **DROP** Undo (cần giữ PHAsset, "cần thử trên máy") và việc dọn nhánh Unhide. |
| M-09 | KEEP | Một dòng, màu đỏ chỉ nên nghĩa "ảnh sẽ mất". |

## 2. Phản hồi lỗi/thành công
| M-ID | Verdict | Lý do |
|---|---|---|
| M-10 | KEEP | `catch {}` rỗng ở `PhotoDetailScreen.swift:1252` và gộp huỷ với lỗi ở `:1266`; coordinator đã có sẵn alert. Xoá code nhiều hơn thêm. |
| M-11 | DOWNGRADE | Mất báo cáo dài khi gửi hỏng là xấu nhưng chỉ khi mạng/Server lỗi, màn ít dùng. Làm S (alert trong compose) sau lô đầu. Dòng "Add a few more words" thì bỏ. |
| M-12 | REPLACE | Một `ActionToast` chung cho mọi `perform` là thiết kế dư: Photos không toast Favorite/Duplicate/Adjust Date. Chỉ làm hai thứ thật sự gây hoang mang: "Added 12 to Trip 2025" (có "Show") và "Remove Location" có số khi chạy theo lô. |

## 3. Viewer / Compare
| M-ID | Verdict | Lý do |
|---|---|---|
| M-13 | KEEP (blocker thật) | `CompareScreen.swift:808` xin `ActiveDisplay.pixelSize()` cho mọi pane, `maximumZoomScale = 5` (`:143`): zoom đồng bộ chỉ nội suy ảnh cỡ màn hình. FS-01.08 §6 viết "bản đó đã thừa nét" cho **cỡ 1/2–1/4 màn**; lập luận đó không phủ ca phóng 5×, mà phóng để soi nét là lý do màn tồn tại. Lưu ý bộ nhớ: 4 pane × giải mã gốc không chịu nổi; chặn cạnh dài ~3000px, chỉ pane đang xem, chỉ khi zoom > 1.5×, `allowNetwork` theo Optimize Storage. Làm cuối lô đầu vì là M–L. |
| M-14 | DOWNGRADE (blocker → nên sửa, nhưng vẫn làm đầu tiên) | Sheet `.medium/.large` với `NavigationStack` không toolbar (`MetadataPanel.swift:30-47`). Trên Duo inner DESIGN §317 xác nhận detent bị bỏ thành full-screen, nhưng page sheet vẫn vuốt-xuống đóng được; "kẹt" là chưa kiểm. Dù vậy một nút Done tốn 0pt, nên làm. Thêm luật "mọi `.sheet` có nút đóng" vào DESIGN. |
| M-15 | REPLACE | Giữ FS-01.08 "chạm = đánh dấu" (người dùng đã chốt, không đảo hành vi chạm). Làm: (2) xoá 1 tấm không thoát cả màn khi còn ≥ 2 thẻ, (3) hint "Touch and hold to keep only this one". **DROP** (1) chuyển nút xoá xuống đáy: Compare là tầng D với Cancel/Title/Save ở trên, đổi là lệch khung §10.3; (4) chip "Zoom linked" chưa có người than. |
| M-16 | KEEP | `fullScreenCover(item:)` không `onDismiss` (`LibraryScreen.swift:154-157`): đóng viewer sau khi lướt 40 ảnh, lưới đứng im. Photos làm; tần suất cao nhất app. Token kiểu `jumpToNewestToken`, bỏ zoom-transition. |
| M-17 | DOWNGRADE | Inspector cạnh ảnh trên iPad là M và đọc EXIF là việc "nhìn rồi đóng". Phần thật là Done button (M-14) và thanh thông tin 1280pt cho một dòng chữ (S, `maxWidth: 520`). |
| M-18 | KEEP (gợi ý) | Đổi thứ tự section 0pt; Camera & Lens lên trước Location. |
| M-19 | KEEP (gợi ý, muộn) | Chrome đã tự ẩn khi zoom (`showsViewerChrome`, `:646`); chạm-để-ẩn cho ảnh tĩnh là thói quen Photos, nhưng thêm trễ 0.25s cho single-tap. Không gấp. |
| M-20 | DROP | Đảo Delete/Share riêng cho Duo cover trái quy ước Photos mà người dùng đã học, thêm một nhánh layout cho một thiết bị, dựa trên một persona. Thùng rác có xác nhận hệ thống. |

## 4. Tìm & lọc theo gear
| M-ID | Verdict | Lý do |
|---|---|---|
| M-21 | REPLACE | "4 chạm" phóng đại: ô Search gõ "R6 85mm" là xong (SearchParser). Thêm `Camera ▸`/`Lens ▸` vào phần Filter của menu là S và **không** vi phạm FS-01.05 §1 (điều kiện hiện thành token trong cùng một thanh, quick/advanced vẫn loại trừ nhau). **DROP** cột lọc 320pt trên iPad (M, ăn 3 cột lưới, Advanced sheet đủ dùng). |
| M-22 | DOWNGRADE | Chip Filename là chủ ý có comment; làm (a) đổi chữ chip "'night' not understood · search filenames?". **Chưa** làm trường `timeOfDay`: M, cần cột indexer, "night/golden hour" phụ thuộc mùa và múi giờ, và không user thật nào nêu. Đổi mức đúng: gợi ý. |
| M-23 | DOWNGRADE | Hiển thị "(actual)" trên capsule là S; **không** đổi mặc định sang equiv khi ≥2 sensor (quyết định ngầm, dễ làm lệch kết quả). |
| M-24 | DOWNGRADE | Nút Advanced trong ô search là tính năng có tên (FS-01.03 §8) và "Known cost on iOS 26" đã được ghi + đo. Chỉ mở đường nếu ảnh chụp thật trên iOS 26.5 cho thấy icon ma; bây giờ chỉ nới vùng chạm 28→44 (phương án c). |
| M-25 | REPLACE | Gộp Media Type + Match thành một hàng (~200pt lấy lại, đáng ở Duo/iPhone) và đưa "Matches N photos" lên gần Search. **DROP** thanh dính trên bàn phím và bố cục một dòng ở regular. |
| M-26 | KEEP | `SearchSuggestionsScreen.swift:208`: "Try: Fukuoka · f > 1.2 · ISO trên 3200 · trước 2020" là chuỗi Việt cứng, không qua String Catalog, thấy ngay ở lần chạy đầu. S, hiển nhiên. |
| M-27 | KEEP | "Ảnh không có vị trí / không lens" là câu hỏi dọn thư viện thật; `isMissing` M, làm sau lô đầu. |
| M-28 | DROP (lần này) | L (bảng mới, sheet, query), cho lens cơ. Lăng kính "Unknown" của Statistics đã cho thấy; cân nhắc lại khi có người dùng. |
| M-29 | DROP | Chuyển capsule thành token là M; "auto-activate" là quyết định có lý do (người dùng chê "chạm đầu không làm gì", ghi trong MEMORY). Không mở lại. |
| M-30 | KEEP (gợi ý, muộn) | Screenshot làm loãng Top Camera là thật; công tắc S trong menu lọc, sau lô đầu. |

## 5. Onboarding & index lần đầu
| M-ID | Verdict | Lý do |
|---|---|---|
| M-31 | KEEP | Đoạn footnote báo trước hộp quyền + "chọn Allow Full Access" S, ngăn lỗi tốn nhất của app này (Limited làm Search/Statistics trả thiếu mà không báo). |
| M-32 | REPLACE | Empty state "No Indexed Photos" chỉ hiện khi `totalPhotos == 0` (vài phút đầu, `StatisticsScreen.swift:136`). Làm: chữ "Index your library from the Library tab" ở Duplicates (không có nút nào như vậy) + nhãn "Still reading photo info · N%" và làm mới Statistics khi `isIndexing` true→false. **DROP** nhãn "Partial" trên từng chart và thẻ tiến độ chung. |
| M-33 | REPLACE | Chỉ `maxWidth: 480` trên regular (nút 1320pt là thật). Màu: giữ Continue xanh hệ thống, icon dùng `.secondary` (phương án a), không tạo ngoại lệ DESIGN §10.6. |
| M-34 | KEEP (gợi ý) | Hai dòng chữ, rẻ. |
| M-35 | KEEP (gợi ý) | Alert nổ lúc mở app, sai số nhiều: sửa chuỗi inflect; banner có thể để sau. |

## 6. Share & riêng tư
| M-ID | Verdict | Lý do |
|---|---|---|
| M-36 | DOWNGRADE | Ba tên mức đã chốt 2026-10-01 và đo trên máy (FS-08.06 §4, AC-2/7/20); dòng của app **vắng mức mặc định**, nên chỉ ai đặt mặc định No Metadata mới thấy "Share Without Location" cạnh "Metadata removed". Ca có thật nhưng hẹp; sửa header/phụ đề cho ca đó, không đổi tên mức. |
| M-37 | KEEP | Ý (a): sau khi lưu bản resize, nút "Share N Photos" với `createdAssetIDs`; Collage Export thêm "Share…". Photographer resize để **gửi**. Làm cùng M-02 vì cùng điểm đóng màn. Không làm Destination "Share only" (M, đường ghi file tạm mới). |
| M-38 | DROP | Share modal đã nói *"Videos keep their metadata"* (FS-08.06 §2); strip video là export lại HEVC/ProRes (chậm, tốn đĩa) cho nhóm nhỏ. Ghi vào backlog, không phải sửa UX. |
| M-39 | KEEP (gợi ý) | Hai câu chữ, nhưng phải khớp `SupportModel` thật. |

## 7. Server / upload nền
| M-ID | Verdict | Lý do |
|---|---|---|
| M-40 | DOWNGRADE | Nỗi đau thật (đám cưới 40–60 GB) nhưng đây là một **intent mới**, không phải sửa review: L, lật FS-15 README:41, `BGContinuedProcessingTask` chỉ iOS 26+, cần máy thật, và app đã giữ màn hình sáng (`ScreenAwakeCoordinator`). Rẻ hơn: khi quay lại từ nền, banner "Upload paused · Resume" thay vì im lặng. Mở `/intent` riêng. |
| M-41 | REPLACE | Đổi chỗ "Add Connection…" (S). Chế độ "một thư mục cho lần upload" (đám cưới qua nửa đêm bị chia đôi) là thật cho người chụp sự kiện, giữ lại nhưng làm sau (sửa FS-15 §02). |
| M-42 | REPLACE | Đưa Select ra toolbar và đổi glyph "In Library" (S, thật). **DROP** claim edge-swipe chết (runtime, chưa thấy) và bố cục nút Import regular. |
| M-43 | KEEP (gợi ý) | "Free Up Space — 214 photos · ~4.2 GB" là phần thưởng của cả tính năng upload; đáng làm. |
| M-44 | DROP | Test ngầm khi Save là hành vi bất ngờ (treo ở mạng chậm, lưu rồi mới cảnh báo); form hiện tại Save được là chủ ý. |

## 8. Màn rộng iPad (+ tool tầng D)
| M-ID | Verdict | Lý do |
|---|---|---|
| M-45 | REPLACE (blocker trên DI được giải bằng một thay đổi) | Ghim nút chính vào `safeAreaInset(.bottom)` cho Compress và Collage Export ở mọi thiết bị (S) giải luôn ca DI (nút ~130–230pt dưới đáy) và PH (dưới home indicator). Hai pane ở regular/short là M và có thể bỏ nếu preview sau khi ghim vẫn >200pt trên Duo; đo lại rồi quyết. |
| M-46 | REPLACE | `LazyVGrid adaptive(420)` cho thẻ + nút Delete tối đa 360pt (S). Master–detail là M cho một màn dùng vài lần mỗi năm. |
| M-47 | KEEP | `adaptive(320…440)` cho Trips (S); cover 8.4:1 là xấu thật. Giữ cao 160, không đụng §10.1d. |
| M-48 | KEEP | Thumbnail phóng ~2.7× là chất lượng ảnh; `adaptive` + `thumbnailPixels` theo cạnh (S). |
| M-49 | KEEP | Dải cuộn ngang thành `LazyVGrid` 4 cột ở `usesRegularToolChrome` (S). |
| M-50 | REPLACE | Esc đóng + ←/→ ở Viewer: S, đáng cho iPad có Magic Keyboard. **DROP** ⌘A/⌘F (niche). |
| M-51 | DOWNGRADE (hoãn) | Hover/contextMenu: chưa kiểm, "runtime", không ai báo bị mất việc. |

## 9. Màn thấp Duo
| M-ID | Verdict | Lý do |
|---|---|---|
| M-52 | REPLACE | `grep verticalSizeClass` = 0 là thật và DESIGN §317 đã biết ca "regular-compact". Nhưng một env `isShortWindow` + 8 điểm gọi là hạ tầng cho một thiết bị. Làm ba chỗ có số: hero `min(260, max(180, 0.28×h))`, Insights một dải, Widget picker; ghi "669pt là cửa sổ thấp nhất" vào DESIGN. Nếu một công thức theo chiều cao đủ thì không tạo cờ mới. |
| M-53 | REPLACE (blocker → nên sửa) | Widget Settings là màn dùng một lần lúc cài; "blocker" cho Large trên Duo inner là quá tay. Phương án rẻ: preview tối đa 158, cỡ Large vào popover (S). |
| M-54 | DOWNGRADE | Mọi dòng là runtime, simulator không có lệnh fold. Không sửa mù; cần máy/ghi trạng thái trước. Chỉ lưới giữ neo ảnh đầu khi bề rộng đổi là đáng thử. |
| M-55 | DROP | 9→10 cột khi vào chọn trên Duo inner: chưa kiểm, và mất 84pt bề ngang là cái giá của ý tưởng sửa. |
| M-56 | KEEP | `presentationDetents([.height(440), .large])`, một dòng. |
| M-57 | DOWNGRADE | Adjust Location + bàn phím trên inner, runtime, hiếm. |

## 10. Statistics
| M-ID | Verdict | Lý do |
|---|---|---|
| M-58 | KEEP | `ChartCard.swift:12,24` in "22640" cạnh trục "25,000", Settings ghi "55,231". 5 dòng, ba reviewer. |
| M-59 | KEEP | `ChartSpec.swift` seed có Body + Lens nhưng không có Top Lens; "lens nào tôi dùng nhiều nhất" là câu hỏi đầu của người chụp. S + tăng `currentSeedGeneration` (chưa release, không migration). |
| M-60 | REPLACE | Ghi tên lên thanh khi topN ≤ 5 (USER-17 b), giữ `Chart`; không dựng `BarRow` mới (M). |
| M-61 | REPLACE | Chỉ sửa `canSave` bỏ điều kiện tên (Save xám dù tên gợi ý hiện ra, S, thật). **DROP** ghim preview/cột phải (M) trong lượt này. |
| M-62 | KEEP | Một dòng (a) `colors[0] = AppAccent` hoặc sửa DESIGN; chọn một. |
| M-63 | DROP | Round-robin là quyết định có lý do ghi rõ (§10.1c, tránh lỗ hổng của LazyVGrid); KPI card cao ~100pt chỉ là khó coi. |
| M-64 | DROP | Token lọc đã có × để xoá và tab bar để về; chip "‹ Statistics" là thêm chrome. |

## 11. Library & Collections
| M-ID | Verdict | Lý do |
|---|---|---|
| M-65 | DROP | Compare/Edit ở nav bar là FS-01.06 §3 "bám Photos" có chủ ý; đổi đẩy bốn nút xuống đáy làm bố cục đáy khác Photos mà không giảm số chạm. |
| M-66 | REPLACE | Menu 14–16 dòng là dài thật. Làm: Create ▸ / Edit Info ▸ / Organise ▸, mục bị tắt có dòng lý do, "Combine Photos" giữ tên (đã có lý do trong DESIGN §332). Paste Edits giữ ẩn khi rỗng (đã đúng code). |
| M-67 | KEEP | "My Albums ›" → lưới dọc; người có 80 album không thấy hết trong carousel (T1). M, làm sau lô đầu. |
| M-68 | KEEP | Một khái niệm, bốn tên; chỉ chuỗi (S). |
| M-69 | KEEP | "Cloud" mang icon iCloud nhưng là Dropbox/Drive: gây hiểu nhầm về nơi ảnh nằm. S. |
| M-70 | DROP | Suy đoán runtime ("chụp lúc đang index"), chưa ai thấy cắt chữ. |
| M-71 | DOWNGRADE | Hơn mười hàng cuộn trong Settings iPhone chấp nhận được (có Search Settings); thêm tầng là thêm một chạm cho Re-index. Hoãn. |

## 12. HIG/sheet
| M-ID | Verdict | Lý do |
|---|---|---|
| M-72 | KEEP | Không có `interactiveDismissDisabled` ở Smart Album Editor, Chart Editor, Connection form, Advanced Search (grep xác nhận) trong khi Editor/Video Studio/Collage đều có. Vuốt nhầm mất form có mật khẩu là đau thật. `isDirty` + alert Discard. |
| M-73 | DROP | Chuyển ba cặp sheet-mở-sheet sang push là M và "Upload → Add Connection" sẽ phá luồng; hệ thống chấp nhận sheet chồng. |
| M-74 | DOWNGRADE | Tab bar đã có nhãn; Library cũng không có tiêu đề cố định. Nếu làm thì `.inline` (0pt), không `.large` (~96pt). |
| M-75 | KEEP | Vùng chạm 44pt cho nút xoá điều kiện và ⋯ của card; `contentShape` giữ glyph nhỏ. S. |
| M-76 | REPLACE | Chỉ sửa ⇅ của Statistics (trông như sắp xếp) vào menu "Add Chart / Reorder". **DROP** tách Customize khỏi "+" và đổi glyph Advanced (chưa ai nhầm). |
| M-77 | DROP | Detents cho Adjust Date/Trim là chuyện khẩu vị. |
| M-78 | KEEP (gợi ý) | `accessibilityLabel` cho Slider Quality: S, đúng. Phần còn lại hoãn. |

## 13. Nhất quán visual & từ ngữ
| M-ID | Verdict | Lý do |
|---|---|---|
| M-79 | KEEP | Chữ trắng trên amber 2.4:1 (`CompressionScreen.swift:187`); Collage Export đã dùng `.black`. Một dòng, làm cùng M-02. |
| M-80 | DROP | Refactor `EditorPrimaryButton`/`EditorSegmentedPicker` là M cho nhất quán nội bộ, người dùng không thấy; cần quyết định (a)/(b) trước. |
| M-81 | DROP | Gộp 4 công thức capsule: ~1 ngày refactor, không đổi gì người dùng thấy. |
| M-82 | REPLACE | Chỉ phần trạng thái chỉ-bằng-màu (vote): đổi glyph filled/unfilled + trait `.isSelected` (a11y thật). Phần accent rò ra control chuẩn thì hoãn. |
| M-83 | DOWNGRADE | Chỉ cần sửa DESIGN §11 cho khớp thực tế; không đổi ba màn. |
| M-84 | DOWNGRADE | Tiêu đề alert và "import/download": copy, làm khi chạm file đó. |
| M-85 | DROP | Nit (radius/spacing ngoài thang, 90pt chừa chrome): mỗi lần đổi 2pt phải chụp lại sim. |

## 14. Quy trình & sản phẩm
| M-ID | Verdict | Lý do |
|---|---|---|
| M-86 | KEEP | Không phải code: quyết định "Delete/Duplicates/Share/Upload không bao giờ bị khoá" nên viết vào `/spec` trước khi có StoreKit. |
| M-87 | KEEP | Một dòng ở `/release-check`. |
| M-88 | KEEP | Một lượt chạy `ios26-parity` trên Duo 27; không đổi quyết định. |

## Số lượng
KEEP 34 · DOWNGRADE 17 · DROP 15 · REPLACE 22 (tổng 88). Năm blocker: M-01 REPLACE (còn blocker cho Similar/Series), M-13 KEEP, M-14 DOWNGRADE, M-45 REPLACE, M-53 REPLACE+hạ mức.

## Review đã bỏ sót (quan trọng hơn một phần ba cuối)
1. **Chấm sao/Pick/Reject và lượt lọc (FS-01.12, 12b, spec cập nhật hôm nay) không có artboard nào và không reviewer nào nhắc**: đây là việc người chụp làm nhiều nhất sau một buổi (300–800 khung), trong khi ba reviewer dành cho Duplicates. Cần board + ux-reviewer trước khi code xong.
2. **Dark mode không ai xem**: toàn bộ board là sáng; tầng A–C dựa vào system color, chart indigo, amber chữ đen/trắng (M-79 chỉ đo sáng) và người dùng app ảnh thường ở chế độ tối.
3. **Accessibility ngoài hai chuỗi chữ**: không có reviewer VoiceOver/Dynamic Type; chỉ 6 file dùng `dynamicTypeSize`/`ScaledMetric`, và các điều khiển tự vẽ (chip lọc, bar chart, vote) không có trạng thái đọc được. Board tĩnh không cho thấy.
4. **Trạng thái quyền `.limited` / bị từ chối / ảnh iCloud offline không có board**: M-31 chỉ chặn việc chọn nhầm ở Onboarding. Người đã chọn Limited sẽ thấy Statistics, Duplicates và Search trả thiếu mà chỉ có một banner ở Library (`LibraryScreen.swift:515`); Linh trong chính persona "suýt chọn Limited theo thói quen".
5. **Không ai chạy vòng lõi từ đầu đến cuối với thư viện thật**: "tôi dùng ống kính nào nhiều nhất năm ngoái → xem các khung đó → xuất" (Statistics → drill-down → Library → Share), đo bằng chạm và giây trên 55k ảnh. Bản review chấm từng màn qua board, nên ba mục đứng đầu (M-01, M-13, M-14) là lỗi cục bộ còn câu hỏi "lời hứa số một có giữ được không" vẫn chưa được đo.

## First batch (12 mục, theo thứ tự)
1. **M-14** Done cho Photo Info/Burst + luật "mọi sheet có nút đóng": 0pt, không rủi ro, chặn kẹt trên Duo.
2. **M-01** Merge chỉ ở Exact + alert, bỏ `try?`: duy nhất mục ghi vào thư viện thật trước xác nhận.
3. **M-10** Favorite/Delete lỗi ở Viewer/Compare đi qua `AssetActionsCoordinator`: xoá code nhiều hơn thêm.
4. **M-26** Dòng "Try:" tiếng Việt trong UI tiếng Anh: thấy ngay lần chạy đầu, một chuỗi.
5. **M-58** Dấu phân cách hàng nghìn trong Statistics (5 dòng).
6. **M-59** Top Lens vào bộ chart mặc định (1 dòng + seed generation): câu hỏi gear số một.
7. **M-07** `confirmationDialog` → `.alert` ở ba màn server + sửa DESIGN §11: xoá kết nối mất Cancel trên iOS 26.
8. **M-02 + M-79** Resize: nhãn nút "…and Delete Originals", toast kết quả, chữ đen trên amber; giữ mặc định bật.
9. **M-03** Dấu xoá ở Duplicates sống qua đổi tab (bộ nhớ) + cảnh báo "all copies marked": nỗi sợ số 1 của app dọn ảnh.
10. **M-16** Đóng Viewer thì lưới cuộn tới ảnh vừa xem: thao tác dùng nhiều nhất app.
11. **M-45 (chỉ phần ghim nút)** Compress & Collage Export: nút chính vào `safeAreaInset`, giải ca DI và PH một lần.
12. **M-13** Compare zoom bằng ảnh độ phân giải cao theo vùng (cap ~3000px): mục dài nhất nên để cuối lô; nhờ `perf-profiler` + `memory-leak` kiểm.

Kế tiếp (chưa vào lô): M-72, M-31, M-61 (canSave), M-06, M-37, M-21 (submenu), M-41 (đổi chỗ Add Connection), M-67.
