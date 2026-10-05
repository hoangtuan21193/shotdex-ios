# FS-15.02b — Upload chạy nền (iOS 26)

`FS-15.02b` · `Features/ServerUpload/ServerUploadModel.swift` · `App/ScreenAwakeCoordinator.swift` · `Info.plist`
· cập nhật 2026-10-02

**Một câu:** trên iOS 26, bấm Upload là xin hệ thống cho lô chạy tiếp khi rời app; hệ thống hiện tiến độ, người dùng
làm việc khác hoặc khoá máy; trước iOS 26 giữ màn hình sáng như FS-15.02 §6.

Nguồn: [intent ui-review-1002](../../_intents/2026-10-02-ui-review-1002.md) (H3) — một ngày cưới là 40–60 GB RAW.

Board: `PH_ServerUpload`, `IP_ServerUpload`, `DI_ServerUpload`, `DC_ServerUpload` — câu ghi chú theo nhánh iOS;
trạng thái **Upload Paused** chưa có board, cần vẽ (bản sáng + tối) trước khi code.

## 1. Khi nào chạy nền

Cơ chế: **BGContinuedProcessingTask** của BackgroundTasks — việc do người dùng bấm bắt đầu, hệ thống cho chạy tiếp
ngoài app và tự vẽ tiến độ. Mã tác vụ khai trong Info.plist, cạnh tác vụ index nền (BD-03.04 §5).

| Nhánh | Bấm Upload | Rời app (Home, khoá máy, đổi app, gập Duo) |
|---|---|---|
| iOS 26+, hệ thống nhận | lô chạy; màn hình **không** bị giữ sáng | lô chạy tiếp tới xong, hỏng, hoặc hệ thống dừng (§3) |
| iOS 26+, hệ thống từ chối | lô vẫn chạy, giữ màn hình sáng | như trước iOS 26 |
| trước iOS 26 | lô chạy, giữ màn hình sáng | lô dừng như bị huỷ; quay lại thấy kết quả + **Upload Remaining** |

- Gửi yêu cầu lúc lô **bắt đầu đẩy**, ngay sau một lần bấm của người dùng khi app đang mở: Upload (sau bước dò
  trùng tên, FS-15.02 §5 — hoặc lúc trả lời câu hỏi trùng tên cuối), Resume, Upload Remaining, Try Again.
  *Vì hệ thống chỉ nhận yêu cầu từ một thao tác khi app đang mở.*
- Bước dò trùng tên chạy **trước** yêu cầu, trong app đang mở; nhờ nó lô ở nền không bao giờ dừng để hỏi tên (K28).
- Yêu cầu là "chạy ngay hoặc thôi", không xếp hàng. *Vì lô xếp hàng có thể bắt đầu khi người dùng đã đi.*
- Một lô một yêu cầu. Lô xong, hỏng hay bị huỷ thì báo hệ thống kết thúc ngay (thành công / hỏng) — không để tác vụ
  treo tới khi hết hạn.
- Đọc, ghi theo khối 1 MB và một file tạm một lúc như FS-15 §5 — chạy nền không đổi trần bộ nhớ, đĩa.

## 2. Giao diện tiến độ của hệ thống

| Phần | Nội dung |
|---|---|
| Tiêu đề | `Uploading to <tên connection>` |
| Dòng phụ | `12 of 40 · 4.1 of 9.8 GB` — cùng số với hàng tiến độ trong sheet (FS-15.02 §6) |
| Thanh | cùng tỉ lệ byte của thanh trong sheet, **tính cả lượt đọc lại** |
| Đang tải bản gốc từ iCloud | dòng phụ `Downloading IMG_1234.CR3 from iCloud` |

- Tỉ lệ báo cho hệ thống cập nhật sau mỗi khối 1 MB ghi hoặc đọc lại — cùng nhịp với thanh trong sheet.
- Hệ thống có nút dừng của riêng nó. Bấm ở đó = hệ thống dừng (§3), không hỏi thêm.
- Sheet trong app giữ nguyên bốn bước của FS-15.02; quay lại app là thấy đúng bước đang chạy, không màn mới.

## 3. Upload Paused · Resume

Hệ thống dừng lô — hết hạn (pin yếu, nóng máy, thiếu tài nguyên) hoặc người dùng bấm dừng ở giao diện hệ thống:

1. Lô dừng như Cancel: xoá `.shotdex-part` của file đang đẩy nếu còn kết nối, xoá file tạm trên máy.
2. File đã khớp checksum giữ lịch sử; file đang đẩy và các file sau là "chưa đẩy".
3. Quay lại app: sheet ở bước kết quả, tiêu đề **Upload Paused**, dòng đầu "Upload paused — 11 of 40 files are on
   the server.", dòng phụ "iOS stopped the upload in the background." và nút **Resume** (thay Upload Remaining).
4. **Resume** dò trùng tên lại cho phần còn lại (FS-15.02 §5), đẩy đúng các file chưa lên (luật Upload Remaining)
   và gửi một yêu cầu chạy nền mới.

- Đề nghị xoá khỏi máy vẫn hiện cho những tấm đã lên đủ (FS-15.02 §7) — dừng giữa chừng không làm mất phần đã xong.
- Không kịp xoá `.shotdex-part` (mất kết nối trước khi dừng): file đó nằm trên server tới lần đẩy lại file ấy, lần
  đó ghi đè nó. Nó không mang tên thật, nên luật "không tên thật nào trỏ tới file chưa kiểm" vẫn giữ.

## 4. Đường hỏng khi app ở nền

| Chuyện | Ở nền | Quay lại app thấy |
|---|---|---|
| Rớt mạng, server tắt | lô dừng (FS-15.02 §4); báo hệ thống "hỏng" | kết quả: "The connection to the server was lost." + **Upload Remaining** |
| Server đầy | lô dừng ở file đang ghi, xoá `.shotdex-part` của nó | "The server is out of space." + **Upload Remaining**; file đã lên giữ nguyên |
| Server từ chối mật khẩu giữa lô | lô dừng | "The username or password was rejected." + **Edit Connection** (mở form của connection đó) + **Upload Remaining** |
| Tên xuất hiện trên server sau lúc dò | **Keep Both**, lô không dừng (FS-15.02 §5) | kết quả ghi tên mới của file đó |
| Bản gốc chỉ trên iCloud | tải tiếp trong nền; iCloud không trả lời → file đó lỗi, lô đi tiếp | dòng lỗi của file đó |
| Hệ thống dừng | §3 | **Upload Paused** + **Resume** |
| Gập / mở Duo | lô chạy tiếp (iOS 26+) | sheet còn ở cảnh đang hiện |
| App bị đóng hẳn (vuốt khỏi app switcher, hệ thống giải phóng bộ nhớ) | lô dừng cùng app; lô dở còn trong bảng (§4a) | lần mở sau: "Upload paused · Resume" (§4a) |

- Lưu xong form từ **Edit Connection** thì về đúng bước kết quả; Upload Remaining dùng mật khẩu mới.

## 4a. Lô dở sống qua lần mở app sau

Board: chưa có board hàng "Upload paused · Resume" — cần vẽ trên `PH_/IP_/DI_/DC_` của On Server (K29).

- Lô đang đẩy được nhớ trong **một bảng riêng**: id ảnh, connection, folder, Date Folders, loại file, các file đã
  lên. Không cột nào trong bảng metadata — indexer ghi đè cả hàng ở đó (BD-02). Thêm bảng = một migration schema.
- Ghi lúc lô bắt đầu đẩy; cập nhật sau mỗi file khớp checksum. Xoá khi lô xong, khi người dùng bấm Cancel / Done,
  và khi xoá connection của nó. Giữ khi hệ thống dừng lô hoặc app bị đóng hẳn.
- Chỉ nhớ **một** lô dở. Bấm Upload cho lô mới khi còn lô dở → bước chuẩn bị có dòng "This replaces the paused
  upload of 29 files." — Upload là bỏ lô cũ.
- Lần mở app sau: hàng **Uploaded from This Device** ở On Server (hiện cả khi 0 ảnh đã lên) thêm dòng dưới
  `Upload paused · 29 files left` và nút **Resume**. Chạm Resume → sheet upload ở bước **Upload Paused** (§3) với lô
  đó, rồi đi như Resume: dò trùng tên cho phần còn lại, gửi yêu cầu chạy nền mới.
- Ảnh trong lô đã bị xoá khỏi thư viện hoặc ra ngoài phần `.limited` → bỏ khỏi lô, bước Upload Paused ghi "2 photos
  are no longer in your library." Connection bị xoá → lô dở bị xoá cùng nó, hàng không hiện.

## 5. Câu ghi chú ở bước chuẩn bị

| Nhánh | Câu (thay hàng Ghi chú của FS-15.02 §2) |
|---|---|
| iOS 26+ | "You can leave ShotDex. The upload keeps going and iOS shows its progress." |
| trước iOS 26 | "Keep ShotDex open until the upload finishes. The screen stays on." |
| iOS 26+, hệ thống vừa từ chối | hàng tiến độ thêm dòng "Keep ShotDex open — iOS didn't allow this upload to run in the background." |

## 6. Kiểm ở đâu

- Simulator (người dùng chốt 2026-10-02): logic chạy, dừng, Resume, fallback và đường hỏng kiểm bằng unit test với
  **bộ chạy nền giả** (nhận / từ chối / hết hạn theo lệnh) — AC-54…67 và AC-80…83 ở [FS-15.03b](03b-acceptance-criteria-ui-review.md).
- Chạy nền thật — giao diện hệ thống, khoá máy, hết hạn thật, gập Duo, iCloud trong nền: **⚠️ chưa chứng minh — cần
  máy thật**; chưa tính là xong tới khi có máy.
