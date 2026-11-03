# FS-19.08 §6b loop hoàn tác — trạng thái

Loop tự chạy (`/loop`, 2026-11-03) làm hết task U1–U9 của [plan](2026-11-03-fs1908-undo.md). File này là trí nhớ của
loop: mỗi vòng đọc nó trước, ghi lại sau.

## Luật mỗi vòng

1. Làm một task:
   - code;
   - build iOS (`-destination 'id=6E3CE306-B474-4EBD-953B-E7D807BB25BC' -derivedDataPath build/sim`) và
     `ShotDexMac` (`-destination 'platform=macOS' -derivedDataPath build/mac`);
   - chạy test liên quan bằng `-only-testing`, không chạy cả bộ;
   - **2 lượt review độc lập**, sửa hết những gì chúng tìm ra;
   - task chạm server thì chạy e2e trên SMB ảo;
   - task UI thì vẽ board trước, rồi chụp `Tools/mac-shot` sáng + tối, xem ảnh, so với board.
2. Cập nhật 08b (cột "Chứng minh bằng"), plan (trạng thái) và dòng Tiến độ của intent, rồi commit chỉ những file mình
   đổi (`/usr/bin/git commit -- <paths>`).
3. **Không tắt hay xoá SMB ảo** cho tới khi xong U9. Cách chạy và dữ liệu thử ở [FS1908_LOOP.md](FS1908_LOOP.md) mục SMB ảo
   (`127.0.0.1:4450`, share `photos`, `tester` / `secret`).

## Task

| Task | Trạng thái | Commit | Ghi chú |
|---|---|---|---|
| U1 | xong | (xem git log) | v47: `undoOf`, `sidecarPlaced`/`sidecarSHA256`, bảng `common_photo_history_moves`; store `startUndo`, `recentRuns`, dọn trong `markState`; runner ghi sidecar trước khi ghi |
| U2 | xong | (xem git log) | `CommonPhotosUndoer` (Copy) + `CommonPhotosServerChecks` tách từ runner; mọi bản nguồn kiểm lại sau khi để riêng; mọi lỗi sau khi để riêng thì trả file về tên cũ (detached); sidecar chỉ xoá khi còn bản nguồn cùng byte; `finishUndo` ghi 2 hàng một transaction |
| U3 | xong | (xem git log) | Undo Move: trả B bằng file part, đổi chỗ A về (bị từ chối thì ghi lại); đích xoá cuối, khi mọi bản đã về và kiểm lại (mtime hoặc SHA); `destinationWasThere` (cột mới trong v47, sửa tại chỗ vì chưa ship) thay cho việc đọc reason `alreadyThere`; hàng Move Failed còn bản đã xoá cũng hoàn tác được |
| U4 | xong | (xem git log) | chỉ test: client giả có `failOnWrite`/`failOnRead`; quét mọi điểm lỗi (ghi trước/sau, đọc) × Move/Copy × share × sidecar; Resume sau khi dừng ở ảnh 4 |
| U5 | chưa | | |
| U6 | chưa | | |
| U7 | chưa | | |
| U8 | chưa | | |
| U9 | chưa | | |

## Ghi chú cho các task sau (từ review U1)

- **U2/U3**: mỗi ảnh hoàn tác xong phải ghi `.undone` lên **hàng gốc** (và `isRemoved = false` cho bản đã trả về).
  Nếu không, một lượt hoàn tác bị Stop rồi bấm Undo lại sẽ làm lại những ảnh đã trả. `startUndo` chỉ lọc theo
  `isUndoable`.
- **U2**: một sidecar dùng chung cho hai ảnh (`IMG_1.JPG` + `IMG_1.MOV`) chỉ được ảnh đầu ghi `sidecarPlaced`. Undo
  Selected ảnh đầu không được xoá `.xmp` khi một hàng khác của lượt gốc, chưa hoàn tác, vẫn dùng nó.
- **U2/U8**: `CommonPhotosRunner.run` từ chối lượt hoàn tác (`notResumable`). Resume, banner và Activity
  (`MacCommonPhotosRuns.leftOver`/`refreshFoot`, `LongRunningJob` Resume) phải chuyển lượt `undoOf != nil` sang
  undoer.
- **U8**: các chỗ đếm (`MacCommonPhotosRunWindow` counts, `MacActivityWindow.readStore`) chưa tính `.undone`.
- Một item chỉ có một chỗ ghi sidecar. Ảnh copy lại sang tên mới khi Resume sẽ làm sidecar cũ thành mồ côi: undo để
  lại sidecar đó. Đây là hướng an toàn nên chấp nhận.
