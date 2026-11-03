# FS-19.08 §6c loop chỉ ảnh mới · tự gom — trạng thái

Loop tự chạy (`/loop`, 2026-11-03), làm hết task G1–G10 của [plan](2026-11-03-fs1908-new-only-and-gather.md). File này là
trí nhớ của loop: mỗi vòng đọc nó trước khi làm, ghi lại sau khi làm.

## Luật mỗi vòng

1. Làm một task theo thứ tự:
   - code;
   - build iOS (`-destination 'id=6E3CE306-B474-4EBD-953B-E7D807BB25BC' -derivedDataPath build/sim`) và `ShotDexMac`
     (`-destination 'platform=macOS' -derivedDataPath build/mac`); file mới dưới `ShotDexMac/` → `Tools/mac-membership`;
   - chạy test liên quan bằng `-only-testing` (không chạy cả bộ);
   - cho 2 lượt review độc lập, sửa hết những gì chúng tìm ra;
   - task chạm server thì chạy thêm e2e trên SMB ảo;
   - task UI thì vẽ board trước (đọc lại canvas Mac, publish), rồi chụp ảnh Mac sáng + tối
     (`-ShotDexDemoLibrary`, `-ShotDexAppearance dark`, `Tools/mac-shot`), so board.
2. Cập nhật 08b (cột "Chứng minh bằng"), plan (trạng thái) và dòng Tiến độ của intent, rồi commit chỉ những file mình
   đổi (`/usr/bin/git commit -- <paths>`).
3. **Không tắt hay xoá SMB ảo** cho tới khi xong G10: `127.0.0.1:4450`, share `photos`, `tester` / `secret`, dữ liệu ở
   `build/smb-share/photos` (ảnh phong cảnh, không mặt người). Đường dẫn client SMB bắt đầu bằng `photos/`.
4. Không đụng file phiên khác đang sửa: `project.pbxproj`, `AlbumsModel.swift`, `UtilitiesScreen.swift`,
   `Localizable.xcstrings`, `MacSidebar.swift`.

## Task

| Task | Trạng thái | Commit | Ghi chú |
|---|---|---|---|
| G1 | xong | (xem git log) | v52 `common_photo_scan_records` (SHA + khoá ngày chụp theo connection + đường dẫn; `""` = đầu file không có khoá); quét Copy tin SHA đã nhớ ở mọi folder và bỏ đọc lại; quét Move giữ luật cũ; đổi sang Move trong/sau quét → bỏ kết quả, `canRun` chặn; prune theo khoảng `folder/`…`folder0` trước khi lưu; lưu theo lô 1.000, giữ 180 ngày, xoá khi xoá connection; hash 0 byte = lệch. e2e SMB ảo: lần quét 2 không đọc byte |
| G2 | xong | (xem git log) | khoá bộ tính từ connection + folder (sắp) + đích, không cần cột; `CommonPhotosStore.gathered` đọc riêng cột `sources` của mục Copied/Moved/Skipped (gồm lượt `finishing`); quét cắt listing theo cỡ có file chưa thấy, rồi bỏ ảnh mà mọi bản đã thấy; chọn/đổi đích sau hay trong lúc quét → cắt lại từ kết quả đầy đủ (`allPhotos`, `recut`, `isCutting` chặn chạy); listing đã cắt mà đổi đích → quét lại. **G4 phải có:** câu trống "Nothing new since …" + Scan Everything khi bộ gom hết; số ảnh đã ẩn; câu báo khi kết quả bị bỏ (đổi đích, Copy→Move); Scan Everything là nút quét luôn, không phải công tắc. Ảnh mất ở Shared → G3 |
| G3 | chưa | | |
| G4 | chưa | | |
| G5 | chưa | | |
| G6 | chưa | | |
| G7 | chưa | | |
| G8 | chưa | | |
| G9 | chưa | | |
| G10 | chưa | | |
