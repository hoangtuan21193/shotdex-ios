# BD-02 — Thiết kế database

`BD-02` · `ShotDex/Data/Database/` · `ShotDexTests/DatabaseTests.swift` · cập nhật 2026-10-02

**Một câu:** bảng nào giữ gì, và luật giữ cho dữ liệu người dùng không bị lượt index xoá mất.

## 1. Quy tắc

- **Lượt index ghi đè nguyên một dòng metadata.** Cột nào nó không biết sẽ bị xoá trắng ở mỗi lần index lại
  → **mọi dữ liệu người dùng tự nhập, và mọi kết quả quét đắt tiền, phải nằm ở bảng riêng.**
- **Tổng hợp (gom nhóm, chia dải, phân vị) làm trong truy vấn**, không gom trong Swift.
- Favorite, và sao trên iOS 27: **thư viện ảnh là nguồn thật**; cột trong database chỉ để lọc nhanh và được
  đồng bộ lại khi thư viện báo thay đổi. Dưới iOS 27 Photos không có sao, nên sao người dùng chấm nằm ở bảng
  riêng (§3) — nó là dữ liệu tự nhập, không đọc lại được từ ảnh.
- **Số megapixel không lưu** — nó tính ra từ chiều rộng và chiều cao.
- Cột **suy ra được từ ảnh** thì ở lại bảng chính, dù lượt index có ghi đè: ghi lại nó chỉ tốn công
  đọc, không mất gì. `isPanorama` là ca mẫu — nó là "cờ panorama của hệ thống **hoặc** thẻ XMP ShotDex
  ghi vào file khi ghép" ([FS-14 §7](../02-functional-spec/FS-14-panorama/01-screen-and-flow.md)), cả
  hai đều đọc lại được từ asset và từ file. Luật bảng riêng là cho thứ **không** đọc lại được: cái
  người dùng gõ vào, và kết quả quét đắt tiền.

## 2. Bảng metadata chính

```
assetId TEXT PK                  -- id ảnh do thư viện hệ thống cấp
creationDate, modificationDate   INTEGER epoch
mediaType                        -- 1 ảnh, 2 video; video có dòng nhưng không có EXIF
cameraManufacturer, cameraModel, normalizedCameraModel, normalizedCameraManufacturer
lensManufacturer, lensModel, normalizedLensModel
originalFilename                 -- dùng cho tìm kiếm theo tên file
iso INTEGER, aperture REAL
shutterSpeedSeconds REAL, shutterSpeedDisplay TEXT
focalLength REAL, focalLengthIn35mm REAL
calculatedEquivalentFocalLength REAL, equivalentFocalLength REAL   -- bản phẳng, để lọc và vẽ biểu đồ
sensorFormat TEXT, cropFactor REAL
width, height INTEGER
fileSize INTEGER
latitude, longitude REAL
placeName, placeSubLocality, placeLocality, placeAdminArea,
placeCountry, placeCountryCode, placeAddress TEXT
placeSearchText TEXT             -- viết thường + bỏ dấu; cột DUY NHẤT tìm theo địa điểm
placeCellKey TEXT, placeResolvedAt INTEGER   -- ô lưới ~110m, ghi bằng đường riêng
isFavorite INTEGER
rating INTEGER                   -- sao 0–5 của Photos (iOS 27+), đọc lại từ ảnh như favorite; NULL = chưa đọc (dưới 27, dòng cũ), truy vấn coi là 0
mediaSubtypes INTEGER            -- mặt nạ bit kiểu chụp, lấy thẳng từ thư viện hệ thống
isPanorama INTEGER               -- cờ hệ thống HOẶC thẻ XMP của ShotDex; xem quy tắc dưới
indexedAt INTEGER
exifStatus TEXT                  -- đã đọc / không có EXIF / chưa đọc / chờ iCloud / lỗi
indexerVersion INTEGER           -- phiên bản bộ index đã ghi dòng này
readAttempts INTEGER             -- số lần "tải được mà đọc không ra"; lỗi mạng KHÔNG đếm
```

Có chỉ mục trên: tên máy và tên ống kính đã chuẩn hoá · ISO · khẩu · tốc độ · tiêu cự · tiêu cự tương đương
· khổ cảm biến · ngày chụp · loại media.

## 3. Bảng vệ tinh

| Bảng | Giữ gì |
|---|---|
| Dấu vân tay ảnh | id ảnh · dấu vân tay 64 bit (rỗng = chưa lấy được ảnh) · ngày sửa lúc tính · thời điểm tính |
| Nhóm ảnh trùng | một dòng cho mỗi ảnh trong mỗi nhóm, theo từng mức so trùng **và từng nguồn** (`v30-photoSources`, FS-19.04 §4) |
| Trạng thái quét trùng | mức so trùng · nguồn · lần quét cuối · số nhóm |
| Kết quả quét chủ thể | id ảnh · số khuôn mặt · số chó mèo · thời điểm quét |
| Gán cảm biến thủ công | những máy người dùng tự chỉ định |
| Trạng thái index | điểm chạy tiếp · lần index cuối · mốc thay đổi của thư viện |
| Smart album | truy vấn đã lưu |
| Biểu đồ thống kê | id · đặc tả dạng JSON · vị trí |
| Sản phẩm đã tạo | collage và project video mở lại được ([FS-06.01b](../02-functional-spec/FS-06-collections/01b-album-management-and-creations.md)); project video lưu thành **nháp** từ lần sửa đầu — cột "ngày xuất" rỗng = nháp, mọi dòng có trước `v29-creationDrafts` lấy ngày sửa làm ngày xuất ([FS-12.18 §5](../02-functional-spec/FS-12-video-studio/18-drafts.md)) |
| File server | server người dùng khai: giao thức · host · cổng · user · share · thư mục · host key đã tin ([FS-15](../02-functional-spec/FS-15-server-upload/README.md)); mật khẩu ở Keychain |
| Lịch sử upload | id ảnh · file nào của ảnh · server (id + **tên lúc đẩy**) · đường dẫn · số byte · SHA-256 · lúc nào |
| Phán quyết bộ giải RAW | máy (hãng\|model đã chuẩn hoá) · bản build iOS · đọc được / chưa đọc được / chưa biết · nguồn (danh sách / thử file / editor) · lúc nào ([FS-03.04b §5](../02-functional-spec/FS-03-photo-editor/04b-unsupported-raw.md)) |
| Cặp RAW giữ RAW làm bản gốc | id ảnh mang tên file RAW mà có kèm JPEG/HEIC — không bao giờ có dấu RAW chưa đọc được |
| Sao chờ lên Photos | id ảnh · sao 1–5 · lúc đặt — sao chấm trên iOS 17–26, hoặc chưa ghi lên Photos được ([FS-01.12 §4–5](../02-functional-spec/FS-01-library/12-rating-and-flags.md)) |
| Cờ | id ảnh · Pick hoặc Reject · lúc đặt — không dòng là không cờ; chỉ ShotDex có, không đồng bộ |
| Keyword Photos (gương) | id ảnh · keyword đúng cách viết · khoá gấp hoa-thường · khoá gấp hoa-thường + dấu — một dòng mỗi (ảnh, keyword); chỉ mục trên hai khoá ([FS-02.07 §8](../02-functional-spec/FS-02-photo-detail/07-caption-and-keywords.md)) |
| Caption Photos (gương) | id ảnh · caption · bản gấp hoa-thường + dấu để tìm |
| Trạng thái lượt đọc gương | id ảnh cuối của lượt đọc đầy · lúc đọc xong (rỗng = cần đọc đầy) |

- Dấu vân tay có **ngày sửa lúc tính**: lệch với ngày sửa hiện tại thì tính lại (ảnh vừa được chỉnh). Video
  không có dòng.
- Bảng quét chủ thể: **có dòng nghĩa là "đã nhìn qua"**, và **số khuôn mặt bằng 0 là một câu trả lời thật**,
  không phải "chưa biết". Danh sách việc = ảnh tĩnh **chưa có dòng**.
- **Lịch sử upload sống lâu hơn server và hơn ảnh**: xoá server thì id về rỗng, tên ở lại; xoá ảnh thì dòng
  ở lại. Nó là bằng chứng một file an toàn ở nơi khác — đúng lúc xoá thứ nó mô tả là lúc cần nó nhất.
- Phán quyết bộ giải là **kết quả quét**: xoá bảng thì mất một lượt xét, dựng lại ở lần mở app kế tiếp. Lên bản
  build iOS mới thì có dòng mới; dòng của build cũ không còn ai đọc.
- **Sao hiện hành = sao chờ nếu có dòng, không thì cột sao của Photos.** Một luật cho cả hai đời iOS. Lên iOS 27,
  bảng chờ được ghi lên Photos bằng **một** khối thay đổi rồi rỗng dần; bảng cờ thì sống mãi. Vì vậy hai bảng
  tách nhau.
- Ngoài lúc người dùng bỏ sao/cờ và lúc ghi lên Photos, hai bảng này chỉ mất dòng khi ảnh **bị xoá thật** — và
  không ngay: ảnh thành **mồ côi** (bảng Ảnh, §3b), sao/cờ rời số đếm và bộ lọc ngay, dòng ở lại **30 ngày** rồi bị
  dọn lúc mở app cùng mọi dữ liệu người dùng khác của ảnh, **trừ** lịch sử upload, tải về, nhập thẻ (FS-19.05 §5).
  Quyền `.limited` không bao giờ làm mồ côi — ảnh không thấy chưa chắc đã mất. Clear local metadata index không đụng
  hai bảng này.
- **Gương caption/keyword là bản sao của Photos, không phải dữ liệu người dùng** (iOS 27, `v28-captionKeywordMirror`):
  Photos giữ bản thật, hai bảng chỉ để lọc và tìm. Vì vậy chúng **đi theo dòng metadata** — xoá ảnh thì xoá cùng
  transaction, Clear local metadata index xoá cả gương lẫn trạng thái rồi đọc lại từ Photos — khác bảng sao/cờ. Lượt
  index **không bao giờ** ghi chúng (upsert dòng metadata không đụng), nên index lại toàn bộ giữ nguyên gương. Không
  khoá ngoại: một `REPLACE` của lượt index sẽ kéo cả gương đi. Mọi truy vấn tới người dùng đều JOIN dòng metadata,
  nên dòng gương của ảnh không còn index (hay không chia sẻ dưới `.limited`) không bao giờ lộ ra.
- Mở màn ảnh trùng **chỉ đọc hai bảng cache** rồi ghép với dữ kiện hiện tại — **không** tính lại dấu vân
  tay, **không** gom lại nhóm.

## 3b. Ảnh, bản sao, nguồn (`v30-photoSources`, [FS-19.05](../02-functional-spec/FS-19-photo-sources/05-data.md))

Một ảnh là một **id** với các **bản sao** ở các **nguồn** (thư viện Photos, thư mục, ổ ngoài, server). Ảnh Photos
**giữ id thư viện cấp** làm id ảnh, nên mọi bảng ở §3 vẫn khoá theo id cũ — không dòng nào bị viết lại.

| Bảng | Giữ gì | Loại |
|---|---|---|
| Nguồn | loại · tên · bookmark · id ổ · connection · thư mục con · ghép RAW+JPEG · khi ổ rút · trạng thái · điểm chạy tiếp; thư viện Photos là dòng `photos-library` | người dùng tạo |
| Ảnh | id · lúc tạo · lúc thành mồ côi (rỗng khi còn bản sao) | danh tính; mọi lượt dọn neo vào đây |
| Bản sao | id bền · id ảnh · nguồn · loại · id PhotoKit **hoặc** đường dẫn tương đối + khoá chuẩn NFC gấp hoa-thường · kích thước · ngày sửa · file ghép cặp · dấu sidecar · online (nguồn) · **mất từ** (`v31-missingCopies`: lượt đọc trọn của nguồn đang online không thấy file; rỗng = còn) · **chỗ giữ chỗ cloud** (`v32-cloudPlaceholders`: chỉ liệt kê, không đọc, không hash, không dòng metadata) · ẩn · lần thấy cuối | kết quả quét |
| Hash | một dòng mỗi bản sao: thuật toán + phiên bản · hash nhanh · hash đầy đủ · lúc băm | kết quả quét đắt tiền |
| Bí danh | id thua → id thắng · lúc gộp | sau mỗi lần gộp |
| Recipe | id ảnh · recipe · lúc đổi | người dùng |
| Dấu ảnh file | id ảnh · sao, favorite, title, caption, mỗi trường kèm lúc đổi; keyword một dòng mỗi (ảnh, keyword) | người dùng |
| Dấu chờ sidecar | bản sao · id ảnh · lý do · lúc đặt | người dùng |
| Album ShotDex · thành viên | id · tên · vị trí · lúc tạo · (album, id ảnh) | người dùng |

- **Không khoá ngoại**: lượt quét cập nhật bản sao tại chỗ; một `REPLACE` kéo theo cascade là mất dữ liệu người dùng.
- Duy nhất: bản sao theo (nguồn, khoá đường dẫn) khi có đường dẫn; theo id PhotoKit khi có. Hash đầy đủ **có chỉ
  mục, không duy nhất** — hai bản sao cùng nội dung mang cùng hash; luật gộp giữ một id ảnh cho mỗi hash đầy đủ.
- Chỉ mục: bản sao theo (nguồn, id ảnh) và (id ảnh, online); ảnh theo lúc mồ côi (chỉ dòng có giá trị); hash
  theo (thuật toán, phiên bản, hash nhanh) và (…, hash đầy đủ).
- Migration điền Ảnh + Bản sao (loại Photos, id bản sao `photos:<id>`) từ **hợp mọi id ảnh** của mọi bảng ở §3 —
  kể cả ảnh chỉ có cờ dưới quyền `.limited`. Hai bảng cache ảnh trùng được dựng lại (rỗng) theo khoá mới.
- Lượt index ghi Ảnh + Bản sao Photos cùng dòng metadata (`INSERT OR IGNORE`, chỉ làm mới lần thấy cuối); ảnh bị
  xoá khỏi Photos mất **bản sao**, dòng Ảnh ở lại giữ dữ liệu người dùng (luật mồ côi 30 ngày, FS-19.05 §5).

## 4. Gỡ một tính năng thì phải dọn cả truy vấn đã lưu

Bất kỳ thay đổi nào **bỏ một trường điều kiện** đều phải viết lại phần truy vấn đã lưu của smart album.

**Bắt buộc, không phải dọn cho đẹp**: bộ giải mã không còn hiểu giá trị đó, mà khi dữ liệu hỏng thì nó rơi
về **một truy vấn rỗng** — và **truy vấn rỗng không có điều kiện nào nên khớp cả thư viện**. Tức là album
"ảnh tôi chọn" âm thầm biến thành "mọi ảnh".

Ngoài ra, danh sách điều kiện được giải mã **khoan dung**: một điều kiện không hiểu được thì **rơi ra**,
không giết cả album — để đỡ những album do một bản build chạy trước lần đổi lược đồ ghi ra. Có test riêng.

Tiền lệ: bảng chấm sao cũ được thêm (`v14`), rồi bỏ cờ (`v15`), rồi xoá hẳn (`v16`). Cả hai lần đều viết lại smart
album. Sao và cờ quay lại ở một migration mới với hai bảng mới, và mang lại tên trường cũ trong smart album.
Không vướng: `v15`/`v16` chạy xong trước khi có album nào dùng tên mới, cả ở máy cài mới lẫn máy đã có dữ liệu.
Migration cũ giữ nguyên — không sửa migration đã chạy.

## 5. Đánh đổi đã chọn

| Chọn | Thay vì | Vì |
|---|---|---|
| Bảng riêng cho dấu vân tay và kết quả quét | thêm cột vào bảng metadata chính | index lại sẽ xoá trắng, mà dựng lại thì tốn giải mã cả thư viện (có test khoá điều này) |
| Lưu sẵn tiêu cự tương đương | tính lúc truy vấn | biểu đồ tiêu cự chạy trên cả thư viện |
| GRDB | SwiftData | cần tổng hợp bằng SQL ([OV-02](../00-overview/OV-02-platform-and-technology.md)) |

## 6. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../README.md#6-việc-còn-nợ).
