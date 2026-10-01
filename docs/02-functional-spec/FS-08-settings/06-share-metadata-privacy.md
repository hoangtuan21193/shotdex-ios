# FS-08.06 — Metadata khi chia sẻ và xuất

`FS-08.06` · tier A (Settings, sheet Save) + D (Resize) · `Features/Shared/PhotoShareSheet.swift` · `Features/Settings/SettingsScreen.swift`
· `Data/Sources/PhotoEditingService.swift` · `Domain/Metadata/MetadataRewriter.swift` · `Data/Sources/ShareExportPipeline.swift` · `ShotDexTests/MetadataRewriterTests.swift` · cập nhật 2026-10-01

Nguồn intent: [2026-09-30-user-wishes-research](../../_intents/2026-09-30-user-wishes-research.md) mục 3.

**Một câu:** mỗi lần chia sẻ hay xuất, người dùng chọn giữ hết metadata, bỏ vị trí, hoặc bỏ hết. Một mặc định
trong Settings áp cho mọi lối ra; video đi nguyên bản và app nói rõ điều đó.

## 1. Người dùng cần gì

Người chụp gửi ảnh cho khách thì muốn giữ thông số máy, nhưng đăng ảnh chụp ở nhà lên mạng thì không muốn lộ toạ độ.
Hôm nay chỉ có một công tắc chung trong Settings, và lúc lưu thì bỏ hết hoặc giữ hết. Họ cần chọn cho từng lần,
và cần chắc chắn file đã rời máy không mang toạ độ khi họ chọn bỏ.

## 2. Phạm vi

**Có:** Share (ô lưới, chế độ chọn, Photo Detail, album, smart album, On This Day) · Share ảnh từ file server
(FS-17.06) · đích Share của sheet xuất server · Save Copy, Paste Edits và Resize vào Photos · kéo ảnh sang app
khác (iPad, Split View).

**Cố ý không có:**
- Upload lên file server (FS-15) — vì đó là bản lưu trữ của chính người dùng, gỡ toạ độ là hỏng bản gốc
  ([NF-03 §2b](../../04-non-functional-design/NF-03-privacy-and-security.md)).
- Export EXIF (CSV) — vì CSV chính là metadata người dùng chủ động xuất, kể cả cột toạ độ.
- Copy lên clipboard — clipboard chỉ nhận ảnh bitmap, vốn không mang metadata.
- File do Collage, Video Studio, Panorama tạo ra — các công cụ này không chép vị trí của ảnh nguồn (đọc code 2026-10-01).
- Save Changes (sửa tại chỗ) — ảnh không rời máy, nên bỏ qua lựa chọn metadata (§4).
- Gỡ metadata của **video** — video share nguyên bản ([NF-03 §3](../../04-non-functional-design/NF-03-privacy-and-security.md)).
  Vì gỡ là chép cả clip ra đĩa, một clip 4K một phút cỡ vài trăm MB.
- Share extension **"Save to ShotDex"** — nó nhận ảnh **vào** thư viện của chính người dùng, không gì rời máy;
  lưu nguyên byte.

## 3. Ba mức

| Mức | Nhãn | Bỏ | Giữ |
|---|---|---|---|
| giữ hết | **All Metadata** | không gì — trừ GPS của file khi asset **không còn vị trí** (dưới bảng) | **nguyên byte** file gốc, không ghi lại |
| bỏ vị trí | **No Location** | nhóm GPS, vị trí chủ thể, địa danh báo chí (thành phố, tỉnh, nước, địa điểm), toạ độ lặp trong XMP | mọi trường khác: máy, lens, phơi sáng, ngày chụp |
| bỏ hết | **No Metadata** | EXIF, TIFF, GPS, IPTC, XMP, MakerNote, ngày chụp | hướng xoay, color profile, kích thước — thiếu chúng thì ảnh xoay sai hoặc lệch màu · **Copyright** và **Artist** |

- Ảnh ghi lại bằng cách **chép dữ liệu ảnh sang file mới kèm bộ thuộc tính đã sửa**, không giải mã rồi mã hoá lại.
  Pixel sau khi giải mã phải trùng bản gốc (người dùng chốt 2026-10-01: không có đường mã hoá lại).
- **Asset đã bị xoá vị trí trong app mà file vẫn mang GPS**: mọi mức đều bỏ GPS của file (ở All Metadata file
  được ghi lại để bỏ đúng nhóm vị trí, mọi trường khác giữ). Vì người dùng đã xoá vị trí thì không được để nó rời
  máy. Asset **đổi** sang vị trí khác thì chưa đổi luật: All Metadata vẫn giao nguyên byte.
- No Metadata giữ Copyright và Artist, giống mức "Copyright Only" của Lightroom. Vì đó là quyền tác giả của người
  chụp, không phải dấu vết về họ. Hai trường này giữ ở mọi nơi chúng nằm (EXIF, TIFF, IPTC, XMP).
- Video không bị ghi lại ở mức nào (§2).

## 4. Chọn ở đâu

| Lối vào | Mặc định lấy từ | Đổi cho lần này |
|---|---|---|
| Share (mọi lối ở §2) | Settings → Sharing → **Metadata When Sharing** | hai dòng hành động trong share sheet (dưới bảng) |
| Save Copy của editor | Settings | picker 3 mức **trong section Save Copy** của sheet Save, thay công tắc Include Metadata; footer nói Save Changes giữ mọi thứ |
| Paste Edits | Settings | picker 3 mức, thay công tắc Include Metadata |
| Resize | Settings | segmented 3 mức, cùng kiểu với segmented Format đang có trên màn này |
| Kéo sang app khác | Settings | không có — kéo thả không có chỗ để hỏi |
| Save Changes | — | bỏ qua picker của sheet Save: ảnh không rời máy, ngày và vị trí asset giữ nguyên |

- **Settings giữ một giá trị cho toàn app**, mặc định **All Metadata**, giống Include Location đang bật sẵn hôm nay.
  Giá trị đó là mặc định của **mọi lối ra** trong bảng trên.
- **Lựa chọn của một lần không ghi đè Settings.** Lần share sau lại bắt đầu từ Settings.
- Share sheet của hệ thống không hiện nút Options của Photos. Lý do: ShotDex giao cho nó file và dữ liệu, không giao
  asset, nên không có hai control chồng nhau. SDK iOS 27.1 cũng không có đường công khai để app chèn control vào
  phần đầu share sheet.
- **Đổi mức cho một lần share** ngay trong share sheet của hệ thống:
  - Chạm Share vẫn là một chạm và chạy theo mặc định Settings.
  - Share sheet có **hai dòng hành động** của app, cho hai mức khác mặc định: *Share With Location* (về All
    Metadata), *Share Without Location*, *Share Without Metadata* — mặc định là mức nào thì dòng đó vắng.
  - Phụ đề ở đầu share sheet nói mức đang áp: *"All metadata"* · *"Location removed"* · *"Metadata removed"*.
    Phụ đề đi qua thông tin xem trước của mục share (tiêu đề + phụ đề), không phải control.
  - Chạm một dòng: share sheet đóng rồi mở lại ngay ở mức đó; phụ đề đổi theo. Chưa tải hay ghi lại gì cho tới
    khi người dùng chọn đích ([FS-02.06 §9](../FS-02-photo-detail/06-icloud-originals.md)).
- **Save Changes không bao giờ đổi ngày hay vị trí của asset.** Code 2026-10-01 xoá cả hai khi Include Metadata
  tắt (editing service ở dòng đầu, dòng 773–776), mà Revert to Original không trả lại — lỗi này phải sửa cùng spec.

## 5. Hành vi

- **Không bao giờ rò toạ độ.** File không ghi lại được thì **không** được giao đi nguyên bản. Cùng luật cho mọi lối.
- **RAW ghi lại không được.** ImageIO chỉ ghi JPEG, HEIC, PNG, TIFF… Trên máy này không có RAW hay DNG (đo trên
  macOS 2026-10-01, iOS chưa đo).
- Mẻ share có RAW và mức không phải All Metadata thì **hỏi một lần cho cả mẻ**, trước khi share sheet mở:
  - *"2 RAW files can't have their location removed"* (No Metadata: *"…their metadata removed"*);
  - **Share as JPEG** — bản JPEG render đủ cỡ của RAW, áp mức đã chọn;
  - **Share RAW with Location** — RAW đi nguyên byte;
  - **Skip** — share phần còn lại; mẻ chỉ có RAW thì không mở share sheet.
  - RAW mà iOS trên máy **không đọc được** ([FS-03.04b](../FS-03-photo-editor/04b-unsupported-raw.md), gồm Share
    Original của nó): **Share as JPEG** mờ kèm lý do *"iOS can't read this RAW yet"*; còn Share RAW with Location ·
    Skip.
- Share không có đường nào âm thầm đổi RAW sang JPEG hay bỏ RAW ra khỏi mẻ. Ngoại lệ duy nhất là kéo thả (dưới).
- **Live Photo** chia sẻ ảnh tĩnh như hôm nay. Không giao file chuyển động, nên file đó không làm lộ vị trí.
- **Share sheet mở ngay** như Photos ([FS-02.06 §9](../FS-02-photo-detail/06-icloud-originals.md)): mỗi mục là nguồn
  dữ liệu lười, chưa tải hay ghi lại gì. Người dùng chọn đích rồi mới gom.
- **Gom ra file tạm, từng ảnh một**, sau khi chọn đích: tải bản gốc nếu chỉ có trên iCloud, rồi ghi lại metadata —
  cả hai trong **cùng một modal** tiến độ giữa màn của FS-02.06. Không giữ cả mẻ trong RAM. Thư mục tạm bị xoá khi
  share sheet đóng, dù đã share hay chưa, và khi huỷ lúc đang gom.
- **Huỷ lúc đang gom** bằng Cancel của modal (hôm nay nút Share chỉ thành vòng quay, không có Cancel). Huỷ thì
  đích không nhận file nào.
- Ảnh không phải RAW mà ghi lại lỗi (file hỏng) **không bao giờ** đi nguyên bản: nó bị bỏ khỏi mẻ và nêu tên trong
  modal, cùng chỗ với ảnh tải hỏng.
- **Video share nguyên bản** ở mọi mức. Mẻ có video và mức không phải All Metadata thì phụ đề share sheet ghi
  thêm *"Videos keep their metadata"*.
- **Kéo ảnh sang app khác** gom file theo mặc định Settings, cùng luật ghi lại như Share. Ảnh đã chỉnh trong app
  thì kéo ra **bản đã chỉnh**, giống Share (người dùng chốt 2026-10-01).
  - RAW mà mặc định không phải All Metadata: kéo thả không có chỗ để hỏi, nên RAW đi dưới dạng **JPEG render đủ
    cỡ** ở mức đó. Vì không bao giờ rò toạ độ, và không có alert nào hiện được giữa lúc kéo.

## 6. Dữ liệu và ràng buộc

| Mặt | Ràng buộc |
|---|---|
| Lưu ở đâu | mặc định nằm trong cài đặt của app, khoá khai một chỗ. **Không** đụng database ([BD-02](../../01-basic-design/BD-02-database-design.md)) |
| Bộ nhớ | đỉnh RAM lúc gom **không tăng theo số ảnh**. Extension ≤ ~120 MB (con số của intent; NF-02 chưa đo trần của extension chia sẻ) |
| Thiết bị | picker vừa trên Duo ngoài 382pt (sau rail 84pt), không cắt chữ |
| iOS 26 vs trước | cả hai nhánh có cùng 3 mức, ở cùng chỗ |
| Truy cập | picker đọc ra mức đang chọn; alert RAW nêu số file RAW trong mẻ |
| Chữ | nhãn trong String Catalog; tên mức giống nhau ở Settings, Share, Save, Resize |

## 7. Tiêu chí nghiệm thu

Ảnh mẫu **A** = HEIC 48MP, GPS 10.7769 N 106.7009 E, Sony ILCE-7M4, lens FE 24-70mm F2.8 GM II, ISO 400, chụp
2026-09-20 17:05, Artist `Nguyen An`, Copyright `© 2026 Nguyen An`.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | Settings = No Location; ảnh A trong lưới | Share → Save to Files | file không có nhóm GPS; còn Make `SONY`, Model `ILCE-7M4`, ISO 400, ngày 2026-09-20 17:05; pixel giải mã trùng bản gốc | `ShareExportPipelineTests.noLocationFromTheGrid` (pipeline của nút Share ở lưới, chọn, album, smart album, On This Day), `MetadataRewriterTests.noLocationRemovesThePlaceOnly`, `.noLocationKeepsEveryPixel` (JPEG/HEIC/TIFF), `.noLocationKeepsTheGainMap`, `.failedRewriteNeverReturnsOriginal`; picker Settings iPhone 17 26.5 (2026-10-01). Còn thiếu: depth của ảnh Portrait (§8) và Save to Files trên máy — lúc `/verify` |
| AC-2 | Settings = All Metadata; ảnh A | Share, rồi chạm dòng *Share Without Metadata* trong share sheet | file không có GPS, Make, Model, ISO, ngày chụp, MakerNote; còn hướng xoay, color profile, Artist `Nguyen An`, Copyright `© 2026 Nguyen An`; Settings vẫn All Metadata, lần share sau mở ở All | ⚠️ chưa có |
| AC-3 | Settings = All Metadata; ảnh A | Share; rồi Remove Location cho A trong app và Share lại | lần 1: SHA-256 file nhận được bằng SHA-256 file gốc của asset. Lần 2: file không có nhóm GPS, còn Make `SONY`, ISO 400, ngày 2026-09-20 17:05 | lần 1 `ShareExportPipelineTests.allMetadataIsByteIdentical`, `.noLocationAnywhereStaysByteIdentical`; lần 2 `ShareExportPipelineTests.removedLocationDropsFileGPSAtAll` (vị trí asset rỗng → bỏ GPS của file, pixel trùng). Remove Location trên máy rồi Save to Files: lúc `/verify` |
| AC-4 | JPEG xuất từ Lightroom: GPS trong cả EXIF lẫn XMP, IPTC City `Ho Chi Minh City`, XMP Rating 4 | Share, No Location | không còn nhóm GPS, không còn toạ độ trong XMP, không còn City; Rating 4 vẫn còn | `MetadataRewriterTests.lightroomXMP` (JPEG một gói XMP kiểu Lightroom + IIM: không còn GPS ở EXIF/XMP, City/State/Country/Location/LocationCreated, không còn chuỗi địa danh nào trong byte của file; Rating 4, Make, pixel giữ) |
| AC-5 | Settings = No Location; ảnh A mở trong Photo Detail | chạm Share | file không có GPS, giống hệt share từ lưới | `ShareExportPipelineTests.detailMatchesGrid` (viewer đi qua `PhotoShareSheet.gather` của lưới; ảnh chưa tải tách khỏi ảnh ghi lại lỗi); iPhone 17 26.5 (2026-10-01): ảnh A (HEIC sinh trên máy, có GPS + IPTC City) → viewer → Share → Save to Files, file trong `File Provider Storage` của sim đọc bằng ImageIO: không GPS, không City, còn SONY / ILCE-7M4 / ISO 400 / ngày / Artist; thư mục `ShotDexShare-` đã xoá khi sheet đóng. Ảnh chỉ trên iCloud vẫn *Unable to Share* tới FS-02.06 task 14 |
| AC-6 | MOV iPhone 4K 30fps 10,0s có vị trí, và ảnh A; Settings = No Location | Share | phụ đề share sheet có *Videos keep their metadata*; SHA-256 của MOV nhận được bằng file gốc; ảnh A không có GPS | ⚠️ chưa có |
| AC-7 | chỉ ảnh A, không video; Settings = No Location | Share | phụ đề là *Location removed*, không có *Videos keep their metadata*; share sheet có đúng hai dòng của app: Share With Location, Share Without Metadata | ⚠️ chưa có |
| AC-8 | Live Photo có GPS | Share, No Location | share sheet nhận **1** item: ảnh tĩnh không có GPS; không có file chuyển động | một phần: `ShareExportPipelineTests.livePhotoSharesOneStill` (1 item, resource ảnh tĩnh, không bao giờ video đi kèm); không GPS ⚠️ chưa có |
| AC-9 | 2 ARW Sony (RAW riêng lẻ, có GPS) + ảnh A đã chọn | Share, No Location | đúng **một** alert *2 RAW files can't have their location removed* với Share as JPEG · Share RAW with Location · Skip, trước khi share sheet mở; chọn Skip → share sheet nhận 1 file (A, không GPS) | ⚠️ chưa có |
| AC-10 | chọn 20 ảnh như A | Share, No Location | share sheet nhận 20 file, 0 file có GPS, 20 file còn Make `SONY`. Đỉnh RAM lúc gom cao hơn lúc gom 1 ảnh không quá dung lượng 1 file | `ShareExportPipelineTests.twentyPhotosPeakIsFlat` (20 JPEG 48MP 45 MB sinh lúc chạy: 0 GPS, 20 còn SONY; đỉnh +127 MB với 1 ảnh, +130 MB với 20 — iPhone 17 26.5, 2026-10-01) |
| AC-11 | chọn 20 ảnh, 5 ảnh chỉ có trên iCloud; Share → chọn Save to Files; modal đang gom | chạm Cancel trong modal | Files không nhận file nào; thư mục tạm của lượt này rỗng; thoát chọn thì không mất ảnh nào | ⚠️ chưa có |
| AC-12 | ảnh A trong editor, đã chỉnh | Save Copy với No Location | asset mới: file không có GPS, vị trí asset rỗng, ngày asset = 2026-09-20 17:05, còn Make/Model | ⚠️ chưa có |
| AC-13 | NAS có cặp `DSCF1000.RAF` + `DSCF1000.JPG`, cả hai có GPS; Settings = No Location | Share từ trình duyệt server, chọn Skip ở alert RAW | JPG nhận được không có GPS; RAF không được giao đi; đóng share sheet thì bản tạm bị xoá | một phần: `ServerEditHandoffTests.shareHandsOriginalAndCleansUp` (chỉ JPEG); RAF ⚠️ chưa có |
| AC-14 | 40 ảnh HEIC 48MP chia sẻ từ Files vào Save to ShotDex | Save to Photos | đỉnh bộ nhớ extension < 120 MB; 40 asset mới; SHA-256 mỗi file bằng file nguồn (extension không đổi metadata) | ⚠️ chưa có |
| AC-15 | như AC-9 | chọn Share as JPEG | share sheet nhận 3 file: JPEG cỡ đầy đủ của 2 ARW, và A; 0 file có GPS; cả 3 còn Make `SONY` | ⚠️ chưa có |
| AC-16 | như AC-9 | chọn Share RAW with Location | share sheet nhận 2 ARW nguyên byte (SHA-256 bằng gốc) và A không có GPS | ⚠️ chưa có |
| AC-17 | ảnh A trong editor, đã chỉnh; Settings = No Metadata | Save Changes | Save Changes bỏ qua picker của section Save Copy; footer nói Save Changes giữ mọi thứ; ngày asset vẫn 2026-09-20 17:05, vị trí asset vẫn 10.7769 N 106.7009 E | `AssetMetadataCarryOverTests.saveChangesNeverTouchesDateOrLocation` (không đường nào xoá ngày/vị trí asset; Save Changes không nhận công tắc); ảnh sheet Save Edit iPhone 17 26.5 (2026-10-01). Kiểm ngày/vị trí asset trước/sau trên máy thật: lúc /verify |
| AC-18 | Settings = No Location; ảnh A | mở sheet Resize, rồi Paste Edits lên A | cả hai mở ở No Location; hai asset mới không có GPS, còn Make/Model | ⚠️ chưa có |
| AC-19 | iPad, Split View với Files; Settings = No Location; ảnh A đã chỉnh trong app (Exposure +1) | kéo ảnh A sang Files | file nhận được là **bản đã chỉnh**, không có GPS, còn Make `SONY`, ISO 400 | ⚠️ chưa có |
| AC-20 | Settings = No Location; ảnh A | Share, chạm *Share With Location* | share sheet đóng rồi mở lại với phụ đề *All metadata*; file nhận được có SHA-256 bằng gốc; Settings vẫn No Location | ⚠️ chưa có |
| AC-21 | iPad, Split View với Files; Settings = No Location; một ARW có GPS | kéo ARW sang Files | Files nhận một JPEG đủ cỡ, không GPS, còn Make `SONY`; không có alert | ⚠️ chưa có |
| AC-22 | ảnh server `DSCF1000.JPG` (của AC-13) đã chỉnh trong editor; Settings = No Location | Export…, chọn đích **Share…** ([FS-17.06 §6](../FS-17-import-from-server/06-edit-and-export.md)), rồi Save to Files | file nhận được là bản render không có nhóm GPS, còn Make/Model; share sheet có hai dòng của app như AC-7; Settings vẫn No Location | ⚠️ chưa có |

**Chưa chứng minh được:** AC-2 → AC-12 và AC-14 → AC-22. AC-1 và AC-13 mới có một phần.

## 8. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| ghi lại HEIC có thể làm mất gain map HDR và depth của ảnh Portrait: test hiện có chỉ kiểm kích thước | **đo 2026-10-01** (`MetadataRewriteProbeTests`, iOS 26.5 + 18.6, kết quả như nhau): chép không giải mã giữ gain map HDR; mã hoá lại thì mất. Depth **chưa đo được** — ImageIO trên simulator từ chối ghi bản đồ disparity tự dựng; cần một ảnh Portrait thật không có người lúc `/verify` |
| vị trí sửa bằng Adjust Location nằm ở asset, còn file vẫn mang GPS cũ. All Metadata có thể giao toạ độ người dùng tưởng đã xoá | asset không còn vị trí → bỏ GPS của file ở mọi mức (§3, AC-3). Asset đổi sang vị trí khác: chưa có luật, All vẫn nguyên byte |
| ghi lại HEIC ở No Metadata không giải mã có thể để sót ngày chụp và IPTC City/Rating (đo macOS 27.0) | **đo 2026-10-01 trên iOS 26.5 + 18.6: còn sót.** Cả bốn cách chép không giải mã (bộ mới chỉ có trường giữ lại, có/không `ShouldExcludeXMP`; bộ gốc gỡ hết trường khác; như trên mà giữ trường cấu trúc) đều để lại ngày chụp, City (IPTC và XMP), địa điểm XMP và Rating; gỡ được GPS, Make, ISO. Chỉ mã hoá lại mới sạch, mà mã hoá lại thì pixel đổi và mất gain map. Chờ người dùng chọn cách (plan task 11) — tới lúc đó HEIC ở No Metadata ghi lại không đạt kiểm tra sau ghi, nên bị bỏ khỏi mẻ và nêu tên, không bao giờ đi nguyên bản |
| định dạng không nén mất dữ liệu (PNG, TIFF) | **đo 2026-10-01 (iOS 26.5 + 18.6):** PNG chép không giải mã **giữ nguyên GPS** ở cả No Location lẫn No Metadata; TIFF chép thì No Location sạch, No Metadata còn Make/ISO/MakerApple. Mã hoá lại hai định dạng này cho pixel trùng từng byte và sạch ở cả hai mức. Chưa chọn: cho PNG/TIFF mã hoá lại (pixel vẫn trùng) hay bỏ khỏi mẻ. Tới lúc chọn, ghi lại không đạt kiểm tra sau ghi thì bỏ khỏi mẻ và nêu tên |
| JPEG | **đo 2026-10-01 (iOS 26.5 + 18.6):** chép không giải mã sạch ở cả hai mức, pixel trùng; No Location giữ Make, ISO, ngày, MakerApple, Rating, Artist, Copyright; No Metadata giữ hướng xoay, P3, Artist, Copyright. Mã hoá lại (cách `stripLocation` cũ) đổi pixel |
| video slow-mo không phải một file, nên hôm nay share bỏ qua nó mà không báo | ghi vào intent mục 1. Spec này không sửa |
| ba lối lưu đang dùng chữ "Include Metadata", mà đổi sang 3 mức là đổi chữ ở 4 màn | chạy agent `copy-consistency` sau khi làm |
| nhãn "Metadata When Sharing" mà áp cho cả Save Copy, Resize và kéo thả | `copy-consistency` xét lại nhãn khi làm |
| share sheet của hệ thống có thể xếp hai dòng của app xuống dưới các app khác, khó thấy | chụp trên iPhone 402pt và Duo ngoài ở `/verify`; ghi vị trí thật vào spec |
