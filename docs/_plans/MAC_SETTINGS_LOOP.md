# Settings Mac loop (FS-18.04 §3) — trạng thái

Loop tự chạy (`/loop`, 2026-11-04), làm hết S0–S13 của [plan](2026-11-04-mac-settings-panes.md). File này là trí nhớ
của loop: mỗi vòng đọc nó trước khi làm, ghi lại sau khi làm.

## Luật mỗi vòng

1. Làm **một** task, theo thứ tự trong plan mục 5:
   - task UI: vẽ board trước. Đọc lại file từ canvas Mac (<https://claude.ai/artifact/HEj8sG21jAEWd7Mgvuyxgj>, `read`
     theo url rồi theo `path`) trước khi sửa, sửa trong `docs/design/mac/project/`, publish lên canvas;
   - code. Logic vào Domain/Data dùng chung, view Mac mỏng. File mới dưới `ShotDexMac/` → `Tools/mac-membership`;
   - build iOS (`-destination 'id=6E3CE306-B474-4EBD-953B-E7D807BB25BC' -derivedDataPath build/sim`) và `ShotDexMac`
     (`-destination 'platform=macOS,arch=arm64' -derivedDataPath build/mac` — `Tools/mac-shot` tìm app ở `build/mac`). `build/sim` bị khoá = phiên khác
     đang build: chờ, đừng chạy chen;
   - chạy test liên quan bằng `-only-testing` (không chạy cả bộ, không `Tools/gate`);
   - **review 2 lần**: 2 lượt reviewer độc lập (code + UI/UX), sửa hết những gì chúng tìm ra rồi mới qua;
   - **chụp ảnh UI** sáng + tối (`-ShotDexDemoLibrary`, `-ShotDexAppearance dark`, `-ShotDexSettingsPane <tên>`,
     `Tools/mac-shot`, mẹo mở lại cửa sổ), xem từng ảnh, so board (`Tools/design-board render` + compare khi có dump).
     **Không bao giờ chụp thư viện thật**;
   - task chạm server: e2e trên SMB ảo `127.0.0.1:4450` (share `photos`, `tester` / `secret`).
2. Cập nhật FS-18.06 (cột "Chứng minh bằng"), plan (trạng thái), dòng Tiến độ của intent, dòng task dưới đây; commit chỉ
   file mình đổi (`/usr/bin/git commit -- <paths>`; zsh: mảng).
3. Không đụng file phiên khác đang sửa khi chúng còn thay đổi chưa commit: `project.pbxproj`, `MacSidebar.swift`,
   `Localizable.xcstrings`, `LiquidGlassTabBar.swift`, `RuleBuilderSections.swift`. Task cần một file trong đó mà nó
   còn bẩn → làm phần khác của task, ghi lại, quay lại sau.
4. Không dùng ảnh có mặt người. Hỏi người dùng bằng AskUserQuestion có lựa chọn. Hết task thì dừng loop.

## Task

| Task | Trạng thái | Commit | Ghi chú |
|---|---|---|---|
| S0 | xong | (commit này) | 8 board, canvas v109. Hàng chưa có tính năng: nhãn `label3`, control 0.45 và ở trạng thái tắt, chữ phụ "Available in a later version" giữ độ tương phản (review design: mờ cả hàng thì chữ lý do chỉ ~1.5:1); AI, Editing mờ cả pane + một dòng chú thích. Sources: bỏ `.xmp`, header ghi "Indexing 22%" (review UX: tiến độ phải thấy không cần cuộn), tweak `indexing`, `battery` (paused/none). Servers: bỏ limit riêng, tweak `localNetworkOff`. `MAC_SourceIndexing`: chân sidebar xếp chồng index trên Common photos, tweak `indexing` cho trạng thái xong; bỏ sao/cờ và chữ "cull, rate" (cull đã bỏ). Giữ "Common photos" (chữ thường) như chuỗi app và board Activity. Board Mac khác (Main, Cull…) còn vẽ sao/cờ: ngoài task này |
| S1 | xong | (commit này) | `MacSettingsPane` (6 tab, 720 × 640, thân cuộn, DEBUG `-ShotDexSettingsPane <tên>` cùng `-ShotDexSection settings`); `MacLaterSettingsRow` (tiêu đề `.secondary`, lý do caption, switch tắt, disabled) cho 4 hàng General; `MacLaterPane` cho AI, Editing (một dòng chú thích, control disabled không có giá trị chọn — review: giá trị mẫu trong control trơ dễ bị hiểu là cài đặt thật —, `accessibilityHidden`, chữ giữ độ tương phản). AC-69 sửa theo board (AI/Editing một dòng chú thích, không chữ phụ từng hàng), AC-59 ghi rõ 640 là thân pane. Tab đang chọn xanh là chrome macOS (không đổi được bằng `.tint`). Nền Settings trắng thay vì xám board: chrome macOS. Sources/Servers/Cameras còn trống tới S4–S12; ảnh `build/design/shots/S1/` |
| S2 | một phần | (commit này) | AC-70 xong: `IndexStatusLine` (Domain: preparing / indexing / upToDate, số ít-nhiều, `format: .number`, "of originals", "indexed just now"), `LibraryQueries.indexSummaryCounts()` (file riêng: chỉ dòng `indexed`/`noExif`, ảnh và video theo `PHAssetMediaType`), `MacSourcesSettings` + `MacIndexSettingsSection` (đếm lại mỗi 500 lần đọc, `TimelineView` 30 s cho "… ago", VoiceOver gộp, thanh ẩn khỏi VoiceOver), `MacDependencies.library` (một `LibraryModel` cho mọi cửa sổ Library — review: mở lại cửa sổ lúc đang index tạo model thứ hai, Settings đọc model rảnh). DEBUG `-ShotDexIndexPreview a/b`. Sửa luôn warning Swift 6 `downloadedPixels` (R9). Board Sources đổi chữ theo app, canvas v110. **AC-71 (chân sidebar) chưa làm**: `MacSidebar.swift` còn bẩn bởi phiên khác — làm khi sạch. Đã lỡ sửa `LibraryQueries.swift` (phiên khác đang bẩn) rồi gỡ ra ngay, chuyển sang file riêng |
| S3 | xong | (commit này) | `ThumbnailInfoFields` (Domain: 8 trường, key và mặc định của lưới iOS — test so thẳng với `GridMetadataDisplayOptions`; File Name, Capture Time là key mới của Mac; `bool(forKey:)` để tham số khởi chạy "YES" cũng đọc được; `fitted` bỏ trọn trường cuối; `room` trừ icon server) + `MacThumbnailSettings` (badge, lưới checkbox 3 cột, Actual / Full-Frame Equivalent). Ô lưới Mac: dòng caption (tên file · giờ, cắt đầu tên để giữ giờ), chữ có bóng, nền tối 46pt khi có caption; đổi cài đặt chỉ vẽ lại chữ (review: tải lại cả ô làm nháy ảnh). Review sửa: lỗi đỏ dòng thông tin bị cắt vì ràng buộc với icon server luôn bật. Board General: badge bật, File Name tắt, bỏ câu Zoom In (Mac chưa có zoom ô), canvas v111. Chụp bằng tham số `-display.* YES/NO` (không ghi đè cài đặt thật). Segmented control xanh: chrome macOS |
| S4 | xong | (commit này) | `MacPhotoSourcesSection` (`MacSourceRows.swift`): hàng nguồn (ô màu, tên + nhãn This Mac/External/Server/Photos, chấm trạng thái), Manage Access…, Re-index, Remove… (hỏi lại, câu theo nơi file nằm, số ít/0 ảnh), Grant Access… (sheet NSOpenPanel mở ở chỗ cũ). `SourcesModel.remove` (ghi ngoài main actor, báo lỗi) + `grantAccess` + `lastKnownPath`; một lượt đọc một lúc (khoá nút các hàng khác, chặn bấm đúp). **Lỗi cũ tìm ra**: bookmark folder trên Mac sandbox không có security scope → mở lại app là mất quyền; `SourceBookmark` tạo/đọc `.withSecurityScope`, bookmark cũ vẫn đọc được. `FolderSourceRoots.forget` đóng scope khi gỡ hoặc cấp lại. Bỏ tổng "items" trên tiêu đề (đếm trùng, lệch Index), tiêu đề chỉ ghi "Indexing 22%" khi đang chạy; board theo, canvas v112. DEBUG `-ShotDexDemoSources` (file riêng `MacDemoSources.swift` vì `MacDemoLibrary.swift` đang bẩn bởi phiên khác). Chưa: dòng đường dẫn · ổ đĩa như board (cần đọc bookmark mỗi hàng); "items" vs "photos" lệch chữ giữa hàng và Index (chữ dùng chung với iOS) |
| S5 | chưa | | |
| S7 | chưa | | |
| S8 | chưa | | |
| S9 | chưa | | |
| S10 | chưa | | |
| S11 | chưa | | |
| S12 | chưa | | |
| S13 | chưa | | |
