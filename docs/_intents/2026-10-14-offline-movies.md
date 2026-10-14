# Intent: Phim offline trong ShotDex — xem trên máy bay, phụ đề đôi để học tiếng

| Trường | Giá trị |
|---|---|
| Tác giả | Hoang Tuan (lời người dùng), Claude soạn |
| Ngày | 2026-10-14 |
| Trạng thái | accepted — người dùng 2026-10-14 |
| Tiến độ | **đang làm** (2026-10-14) — plan [2026-10-14-fs23-movies](../_plans/2026-10-14-fs23-movies.md) đã duyệt, spike S1 **đi** ([báo cáo](2026-10-14-fs23-s1-vlckit-spike.md)), S2 **đi** ([báo cáo](2026-10-14-fs23-s2-mkv-subtitles-spike.md)), S3 **đi** ([báo cáo](2026-10-14-fs23-s3-plex-spike.md)); hết spike; task 25/36 xong, 22/56 AC xanh (AC-1, 4, 7, 8, 9, 11, 12, 13, 14, 15, 16, 18, 19, 20, 24, 25, 26, 39, 40, 44, 45, 46; AC-2, 3, 5, 6, 10, 21, 22, 41, 53, 55, 43, 52, 54 một phần); 3 spike + 36 task; spec FS-23 (56 AC) + FS-08.07 (9 AC) |
| Nguồn | phản hồi người dùng 2026-10-14 |
| Spec sinh ra từ đây | [FS-23](../02-functional-spec/FS-23-offline-movies/README.md) · [FS-08.07](../02-functional-spec/FS-08-settings/07-ai-providers.md) |

## Problem — vấn đề

Người dùng muốn mang phim lên máy bay để xem lúc không có mạng, và xem với hai phụ đề cùng lúc để học tiếng. Hôm nay
ShotDex không làm được việc nào trong đó:

- **Không có chỗ để phim.** Mọi video ShotDex mở được đều là `PHAsset` của thư viện Photos
  (`VideoPlaybackModel.swift:57,207` → `PhotoLibraryService.swift:918-933`). Muốn xem trong app thì phải đưa phim vào
  Photos, mà Photos đồng bộ iCloud: một bộ phim vài GB chiếm dung lượng iCloud, trộn vào thư viện ảnh, nhảy vào
  Statistics/Duplicates/Backup (FS-22) như một "video đã chụp".
- **Không mở được định dạng phim thường gặp.** Player hiện tại là AVPlayer, chỉ chạy MP4/MOV/M4V với codec Apple hỗ
  trợ. MKV, FLV, AVI, WMV, WebM, âm thanh AC3/DTS, phụ đề ASS/PGS nằm trong file — không mở được. Repo không có thư
  viện giải mã nào ngoài AVFoundation (Package.resolved: GRDB, SMBClient, Citadel, swift-collections, …).
- **Không có phụ đề khi xem.** Không có trình đọc SRT/WebVTT/ASS, không có chọn track phụ đề (`AVMediaSelection`
  không dùng ở đâu). Thứ duy nhất dính tới phụ đề là ghi track phụ đề lúc *xuất* video trong Video Studio
  (`VideoExportWriter.swift:37,103,213`).
- **Không tìm được phụ đề.** Phim tải về thường không kèm sub, hoặc không có ngôn ngữ cần. Người dùng phải tự lên web
  tìm file `.srt` khớp đúng bản phim (đúng release, đúng tốc độ khung hình), tải về, đổi tên — trên điện thoại gần như
  không ai làm.
- **Không xem hai phụ đề cùng lúc.** Infuse và player hệ thống chỉ hiện một phụ đề. Muốn học tiếng (ví dụ tiếng Anh
  trên, tiếng Việt dưới) thì không có app nào trong máy làm. Và nhiều phim chỉ có sub một thứ tiếng — thứ tiếng thứ hai
  không tồn tại để mà tải.

Ai bị ảnh hưởng: chính người dùng ShotDex, mỗi chuyến bay dài. Mức độ: không có cách làm trong app; cách làm ngoài app
(Infuse + tự tìm sub) không có phụ đề đôi.

Lời người dùng: "lưu video movie offline vào shotdex, không up lên library của iCloud … để lên máy bay xem lúc không có
mạng. movie phải support subtitle, hỗ trợ download sub dựa vào metadata của file movie, cho chọn ngôn ngữ rồi tìm xong
rồi cho người dùng chọn như kiểu infuse … các định dạng như flv, mp4 … cho phép render 2 subtitle lên cùng 1 video …
dùng AI để generate subtitle thứ 2 sang một ngôn ngữ khác … cho chọn vị trí hiện 2 sub, 1 cái trên 1 cái dưới".

## Proposed outcome — kết quả mong muốn

1. **Kho phim riêng trong ShotDex**, nằm ngoài thư viện Photos: không lên iCloud Photos, không nằm trong bản sao lưu
   iCloud của máy, không vào Library/Statistics/Duplicates/Backup. Thấy rõ mỗi phim chiếm bao nhiêu chỗ và còn trống bao
   nhiêu; xoá được.
2. **Đưa phim vào** (đổi 14/10: thư viện nhiều nguồn có stream + Plex — xem cuối mục Open questions) từ những nơi người dùng đã có: server/NAS đã nối trong ShotDex (FS-15/FS-17), app Files, Share
   sheet / AirDrop. Phim lớn tải lâu thì thấy tiến độ, tải dở được tiếp, không chiếm hết bộ nhớ máy.
3. **Mở được phim như Infuse**: MP4, MOV, M4V, MKV, FLV, AVI, WMV, WebM… cùng các track âm thanh và phụ đề nằm sẵn
   trong file; chọn track âm thanh; nhớ chỗ đang xem; xem được khi máy bay ở chế độ máy bay.
4. **Tìm phụ đề trên mạng theo chính file phim**: ShotDex đọc tên/metadata/mã băm của file để đoán phim nào (tên, năm,
   mùa/tập), người dùng chọn ngôn ngữ, ShotDex hiện danh sách kết quả (tên bản, ngôn ngữ, độ khớp, lượt tải), người dùng
   chọn một cái — giống Infuse. Phụ đề tải về được giữ cùng phim để xem offline. Cũng nhập được file sub có sẵn.
5. **Hai phụ đề cùng lúc**: chọn sub chính và sub phụ, mỗi cái một vị trí (một trên một dưới, hoặc cả hai ở dưới xếp
   chồng), chỉnh được cỡ chữ; lệch giờ thì dịch được từng sub.
6. **AI tạo sub thứ hai**: phim chỉ có sub một thứ tiếng thì ShotDex dịch sang thứ tiếng khác, làm trước khi lên máy
   bay, rồi giữ lại để xem offline. Người dùng chọn AI nào dịch (on-device, máy chủ LLM ở nhà, hay dịch vụ cloud bằng API
   key của mình); cài đặt AI nằm ở một mục riêng trong Settings.

## Affected users and systems — phạm vi ảnh hưởng

- **Màn hình:** chip Movies trong Albums, danh sách phim, màn phát phim toàn
  màn, sheet tìm phụ đề, bảng chọn phụ đề/âm thanh, trạng thái tải. Settings: mục AI mới (nhà cung cấp, API key, máy
  chủ LLM cục bộ), dung lượng kho phim. Đường vào từ duyệt server (FS-17) và Share sheet.
- **Thiết bị:** iPhone · iPad · Duo trong · Duo ngoài (466×678, rail 84pt) · Mac (FS-18…21, chưa có code — câu 8).
- **Tầng code:**
  - Data: kho file mới trong Application Support (đã có tiền lệ `ImportedMusicStore.swift:28`), tải từ server qua
    `RemoteFileClient.download` (`Domain/ServerUpload/RemoteFileClient.swift:41`, đủ WebDAV/SMB/SFTP/Files), client
    mạng mới cho nguồn phụ đề.
  - Domain: đọc tên file ra tên phim/năm/mùa/tập, mã băm file, đọc/ghép/dịch giờ phụ đề (SRT, VTT, ASS).
  - Features: kho phim + player mới. Player hiện tại (`ZoomableVideoView`, `DetailVideoPlayer`) gắn chặt với
    `PHAsset`.
  - AI: lớp gọi nhiều nhà cung cấp LLM (Foundation Models, máy chủ cục bộ, Claude/OpenAI/OpenRouter/Grok/Gemini),
    dùng chung cho dịch sub và AI Search (câu 9).
    Hiện có `FoundationModels` (`AISearchTranslator.swift:4`, iOS 26 + Apple Intelligence) và `Speech`
    (`SpeechCaptionService.swift`); chưa dùng framework Translation.
  - Info.plist: `LSSupportsOpeningDocumentsInPlace = false` (`ShotDex/Info.plist:187`), không có
    `UIFileSharingEnabled`; không có `URLSession` nền (`UIBackgroundModes` chỉ `fetch`, `processing`).
- **Dữ liệu:** bảng mới cho phim (đường dẫn file, chỗ đang xem, track chọn) và phụ đề đi kèm. Đây là dữ liệu người dùng
  tạo, phải ở bảng riêng, không trong `photo_metadata`. App chưa phát hành → không cần migration giữ dữ liệu cũ.
- **Dung lượng app:** VLCKit thêm khoảng 40–60 MB vào app.
- **Tài liệu đang có phải sửa:** FS-02.02 §1 (luật không thêm thư viện player → chỉ cho video trong Photos), FS-08
  Settings (mục AI).

## Constraints — ràng buộc

- **Phim không vào thư viện Photos** và không lên iCloud: file đánh dấu không sao lưu (`isExcludedFromBackup`), không
  qua PhotoKit.
- **Không tải từ YouTube hay dịch vụ streaming** (luật đã có cho nhạc: vi phạm ToS + bản quyền + App Store từ chối).
  Không bẻ DRM (Netflix, Apple TV…). Phim đến từ file người dùng đã có.
- **Không làm đầy bộ nhớ máy**: kiểm chỗ trống trước khi tải, như Backup FS-22 và `ServerOriginalLoader.swift:30`.
- **Đụng luật đang có** — FS-02.02 §1: "Giữ khung phát của hệ thống, không thêm thư viện player". MKV/FLV/AVI/ASS
  không mở được bằng AVPlayer, nên đòi hỏi định dạng "như Infuse" va thẳng vào luật này. Lý do của luật (mất đường lấy
  video của Photos) không áp dụng cho phim offline vì phim không nằm trong Photos. Đã chốt (câu 2): VLCKit cho phim
  offline, luật FS-02.02 thu lại chỉ còn cho video trong Photos.
- **Dependency mới** phải duyệt riêng, giấy phép dùng được trên App Store, **không GPL/AGPL**. VLCKit dùng bản LGPL, nhúng
  dạng framework động; module GPL (nếu có trong bản build) phải tắt.
- **Dịch phụ đề**: nội dung phụ đề chỉ rời máy khi người dùng tự chọn một dịch vụ cloud, và chỗ chọn nói rõ điều đó.
  API key nằm trong Keychain, không trong database, không trong log.
- **Nguồn phụ đề trên mạng** có điều khoản riêng và giới hạn lượt tải mỗi ngày. Không bắt người dùng tạo/nhập tài
  khoản nguồn phụ đề (câu 11). Chỉ dùng API chính thức, không cào web.
- Không làm hỏng nhánh iOS 17–25 và nhánh iOS 26. Min target iOS 17 — FoundationModels chỉ iOS 26 + máy có Apple
  Intelligence; framework Translation có API cho app từ iOS 18.
- UI theo `DESIGN.md`; màn mới phải có board trên canvas từng thiết bị trước khi code (luật design đi cùng code).

## Open questions — câu hỏi còn treo

Đã trả lời (người dùng 2026-10-14):

1. **Kho phim nằm ở đâu** → **mục "Movies" trong Albums.** Không thêm tab.
2. **Engine phát phim** → **VLCKit** (LGPL 2.1, mở hầu hết định dạng + sub ASS/PGS sẵn, ~40–60 MB, giao diện tự làm).
   Dependency mới được duyệt ở đây. FS-02.02 §1 sửa thành luật cho video *trong Photos*; phim offline đi engine riêng.
3. **Phim lấy từ đâu** → **server/NAS đã nối (FS-15/FS-17) + app Files + Share sheet/AirDrop.** Không tải từ link HTTP.
4. **AI dịch sub thứ hai** → **người dùng chọn nhà cung cấp**:
   - **Foundation Models** của Apple — chỉ hiện khi máy hỗ trợ (iOS 26 + Apple Intelligence).
   - **LLM offline chạy ở máy chủ cục bộ** (ví dụ Ollama, LM Studio) — người dùng nhập địa chỉ.
   - **API key dịch vụ ngoài**: Claude, ChatGPT, OpenRouter, Grok, Gemini…
   - Có **mục AI riêng trong Settings** để cài các nhà cung cấp; lúc dịch sub thì chọn một cái trong số đã cài. Chưa cài
     cái nào → gợi ý và dẫn sang mục AI trong Settings.
   - Hệ quả cho ràng buộc: API key ở Keychain, không ở database; chọn dịch vụ cloud nghĩa là nội dung phụ đề rời máy —
     phải nói rõ ở chỗ chọn.
5. **Apple Translation** → **có, là một lựa chọn, không mặc định.** On-device, miễn phí, dịch offline sau khi tải gói
   ngôn ngữ, iOS 18+. Chưa cài/chọn nhà cung cấp nào → gợi ý sang mục AI trong Settings như câu 4.
6. **"localhost"** → **máy chủ trong mạng nhà**: Ollama/LM Studio trên Mac/PC, nhập địa chỉ (kiểu
   `http://192.168.1.10:11434`) + tên model. Không chạy model trên chính iPhone.
7. **Ảnh offline** → **có, cả ảnh** được giữ offline ngoài Photos, nhưng **là một chip riêng trong Albums**, tách khỏi
   chip Movies — viết ở intent riêng (câu 10).
8. **Thiết bị** → **iPhone · iPad · Duo · Mac** trong đợt này. Lưu ý: app Mac (FS-18…21) mới có spec, chưa có code —
   phim/ảnh offline trên Mac đứng sau phần nền của app Mac. VLCKit có bản macOS.

9. **Mục AI dùng chung cho AI Search** → **có**, nhưng ở bước spec người dùng chốt thêm: AI Search **không dùng
   cloud** (vốn từ gửi đi có tên địa điểm) — chỉ Apple Intelligence hoặc máy chủ trong nhà. AI Search (`AISearchTranslator.swift`, hôm nay cố định Foundation
   Models) cũng chọn nhà cung cấp từ mục AI trong Settings: Foundation Models, Apple Translation không áp dụng (không
   phải LLM), LLM máy chủ nhà, API key cloud.
10. **Ảnh offline** → **tách intent riêng** (`offline-photos`), viết sau. Intent này không làm chip ảnh.
11. **Nguồn phụ đề** → **đổi ở bước spec (2026-10-14): bỏ tìm phụ đề trên mạng**; người dùng tự tải file phụ đề
    rồi đưa vào ShotDex (Files, Share/AirDrop, cạnh phim). Lý do: điều khoản OpenSubtitles và SubDL chỉ cho dùng
    không đăng nhập khi app trả phí hằng tháng. Câu trả lời cũ, giữ để biết vì sao đổi: **dùng các nguồn không cần tài khoản người dùng**:
    OpenSubtitles.com chạy bằng key của app, không đăng nhập (lượt tải ẩn danh bị giới hạn theo IP), cộng nguồn khác
    cũng chỉ cần key của app (SubDL, Podnapisi) để bù lượt. Kết quả gộp vào một danh sách để chọn như Infuse.
    Ghi chú: Infuse không hỏi tài khoản vì Firecore có thoả thuận riêng với OpenSubtitles; API công khai không có sẵn
    đường đó.
12. **AI tạo sub từ tiếng trong phim** → **không trong đợt này.**
13. **Một intent** → **một intent, spec tách nhiều FS**: kho + player, phụ đề (tìm/đôi/dịch), mục AI trong Settings.

Đổi phạm vi ở bước Design (người dùng, comment trên canvas 2026-10-14; chốt qua planboard
`.planboard/movies-library/`, 9 quyết định):

- **Movies là thư viện chung của mọi nguồn**, như Infuse: thư mục NAS/Files và máy chủ **Plex** trong mạng nhà là
  nguồn; ở nhà bấm là **stream**, phim cần mang đi thì **Download**. Phim có trên máy mang dấu ✓, có bộ lọc
  "On This iPhone"; xa nhà thì phim stream hiện mờ. *Vì:* spec cũ chỉ chép-rồi-xem, người dùng tưởng là stream và
  muốn cả hai, nhìn vào biết ngay phim nào xem được offline.
- **Plex**: đăng nhập tài khoản Plex của người dùng bằng mã plex.tv/link; stream bản gốc; tải bản gốc kèm poster, năm,
  mô tả để xem offline; đồng bộ chỗ đang xem với Plex.
- **Grid poster dọc** (tên + năm) mặc định, List trong ⋯; **search** và **sort**. Poster phim NAS lấy từ ảnh có sẵn
  (poster.jpg, ảnh nhúng), thiếu thì khung hình — không gọi dịch vụ ngoài.
- **Gọn lại**: một bảng "Audio & Subtitles"; + chỉ còn Add a Source… / Add Movie Files…; việc của từng phim vào menu.

Claude kiểm trước khi viết spec (không chờ người dùng):

- Điều khoản và giới hạn thật hôm nay của OpenSubtitles khi không đăng nhập (số nguồn ghi 5, 10, 20, 200 lượt/ngày —
  không khớp nhau), của SubDL và Podnapisi; nguồn nào cho phép dùng trong app iOS miễn phí.
- Bản VLCKit nào build được LGPL cho iOS/macOS, và giấy phép có hợp App Store.

Còn treo (không chặn sang Design):

14. **Có nên nằm trong ShotDex không?** ShotDex là app cho người chụp ảnh; kho phim + player là một sản phẩm thứ hai
    trong app. Người dùng đã nói rõ muốn trong ShotDex — ghi lại để `challenger` xem ở bước spec, không chặn.

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
