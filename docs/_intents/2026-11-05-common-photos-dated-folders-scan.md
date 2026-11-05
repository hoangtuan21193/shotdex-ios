# Intent: Common Photos — quét nhanh hơn khi hai folder cùng cấu trúc năm/tháng/ngày

| Trường | Giá trị |
|---|---|
| Tác giả | Tuấn (qua Claude) |
| Ngày | 2026-11-05 |
| Trạng thái | accepted (2026-11-05) |
| Tiến độ | **chưa làm** (2026-11-05) — plan [2026-11-05-fs1908-6e-dated-organize-fileinfo](../_plans/2026-11-05-fs1908-6e-dated-organize-fileinfo.md) chờ duyệt, 12 task |
| Nguồn | phản hồi người dùng 2026-11-05: "sẽ có trường hợp ở thư mục A và B đều có cấu trúc folder giống nhau, theo năm, tháng, ngày … trong trường hợp này có thể lợi dụng để tìm ảnh giống nhau nhanh hơn không" |
| Spec sinh ra từ đây | [FS-19.08 §6e](../02-functional-spec/FS-19-photo-sources/08-common-photos.md) · AC-193…219 ở [08b](../02-functional-spec/FS-19-photo-sources/08b-common-photos-ac.md) |

Intent anh em: [2026-11-05-common-photos-destination-layout](2026-11-05-common-photos-destination-layout.md) (xếp ảnh ở đích).

## Problem — vấn đề

Người chụp ảnh thường xếp ảnh trên NAS theo `Năm/Tháng/Ngày`, và hai folder cần so (vd `Tuấn/` và `Vợ/`, hay ổ cũ
và ổ mới) thường có **cùng cây đó**: `2025/` có 12 folder tháng, mỗi tháng có folder từng ngày. Find Common Photos
(FS-19.08, Mac) không biết điều này và quét như hai đống file không liên quan:

- **Liệt kê cả hai cây, tuần tự, mỗi folder một lệnh.** `ServerTreeListing.list`
  (`ShotDex/Data/Sources/FileServer/ServerTreeListing.swift:9`) đi từng folder một; `CommonPhotosScanner.list`
  (`ShotDex/Data/Sources/FileServer/CommonPhotos/CommonPhotosScanner.swift:17`) liệt kê A xong mới tới B. Một năm
  xếp theo ngày ≈ 12 + ~365 folder mỗi bên. Folder chỉ một bên có (`A/2019/` mà B không có `2019/`) vẫn bị liệt kê
  hết dù không thể chứa ảnh chung.
- **Chạy lại vẫn liệt kê lại cả cây.** "Only new photos" (§6c, `CommonPhotosIncremental.swift`) bỏ được phần băm
  của file đã thấy, nhưng vẫn liệt kê mọi folder ngày, kể cả folder không đổi từ lần trước.
- **Băm cả file ở mọi bản.** Bước 4–5 (`CommonPhotosVerifier.swift`) tải toàn bộ mỗi bản để lấy SHA-256: 100 GB ảnh
  chung là ~200 GB đọc qua mạng. Với hai cây cùng cấu trúc, `A/2025/03/15/DSC_0412.ARW` và
  `B/2025/03/15/DSC_0412.ARW` cùng cỡ gần như chắc là một ảnh, nhưng vẫn phải đọc đủ cả hai.

Phần app đã tận dụng: cùng tên hoặc cùng folder con đã làm file thành Likely, nên bước đọc đầu file lấy giờ chụp
(§5 bước 3) gần như không chạy với hai cây cùng cấu trúc. Ghép theo cỡ làm trong bộ nhớ, đã rẻ.

**Số đo trên NAS thật (2026-11-05)** — `iCloud Photo/Tuan` vs `iCloud Photo/Hue` (`Năm/Tháng/Ngày`), qua SMB mount
của Finder, Mac trên Wi-Fi, chỉ đọc (script ở scratchpad phiên, không phải client SMB của app — số là cỡ, không phải
số của app):

| | Tuan | Hue |
|---|---|---|
| Folder / file / dung lượng | 2.549 / 60.259 / 954 GB | 2.532 / 62.514 / 1.036 GB |
| Liệt kê cả cây (từng folder một) | 409 s | 128 s |
| Một folder: trung vị / p90 | 44 / 303 ms | 31 / 89 ms |

- **Cỡ có ở cả hai bên** (ứng viên sau §5 bước 2): 15.712 file / 230 GB bên Tuan, 15.054 / 229 GB bên Hue.
- **Băm cả file hôm nay** (không cache): 459 GB đọc ở **23 MB/s** đo được ≈ **5,5 giờ**.
- **Liệt kê** cả hai cây ≈ **9 phút**. → Băm chiếm ~97% thời gian quét lần đầu.
- **Cùng đường dẫn + cùng cỡ**: 13.340 file / 195 GB — 85% số ứng viên. Đọc 3 mẫu 64 KB mất **113 ms/file** (tuần tự)
  → kiểm nhanh hai bên ≈ 13.340 × 2 × 0,113 s ≈ **50 phút** thay vì ~4,7 giờ băm phần đó.
- **Cùng tên + cùng cỡ nhưng khác folder ngày**: 205 file (vd `2026/07/25/HAT00130.MOV` ↔ `2026/07/26/`, lệch một
  ngày — múi giờ). Ghép chỉ trong cùng folder sẽ **bỏ sót** chúng.
- **Folder chỉ một bên có**: 792/2.549 (Tuan), 775/2.532 (Hue) — nhưng chỉ chiếm 42 s / 33 s thời gian liệt kê. Bỏ
  qua chúng tiết kiệm ~75 s trên 9 phút.
- Giờ sửa folder: folder ngày đổi khi thêm/xoá file, folder cha thì không (Open question 4).
- Chạy lại: liệt kê lại vẫn ~9 phút mỗi lượt; tự gom 15 phút một lần thì gần như liệt kê không nghỉ.

Mức độ: trung bình. Không sai kết quả, chỉ chậm; nhưng chậm tới mức lần quét đầu một thư viện vài năm mất hàng giờ,
và tự gom 15 phút một lần (§6c) phải liệt kê lại cả cây mỗi lượt.

## Proposed outcome — kết quả mong muốn

- Hai folder cùng cấu trúc ngày, Copy với kiểm nhanh: lần quét đầu bộ Tuan/Hue từ ~5,5 giờ xuống cỡ **1 giờ** (đo
  2026-11-05); con số chốt ở `/spec`.
- Folder chỉ một bên có thì không bị đọc.
- Chạy lại / tự gom: folder ngày không đổi thì không liệt kê lại.
- Có thể chọn **kiểm nhanh** cho Copy: không đọc cả file khi đường dẫn, tên, cỡ và vài mẫu đều khớp — người dùng
  biết rõ đó là "gần như chắc", không phải "từng byte".
- **Move vẫn chắc như hôm nay**: chỉ xoá khi bản kia được chứng minh giống từng byte.
- Ảnh bị xếp lệch ngày giữa hai bên (lệch múi giờ, sửa tay) vẫn được tìm thấy, không bị bỏ sót vì cấu trúc.
- Hai folder không cùng cấu trúc: không chậm hơn hôm nay.

## Affected users and systems — phạm vi ảnh hưởng

- Tính năng: Find Common Photos — sheet Scan, tự gom (§6c), Activity. Board `MAC_CommonPhotos` nếu thêm lựa chọn
  kiểm nhanh.
- Thiết bị: Mac (FS-19.08 chỉ có trên Mac).
- Tầng: Data (`ServerTreeListing`, `CommonPhotosScanner`, `CommonPhotosVerifier`), Domain (`CommonPhotosMatcher`,
  `CommonPhotosIncremental`), ShotDexMac (sheet). `ServerTreeListing` còn được index nguồn server dùng (FS-19.03) —
  đổi nó là đổi cả đường index.
- Dữ liệu đã lưu: muốn bỏ qua folder không đổi thì phải nhớ dấu từng folder (giờ sửa) cho mỗi bộ → có thể thêm bảng
  vào `CommonPhotosStore` (migration).

## Constraints — ràng buộc

- **Luật an toàn Move (§6) không đổi**: Move chỉ xoá khi SHA-256 cả file khớp và đích được chứng minh còn đó.
- Không bỏ sót ảnh chung chỉ vì nó nằm khác folder ngày ở hai bên.
- Server có thể không trả giờ sửa folder, hoặc giờ sửa folder không đổi khi file bên trong đổi (tuỳ SMB/WebDAV/NAS) —
  không được tin dấu folder khi server không đáng tin.
- Không mở quá nhiều kết nối song song làm NAS nghẽn hay bị từ chối.
- Không thêm dependency.

## Open questions — câu hỏi còn treo

1. ~~Đo trước: liệt kê chiếm bao nhiêu, băm chiếm bao nhiêu?~~ **Đã đo (2026-11-05, bảng ở Problem): băm ~5,5 giờ,
   liệt kê ~9 phút.** Còn đo lại bằng client SMB của app và trên dây LAN khi `/verify`.
2. ~~Có muốn chế độ kiểm nhanh cho Copy không?~~ **Đã trả lời (user 2026-11-05): có, tắt sẵn, chỉ cho Copy.** Move
   vẫn băm đủ.
3. **Nhận ra "cùng cấu trúc" thế nào**: tự đoán từ tên folder (`2025`, `03`, `2025-03-15`…) hay người dùng bật?
   — người dùng. Mặc định đề xuất: tự áp dụng cho mọi bộ (bỏ nhánh một bên, bỏ folder không đổi), không cần nhận
   dạng tên. **Chốt theo mặc định đề xuất (user duyệt intent 2026-11-05).**
4. ~~NAS có đổi giờ sửa của folder ngày khi thêm/xoá file bên trong không?~~ **Đã đo (2026-11-05, user cho ghi thử
   một file tạm vào `Tuan/2026/07/25`, đã xoá):** folder `25` đổi giờ sửa khi tạo và khi xoá file; folder cha `07`
   và `2026` **không** đổi. Share là Windows (`//…@win/Media`, NTFS).
   - Hệ quả: chạy lại vẫn phải liệt kê năm và tháng (~215 folder), nhưng giờ sửa của từng folder ngày có sẵn trong
     danh sách tháng → folder ngày không đổi thì không mở. Ước ~2.549 → ~215 lệnh liệt kê, ~9 phút → dưới 1 phút.
   - Không bắt được: file bị ghi đè tại chỗ cùng tên (NTFS không đổi giờ sửa folder); folder con nằm *trong* folder
     ngày (thay đổi của nó không lên folder ngày) → chỉ bỏ qua folder không có folder con.
   - Chưa đo: WebDAV, NAS khác (Synology/ext4/btrfs).
