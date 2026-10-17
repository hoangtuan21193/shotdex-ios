# FS-03.07b — Xuất ra folder (Files, ổ ngoài)

`FS-03.07b` · tier A (sheet Export) · `Data/Sources/CompressionPresetStore.swift` · `Data/Sources/ShareExportPipeline.swift`
· `Data/Sources/OriginalPreparation.swift` · `Data/Sources/FileServer/FilesFolderClient.swift` · `Domain/ServerUpload/ServerUploadPath.swift`
· test `ShotDexTests/FileExport*Tests.swift` · cập nhật 2026-10-05

Nguồn intent: [2026-09-30-user-wishes-research](../../_intents/2026-09-30-user-wishes-research.md) mục 4.
Chạy mẻ, tiến độ, đường hỏng, tiêu chí nghiệm thu, rủi ro: [07c](07c-export-acceptance-criteria.md). Preset dùng chung: [07](07-resize-and-compression.md) §3.

**Một câu:** chọn ảnh → **Export…** → ghi ra một folder bất kỳ trong Files (On My iPhone, iCloud Drive, Dropbox, SSD
cắm cáp) hoặc một server đã lưu, với preset Resize sẵn có, tên file theo mẫu, nhớ folder lần trước; sheet xuất server
dùng cùng preset.

## 1. Người dùng cần gì

Sau buổi chụp, người chụp muốn đổ 300 ảnh 2048px cho khách vào SSD, hoặc chép RAW gốc ra ổ lưu trữ, tên theo ngày
và máy. Hôm nay Resize chỉ lưu ngược vào Photos; Share → Save to Files không có preset, không đặt tên, gom cả mẻ
ra thư mục tạm trước (500 ảnh là gấp đôi dung lượng), và hỏi trùng tên từng file. Họ cần một lệnh làm trọn việc đó.

## 2. Phạm vi

**Có:** chế độ chọn của Library, album, smart album, On This Day · Photo Detail · ảnh tĩnh, RAW, cặp RAW+JPEG, Live
Photo, video · folder bất kỳ trình chọn folder của hệ thống cho chọn · connection server đã lưu làm đích của Export (§7) · preset
Size của Resize ở sheet xuất server (§8).

**Cố ý không có:**
- Nút Export trong editor — vì Save Changes đã đưa bản sửa vào ảnh; Export từ viewer xuất bản đó.
- Chuyển mã video (đổi cỡ, đổi codec) — vì là cả một pipeline AVFoundation; video luôn đi nguyên file.
- Xuất từ Collage, Video Studio, Panorama ra Files — các công cụ đó lưu vào Photos; xuất từ ảnh kết quả.
- Đồng bộ, xuất tự động theo lịch — vì không chạy nền được quá vài chục giây (FS-15 §2).
- Chạy tiếp khi app ra nền — như Upload: ra nền là dừng, quay lại có **Export Remaining**.
- Bản chuyển đổi trong sheet Upload — Upload chỉ chép bản gốc (§7).

## 3. Sheet Export

Lối vào: ⋯ của chế độ chọn và ⋯ của Photo Detail, dòng **Export…** ngay dưới Resize, glyph `square.and.arrow.up.on.square`.
Sheet là **một Form**: iPhone detent large 402pt; iPad canh giữa, rộng tối đa 700pt như Resize; hàng 44pt
([07c](07c-export-acceptance-criteria.md) §1 mục 1–2).

| Section | Hàng | Luật |
|---|---|---|
| Destination | **Folder** | tên folder + vị trí (`T7 › Exports`); chạm → menu: tối đa 5 folder gần đây, các connection server đã lưu (§7), rồi **Choose Folder…** (trình chọn của hệ thống) |
| | **Date Folders** | công tắc; bật thì ghi vào `năm/năm-tháng-ngày` theo ngày chụp, cùng luật FS-15.02 §3 |
| Export | **Export As** | segmented **Current Version** · **Unmodified Original** (chữ của Photos) |
| | Version | chỉ khi có ảnh đã chỉnh, chỉ ở Current Version: **Edited** (mặc định) · **Original** |
| | **Size** | chỉ ở Current Version: danh sách preset của Resize, kể cả preset tự tạo; đầu danh sách là **Original**, mặc định lần đầu (không phải 2048 px) |
| | **Format** | chỉ ở Current Version: **Same as Original** (mặc định) · **JPEG** · **HEIC**, như màn Resize |
| | **Color Space** | chỉ ở Current Version: **Original** (mặc định) · **sRGB** · **Display P3** · **Adobe RGB** (§3a) |
| | **Quality** | chỉ ở Current Version: slider 10–100%, bước 1%, mặc định 80%, giá trị `80%` bên phải (§3a) |
| | Metadata | chỉ ở Current Version: 3 mức của FS-08.06, mặc định lấy từ Settings |
| | Live Photo Video | chỉ ở Unmodified Original: công tắc, mặc định bật |
| File Names | **Name** | tên mẫu đang dùng, dòng phụ là ví dụ; chạm đẩy màn **File Name** (§5) |
| | **If a File Exists** | **Keep Both** (mặc định) · **Replace** · **Skip** (§6) |
| Tóm tắt | footer | `48 photos · 3 videos · ~1.2 GB` và `412 GB free on T7`; Current Version thêm *Videos are exported as they are.* |

- Toolbar: **Cancel** trái, **Export** phải; Export mờ khi chưa có folder, folder không mở được, hoặc mẫu tên rỗng.
- **Nhớ sang lần sau:** folder và danh sách gần đây, Date Folders, Export As, preset, Format, Color Space, Quality,
  mẫu tên, If a File Exists, Live Photo Video. **Không nhớ:** Metadata (luôn từ Settings, FS-08.06 §4) và Version.
  Khác Resize (không nhớ gì) vì xuất ra cùng một ổ là việc lặp lại sau mỗi buổi chụp.
- Unmodified Original chép **nguyên byte**; footer ghi *"Original files are copied as they are, with all their
  metadata. Edits aren't included."* Không có hàng Metadata: đây là bản lưu trữ, như Upload (07c §1 mục 6).
- Bản Current Version: mỗi ảnh render một lần ở cỡ preset, như Resize ([07](07-resize-and-compression.md) §3–4).
  **Same as Original**: HEIC ra HEIC, JPEG ra JPEG, mọi thứ khác (RAW, PNG, TIFF) ra JPEG.
  Preset Fill dùng crop giữa cho mọi ảnh, như Resize cả mẻ.
- Live Photo ở Current Version ra **ảnh tĩnh**, như Resize và Share.

### 3a. Size, Color Space, Quality (người dùng chốt 2026-10-05)

- **Size mặc định Original.** Lần đầu mở sheet (chưa nhớ gì), hàng Size ghi `Original`; sau đó là preset lần trước.
  Preset đã nhớ bị xoá trong Settings → Resize Presets thì về Original. Khác Resize (mặc định 2048 px): Export là
  bản giao đầy đủ, ai cần nhỏ thì chọn. Mọi board sheet Export vẽ `Original` ở hàng Size.
- **Color Space** — bốn lựa chọn, cùng tên với popup của bản Mac ([FS-18 §4](../FS-18-mac-app/03-editor-and-export.md), D17):

  | Lựa chọn | File ra |
  |---|---|
  | **Original** (mặc định) | giữ profile của ảnh như renderer làm hôm nay ([FS-03.04 §2](04-raw-and-render-graph.md)): Display P3 hay Adobe RGB khi file nguồn ghi vậy, RAW ra Display P3, mọi profile khác ra sRGB |
  | **sRGB** | điểm ảnh đổi sang sRGB, file mang profile `sRGB IEC61966-2.1` |
  | **Display P3** | đổi sang Display P3, profile `Display P3` |
  | **Adobe RGB** | đổi sang Adobe RGB (1998), profile `Adobe RGB (1998)` |

  - Bốn lựa chọn là bốn profile bộ ghi ImageIO của app ghi được cho **cả JPEG lẫn HEIC** (đo 2026-10-05: ghi rồi
    đọc lại, profile và không gian màu của ảnh giải ra đúng cả 6 tổ hợp). Không có ProPhoto RGB, không có
    "Display" của máy: file 8 bit ở profile rộng hơn Adobe RGB thì dải màu vỡ.
  - Đổi profile là đổi điểm ảnh, không chỉ gắn nhãn: cùng một màu trong gamut, đọc lại qua profile của file, lệch ≤ 2 mức
    (8 bit) giữa các lựa chọn, trừ màu nằm ngoài gamut đích (bị cắt về mép gamut — vì vậy mặc định là Original).
  - Đổi sau mọi chỉnh sửa và **trước** dấu watermark: dấu được vẽ trong profile đích như mọi điểm ảnh khác.
  - Preset tự tạo không mang color space (Resize Presets không có hàng này): chọn preset không đổi Color Space.
  - Resize, Share và sheet xuất ảnh server **không** có hàng này; chúng giữ profile gốc như cũ.
- **Quality** dùng đúng dải, bước và mặc định của Resize và Settings → Resize Presets: 10–100%, bước 1%,
  mặc định 80%. Chọn preset tự tạo thì Quality lấy **đúng** chất lượng của preset (`85%` ra `85%`, không làm tròn
  về bước 10). Kéo slider không đổi preset.
  - Quality chỉ có nghĩa với định dạng nén mất dữ liệu. Mọi Format của sheet đều nén mất dữ liệu (JPEG, HEIC; Same
    as Original đổi RAW, PNG, TIFF sang JPEG), nên hàng hiện **mỗi khi** Current Version hiện và ẩn cùng các hàng
    render ở Unmodified Original. Sau này có định dạng không mất dữ liệu thì hàng ẩn với định dạng đó.
- **Thứ tự và hình:** Size · Format · Color Space · Quality ngay dưới Version, trước Metadata, mọi thiết bị.
  Color Space là hàng menu như Format (`Original ⌃⌄`); Quality là hàng slider: nhãn, slider, giá trị. iPhone, Duo
  ngoài: hàng Form; iPad, Duo trong: hàng 44pt của thẻ (board `IPP19_Export`).

## 4. Folder và quyền truy cập

- Folder chọn qua trình chọn folder của hệ thống, lưu bằng **bookmark** có phạm vi bảo mật, nên lần sau ghi vào mà
  không mở lại trình chọn. Bookmark báo cũ thì app tạo lại ngay khi mở được.
- Cùng cách làm với folder cloud của [FS-17.05](../FS-17-import-from-server/05-cloud-folders.md) §2: ghi qua điều phối
  file của hệ thống, nên Dropbox, iCloud Drive tự nhận file mới.
- Ổ ngoài đang rút: hàng Folder ghi `T7 › Exports — Not connected` (mờ); footer *"Connect “T7” or choose another
  folder."*; Export mờ. Cắm lại thì hàng sáng lại, không phải chọn lại.
- Bookmark không còn mở được (folder bị xoá, ổ bị format) → *"ShotDex can't open this folder anymore. Choose it
  again."*, folder rơi khỏi danh sách gần đây. Cùng câu với FS-17.05.

## 5. Mẫu tên file

| Token | Ra | Khi thiếu |
|---|---|---|
| `{original}` | tên gốc không đuôi: `DSCF1000` | không bao giờ thiếu |
| `{originalNumber}` | chữ số cuối tên gốc: `IMG_6123` → `6123`, `DSCF0042` → `0042` | bỏ token khi tên không tận cùng bằng số |
| `{date}` · `{time}` | ngày chụp `2026-09-20` · giờ `170512`, theo giờ máy | rơi về ngày tạo asset |
| `{camera}` · `{lens}` | model như chip lọc: `X-T5`, `EOS R6 Mark II` · lens như chip lọc | bỏ token (dưới bảng) |
| `{sequence}` | số thứ tự trong mẻ, đệm 3 chữ số (`001`); mẻ ≥ 1000 ảnh thì 4 | không bao giờ thiếu |

- Mặc định `{original}`. Mẫu dựng sẵn: *Original Name* `{original}` · *Date + Camera + Sequence* `{date}_{camera}_{sequence}`
  · *Date + Original Name* `{date}_{original}`. Mẫu tự gõ được nhớ (§3).
- **Màn File Name** (đẩy từ hàng Name, có Back):
  - section mẫu dựng sẵn: 3 hàng, dấu ✓ ở mẫu đang dùng;
  - section **Custom**: ô chữ 44pt, lưới 8 chip, 3 một hàng (Original Name · Original Number · Date · Time · Camera · Lens ·
    Sequence · Text, cao 32pt; chữ dài xuống hai dòng) — **cùng một danh sách với inspector nhập thẻ** (FS-20 AC-25,
    `FileNameChip.all`). Chip **Text** không phải token: thêm `_Text` (bỏ `_` khi mẫu trống hoặc đã tận cùng bằng dấu
    nối), chữ `Text` được bôi chọn để gõ đè (iOS 18 trở lên; iOS 17 chỉ thêm), dòng ví dụ. Gõ vào Custom thì ✓ chuyển sang Custom.
- Dòng ví dụ dùng **ảnh đầu tiên của mẻ**: `2026-09-20_X-T5_001.jpg`, đổi ngay khi gõ.
- Token thiếu giá trị thì bị bỏ, kéo theo dấu nối thừa: `{date}_{camera}_{sequence}` của ảnh chụp màn hình ra
  `2026-09-21_003.jpg`, không ra `2026-09-21__003.jpg`.
- `{sequence}` đánh theo **ảnh**, không theo file; thứ tự theo ngày chụp rồi tên gốc. Cặp RAW+JPEG và Live Photo dùng chung một
  tên, khác đuôi: `2026-09-20_X-T5_001.RAF` + `.JPG`.
- Ký tự ổ exFAT/FAT không nhận (`" * / : < > ? \ |`, ký tự điều khiển) thành `-`; bỏ `.` ở đầu; tên dài quá 200
  ký tự thì cắt. Vì SSD thường format exFAT, một luật cho mọi đích.
- Đuôi: Current Version dùng `jpg`/`heic` chữ thường; Unmodified Original giữ đuôi của file gốc như nó vốn có.

## 6. Ghi một file và trùng tên

1. Đọc danh sách tên trong folder đích **một lần** trước khi ghi, so **không phân biệt hoa thường** (APFS và exFAT
   mặc định như vậy).
2. Ghi dưới tên tạm `<tên>.shotdex-part`, rồi đổi sang tên thật khi file đã đủ byte và mở được. Như FS-15.02 §4:
   không tên thật nào trỏ tới một file ghi dở. Không đọc lại SHA-256 — đích là đĩa của máy, không phải mạng.
3. **Keep Both** thêm ` (2)`, ` (3)`… như FS-15.02 §5. Hai ảnh **trong cùng mẻ** ra cùng tên (`IMG_0001` của hai
   máy) luôn được đánh số, ở cả Replace — một lượt không bao giờ ghi đè file chính nó vừa ghi.
4. **Replace**: có ≥ 1 tên trùng thì hỏi một lần trước byte đầu: *"Replace 12 files in “Exports”?"* · **Replace**
   (đỏ) · Cancel. Ghi xong file mới mới xoá file cũ.
5. **Skip**: bỏ ảnh trùng, tổng kết ghi *"12 skipped — already in the folder"*.

## 7. Export lên server đã lưu

Sheet Upload **không đổi**: nó chỉ chép bản gốc. Bản chuyển đổi lên server đi qua sheet Export: hàng Folder liệt kê
thêm các connection đã lưu (SMB, SFTP, WebDAV, folder cloud) — chọn một cái thì duyệt folder như FS-15.02 §2a.

- Ghi lên server đi đúng khuôn FS-15.02 §4: tên tạm, đọc lại SHA-256, đổi tên thật.
- Bản đã chuyển đổi **không** ghi dòng lịch sử upload: lịch sử là bằng chứng bản gốc đã an toàn, nó quyết định dấu
  trên lưới và lời mời xoá (FS-15.02 §7). Bản 2048px trên NAS không được làm ảnh gốc trông như đã sao lưu.

## 8. Sheet xuất server (FS-17.06) dùng preset

- Hàng **Size** hiện ở **mọi** lần xuất không gộp (Edit, Paste Edits, Resize), không chỉ Resize; danh sách là preset
  của Resize **kể cả preset tự tạo**, đầu danh sách là preset Original (mặc định, trừ Resize mặc định 2048 px).
  Code hôm nay chỉ có Size ở Resize, chỉ cỡ dựng sẵn, mặc định 4K — **sửa code theo dòng này** (người dùng chốt
  2026-10-03).
- **Other Folder…** thêm dòng đầu **Folder in Files…**: trình chọn của hệ thống, cùng bookmark và danh sách gần đây của §4.
- Tên `<tên gốc>_edited` của FS-17.06 §6 giữ nguyên (người dùng chốt 2026-09-29); mẫu tên chỉ có ở sheet Export.

## 9. Dữ liệu và ràng buộc

| Mặt | Ràng buộc |
|---|---|
| Lưu ở đâu | bookmark folder, danh sách gần đây (≤ 5), mẫu tên, lựa chọn của sheet: trong cài đặt của app. **Không** đụng database ([BD-02](../../01-basic-design/BD-02-database-design.md)) |
| Bộ nhớ | một ảnh render mỗi lúc, như Resize; file gốc chép theo khối ≤ 1 MB. Đỉnh RAM không tăng theo số ảnh ([NF-02](../../04-non-functional-design/NF-02-memory-and-resources.md)) |
| Đĩa | Current Version render **thẳng** vào tên tạm ở folder đích, không qua bản sao trên máy; đích là server thì render ra một file tạm mỗi lần, như FS-15 §5. Thư mục tạm còn chứa bản gốc iCloud (07c §1 mục 5) |
| Chỗ trống | kiểm trước byte đầu: Unmodified Original = tổng dung lượng gốc; Current Version = dung lượng gốc × tỉ lệ pixel của preset. Đích không báo chỗ trống (một số dịch vụ cloud) thì bỏ qua bước này |
| Thiết bị | iPhone 402×874 · iPad 1376×1032 · Duo trong 951×669 · Duo ngoài 466×678: sheet trong 382pt trước dải 84pt |
| iOS 26 vs trước | cùng hàng, cùng chữ ở hai nhánh; menu ⋯ giống nhau |
| Truy cập | chip token có nhãn *"Insert Date"*…; VoiceOver đọc dòng ví dụ và phần trăm tiến độ |
| Chữ | nhãn trong String Catalog; tên preset trùng tên ở Resize và Settings → Resize Presets |

**Design canvas:** không board cũ nào đổi. Board mới nằm trên canvas từng thiết bị ([design/README](../../design/README.md)),
nối vào hàng từng thiết bị (2026-10-05: mọi board sheet Export vẽ Size `Original` và hai hàng Color Space, Quality của §3a): sheet Export
`PH33`/`IP23`/`IPP19`/`DI18`/`DIP18`/`DC19` `_Export`, màn File Name `PH34`/`IP24`/`IPP20`/`DI19`/`DIP19`/`DC20`
`_FileName`, sheet đang chạy `PH35_ExportRunning`, tổng kết `PH36_ExportSummary` (hai board sau chỉ ở hàng iPhone).
