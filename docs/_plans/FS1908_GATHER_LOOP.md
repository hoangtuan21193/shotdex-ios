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
| G3 | xong | (xem git log) | quét và mỗi lần cắt lại liệt kê folder chung (phẳng, tên thường → các cỡ); mục đã gom mà bản ở đích mất / khác cỡ / không có đường dẫn đích → không tính đã gom; folder chưa có → `[]`; lỗi liệt kê → nối lại 1 lần rồi coi như chưa gom gì (Copy vẫn bỏ qua bản cùng byte); quét lại hủy lần cắt cũ. Test helper `copyAll` đặt file thật vào Shared. e2e SMB ảo `goneFromSharedOnTheServer` (scratch `photos/Shared/e2e-g3-*`, đã dọn) |
| G4 | xong | (xem git log) | board `MAC_CommonPhotos` tweak `state` (first/again/nothingNew, ô Keep gathering vẽ sẵn cho G5), `MAC_CommonPhotosRun` + `MAC_Activity` thêm Run Again… (canvas Mac v87–v88); sheet: tiêu đề "N new photos…", dòng Last gathered + Scan Everything (một lần quét), "Nothing new since …", câu báo khi kết quả bị bỏ, nút chỉ có động từ khi 0; Run Again… → `runAgainRequest` → Library (mở lại nếu đóng, `WindowGroup(id: "library")`) → sheet quét ngay; đếm ảnh đã gom theo SHA. DEBUG `-ShotDexCommonPhotosRunAtOnce` + `-ShotDexDemoDatabase resumeg4.sqlite` để chụp; ảnh `build/design/shots/G4/`. **Ô Keep gathering chưa có trong code** (G5) |
| G5 | xong | (xem git log) | v53 `common_photo_watches` (một hàng mỗi bộ, `isOn`, `checkedAt`, `waiting`, `stoppedBecause`); `CommonPhotosWatchStore` (ghi từ lượt gom chỉ khi `isOn = 1`; hàng đọc không được → hiện là dừng `cannotGather`); `CommonPhotosGatherPass` (điện ngoài + mạng không tính tiền → khoá kết nối → kiểm folder, "mất" phải được folder cha xác nhận → quét chỉ ảnh mới trên cùng phiên → `onFound`); huỷ = không ghi gì; lỗi DB không còn bị coi là "chưa gom". e2e SMB ảo `passOnTheServer`. **G9 cần:** giữ Task của lượt để huỷ khi thoát; một lượt một lúc mỗi bộ (app ↔ helper, lease); cấp `onPower` = `PowerMonitor.isCharging`. **Ô Keep gathering trong sheet:** làm ở G6 |
| G6 | xong | fb5459dd | v54 `watchId`/`day` trên `common_photo_runs`; `CommonPhotosAutoGather` (bộ Copy: `makeRun` → `gatherIntoDay`; bộ Move chỉ tìm, G7); một lượt mỗi bộ mỗi ngày (lịch gregorian), CSV `ShotDex Common Photos <ngày> auto.csv` ghi đè một tên; lượt của ngày đang chạy/tạm dừng/đang hoàn tác → `DayRunBusy`, ảnh chờ lượt sau; ngày bị Stop → lượt mới; ảnh đã hoàn tác trong lượt tự gom không chép lại, không đếm là đã gom; giữ 20 nhóm theo `updatedAt`; sheet: ô Keep gathering (đọc theo khoá bộ, lưu sau khi lượt chạy bắt đầu, lỗi lưu báo ra). Ảnh `build/design/shots/G6/`. **G9 cần:** gọi `CommonPhotosAutoGather` rồi chạy `runId` bằng `MacCommonPhotosRuns`; tiêu đề Activity " · Nov 3" đã có |
| G7 | xong | 000aa866 | trạng thái `ready` (không phải unfinished: không Resume/Stop/Discard/undo, không bị prune); `gatherIntoDay(ready:)` → một lượt ready mỗi bộ, lượt sau thay danh sách pending, `updatedAt` luôn tăng; lượt không thấy gì → `dropReady(watchId:)`; lọc theo action; `confirmReady(asOf:)`; Stop Gathering / xoá connection / Remove from List → `dropReady`; Activity "Ready to move N" + Move N… · Show Log · Remove from List…; cửa sổ log header/footer ready + hộp hỏi; `MacCommonPhotosNotices` (xin quyền khi bật Move, click mở cửa sổ, giữ click tới khi có `runs`). DEBUG `-ShotDexCommonPhotosGatherReady [-ShotDexCommonPhotosAskMove] [-ShotDexOpenActivity]` + `-ShotDexDemoDatabase readyg7.sqlite`; ảnh `build/design/shots/G7/`; canvas v89–v90. **G9 cần:** gọi `CommonPhotosAutoGather` với `readyToMove: MacCommonPhotosNotices.readyToMove`, sau mỗi lượt làm mới `runs` (generation) để Activity/foot thấy lượt ready |
| G8 | chưa | | |
| G9 | chưa | | |
| G10 | chưa | | |
