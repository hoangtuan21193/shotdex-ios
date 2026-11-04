# FS-19.08 §6d loop xem kết quả Scan · chạy nhanh hơn — trạng thái

Loop tự chạy (`/loop`, 2026-11-04), làm hết task R1–R12 của [plan](2026-11-04-fs1908-review-scan-and-faster.md). File
này là trí nhớ của loop: mỗi vòng đọc nó trước khi làm, ghi lại sau khi làm.

## Luật mỗi vòng

1. Làm một task theo thứ tự:
   - code;
   - build iOS (`-destination 'id=6E3CE306-B474-4EBD-953B-E7D807BB25BC' -derivedDataPath build/sim`) và `ShotDexMac`
     (`-destination 'platform=macOS' -derivedDataPath build/mac`); file mới dưới `ShotDexMac/` → `Tools/mac-membership`;
   - chạy test liên quan bằng `-only-testing` (không chạy cả bộ, không `Tools/gate` — người dùng 2026-11-04);
   - cho 2 lượt review độc lập, sửa hết những gì chúng tìm ra;
   - task chạm server thì chạy thêm e2e trên SMB ảo (và WebDAV cục bộ cho R11);
   - task UI thì vẽ board trước (đọc lại canvas Mac trước khi sửa, publish), rồi chụp ảnh Mac sáng + tối
     (`-ShotDexDemoLibrary`, `-ShotDexAppearance dark`, `Tools/mac-shot`, mẹo mở lại cửa sổ), so board.
2. Cập nhật 08b (cột "Chứng minh bằng"), plan (trạng thái) và dòng Tiến độ của intent, rồi commit chỉ những file mình
   đổi (`/usr/bin/git commit -- <paths>`; zsh: danh sách đường dẫn dùng mảng).
3. **Không tắt hay xoá SMB ảo** cho tới khi xong R12: `127.0.0.1:4450`, share `photos`, `tester` / `secret`, dữ liệu ở
   `build/smb-share/photos` (ảnh phong cảnh, không mặt người). File thêm vào share để test phải gỡ khi xong
   (test G1/G3 phụ thuộc nội dung share).
4. Không đụng file phiên khác đang sửa: `project.pbxproj`, `AlbumsModel.swift`, `UtilitiesScreen.swift`,
   `Localizable.xcstrings`, `MacSidebar.swift`, `LiquidGlassTabBar.swift`. Không vá `SMBClient` (người dùng 2026-11-04).
5. Không dùng ảnh có mặt người. Hỏi người dùng bằng AskUserQuestion có lựa chọn.

## Task

| Task | Trạng thái | Commit | Ghi chú |
|---|---|---|---|
| R1 | xong | (commit này) | test khoá AC-177…180 (`CommonPhotosReviewTests`, 6 test) + e2e SMB `changedAfterScanOnTheServer`; fake `move` giữ ngày sửa như SMB/WebDAV. Review: thêm ca bản đầu (A) đổi, sidecar, kiểm server; e2e chờ 2.1 s cho share giữ ngày sửa 2 giây |
| R2 | xong | (commit này) | board Mac canvas v100: `MAC_CommonPhotos` (chỉ Same, ô chọn thật có `checked`, kế hoạch `→ Shared/tên` không bị cắt, Already in Shared mờ ảnh không mờ chữ, Move: cột Removes N copies + nút Move 278…, hàng bỏ = Left out from now on, nút Compare khi rê, Left Out ở chân danh sách; tweak `action`, `leftOut`), `MAC_CommonPhotosRun` readyToMove (ô chọn, tên dự kiến, Move 3…, Space to compare), `MAC_CommonPhotosCompare` mới tier D (photo/video/loading/waiting/noPreview/error/threeFolders, Include in Copy, câu lỗi FS-15.01 §3). Review design + UX: sửa hết điểm nên sửa; chưa vẽ: menu chuột phải, trạng thái 0 Same / bỏ hết. Spec §6d thêm Include in Compare, câu chân sheet, đếm theo số chọn |
| R3 | xong | (commit này) | `CommonPhotosScanModel.rows` chỉ Same (bỏ `Row.Status`), `notCheckedCount` sau Scan hỏng; sheet bỏ cột trạng thái, thêm "Not checked N" (có glyph, gộp VoiceOver), nhãn danh sách "Same photos in both folders". Review: race — lỗi tới trước khi callback về main actor thì mất nhóm vừa quyết; giữ `decided` + `foundSoFar` trong lock, đọc lại khi hỏng. Ảnh Mac `build/design/shots/R3/` (chưa có ô chọn/kế hoạch: R4–R5). Chưa chụp trạng thái Scan hỏng |
| R4 | xong | (commit này) | `CommonPhotosDestinationPlan` (luật của runner: cùng tên+cỡ+SHA = already there, còn lại `nextFreeName` dồn theo thứ tự); model `replan()` sau Scan/recut, `landings`, `runCount` (Copy không đếm already there), `isPlanning`; SHA ở đích lấy từ `Gathered.placed` (bộ đã đặt) hoặc cache phiên (cỡ+ngày sửa), chỉ đọc file trùng tên+cỡ; file đọc lỗi = hàng không có plan; helper không plan. Sheet: dòng `→ Shared/tên`, cột Already in / Removes N copies. Review: sửa lỗi đỏ có sẵn (đổi đích lúc đang liệt kê sau khi cắt → quét lại), cancel trước reconnect, sha256 nhạy huỷ, guard scanId. Còn biết: Copy hỏng một ảnh trả lại tên → ảnh sau cùng tên có thể ra tên khác plan; server phân biệt hoa thường có 2 file chỉ khác hoa. Hai test Incremental chập chờn vì plan nền đọc Shared → helper chờ `isPlanning` |
| R5 | xong | (commit này) | `leftOut` (SHA, sống qua quét lại trong sheet; R6 lưu DB), `setIncluded`, `includedPhotos`, `runCount`/`selectableCount`/`runBytes` (Copy không tính hàng đã có), `makeRun` chỉ hàng chọn, `canRun` = còn ảnh chọn (hàng đã có vẫn chạy để ghi nhận + sidecar); lượt gom nền tính `includedPhotos`. Sheet: ô chọn (VoiceOver: tên + Included/Left out), "N of M selected" cả bộ đã gom, chân Copy "Unchecked photos are not copied." (đổi thành 'stay out of this set' ở R6), Move "Verified in Shared, then removed from …", "Nothing selected…", nút Move N…; DEBUG `-ShotDexCommonPhotosLeaveOut`. Chưa: Space bật tắt nhóm + menu chuột phải (R6/R8) |
| R6 | xong | a9ad20b2 | v57 `common_photo_left_out` (setKey+sha PK, connectionId index, tên+cỡ để hiện) + `CommonPhotosLeftOutStore` (include xoá theo khối 500); xoá ở `WatchStore.remove` và `FileServerStore.delete`; Clear Index không đụng. Model: `leftOut` (lưu ngay khi bỏ), `leftOutBefore` (bỏ từ trước: mục Left Out, không thành hàng, không chiếm tên trong plan), `leftOutPending` (chưa có đích: lưu khi chọn đích), đổi folder/đích nạp lại; `include()`. Sheet: mục Left Out dưới danh sách, Include có tên cho VoiceOver, menu chuột phải Leave Out/Include. Board chỉnh theo, canvas v102. DEBUG `-ShotDexCommonPhotosShowLeftOut`; chụp cần `-ShotDexDemoDatabase r6.sqlite`. §8: bộ chưa bật Keep gathering giữ Left Out tới khi xoá connection |
| R7 | chưa | | |
| R8 | chưa | | |
| R9 | chưa | | |
| R10 | chưa | | |
| R11 | chưa | | |
| R12 | chưa | | |
