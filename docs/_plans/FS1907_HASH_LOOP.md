# FS-19.07 §12 loop băm dùng chung — trạng thái

Loop tự chạy (`/loop`, 2026-11-03), làm hết task H1–H8 của [plan](2026-11-03-fs1907-shared-hashing.md). File này là trí
nhớ của loop: mỗi vòng đọc nó trước khi làm, ghi lại sau khi làm.

## Luật mỗi vòng

1. Làm một task theo thứ tự:
   - code;
   - build iOS (`-destination 'id=6E3CE306-B474-4EBD-953B-E7D807BB25BC' -derivedDataPath build/sim`) và `ShotDexMac`
     (`-destination 'platform=macOS' -derivedDataPath build/mac`);
   - chạy test liên quan bằng `-only-testing`;
   - cho 2 lượt review độc lập, sửa hết những gì chúng tìm ra;
   - task chạm server thì chạy thêm e2e trên SMB ảo;
   - task UI thì vẽ board trước, rồi chụp ảnh sáng + tối.
2. Cập nhật 07b (cột "Chứng minh bằng"), plan (trạng thái) và dòng Tiến độ của intent, rồi commit chỉ những file mình
   đổi (`/usr/bin/git commit -- <paths>`).
3. **Không tắt hay xoá SMB ảo** cho tới khi xong H8. Cách chạy ở [FS1908_LOOP.md](FS1908_LOOP.md) mục SMB ảo
   (`127.0.0.1:4450`, share `photos`, `tester` / `secret`).
4. CloudKit thật cần thiết bị: test qua kênh giả. AC cần thiết bị ghi "một phần".

## Task

| Task | Trạng thái | Commit | Ghi chú |
|---|---|---|---|
| H1 | xong | (xem git log) | v48 `sharedFrom`, `hash_index_segments`, `distrusted_hash_devices`; origin `shared`/`ledger`; `distrust`/`accepts` |
| H2 | xong | (xem git log) | cờ `everything` trong 2 câu ứng viên (thứ tự `indexedAt`, bỏ file hỏng 5 lần); Mac bật theo `indexShare != nil && sharesIndex`; ảnh PhotoKit không lấy được rời hàng đợi; file không rõ cỡ tính 2 GB; spike S9 (Photos có giữ bản tải không) |
| H3 | xong | (xem git log) | sổ `.shotdex/hash-index/` ở gốc nguồn; v49 `hash_index_lines` (giữ dòng đã đọc, đọc theo lô key); chỉ nối server khi có ứng viên hay nợ sổ; một đoạn khi đọc xong nguồn (hoặc ≥ 5.000 dòng); dòng phải đúng máy tên đoạn, SHA viết thường; `recordedAt` = lúc băm; lỗi server lúc nối → `stoppedBy` như cũ; xoá nguồn xoá sổ |
| H4 | xong | (xem git log) | `OnServerSMBTests.ledgerSavesDownloads`: Mac ghi sổ trên SMB ảo, máy kia lấy 3/3 từ sổ, 0 lần băm; đường dẫn phải có tiền tố share `photos/`. Sai share làm rescan treo > 10 phút (`connectShare` không timeout) → REVIEW_QUEUE |
| H5 | xong | (xem git log) | v50 `shared_photo_hashes`/`shared_server_hashes` + `copy_files.sharedAt`; record `PhotoFileHash`/`ServerFileHash` (tên = SHA các phần); khớp Photos ngay sau khi liệt kê (`adoptListed`), trước khi chọn file tải; server khớp `ServerIdentity.key` (WebDAV thêm TLS) + path; pull chờ tối đa 10 s, push 5 lô/lượt, dừng khi huỷ; gửi `hashedAt` thật; hash máy khác không đè hash có sẵn. Sửa luôn lỗi có sẵn: EXIF outbox so byte JSON không sort key (`anUnchangedReadIsNotQueuedAgainAfterPush` đỏ) |
| H6 | xong | (xem git log) | `SharedHashAuditPass` sau vòng băm, trước merge; mẫu K=10/máy lấy từ cửa sổ quanh một rowid ngẫu nhiên (không `ORDER BY random()` cả bảng), chỉ file ≤ 1 GB, đang làm khớp, đọc được lúc này (Wi‑Fi/sạc, nguồn mở), ảnh Photos có listing mới; lệch → `recordMismatch` (giữ SHA đọc + bỏ tin trong một giao dịch, reset `triedAt`/`attempts`) rồi băm lại ngay trong lượt; `caughtDevices` cho H7, xoá theo từng máy; đọc server có timeout 180 s, luôn ngắt. Hoãn vào REVIEW_QUEUE: merge đã làm trên SHA bị bỏ, lệch đồng hồ máy gửi, file NAS đổi sau listing |
| H7 | chưa | | |
| H8 | chưa | | |
