# Intent: Đưa cả một folder NAS về Photos vào một album — ảnh, video, Live Photo, chạy nền, làm tiếp được

| Trường | Giá trị |
|---|---|
| Tác giả | Hoang Tuan (người dùng) · Claude soạn |
| Ngày | 2026-10-24 |
| Trạng thái | accepted (2026-10-25) |
| Tiến độ | **chưa làm** (2026-10-24) — chưa có spec |
| Nguồn | phản hồi người dùng (2026-10-24, bước 5 của kế hoạch "ảnh gia đình") |
| Spec sinh ra từ đây | (điền khi sang Design; có thể là bản sửa FS-17.02 / FS-19.03 §4) |

Đi cùng: [2026-10-24-smart-album-on-nas](2026-10-24-smart-album-on-nas.md) (bước 4 — xoá ảnh đã có trên NAS để giải
phóng iCloud). Intent này là bước 5: khi iCloud đã có chỗ, đưa ảnh từ `Shared/` trên NAS về Photos để người dùng chuyển
vào iCloud Shared Library.

## Problem — vấn đề

Người dùng muốn đưa toàn bộ folder `Shared/` trên NAS (hàng nghìn ảnh **và video**, hàng chục–trăm GB) về thư viện Photos
của một người, gom vào **một album**, rồi trong app Photos chọn hết album đó → **Move to Shared Library**. ShotDex không
tự chuyển vào Shared Library được (PhotoKit không có API, đã kiểm SDK iOS 27.1), nên album là cầu nối.

Hôm nay **Save to Photos** (FS-17.02, `ShotDex/Data/Sources/FileServer/PhotoKitAssetCreator.swift`) đã chọn được đích là
album có sẵn hoặc album mới, giữ cặp RAW+JPEG và ngày chụp. Nhưng không làm được việc này vì:

- **Không có video**: FS-17 README "Cố ý không có: video (v1 chỉ ảnh)"; lưới server ẩn video (FS-17.01 §2).
- **Live Photo bị tách**: `PhotoKitAssetCreator` chỉ thêm `.photo` / `.alternatePhoto`, không có `.pairedVideo` — HEIC +
  MOV của một Live Photo (đã được Backup FS-22 chép lên) về thành một ảnh tĩnh, còn video thì bị bỏ.
- **Chỉ chọn tay trong một folder**: không có lệnh lưu cả một folder kèm mọi folder con. `Shared/` xếp theo năm/tháng/ngày
  → hàng trăm folder.
- **Chỉ chạy khi mở app**: FS-17.02 §3 "app ra nền = huỷ", màn hình phải sáng. Hàng chục GB là hàng giờ; khoá máy hay
  chuyển app là đứt, và không lưu tiến độ để làm tiếp.
- **Đầy máy**: ảnh đã lưu vào Photos nằm trên máy cho tới khi Photos đẩy lên iCloud và Optimize Storage dọn bớt. Lưu 200 GB
  vào iPhone 256 GB một mạch sẽ làm đầy máy. Kiểm hiện tại chỉ là "ước tính + 1 GB > chỗ trống" lúc bắt đầu.
- Vị trí (GPS) trong file có được Photos đọc khi tạo asset từ file không — chưa kiểm.
- **Mất favorite và caption**: Backup (FS-22) chỉ chép file gốc; favorite và caption nằm trong thư viện Photos, không
  nằm trong file, nên ảnh đưa về là ảnh "trắng". PhotoKit đọc được favorite (`PHAsset.isFavorite`) ở mọi bản iOS; caption
  chỉ đọc/ghi được từ **iOS 27** (`PHAssetExtendedMetadata.caption`, `PHAssetChangeRequest.caption` — SDK 27.1).

## Proposed outcome — kết quả mong muốn

1. Trên màn duyệt server (FS-17), một folder có lệnh **Save Folder to Photos**: lấy mọi ảnh và video trong folder đó và
   mọi folder con.
2. Đích như hôm nay: album mới (mặc định tên folder, ví dụ "Shared") hoặc album có sẵn. Mọi mục lưu vào đều vào album đó.
3. Mỗi mục về Photos **đúng như lúc chụp**: một asset cho mỗi ảnh; Live Photo vẫn là Live Photo; RAW+JPEG vẫn là một ảnh
   có RAW; video giữ nguyên độ phân giải; ngày chụp, vị trí, tên file gốc giữ nguyên. Không nén, không đổi định dạng.
4. Mục đã có trong thư viện (cùng nội dung) thì bỏ qua, không tạo bản trùng.
5. Chạy được ở nền và khi mở lại app; **tiến độ được lưu** — bị iOS dừng, tắt app, mất Wi‑Fi thì lần sau làm tiếp, không
   lưu lại mục đã lưu. Người dùng thấy `Saving 1,204 of 8,930 · 48 of 212 GB` và lý do đang chờ, nếu có.
6. **Không làm đầy máy**: máy còn trống **< 5 GB** thì dừng và chờ (Photos đẩy lên iCloud, Optimize Storage dọn), tự chạy tiếp khi có
   chỗ, và nói rõ đang chờ gì.
7. **Favorite và caption đi theo ảnh**: Backup ghi một file **`.xmp` cạnh ảnh** trên NAS (`IMG_8812.xmp` cạnh
   `IMG_8812.HEIC`), đọc được bằng Lightroom và công cụ khác; đổi favorite/caption sau khi đã backup thì lượt Backup kế
   cập nhật file `.xmp` đó. Lưu về Photos thì đọc `.xmp` và đặt lại favorite + caption. Caption chỉ trên iOS 27+.
8. Xong: thông báo + nút mở album; câu hướng dẫn ngắn: trong Photos, mở album → Select → chọn hết → ⋯ → Move to Shared
   Library.

## Affected users and systems — phạm vi ảnh hưởng

- **Ai:** người muốn đưa một folder NAS lớn về Photos; trường hợp đầu tiên là người sẽ tạo iCloud Shared Library.
- **Thiết bị:** iPhone · iPad · Duo trong/ngoài (màn server FS-17 đã có ở cả ba). Mac: ngoài phạm vi.
- **Màn:** duyệt server (FS-17.01: menu folder, hiện video), sheet Save to Photos (FS-17.02), một chỗ xem tiến độ khi đã
  đóng sheet (chưa có — có thể Utilities hoặc giống Backup).
- **Backup (FS-22):** ghi và cập nhật sidecar `.xmp` (favorite, caption) cạnh file gốc; sổ Backup biết sidecar nào
  cần ghi lại khi favorite/caption đổi. Mac app (FS-19 D3) cũng dùng `.xmp` — cùng một cách ghi.
- **Tầng:** Domain (`ServerDownloadSession`: ghép Live Photo, lô cả folder, chờ chỗ trống), Data
  (`PhotoKitAssetCreator`: `.pairedVideo`, `.video`; `ServerDownloadStore`: lưu tiến độ lô), chạy nền (tái dùng
  `BackupBackgroundService` / iOS 26 continued task của FS-22).
- **Dữ liệu đã lưu:** thêm bảng/cột cho lô lưu dài hạn (migration mới). Lịch sử tải về FS-17 §4 giữ nguyên. App chưa
  release — không cần tương thích ngược.

## Constraints — ràng buộc

- Không chuyển ảnh vào iCloud Shared Library từ ShotDex — PhotoKit không cho; người dùng tự làm trong Photos từ album.
- Không tạo bản trùng trong thư viện; không bao giờ ghi đè hay xoá asset có sẵn.
- Không sửa, dời, xoá file ảnh trên NAS (FS-17 README: không xoá/đổi tên/chuyển file trên server). Ngoại lệ duy nhất:
  Backup ghi đè sidecar `.xmp` của chính nó — đó là file của ShotDex, không phải ảnh.
- Script của người dùng dời/gộp file phải dời `.xmp` đi kèm ảnh; ShotDex không bù được nếu script bỏ sót.
- Minimum iOS 17: caption chỉ trên iOS 27+, nhánh `#available` — dưới 27 chỉ có favorite.
- Một file tạm một lúc, xoá ngay sau khi lưu; kiểm SHA-256 / cỡ trước khi lưu như FS-17.02 §2.
- Không làm đầy máy (luật người dùng 2026-10-12 cho Backup, áp cho cả việc lưu vào Photos).
- Tôn trọng Only on Wi‑Fi như Backup; không thêm dependency; dữ liệu không rời mạng nhà.
- Quyền `.limited`: không thêm vào album được (FS-17.02 §1) — phải nói rõ, vì album là mục đích của lệnh này.
- Không test bằng ảnh có mặt người.

Quyết định của người dùng (2026-10-25, trả lời Open questions):
- Dừng chờ khi máy còn trống **< 5 GB**.
- **Không chia lô**, lưu hết folder vào một album; iCloud đầy thì Photos tự ngừng đẩy lên, ảnh nằm lại trên máy.
- **Giữ favorite + caption** qua sidecar `.xmp` cạnh ảnh, cập nhật khi đổi.
- **Không chặn** hai người cùng lưu `Shared/` về — chỉ ghi trong câu hướng dẫn; album cũ, bản sửa Photos: không giữ.

## Open questions — câu hỏi còn treo

Q1, Q2, Q7, Q8 đã trả lời 2026-10-25 (xem Constraints). Còn — spec / spike trên máy thật trả lời, không cần người dùng:

_Người dùng 2026-10-25: câu cần thử trên máy thật thành **spike trong `/spec`** (đo trước, chốt AC sau); câu "spec" do `/spec` quyết._

| # | Câu hỏi | Ai trả lời | Đề xuất mặc định |
|---|---|---|---|
| Q3 | "Đã có trong thư viện" so bằng gì: lịch sử tải về/upload FS-15/FS-17 (biết SHA), hay cả kết quả kiểm "On Server" của intent smart-album-on-nas? | spec | dùng cả hai — ảnh gốc vẫn còn trên máy thì không lưu thêm |
| Q4 | Ghép Live Photo bằng gì: cùng tên gốc (`IMG_8812.HEIC` + `IMG_8812.MOV`, cách Backup đặt tên — FS-22.01 §5), hay đọc content identifier trong file? Photos có từ chối cặp không khớp identifier không? | spike trên máy thật | tên gốc để tìm cặp, content identifier để xác nhận; không khớp thì lưu riêng và ghi lý do |
| Q5 | Photos có tự đọc GPS / múi giờ trong file khi tạo asset từ file không, hay phải đặt `location` tay? | spike | đo; thiếu thì đặt `location` từ EXIF |
| Q6 | Ghi vào Photos từ tác vụ nền có được không (BG processing / iOS 26 continued task)? | spike trên máy thật | giả định được; nếu không, nền chỉ tải file về chờ, ghi khi mở app |
| Q9 | Favorite ghi vào `.xmp` bằng trường nào (Photos không có chuẩn XMP cho favorite; Lightroom dùng `xmp:Rating`, iOS 27 có `PHAssetRating`)? Caption → `dc:description`? | spec | favorite → `xmp:Rating` = 5 + một trường riêng của ShotDex; caption → `dc:description` |

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
