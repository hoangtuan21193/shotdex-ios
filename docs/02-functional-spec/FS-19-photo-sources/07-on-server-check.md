# FS-19.07 — Ảnh Photos đã có trên server chưa

`FS-19.07` · tier B (smart album, lưới, Photo Info) · mã có sẵn: `Data/Sources/PhotosContentHashPass.swift`,
`Data/Sources/FileServer/ServerSourceIndexer.swift`, `Data/Database/SmartAlbumSQLBuilder.swift`,
`Data/Sources/Folders/DeletionService.swift` · AC + spike: [07b](07b-on-server-check-ac.md) · cập nhật 2026-11-06 (§7 Also on Server; §12 băm dùng chung)

**Một câu:** ShotDex biết chắc từng ảnh/video trong Photos có bản **giống hệt từng byte** trên một folder của nguồn
server hay chưa — kể cả file do công cụ khác chép, hay bị script dời, đổi tên — và kiểm lại NAS trước khi xoá.

Nguồn: [intent 2026-10-24-smart-album-on-nas](../../_intents/2026-10-24-smart-album-on-nas.md) · người dùng 2026-10-25:
dựa trên nguồn FS-19 · Folder trong điều kiện · một dấu lưới · N1, N2 · sau phản biện: SHA-256 cả file, lọc theo cỡ,
ảnh đã sửa cần bản sửa trên NAS, hai đợt, có *Delete Anyway* khi NAS tắt.

## 1. Người dùng cần gì

- iCloud đầy; bản gốc nằm trên NAS — do Backup FS-22, do script gộp của người dùng, hay chép bằng công cụ khác.
- Cần album "ảnh trên máy này đã có trên `NAS › iCloud Photo/Shared`" để xoá khỏi Photos mà không mất gì.
- Hàng chục nghìn mục: kiểm phải tự chạy, dừng ở đâu làm tiếp ở đó, và tải từ iCloud càng ít càng tốt.

## 2. Phạm vi và hai đợt

| Đợt | Có |
|---|---|
| 1 — xoá được an toàn | hash theo từng file gốc · lấy lại SHA của Backup · lọc theo cỡ · kiểm khi app ở trước mặt · Folder trong điều kiện (Source tới 2026-11-06, nay Also on Server) · chưa kiểm · dòng tiến độ · cổng xoá ở smart album, Free Up Space, Library |
| 2 — sau khi đo S3 | chạy nền · ghép Live Photo trên nguồn thư mục/server (ảnh + MOV cùng tên gốc trong một folder là một Live Photo) · dấu lưới theo hiện trạng · Photo Info On Server · cổng xoá ở mọi lối còn lại · gộp Photos ↔ server để hiển thị |

**Cố ý không có:**
- Tìm/gộp ảnh trùng, dời hay xoá file trên NAS — *vì* script của người dùng làm (intent).
- Bản cùng điểm ảnh nhưng metadata khác (app khác nhúng XMP), bản nén lại — **không** tính là có. *Vì* cỡ khác nên không
  lọc được, bắt nó phải tải cả thư viện; và xoá theo nó có thể mất ngày chụp, GPS. Duplicates FS-06.06 lo phần giống hình.
- File hash do script ghi sẵn trên NAS — để sau; đợt 1 ShotDex tự đọc ứng viên.
- Đưa ảnh từ NAS về Photos — intent `2026-10-24-restore-from-nas-to-album`.

## 3. Khớp

- **Hash:** SHA-256 của **cả file**, cho từng file gốc — cùng loại hash Backup đã ghi. Khác một byte là khác.
- Một mục Photos **có trên folder F của nguồn S** khi mỗi file sau có một file trong F (mọi tầng con) cùng SHA-256:
  ảnh · RAW của RAW+JPEG · video đi kèm Live Photo · video · và, nếu mục **đã sửa** trong Photos, **bản sửa** (ảnh, video).
- Mục đã sửa mà bản sửa chưa có trên NAS → **không** có trên F; tiến độ và hộp xoá gọi tên: *"Edited — edit not on NAS
  Home"*. Bản sửa lên NAS khi job Backup bật **Include Edited Versions** (FS-22.01 §2).
- Kiểm **không phụ thuộc** việc gộp ảnh của FS-19 (§02): đọc thẳng bảng hash theo file. Gộp chỉ để hiển thị (đợt 2), và
  không bao giờ ghi sidecar lên NAS vì một lần kiểm.
- Gộp (đợt 2, `OnServerMergePass`, chạy cuối mỗi lượt kiểm): ảnh server chỉ có bản server, mà mọi file của nó cùng SHA-256
  với một file của một mục Photos, được gộp vào mục Photos đó — **id của Photos luôn thắng** (`PhotoMergePlan.merge
  keeping:`), vì mọi thứ phía Photos theo id đó. Gộp không tạo dòng `pending_sidecar`. Khớp một phần (ảnh có, video Live
  Photo khác) thì không gộp. Xoá ảnh đã gộp: bản đầu là Photos nên chạy đường xoá Photos qua cổng, bản NAS ở lại.

## 4. Hash phía Photos

- **Đã có từ Backup:** sổ Backup có SHA-256 từng file gốc nó đã chép, theo dấu nguồn. Dấu nguồn còn khớp → dùng luôn,
  không tải. Đây là phần lớn thư viện của người dùng có Backup.
- **Chưa có:** cỡ từng file gốc lấy từ Photos không cần tải. Chỉ mục có **ít nhất một file trên NAS cùng cỡ** mới được tải
  bản gốc để băm; mục không có ứng viên nào thì đã biết là *không có*, không tải. Photos không báo cỡ một file (hiếm) →
  file đó là ứng viên khi nguồn server có file nào đó.
- Tải: thư mục tạm, **một file một lúc**, băm theo khối 1 MB, xoá ngay; không giữ cả file trong RAM; video đọc luồng.
- Còn trống − cỡ file < 2 GB → chờ, `Waiting for space` (luật FS-22).
- Mỗi file băm xong ghi ngay → bị dừng ở đâu làm tiếp ở file kế. Thứ tự liệt kê: **mục vào thư viện gần nhất trước** — theo lúc ShotDex index mục đó (`indexedAt`), rồi ngày chụp mới nhất
  (đổi 2026-11-02: theo ngày chụp thì ảnh vừa nhập mà ngày chụp cũ nằm cuối hàng đợi 55k mục, lượt đầu ~55 phút). Đọc hỏng → ghi lỗi, đi tiếp, lượt sau
  mới thử lại — mục hỏng không chặn hàng.
- `.limited`: chỉ mục được cấp; dòng tiến độ thêm "Only photos ShotDex can access are checked."

## 5. Hash phía server

- Liệt kê cây (tên, cỡ, ngày sửa): **mỗi lần app về trước mặt**, khi server về lại, khi bấm Rescan; một lượt đang chạy thì
  không mở lượt mới.
  Mạng hoặc nguồn điện đổi trong lúc app ở trước mặt (Wi‑Fi tới, server về) → một lượt mới nếu chưa có lượt nào chạy.
  Danh sách tìm thấy ảnh mới thì Library tải lại (`SourcesModel.serverListingChanged`).
- **Ứng viên** = file có cỡ bằng cỡ một file gốc Photos chưa khớp. Chỉ ứng viên được đọc trọn (tải ra file tạm rồi băm).
  Kết quả nhớ theo đường dẫn + cỡ + ngày sửa; file dời/đổi tên nối bằng hash nhanh + cỡ, không băm lại.
- **Backup ghi sẵn:** Backup đẩy file vào folder nằm trong nguồn → lượt quét nguồn lấy SHA-256 trong sổ Backup (bản đã
  đẩy và đọc lại) và sổ chung `.shotdex` (file của máy khác) cho file cùng đường dẫn + cỡ, không đọc file. Ảnh vừa
  backup có trên F ngay, không đọc lại NAS.
- Mỗi connection **một lệnh một lúc**, dùng chung với Backup và Upload; Backup đi trước; kiểm nhả khoá giữa các file và
  không giữ khoá trong lúc tải iCloud.

## 6. Khi nào chạy

| Việc | Điều kiện |
|---|---|
| Liệt kê, băm phía server; tải iCloud để băm | job Backup của connection: Only on Wi‑Fi / Only While Charging, nhiều job thì **khắt nhất**; không có job → chỉ Wi‑Fi. **Use Cellular Data for Indexing** chỉ còn cho index Photos |
| Đợt 1 | khi app ở trước mặt; về trước mặt thì chạy tiếp |
| Đợt 2 | thêm tác vụ nền riêng `com.hoangtuan.shotdex.onserver` (`OnServerBackgroundService`, BGProcessingTask: luôn cần mạng, cần sạc khi một job Backup của connection bật Only While Charging), xin mỗi lần app rời màn hình còn việc; hết hạn thì dừng giữa hai đợt. Tác vụ tiếp tục iOS 26 chưa dùng — chờ S3 |

Mã: `Domain/OnServer/OnServerSchedule.swift` (cổng), `Data/Sources/OnServerCheck.swift` (một lượt: liệt kê từng nguồn mở
cổng → từng vòng băm server rồi Photos tới khi một vòng không làm gì; cả lượt dùng một mốc giờ nên file hỏng chờ lượt
sau). Tải iCloud theo cổng khắt nhất của mọi connection có nguồn server. App xuống nền → dừng giữa hai đợt, lý do
`Open ShotDex to continue`.

## 7. Smart album — điều kiện **Also on Server** (đổi 2026-11-06)

Người dùng 2026-11-06 ([intent also-on-nas-condition](../../_intents/2026-11-06-also-on-nas-condition.md)): đặt trong
**Source** thì `Source is NAS Home` đọc như "hiện ảnh nằm trên NAS", trong khi album là ảnh **trong Photos** có bản giống
hệt trên NAS. Tách ra thành trường riêng; Source thôi nhận nguồn server.

- **Trường** `Also on Server` (bộ dựng dùng chung: smart album, Advanced Search, điều kiện thẻ Statistics — FS-06.08 §2).
  Chỉ hiện trong menu trường khi có ít nhất một nguồn server (FS-19.03).
- **Dòng điều kiện** (tier B, hàng chuẩn của bộ dựng): menu trường → dải chọn **Yes / No** (như Favorite) → menu
  **Server** (tên các nguồn server; một nguồn thì chọn sẵn) → dòng **Folder** — trống = cả nguồn (`All Folders`), chọn
  bằng màn duyệt folder FS-15.02 §2a, mở ở folder đang chọn; folder ngoài gốc của nguồn bị bỏ qua. Đổi server thì xoá
  Folder. Chưa chọn server → điều kiện chưa đủ, bị bỏ qua khi biên dịch (FS-06.08 §1).
- **Chip chỉ đọc** (smart album, Advanced Search của Library, thẻ Statistics): Yes → `Also on NAS Home › Shared`, No →
  `Not on NAS Home › Shared`; cả nguồn → `Also on NAS Home`. VoiceOver đọc như chữ.
  Người dùng chốt 2026-11-06: ghi tên server, không ghi tên trường.
- **Yes**: có trên folder theo §3. **No**: đã kiểm xong và thiếu ít nhất một file.
- **Chưa kiểm xong** (một file gốc chưa có hash mà NAS có ứng viên cùng cỡ chưa băm): không vào **Yes** lẫn **No**.
- Chỉ mục **có bản Photos** được đếm: ảnh riêng của NAS (dòng của nó trong Library) không vào album — album là danh sách
  mục xoá được khỏi Photos. Mục đã đổi trong Photos sau lần liệt kê file cuối thì chờ liệt kê lại, không vào **Yes** lẫn
  **No**. Mã hôm nay: `OnServerPresenceSQL.swift`, gọi từ `SmartAlbumSQLBuilder.sourceClause` — tách ra mệnh đề riêng.
- **Source** chỉ còn Photos Library và nguồn thư mục/ổ đĩa (nghĩa FS-19.04 §5: có bản ở đó, đang có, không ẩn). Rule
  `Source is <server>` đã lưu:
  Người dùng chốt 2026-11-06: khi giải mã, rule Source trỏ tới nguồn server **đổi thành Also on Server** cùng server,
  folder, *is* → Yes, *is not* → No — album ra đúng tập cũ. Đây là độ bền khi giải mã, không phải migration dữ liệu.
  Không đổi được (server đã gỡ) thì rule rơi ra, và album **còn 0 điều kiện vì thế** hiện *No Photos Match* + nút Edit
  Smart Album thay vì khớp cả thư viện — album "để xoá" không được nở ra.
- **Popup Source của màn** (Statistics trên Mac, FS-18.04 §2) không phải bộ dựng điều kiện — giữ nguyên, vẫn có server.
- Thanh điều kiện: `Checking · 12,408 of 54,920 · 38 GB to download`; lý do chờ (`Waiting for Wi‑Fi`, `Waiting for space`,
  `NAS Home isn't reachable`, `Open ShotDex to continue` ở đợt 1); xong thì `Checked 3 min ago`.
  Dòng thêm: `3 Edited — edit not on NAS Home` khi có mục chỉ thiếu bản sửa; `Only photos ShotDex can access are
  checked.` khi quyền `.limited`; `Waiting to Charge` khi job bật Only While Charging. Tính cho điều kiện **Also on
  Server** đầu tiên của album, đọc lại sau mỗi đợt băm (album tải lại theo). Mã: `OnServerProgressQueries`,
  `OnServerProgressLine`.
- **Mọi thiết bị cùng lượt**, gồm Mac: rule model dùng chung (`SmartAlbumRule`), bỏ server khỏi Source mà không đổi
  `MAC_SmartAlbumEditor` thì Mac mất điều kiện. Board phải vẽ lại trước khi code: `PH_SmartAlbumEditor`,
  `DI_SmartAlbumEditor`, `DC_SmartAlbumEditor`, `IP_SmartAlbumEditor`, `MAC_SmartAlbumEditor` và chip trên
  `PH_/DI_/DC_/IP_/MAC_SmartAlbum` (hôm nay vẽ `Source, NAS Home` + `Folder, Shared` — khớp code cũ).
- AC: [07b §5](07b-on-server-check-ac.md#5-also-on-server-2026-11-06).

## 8. Dấu lưới và Photo Info (đợt 2)

- Glyph "trên server" của FS-15.02c giữ hình, đổi nghĩa: mục có trên ít nhất một nguồn server theo §3 (đã làm, T18:
  `ServerUploadIndex.presentIds`, đọc lại sau mỗi đợt kiểm). Lịch sử upload vẫn nuôi Uploaded to Server và Photo Info.
  VoiceOver "On server".
- Photo Info: mục **On Server** — mỗi file khớp một dòng `NAS Home` + đường dẫn; mục Uploaded to Server giữ nguyên.

## 9. Xoá

- **Dựa vào server** = mục đang có trên ít nhất một folder server theo §3. Chỉ những mục đó qua bước kiểm; mục khác xoá
  như cũ.
- Ngay trước khi gọi Photos: hỏi server từng file đã khớp — còn đúng đường dẫn, đúng cỡ, đúng ngày sửa. Lệch đường dẫn →
  tìm lại bằng hash nhanh + cỡ trong cùng nguồn trước khi coi là mất. Không băm lại lúc xoá.
- File mất hay đổi → mục đó **không** bị xoá; alert sau lượt: "2 photos weren't deleted — they're no longer on NAS Home."
- Server không với tới → alert "Can't reach NAS Home" + "ShotDex couldn't check that these are still on NAS Home." ·
  **Delete Anyway** (đỏ) · **Cancel**. Mục không dựa vào server trong cùng lượt vẫn xoá.
- Xoá bản Photos **không bao giờ** ẩn hay đụng bản server; mục còn trong Library qua bản NAS.
- Hộp xác nhận thêm: "They move to Recently Deleted. iCloud space is freed after Recently Deleted is emptied."
- Đợt 1 nối cổng vào xoá ở smart album, Free Up Space, chọn-rồi-xoá ở Library; một test chặn mọi lời gọi xoá PhotoKit
  mới nằm ngoài cổng. Đợt 2 nối mọi lối còn lại (N2: mọi lối xoá).
- Đợt 2 (T20, đã làm): mọi lối còn lại — viewer, album thường, On This Day, Hidden, Duplicates, Bursts, Cull (Rejected),
  phần Photos của xoá qua nguồn, xoá bản gốc sau Compress — đi qua `PhotoLibraryService.deleteAssetsCheckingServer` (hoặc
  hỏi cổng trực tiếp ở Compress). Các lối này không có alert riêng: mục xác nhận được (hoặc không dựa vào server) bị xoá,
  mục còn lại **giữ lại** và lối đó báo lỗi bằng câu của `PhotoDeletionGate.Kept` ("2 photos weren't deleted — they're no
  longer on NAS Home." / "Can't reach NAS Home, so 3 photos weren't deleted…"). *Delete Anyway* chỉ có ở ba lối đợt 1.
- Ngoài phạm vi: file trên NAS hỏng âm thầm sau khi đã băm.
- Mã: `Data/Sources/PhotoDeletionGate.swift` (hỏi server: một lần liệt kê mỗi folder, so cỡ + ngày sửa bằng
  `ServerCopyVerification`; file không ở đường dẫn cũ → liệt kê lại nguồn một lần rồi xét lại), `Features/Shared/
  PhotoDeletionFlow.swift` (alert). Mục có trên hai nguồn: một nguồn trả lời đủ là xoá được. **Cancel** ở alert *Can't
  Reach* không xoá gì cả (kể cả mục không dựa vào server) — chọn an toàn khi câu "vẫn xoá" ở trên có hai cách hiểu.
  Hộp xác nhận (câu Recently Deleted) chỉ hiện khi lượt xoá có mục dựa vào server; Free Up Space đã có hộp riêng nên bỏ
  qua hộp này. Hộp hệ thống của Photos vẫn hiện sau đó.

## 10. Board

Dòng Folder: `PH_/IP_/DI_/DC_SmartAlbumEditor` · dòng tiến độ + chip Also on Server (tới 2026-11-06: chip Source): `PH_/IP_/DI_/DC_SmartAlbum` (vẽ
2026-10-25). Alert sau xoá và alert *Delete Anyway* là alert hệ thống, không vẽ — chữ ghi trong comment của
`PH_/IP_/DI_DeleteCopies`. Mục On Server trong Photo Info: `PH_/IP_/DI_/DC_Metadata` (vẽ 2026-10-26, dưới Shutter Count).

## 11. Mac (2026-11-02)

Người dùng 2026-11-02: Mac ưu tiên quản lý ảnh — smart album "đã có trên NAS" có trên Mac, kiểm chạy cả khi app đã Quit.

- Quy tắc khớp, hash, smart album, xoá (§3–§9) **giữ nguyên**; code `OnServerCheck`, `OnServerPresenceSQL`,
  `PhotoDeletionGate` đã build cho macOS.
- **Ai chạy:** helper `ShotDexMacAgent` của [FS-22.06 §2](../FS-22-backup/06-mac.md#2-helper) — một người chạy cho cả
  Backup và kiểm; Backup đi trước, cùng khoá connection §5. Thay BGProcessingTask của §6 (đợt 2) trên Mac.
  Helper tắt → kiểm chạy khi app mở; lý do chờ `Open ShotDex to continue` giữ nguyên.
- **Khi nào:** cổng §6 giữ nguyên, với hàng điều kiện đổi tên theo FS-22.06 §4. Liệt kê server lại: mỗi lần app về trước
  mặt (§5) **và** mỗi 30 phút trong helper — *vì* trên Mac không có "về trước mặt" khi app đã Quit.
  Code (2026-11-02): `MacAgent` chạy `OnServerCheck` lúc khởi động, sau khi máy thức, mỗi 30 phút và khi app về trước
  mặt (lệnh `checkOnServer`; đến giữa lượt thì chạy lại ngay khi lượt xong). Helper đăng waits/finishedAt qua defaults
  nhóm app + thông báo Darwin; app hiện bằng `OnServerCheck.showRemote`, số đếm đọc từ database chung. Không còn nguồn
  server → lượt dừng giữa batch; không còn job lẫn nguồn → helper thoát.
- **Smart album:** sheet `MAC_SmartAlbumEditor` — điều kiện Also on Server (tới 2026-11-06: Source với nguồn server) có dòng **Folder** (popup + Choose…
  mở `MAC_ServerBrowser`); album mở trong cửa sổ chính (`MAC_SmartAlbum`): chip Also on Server và dòng tiến độ §7 nằm ở thanh
  dưới toolbar, cùng hàng với số mục. Lưới phẳng 7 cột, mới nhất trước, không tiêu đề ngày (như iOS). Không ảnh nào
  khớp → thanh điều kiện giữ nguyên, giữa màn là *No Photos Match* + nút **Edit Smart Album…** (tweak `empty`).
- **Dấu lưới và Get Info:** glyph "trên server" ở góc ô lưới Mac như iOS; Get Info (`MAC_GetInfoSingle`) thêm mục
  **On Server** — mỗi file một dòng `NAS Home` + đường dẫn.
- **Xoá:** chọn trong album → Delete (⌘⌫) hoặc chuột phải › Delete N Photos… — đi qua `PhotoDeletionGate` như ba lối
  đợt 1; alert là `NSAlert` (Delete Anyway đỏ, Cancel mặc định). Mọi lối xoá Photos khác trên Mac cũng qua cổng (N2).
  Lựa chọn có ảnh mang bản sao thư mục hoặc server (không có PHAsset) đi qua nguồn như iOS
  ([FS-19.04 §2](04-deleting-and-duplicates.md)): file vào Thùng rác, bản trên NAS chỉ **Hide** trong ShotDex — không bao giờ xoá trên
  server. Trước đây (tới 2026-11-04) Mac chỉ gọi PhotoKit, nên ảnh chỉ có trên NAS bị bỏ qua mà vẫn báo xong.
- **Ngoài phạm vi trên Mac lúc này:** Free Up Space (FS-15.02c) — chưa có màn Mac.

AC: [07b §3](07b-on-server-check-ac.md#3-mac).

### 11.1 Tiến độ luôn thấy và kiểm lại khi cần (2026-11-08)

- **Nhanh hơn trên Mac (người dùng 2026-11-08: "library đã tải full, WIN đã có SHA từ Common Photos, sao vẫn tắc"):**
  - SHA mà Find Common Photos đã đọc trên connection (`common_photo_scan_records`, khớp đường dẫn + cỡ) được dùng thẳng
    cho file server, như sổ Backup — không đọc lại file.
  - Mac băm **4 bản gốc cùng lúc** (`concurrentDownloads`; iPhone/iPad vẫn 1 file một lúc như §4), luật chỗ trống cộng
    cả các file đang chạy.
  - Quét lại nguồn server: đọc mọi bản ghi cũ một lần và ghi file không đổi theo lô 500 (trước là 1 đọc + 1 ghi mỗi file);
    khoá file cạnh DB để app và helper không cùng quét một nguồn (trước hai process giành khoá ghi hàng giờ).
  - Helper gửi số lô mỗi lần (trước chỉ gửi khi lý do chờ đổi, nên dòng tiến độ của app đứng yên) và **bước hiện tại**:
    Listing the server's files · Reading files on the server · Hashing originals from Photos · Spot-checking other
    devices' hashes · Linking matched photos — hiện trong Activity › Background.
- Dòng `Checking · …` ở header smart album và chân sidebar bấm được → Activity › Background.

- **Chân sidebar Mac:** khi còn mục chưa có câu trả lời, khi đang chạy hay đang chờ — `Checking On Server`, dòng §7 của
  nguồn server đầu tiên (`Checking · 1,240 of 23,904 · 38 GB to download` hoặc lý do chờ) và thanh tiến độ; bấm mở
  On Server. Đọc ngoài main mỗi lô (`generation`), không mỗi khung hình. Hết việc thì về dòng index.
- **Chạy lại:** mỗi lần app Mac về trước mặt và khi mở một smart album có điều kiện server (lệnh `checkOnServer` cho
  helper nếu helper chạy), không chờ lượt 30 phút; một lượt đang chạy thì không mở thêm.
- Kiểm: `mac-smartalbum-onserver.json` (chân sidebar, bấm → On Server).
- **Không bao giờ giữ DB lâu (hang 2026-11-08, Mac treo 17 phút):** truy vấn tiến độ có `size IS NULL OR s.size =
  size` không dùng được index cỡ — mỗi file Photos quét mọi file server, ~20 phút ở 55.000 ảnh, giữ một reader của pool;
  các màn hỏi lại mỗi lô nên giữ hết reader và main thread chờ. Sửa: tách hai nhánh (0,43 s ở 30.000 ảnh,
  `OnServerScaleTests`), `OnServerReadGate` (mỗi câu hỏi một lần đọc chạy một lúc, kết quả giữ 10 s, các màn dùng
  chung), và không đọc DB đồng bộ trên main ở các màn Mac (trình duyệt server, cửa sổ gốc, chọn người chạy nền).

## 12. Băm dùng chung — Mac băm hộ, máy khác chỉ đọc (2026-11-03)

Nguồn: [intent 2026-11-03-mac-hashes-for-on-server-check](../../_intents/2026-11-03-mac-hashes-for-on-server-check.md).
Quy tắc khớp (§3) và xoá (§9) **giữ nguyên**; mục này chỉ đổi **ai băm** và **SHA đi đường nào**.

### 12.1 Mac băm

- **Phía Photos:** helper Mac băm SHA-256 mọi file gốc (§3: ảnh, RAW, video Live Photo, video, bản sửa) của **mọi**
  mục Photos có `cloudIdentifier`, không chỉ mục có ứng viên cùng cỡ trên NAS. Mục mới vào thư viện được băm trước, như
  §4.
  - Bản gốc chưa có trên Mac (Mac cũng bật Optimize Storage): tải về thư mục tạm, băm, **xoá ngay**, một file một lúc
    như §4. Photos có giữ bản gốc vừa tải trên Mac hay không thì PhotoKit không cho điều khiển: đo bằng spike S9 trước
    khi hứa "vẫn tối ưu". Luật chỗ trống (§4) giữ nguyên; file không rõ cỡ tính thêm 2 GB. File hỏng 5 lần thì thôi băm
    hết cho nó (vẫn băm khi có file server cùng cỡ).
- **Phía NAS:** helper băm **mọi** file ảnh và video (các đuôi FS-19.01 nhận) trong mọi nguồn server, không chỉ ứng
  viên (§5). File có SHA sẵn (sổ Backup, sổ dưới đây, cache theo đường dẫn + cỡ + ngày sửa) thì không đọc lại.
- **Thứ tự và cổng:** cùng khoá connection §5 (Backup đi trước, một lệnh một lúc), cùng cổng §6/§11.
- **Cùng cỡ đi trước (người dùng 2026-11-08: "cả chục nghìn ảnh chung mà chỉ hiện vài cái"):** băm hết không có nghĩa
  là băm theo thứ tự mới nhất bất kể. Phía Photos, file có một file server **cùng cỡ** được tải và băm trước mọi file
  khác; phía NAS, file có một file Photos cùng cỡ được đọc trước (rồi mới theo đường dẫn). Trong mỗi nhóm giữ thứ tự cũ.
  *Vì* "không có trên server" đã biết ngay từ cỡ (§3), còn "có" thì phải băm cả hai phía: không ưu tiên thì ảnh chung
  nằm cuối hàng đợi sau cả thư viện. Code `CopyFileStore.photosCandidates`/`serverCandidates` (`everything`), test
  `PhotosHashTests.everythingHashesSameSizeFirst`, `everythingReadsSameSizeServerFilesFirst`.
- **Công tắc:** Mac băm cả thư viện và cả NAS khi công tắc có sẵn *Share Index Across Devices* (BD-03.05) bật
  (người dùng 2026-11-03). Không có màn hay công tắc mới.

### 12.2 Sổ SHA trên NAS (A)

- **Ngoại lệ có chủ ý** của luật "không ghi gì lên nguồn server" (§3, FS-19.04 D6), người dùng 2026-11-03: một sổ ở
  **gốc mỗi nguồn server**, thư mục ẩn **`.shotdex/hash-index/`**, cho cả cây folder của nguồn.
- Định dạng và luật ghi **giống sổ Backup** ([FS-22.05 §2](../FS-22-backup/05-duplicates-across-devices.md)):
  - Mỗi máy chỉ ghi các đoạn của chính nó, `<mã máy>-<số>.jsonl`, mỗi lượt có SHA mới thì thêm một đoạn.
  - Ghi qua file part, đọc lại SHA rồi mới đổi tên.
  - Một dòng = một file: đường dẫn tương đối với gốc nguồn, cỡ, ngày sửa, SHA-256, máy ghi, lúc ghi.
  - Mọi máy đã băm file NAS (Mac là chính, iPhone cũng có) đều ghi đoạn của mình.
- **Đọc:** sau mỗi lần liệt kê nguồn, đọc các đoạn chưa đọc. Một dòng gắn SHA cho file đã liệt kê chỉ khi **đường
  dẫn + cỡ + ngày sửa đều khớp**; listing không có ngày sửa thì bỏ dòng đó. Dòng lệch hay dòng hỏng thì bỏ, không dừng
  lượt.
- `.shotdex/` ẩn với mọi phía: không liệt kê thành ảnh, không băm, không tính vào số ảnh của nguồn, FS-19.08 bỏ qua.
  ShotDex không bao giờ sửa hay xoá file ảnh của người dùng vì sổ này.
- Ghi lỗi (quyền ghi, server đầy): thử lại lượt sau, kiểm vẫn chạy.

### 12.3 Chia sẻ qua iCloud (C)

- Đi trong index dùng chung BD-03.05 (container `iCloud.com.hoangtuan.shotdex`, private database, zone `SharedIndex`),
  thêm hai loại record:
  - **`PhotoFileHash`**: tên = SHA-256 của (máy, cloud id, khoá file) — mỗi máy một record, tên luôn dưới 255 byte. Trường: cloud id, khoá file (`type:name` như sổ Backup), ngày
    sửa ảnh (giây), cỡ, SHA-256, máy.
  - **`ServerFileHash`**: tên = SHA-256 của (máy, danh tính server, đường dẫn). Trường: danh tính server
    (`ServerIdentity.key`: giao thức, host, cổng, user SFTP, share và http/https của WebDAV), đường dẫn đầy đủ trên server, cỡ, ngày sửa, SHA-256, máy.
- **Dùng khi:**
  - Photos: cloud id ánh xạ ra ảnh trên máy, **ngày sửa ảnh trùng**, cỡ file trùng.
  - NAS: connection trên máy cùng danh tính, file đã liệt kê có **đường dẫn + cỡ + ngày sửa** trùng.
  - Lệch thì máy tự băm như §4–§5.
  - Danh tính khác nhau giữa các máy (một máy `nas.local`, máy kia IP) thì không khớp: giới hạn đã biết.
- **Thứ tự trong một lượt:** kéo record (chờ tối đa 10 giây, phần về muộn dùng ở lượt sau) → khớp → băm phần còn
  lại. Ảnh Photos mới liệt kê được khớp ngay sau khi liệt kê, trước khi chọn file để tải, nên lượt đầu cũng không tải
  file máy khác đã băm.
- **Hai chiều:** máy nào băm trước thì đẩy lên, mỗi lượt tối đa 2.000 SHA của chính máy và 5 lô đẩy; phần còn lại đi ở
  lượt sau. SHA gửi kèm **lúc băm**, không phải lúc gửi (§12.4 so theo lúc băm). Gửi lại khi máy băm lại file đó.
  Record của máy khác không bao giờ đè record của máy này; SHA nhận về chỉ điền file chưa có SHA.
- Lưu trên máy: SHA nhận được ghi vào `copy_files` với `origin = shared` và mã máy gửi, để §12.4 xoá được theo máy.
- Tắt *Share Index Across Devices*, không có iCloud, hoặc bản Mac thiếu entitlement: không kéo, không đẩy, chạy như hôm
  nay.

### 12.4 Tin SHA từ máy khác — kiểm ngẫu nhiên

- SHA nhận từ máy khác (qua iCloud hay sổ NAS) dùng cho §7 (smart album) và §9 (xoá) như SHA tự băm.
- **Kiểm ngẫu nhiên** (người dùng 2026-11-03): mỗi lượt kiểm, mỗi máy gửi, iPhone/iPad tự băm lại **K** file chọn
  ngẫu nhiên trong những file mà SHA từ máy đó đang làm một mục khớp **is**. Đó là file NAS hoặc file Photos.
  **K = 10** mỗi máy gửi mỗi lượt (người dùng 2026-11-03); ít hơn 10 file như vậy thì kiểm hết.
  - Chạy sau vòng băm, trước gộp ảnh (merge). Chỉ chọn file đọc được lúc này: ảnh iCloud khi luật Wi‑Fi/sạc cho phép,
    file NAS của nguồn đang mở; ảnh Photos phải có danh sách file còn mới (chưa sửa sau lần liệt kê); file > 1 GB
    không đưa vào mẫu. Đọc không được thì bỏ qua, không tính là lệch.
  - File đọc lại khớp thì từ đó là SHA của máy này.
- **Lệch một file:**
  - Bỏ **mọi** SHA nhận từ máy đó và chưa được tự băm lại, ở cả hai kênh. Các mục đó quay về "chưa kiểm xong" rồi máy
    tự băm.
  - Ghi dòng tiến độ: `Hashes from Tuấn's MacBook didn't match — checking on this iPhone.` (`this iPad` / `this
    Mac` theo máy đang xem; nhiều máy thì nối tên kiểu danh sách). Tên là tên máy gửi kèm record iCloud (trường
    `deviceName`, giữ trong bảng `hash_device_names`). Máy không gửi tên (chỉ qua sổ NAS) → `another device`.
    iPhone/iPad không có entitlement tên máy chỉ gửi được `iPhone`/`iPad`: giới hạn đã biết. Câu này được xuống
    dòng, không cắt chữ; nó mất khi lần kiểm sau đọc file của máy đó và thấy đúng.
  - Tin lại: SHA máy đó gửi **sau** lúc lệch được tin lại, vẫn kèm kiểm ngẫu nhiên (người dùng 2026-11-03). SHA gửi
    trước lúc lệch thì không bao giờ được dùng lại.
- Xoá vẫn hỏi lại server từng file ngay trước khi gọi Photos (§9), dù SHA đến từ đâu.

### 12.5 Máy nhận

- iPhone/iPad/Duo: lấy SHA dùng chung trước, rồi mới tự băm phần còn thiếu, theo đúng thứ tự §4–§5. Mac chưa băm tới thì
  máy tự băm như hôm nay (người dùng 2026-11-03), rồi đẩy kết quả lên.
- Dòng tiến độ (§7) giữ nguyên, chỉ thêm câu lệch ở §12.4; không có câu "checked on Mac" (người dùng 2026-11-03).
- Chỉ phục vụ §7–§9 (người dùng 2026-11-03, phạm vi v1). Duplicates "trùng byte" và FS-19.08 chưa đọc SHA dùng chung.

### 12.6 Board

- Câu lệch ở §12.4 nằm trong dòng tiến độ có sẵn của `PH_/IP_/DI_/DC_SmartAlbum` và `MAC_SmartAlbum`: vẽ thêm trạng
  thái này (tweak) trên từng board khi làm.
- Không có màn mới.

AC và spike: [07b §1 (S5–S8), §4](07b-on-server-check-ac.md#4-băm-dùng-chung-12).

