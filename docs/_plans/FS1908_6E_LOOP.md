# FS-19.08 §6e loop — trạng thái

Loop tự chạy (`/loop`, 2026-11-05, người dùng: "loop t0 đến t11, task nào cũng phải review 2 lần và chụp ảnh màn hình
để check ui"), làm hết T0–T11 của [plan](2026-11-05-fs1908-6e-dated-organize-fileinfo.md). File này là trí nhớ của
loop: mỗi vòng đọc nó trước khi làm, ghi lại sau khi làm.

## Luật mỗi vòng

1. Làm **một** task, theo thứ tự plan mục 5:
   - task có UI: vẽ board trước. Đọc lại từ canvas Mac (<https://claude.ai/artifact/HEj8sG21jAEWd7Mgvuyxgj>, `read`
     chỉ url rồi theo `path`) trước khi sửa; sửa trong `docs/design/mac/project/`; publish lên canvas;
   - code. Logic vào Domain/Data, view Mac mỏng. File mới dưới `ShotDexMac/` → `Tools/mac-membership`;
   - build iOS (`-destination 'id=6E3CE306-B474-4EBD-953B-E7D807BB25BC' -derivedDataPath build/sim`) và `ShotDexMac`
     (`-destination 'platform=macOS,arch=arm64' -derivedDataPath build/mac`). `build/sim` bị khoá = phiên khác đang
     build: chờ, đừng chạy chen;
   - test liên quan bằng `-only-testing:'ShotDexTests/Class/method()'` (không cả bộ, không `Tools/gate`);
   - **review 2 lần**: 2 reviewer độc lập (code + UX/UI), sửa hết những gì chúng tìm ra rồi mới qua;
   - **chụp ảnh UI** Mac sáng + tối (`-ShotDexDemoLibrary`, `-ShotDexAppearance dark`, `Tools/mac-shot`), xem từng ảnh,
     so board (`Tools/design-board render` + compare khi có dump). Task không đổi UI: chụp màn Mac mà task chạm tới
     (sheet, cửa sổ log) để chắc không vỡ; thật sự không có màn nào thì ghi lý do. **Không bao giờ chụp thư viện thật**,
     không ảnh có mặt người. Ảnh vào `build/design/shots/6E-Tn/`;
   - task chạm server: e2e trên SMB ảo `127.0.0.1:4450` (share `photos`, `tester` / `secret`, cách bật ở
     `FS1908_LOOP.md`) và WebDAV wsgidav `127.0.0.1:8096`. NAS người dùng: chỉ đọc, và chỉ ở T11; ghi lên NAS phải hỏi.
2. Cập nhật 08b (cột "Chứng minh bằng"), §6e nếu kết quả đổi điều spec nói, plan (trạng thái), dòng Tiến độ của ba
   intent, dòng task dưới đây; commit chỉ file mình đổi (`/usr/bin/git commit -- <paths>`; zsh: mảng).
3. Không đụng file phiên khác đang sửa khi chúng còn thay đổi chưa commit: `project.pbxproj`, `MacSidebar.swift`,
   `Localizable.xcstrings`, `LiquidGlassTabBar.swift`, board `docs/design/duo/**`, `REVIEW_QUEUE.md`. Task cần một file
   trong đó mà nó còn bẩn → làm phần khác của task, ghi lại, quay lại sau.
4. Hỏi người dùng bằng AskUserQuestion có lựa chọn. Trước T2 chạy `challenger` lên plan. Hết task thì dừng loop.

## Task

| Task | Trạng thái | Commit | Ghi chú |
|---|---|---|---|
| T0 | xong | (commit này) | Canvas v127. `MAC_CommonPhotos`: hàng Organize dưới Save to (nút "Same as Source · videos together…" + "e.g. 2025/10/12/DSC04388.ARW"), câu "Changing this affects new photos only…" chỉ khi Organize khác lượt trước (tweak `organizeChanged`), ô **Quick check** một dòng + tooltip nói cái giá, câu cam "does not keep file dates" ngay dưới hàng Save to · Action, hàng kế hoạch ghi đích đủ (bỏ tiền tố Shared/) + nhãn Quick, "Same 282 · 214 quick", trạng thái mới `readingDates`, `quickThenMove` (kết quả bị bỏ, nút Scan). Sheet 640×640: **MAC_STYLE thêm ngoại lệ** cho sheet có danh sách kết quả (560 chỉ còn 1–2 hàng — cả hai review chỉ ra). `MAC_BackupOrganize`: tweak `from=commonPhotos` (Same as Source, câu nói folder đầu, không Folder Names/popover, nền trình duyệt NAS Home). `MAC_CommonPhotosRun`: rộng 1040, cột Check (Quick/Full) + File info (Kept/Dates not kept/Restored), Restore File Info… (bật khi còn hàng chưa Kept, trạng thái `restored`), tên CSV vào tooltip. **Không vẽ menu Levels mở** (luật người dùng: không board menu mở) — review design đề nghị, bỏ qua có lý do. `Tools/design-board render --props` để render từng tweak. §6e + AC-193/208/214 sửa chữ theo review UX. Code (sheet hiện 560) đổi ở T7/T10. Ảnh `build/design/shots/6E-T0/` |
| T1 | chưa | | spike ADS SMB + WebDAV PROPPATCH |
| T2 | chưa | | AC-211, 215, 218 |
| T3 | chưa | | AC-212, 213, 214 |
| T4 | chưa | | AC-216 |
| T5 | chưa | | AC-217 |
| T6 | chưa | | AC-219 |
| T7 | chưa | | AC-193…197 |
| T8 | chưa | | AC-198…200 |
| T9 | chưa | | AC-204…207 |
| T10 | chưa | | AC-202, 203, 208, 209, 210 |
| T11 | chưa | | `/verify`, AC-201 đo NAS |
