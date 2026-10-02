# Persona walkthroughs: Linh, Minh, An

**Ghi chú về nguồn.** Mình xem các board qua bản tự render (`scratchpad/persona/render/`), không qua bản PNG gốc. Bản đó dùng `dc-runtime.js` của artifact làm `support.js`, nên có đủ lưới ảnh, chart và bàn phím. Bản PNG cũ trong `build/design/app/render/` thì chưa mở rộng các `{{…}}`. Mình đã đối chiếu với bản render lại của coordinator. Riêng bốn board `*_ServerUpload` vẫn hỏng ở cả hai bản vì script của board có lỗi cú pháp, xem USER-20. Mọi điều nói về hành vi ở đây đều đã kiểm trong Swift, có file:line đi kèm.

---

## 1. Linh: hobbyist, X-T5 + α7 IV, 55.000 ảnh, iPhone 17, bật Optimize Storage

**Lần đầu mở app (PH_Onboarding).** Icon cam, chữ ShotDex, bốn lời hứa. Dòng "Compare focal lengths across sensor sizes" làm mình thích ngay, vì mình dùng cả APS-C lẫn full-frame và luôn phải nhẩm ×1,5. Dòng "Your photos stay on your device" cũng làm mình yên tâm. Mình bấm Continue thì iOS hiện hộp hỏi quyền liền. Không ai dặn mình nên chọn "Allow Full Access", cũng không ai nói 55.000 ảnh cần bao lâu để đọc xong. Mình suýt chọn "Limited" theo thói quen.

**Library (Main).** Lưới 3 cột, mỗi ô ghi "ISO 400 · 85mm · f/1.8". Trời ơi, cái này đúng thứ mình cần, mấy app khác không có. Có badge RAW/HEIC nữa. Nhưng thực tế lúc này app còn đang đọc EXIF. Board không vẽ trạng thái đó, nên mình không biết mấy phút đầu mình sẽ thấy gì.

**Tìm "ảnh 85mm chụp đêm" (PH_Search → PH_AdvancedSearch).** Mình bấm kính lúp ở góc phải tab bar, gõ "85mm night". Capsule phía trên ghi kiểu "focal 85mm · filename night". Filename? Mình đâu có đặt tên file là night. Kết quả bằng 0. App không hiểu "đêm". Mình mở Advanced Search (nút ≡ trong ô tìm), mở danh sách điều kiện ra thì có Camera Brand, Lens, ISO, Shutter, Date Taken, nhưng không có giờ chụp. Cuối cùng mình phải tự chế: ISO ≥ 3200. Mà ảnh đêm chụp chân máy ISO 100 thì lọt mất. Đến lúc thấy album mẫu "Night ISO 3200+" trong Collections, mình hiểu luôn là chính app cũng phải đi đường vòng này.

Chuyện thứ hai: "85mm" ở đây là tiêu cự thật. Cái 56mm trên X-T5 của mình tương đương 85mm, vậy mà không được tính. Trong Advanced Search có công tắc Actual / FF Equivalent, nhưng capsule ở ô tìm chỉ ghi "focal 85mm", không nói là loại nào.

**So sánh 3 tấm gần giống nhau rồi xoá 2 tấm (PH_LibrarySelect → PH_Compare).** Mình bấm Select, chọn 3 tấm rồi bấm Compare ở góc trái. Trên màn Compare, ba thẻ xếp dọc một cột, mỗi lúc chỉ thấy khoảng hai tấm. Phản xạ đầu tiên của mình là chạm vào ảnh để xem to. Chạm xong thì ảnh bị đánh dấu xoá, viền đỏ hiện lên, mình giật mình. May là có dòng chữ "Tap a photo to mark it for deletion" và có thể chạm lại để bỏ. Mình pinch thì cả ba tấm cùng zoom theo. Hay quá, nhưng cũng chẳng chỗ nào trên màn hình nói như vậy.

Rồi mình zoom 5× để soi mắt mẫu, và ảnh nhoè như nhau cả ba. Mình không biết tấm nào nét hơn, hay chỉ là app đang cho mình xem bản thu nhỏ. Kiểm lại code thì đúng là app chỉ tải ảnh bằng cỡ màn hình. Nút "Delete 1 Photo" đỏ rõ ràng, chuyện đó thì tốt.

**Hay vào Duplicates (PH_Duplicates).** Mình phải mò ra nó nằm trong Collections › Utilities, mục cuối cùng. Thẻ nhóm "3 Photos" có nút Compare, tốt. Chú thích dưới ô ghi "6000 × 4000 · La…" và "Sep 14, 2…", nên mình không đọc được chữ quan trọng nhất ("Largest"). Mà kể cả đọc được thì "Largest" cũng vô nghĩa với ba tấm burst cùng độ phân giải.

**Lens nào mình dùng nhiều nhất? (PH_Statistics).** Màn không có tiêu đề, chỉ có ⚙, ⇅ và +. Card đầu tiên là Insights, câu "Sony α7 IV with FE 24-70mm took 23%" có ích. Card thứ hai là Top Camera, nhưng mình hỏi lens chứ không hỏi máy. Mình cuộn tiếp, qua Total Photos, qua Equivalent Focal Length, rồi mới tới "Body + Lens". Card này tách theo cặp, nên một lens gắn adapter lên hai body sẽ thành hai dòng. Muốn có "Top Lens" thì mình phải bấm + và tự dựng chart. Còn số trong danh sách là "22640" mà trục lại ghi "25,000", nhìn lệch nhau.

**Làm collage đăng Instagram (PH_Collage → PH_CollageExport).** Mình vào Select, ⋯, "Create Collage", và mình hơi khựng vì ngay trên có "Combine Photos ›". Hai cái này khác nhau thế nào? Vào editor rồi thì thấy có sẵn tỉ lệ 4:5. Tuyệt, đúng tỉ lệ feed Instagram. Ở màn Export, Size 2K và Quality 90 rõ ràng, "Keep EXIF of first photo" mặc định tắt, tốt. Nhưng nút duy nhất là "Save to Photos" ("Opens the new photo when done"). Mình phải lưu xong rồi mới bấm Share trong viewer. Thêm một bước, nhưng ít ra nó có nói trước.

## 2. Minh: thợ chụp cưới, iPad 13", NAS ở studio

**Đẩy ảnh chọn trong ngày lên NAS theo thư mục ngày (IP_LibrarySelect → IP_ServerUpload).** Mình chọn ảnh, bấm ⋯. Menu dài 16 dòng, "Upload to Server…" nằm ở dòng thứ 8, mình tìm cũng được. Sheet Upload hiện Connection "Studio NAS", Folder "Photos/2026", Date Folders. Dưới đó là "Add Connection…", rồi mới tới dòng giải thích "Photos go into year and day folders…". Mình đọc lần đầu cứ tưởng dòng giải thích đó nói về Add Connection.

Date Folders xếp theo ngày chụp, mà tiệc cưới thì kéo qua nửa đêm. Ảnh sau 0h sẽ rơi sang thư mục hôm sau, và một đám cưới bị chia làm hai thư mục. Phần Files (Only RAW / All Originals / Originals + Edited) rất đúng nhu cầu của mình, kèm dòng "12 photos · 19 files · ~486 MB".

Rồi tới dòng cuối: "Keep ShotDex open until the upload finishes." Một ngày cưới là 40 đến 60 GB RAW. Mình còn phải mở Lightroom trên chính cái iPad này. Chuyển app là lô upload dừng. Đây là điểm mình bực nhất.

**Thiết lập NAS (IP_ServerList, IP_ServerForm).** Lúc đầu mình vào Settings tìm chữ "NAS" hay "Server". Nó nằm trong Sharing and Export › File Servers, nhờ ô Search Settings mới tìm ra. Form Add Connection liệt kê sẵn "Studio NAS · SMB · SFTP · WebDAV" tìm được trong mạng. Hay. Chọn một cái là điền host luôn.

**Vào NAS duyệt và lấy 20 tấm về (IP_Collections → IP_ServerBrowser).** Trong Utilities có "Local Network" và "Cloud". "Cloud" mang icon iCloud, mình tưởng là iCloud Photos. Hoá ra là Dropbox/Drive. Còn "Unable to Upload" ngay bên cạnh, mình tưởng là danh sách ảnh đẩy lên NAS bị lỗi. Hoá ra là lỗi đồng bộ iCloud của Photos.

Vào "Hanoi trip", lưới 13 cột có badge RAW+JPG. Đẹp. Nhưng nút Select ở đâu? Library có chữ "Select" to ở góc phải, còn màn này chỉ có ⋯. Select nằm trong menu đó. Vài ô có dấu ✓ nhỏ ở góc dưới trái, và mình tưởng chúng đã được chọn sẵn. Thật ra dấu đó nghĩa là "In Library". Chọn 20 tấm, bấm "Import 20 to Library", sheet hiện "Skip Photos Already in Library". Hay, nhưng sheet này không có board, nên phần này mình đọc từ code. Trong cùng một sheet, tiêu đề ghi "Importing" mà dòng nhắc lại ghi "until the download finishes".

**Gửi khách JPEG nén, không có vị trí (IP_Share, IP_Compress).** Mình mở Share. Header ghi "DSC04218 · Metadata removed / HEIC sent as JPEG", bên dưới là hai dòng "Share With Location" và "Share Without Location". Metadata đã bị xoá rồi thì sao còn hỏi tới location? Mình bấm "Share Without Location" vì nghe an toàn hơn, nhưng thật ra nó **thêm lại** thông tin máy ảnh. Share cũng không cho chọn kích thước. Muốn nén thì phải dùng "Resize" (IP_Compress): 2048 px, JPEG, No Location, rõ ràng. Nhưng cuối cùng nó chỉ báo "8 saved to Photos" kèm nút Done. Mình phải quay ra Library, tìm 20 bản copy mới chen giữa ảnh gốc, chọn lại từng tấm rồi mới Share được. Và thư viện của mình giờ có thêm 20 bản trùng.

**Dọn máy (IP_UploadedToServer).** "Where They Are · Studio NAS · Photos/2026/2026-09-28 · 214", rồi trong ⋯ có xoá khỏi máy. Cái này mình cực thích. Mình biết chắc ảnh đã nằm trên NAS rồi mới xoá.

## 3. An: thích máy ảnh, iPhone Duo, dùng màn ngoài một tay trên metro

**Xem thống kê gear (DC_Statistics).** Rail tab nằm dọc bên phải, ngay dưới ngón cái phải. Tuyệt, đổi tab không cần với. Đọc Insights dễ. Bar của Top Camera không ghi tên, tên lại nằm trong danh sách bên dưới, nên mình phải dò từng thanh với từng dòng. Nút ⇅ mình tưởng là "sắp xếp", hoá ra là "Reorder charts". Nút ⚙ nằm ở góc trên trái, xa ngón cái nhất và sát góc bo của màn.

**On This Day (DC_Collections → DC_OnThisDay).** Card hero to, chạm một cái là vào. Header năm "2025 · 1 year ago" dạng capsule kính dễ đọc. Mở ra là đứng ở năm gần nhất, ở đáy, gần ngón cái. Hợp lý. Có một điều lạ: icon Settings ở Collections nhìn như mặt trời ☼, còn ở Library lại là bánh răng.

**Chia sẻ một tấm (DC_Viewer → DC_Share).** Thanh dưới của Viewer có Share ở bên trái và Delete ở bên phải. Cầm một tay bằng tay phải thì nút gần ngón cái nhất lại là… thùng rác. Share sheet ở detent medium vừa màn 382pt. Mình gặp lại đúng cái băn khoăn "Metadata removed" so với "Share Without Location" như anh Minh.

---

## Findings

### USER-01 "85mm night" ra 0 ảnh vì app không biết giờ chụp
- Màn / thiết bị: Search, Advanced Search, Smart Album Editor · mọi thiết bị
- Mức: blocker
- Ở đâu: APP. `SmartAlbumQuery.swift:30-46` (RuleField không có giờ chụp), `SearchService.swift:139-145` (chữ thừa bị đổi thành `Filename contains "night"`)
- Vấn đề: "Ảnh chụp đêm / golden hour / bình minh" là câu đầu tiên một người chụp du lịch nghĩ tới. Hiện giờ chữ "night" thành một chip Filename nên ra 0 kết quả, mà không câu nào giải thích. Chính album mẫu "Night ISO 3200+" trên board PH_Collections cho thấy cách duy nhất là lấy ISO thay cho giờ, và cách này bỏ sót toàn bộ ảnh đêm chụp chân máy ISO thấp.
- Đề xuất: Thêm RuleField `timeOfDay` (giờ theo giờ địa phương lúc chụp, kiểu số, toán tử "between" 0–23 có cho vắt qua nửa đêm). Thêm từ khoá trong parser: `night` = 19–05, `golden hour`/`sunset` = 17–19, `morning`. Khi còn chữ không hiểu, capsule nên ghi "‘night’ not understood" thay vì lặng lẽ biến nó thành filename. Chi phí: một cột giờ đã chuẩn hoá trong `photo_metadata` (do indexer ghi, đúng quy tắc), một nhánh parser, một hàng trong menu điều kiện.
- Bằng chứng: PH_Search, PH_AdvancedSearch, PH_Collections ("Night ISO 3200+"); `SearchIntentParser+Dates.swift:138-145` chỉ có today/lastweek…

### USER-02 Compare zoom 5× chỉ phóng bản ảnh cỡ màn hình, không soi được độ nét
- Màn / thiết bị: Compare · PH, IP, DI, DC
- Mức: blocker
- Ở đâu: APP. `CompareScreen.swift:805-830` (`targetSize = ActiveDisplay.pixelSize()`), `CompareScreen.swift:143` (`maximumZoomScale = 5`)
- Vấn đề: Mình vào Compare để chọn tấm nét nhất trong 3 tấm gần giống nhau. Ảnh 6000×4000 được tải ở khoảng 1206 px, nên zoom 5× ra một bản phóng to bị nội suy và cả ba nhoè như nhau. Nhiệm vụ cốt lõi của màn này vì thế không làm được.
- Đề xuất: Khi `zoomScale` vượt khoảng 1,5×, xin bản cắt vùng đang nhìn ở độ phân giải gốc (`PHImageManager` với `targetSize` = kích thước asset, hoặc `CGImageSourceCreateThumbnailAtIndex` với `kCGImageSourceThumbnailMaxPixelSize` theo vùng zoom) cho từng pane và đồng bộ theo `CompareScrollSynchronizer`. Trong lúc chờ, hiện vòng iCloud ở góc pane, giống Viewer. Chi phí: bộ nhớ (3–4 bản gốc giải mã, nên chỉ giải mã vùng nhìn thấy) và tải iCloud khi bật Optimize Storage. Nên cho `perf-profiler`/`memory-leak` xem.
- Bằng chứng: PH_Compare, IP_Compare; câu Linh nói "zoom 5× soi mắt thì nhoè như nhau"

### USER-03 Resize kết thúc ở "saved to Photos", không có đường gửi khách
- Màn / thiết bị: Resize (Compress) · mọi thiết bị
- Mức: nên sửa
- Ở đâu: APP. `CompressionScreen.swift:628-712` (CompressionSummary chỉ có nhãn kết quả và nút Done)
- Vấn đề: "Gửi khách 20 JPEG 2048px không có location" thành ra phải Resize, rồi quay về Library, tìm 20 bản copy mới chen giữa bản gốc, chọn lại, rồi Share. Thư viện còn dư 20 bản trùng. Share sheet thì đổi được metadata nhưng không đổi được kích thước.
- Đề xuất: Ở màn kết quả, thêm nút chính "Share 20 Photos" (mở share sheet với đúng `createdAssetIDs`). Kèm một lựa chọn trước khi chạy: Destination "Save to Photos / Share only (don't keep copies)". Lựa chọn sau ghi ra file tạm rồi share, không đụng thư viện. Chi phí: một segmented ở form 700pt và một nút ở summary. Không phá rule nào.
- Bằng chứng: IP_Compress, PH_Compress; `CompressionScreen.swift:640`

### USER-04 Share: "Metadata removed" đi cùng "Share Without Location" làm người dùng hiểu ngược
- Màn / thiết bị: Share sheet · PH, IP, DI, DC
- Mức: nên sửa
- Ở đâu: APP. `ShareLevelRow.swift:16-21` (tên các hàng), `:90-96` (subtitle của header)
- Vấn đề: Header ghi "Metadata removed", bên dưới có hai hàng "Share With Location" và "Share Without Location". Người dùng đọc "Without Location" thành "an toàn hơn", trong khi thật ra hàng này **thêm lại** thông tin máy và ống kính so với mức hiện tại. Cả Minh và An đều khựng ở đây.
- Đề xuất: Đặt tên theo thứ sẽ đi kèm ảnh, đừng theo thứ bị bỏ: "Share With Camera Info" (không location) và "Share With Camera Info & Location". Header đổi thành "No metadata · HEIC sent as JPEG". Chi phí: hai chuỗi và bản dịch. Nếu FS-08.06 §4 đã chốt tên thì đây là đề xuất đổi quyết định đó, với lý do là người dùng hiểu ngược ý.
- Bằng chứng: IP_Share, DC_Share, PH_Share

### USER-05 Upload dừng khi rời app: một ngày cưới không thể giữ iPad đứng yên
- Màn / thiết bị: Upload to Server · IP chủ yếu, mọi thiết bị
- Mức: nên sửa (đề xuất đổi quyết định đã ghi trong FS-15)
- Ở đâu: APP + docs. `ServerUploadSheet.swift:170-174`, `docs/02-functional-spec/FS-15-server-upload/README.md:41` và `02-upload-flow.md:98` ("App ra nền → lô dừng")
- Vấn đề: 40–60 GB RAW qua SMB mất hàng giờ. Minh cần mở Lightroom/Mail trên chính iPad đó. Chỉ cần chuyển app là lô dừng, quay lại phải bấm "Upload Remaining".
- Đề xuất: Phản biện quyết định "hệ thống chỉ cho vài chục giây". Từ iOS 26 có `BGContinuedProcessingTask`, dành đúng cho việc người dùng tự bấm chạy và hiện tiến độ trên hệ thống. Trên 26, đăng ký lô upload/import làm continued-processing task. Trước 26, giữ hành vi cũ. Dòng nhắc đổi thành "You can switch apps — progress shows in the status bar." Chi phí: tích hợp BGTask cùng chuyện huỷ, và kiểm SMB session còn sống khi app ra nền. Cần `swift-concurrency` xem.
- Bằng chứng: PH_ServerUpload, IP_ServerUpload (board hỏng, xem USER-20); FS-15 README:41

### USER-06 Lần đầu: không ai nói phải chờ đọc 55.000 ảnh, và Search lặng lẽ trả thiếu
- Màn / thiết bị: Onboarding, Library, Search · mọi thiết bị
- Mức: nên sửa
- Ở đâu: cả hai. APP: `OnboardingScreen.swift:21` (Continue gọi `requestAuthorization()` luôn, không có câu nào về Full Access hay thời gian index). `SearchSuggestionsScreen.swift` và `AdvancedSearchSheet.swift` không đọc `isIndexing` (chỉ `InsightsCard.swift:177` có). BOARD: không có board nào vẽ trạng thái đang index.
- Vấn đề: Linh chọn "Limited" theo thói quen thì Statistics sai. Nếu chọn Full Access thì ngay sau đó cô tìm "85mm" lúc mới đọc được 4.000/55.000 ảnh, và "Matches 312 photos" trông như kết quả cuối cùng.
- Đề xuất: (a) Thêm một dòng trên Continue ở Onboarding: "Next, iOS asks for access. Choose Allow Full Access so stats cover every photo. Reading 55,000 photos takes a while on first launch." (b) Trong Search và Advanced Search, khi `isIndexing`, thêm footer "Still reading photo info · 38% — results will grow." (c) Vẽ một board "PH_LibraryIndexing" có thẻ token mở rộng. Chi phí: hai chuỗi và một board.
- Bằng chứng: PH_Onboarding, Main, PH_AdvancedSearch ("Matches 1284 photos.")

### USER-07 "85mm" trong ô tìm không nói là tiêu cự thật hay tương đương
- Màn / thiết bị: Search · mọi thiết bị
- Mức: nên sửa
- Ở đâu: APP. `SearchIntentParser+Numbers.swift:28-30` (`85mm` thành `.focalLength`, tức tiêu cự thật). Capsule chỉ ghi "focal 85mm".
- Vấn đề: Người dùng nhiều hệ (X-T5 APS-C cùng α7 IV FF) nói "85mm" là nói góc nhìn. Ống 56mm trên Fuji bị loại mà capsule không hé lộ gì. Onboarding còn hứa "Full-frame equivalent views across all your cameras".
- Đề xuất: Capsule ghi "focal 85mm (actual)", chạm vào thì đổi sang "85mm equiv." (dùng lại công tắc Actual/FF Equivalent của Advanced Search). Nếu thư viện có từ hai sensor format trở lên, mặc định là equiv. Chi phí: một trạng thái trên capsule, không thêm màn.
- Bằng chứng: PH_Search ("brand Sony · focal 85mm"), PH_AdvancedSearch (Actual / FF Equivalent), PH_Onboarding

### USER-08 Server browser giấu Select trong ⋯, và dấu ✓ "In Library" trông như đã chọn
- Màn / thiết bị: Server Browser · PH, IP, DI, DC
- Mức: nên sửa
- Ở đâu: APP. `ServerBrowserScreen.swift:483` (Select nằm trong menu More), `:820` (glyph In Library)
- Vấn đề: Library, Album và On This Day đều có chữ "Select" ở góc phải. Riêng màn duyệt NAS, nơi việc chính là chọn rồi import, lại chỉ có ⋯. Dấu ✓ trắng khoảng 10pt ở góc dưới trái ô làm Minh tưởng ảnh đã được chọn sẵn.
- Đề xuất: Đưa nút "Select" ra toolbar cạnh ⋯, giống Library. Đổi glyph In Library thành badge chữ "In Library" hoặc icon `photo.badge.checkmark` mờ, để nó khác hẳn dấu chọn tròn accent. Chi phí: khoảng 70pt toolbar. Trên IP còn dư nhiều chỗ, trên DC thì phải thu tiêu đề folder.
- Bằng chứng: IP_ServerBrowser, PH_ServerBrowser, DC_ServerBrowser

### USER-09 Utilities: "Cloud" mang icon iCloud nhưng là Dropbox/Drive; "Unable to Upload" đứng cạnh "Local Network"
- Màn / thiết bị: Collections › Utilities · mọi thiết bị
- Mức: nên sửa
- Ở đâu: APP. `AlbumsScreen.swift:656-680`
- Vấn đề: Với người bật Optimize Storage, "Cloud" kèm `icloud` có nghĩa là ảnh đang nằm trên iCloud. "Unable to Upload" (lỗi đồng bộ iCloud của Photos) đứng cạnh "Local Network", nên Minh hiểu thành ảnh đẩy lên NAS bị lỗi.
- Đề xuất: Đổi thành "Cloud Folders" với icon `folder.badge.person.crop` hoặc `externaldrive.connected.to.line.below`. Đổi "Unable to Upload" thành "iCloud Upload Errors", hoặc đưa nó xuống cạnh Recently Deleted. Chi phí: chuỗi và icon. Comment trong code nói thẻ 190pt cắt "On Local Network", và "Cloud Folders" là 13 ký tự nên vẫn vừa.
- Bằng chứng: IP_Collections, PH_Collections

### USER-10 Compare: chạm vào ảnh là đánh dấu xoá, và không có gì cho biết zoom đang đồng bộ
- Màn / thiết bị: Compare · PH, DC chủ yếu
- Mức: nên sửa
- Ở đâu: APP. `CompareScreen.swift:457-470` (hint), `:17-20` (sync luôn bật, không có điều khiển)
- Vấn đề: Phản xạ của người dùng Photos là chạm để xem to. Ở đây chạm là viền đỏ và icon thùng rác. Hint chỉ hiện ở góc trên phải, chữ caption trắng 75%. Pinch đồng bộ cả ba pane là thứ đáng khoe, nhưng chỉ khám phá được nhờ tình cờ. Trên PH, mỗi lúc chỉ thấy khoảng 2 trong 3 thẻ.
- Đề xuất: Chạm một lần thì mở pane đó ra toàn màn (vẫn giữ zoom chung), việc đánh dấu xoá chỉ làm qua vòng tròn ở góc trên phải (vòng này đã có). Thêm một chip "Zoom linked" nhỏ, chạm vào để tắt. Trên PH, với 3 ảnh trở lên, cho phép thu thẻ để thấy 3 tấm cùng lúc. Chi phí: đổi hành vi chạm. Phải cập nhật FS của Compare.
- Bằng chứng: PH_Compare, DC_Compare

### USER-11 Upload: "Add Connection…" kẹp giữa Date Folders và lời giải thích của nó; tiệc cưới qua nửa đêm bị chia hai thư mục
- Màn / thiết bị: Upload to Server · mọi thiết bị
- Mức: nên sửa
- Ở đâu: APP. `ServerUploadSheet.swift:147-156`
- Vấn đề: Footer "Photos go into year and day folders…" nằm ngay dưới "Add Connection…", nên ai đọc cũng tưởng nó giải thích Add Connection. Date Folders xếp theo ngày chụp, nên một đám cưới 16h–1h thành hai thư mục `2026-10-02` và `2026-10-03`.
- Đề xuất: Đưa "Add Connection…" lên hàng đầu của section, dưới Connection (hoặc vào menu của picker Connection như mục cuối). Thêm lựa chọn "One folder for this upload" để đặt tên theo ngày của tấm đầu tiên, sửa được, ví dụ `2026-10-02 Lan & Huy`. Chi phí: một dòng picker. Cần sửa FS-15 §02.
- Bằng chứng: PH_ServerUpload, IP_ServerUpload (đọc từ code vì board hỏng)

### USER-12 Không có "Top Lens"; câu hỏi phổ biến nhất phải tự dựng chart
- Màn / thiết bị: Statistics · mọi thiết bị
- Mức: nên sửa
- Ở đâu: APP. `ChartSpec.swift:76-82` (6 chart mặc định: Top Camera, Total, Equivalent Focal, Body + Lens, Slow Shutter, Photos per Month)
- Vấn đề: "Mình dùng ống nào nhiều nhất" là lý do số một để mở tab này. Body + Lens tách một ống thành nhiều dòng khi ống đó dùng trên hai body, và nó nằm ở vị trí thứ 4.
- Đề xuất: Thêm "Top Lens" (`dimension: .lens`, topN 5) vào seed và đặt ngay sau Top Camera. Phải tăng `currentSeedGeneration` lên 3, nhưng app chưa release nên không cần migration (theo CLAUDE.md). Chi phí: một dòng spec và một chart cao khoảng 300pt.
- Bằng chứng: PH_Statistics, DC_Statistics

### USER-13 Duplicates: "Largest" bị cắt còn "La…", và "lớn nhất" không giúp chọn tấm đẹp nhất
- Màn / thiết bị: Duplicates · PH, DC
- Mức: gợi ý
- Ở đâu: APP. `DuplicatesScreen.swift:424-442` (`lineLimit(1)`, chuỗi `"\(w) × \(h) · Largest"`)
- Vấn đề: Ô rộng 110pt chỉ hiện "6000 × 4000 · La…" và "24.6 MB · Sep 14, 2…". Trong chế độ Similar, ba tấm burst cùng độ phân giải thì "Largest" (theo dung lượng file) chẳng nói lên điều gì.
- Đề xuất: Đổi thành badge nhỏ "Largest" ở góc ô thay vì chữ trong caption. Bỏ năm khỏi ngày khi cả nhóm cùng năm ("Sep 14"). Nếu có thể, ở chế độ Similar dùng điểm nét của Vision (`VNCalculateImageAestheticsScoresRequest`, iOS 18+) để gợi ý "Sharpest". Chi phí: phần badge rẻ; phần điểm nét cần thêm một lượt tính.
- Bằng chứng: PH_Duplicates, DC_Duplicates

### USER-14 Menu ⋯ khi chọn ảnh có 16 dòng, mở đầu bằng "Paste Edits", và "Combine Photos" lẫn với "Create Collage"
- Màn / thiết bị: Library select · PH, IP, DC
- Mức: gợi ý
- Ở đâu: cả hai. APP `SelectionBarViews.swift:293+`. Trên BOARD, "Paste Edits" trông như đang bật dù chưa copy edit nào.
- Vấn đề: Linh cần "Create Collage" nhưng lại thấy "Combine Photos ›" ngay trên và không phân biệt được. Hành động đầu menu là thứ người hobbyist hiếm khi dùng. Trên PH, menu che gần hết lưới.
- Đề xuất: Ẩn "Paste Edits" khi clipboard edit rỗng. Đổi "Combine Photos" thành "Merge (HDR / Panorama)" để nói rõ nó làm gì. Gom Favorite, Adjust Date & Time, Adjust Location và Hide vào một submenu "Edit Info". Chi phí: chuỗi và cấu trúc menu.
- Bằng chứng: PH_LibrarySelect, IP_LibrarySelect, DC_LibrarySelect

### USER-15 Collage export chỉ có "Save to Photos", muốn đăng Instagram phải thêm một vòng
- Màn / thiết bị: Collage Export · mọi thiết bị
- Mức: gợi ý
- Ở đâu: APP. `CollageExportScreen.swift`
- Vấn đề: Mục tiêu là đăng bài, nhưng app chỉ lưu rồi mở viewer, và người dùng phải bấm Share thêm lần nữa. Dòng "Opens the new photo when done" có giúp đỡ phần nào.
- Đề xuất: Thêm nút phụ "Share…" (icon share) cạnh "Save to Photos", hoặc biến nút chính thành split. Chi phí: khoảng 44pt bên cạnh nút 52pt.
- Bằng chứng: PH_CollageExport, DC_CollageExport

### USER-16 Số trong danh sách Statistics không có dấu phân cách hàng nghìn ("22640" cạnh trục "25,000")
- Màn / thiết bị: Statistics · mọi thiết bị
- Mức: gợi ý
- Ở đâu: APP. `ChartCard.swift:24-26` (`String(Int(value))`)
- Vấn đề: Trục ghi "25,000" còn danh sách ghi "22640". Hai cách viết số nằm sát nhau, và sang tiếng Việt hay tiếng Đức càng lệch.
- Đề xuất: Dùng `value.formatted(.number)` cho số nguyên. Chi phí: một dòng.
- Bằng chứng: PH_Statistics, DC_Statistics

### USER-17 Statistics: ⇅ trông như "sắp xếp" nhưng là "Reorder charts"; bar không có nhãn
- Màn / thiết bị: Statistics · PH, DC
- Mức: gợi ý
- Ở đâu: APP. `StatisticsScreen.swift:62-66`
- Vấn đề: An bấm ⇅ để sắp xếp danh sách camera thì cả dashboard lại vào chế độ sửa. Bar của Top Camera không ghi tên, nên phải dò với danh sách bên dưới.
- Đề xuất: Bỏ ⇅ khỏi toolbar và đưa "Reorder Charts" vào menu của nút + (đổi nút này thành ⋯ có "Add Chart" và "Reorder Charts"). Hoặc dùng `list.bullet` với chữ "Edit". Ghi tên ngay trên thanh bar khi topN ≤ 5. Chi phí: một nút ít đi; nhãn bar chiếm 13pt mỗi thanh.
- Bằng chứng: PH_Statistics, DC_Statistics

### USER-18 Màn ngoài Duo: nút gần ngón cái nhất là thùng rác; Settings và Back nằm ở góc xa nhất
- Màn / thiết bị: Viewer, Library, Statistics, On This Day · DC
- Mức: gợi ý
- Ở đâu: cả hai. Cần đo bằng `Tools/sim-shot … cover` vì trên board, nút 44pt ở (16, 8) nằm trong vùng bo góc khoảng 66pt.
- Vấn đề: Cầm một tay phải trên metro thì thanh dưới của Viewer có Share ở x≈46 (xa) và Delete ở x≈336 (gần ngón cái). Settings hay Back ở góc trên trái là điểm khó với nhất và còn sát góc bo.
- Đề xuất: Giữ quy ước của Photos trên iPhone, nhưng trên màn ngoài (chiều ngang 382pt, rail bên phải) thì đảo: Share sang phải, Delete sang trái. Hoặc ít nhất đưa Share vào rail. Chi phí: một nhánh layout riêng cho cover; lệch với Photos thì phải lý giải trong DESIGN.md. Nhờ `duo-ux-review` xác nhận.
- Bằng chứng: DC_Viewer, DC_Library, DC_Statistics, DC_OnThisDay

### USER-19 Sheet Import dùng cả "Import" lẫn "download" cho cùng một việc
- Màn / thiết bị: Import from server · mọi thiết bị
- Mức: gợi ý
- Ở đâu: APP. `ServerDownloadSheet.swift:60-62` ("Import to Library / Importing"), `:209` ("…until the download finishes"), `:226` ("Downloading")
- Vấn đề: Nút ghi "Import 20 to Library", tiêu đề ghi "Importing", còn dòng nhắc lại ghi "download". Người dùng tự hỏi đây là hai bước hay một.
- Đề xuất: Dùng "import" ở mọi chỗ: "Keep ShotDex open until the import finishes." Chi phí: chuỗi.
- Bằng chứng: code (sheet này không có board, xem USER-21)

### USER-20 BOARD: cả 4 board ServerUpload hỏng script; icon Settings bị vẽ thành mặt trời
- Màn / thiết bị: Upload to Server · PH, IP, DI, DC; Collections, Library · IP, DC
- Mức: nên sửa (với canvas)
- Ở đâu: BOARD. `PH_ServerUpload.dc.html` (và IP/DI/DC), dòng `lib = Array.from(…{… accent:t.accent}};});`, thừa `};`, trình chạy báo "Unexpected token ';'". Thêm nữa, trên PH_Collections, IP_Collections, DC_Collections, IP_Library và DC_Share, nút `aria-label="Settings"` được vẽ bằng glyph mặt trời, còn Main và DC_Library vẽ bánh răng.
- Vấn đề: Board Upload hiện token chưa thay giá trị và không có lưới Library phía sau, kể cả ở bản render lại của coordinator. Agent nào dựa vào board này đều đang nhìn một sheet trống. Icon mặt trời làm người xem tưởng đó là nút độ sáng hay Display. Trong code, mọi chỗ đều dùng `gearshape` (`SettingsSheet.swift:11`).
- Đề xuất: Sửa thành `accent:t.accent}});` ở cả 4 board rồi render lại. Thay glyph mặt trời bằng bánh răng giống Main. Chi phí: vài phút.
- Bằng chứng: render/PH_ServerUpload.png (bản render lại vẫn hỏng), DC_Collections, IP_Collections

### USER-21 BOARD: thiếu ba khoảnh khắc người dùng gặp chắc chắn
- Màn / thiết bị: Library (đang index), Import sheet, Viewer (đang tải iCloud) · mọi thiết bị
- Mức: gợi ý
- Ở đâu: BOARD (canvas.json không có board nào cho ba trạng thái này)
- Vấn đề: Với 55.000 ảnh và Optimize Storage, thứ Linh thấy nhiều nhất trong giờ đầu là trạng thái đang index và vòng tải iCloud. Còn với Minh, bước "lấy 20 tấm về" chính là `ServerDownloadSheet`. Không có board thì cũng không có parity check cho những chỗ này.
- Đề xuất: Thêm `PH_LibraryIndexing` (token và thẻ mở rộng, `LibraryScreen.swift:1005-1050`), `IP_ServerImport` (`ServerDownloadSheet` với Existing Album / New Album và Skip Photos Already in Library), `PH_ViewerDownloading` (`PhotoDetailScreen.swift:1107-1127`). Nối vào hàng của từng thiết bị theo quy ước.
- Bằng chứng: canvas.json; các file:line nêu trên

---

## Điều mình sẽ nói với bạn bè về app này

**Linh:** "App này hiện ISO, tiêu cự, khẩu ngay trên từng ô ảnh, và cho biết mình chụp ở 24–35mm tương đương nhiều nhất. Không app ảnh nào khác cho mình cái đó. Có điều nó chưa hiểu 'ảnh đêm', và lúc so 3 tấm để giữ tấm nét nhất thì zoom vào vẫn nhoè như nhau. Collage 4:5 làm nhanh, nhưng phải lưu xong rồi mới share lên Instagram được."

**Minh:** "Nó tự tìm ra con NAS trong studio, đẩy RAW vào thư mục theo ngày, còn nhớ tấm nào đã nằm trên NAS để mình xoá khỏi iPad cho yên tâm. Cái đó mình chưa thấy app nào làm. Dở nhất là phải để iPad đứng yên cho tới khi upload xong, và muốn gửi khách JPEG nhỏ thì phải Resize ra một đống bản copy rồi chọn lại từ đầu. Chỗ Share 'Metadata removed' với 'Without Location' thì đọc ba lần vẫn chưa chắc mình chọn đúng."

**An:** "Trên màn ngoài cái Duo, tab nằm ngay dưới ngón cái, xem máy nào chụp nhiều nhất hay coi lại ảnh ngày này năm trước bằng một tay rất sướng. Chỉ có điều nút gần ngón cái nhất trong viewer lại là thùng rác, còn Settings thì nằm tít góc trên. Mình vẫn sẽ khuyên mấy đứa mê máy ảnh dùng thử."
