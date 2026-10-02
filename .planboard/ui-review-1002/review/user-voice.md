# User voice — người dùng thật nói gì về các app cùng mảng, và ShotDex đứng đâu

Slug `user-voice` · 2026-10-02

**Nguồn và giới hạn.**
- Review App Store (US) tải qua RSS của iTunes, khoảng 3.600 review của 15 app: Lightroom, Darkroom, Photomator,
  Metapho, Exif Metadata, Photo Investigator, EXIF Viewer by Fluntro, PhotoSync, FE File Explorer, Owlfiles,
  Google Photos, Gemini Photos (nay là CleanMy®Phone), Remo Duplicate Photos, Cleanup.
- Thêm Apple Community, Apple Developer Forums, Adobe Community, Kirkville, và báo công nghệ (9to5Mac, BGR,
  TechCrunch, Creative Bloq, MacRumors).
- **Reddit chặn hẳn** cả trình tìm kiếm lẫn fetch, nên không có trích dẫn nào từ r/photography, r/iphone hay
  r/fujifilm. Những gì báo chí kể lại từ Reddit thì tôi chỉ tóm tắt.
- Đợt nghiên cứu 30/9 ([`docs/_intents/2026-09-30-user-wishes-research.md`](/Users/hoangtuan/Project/shotdex-ios/docs/_intents/2026-09-30-user-wishes-research.md))
  đã phủ các mục iCloud, RAW, riêng tư khi share, Insights, sao/cờ, keyword, xuất ra Files và mua đứt. Ở đây tôi
  không nêu lại các mục đó, trừ khi tôi phản biện một quyết định đã chốt (có ghi rõ).
- Board đã xem lại sau lần render lại (bản sáng): `PH_Duplicates`, `PH_Share`, `Main`, `PH_Search`,
  `PH_AdvancedSearch`, `PH_Statistics`, `PH_Collections`, `PH_Viewer`, `PH_ServerUpload`, `PH_UploadedToServer`,
  `PH_Onboarding`, `IP_Library`.

---

## 1. Người dùng nói gì

Cột "mức" là ước lượng của tôi: dựa vào số review/thread gặp được và độ gắt của lời lẽ.

### T1. Photos iOS 18: đập bỏ tab là phản bội thói quen
- **Họ nói gì:** đây là làn sóng phản đối lớn nhất của mảng ảnh mấy năm nay.
  - Bỏ thanh tab, gộp mọi thứ vào một trang cuộn dài.
  - Carousel và bộ sưu tập do máy tự dựng đẩy album của chính họ xuống dưới.
  - Video không còn mở toàn màn hình.
  - Hai tháng sau khi phát hành vẫn có người than mỗi ngày (BGR 20/9/2024, Creative Bloq 11/2024).
  - Apple phải gỡ carousel ngay từ beta. Lên iOS 26 thì đưa tab về, và Federighi thừa nhận người dùng nhớ tab
    (TechCrunch 9/6/2025).
- **Mức:** rất nhiều, rất gắt.
- **Trích:** "iOS 18 is the worst update to the Apple photos app ever." — Apple Developer Forums, 11/2024,
  <https://developer.apple.com/forums/thread/769501>
- **Đối thủ:** Apple Photos.

### T2. Liquid Glass ở iOS 26: thanh tab co lại và Search tách riêng
- **Họ nói gì:**
  - Thanh tab trong suốt và co lại khi cuộn, nên phải chạm thêm mới đổi được màn.
  - Trong Photos, khi vuốt lên thì Select và Search rất khó thấy.
  - Apple được đồn là sẽ gộp Search lại vào thanh tab ở iOS 27 cho nhiều app.
- **Mức:** vừa. Báo chí nhắc nhiều, ít giận dữ hơn T1.
- **Trích:** "combine the search tab with the rest of an app's tabs" — 9to5Mac, 13/5/2026,
  <https://9to5mac.com/?p=1052059>
- **Đối thủ:** Apple (mọi app hệ thống).

### T3. Muốn lọc theo body, lens, tiêu cự mà không có giao diện
- **Họ nói gì:**
  - Photos trên iPhone chỉ cho xem thông tin camera ở bảng Info. Smart album theo lens chỉ có trên Mac và không
    đồng bộ sang iPhone (Six Colors, Kirkville).
  - Lightroom mobile chỉ có lọc theo body. Lọc theo lens phải gõ cú pháp `lens:` mà không có giao diện nào chỉ ra.
  - Bộ lọc camera trên iPad thiếu máy, sai số đếm, và trống trơn trong album. Adobe giải thích là bộ lọc cần
    server phân tích metadata (Adobe Community 21/6/2025).
  - iOS 27 mới thêm "search using additional metadata" cùng sao và keyword (BGR 21/9/2026).
- **Mức:** đòi đều và lâu năm. Thread Adobe từ 2018 vẫn còn người trả lời.
- **Trích:** "Would love to filter by lens type, similar to camera body filter" — Adobe Community, 18/5/2018,
  <https://community.adobe.com/feature-requests-681/p-filter-by-lens-and-file-type-661143>
- **Đối thủ:** Apple Photos, Lightroom mobile.

### T4. Một lens mang hai tên, nên số liệu bị chia đôi
- **Họ nói gì:**
  - Cập nhật firmware, hay chụp từ hai body, làm cùng một lens hiện ra với hai tên khác nhau.
  - Smart album theo lens vì thế sót ảnh.
  - Người dùng phải thêm điều kiện thứ hai bằng tay.
- **Mức:** ít người nói ra, nhưng ai thống kê gear cũng gặp.
- **Trích:** "A lens may appear in the list with two different names." — Kirkville, 27/4/2023,
  <https://kirkville.com/create-smart-albums-for-your-lenses-and-cameras-in-apple-photos/>
- **Đối thủ:** Apple Photos (Mac).

### T5. "Thực ra mình chụp tiêu cự nào?" Người ta phải tự đi tìm số liệu
- **Họ nói gì:**
  - Người ta dùng plugin Lightroom (Data Explorer, Data Plot, Lightroom Analytics xuất CSV) hoặc app Mac
    (PhotoStatistica).
  - Mục đích là trả lời câu "lens tiếp theo nên mua là gì" và "prime hay zoom".
  - FocalViz, một app iPhone/iPad ra 9/4/2026, bán đúng lời hứa này: quy đổi 35mm, mua đứt, chạy trên máy.
- **Mức:** đòi đều. Ngách nhỏ nhưng là người dùng chính của ShotDex.
- **Trích:** FocalViz tự giới thiệu là giúp giảm "kit anxiety with hard data" — mwm.ai, 4/2026,
  <https://mwm.ai/apps/focalviz/6761746933>
- **Đối thủ:** plugin Lightroom Classic, PhotoStatistica, FocalViz.

### T6. Sợ app dọn ảnh trùng xoá nhầm, kể cả bản gốc
- **Họ nói gì:** đây là chủ đề 1★ dày nhất trong ba app dọn ảnh. Họ kể bốn chuyện:
  - "Similar" gom cả những ảnh không giống nhau.
  - App xoá cả bản gốc lẫn bản sao.
  - App xoá mất bản đã chỉnh vì tưởng là bản trùng (iMore nhắc lại).
  - AI coi ảnh kỷ niệm là "clutter".

  Recently Deleted là cái phao duy nhất. Có người không kịp xem hết 30 ngày nên mất thật.
- **Mức:** rất nhiều, rất gắt.
- **Trích:** "it deleted both original and copy" — App Store, Gemini Photos/CleanMy®Phone, 5/5/2025,
  <https://apps.apple.com/us/app/id1277110040>
- **Đối thủ:** Gemini Photos, Cleanup, Remo, và Duplicates của Photos (gom nhầm burst, theo Macworld).

### T7. Duyệt trùng là việc dài, và app không cho biết bản nào đáng giữ
- **Họ nói gì:**
  - Lựa chọn không được lưu. Một người mất 4 giờ đánh dấu thì app tự bỏ chọn hết (Gemini, 20/9/2025).
  - Phải mở từng nhóm mới dám bấm Clean (Gemini, 16/6/2026).
  - Không biết bản nào nằm trong album, nên không dám xoá (Cleanup, 9/8/2024).
- **Mức:** nhiều.
- **Trích:** "No way to tell if a duplicate photo is in an album" — App Store, Cleanup, 9/8/2024,
  <https://apps.apple.com/us/app/id1510944943>
- **Đối thủ:** Gemini, Cleanup, Remo.

### T8. Thu app xuống là việc dài dừng luôn
- **Họ nói gì:**
  - Remo hứa vẫn quét được khi thu nhỏ app, nhưng thực tế dừng.
  - Thư viện 25k–45k ảnh phải để màn hình mở hàng giờ, đôi khi treo ở tấm cuối.
  - Gemini phải mở app cả buổi mới quét xong (9/2025).
  - PhotoSync bán việc tự chuyển ảnh chạy nền thành gói riêng ($0.99/tháng hoặc $25), và người ta vẫn trả.
- **Mức:** nhiều. Người dùng thư viện lớn gặp gần như chắc chắn.
- **Trích:** "when you do it pauses the scanning" — App Store, Remo Duplicate Photos, 4/3/2021,
  <https://apps.apple.com/us/app/id1066797785>
- **Đối thủ:** Remo, Gemini, PhotoSync.

### T9. Làm việc với NAS: tên file trùng, SMB hỏng sau bản iOS mới, lỡ tay xoá
- **Họ nói gì:**
  - PhotoSync không xử lý được nhiều ảnh trùng tên `IMG_xxxx` trong một lô.
  - Nhiều đích thì chỉ theo dõi được "đã gửi" chung cho tất cả, không theo từng đích.
  - Sau mỗi bản iOS lớn lại có "No Route to Host" hoặc SMB hỏng.
  - Owlfiles: vuốt trái để mở menu mà nhiều người lỡ xoá file trên NAS.
  - FE File Explorer: không xem được EXIF của ảnh trên server.
- **Mức:** vừa, nhưng đều đặn qua từng bản iOS.
- **Trích:** "it does not handle files with identical names" — App Store, PhotoSync, 31/3/2024,
  <https://apps.apple.com/us/app/id415850124>
- **Đối thủ:** PhotoSync, Owlfiles, FE File Explorer.

### T10. Bỏ vị trí khi chia sẻ: phải nhớ tắt mỗi lần, và video vẫn lộ
- **Họ nói gì:**
  - Photos có Options › Location, nhưng không có mặc định. Thread hỏi việc này có 27 người bấm "Me too".
  - EXIF Viewer by Fluntro bị chê vì MOV slow-motion vẫn còn toạ độ (25/9/2026), và vì không lưu được video đã
    gỡ EXIF (22/2/2026).
  - Metapho thì có người báo app nói đã gỡ vị trí mà app khác vẫn đọc ra.
- **Mức:** vừa, nhưng người dùng rất cẩn thận với chuyện này.
- **Trích:** "manually go to Options and turn off Location for each photo set" — Apple Community, 4/7/2025,
  <https://discussions.apple.com/thread/256092610>
- **Đối thủ:** Apple Photos, Metapho, Fluntro.

### T11. Mệt subscription, sợ bẫy dùng thử, bị "lifetime" bỏ rơi
- **Họ nói gì:** chủ đề 1★ dày nhất trong các app chỉnh và dọn ảnh.
  - **Bẫy dùng thử.** Trừ tiền ngay sau khi hết hạn. Không thấy giá trước khi tải.
  - **Mua đứt bị đổi luật về sau.**
    - Darkroom ra gói Darkroom+ rồi nhắc mua liên tục, cả với người đã mua lifetime.
    - Photomator bị Apple mua, người mua lifetime 11/2024 không còn được cập nhật.
    - Gemini đổi tên, người mua lifetime mất quyền.
  - **Giá tăng.** Adobe tăng gói tháng từ $9.99 lên $14.99 (1/2025).
  - **Phải trả để xoá ảnh của chính mình.** Cleanup bắt xem quảng cáo hoặc trả tiền mới được xoá.
- **Mức:** rất nhiều, rất gắt.
- **Trích:** "I’d happily pay 5-10 bucks for this once." — App Store, Photomator, 4/12/2023,
  <https://apps.apple.com/us/app/id1444636541>
- **Đối thủ:** Darkroom, Photomator, Lightroom, Gemini, Cleanup.

### T12. Tiện ích EXIF: quảng cáo, chức năng bị khoá, thu thập dữ liệu
- **Họ nói gì:**
  - Exif Metadata và Photo Investigator bị 1★ vì quảng cáo đầy màn và vì chức năng "free" phải trả mới dùng.
  - Bảng thông tin quyền riêng tư của app ghi chép dữ liệu nhiều, nên app ảnh đáng ra phải riêng tư lại không
    được tin.
  - Lightroom cũng bị một review 1★ tên "No Privacy" (29/4/2026).
- **Mức:** nhiều với nhóm tiện ích nhỏ.
- **Trích:** "It even collects a ton of data on you" — App Store, Exif Metadata, 31/8/2026,
  <https://apps.apple.com/us/app/id1455197364>
- **Đối thủ:** Exif Metadata, Photo Investigator, Lightroom.

### T13. Optimize Storage: bản mờ và chờ tải trong app bên thứ ba
- **Họ nói gì:**
  - Darkroom phải phóng to rồi đổi ảnh thì ảnh mới hết mờ. Lỗi "không tải bản full" kéo dài cả năm.
  - Lightroom mobile chậm khi ảnh nằm trên cloud.
  - MacRumors và Six Colors giải thích: khi Optimize Storage bật, ảnh gốc chỉ được tải về lúc mở ra.
- **Mức:** vừa. Ai bật Optimize Storage cũng gặp.
- **Trích:** "old bug where photos don’t load in full resolution" — App Store, Darkroom, 25/5/2025,
  <https://apps.apple.com/us/app/id953286746>
- **Đối thủ:** Darkroom, Lightroom.

### T14. Thư viện lớn thì cái gì cũng chậm
- **Họ nói gì:**
  - Google Photos tìm kiếm chậm với thư viện lớn.
  - Lightroom bị chê "S.L.O.W." (8/2026) và "laggy".
  - EXIF Viewer mất "an eternity" mới hiện lưới ảnh.
  - Một người có 78k ảnh không lọc được những ảnh thiếu ngày.
  - Lightroom còn bị chê vì nhồi AI mà bỏ quên hiệu năng (1/2026).
- **Mức:** nhiều.
- **Trích:** "It takes far too long to execute" — App Store, Google Photos, 6/10/2025,
  <https://apps.apple.com/us/app/id962194608>
- **Đối thủ:** Google Photos, Lightroom, Fluntro.

### T15. Không muốn thêm một thư viện riêng
- **Họ nói gì:**
  - **Phe đông:** khen Darkroom vì sửa thẳng trên iCloud Photos, ghét Lightroom vì bắt import vào thư viện riêng
    và lưu thêm bản JPG trùng.
  - **Phe ít hơn nhưng có thật:** muốn sửa thẳng trên SSD ngoài hoặc ngoài Photos.
    - Photomator bị 1★ vì "chỉ làm với thư viện Photos".
    - Darkroom bị đòi cho sửa từ ổ ngoài (7/2025).
- **Mức:** nhiều.
- **Trích:** "I don’t want a separate library." — App Store, Lightroom, 29/7/2026,
  <https://apps.apple.com/us/app/id878783582>
- **Đối thủ:** Lightroom, Photomator, Darkroom.

### T16. Lọc ảnh nhanh sau buổi chụp, và lời cảnh báo khi đổi chỗ chức năng quen
- **Họ nói gì:**
  - Lightroom mobile giấu Rate/Flag sau một bản cập nhật, vuốt để gắn cờ không ăn (10/2023, 3/2026).
  - Bản 11.5 (8/2026) gỡ danh mục preset, bị 1★ dồn dập.
  - Google Photos bỏ cụm theo ngày (2/2026, 9/2026), cũng bị 1★.
  - iOS 27 Photos thêm chấm sao 1–5 và keyword. Chấm sao thôi không còn là thứ riêng của app chuyên.
- **Mức:** nhiều mỗi khi có bản cập nhật đổi bố cục.
- **Trích:** "Now you can mark pictures and videos with a star rating" — BGR, 21/9/2026,
  <https://www.bgr.com/2263939/ios-27-photos-app-new-features/>
- **Đối thủ:** Lightroom, Google Photos, Apple Photos (iOS 27).

---

## 2. Áp vào ShotDex

### Những gì ShotDex đã trả lời được

Mỗi dòng có chỗ để kiểm. Không cần làm gì thêm, chỉ cần giữ đúng như vậy.

| Chủ đề | ShotDex làm gì | Ở đâu |
|---|---|---|
| T1 tab | Có ba tab Library / Collections / Statistics và nút Search kiểu iOS 26. Không có màn cuộn gộp kiểu iOS 18. | `Main`, `IP_Library` · `App/RootTabView.swift` |
| T2 thanh tab co lại | `tabBarMinimizeBehavior(.never)`: thanh tab không bao giờ co, tránh đúng lời than về iOS 26. | `App/RootTabView.swift:216` |
| T3 lọc theo gear | Gõ "Sony 85mm" là có capsule diễn giải "brand Sony · focal 85mm". Advanced Search có điều kiện và đếm khớp tại chỗ ("Matches 1284 photos"), lưu được thành smart album. Lightroom bị chê đúng vì thiếu cái capsule này. | `PH_Search`, `PH_AdvancedSearch` |
| T3 EXIF dễ thấy | Lưới ghi ISO · mm · f dưới mỗi ô. Viewer có dải EXIF ngay đầu màn, không phải vuốt lên mới thấy. | `Main`, `PH_Viewer` |
| T4 lens hai tên | `LensNormalizer` gộp các cách viết khác nhau của cùng một lens (tiền tố hãng, khoảng trắng trước mã ngàm). | `Domain/Normalize/LensNormalizer.swift:1-30` |
| T5 thống kê | Có Insights, quy đổi 35mm, Top Camera, và dòng "214 photos… unknown sensor size" dẫn vào Unknown Cameras. | `PH_Statistics` · FS-07 |
| T6 không tự chọn hộ | Không ảnh nào bị đánh dấu sẵn. Ảnh xoá đi vào Recently Deleted, có ghi ngay dưới nút đỏ. Compare là đường chính. | `PH_Duplicates` · FS-06.06 §1, §7 |
| T9 NAS | Trùng tên thì hỏi Replace / Keep Both / Skip. "Uploaded to Server" theo dõi riêng từng kết nối và thư mục, đúng cái PhotoSync thiếu. Xoá trên server luôn hỏi lại và nói rõ "can't be undone". Thiếu quyền Local Network thì có câu giải thích riêng. | `Domain/ServerUpload/ServerUploadSession.swift:16-28` · `PH_UploadedToServer` · `ServerImport/ServerBrowserScreen.swift:107-113` · `ServerUpload/FileServerFormScreen.swift:339` |
| T10 mặc định riêng tư | Có ba mức share và một mặc định trong Settings, đúng cái thread Apple Community xin. | `PH_Share` · FS-08.06 |
| T12 riêng tư | Onboarding hứa "Your photos stay on your device". Không quảng cáo, không tài khoản. | `PH_Onboarding` · NF-03 |
| T13 iCloud | Đang làm ở FS-02.06 (đợt 1 của intent 30/9). | — |
| T15 thư viện riêng | Sửa thẳng trên thư viện Photos bằng adjustment data, không tạo bản trùng. SSD ngoài và folder mạng đã có intent. | intent 30/9 · network-folder-edit |
| T16 sao/cờ | FS-01.12 và 12b đã spec, dùng `PHAsset.rating` trên iOS 27. | intent 30/9 mục 9, 14 |

### Những gì còn thiếu hoặc có nguy cơ lặp lỗi của đối thủ

Xếp theo mức quan trọng.

### VOICE-01 Merge All Groups ghi vào thư viện trước khi người dùng xác nhận, và chạy được cả ở Series
- **Màn / thiết bị:** Duplicates · mọi thiết bị
- **Mức:** nên sửa (cao nhất trong danh sách)
- **Ở đâu:** APP. `Features/Duplicates/DuplicatesScreen.swift:99-103` (menu ⋯, chỉ bị tắt khi `groups.isEmpty`) ·
  `DuplicatesModel.swift:299-311` (`mergeAll`) · `DuplicatesModel.swift:314-330` (`adoptMetadata`, gọi thẳng
  `performChanges`)
- **Vấn đề:** nỗi sợ số 1 của người dùng app dọn ảnh là app quyết định thay họ (T6). Merge All Groups làm ba
  việc trái với chính luật "Không tự chọn hộ" của FS-06.06 §1:
  1. **Chạy ở cả ba mức, kể cả Series.** FS-06.06 §6 tự nói ở một loạt tư thế "câu trả lời thường là giữ vài
     tấm", vậy mà một chạm đánh dấu xoá mọi khung trừ file lớn nhất của **mọi** loạt. Ở Similar cũng vậy: hai
     tấm chụp cách nhau một giây (khác biểu cảm) bị coi như bản sao.
  2. **Ghi metadata ngay lập tức, không hỏi.**
     - Bản được giữ nhận ngày chụp sớm nhất, toạ độ và cờ favorite của các bản kia.
     - Việc ghi xảy ra trước khi người dùng thấy hộp xác nhận xoá của hệ thống.
     - Huỷ xoá thì những thay đổi này vẫn ở lại. Ở Similar, ngày chụp của tấm giữ bị dời sang khoảnh khắc của
       một tấm **khác**.
  3. **Không báo trước sẽ đánh dấu bao nhiêu ảnh.** Nút không có số, không có hộp hỏi. Người dùng chỉ thấy
     nút đỏ "Delete 31 Photos" hiện ra.
- **Đề xuất:**
  - Chỉ cho Merge ở **Exact**. Ở Similar và Series thì ẩn hẳn khỏi menu.
  - Đổi nhãn thành "Merge N Groups…" và mở `confirmationDialog`: *"Keeps the largest copy in each of 12 groups
    and marks 19 photos for deletion. The kept copy takes the favourite, location and earliest date of its
    copies."*
  - Chuyển `adoptMetadata` ra **sau** khi `deleteAssets` thành công, chạy theo từng nhóm. Nếu sợ xoá rồi mới chép
    hỏng thì chép trong cùng một `performChanges` với lệnh xoá, vì PhotoKit cho gộp hai việc trong một lần
    thay đổi.
  - Chi phí: khoảng 30 dòng và một dialog. Giữ được tinh thần FS-06.06 §8 ("chép trước, xoá sau" chỉ còn đúng
    trong một giao dịch).
- **Bằng chứng:**
  - Board `PH_Duplicates` (menu ⋯ không vẽ, xem code).
  - Gemini, 5/5/2025: "it deleted both original and copy".
  - Gemini, 7/4/2025: chê bản mới chỉ còn tìm được ảnh y hệt.
  - Macworld: Duplicates của Photos gom nhầm burst RAW.

### VOICE-02 Ô ảnh trùng không cho thấy bản nào đáng giữ, và xoá đi thì mất luôn chỗ trong album
- **Màn / thiết bị:** Duplicates, Compare · mọi thiết bị
- **Mức:** nên sửa
- **Ở đâu:** cả hai.
  - `DuplicatesScreen.swift:419-452`: chú thích chỉ có kích thước, dung lượng và ngày.
  - `Domain/Duplicates/DuplicateGrouper.swift:5-12`: `HashedPhoto` có `isFavorite` nhưng không hiện ra.
  - `DuplicateGrouper.swift:278-286` và `DuplicatesModel.keeper`: chọn bản giữ chỉ theo pixel và dung lượng.
  - FS-06.06 §8 dòng cuối: "Không có bước hợp nhất album".
- **Vấn đề:**
  - Trên `PH_Duplicates`, ô 100pt bị cắt chữ: "6000 × 4000 · La…", "Sep 14, 2…". Ngày, là thứ duy nhất phân biệt
    hai bản, lại bị cụt.
  - Không có dấu nào cho biết bản nào đã **chỉnh**, bản nào **favorite**, bản nào **nằm trong album**, bản nào
    là RAW hay Live. Người dùng Cleanup và Gemini đã nói đúng chỗ này (T7). Bài học "xoá mất bản đã chỉnh" của
    iMore cũng đúng chỗ này.
  - Xoá bản đang nằm trong album "Iceland 2026" thì ảnh biến khỏi album, và bản được giữ không được thêm vào
    album thay thế.
  - Bản chọn giữ là "file lớn nhất", nên một bản gốc chưa chỉnh to hơn sẽ thắng bản đã chỉnh.
- **Đề xuất:**
  - Thêm một hàng huy hiệu dưới ảnh, glyph 12pt, kiểu chữ caption2: `heart.fill` · `slider.horizontal.3` (đã
    chỉnh) · `rectangle.stack` + số album · `RAW` · `LIVE`.
  - Bỏ chữ "Largest" khỏi dòng kích thước, thay bằng một nhãn trên góc ảnh.
  - Hàm `keepFirst` ưu tiên: đã chỉnh > trong album > favorite > pixel > dung lượng.
  - Lúc Merge, thêm bản được giữ vào mọi album của các bản sắp xoá (`PHAssetCollectionChangeRequest.addAssets`,
    cùng giao dịch với VOICE-01).
  - Cái giá:
    - đảo dòng "không hợp nhất album" của FS-06.06 §8;
    - một lần fetch `PHAssetCollection.fetchAssetCollectionsContaining` cho mỗi ảnh **đang hiện**, không phải cả
      thư viện ([NF-01](/Users/hoangtuan/Project/shotdex-ios/docs/04-non-functional-design/NF-01-performance.md) luật 1).
- **Bằng chứng:**
  - Board `PH_Duplicates` (chữ bị cắt).
  - Cleanup, 9/8/2024: "No way to tell if a duplicate photo is in an album".
  - Cleanup, 29/6/2024: các bản trùng "mostly pics I had edited".

### VOICE-03 Đánh dấu xoá chỉ sống trong màn hình: bấm Back là mất hết
- **Màn / thiết bị:** Duplicates · mọi thiết bị
- **Mức:** nên sửa
- **Ở đâu:** APP. `DuplicatesScreen.swift:16,30` (`@State private var model`, tạo mỗi lần vào màn) ·
  `DuplicatesModel.swift:39-40` (`markedForDeletion` chỉ nằm trong RAM)
- **Vấn đề:**
  - Với 12 nhóm thì không sao. Với thư viện 55k sau lần quét đầu thì có thể là vài trăm nhóm.
  - Người dùng đánh dấu được nửa chừng, rồi chạm Back, đổi tab Collections, hoặc iOS đóng app nền. Lúc đó
    mọi dấu mất mà không có cảnh báo.
  - Đây đúng là review "4 hours of work gone" của Gemini.
  - Câu "dấu sống qua các lần nạp lại" trong FS-06.06 §7 chỉ đúng khi vẫn ở trong màn.
- **Đề xuất:**
  - Lưu `markedForDeletion` theo asset id, và theo mức đang dùng, vào `UserDefaults` hoặc một bảng nhỏ. Lúc nạp
    lại vẫn lọc theo `liveIds` như dòng 162 đang làm.
  - Dòng trạng thái đầu màn ghi thêm "19 marked · Review".
  - Chi phí nhỏ. Nếu thích bảng hơn thì dấu là dữ liệu người dùng nhập, nên không nằm trong `photo_metadata`
    (BD-02 §4).
- **Bằng chứng:** Gemini, 20/9/2025 ("4 hours of work gone"). Gemini, 16/6/2026: "doesn't save".

### VOICE-04 Upload dừng khi app ra nền, trong khi iOS 26 đã có API cho đúng việc này (phản biện quyết định 24/9)
- **Màn / thiết bị:** Upload to Server, và cả Resize hàng loạt, Rescan Duplicates, tải từ server · iOS 26+
- **Mức:** nên sửa
- **Ở đâu:**
  - APP: `Features/ServerUpload/ServerUploadSheet.swift:48-52` (ra nền là huỷ) và `:170` ("Keep ShotDex open…").
  - Quyết định: `docs/_intents/2026-09-24-local-network-upload.md:125` ("Chạy nền: không") và FS-15 README:41.
- **Vấn đề:**
  - Quyết định cũ dựa trên "hệ thống chỉ cho vài chục giây". Điều đó đúng với `beginBackgroundTask`.
  - Nhưng iOS 26 có `BGContinuedProcessingTask` (WWDC25 phiên 227). Đây là việc do người dùng bấm, được chạy
    tiếp sau khi app ra nền, có tiến độ hiện trong UI hệ thống, và người dùng tự huỷ được. Apple nêu đích danh
    "photo/video export" và "publishing content".
  - Hôm nay một lô 486 MB (board `PH_ServerUpload`) buộc người dùng giữ máy sáng, không được mở app khác. Chỉ
    cần trả lời một tin nhắn là lô bị huỷ.
  - Người dùng đã nói rõ họ ghét đúng điều này (T8). Họ trả tiền cho PhotoSync chính vì nó chạy nền.
- **Đề xuất:**
  - Trên iOS 26+, lúc bấm Upload thì gửi `BGContinuedProcessingTaskRequest` (tiêu đề "Uploading 12 photos to
    Studio NAS"), báo `progress` theo từng file, và đặt `expirationHandler`.
  - Khi hết hạn thì dọn file `.shotdex-part` như lối huỷ đang làm (`ServerUploadPath.swift:6-8`).
  - Dưới 26 giữ nguyên cách hiện nay.
  - Câu ở `:170` đổi theo `#available`: *"You can leave ShotDex — progress shows on the Lock Screen."*
  - Cùng khung này dùng được cho Resize hàng loạt và Rescan.
  - Cái giá:
    - Info.plist cần `BGTaskSchedulerPermittedIdentifiers` có wildcard;
    - đổi AC-15 của FS-15;
    - phải thử trên máy thật vì hệ thống có thể cắt task chậm tiến độ trước.
- **Bằng chứng:**
  - <https://developer.apple.com/videos/play/wwdc2025/227/>
  - Remo, 4/3/2021: "when you do it pauses the scanning".
  - PhotoSync, 30/7/2025: chuyển tự động bị khoá sau gói trả tiền riêng.

### VOICE-05 Đợt 3 "mua đứt": đưa các lời than vào AC ngay từ bây giờ
- **Màn / thiết bị:** màn mua, mọi cổng khoá · mọi thiết bị
- **Mức:** nên sửa (là đầu vào cho `/spec`, chưa có code)
- **Ở đâu:** intent 30/9 mục 13 và câu hỏi đã chốt số 3 ("Editor, xuất và Video Studio cần mua").
- **Vấn đề:**
  - Quyết định mua đứt khớp với người dùng (T11).
  - Nhưng chữ "xuất" để mở. Nếu Share, Upload lên NAS, Resize, hay **Delete trong Duplicates** bị tính là xuất
    và bị khoá, ShotDex lặp đúng lỗi bị chửi nhiều nhất: trả tiền mới được xoá hay lấy ảnh của chính mình ra
    (Cleanup, 19/6/2025).
  - Các lời than khác cũng cần thành luật:
    - Darkroom nhắc mua sau khi người dùng đã mua.
    - Darkroom xin đánh giá liên tục.
    - Không thấy giá trước khi dùng thử (Photomator, 1/11/2023; Darkroom, 19/4/2025).
    - "Lifetime" bị đổi luật về sau (Darkroom+, Photomator, Gemini).
- **Đề xuất:** ghi thành AC trong spec mua đứt.
  1. Delete, Duplicates, Share, Upload và tải ảnh gốc từ server **không bao giờ** bị khoá.
  2. Giá hiện ở Onboarding và trên mọi cổng khoá **trước** khi người dùng chạm.
  3. Dùng thử không tự trừ tiền. Gói không tự gia hạn vốn đã không trừ được, nên chỉ cần ghi rõ thành chữ.
  4. Sau khi mua thì không còn màn bán hàng nào, và `requestReview` tối đa 1 lần mỗi phiên bản.
  5. Bản mua phủ mọi tính năng ra sau này. Không có gói "Plus".
- **Bằng chứng:**
  - Photomator, 4/12/2023: "I’d happily pay 5-10 bucks for this once."
  - Darkroom: 3 review 1–3★ về nhắc mua (8/2025).
  - Cleanup: 3 review về khoá việc xoá.

### VOICE-06 Video vẫn mang toạ độ khi chia sẻ (phản biện NF-03 §3)
- **Màn / thiết bị:** Share sheet, Save to Files · mọi thiết bị
- **Mức:** nên sửa
- **Ở đâu:** quyết định ở `docs/04-non-functional-design/NF-03-privacy-and-security.md:73-74` và FS-08.06 §2
  ("Video share nguyên bản"). APP: `Features/Shared/PhotoShareSheet.swift`.
- **Vấn đề:**
  - Lý do của quyết định là gỡ vị trí thì phải chép cả clip ra đĩa. Nhưng chép kiểu **passthrough** (không mã
    hoá lại) với bộ lọc metadata chỉ là chép byte. Một clip 4K một phút, khoảng 400 MB, mất vài giây trên NVMe.
    Đó không phải lần mã hoá lại mà quyết định cũ đã hình dung.
  - Người đăng video quay ở nhà, đúng nhóm FS-08.06 §1 nói tới, vẫn lộ địa chỉ dù đã chọn "No Location".
  - Câu "Videos keep their metadata" là trung thực, nhưng chuyển hết gánh nặng sang người dùng. Review của
    Fluntro cho thấy người ta dùng app EXIF chính là để gỡ vị trí khỏi video.
- **Đề xuất:**
  - Ở mức No Location / No Metadata, chép video bằng `AVAssetExportSession` preset Passthrough. Đặt
    `metadataItemFilter = AVMetadataItemFilter.forSharing()` (bộ lọc của Apple bỏ vị trí và thông tin nhận
    dạng người dùng), hoặc gán `metadata` đã lọc.
  - Trước khi spec cần spike đo hai việc: passthrough có tôn trọng bộ lọc với HEVC/ProRes không, và tốc độ
    trên máy thật.
  - Nếu đo ra quá nặng thì giữ quyết định cũ, nhưng thêm một nút "Remove Location from Videos" thay cho một
    câu thông báo.
  - Cái giá: đĩa tạm bằng cỡ clip, cần hiện tiến độ, và một lần đổi NF-03.
- **Bằng chứng:**
  - Fluntro, 25/9/2026: MOV slow-motion "still have EXIF datas (e.g., locations)".
  - Fluntro, 22/2/2026: "Downloaded to remove EXIF from video".
  - Apple Community, 4/7/2025: 27 "Me too".

### VOICE-07 Không lọc được ảnh **thiếu** dữ liệu (không vị trí, không lens, không ngày)
- **Màn / thiết bị:** Advanced Search, Smart Album Editor · mọi thiết bị
- **Mức:** nên sửa
- **Ở đâu:** APP. `Core/Models/SmartAlbumQuery.swift:131-147`: `RuleOperator` không có toán tử "is missing".
  `SmartAlbumQuery.swift:31-47`: không có trường Location (có/không).
- **Vấn đề:**
  - ShotDex đã có công cụ **sửa**: `Shared/AdjustDateTimeSheet.swift`, `Shared/AdjustLocationSheet.swift`.
  - Nhưng không có cách **tìm** ảnh cần sửa:
    - ảnh scan không có ngày;
    - ảnh từ body không GPS cần gắn vị trí cả buổi;
    - ảnh lens cơ không có tên lens.
  - Người dùng EXIF Viewer có 78k ảnh đã bỏ app vì đúng chỗ này. Trong FS-07, Statistics đã gom cả nhóm
    "Unknown" mà không có đường từ nhóm đó dẫn ra lưới ảnh.
- **Đề xuất:**
  - Thêm toán tử `isMissing` cho mọi trường text, number và date (SQL `IS NULL OR = ''`). Thêm trường
    `Location` dạng choice: Has Location / No Location.
  - Thanh Bar "Unknown" trong chart chạm vào thì mở lưới với điều kiện đó.
  - Sửa xong theo lô thì smart album "No Location" tự rỗng dần. Đó là vòng lặp người dùng cần.
  - Chi phí:
    - một case enum;
    - một nhánh SQL;
    - nhãn trong `RuleBuilderSections`;
    - test trong `SmartAlbumQuery` tests.
- **Bằng chứng:** Fluntro, 10/1/2021: "no way to filter the ones without dates". Board `PH_AdvancedSearch`.

### VOICE-08 Lens cơ hoặc lens qua adapter rơi vào "Unknown" mà không gán lại được
- **Màn / thiết bị:** Library (chế độ chọn), Statistics, Camera Database · mọi thiết bị
- **Mức:** nên sửa
- **Ở đâu:**
  - APP: không có. Tìm `lensOverride`, `manualLens`, `Assign Lens`, `Set Lens` không ra gì.
  - `Data/Database/StatisticsQueries.swift:39-46`: ảnh không có lens đi vào bucket "Unknown".
- **Vấn đề:**
  - Người chụp Fuji và Sony với lens cổ hay lens qua adapter đúng là nhóm quan tâm "mình dùng lens nào bao nhiêu".
  - Ảnh của họ không có `LensModel`, có khi không có cả tiêu cự.
  - Lightroom có plugin LensTagger chỉ để làm việc này. Fuji-X Forum có thread riêng.
  - Một review Fluntro (4/2025) xin "lens template" để gán hàng loạt.
  - ShotDex hôm nay sẽ đếm mọi tấm chụp bằng Helios 44 là "Unknown". Insights cũng loại những tấm đó khỏi mẫu
    số, nên câu "41% ở 20–34mm" bỏ sót đúng lens họ thích nhất.
- **Đề xuất:**
  - Thêm lệnh "Set Lens…" trong menu ⋯ của chế độ chọn. Sheet có: tên lens (gợi ý từ danh sách lens đã gặp và
    lens người dùng tạo), tiêu cự, khẩu tối đa.
  - Lưu ở **bảng riêng** `lens_assignment` (asset id → lens). Không nằm trong `photo_metadata`, vì indexer ghi
    đè cả hàng (BD-02 §4, luật data-migration).
  - Statistics, bộ lọc và Info đọc `COALESCE(assignment, exif)`, và Info có nhãn "Set by you".
  - Camera Database thêm mục "Lenses" để gộp hai tên của cùng một lens (T4), cho những ca `LensNormalizer` không
    đoán được.
  - Chi phí: một migration, một sheet, và chỉnh các query thống kê.
- **Bằng chứng:**
  - Fluntro, 11/4/2025: "Need way to create templates for lenses".
  - <https://www.fuji-x-forum.com/topic/2187-adding-adapted-lens-information-to-picture-metadata>
  - Kirkville, 27/4/2023 (T4).

### VOICE-09 Collections chỉ có hàng ngang, không có "See All"
- **Màn / thiết bị:** Collections · PH, DC (iPad và Duo inner rộng hơn nên đỡ hơn)
- **Mức:** nên sửa
- **Ở đâu:** APP. `Features/Albums/AlbumsScreen.swift:473-517`: tiêu đề mục chỉ là `Text(title)`, theo sau là
  `ScrollView(.horizontal)`. Tìm `See All` / `Show All` trong `Features/Albums/` không ra gì.
- **Vấn đề:**
  - Trên `PH_Collections`, Smart Albums và My Albums là hai hàng ngang 132pt bị cắt ở mép phải. Muốn tới album
    thứ 30 thì phải vuốt ngang mãi.
  - Lời than về iOS 18 chính là carousel và cuộn vô tận che mất album của người dùng (T1).
  - Collections của iOS 26 sửa bằng tiêu đề mục chạm được, có chevron, mở ra lưới dọc.
  - ShotDex đã học được một nửa bài: có Customize để ẩn và xếp lại mục (`CustomizeCollectionsSheet.swift`). Nửa
    còn lại thì chưa.
- **Đề xuất:**
  - Tiêu đề mục thành nút "My Albums ›" (cùng `.title2.bold()`, chevron `.footnote.weight(.semibold)` màu
    secondary). Chạm vào thì push lưới dọc 2 cột (iPhone) hoặc adaptive 180pt (iPad), có sort theo tên/ngày.
  - Hàng ngang giữ nguyên làm phần xem nhanh.
  - Chi phí: một màn danh sách dùng lại `AlbumToken`. Không thêm token mới.
- **Bằng chứng:** board `PH_Collections`. Creative Bloq 11/2024. AppleInsider 12/6/2025 (iOS 26 đưa tab và mục rõ
  ràng trở lại).

### VOICE-10 Không có phạm vi "ảnh do mình chụp" (iOS 27 vừa thêm Captured by Me)
- **Màn / thiết bị:** Library filter, Statistics · mọi thiết bị
- **Mức:** gợi ý
- **Ở đâu:**
  - APP. `Core/Models/FilterCriteria.swift:138`: kiểu chụp chỉ cộng thêm vào kết quả, không loại ra được.
  - `StatisticsQueries.swift:30-35`: `totalPhotos` đếm mọi dòng trong phạm vi.
- **Vấn đề:**
  - Thư viện thật đầy ảnh chụp màn hình, ảnh lưu từ Messages, WhatsApp. Chúng làm loãng lưới khi duyệt theo gear.
  - Chúng cũng làm loãng phần trăm của Top Camera, ví dụ "Sony α7 IV 42%" tính trên cả screenshot.
  - Insights đã cẩn thận đổi mẫu số sang "photos with a known camera". Chart thì chưa.
  - Apple thêm "Captured by Me" vào iOS 27 vì người dùng đã đòi một camera roll thật từ lâu (9to5Mac 22/9/2026).
- **Đề xuất:**
  - Thêm công tắc "Only Photos Shot with a Camera" (có camera make) vào menu lọc của Library.
  - Statistics có mặc định cùng tên trong Chart Editor (Media Type đã có chỗ).
  - Trên iOS 27 có thể nối thêm smart album hệ thống tương ứng, nếu PhotoKit mở ra. Cần kiểm SDK.
  - Chi phí: một điều kiện SQL và một hàng trong menu.
- **Bằng chứng:** 9to5Mac 22/9/2026. Board `PH_Statistics` (cột %).

### VOICE-11 Lời hứa riêng tư ở Onboarding chưa nhắc ngoại lệ Support, và chưa có câu "không thu thập gì"
- **Màn / thiết bị:** Onboarding, Support · mọi thiết bị
- **Mức:** gợi ý
- **Ở đâu:**
  - cả hai: `PH_Onboarding` (câu 4).
  - `docs/02-functional-spec/FS-13-support.md` §1: Support là "ngoại lệ duy nhất", có công tắc gửi kèm log.
- **Vấn đề:**
  - Người dùng tiện ích EXIF đọc bảng quyền riêng tư và bỏ app vì "collects a ton of data" (T12). Lời hứa của
    ShotDex là lợi thế cạnh tranh thật.
  - Nhưng câu 4 nói ảnh chỉ rời máy khi "upload them to a server you set up". Câu đó bỏ sót Share (hiển nhiên),
    và quan trọng hơn là log của Support gửi về `api.shotdex.app`.
  - Một người dùng khó tính bật log, thấy request ra ngoài, là mất niềm tin.
- **Đề xuất:**
  - Câu 4 thành: *"No account, no ads, no tracking. Your photos and their details stay on this device unless you
    share or upload them."*
  - Trong sheet Report a Bug, dưới công tắc log ghi: *"The log lists app events, never photos, names or
    places."* Câu này phải đúng với code, cần kiểm `SupportModel` khi `/spec`.
  - Nhãn App Store giữ ở mức "Data Not Collected", trừ phần Support khai là "Diagnostics, not linked".
- **Bằng chứng:** Exif Metadata, 31/8/2026. Lightroom "No Privacy", 29/4/2026. FS-13 §1.

### VOICE-12 iOS 27 gộp Search vào thanh tab ở nhiều app: kiểm lại trên Duo 27, chưa cần đổi
- **Màn / thiết bị:** Root tab bar · Duo (iOS 27), và mọi máy khi lên 27
- **Mức:** gợi ý
- **Ở đâu:** APP. `App/RootTabView.swift` (`Tab(role: .search)`). Memory "iOS 26 search-tab sheet" ghi là giữ
  search tab theo HIG.
- **Vấn đề:**
  - Apple đổi hành vi thanh tab của chính họ ở iOS 27 vì bị chê (T2).
  - ShotDex dùng `TabView` hệ thống nên có thể được đổi theo tự động. Như vậy cách đi tới Search, và các sheet
    phải đi vòng qua tab Library, có thể khác trên 27.
  - Board `DC_*`/`DI_*` vẽ theo nhánh iOS 26.
- **Đề xuất:**
  - Chạy `ios26-parity` / `device-layout` trên Duo iOS 27, cho Library và Search, trước khi đóng đợt review này.
  - Không đổi quyết định "search tab stays".
  - Chi phí: một lượt chụp màn.
- **Bằng chứng:** 9to5Mac 13/5/2026. Board `DI_Library`, `DC_Search`.

### VOICE-13 Khi đã ship: đừng gỡ thứ người dùng đã quen mà không có đường lui
- **Màn / thiết bị:** mọi màn · mọi thiết bị
- **Mức:** gợi ý (luật quy trình, không phải lỗi hôm nay)
- **Ở đâu:** `docs/PROCESS.md` (giai đoạn Maintain). Lịch sử dự án: editor dựng lại nhiều lượt, sao/cờ gỡ ở v16
  rồi đưa lại.
- **Vấn đề:**
  - Ba bản cập nhật bị 1★ dồn dập năm nay đều là **gỡ** thứ người dùng quen:
    - Lightroom 11.5 gỡ danh mục preset;
    - Google Photos bỏ cụm theo ngày;
    - Lightroom giấu Rate/Flag.
  - Lúc chưa release thì đổi gì cũng được. Từ ngày ship, cùng kiểu đổi đó sẽ thành review 1★.
- **Đề xuất:** thêm một dòng vào checklist `/release-check` và REVIEW.md, áp từ ngày ship: *"Bản này gỡ hoặc
  dời chỗ một control người dùng đã thấy? Ghi tên nó và chỗ mới của nó vào What's New."* Không tốn code.
- **Bằng chứng:**
  - Lightroom, 23/8/2026 ("Version 11.5 Removed Most Used Feature").
  - Google Photos, 4/9/2026 ("Hate the new update").
  - Lightroom, 17/10/2023 ("Please put rate and review back").
