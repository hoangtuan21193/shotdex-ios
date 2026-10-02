# ShotDex: gộp 8 báo cáo review UI/UX (2026-10-02)

Nguồn: `ux-flow.md` (UX-*), `visual.md` (VIS-*), `hig.md` (HIG-*), `iphone.md` (PH-*), `ipad.md` (IP-*),
`duo.md` (DUO-*), `persona.md` (USER-* và ba persona Linh/Minh/An), `user-voice.md` (VOICE-*, chủ đề T1–T16).
Board PNG đã xem lại trên bản render đúng ở `build/design/app/render/`.

**Cách đọc.**
- Mỗi mục M-xx gộp mọi finding nói về cùng một vấn đề gốc, kèm đủ ID nguồn. Càng nhiều reviewer độc lập cùng nêu thì mục càng lên cao.
- Xếp hạng: hại cho người dùng × số reviewer/persona/người dùng thật gặp × độ rẻ. Thứ tự trong từng chủ đề là thứ tự ưu tiên. Bảng "Top 15" ở cuối xếp chéo mọi chủ đề.
- **Kiểm code:** "đã kiểm code" nghĩa là tôi tự mở Swift tại file:line và thấy đúng như mô tả. "chưa kiểm" nghĩa là tin theo reviewer. "runtime" nghĩa là code đúng nhưng hậu quả còn phải thấy trên máy.
- **Chi phí:** S là dưới nửa ngày, M là 1–3 ngày, L là hơn 3 ngày hoặc đụng tới hệ thống/quyết định lớn.

**Bị loại vì chỉ là lỗi renderer (board render thiếu canvas runtime: `{{…}}` không mở, lưới/chart trống, sheet vẽ trong suốt chồng lên màn dưới):**
VIS-22, PH-17, IP-16, HIG-20, các phần renderer của DUO-18, UX-19 (a)(c)(d)(e), phần "script lỗi" của USER-20
(bốn board `*_ServerUpload` nay render bình thường), VIS-19 (Photo Info đè lên ảnh: sai. `MetadataPanel` là `List` trong `.sheet`, không có `GlassPanel`; chữ đè lên ảnh chỉ có ở bản render cũ).
Không thành mục: DUO-17 (reviewer tự kết luận giữ nguyên). Phần "ẩn Paste Edits khi rỗng" của USER-14 bị bỏ, vì code đã ẩn hàng đó rồi (`LibraryScreen.swift:585`, `editClipboard.hasContent`). Board vẽ trạng thái clipboard có nội dung.

---

**Số mục:** 88. Blocker 5 (M-01, M-13, M-14, M-45 trên DI, M-53) · nên sửa 58 · gợi ý 25.

| Chủ đề | Tổng | blocker | nên sửa | gợi ý |
|---|---|---|---|---|
| 1 An toàn khi xoá & hàng loạt | 9 | 1 | 7 | 1 |
| 2 Phản hồi lỗi/thành công | 3 | 0 | 3 | 0 |
| 3 Viewer/Compare | 8 | 2 | 3 | 3 |
| 4 Tìm & lọc theo gear | 10 | 0 | 7 | 3 |
| 5 Onboarding & index lần đầu | 5 | 0 | 3 | 2 |
| 6 Share & riêng tư | 4 | 0 | 3 | 1 |
| 7 Server/upload nền | 5 | 0 | 3 | 2 |
| 8 Màn rộng iPad (+ tool tầng D nhỏ) | 7 | 1 (DI) | 5 | 1 |
| 9 Màn thấp Duo | 6 | 1 | 5 | 0 |
| 10 Statistics | 7 | 0 | 4 | 3 |
| 11 Library & Collections | 7 | 0 | 5 | 2 |
| 12 HIG/sheet | 7 | 0 | 5 | 2 |
| 13 Nhất quán visual & từ ngữ | 7 | 0 | 5 | 2 |
| 14 Quy trình & sản phẩm | 3 | 0 | 0 | 3 |

## 1. An toàn khi xoá & thao tác hàng loạt

### M-01 Duplicates ▸ Merge All Groups ghi vào thư viện trước khi người dùng xác nhận, và chạy cả ở Series/Similar
- Màn / thiết bị: Duplicates · PH, IP, DI, DC
- Mức: **blocker**
- Nguồn: UX-04, HIG-02, VOICE-01 (ba reviewer độc lập) · user-voice T6 (nỗi sợ số 1 với app dọn ảnh)
- Kiểm code: **đã kiểm code**. `DuplicatesModel.swift:300-311` `mergeAll` gọi `adoptMetadata` ngay lúc bấm. `:323` `try? await PHPhotoLibrary.shared().performChanges` ghi `isFavorite`/`location`/`creationDate` và nuốt lỗi. `DuplicatesScreen.swift:99-104`: menu chỉ bị tắt khi `isBusy || groups.isEmpty`, không chặn `.series`. Không có alert.
- Vấn đề: một hàng menu trung tính đổi **ngày chụp, vị trí và favorite** của bản giữ lại trong thư viện thật, trước cả hộp xoá. Người dùng huỷ hộp xoá hoặc bấm Clear Selection thì thư viện vẫn mang thay đổi đó, và trong app không có đường đảo lại. Ở Similar, ngày của tấm giữ bị dời sang khoảnh khắc của một tấm khác. Ở Series, mọi loạt bị cắt còn 1 khung, trái FS-06.06 §6 ("thường là giữ vài tấm"). Màn hình cũng không báo đã đánh dấu bao nhiêu ảnh.
- Đề xuất: (1) chỉ cho Merge ở Exact; ẩn ở Similar/Series. (2) nhãn "Merge 12 Groups…" + `.alert` (không dùng `confirmationDialog`, xem M-07): *"Keeps the largest copy in each of 12 groups and marks 19 photos for deletion. The kept copy takes the favourite, location and earliest date of its copies. Nothing is deleted until you tap Delete."* (3) dời `adoptMetadata` vào cùng `performChanges` với `deleteAssets` trong `deleteMarked`, để chép và xoá xảy ra cùng một lúc. (4) bỏ `try?`; nhóm nào chép lỗi thì dừng nhóm đó. (5) toast "Marked 19 photos in 12 groups" và cuộn tới nhóm đầu.
- Chi phí: S–M (~30 dòng + 1 alert).
- Cần quyết định: **có**. Đảo câu "chép trước, xoá sau" của FS-06.06 §8. Phương án: (a) chép trong cùng giao dịch với xoá (khuyến nghị); (b) giữ ghi sớm nhưng thêm alert; (c) đổi tên thành "Mark Smaller Copies" và bỏ hẳn phần chép metadata.

### M-02 Resize: "Delete Originals" bật sẵn, nút không nói, xong thì đóng im lặng
- Màn / thiết bị: Compress (Resize) · PH, IP, DI, DC
- Mức: nên sửa (ưu tiên cao nhất trong nhóm "nên sửa")
- Nguồn: UX-01, PH-04 (công tắc nằm sát nút chính, nút dưới nếp gập), persona Minh (bản copy mới chen giữa bản gốc), VIS-01 (chữ nút)
- Kiểm code: **đã kiểm code**. `CompressionController.swift:48` `var deleteOriginals = true` ("On by default — compressing is normally a replace"). `CompressionScreen.swift:183-185`: nhãn "Resize N Photos" / "Save to Photos" giống nhau dù công tắc bật hay tắt. `:122-124`: khi `finishedCleanly` thì `dismiss()` thẳng.
- Vấn đề: bấm nút chính là xoá luôn bản gốc của cả lô (hộp hệ thống của PhotoKit là lưới an toàn duy nhất), và với iCloud Photos thì xoá trên mọi thiết bị. Upload sheet có nói câu này, Resize thì không. Chạy xong, màn hình đóng mà không nói đã lưu bao nhiêu, tiết kiệm bao nhiêu MB, bản gốc nằm ở đâu.
- Đề xuất: (1) khi bật, nhãn thành "Resize 8 Photos and Delete Originals", hoặc thêm dòng phụ 12pt "Originals go to Recently Deleted" (~16pt). (2) sau `finishedCleanly`, toast 3s trên lưới: "8 resized copies saved · 41 MB freed · Originals in Recently Deleted". (3) dời công tắc lên cao, tách khỏi nút bằng khối Bulk Fill (PH-04).
- Chi phí: S (chuỗi + toast).
- Cần quyết định: **có**. Đổi FS-03.07 §2 (mặc định BẬT) và §5 (bỏ summary). Phương án: (a) mặc định TẮT (UX-01 khuyến nghị); (b) giữ BẬT nhưng (1)+(2) là bắt buộc.

### M-03 Duplicates: dấu xoá mất khi đổi tab hay bấm Back, và đánh dấu được cả nhóm
- Màn / thiết bị: Duplicates · mọi thiết bị
- Mức: nên sửa
- Nguồn: UX-05, VOICE-03 · user-voice T7 (người dùng Gemini mất 4 giờ đánh dấu)
- Kiểm code: **đã kiểm code**. `DuplicatesModel.swift:162-163`: `apply` cắt `markedForDeletion` về các id có trong tab mới. `:45-50`: `strictness.didSet` gọi `loadCache`. `DuplicatesScreen.swift:16,28`: `@State model` được tạo mới mỗi lần vào màn. `toggleMark` không chặn ô cuối của nhóm.
- Vấn đề: đánh dấu 6 ảnh ở Similar, sang Exact xem thử rồi quay lại thì dấu đã mất, số trên thanh đỏ tụt mà không có lời nào. Back hay đổi tab cũng xoá sạch dấu. Chạm hết mọi ô của một nhóm thì "Delete" xoá sạch mọi bản.
- Đề xuất: giữ `markedForDeletion` qua các lần đổi tab, chỉ lọc theo `liveIds` lúc xoá. Lưu dấu theo asset id vào `UserDefaults` hoặc một bảng nhỏ (không vào `photo_metadata`). Dòng đầu màn ghi "19 marked · Review". Nhóm sắp bị đánh dấu hết thì viền vàng + "All copies marked — nothing will be kept".
- Chi phí: S–M.
- Cần quyết định: không.

### M-04 Ô ảnh trùng không cho thấy bản nào đáng giữ
- Màn / thiết bị: Duplicates, Compare · mọi thiết bị
- Mức: nên sửa
- Nguồn: VOICE-02, USER-13, persona Linh ("La…" bị cắt) · user-voice T6/T7 (xoá mất bản đã chỉnh, không biết bản nào nằm trong album)
- Kiểm code: chưa kiểm (board `PH_Duplicates` đúng là cắt "6000 × 4000 · La…", "Sep 14, 2…")
- Vấn đề: caption 100–110pt bị cụt đúng chữ quan trọng. Không có dấu nào cho biết bản đã chỉnh, favorite, nằm trong album, RAW hay Live. Bản giữ được chọn theo "file lớn nhất", nên bản gốc chưa chỉnh thắng bản đã chỉnh. Xoá bản trong album thì ảnh biến khỏi album.
- Đề xuất: hàng huy hiệu glyph 12pt dưới ảnh (`heart.fill`, đã chỉnh, `rectangle.stack`+số album, RAW, LIVE). "Largest" thành nhãn ở góc ảnh. Bỏ năm khi cả nhóm cùng năm. Keeper ưu tiên: đã chỉnh > trong album > favorite > pixel > dung lượng. Lúc Merge, thêm bản giữ vào các album của bản sắp xoá.
- Chi phí: M (fetch album chỉ cho ô đang hiện, theo NF-01 luật 1).
- Cần quyết định: **có**. Hợp nhất album đảo dòng "không có bước hợp nhất album" của FS-06.06 §8. Phương án: (a) chỉ thêm huy hiệu + đổi thứ tự keeper; (b) thêm cả bước hợp nhất album.

### M-05 Xoá chart không hỏi, không hoàn tác
- Màn / thiết bị: Statistics · mọi thiết bị
- Mức: nên sửa
- Nguồn: HIG-10
- Kiểm code: chưa kiểm
- Vấn đề: "Delete" trong ⋯ của card xoá ngay hàng DB của một cấu hình do người dùng dựng. Hàng này nằm ngay dưới Duplicate.
- Đề xuất: xoá mềm + `AppBanner` "Chart deleted · Undo" 5s (hợp HIG hơn alert).
- Chi phí: S.
- Cần quyết định: không.

### M-06 Upload: công tắc "Apply to Remaining Conflicts" nằm dưới ba nút trả lời
- Màn / thiết bị: ServerUpload (xung đột tên) · mọi thiết bị
- Mức: nên sửa
- Nguồn: UX-11
- Kiểm code: chưa kiểm
- Vấn đề: người dùng bấm Replace (ghi đè file trên server) trước khi thấy công tắc áp cho tất cả.
- Đề xuất: đưa công tắc lên trên ba nút, nhãn "Do this for all remaining conflicts". Khi bật, nút đổi thành "Replace All" (đỏ) / "Skip All".
- Chi phí: S (đổi thứ tự hai Section).
- Cần quyết định: không.

### M-07 Ba màn server xác nhận xoá bằng `.confirmationDialog`; DESIGN.md tự mâu thuẫn
- Màn / thiết bị: File Servers, On Server, On Cloud · mọi thiết bị
- Mức: nên sửa
- Nguồn: HIG-01
- Kiểm code: **đã kiểm code**. `FileServerListScreen.swift:59`, `OnServerScreen.swift:99`, `OnCloudScreen.swift:130`. Cancel bị ẩn trên iOS 26 là theo số đo cũ của dự án (`SettingsScreen.swift:945`), lượt này chưa chụp lại.
- Vấn đề: trên iOS 26, `confirmationDialog` vẽ thành popover và mất nút Cancel. Settings, Editor, Video Studio, Collage đã đổi sang `.alert`. DESIGN.md §10.5 cấm dùng `confirmationDialog`, còn §11 vẫn bắt dùng.
- Đề xuất: đổi ba chỗ sang `.alert` (Cancel + "Delete Connection" đỏ). Sửa §11 thành "alert 2 nút". Giữ `ServerExportSheet.swift:74`, vì đó là lựa chọn không phá huỷ.
- Chi phí: S.
- Cần quyết định: không (sửa tài liệu cho khớp §10.5).

### M-08 Hide là cửa một chiều: ảnh biến mất, toast không nói tìm lại ở đâu
- Màn / thiết bị: Library chọn nhiều, Viewer · mọi thiết bị
- Mức: nên sửa
- Nguồn: UX-07
- Kiểm code: **đã kiểm code** một phần. Toast duy nhất có ở `AssetActionsCoordinator.swift:136` (Hide) và `:220` (Copied).
- Vấn đề: 12 ảnh biến khỏi lưới, album và thống kê. Toast 1.6s "12 Photos Hidden" không nói ảnh nằm trong Photos › Hidden, nên người dùng tưởng ảnh đã bị xoá. Nhánh "Unhide" gần như không bao giờ tới được.
- Đề xuất: toast 4s, hai dòng: "12 photos hidden · Find them in Photos › Hidden" + Undo 6s nếu còn cầm `PHAsset` (cần thử trên máy). Bỏ nhánh Unhide chết.
- Chi phí: S.
- Cần quyết định: không (giữ quyết định FS-01.06 về Hidden).

### M-09 Nút Cancel của lượt quét Duplicates mang `role: .destructive`
- Màn / thiết bị: Duplicates · mọi thiết bị
- Mức: gợi ý
- Nguồn: HIG-14
- Kiểm code: chưa kiểm (`DuplicatesScreen.swift:206`)
- Vấn đề: nút huỷ quét đỏ cùng màu với "Delete N Photos" bên dưới, làm màu đỏ mất nghĩa "ảnh sẽ mất".
- Đề xuất: bỏ role destructive.
- Chi phí: S.
- Cần quyết định: không.

## 2. Phản hồi: lỗi và thành công im lặng

### M-10 Viewer/Compare: favorite hay xoá thất bại thì không có gì xảy ra
- Màn / thiết bị: Viewer, Compare · mọi thiết bị
- Mức: nên sửa
- Nguồn: UX-02
- Kiểm code: **đã kiểm code**. `PhotoDetailScreen.swift:1252-1254` `catch { }` rỗng. `:1266-1270` gộp "người dùng huỷ" với "lỗi" rồi `return`.
- Vấn đề: tim không đổi, ảnh không mất, không có thông báo. Người dùng không phân biệt được "mình bấm huỷ" với "app hỏng". Lưới và Duplicates thì đã tách đúng hai trường hợp.
- Đề xuất: dùng chung `AssetActionsCoordinator.perform` (đã có alert "Couldn't Update Photos" + lọc `userCancelled`) cho cả ba chỗ.
- Chi phí: S (xoá code nhiều hơn thêm).
- Cần quyết định: không.

### M-11 Support: gửi thất bại không hiện lỗi; Send bị tắt mà không nói vì sao
- Màn / thiết bị: Support › Report a Bug / Request a Feature · mọi thiết bị
- Mức: nên sửa
- Nguồn: UX-03
- Kiểm code: **đã kiểm code**, runtime chưa thấy. `SupportComposeScreen.swift:139-141` comment: "the alert belongs to the screen underneath". Alert nằm ở `SupportScreen.swift:46`, dưới sheet soạn thư.
- Vấn đề: vừa gõ xong một báo cáo dài, bấm Send, spinner quay rồi thôi, không có chữ nào. Send cũng bị tắt khi tiêu đề dưới 4 ký tự hoặc nội dung dưới 10 ký tự mà không nói điều kiện.
- Đề xuất: `onSend` trả `SupportError?`, alert hoặc dòng đỏ hiện ngay trong compose kèm "Try Again". Footer "Add a few more words" khi nút đang tắt.
- Chi phí: S.
- Cần quyết định: không.

### M-12 Hành động hàng loạt thành công không để lại dấu vết
- Màn / thiết bị: Library chọn nhiều, Album, Viewer, Upload sheet · mọi thiết bị
- Mức: nên sửa
- Nguồn: UX-06, UX-13
- Kiểm code: **đã kiểm code** (chỉ Hide/Copy có toast, xem M-08)
- Vấn đề: Add to Collection, Duplicate, Favorite, Adjust Date, Adjust Location đều đóng sheet mà không có một dòng nào. "Remove Location" áp ngay cho cả lô mà nút không nêu số. Sau khi xoá ảnh đã upload, Section Delete biến mất mà không nói "214 moved to Recently Deleted".
- Đề xuất: một toast chung (`ActionToast`, 2.5s) sau mọi `perform` thành công: "Added 12 to Trip 2025" (+ "Show"), "Duplicated 12 photos", "Location removed from 12 photos" (+ Undo). "Remove Location" ghi số khi chạy theo lô. Upload sheet hiện một dòng tick xám "214 photos moved to Recently Deleted".
- Chi phí: S (~6 chuỗi + 1 hàm).
- Cần quyết định: không.

## 3. Viewer / Compare

### M-13 Compare zoom 5× chỉ phóng bản ảnh cỡ màn hình, nên không soi được độ nét
- Màn / thiết bị: Compare · mọi thiết bị
- Mức: **blocker** (màn không làm được đúng việc nó tồn tại để làm)
- Nguồn: USER-02, persona Linh · user-voice T13 (bản mờ khi bật Optimize Storage)
- Kiểm code: **đã kiểm code**. `CompareScreen.swift:808` `targetSize = ActiveDisplay.pixelSize()` cho cả hai request. `:143` `maximumZoomScale = 5`. Không có request độ phân giải gốc khi zoom.
- Vấn đề: ảnh 6000×4000 được tải ở khoảng 1206px, nên zoom 5× là nội suy và ba tấm nhoè như nhau. Người dùng không chọn được tấm nét nhất.
- Đề xuất: khi `zoomScale` vượt khoảng 1.5×, xin ảnh gốc theo vùng đang nhìn (`CGImageSourceCreateThumbnailAtIndex` hoặc tile) cho từng pane, đồng bộ theo `CompareScrollSynchronizer`, kèm vòng tải iCloud ở góc pane như Viewer.
- Chi phí: M–L (bộ nhớ khi giải mã 3–4 ảnh gốc, nên chỉ giải mã vùng thấy được; cần `perf-profiler` + `memory-leak`).
- Cần quyết định: không (chỉ có một cách đúng; chọn tile hay full decode là chuyện kỹ thuật).

### M-14 Photo Info (và Burst) không có nút đóng; trên Duo inner sheet thành full-screen nên kẹt
- Màn / thiết bị: Viewer › Photo Info, Viewer › Burst · DI chủ yếu; mọi thiết bị đều thiếu nút
- Mức: **blocker** (DI)
- Nguồn: DUO-01
- Kiểm code: **đã kiểm code** cho Photo Info. `MetadataPanel.swift:30-47`: `NavigationStack` chỉ có `navigationTitle`, không có toolbar. `PhotoDetailScreen.swift:356-361` `.sheet` + `[.medium, .large]`. Burst (`PhotoListScreen`) chưa kiểm. Việc kéo xuống không đóng được trên inner: runtime.
- Vấn đề: trên inner, detent bị bỏ qua và sheet thành 951×669. Nếu kéo xuống không đóng được thì không còn đường thoát nào nhìn thấy được.
- Đề xuất: `ToolbarItem(.confirmationAction) { Button("Done") }` trong `MetadataPanel` và Burst. Thêm luật vào DESIGN.md: "mọi `.sheet` có nút đóng trong toolbar".
- Chi phí: S (0pt chiều cao).
- Cần quyết định: không.

### M-15 Compare: chạm là đánh dấu xoá; nút xoá ở góc trên; xoá 1 tấm là thoát cả màn; "Keep Only This" bị giấu
- Màn / thiết bị: Compare (từ Library, Duplicates) · PH, DC chủ yếu
- Mức: nên sửa
- Nguồn: UX-17, PH-03, PH-12, USER-10, persona Linh ("chạm xong… mình giật mình")
- Kiểm code: chưa kiểm
- Vấn đề: phản xạ của người dùng Photos là chạm để xem to, ở đây chạm là đánh dấu xoá. Zoom đồng bộ là thứ đáng khoe nhưng không có chỗ nào nói ra. "Delete N Photos" ở góc trên-phải sau một danh sách cuộn, trong khi Duplicates đặt nút ở đáy. Từ Duplicates, nhóm 4 ảnh xoá 1 tấm là màn đóng luôn. Long-press "Keep Only This" không có gợi ý nào.
- Đề xuất: (1) nút xoá xuống thanh đáy 52pt như Duplicates. (2) chỉ đóng màn khi còn dưới 2 thẻ. (3) hint đổi thành "Touch and hold a photo to keep only that one" sau dấu đầu tiên. (4) chip "Zoom linked", chạm để tắt.
- Chi phí: S–M.
- Cần quyết định: **có**. Đổi chạm thành "mở to" và chỉ đánh dấu qua vòng tròn ở góc là đảo FS-01.08 ("cả thẻ là control"). Phương án: (a) chỉ làm (1)–(4), giữ chạm = đánh dấu; (b) đổi luôn hành vi chạm.

### M-16 Đóng Viewer thì lưới không đưa tới ảnh vừa xem
- Màn / thiết bị: Library, Album, Smart Album · mọi thiết bị
- Mức: nên sửa
- Nguồn: PH-01
- Kiểm code: **đã kiểm code**. `LibraryScreen.swift:154-157` `fullScreenCover(item: $viewerTarget)` không có `onDismiss`. `currentIndex` của viewer là state cục bộ. grep `matchedTransitionSource|navigationTransition` ra 0 kết quả.
- Vấn đề: mở ảnh thứ 10, lướt sang 40 ảnh nữa rồi đóng: lưới vẫn đứng ở chỗ cũ. Đây là thao tác dùng nhiều nhất app.
- Đề xuất: khi đóng, ghi asset id đang xem vào một token (giống `jumpToNewestToken`), lưới `scrollToItem` nếu tile đó đang ngoài màn. Zoom-from-tile để sau, vì lưới là UICollectionView.
- Chi phí: S.
- Cần quyết định: không.

### M-17 Photo Info trên iPad nên là inspector cạnh ảnh, không phải sheet che ảnh
- Màn / thiết bị: Viewer › Photo Info · IP
- Mức: nên sửa
- Nguồn: IP-01, IP-13 (thanh thông tin là Button 1280pt cho một dòng chữ)
- Kiểm code: **đã kiểm code** (sheet tại `PhotoDetailScreen.swift:356`)
- Vấn đề: sheet khoảng 700×850 che hơn nửa ảnh và chặn vuốt sang ảnh kế, đúng lúc người dùng đang soi EXIF với ảnh.
- Đề xuất: ở regular width, `.inspector` 340–380pt cạnh phải. Nút ⓘ và phím I bật/tắt. Lướt ảnh thì nội dung cột đổi theo. Thanh thông tin trên cùng `maxWidth: 520`.
- Chi phí: M (tốn bề ngang, vốn đang dư).
- Cần quyết định: không.

### M-18 Photo Info: bản đồ đứng đầu, EXIF bị đẩy dưới nếp gập ở detent medium
- Màn / thiết bị: Photo Info · PH, DC
- Mức: gợi ý
- Nguồn: PH-10
- Kiểm code: chưa kiểm (board `PH_Metadata` xác nhận thứ tự Location → Camera & Lens)
- Đề xuất: đưa Camera & Lens và Exposure lên trước, Location xuống sau.
- Chi phí: S (0pt).
- Cần quyết định: không.

### M-19 Viewer: ảnh tĩnh không có "chạm để ẩn chrome"
- Màn / thiết bị: Viewer · mọi thiết bị
- Mức: gợi ý
- Nguồn: PH-08
- Kiểm code: chưa kiểm
- Đề xuất: single-tap ẩn/hiện chrome (dùng lại animation của video), chờ double-tap fail khoảng 0.25s.
- Chi phí: S (single-tap chậm đi 0.25s).
- Cần quyết định: không.

### M-20 Duo cover cầm một tay: nút gần ngón cái nhất là thùng rác; Settings/Back ở góc bo xa nhất
- Màn / thiết bị: Viewer, Library, Statistics · DC
- Mức: gợi ý
- Nguồn: USER-18, persona An
- Kiểm code: chưa kiểm (cần `Tools/sim-shot … cover`)
- Đề xuất: trên cover, đảo Share sang phải và Delete sang trái, hoặc đưa Share vào rail.
- Chi phí: S–M (một nhánh layout riêng cho cover).
- Cần quyết định: **có**. Lệch quy ước của Photos. Phương án: (a) đảo trên cover; (b) giữ như Photos.

## 4. Tìm & lọc theo gear

### M-21 Lọc theo máy/ống kính cách Library 4 chạm; menu lọc không có Camera/Lens; iPad không có cột lọc
- Màn / thiết bị: Library, Advanced Search · PH, IP (mọi thiết bị)
- Mức: nên sửa
- Nguồn: PH-05, IP-02 · user-voice T3 (đòi lọc theo lens từ 2018) · lời hứa số 1 của Onboarding
- Kiểm code: **đã kiểm code**. `PhotoFilterMenu.swift:55-85`: All Items, Favorites, Photos/Videos Only, Capture Kind, Advanced Filter… Không có Camera/Lens. `LibraryModel.swift:227-228` đã có `availableBodies`/`availableLenses`.
- Vấn đề: tính năng cốt lõi nằm sau menu → Advanced Filter… → sheet → Add Condition → chọn trường → gõ → Search. Trên iPad, lưới bị che nên chỉnh ISO từ 800 lên 1600 phải mở lại sheet.
- Đề xuất: thêm submenu `Camera ▸` và `Lens ▸` (8 mục có nhiều ảnh nhất trước) vào phần Filter. Ở regular width, thêm cột lọc 320pt bên phải chứa `RuleBuilderSections`, áp dụng trực tiếp (debounce 300ms).
- Chi phí: S (menu) · M (cột iPad, lưới từ 13 còn 10 cột).
- Cần quyết định: **có**. FS-01.05 §1 ("một điều kiện không hiện ở hai chỗ") và §5 (Advanced loại trừ quick filter). Phương án: (a) chỉ thêm submenu, coi là lối tắt; (b) thêm cả cột iPad và quyết định quick + advanced được cùng bật.

### M-22 "85mm night" ra 0 ảnh: chữ không hiểu bị biến thành Filename, và không có giờ chụp
- Màn / thiết bị: Search, Advanced Search, Smart Album Editor · mọi thiết bị
- Mức: nên sửa (persona xếp blocker; hạ một bậc vì đây là thiếu tính năng, còn chip Filename là chủ ý có ghi trong code)
- Nguồn: USER-01, persona Linh
- Kiểm code: **đã kiểm code**. `SearchService.swift:137-143`: phần chữ thừa thành `SmartAlbumRule(field: .filename, op: .contains)`, và comment ghi đây là chủ ý. grep `timeOfDay|hourOfDay` ra 0 kết quả.
- Vấn đề: "ảnh đêm / golden hour" là câu đầu tiên một người chụp du lịch nghĩ tới. Album mẫu "Night ISO 3200+" cho thấy chính app cũng phải đi vòng qua ISO, và bỏ sót ảnh đêm chụp chân máy.
- Đề xuất: RuleField `timeOfDay` (giờ địa phương lúc chụp, 0–23, cho phép vắt qua nửa đêm). Parser hiểu `night` (19–05), `golden hour`/`sunset`, `morning`. Chip ghi "'night' not understood · search filenames?" thay vì im lặng chuyển thành filename.
- Chi phí: M (cột giờ do indexer ghi vào `photo_metadata`, đúng luật; một nhánh parser).
- Cần quyết định: **có**. (a) chỉ đổi chữ của chip; (b) thêm trường giờ chụp + từ khoá.

### M-23 "85mm" không nói là tiêu cự thật hay tương đương
- Màn / thiết bị: Search · mọi thiết bị
- Mức: nên sửa
- Nguồn: USER-07, persona Linh (56mm trên X-T5 bị loại)
- Kiểm code: chưa kiểm (`SearchIntentParser+Numbers.swift:28-30`)
- Đề xuất: capsule ghi "focal 85mm (actual)", chạm để đổi sang "85mm equiv.". Mặc định equiv khi thư viện có từ hai sensor format trở lên.
- Chi phí: S.
- Cần quyết định: **có**, về mặc định: (a) actual; (b) equiv khi có ≥2 format.

### M-24 Nút Advanced Search được nhét vào ô search bằng hack UIKit, làm mất nút Clear
- Màn / thiết bị: Search tab/sheet · PH, DI, DC
- Mức: nên sửa
- Nguồn: HIG-03, PH-07 (vùng chạm 28pt)
- Kiểm code: **đã kiểm code**. `SearchFieldAccessory.swift:94,111` `Timer` lặp lại. `:149` `field.rightView = button`.
- Vấn đề: ô search mất nút Clear. Trên iOS 26 có một icon ma ở vùng status bar. Vùng chạm 28pt. Cách này phụ thuộc view nội bộ của iOS.
- Đề xuất: bỏ hack. Đưa "Advanced" thành hàng gợi ý đầu tiên, hoặc nút chữ ở title row (đã có `AdvancedSearchButton`).
- Chi phí: S–M (thêm khoảng 1 chạm).
- Cần quyết định: **có**. Lật quyết định "Known cost on iOS 26" ghi trong code. Phương án: (a) hàng gợi ý; (b) nút ở title row; (c) giữ hack và chỉ nới vùng chạm lên 44.

### M-25 Advanced Search: số ảnh khớp và nút Search xa ngón cái; Media/Match ăn 250pt; trên Duo ba điều kiện đã đầy màn
- Màn / thiết bị: Advanced Search, Smart Album Editor, Chart Editor · PH, DI, DC
- Mức: nên sửa
- Nguồn: PH-07, DUO-06
- Kiểm code: chưa kiểm (board `PH_AdvancedSearch`: điều kiện đầu ở y≈400, "Matches 1284 photos." là footer sau Add Condition)
- Đề xuất: thanh dính trên bàn phím "Search · 1,284 photos" 50pt. Media Type và Match gộp một hàng (~44pt thay vì ~250pt). Ở regular/short, mỗi điều kiện một dòng `[field▾][op▾][value][−]`. Đếm kết quả đưa lên subtitle.
- Chi phí: M.
- Cần quyết định: không (comment "two-line iOS layout" chỉ nói về phone).

### M-26 Dòng gợi ý "Try:" trộn tiếng Việt vào UI tiếng Anh
- Màn / thiết bị: Search (lần đầu) · mọi thiết bị
- Mức: nên sửa (ba reviewer, 1 chuỗi)
- Nguồn: UX-15, HIG-19, PH-15
- Kiểm code: chưa kiểm (`SearchSuggestionsScreen.swift:208`)
- Đề xuất: ví dụ theo ngôn ngữ giao diện qua String Catalog ("ISO over 3200 · before 2020"). "Fukuoka" thay bằng một nơi chốn có thật trong thư viện.
- Chi phí: S.
- Cần quyết định: không.

### M-27 Không lọc được ảnh **thiếu** dữ liệu (không vị trí, không lens, không ngày)
- Màn / thiết bị: Advanced Search, Smart Album · mọi thiết bị
- Mức: nên sửa
- Nguồn: VOICE-07 · T14 (người có 78k ảnh bỏ app vì không lọc được)
- Kiểm code: chưa kiểm
- Đề xuất: toán tử `isMissing` cho mọi trường; trường Location "Has / No Location". Thanh "Unknown" trong chart chạm vào thì mở lưới có điều kiện đó.
- Chi phí: M.
- Cần quyết định: không.

### M-28 Lens cơ hoặc lens qua adapter rơi vào "Unknown" mà không gán lại được
- Màn / thiết bị: Library chọn nhiều, Statistics, Camera Database · mọi thiết bị
- Mức: gợi ý
- Nguồn: VOICE-08 · T4
- Kiểm code: chưa kiểm
- Đề xuất: lệnh "Set Lens…" lưu vào bảng riêng `lens_assignment`; query đọc `COALESCE(assignment, exif)`; Info ghi "Set by you"; Camera Database có thêm mục Lenses.
- Chi phí: L (migration, sheet, query).
- Cần quyết định: **có** (có làm trong đợt này không).

### M-29 Search tab: diễn giải là capsule phẳng, không phải token; bàn phím ăn landing page; quay lại tab thì ô trống
- Màn / thiết bị: Search · PH
- Mức: gợi ý
- Nguồn: HIG-17, PH-14
- Kiểm code: **đã kiểm code** phần auto-activate (`RootTabView.swift:215` `.tabViewSearchActivation(.searchTabSelection)`). Thứ tự xoá ô: runtime.
- Đề xuất: `searchable(tokens:)` cho brand/focal/ISO; quay lại tab thì điền sẵn và chọn hết chữ.
- Chi phí: M.
- Cần quyết định: **có**. HIG chia hai kiểu: (a) bàn phím bật ngay, bỏ landing; (b) landing đầy đủ, không auto-activate (lý do hiện tại là người dùng chê "chạm đầu không làm gì").

### M-30 Không có phạm vi "chỉ ảnh chụp bằng máy ảnh" (screenshot làm loãng % Top Camera)
- Màn / thiết bị: Library filter, Statistics · mọi thiết bị
- Mức: gợi ý
- Nguồn: VOICE-10
- Kiểm code: chưa kiểm
- Đề xuất: công tắc "Only Photos Shot with a Camera" (có camera make) trong menu lọc và trong Chart Editor.
- Chi phí: S.
- Cần quyết định: không.

## 5. Onboarding & index lần đầu

### M-31 Onboarding không nói trước hộp xin quyền, không nhắc chọn Full Access, không nói index mất bao lâu
- Màn / thiết bị: Onboarding · mọi thiết bị
- Mức: nên sửa
- Nguồn: PH-06, USER-06(a), persona Linh ("suýt chọn Limited theo thói quen")
- Kiểm code: chưa kiểm (`OnboardingScreen.swift:21` gọi `requestAuthorization()` ngay)
- Đề xuất: dòng `.footnote` 2 dòng trên nút: "Next, iOS asks for access to your photos. Choose Allow Full Access so every photo can be searched. Reading a large library takes a while the first time." Có thể đổi nút thành "Allow Photo Access".
- Chi phí: S (~36pt, lấy từ vùng trống sẵn có).
- Cần quyết định: không.

### M-32 Lúc đang index: Statistics/Duplicates báo "No Indexed Photos", Search trả thiếu mà không nói
- Màn / thiết bị: Statistics, Duplicates, Search, Advanced Search · mọi thiết bị
- Mức: nên sửa
- Nguồn: UX-08, USER-06(b)
- Kiểm code: **đã kiểm code**, có sắc thái. `StatisticsScreen.swift:136-141` chỉ hiện empty state khi `totalPhotos == 0`, tức chỉ ở những phút đầu. Phần đáng lo hơn là model chỉ nạp ở `.task`, nên số liệu không tự làm mới (runtime). `DuplicatesScreen.swift:225-230` bảo người dùng "Index your library from the Library tab", trong khi không có nút index nào.
- Đề xuất: khi `isIndexing`, dùng chung thẻ tiến độ của Library ("Reading photo info · 34%") + nhãn "Partial · 34% read" trên chart, làm mới khi `isIndexing` chuyển true→false. Duplicates: "ShotDex is still reading your library (34%)…" + "Show Progress". Search/Advanced: footer "Still reading photo info · 38% — results will grow."
- Chi phí: M (1 view chung + `onChange`).
- Cần quyết định: không.

### M-33 Onboarding: nút Continue xanh hệ thống cạnh icon amber; trên iPad nút trải 1320pt, nội dung dồn lên trên
- Màn / thiết bị: Onboarding · PH, IP
- Mức: nên sửa
- Nguồn: VIS-06, IP-12
- Kiểm code: chưa kiểm
- Đề xuất: regular width `maxWidth: 480`, pitch và nút canh giữa thành một khối. Spacing theo thang (28→24, 22→24, 6→8). Chỉ giữ một màu nhấn.
- Chi phí: S.
- Cần quyết định: **có**. (a) icon hàng dùng `.secondary`, Continue giữ xanh hệ thống (VIS khuyến nghị, không cần ngoại lệ); (b) tint Continue amber và ghi ngoại lệ có tên vào DESIGN §10.6.

### M-34 Re-index / Clear Index không nói quy mô và hệ quả
- Màn / thiết bị: Settings · mọi thiết bị
- Mức: gợi ý
- Nguồn: UX-14, HIG-19 (mục Re-index)
- Kiểm code: chưa kiểm
- Đề xuất: dòng phụ "Reads all 54,971 photos again. Takes a while; you can keep using ShotDex." Alert Clear Index thêm câu "Statistics and filters stay empty until indexing finishes."
- Chi phí: S.
- Cần quyết định: không.

### M-35 Alert "Saving was interrupted" bật ngay khi mở app, sai số nhiều
- Màn / thiết bị: Library · mọi thiết bị
- Mức: gợi ý
- Nguồn: HIG-11
- Kiểm code: chưa kiểm (`LibraryScreen.swift:178-200`)
- Đề xuất: đổi sang `AppBanner` có "Try Again"; sửa chuỗi inflect.
- Chi phí: S.
- Cần quyết định: không.

## 6. Share & riêng tư

### M-36 Share: header "Metadata removed" đi cùng hàng "Share Without Location" làm người dùng hiểu ngược
- Màn / thiết bị: Share sheet · mọi thiết bị
- Mức: nên sửa
- Nguồn: USER-04, persona Minh ("đọc ba lần vẫn chưa chắc") và An
- Kiểm code: **đã kiểm code**. `ShareLevelRow.swift:16-21` ba hàng "Share With Location / Without Location / Without Metadata". `:90-96` subtitle "Metadata removed".
- Vấn đề: "Without Location" đọc như lựa chọn an toàn hơn, nhưng so với mức hiện tại nó **thêm lại** thông tin máy và ống kính.
- Đề xuất: đặt tên theo thứ đi kèm ảnh: "Share With Camera Info", "Share With Camera Info & Location". Header "No metadata · HEIC sent as JPEG".
- Chi phí: S (chuỗi + bản dịch).
- Cần quyết định: **có**. Đổi tên đã chốt trong FS-08.06 §4. Phương án: (a) tên theo thứ đi kèm; (b) giữ tên cũ, chỉ đổi header.

### M-37 Resize và Collage Export kết thúc ở "saved to Photos", không có đường gửi đi
- Màn / thiết bị: Compress, Collage Export · mọi thiết bị
- Mức: nên sửa
- Nguồn: USER-03, USER-15, persona Minh (20 bản copy chen giữa bản gốc) và Linh (Instagram)
- Kiểm code: chưa kiểm
- Đề xuất: summary của Resize có nút chính "Share 20 Photos" mở share sheet với `createdAssetIDs`. Thêm Destination "Save to Photos / Share only (don't keep copies)", lựa chọn sau ghi ra file tạm. Collage Export có nút phụ "Share…" 44pt.
- Chi phí: M.
- Cần quyết định: **có**. Phương án: (a) chỉ nút Share sau khi lưu; (b) thêm Destination "Share only", không ghi vào thư viện. Tương tác với M-02 (`finishedCleanly` đang đóng thẳng màn).

### M-38 Video vẫn mang toạ độ khi share "No Location"
- Màn / thiết bị: Share sheet, Save to Files · mọi thiết bị
- Mức: nên sửa
- Nguồn: VOICE-06 · T10
- Kiểm code: chưa kiểm
- Đề xuất: export Passthrough + `AVMetadataItemFilter.forSharing()`. Spike trước để đo HEVC/ProRes và tốc độ. Nếu quá nặng, thêm nút "Remove Location from Videos".
- Chi phí: M (cần spike, đĩa tạm, tiến độ).
- Cần quyết định: **có**. Phản biện NF-03 §3 / FS-08.06 §2 ("Video share nguyên bản").

### M-39 Lời hứa riêng tư ở Onboarding không nhắc Share và log của Support
- Màn / thiết bị: Onboarding, Support · mọi thiết bị
- Mức: gợi ý
- Nguồn: VOICE-11 · T12
- Kiểm code: chưa kiểm
- Đề xuất: câu 4: "No account, no ads, no tracking. Your photos and their details stay on this device unless you share or upload them." Dưới công tắc log: "The log lists app events, never photos, names or places." (phải khớp `SupportModel`).
- Chi phí: S.
- Cần quyết định: không.

## 7. Server / upload nền

### M-40 Upload dừng khi app ra nền; iOS 26 đã có `BGContinuedProcessingTask`
- Màn / thiết bị: Upload to Server (và Resize hàng loạt, Rescan, Import) · IP chủ yếu, mọi thiết bị
- Mức: nên sửa
- Nguồn: USER-05, VOICE-04, UX-18, DUO-10 (gập Duo có thể đi qua `.background`), persona Minh ("điểm mình bực nhất") · T8 (người ta trả tiền PhotoSync vì chạy nền)
- Kiểm code: **đã kiểm code**. `ServerUploadSheet.swift:50-51`: `phase == .background` thì `model.cancel()`. `:170` "Keep ShotDex open until the upload finishes."
- Vấn đề: một ngày cưới là 40–60 GB RAW. Trả lời một tin nhắn là lô dừng, quay lại phải bấm "Upload Remaining".
- Đề xuất: trên iOS 26+, gửi `BGContinuedProcessingTaskRequest` ("Uploading 12 photos to Studio NAS"), báo progress theo file, `expirationHandler` dọn `.shotdex-part`. Dưới 26 giữ như cũ; câu nhắc đổi theo `#available`. Cùng khung đó dùng được cho Resize và Rescan.
- Chi phí: L (Info.plist `BGTaskSchedulerPermittedIdentifiers`, thử trên máy thật, đổi AC-15 của FS-15).
- Cần quyết định: **có**. Lật quyết định "Chạy nền: không" (intent 2026-09-24 dòng 125, FS-15 README:41). Phương án: (a) BGContinuedProcessing trên 26+; (b) giữ nguyên, thêm ước tính thời gian + local notification "Upload paused" (UX-18).

### M-41 Upload sheet: "Add Connection…" kẹp giữa Date Folders và lời giải thích của nó; tiệc qua nửa đêm bị chia hai thư mục
- Màn / thiết bị: Upload to Server · mọi thiết bị
- Mức: nên sửa
- Nguồn: USER-11, persona Minh
- Kiểm code: chưa kiểm. Board `PH_ServerUpload` (nay render đúng) xác nhận thứ tự Date Folders → Add Connection… → footer.
- Đề xuất: đưa "Add Connection…" vào cuối menu của picker Connection. Thêm lựa chọn "One folder for this upload" (tên theo ngày của tấm đầu, sửa được).
- Chi phí: S (thứ tự) · M (lựa chọn thư mục).
- Cần quyết định: **có** cho phần thư mục (sửa FS-15 §02): (a) chỉ đổi thứ tự; (b) thêm chế độ một thư mục.

### M-42 Server Browser: Select giấu trong ⋯, dấu ✓ "In Library" trông như đã chọn, Back tự vẽ có thể làm chết vuốt-cạnh
- Màn / thiết bị: Server Browser · mọi thiết bị
- Mức: nên sửa
- Nguồn: USER-08, HIG-18, PH-13, persona Minh
- Kiểm code: chưa kiểm (`ServerBrowserScreen.swift:40` `navigationBarBackButtonHidden(true)`, `:483`, `:820`). Vuốt-cạnh: runtime.
- Đề xuất: nút "Select" ra toolbar như Library. Glyph In Library đổi thành badge chữ hoặc `photo.badge.checkmark` mờ. Bật lại edge-swipe (hoặc dùng Back hệ thống khi lịch sử trống). Ở regular, chỉ một nút nổi "Import"; "Done" đổi thành `xmark`.
- Chi phí: S (~70pt toolbar; trên DC phải thu tiêu đề).
- Cần quyết định: không.

### M-43 Uploaded to Server: "giải phóng dung lượng" nằm trong ⋯ và không nói được bao nhiêu GB
- Màn / thiết bị: UploadedToServer · mọi thiết bị
- Mức: gợi ý
- Nguồn: UX-12, VIS-18
- Kiểm code: chưa kiểm
- Đề xuất: hàng đầu "Free Up Space — 214 photos · ~4.2 GB"; khi tắt thì ghi lý do; toast sau khi xoá. "All Uploaded Photos" lên làm section đầu, glyph `server.rack`.
- Chi phí: S (~56pt).
- Cần quyết định: không.

### M-44 Form server: Save được mà không cần Test; Test nằm ở đáy form
- Màn / thiết bị: ServerForm · PH, DI, DC
- Mức: gợi ý
- Nguồn: UX-16
- Kiểm code: chưa kiểm
- Đề xuất: Save khi chưa test thì chạy test ngầm và chỉ cảnh báo nếu lỗi ("Save Anyway / Edit"). "Servers Found" rút còn 3 hàng + "Show More".
- Chi phí: S.
- Cần quyết định: không.

## 8. Màn rộng iPad (và các công cụ nhỏ tầng D)

### M-45 Compress & Collage Export: nút chính nằm cuối cuộn; preview là thứ duy nhất bị thu nhỏ; cần ghim nút + 2 pane ở regular
- Màn / thiết bị: Compress, Collage Export · PH (nút dưới home indicator), IP (cột 700 giữa màn, bảng 1344pt), DI (preview 167pt, nút ~130–230pt dưới đáy)
- Mức: **blocker trên DI**, nên sửa trên PH/IP
- Nguồn: PH-04, IP-06, VIS-20, IP-07, DUO-04, DUO-05 (bốn reviewer)
- Kiểm code: **đã kiểm code** một phần. `CompressionScreen.swift:117` `maximumFormWidth = 700`; `exportButton` là phần tử cuối trong ScrollView. Board `PH_Compress` (nay đúng) cho thấy nút bị cắt ở mép dưới 874.
- Đề xuất: mọi thiết bị ghim nút chính vào `safeAreaInset(.bottom)` (~74pt). Regular hoặc short: `HStack` gồm preview/gallery bên trái (phần còn lại) và cột điều khiển 400pt bên phải, nút ghim đáy cột phải. Collage Export dùng cùng hình dạng đó.
- Chi phí: M (~40 dòng mỗi màn).
- Cần quyết định: không (§10.1d cho phép vì preview *là* nội dung; nên ghi thêm vào §10.1d).

### M-46 Duplicates trên iPad: mỗi nhóm một thẻ 1344pt, 80% rỗng; nút Delete trải 1320pt
- Màn / thiết bị: Duplicates · IP
- Mức: nên sửa
- Nguồn: IP-03
- Kiểm code: chưa kiểm
- Đề xuất: master–detail (danh sách nhóm 360pt + pane ô to khoảng 300pt có EXIF). Phương án rẻ: `LazyVGrid adaptive(420)` cho thẻ. Nút Delete rộng tối đa 360pt, sát cạnh phải.
- Chi phí: M (phương án rẻ: S).
- Cần quyết định: **có**: (a) master–detail; (b) lưới thẻ.

### M-47 Trips trên iPad: cover 1344×160 (8.4:1), một cột
- Màn / thiết bị: Trips · IP
- Mức: nên sửa
- Nguồn: IP-04
- Kiểm code: chưa kiểm
- Đề xuất: `adaptive(minimum: 320, maximum: 440)` → 3 cột. Request cover theo bề rộng cột. Có thể cao 240 nếu thêm Trips vào danh sách §10.1d.
- Chi phí: S.
- Cần quyết định: không (giữ cao 160 thì không cần đổi luật).

### M-48 Search Recents: thẻ vuông 437pt trên iPad (thumbnail bị phóng khoảng 2.7×), 267pt dưới bàn phím trên Duo inner
- Màn / thiết bị: Search · IP, DI
- Mức: nên sửa
- Nguồn: IP-05, DUO-07
- Kiểm code: chưa kiểm
- Đề xuất: regular: `adaptive(150…200)`, `maximumCards` từ 3 lên 6, `thumbnailPixels` theo cạnh thật. Short: `aspectRatio(2.4)`.
- Chi phí: S.
- Cần quyết định: không.

### M-49 Collage inspector tab Layout: dải cuộn ngang của điện thoại nhét trong cột 320pt, để trống 700pt
- Màn / thiết bị: Collage · IP
- Mức: nên sửa
- Nguồn: IP-08
- Kiểm code: chưa kiểm
- Đề xuất: ở `usesRegularToolChrome`, `templateStrip` thành `LazyVGrid` 4 cột cuộn dọc.
- Chi phí: S.
- Cần quyết định: không.

### M-50 Bàn phím: thiếu Esc/←/→ ở mọi full-screen cover trừ Editor/Collage/Video Studio; không có ⌘A, ⌘F
- Màn / thiết bị: Viewer, Compare, Compress, VideoTrim, Slideshow, Library · IP
- Mức: nên sửa
- Nguồn: IP-10
- Kiểm code: chưa kiểm
- Đề xuất: `.keyboardShortcut(.cancelAction)` cho 5 nút đóng. Viewer: ←/→ chuyển ảnh, Space play/pause. Library: ⌘A khi đang chọn, ⌘F tới Search.
- Chi phí: S.
- Cần quyết định: không.

### M-51 Con trỏ: thiếu hover và chuột phải ở thẻ Collections/Trips/Statistics, nút kính trước 26, ảnh trong Viewer
- Màn / thiết bị: Collections, Trips, Statistics, Viewer · IP
- Mức: gợi ý
- Nguồn: IP-14, IP-15
- Kiểm code: chưa kiểm (runtime cho hover với `.plain`)
- Đề xuất: `.hoverEffect(.highlight/.lift)`; `contextMenu` lặp lại các hàng ⋯ của ChartCard, thẻ Trips và ảnh trong Viewer.
- Chi phí: S.
- Cần quyết định: không.

## 9. Màn thấp Duo (verticalSizeClass / chiều cao cửa sổ)

### M-52 Mọi công tắc "màn rộng" chỉ nhìn chiều ngang; Duo inner nhận metric iPad với 669pt chiều cao
- Màn / thiết bị: Collections (hero 260 + tile 192), Statistics (Insights 190pt), Search, Widget pickers, Collage · DI (và cửa sổ iPad thấp)
- Mức: nên sửa (nguyên nhân gốc của M-45 (DI), M-48 (DI), M-53, M-25 (DI))
- Nguồn: DUO-02, VIS-09, DUO-12, DUO-13
- Kiểm code: **đã kiểm code**. grep `verticalSizeClass` trong `ShotDex/` ra 0 kết quả.
- Vấn đề: màn đầu của Collections chỉ thấy một hero và một hàng tile. Chrome cố định có khi vượt 1/3 chiều cao.
- Đề xuất: một environment `isShortWindow` (chiều cao cửa sổ dưới khoảng 720, đo ở `RootTabView`), để các `*Metrics` nhận cả giá trị này. Hero `min(260, max(180, 0.28 × containerHeight))` (khoảng 187 trên inner). Tile 140. Insights một dải khoảng 64pt. Ghi "669pt là chiều cao nhỏ nhất app hỗ trợ" vào DESIGN.md.
- Chi phí: M (1 key + khoảng 8 điểm gọi).
- Cần quyết định: **có**. Sửa DESIGN §10.1e ("180 compact → 260 regular"). Phương án: (a) công thức theo chiều cao container (VIS-09); (b) cờ `isShortWindow` nhị phân với hằng số riêng (DUO-02). Có thể kết hợp cả hai. Insights dạng dải cần nới FS-07.01 §6.

### M-53 Widget Settings: phần ghim chiếm 58–77% chiều cao, danh sách tuỳ chọn còn 160–280pt
- Màn / thiết bị: Widget Settings · DI, DC
- Mức: **blocker** (DI, cỡ Large)
- Nguồn: DUO-03
- Kiểm code: **đã kiểm code** chiều cao preview (`PhotoWidgetSettingsScreen.swift:186`: 158, Large thì 280; ghim ở `:45`). Tỉ lệ % là ước lượng, runtime.
- Đề xuất: khi `isShortWindow`, ẩn sidebar Settings và đặt preview cạnh list. Phương án rẻ: dòng hướng dẫn xuống footer, preview tối đa 158, cỡ Large vào popover.
- Chi phí: M (phương án rẻ: S).
- Cần quyết định: **có**: (a) chia hai cột; (b) phương án rẻ.

### M-54 Gập/mở Duo: lưới nhảy hàng trăm ảnh, Statistics cuộn về đầu, Search mất focus, ảnh Viewer không tải lại
- Màn / thiết bị: mọi lưới, Statistics, Search, Viewer · gập cover ↔ inner
- Mức: nên sửa
- Nguồn: DUO-09, DUO-10, DUO-11
- Kiểm code: chưa kiểm. Mọi dòng là runtime (simulator không có lệnh fold).
- Đề xuất: lưới giữ "ảnh đầu tiên nhìn thấy" làm neo khi bề rộng đổi (dùng lại `restoreScroll`). Statistics dùng một `ScrollView` + `LazyVGrid` đổi số cột thay vì hai nhánh. Search giữ focus ở model. Viewer gọi lại `loadDisplayImage` khi cạnh dài tăng hơn 1.3×.
- Chi phí: M.
- Cần quyết định: không.

### M-55 Vào chế độ chọn trên Duo inner: lưới đổi 9 → 10 cột ngay dưới ngón tay
- Màn / thiết bị: Library/Album chọn ảnh · DI
- Mức: nên sửa
- Nguồn: DUO-08
- Kiểm code: chưa kiểm (runtime: inset ngang có đổi khi rail ẩn hay không)
- Đề xuất: giữ số cột trong lúc `isSelecting`.
- Chi phí: S (mất 84pt bề ngang trong lúc chọn).
- Cần quyết định: không.

### M-56 On This Day: sheet chọn ngày `.medium` trên cover bị cắt, không cuộn được
- Màn / thiết bị: On This Day · DC
- Mức: nên sửa
- Nguồn: DUO-14
- Kiểm code: chưa kiểm (runtime)
- Đề xuất: `.presentationDetents([.height(440), .large])` hoặc bọc ScrollView.
- Chi phí: S (1 dòng).
- Cần quyết định: không.

### M-57 Adjust Location: bản đồ còn 40–140pt (hoặc biến mất) khi gõ tìm trên inner
- Màn / thiết bị: Adjust Location · DI
- Mức: nên sửa
- Nguồn: DUO-15
- Kiểm code: chưa kiểm (runtime: chiều cao bàn phím)
- Đề xuất: `resultList` dùng `frame(maxHeight: 220)` có ưu tiên thấp, hoặc đặt list cạnh bản đồ khi `isShortWindow`.
- Chi phí: S.
- Cần quyết định: không.

## 10. Statistics

### M-58 Số trong Statistics không có dấu phân cách hàng nghìn ("22640" cạnh trục "25,000")
- Màn / thiết bị: Statistics · mọi thiết bị
- Mức: nên sửa (rẻ nhất, ba nguồn)
- Nguồn: VIS-03, USER-16, persona Linh
- Kiểm code: **đã kiểm code**. `ChartCard.swift:12` `"\(Int(value.rounded()))"`, `:24` `String(Int(value))`. Settings cùng con số thì ghi "55,231".
- Đề xuất: `.formatted(.number)`, % qua `.percent`, `.monospacedDigit()` cho cột số. Ghi vào DESIGN §7.3. Cùng lỗi ở "Matches 1284 photos" trên board AdvancedSearch.
- Chi phí: S (5 dòng).
- Cần quyết định: không.

### M-59 Không có "Top Lens" trong bộ chart mặc định
- Màn / thiết bị: Statistics · mọi thiết bị
- Mức: nên sửa
- Nguồn: USER-12, persona Linh · T5 ("lens tiếp theo nên mua là gì")
- Kiểm code: **đã kiểm code**. `ChartSpec.swift:74-84`: Top Camera, Total, Equivalent Focal, Body + Lens, Slow Shutter, Photos per Month. Không có `.lens`.
- Đề xuất: thêm `ChartSpec(title: "Top Lens", kind: .bar, dimension: .lens, topN: 5)` ngay sau Top Camera. Tăng `currentSeedGeneration`. Không cần migration, theo luật "chưa release".
- Chi phí: S.
- Cần quyết định: không.

### M-60 Card bar: chart không nhãn và danh sách vẽ cùng một dữ liệu hai lần, không thẳng hàng
- Màn / thiết bị: Statistics · mọi thiết bị
- Mức: nên sửa
- Nguồn: VIS-02, USER-17 (phần bar), persona An ("phải dò từng thanh")
- Kiểm code: chưa kiểm (board `PH_Statistics` nay vẽ đúng: 5 thanh không tên, bên dưới là 5 dòng tên)
- Đề xuất: với bar có tối đa 10 hàng, vẽ thanh trong chính hàng: dòng 1 là nhãn + giá trị + %, dòng 2 là capsule 6pt. Hàng cao ít nhất 44pt và cả hàng là vùng chạm drill. Giữ `Chart` cho line/donut.
- Chi phí: M (~40 dòng `BarRow`).
- Cần quyết định: **có**: (a) thanh nội tuyến (VIS); (b) giữ Chart, ghi tên lên thanh khi topN ≤ 5 (USER-17).

### M-61 Chart Editor: Save xám vì tên trống dù ô hiện tên gợi ý; preview ở cuối list; Date Range là sheet chồng sheet
- Màn / thiết bị: Chart Editor · mọi thiết bị
- Mức: nên sửa
- Nguồn: HIG-04, PH-09, IP-09
- Kiểm code: **đã kiểm code**. `ChartEditorSheet.swift:96-100` `canSave` đòi `!trimmedTitle.isEmpty`, trong khi `draft` đã có fallback `defaultTitle`. Preview cũng phụ thuộc `canSave` (`:284`).
- Đề xuất: bỏ điều kiện tên khỏi `canSave`. Ghim preview 140pt ở đầu (compact), hoặc cột phải 420pt (regular). Date Range thành push (xem M-73).
- Chi phí: S (canSave) · M (preview ghim).
- Cần quyết định: không.

### M-62 Chart dùng indigo trong khi DESIGN.md nói chart ăn accent amber
- Màn / thiết bị: Statistics, Chart Editor · mọi thiết bị
- Mức: gợi ý
- Nguồn: VIS-04
- Kiểm code: chưa kiểm (`ChartPalette.swift:6-23`; board `PH_Statistics` cho thấy thanh tím)
- Cần quyết định: **có**: (a) `colors[0] = AppAccent`, series 2..8 giữ màu khác; (b) bỏ "charts" khỏi DESIGN §10.6 và `AppAccentTheme`.
- Chi phí: S.

### M-63 KPI: một con số chiếm một card khoảng 100pt; chia cột round-robin làm một cột iPad rỗng
- Màn / thiết bị: Statistics · IP (cột giữa), PH
- Mức: gợi ý
- Nguồn: VIS-05, IP-11
- Kiểm code: chưa kiểm
- Đề xuất: gom các KPI liền nhau thành hàng 2–4 tile 88pt; hoặc xếp vào cột đang ngắn nhất.
- Chi phí: S–M.
- Cần quyết định: **có**. Trái chữ "dealt round-robin" của §10.1c: (a) gom KPI; (b) xếp vào cột ngắn nhất; (c) giữ nguyên.

### M-64 Statistics → Library (drill-down): không có lối về, bộ lọc ở lại
- Màn / thiết bị: Statistics · mọi thiết bị
- Mức: gợi ý
- Nguồn: PH-16
- Kiểm code: chưa kiểm
- Đề xuất: chip đầu tiên "‹ Statistics", chạm vào thì xoá lọc và về tab.
- Chi phí: S.
- Cần quyết định: không.

## 11. Library & Collections (điều hướng, menu)

### M-65 Chế độ chọn: Compare/Edit/⋯/× đều ở hàng trên, chỉ Share và Delete ở đáy
- Màn / thiết bị: Library, Album, Smart Album · PH
- Mức: nên sửa
- Nguồn: PH-02
- Kiểm code: chưa kiểm (board `PH_LibrarySelect` khớp)
- Đề xuất: thanh đáy `[Share][Compare][pill "5・68.4MB"][Edit][Delete]`, nav còn ⋯ và ×.
- Chi phí: S (0pt chiều cao).
- Cần quyết định: **có**. Phản biện FS-01.06 §3 ("Compare và Edit nằm ở nav bar, bám Photos"). Phương án: (a) đưa xuống đáy; (b) chỉ thêm ⋯ vào đáy; (c) giữ nguyên.

### M-66 Menu ⋯ của chế độ chọn: 14–16 dòng; mục bị tắt không nói vì sao; "Combine Photos" lẫn với "Create Collage"
- Màn / thiết bị: Library chọn nhiều · mọi thiết bị (DI: 523/669pt)
- Mức: nên sửa
- Nguồn: DUO-16, USER-14, UX-09, persona Linh và Minh
- Kiểm code: **đã kiểm code** phần Paste Edits (`LibraryScreen.swift:585` chỉ hiện khi có clipboard). Phần Collage `.disabled` chưa kiểm.
- Đề xuất: hàng hai dòng có lý do: "Create Collage · Pick 2–9 photos". Đổi "Combine Photos" thành "Merge (HDR / Panorama)". Gom 3 submenu (Create ▸, Edit Info ▸, Organise ▸), để Select All/Favorite ở ngoài; còn tối đa 8 hàng.
- Chi phí: S.
- Cần quyết định: **có**. Paste Edits: (a) mờ nhưng luôn hiện, theo quy ước "dim, never vanish" của FS-01.09 §2 (UX-09); (b) ẩn như hiện nay (USER-14). Và có gom submenu hay không.

### M-67 Collections: tiêu đề section không chạm được, không có "See All"
- Màn / thiết bị: Collections · PH, DC chủ yếu
- Mức: nên sửa
- Nguồn: VIS-10, VOICE-09 · T1 (carousel che album của người dùng)
- Kiểm code: chưa kiểm
- Đề xuất: `CollectionSectionHeader` "My Albums ›" push tới lưới dọc (2 cột trên iPhone, adaptive trên iPad) có sort. Bổ sung "See All" vào §10.1d.
- Chi phí: M.
- Cần quyết định: không.

### M-68 Một thứ nhiều tên: Add to Collection / Your Albums / My Albums / Remove from Album
- Màn / thiết bị: menu chọn nhiều, AddToCollectionSheet, Collections · mọi thiết bị
- Mức: nên sửa
- Nguồn: UX-10
- Kiểm code: chưa kiểm
- Đề xuất: lệnh "Add to Album"; "Your Albums" đổi thành "My Albums"; "Collections" chỉ là tên tab.
- Chi phí: S.
- Cần quyết định: không.

### M-69 Utilities: "Cloud" mang icon iCloud nhưng là Dropbox/Drive; "Unable to Upload" đứng cạnh "Local Network"
- Màn / thiết bị: Collections › Utilities · mọi thiết bị
- Mức: nên sửa
- Nguồn: USER-09, persona Minh
- Kiểm code: chưa kiểm
- Đề xuất: "Cloud Folders" + icon thư mục. "Unable to Upload" đổi thành "iCloud Upload Errors" hoặc dời xuống cạnh Recently Deleted.
- Chi phí: S.
- Cần quyết định: không.

### M-70 Tiêu đề ngày của Library (18 ký tự) tranh chỗ với token Indexing trên 402/382pt
- Màn / thiết bị: Library · PH, DC
- Mức: gợi ý (runtime)
- Nguồn: HIG-13
- Kiểm code: chưa kiểm
- Đề xuất: chụp lúc đang index với tháng có tên dài. Nếu bị cắt thì dùng "Sep 30, 2026" khi `isIndexing`.
- Chi phí: S.
- Cần quyết định: không.

### M-71 Settings trên iPhone là một danh sách dài, iPad thì có sidebar 9 mục có icon
- Màn / thiết bị: Settings · PH, DC
- Mức: gợi ý
- Nguồn: VIS-11, persona Minh (tìm "NAS" phải dùng Search Settings)
- Kiểm code: chưa kiểm
- Đề xuất: trang gốc trên iPhone là 9 hàng `Label` + chevron, dùng `SettingsSection.allCases`.
- Chi phí: S–M (thêm 1 chạm cho Re-index; sửa §10.1).
- Cần quyết định: **có**: (a) danh sách mục như Settings hệ thống; (b) giữ một danh sách dài.

## 12. HIG / sheet

### M-72 Sheet nhập liệu vuốt xuống là mất bản nháp, không hỏi
- Màn / thiết bị: Smart Album Editor, Chart Editor, Add/Edit Connection, Advanced Search · mọi thiết bị
- Mức: nên sửa
- Nguồn: HIG-07
- Kiểm code: **đã kiểm code** (grep `interactiveDismissDisabled` trong bốn file ra 0)
- Đề xuất: `isDirty` + `.interactiveDismissDisabled(isDirty)` + alert "Discard Changes?" khi bấm Cancel.
- Chi phí: S.
- Cần quyết định: không.

### M-73 Sheet mở sheet (ba cặp: Chart Editor → Date Range; Advanced → Save as Smart Album; Upload → Add Connection)
- Màn / thiết bị: các sheet trên · mọi thiết bị
- Mức: nên sửa
- Nguồn: HIG-08, PH-09 (Date Range)
- Kiểm code: chưa kiểm
- Đề xuất: đổi thành push trong `NavigationStack` của sheet. Form server cần bỏ stack lồng.
- Chi phí: M.
- Cần quyết định: không.

### M-74 Collections và Statistics không có tiêu đề màn hình
- Màn / thiết bị: Collections, Statistics · mọi thiết bị
- Mức: nên sửa
- Nguồn: HIG-05, persona Linh ("Màn không có tiêu đề")
- Kiểm code: **đã kiểm code** (grep `navigationTitle` trong `AlbumsScreen.swift`, `StatisticsScreen.swift` ra 0)
- Đề xuất: `.navigationTitle("Collections"/"Statistics")`.
- Chi phí: S.
- Cần quyết định: **có**: (a) `.large` (theo DESIGN §7.1, tốn ~96pt khi chưa cuộn); (b) `.inline` (0pt); (c) ghi ngoại lệ có tên vào DESIGN.

### M-75 Vùng chạm dưới 44pt trong form và card tầng A
- Màn / thiết bị: rule builder, chip gợi ý, nút ⋯ của ChartCard/Insights · mọi thiết bị
- Mức: nên sửa
- Nguồn: HIG-09, VIS-15
- Kiểm code: chưa kiểm
- Đề xuất: `.frame(minWidth: 44, minHeight: 44).contentShape(.rect)` cho nút xoá điều kiện và ⋯ (giữ glyph nhỏ). ⋯ của card dùng `ellipsis` không vòng, hoặc chuyển vào `contextMenu`.
- Chi phí: S.
- Cần quyết định: không.

### M-76 Icon toolbar mơ hồ: "+" của Collections gánh luôn Customize; `slider.horizontal.3` cho 5 việc; ⇅ của Statistics trông như "sắp xếp"
- Màn / thiết bị: Collections, Viewer, Search, Filter, Server Browser, Statistics · mọi thiết bị
- Mức: nên sửa
- Nguồn: HIG-06, HIG-16, USER-17 (⇅), persona An
- Kiểm code: chưa kiểm
- Đề xuất: "+" chỉ còn New Album/Smart Album; Customize thành hàng cuối trang. Edit giữ `slider.horizontal.3` (ghi vào từ điển §8); Advanced đổi glyph hoặc dùng chữ. ⇅ vào menu "Add Chart / Reorder Charts".
- Chi phí: S.
- Cần quyết định: không.

### M-77 Sheet cao hết cỡ cho việc nhỏ: nút xác nhận luôn ở 120pt trên cùng
- Màn / thiết bị: Adjust Date & Time, Upload prep, Video Trim · PH
- Mức: gợi ý
- Nguồn: PH-11
- Kiểm code: chưa kiểm
- Đề xuất: detents `[.height(520), .large]` / `[.medium, .large]`; Trim có thêm nút Save ở panel đáy.
- Chi phí: S.
- Cần quyết định: không.

### M-78 Lặt vặt HIG/a11y
- Màn / thiết bị: Resize Presets, Filter menu, Selected Items, Customize · mọi thiết bị
- Mức: gợi ý
- Nguồn: HIG-19 (các mục còn lại)
- Kiểm code: chưa kiểm
- Đề xuất: Slider Quality có `accessibilityLabel`. All/Photos/Videos dùng Picker inline thay ba Toggle loại trừ nhau. Mỗi ô trong Selected Items có label riêng. Customize đổi "Done" thành "Close".
- Chi phí: S.
- Cần quyết định: không.

## 13. Nhất quán visual & từ ngữ

### M-79 Chữ trắng trên nền amber không đạt tương phản (2.4:1)
- Màn / thiết bị: Compress, DateRange, badge Support · mọi thiết bị
- Mức: nên sửa
- Nguồn: VIS-01
- Kiểm code: **đã kiểm code**. `CompressionScreen.swift:187` `.foregroundStyle(... : .white)` trên `accent`. Collage Export dùng `.black`.
- Đề xuất: `.black` (8.9:1) đúng như DESIGN §9; thêm token `AppAccent.onAccent`.
- Chi phí: S.
- Cần quyết định: không.

### M-80 Ba công cụ tầng D nhỏ vẽ ba kiểu segmented, nút chính và Cancel
- Màn / thiết bị: Compress, Collage Export, Video Trim · mọi thiết bị
- Mức: nên sửa
- Nguồn: VIS-07
- Kiểm code: chưa kiểm
- Đề xuất: `EditorPrimaryButton` + `EditorSegmentedPicker` dùng chung trong `EditorTheme`.
- Chi phí: M (2 component, khoảng 6 call site).
- Cần quyết định: **có**. Chọn một quy tắc "active" cho tool tầng D ngoài photo editor: (a) amber + glyph đen (§9); (b) trắng + glyph đen (§10.3).

### M-81 Pill/chip điều kiện lọc: 4 công thức capsule, nút Clear/Edit chép 3 lần, 2 kiểu nền
- Màn / thiết bị: Library FilterTokenBar, AdvancedSearch bar, Smart Album · mọi thiết bị
- Mức: nên sửa
- Nguồn: VIS-08
- Kiểm code: chưa kiểm
- Đề xuất: `GlassTextPill` (cao 32, padding 12) + `ConditionChip` trong `Shared/`; bỏ `.bar` ở `SmartAlbumConditionsBar`.
- Chi phí: M (~1 ngày, 5 file).
- Cần quyết định: không.

### M-82 Accent rò ra control chuẩn ở tầng A; vote chỉ khác nhau bằng màu
- Màn / thiết bị: Support, Camera Database, AutocompleteTokenField, DateRange · mọi thiết bị
- Mức: nên sửa
- Nguồn: VIS-12, HIG-15
- Kiểm code: chưa kiểm
- Đề xuất: control chuẩn (dấu check, `plus.circle`) về tint hệ thống. Vote: chưa vote là `arrowtriangle.up`, đã vote là `.fill` + trait `.isSelected`. Trạng thái ticket dùng `.secondary`, riêng Shipped dùng `.green`.
- Chi phí: S.
- Cần quyết định: **có**: thêm dòng "chỉ báo trạng thái tự vẽ" vào DESIGN §10.6 hay bỏ accent hoàn toàn.

### M-83 Ba công thức empty state, và DESIGN.md mô tả công thức thứ tư
- Màn / thiết bị: Library, Places, Trips, Collections, Duplicates, Statistics · mọi thiết bị
- Mức: nên sửa
- Nguồn: VIS-16
- Kiểm code: chưa kiểm
- Đề xuất: sửa DESIGN §11 thành "dùng `ContentUnavailableView`"; Places, Trips và Library đổi theo.
- Chi phí: S.
- Cần quyết định: **có** (đổi §11): (a) theo hệ thống (khuyến nghị); (b) theo §11 hiện tại.

### M-84 Tiêu đề alert lỗi chung chung; "Import" và "download" cùng một việc
- Màn / thiết bị: Library, Album, Smart Album, Duplicates, Import sheet · mọi thiết bị
- Mức: gợi ý
- Nguồn: HIG-12, USER-19
- Kiểm code: chưa kiểm
- Đề xuất: tiêu đề kiểu "Couldn't <việc>"; sửa DESIGN §11 (đang bắt "<Nơi> Error"); dùng "import" ở mọi chỗ.
- Chi phí: S–M.
- Cần quyết định: không (theo HIG).

### M-85 Hằng số ngoài thang: radius, spacing, 90pt chừa chrome, chevron
- Màn / thiết bị: nhiều màn · mọi thiết bị (90pt: iOS 17–25)
- Mức: gợi ý (nit)
- Nguồn: VIS-13, VIS-14, VIS-17, VIS-21
- Kiểm code: chưa kiểm
- Đề xuất: `RoundedRectangle.app(token)`; `AppTheme.Size.bottomChromeClearance` thay cho 90 ở 4 màn; lint nhỏ trong `Tools/`; ghi chevron tự vẽ vào DESIGN.
- Chi phí: S mỗi chỗ (mỗi lần đổi 2pt phải chụp sim).
- Cần quyết định: không.

## 14. Quy trình & sản phẩm (chưa phải lỗi UI hôm nay)

### M-86 Spec "mua đứt": ghi các lời than của người dùng thành AC ngay bây giờ
- Mức: gợi ý (đầu vào cho `/spec`)
- Nguồn: VOICE-05 · T11
- Đề xuất: Delete, Duplicates, Share, Upload và tải ảnh gốc **không bao giờ** bị khoá. Giá hiện trước khi chạm. Không màn bán hàng nào sau khi mua. `requestReview` tối đa 1 lần mỗi phiên bản. Không có gói "Plus".
- Cần quyết định: **có** (chữ "xuất" trong intent 30/9 đang để mở).

### M-87 Từ ngày ship: gỡ hay dời chỗ một control phải ghi vào What's New
- Mức: gợi ý
- Nguồn: VOICE-13 · T16
- Đề xuất: thêm một dòng vào `/release-check` và REVIEW.md.

### M-88 iOS 27 gộp Search vào thanh tab: kiểm lại trên Duo 27
- Mức: gợi ý
- Nguồn: VOICE-12 · T2
- Đề xuất: chạy `ios26-parity`/`device-layout` cho Library và Search trên Duo iOS 27. Không đổi quyết định "search tab stays".

---

## Lỗi board (sửa canvas, không sửa app)

1. **`*_Compress` vẽ "Delete Originals" TẮT**, trong khi code mặc định BẬT (`CompressionController.swift:48`, đã kiểm). Board giấu đúng điểm của M-02. Nguồn: UX-19(b). Đã xem `PH_Compress.png`.
2. **Glyph Settings vẽ thành mặt trời** trên `PH_Collections`, `IP_Collections`, `DC_Collections`, `IP_Library`, `DC_Share`. Code dùng `gearshape`, và `PH_Statistics`/`Main` vẽ đúng bánh răng. Nguồn: USER-20 (phần icon), persona An. Đã xem `PH_Collections.png`.
3. **Hai kiểu sidebar Settings trên iPad:** `IP_Settings` vẽ capsule xám đặc cho mọi hàng, `IP_ServerList` vẽ hàng trơn có icon. Code chỉ có một `List(selection:)`. Nguồn: IP-16 (phần thật). Đã xem cả hai PNG.
4. **`DC_Onboarding`:** caption nói lời hứa cuối bị cắt dưới nút Continue, nhưng hình hiện đủ 4 lời hứa. Caption hoặc hình sai (chưa kiểm). Nguồn: DUO-18.
5. **`PH_LibrarySelect` vẽ "Paste Edits" như đang bật** mà không ghi là trạng thái đã copy edit. Nên ghi vào caption, hoặc vẽ trạng thái mặc định (không có hàng đó). Nguồn: USER-14.
6. **Thiếu artboard cho các trạng thái người dùng chắc chắn gặp** (nối vào hàng của từng thiết bị theo quy ước):
   Library đang index (token + thẻ mở rộng), Statistics đang index, Duplicates "Scanning N of M"/rỗng, ServerUpload "File Already Exists", UploadedToServer rỗng,
   `ServerDownloadSheet` (Import), Viewer đang tải iCloud, `DI_WidgetSettings` cỡ Large (ca xấu nhất của M-53), `DI_Search` có bàn phím đo thật.
   Nguồn: UX-19, USER-21, DUO-18.

---

## Người dùng nói gì

Nguồn: user-voice.md §1 (review App Store, Apple/Adobe Community, báo chí; Reddit bị chặn) và lời ba persona.

- **Sợ app dọn ảnh xoá nhầm** là chủ đề 1★ dày nhất ở Gemini, Cleanup, Remo. Một review Gemini (5/2025) kể app xoá cả bản gốc lẫn bản sao. Đây là lý do M-01 xếp đầu.
- **Duyệt ảnh trùng là việc dài mà không biết bản nào đáng giữ.** Người dùng mất 4 giờ đánh dấu vì app tự bỏ chọn (Gemini 9/2025); không biết bản nào nằm trong album (Cleanup 8/2024). Liên quan M-03, M-04.
- **Thu app xuống là việc dài dừng luôn.** Người dùng Remo, Gemini phải để màn hình mở hàng giờ; PhotoSync bán tính năng chạy nền thành gói trả tiền riêng. Liên quan M-40.
- **Muốn lọc theo lens/body mà không có giao diện.** Thread Adobe Community từ 2018 vẫn còn người trả lời. Câu trích: "Would love to filter by lens type, similar to camera body filter". Liên quan M-21.
- **Một lens mang hai tên, lens cơ thành "Unknown"** (Kirkville, Fuji-X Forum). Liên quan M-28, và `LensNormalizer` đã có sẵn.
- **Phải nhớ tắt vị trí mỗi lần share, và video vẫn lộ toạ độ.** Thread Apple Community có 27 người "Me too"; Fluntro bị chê vì MOV còn GPS. Liên quan M-36, M-38.
- **Mệt subscription, sợ "lifetime" bị đổi luật, ghét phải trả tiền mới được xoá ảnh của mình** (Darkroom, Photomator, Cleanup). Liên quan M-86.
- **Persona Linh:** "App này hiện ISO, tiêu cự, khẩu ngay trên từng ô ảnh" — "zoom vào vẫn nhoè như nhau" (M-13, M-22).
- **Persona Minh:** "Dở nhất là phải để iPad đứng yên cho tới khi upload xong"; Share "đọc ba lần vẫn chưa chắc mình chọn đúng" (M-40, M-36, M-37).
- **Persona An:** "nút gần ngón cái nhất trong viewer lại là thùng rác", nhưng tab rail trên màn ngoài "dưới ngón cái… rất sướng" (M-20).

---

## Top 15 (xếp chéo mọi chủ đề)

| # | ID | Mục | Mức | Chi phí | Nguồn |
|---|---|---|---|---|---|
| 1 | M-01 | Merge All Groups ghi metadata trước khi xác nhận, chạy cả ở Series | blocker | S–M | UX-04, HIG-02, VOICE-01, T6 |
| 2 | M-02 | Resize: Delete Originals bật sẵn, nút không nói, đóng im lặng | nên sửa | S | UX-01, PH-04, VIS-01, Minh |
| 3 | M-14 | Photo Info/Burst không có nút Done (kẹt trên Duo inner) | blocker | S | DUO-01 |
| 4 | M-13 | Compare zoom chỉ là ảnh cỡ màn hình | blocker | M–L | USER-02, Linh |
| 5 | M-40 | Upload dừng khi ra nền (BGContinuedProcessingTask) | nên sửa | L | USER-05, VOICE-04, UX-18, DUO-10, T8 |
| 6 | M-03 | Dấu xoá ở Duplicates mất khi đổi tab/Back | nên sửa | S–M | UX-05, VOICE-03, T7 |
| 7 | M-10 | Viewer/Compare: favorite/xoá lỗi im lặng | nên sửa | S | UX-02 |
| 8 | M-45 | Compress/Collage Export: ghim nút + 2 pane | blocker DI / nên sửa | M | PH-04, IP-06, VIS-20, IP-07, DUO-04, DUO-05 |
| 9 | M-36 | Tên mức Share bị hiểu ngược | nên sửa | S | USER-04, Minh, An |
| 10 | M-52 | Không có nhánh màn thấp (verticalSizeClass = 0) | nên sửa | M | DUO-02, VIS-09, DUO-12, DUO-13 |
| 11 | M-31 | Onboarding không chuẩn bị hộp quyền / Full Access | nên sửa | S | PH-06, USER-06, Linh |
| 12 | M-32 | Trạng thái đang index ở Statistics/Duplicates/Search | nên sửa | M | UX-08, USER-06 |
| 13 | M-21 | Lọc Camera/Lens ngay trong Library | nên sửa | S/M | PH-05, IP-02, T3 |
| 14 | M-12 | Thành công im lặng sau hành động hàng loạt | nên sửa | S | UX-06, UX-13 |
| 15 | M-58 | Số Statistics không có dấu phân cách | nên sửa | S | VIS-03, USER-16, Linh |

Rẻ và đáng làm ngay sau top 15: M-07 (confirmationDialog → alert), M-72 (bản nháp mất khi vuốt), M-59 (Top Lens), M-61 (Save của Chart Editor), M-79 (chữ đen trên amber), M-26 (chuỗi "Try:"), M-74 (tiêu đề màn).

## Kiểm code: tóm tắt

Có 29 mục "đã kiểm code" (mở đúng file:line và thấy đúng như mô tả; M-08, M-29, M-45, M-66 chỉ kiểm một phần), bao trùm cả 15 claim quan trọng nhất. Không claim quan trọng nào sai. Hai sắc thái:
- M-32: empty state của Statistics chỉ hiện khi `totalPhotos == 0`, tức những phút đầu. Vấn đề dai dẳng hơn là số liệu không tự làm mới (runtime).
- M-22: chip Filename là chủ ý có comment trong code. Mục được giữ nhưng hạ từ blocker xuống nên sửa.

Các claim bị loại vì sai: VIS-19 (Photo Info không phải kính trên ảnh), phần "ẩn Paste Edits" của USER-14 (code đã ẩn).
