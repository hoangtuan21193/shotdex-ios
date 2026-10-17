# FS-20 — Tiêu chí nghiệm thu

Thuộc [FS-20 Nhập từ thẻ nhớ](README.md). Mục số trong cột Cho/Khi/Thì là mục của README.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | thẻ 1.046 file, 234 có trong lịch sử nhập | mở màn Import | đầu màn *812 new photos · 234 already imported · skipped*; segmented ở New; 812 ô tick, 234 ô Imported không có ô tick | ⚠️ chưa có |
| AC-2 | như AC-1 | bỏ tick 1 ô HIF 9.8 MB | `811 checked`, nút **Import 811 Photos**, tổng GB giảm 9.8 MB | ⚠️ chưa có |
| AC-3 | ngày 27/9 có 228 ảnh, cả 228 đã nhập | mở màn | ngày đó là 1 dòng thu gọn `228 already imported`, 0 ô | ⚠️ chưa có |
| AC-4 | ảnh `IMG_6123.CR3` chụp 2026-10-03; Folders Year/Date; mẫu Date_`Kyoto`_Original Number | Import | file đích `RAW/2026/2026-10-03/2026-10-03_Kyoto_6123.CR3`; SHA-256 = bản trên thẻ | ⚠️ chưa có |
| AC-5 | preset Creator `Linh Pham`, Copyright `© 2026 Linh Pham`, Keywords Kyoto, autumn | Import 3 ảnh | mỗi ảnh có `.xmp` cạnh file mang Creator, Copyright và 2 keyword; SHA-256 của file ảnh không đổi | ⚠️ chưa có |
| AC-6 | cặp `IMG_0042.CR3` + `IMG_0042.JPG` | Import | 1 ô trên lưới; 2 file đích cùng tên, khác đuôi | ⚠️ chưa có |
| AC-7 | đích đã có `2026-10-03_Kyoto_0001.cr3`; mẻ có 2 ảnh ra cùng tên (đếm số máy quay vòng) | Import | `…_0001 (2).CR3` và `…_0001 (3).CR3`; SHA-256 file có sẵn không đổi | ⚠️ chưa có |
| AC-8 | backup bật, LaCie không cắm | mở màn | hàng Backup *Not connected*, footer nêu tên ổ, Import mờ | ⚠️ chưa có |
| AC-9 | mẻ 811 ảnh, backup bật, Eject bật | rút LaCie ở ảnh ~357 | bản chính chạy hết 811; thẻ không nhả; tổng kết *Backup incomplete — 357 of 811.* + Back Up Remaining; cắm lại → chạy 454 còn lại | ⚠️ chưa có |
| AC-10 | mẻ 811 ảnh | rút thẻ ở ảnh ~412 | ≤ 2 s: *EOS_DIGITAL was disconnected. 412 of 811 imported.*; 0 file `.shotdex-part` ở đích; cắm lại → 412 ô Imported, Import Remaining chép 399 | ⚠️ chưa có (logic bằng thẻ giả = thư mục DCIM ném lỗi); rút thẻ thật: chưa kiểm (cần máy thật) |
| AC-11 | đích còn 12.0 GB, mẻ 24.6 GB | mở màn | footer *Needs 24.6 GB, 12.0 GB free on T7.*; Import mờ; 0 file ghi | ⚠️ chưa có |
| AC-12 | đích báo đầy ở ảnh 412 (giả lập) | đang chép | mẻ dừng; *“T7 RAW Archive” is full — 412 of 811 imported.*; tên tạm bị xoá; 412 ảnh có trong nguồn | ⚠️ chưa có |
| AC-13 | đọc lại ảnh thứ 5 trả về byte khác (giả lập, 2 lần) | Import 10 ảnh | 9 ảnh vào nguồn; ảnh 5 không có ở đích, có trong tổng kết + Retry Failed; Eject bật mà thẻ **không** nhả | ⚠️ chưa có |
| AC-14 | mẻ đang chạy 200/811 | Stop Import… → Stop | dừng ≤ 1 s; 200 ảnh ở lại trong nguồn; 0 tên tạm; thẻ không nhả | ⚠️ chưa có |
| AC-15 | AC-14 xong, thẻ còn cắm | mở lại màn Import | 200 ô thêm vào nhóm Imported; New = 612 | ⚠️ chưa có |
| AC-16 | thẻ đã nhập hết 1.046 | cắm lại | đầu màn *0 new photos*; lưới New trống với dòng *"Everything on EOS_DIGITAL is already imported."* + Show All | ⚠️ chưa có |
| AC-17 | mẻ 811 ảnh đang chạy (Mac) | mở lưới All Photos, cuộn, mở Viewer | mọi thao tác làm được; chân sidebar `Importing from EOS_DIGITAL N%`; ảnh đã kiểm xuất hiện trong nguồn T7 trong lúc mẻ chạy | ⚠️ chưa có |
| AC-18 | mẻ 811 ảnh, backup bật, Eject bật, không lỗi | bản backup cuối cùng kiểm xong | banner *Imported 811 photos. EOS_DIGITAL ejected.*; thẻ biến khỏi hệ thống; 811 dòng lịch sử nhập | ⚠️ chưa có |
| AC-19 | app đang ở lưới All Photos (Mac và iPad) | cắm thẻ `EOS_DIGITAL` | ≤ 2 s có hàng `EOS_DIGITAL` trong nhóm Sources; lưới vẫn là All Photos, 0 banner; chạm hàng → màn Import | ⚠️ chưa có |
| AC-20 | thẻ không hiện qua khung máy ảnh; người dùng đã chọn ổ thẻ một lần | rút rồi cắm lại cùng thẻ | màn Import mở được, 0 trình chọn ổ hiện lại | chưa kiểm (cần máy thật) — logic: `CardBookmarkStoreTests.recognisesSameCard` |
| AC-21 | thẻ như AC-1; 10 trong 234 ảnh đã nhập bị xoá ở đích | mở màn Import | 822 ô New có tick, 224 ô Imported; đầu màn *822 new photos* | ⚠️ chưa có |
| AC-22 | `IMG_0100.CR3` khớp lịch sử theo tên + byte + giờ chụp, nội dung khác bản đã nhập | mở màn, chờ hash nền xong | ô hiện Imported ngay khi mở, rồi thành New có tick sau hash | ⚠️ chưa có |
| AC-23 | thẻ có `IMG_0200.JPG` + `IMG_0200.WAV`, `MVI_0201.MP4` + `MVI_0201.THM` | Import cả mẻ | đích có `.JPG` + `.WAV` cùng tên mới, `.MP4` riêng một ô; 0 file `.THM`, 0 file MISC | ⚠️ chưa có |
| AC-24 | công tắc XMP trong Settings tắt; preset Creator `Linh Pham` | Import 3 ảnh | 3 file `.xmp` có Creator; ảnh khác trong nguồn có thêm 0 file `.xmp` | ⚠️ chưa có |
| AC-25 | sheet Export (07b) và inspector Import | mở lưới chip token của mỗi màn | cùng 8 chip, cùng chữ: Original Name · Original Number · Date · Time · Camera · Lens · Sequence · Text | ✅ Export: `FileNameTokenGridTests.eightChipsSameWords` + `.chipsAppendToTheTemplate`, `FileNameTemplateTests.originalNumberTakesTrailingDigits` + `.sequenceKeepsWidth`; `ShotDexUITests/scripts/file-name-chips-iphone.json` (iPhone 17, iOS 26.5 sim): dump 8 chip "Insert …" 3 một hàng, chạm Text → `_Text` bôi chọn. Nửa Import: inspector dùng cùng `FileNameTokenGrid` — chứng minh ở task 13 khi màn có |
| AC-26 | iPad iPadOS 26.5, mẻ 811 ảnh ở 200 | về màn Home 60 s rồi mở lại | mẻ chạy tiếp, > 200 ảnh đã kiểm; trước 26 (18.6): mẻ dừng, 0 tên tạm, có **Import Remaining** | ⚠️ chưa có |
| AC-27 | iPhone 402×874 và Duo ngoài 466×678, đầu đọc USB-C có thẻ | chạm hàng thẻ → Import 3 ảnh | 3 ảnh vào nguồn thư mục đích, SHA-256 = bản trên thẻ; Duo ngoài: mọi control trong x ≤ 366 | ⚠️ chưa có (thẻ giả = thư mục DCIM); đầu đọc USB-C thật: chưa kiểm (cần máy thật) |

**Chưa chứng minh được:** cả 27 AC — chưa có code. Phần cần thẻ, đầu đọc hoặc máy ảnh thật (AC-10 rút thật, AC-20,
AC-27 đầu đọc thật) ghi "chưa kiểm (cần máy thật)" — planboard mac-ipad-v2 Q10. Board iPad dọc, `PH_Ingest`, `DI_Ingest`, `DC_Ingest` chưa vẽ.
