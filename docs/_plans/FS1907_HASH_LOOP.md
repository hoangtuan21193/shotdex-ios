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
| H2 | chưa | | |
| H3 | chưa | | |
| H4 | chưa | | |
| H5 | chưa | | |
| H6 | chưa | | |
| H7 | chưa | | |
| H8 | chưa | | |
