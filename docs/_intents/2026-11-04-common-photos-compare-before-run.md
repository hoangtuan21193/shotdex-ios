# Intent: Common Photos — xem kết quả Scan rồi mới quyết, và chạy nhanh hơn

| Trường | Giá trị |
|---|---|
| Tác giả | Tuấn (qua Claude) |
| Ngày | 2026-11-04 |
| Trạng thái | accepted (2026-11-04) |
| Tiến độ | **đang làm** (2026-11-04) — task 2/12, 4/18 AC xanh; plan [2026-11-04-fs1908-review-scan-and-faster](../_plans/2026-11-04-fs1908-review-scan-and-faster.md) |
| Nguồn | phản hồi người dùng 2026-11-04: "có thể check trước khi copy hay move không, nghĩa là có chỗ để compare thật sự 2 ảnh giống nhau hay video giống nhau trước khi click move hay copy không" · "tôi chỉ cần same, k cần likely, dùng SHA thôi là đủ … làm sao để cải tiến tốc độ nữa … khi scan sẽ tổng hợp list các ảnh và video giống nhau, có sẵn thông tin sẽ move hay copy ảnh nào về đâu, rồi khi ấn move hay copy sẽ làm dựa trên kết quả scan, k băm lấy SHA lại" |
| Spec sinh ra từ đây | [FS-19.08 §6d](../02-functional-spec/FS-19-photo-sources/08-common-photos.md) · AC-174…191 ở [08b](../02-functional-spec/FS-19-photo-sources/08b-common-photos-ac.md) |

## Problem — vấn đề

Bấm **Scan** trong sheet Find Common Photos (FS-19.08 §4, board `MAC_CommonPhotos`) xong, người dùng nhận một danh sách
nhưng chưa đủ để quyết Copy hay Move:

- **Danh sách không nói sẽ làm gì.** Mỗi hàng chỉ có thumbnail 28pt, tên, đường dẫn nguồn, cỡ, nhãn Same / Likely.
  Không biết:
  - ảnh sẽ nằm ở đâu trong Shared, tên cuối là gì (`IMG_0001 (2).JPG` khi trùng tên);
  - ảnh nào sẽ là Skipped vì Shared đã có;
  - Move sẽ xoá những bản nào.
- **Nhãn Likely thừa.** Người dùng chỉ cần Same: SHA-256 cả file trùng tức là giống từng byte. Likely (§5 bước 3) hiện
  ra trước khi kịp băm, không bao giờ được chạy, chỉ làm danh sách nhiễu.
- **Không nhìn được hai bản cạnh nhau.** Không mở được ảnh hay video của bản ở `Tuấn/` và bản ở `Vợ/`.
  - Thumbnail chỉ có khi folder là nguồn đã index (`MacCommonPhotosRow.loadThumbnail`,
    `ShotDexMac/Servers/CommonPhotos/MacCommonPhotosSheet.swift:748`). Không phải nguồn thì hàng là ô xám.
  - Video không có gì để xem.
- **Không bỏ được từng hàng.** Nút **Copy N / Move N** chạy *mọi* hàng Same. Thấy một hàng lạ thì chỉ có hai đường:
  chạy cả loạt, hoặc huỷ.
- **Danh sách Move chờ của tự gom cũng vậy.** Bộ Move tự gom để sẵn "Ready to move N" (§6c, AC-169). Người dùng bấm
  **Move N…** mà không xem được từng ảnh sẽ bị xoá khỏi nguồn.
- **Copy chậm hơn cần thiết.** Mỗi ảnh đi qua mạng 3 lần: tải về, đẩy lên, rồi đọc lại bản ở Shared để kiểm SHA
  (`CommonPhotosRunner.swift:374–384`).
  - Ước tính 15k ảnh / 90 GB qua 1 GbE: ~45–60 phút Copy, cộng ~30 phút băm khi Scan. Chưa đo trên NAS thật.
  - Người dùng muốn bấm chạy là làm theo kết quả Scan, không băm lại.
  - Move đã không băm lại: kiểm cỡ + ngày sửa, chỉ băm khi file đổi sau Scan.
- **Board lệch code.** Board `MAC_CommonPhotos` chỉ vẽ trạng thái sau Scan; trạng thái trước Scan có nút **Scan**
  (code: `MacCommonPhotosSheet.swift:601`) không có board. Phần này sửa ngay, không chờ spec.

Mức độ: cao với Move. Server không có Trash; Undo có nhưng chậm như chính lượt chạy (§10). Với hàng chục nghìn file,
không thấy trước kế hoạch thì không dám bấm.

## Proposed outcome — kết quả mong muốn

- **Scan ra một kế hoạch**: danh sách chỉ gồm ảnh và video **Same**.
  - Mỗi hàng ghi: bản nào ở folder nào → tên gì ở Shared, hoặc Skipped (đã có).
  - Với Move, hàng ghi thêm bản nào sẽ bị xoá.
  - Đếm tổng ở trên: số ảnh, số video, dung lượng.
- **Bấm Copy/Move là chạy đúng kế hoạch đó**, không băm SHA lại các bản nguồn.
  - Vẫn chặn được trường hợp file bị đổi trên server sau Scan (luật an toàn §6).
  - Bước kiểm nào còn giữ, và vì sao, thì nói rõ trên màn.
- Từ một hàng mở được **hai bản cạnh nhau**: ảnh to, video chạy đồng bộ. Mỗi bên ghi folder, tên, cỡ, ngày chụp và SHA
  rút gọn.
- **Bỏ chọn** được từng hàng hay nhiều hàng; nút đếm đúng số còn chọn ("Copy 278"). Ảnh đã bỏ được nhớ cho bộ đó.
- Danh sách Move chờ của tự gom có cùng cách xem và bỏ chọn.
- **Copy nhanh hơn rõ.** Đích mong muốn: không còn đi qua mạng 3 lần mỗi ảnh. Con số cụ thể đặt ở `/spec` sau khi đo.
- Không xem gì thì vẫn một bấm là chạy.

## Affected users and systems — phạm vi ảnh hưởng

- Màn:
  - sheet `MAC_CommonPhotos`;
  - cửa sổ log `MAC_CommonPhotosRun` (danh sách ready, Move N…);
  - một board mới cho khung so sánh.
  - Board `MAC_Duplicates` (A/B) và `PhotoCompareScreen` của iOS là tiền lệ: đọc trước, không làm hai kiểu so sánh.
- Thiết bị: chỉ Mac (FS-19.08 chỉ Mac).
- Tầng:
  - Domain:
    - `CommonPhotosScanModel`: bỏ Likely, kế hoạch từng hàng, hàng nào đang chọn;
    - `CommonPhotosRunner`: chạy theo kế hoạch, ít đọc lại hơn;
    - `CommonPhotosAutoGather`: bộ Move ready.
  - Data:
    - client FS-15 (SMB, WebDAV, SFTP): có thể thêm lệnh chép ngay trên server;
    - tải byte để xem.
  - Features: ShotDexMac.
- Dữ liệu đã lưu: ảnh bị bỏ chọn là **dữ liệu người dùng tự tạo**, nên cần bảng riêng (BD-02) và migration mới.
  Kế hoạch của Scan đã nằm ở `common_photo_items` (đường dẫn đích, các nguồn) và có thể cần thêm cột.

## Constraints — ràng buộc

- Byte chỉ đi giữa Mac và server của người dùng (NF-03 §2b).
- Một lệnh tới server một lúc mỗi connection (03 §2). Song song hoá thì phải đo trước, không đoán.
- Xem một bản chưa index nghĩa là tải bản đó về. Việc này không được làm chậm Scan đang chạy.
- Bộ nhớ: không giải mã full-res cả danh sách; một lúc chỉ mở bản đang xem (NF-02).
- Không thêm dependency. Video dùng AVKit, ảnh dùng ImageIO đang có.
- Luật an toàn §6 giữ nguyên:
  - không bản nguồn nào bị xoá trước khi bản ở đích được kiểm;
  - file đổi sau Scan phải bị bắt.
- Không đổi luật so sánh: vẫn SHA-256, không thêm "trông giống" (người dùng 2026-11-02 đã loại).
- Bỏ chọn chỉ được bớt hàng, không thêm hàng.
- Mac: `docs/design/mac/MAC_STYLE.md`, không bịa token. Board vẽ trước, code sau.

## Open questions — câu hỏi còn treo

Đã chốt (người dùng 2026-11-04):

1. **Chỉ Same**, bỏ Likely khỏi UI. SHA-256 là đủ.
2. **Khung so sánh:** hai bản cạnh nhau, trong cửa sổ hoặc sheet riêng.
   - Mỗi bên ghi folder, tên, cỡ, ngày chụp và SHA rút gọn.
   - ←/→ sang hàng kế.
3. **Bỏ chọn được nhớ mãi cho bộ đó:**
   - lượt quét lại và tự gom bỏ qua ảnh đã bỏ;
   - có danh sách ảnh đã bỏ để xem lại và gỡ;
   - cần bảng riêng và migration.
4. **Video:** hai bên chạy đồng bộ, một nút play, một thanh tua.
5. **Danh sách Move chờ của tự gom:** dùng cùng khung xem và bỏ chọn, trong cửa sổ log.
6. **Chạy theo kết quả Scan**, không băm lại các bản nguồn.

Claude chọn sẵn, người dùng đổi được khi duyệt:

7. **Ảnh chưa index:** mở so sánh thì tải cả file về để xem (HEIC/RAW không phải lúc nào cũng có preview nhúng).
   Cache tạm và trần dung lượng quyết ở `/spec`.

Chốt ở `/spec` (người dùng 2026-11-04): 8 → không vá `SMBClient` (SMB giữ tải + đẩy), chỉ WebDAV `COPY`; 9 → vẫn đọc lại SHA ở đích; 10 → giữ một lệnh, chỉ xét lại khi có số đo trên NAS thật; cache Compare tối đa 2 GB. Câu hỏi gốc:

8. **Copy ngay trên server.** SMB có lệnh để NAS tự chép (server-side copy), WebDAV có `COPY`, SFTP thì tuỳ server.
   - Client SMB của app và NAS của người dùng có hỗ trợ không: Claude thử trên SMB ảo + NAS thật.
   - Nếu có thì bản ở Shared kiểm bằng gì: đọc lại SHA vẫn qua mạng một lần, hay tin server. Người dùng chốt sau khi
     có số đo.
9. **Bỏ bước đọc lại SHA ở Shared với Copy** (nhanh ~1/3). Copy không xoá nguồn nên rủi ro thấp; Move vẫn giữ bước
   kiểm. Người dùng chốt.
10. **Băm song song 2–4 file khi Scan:** chỉ nhanh hơn trên NAS SSD/nhiều ổ; NAS một ổ cứng có thể chậm đi. Claude đo,
    người dùng chốt.

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
