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
| R1 | chưa | | |
| R2 | chưa | | |
| R3 | chưa | | |
| R4 | chưa | | |
| R5 | chưa | | |
| R6 | chưa | | |
| R7 | chưa | | |
| R8 | chưa | | |
| R9 | chưa | | |
| R10 | chưa | | |
| R11 | chưa | | |
| R12 | chưa | | |
