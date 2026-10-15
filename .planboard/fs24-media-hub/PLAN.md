# FS-24 Media hub — plan thực thi (chốt spec và design, trước /plan)

> Chốt ngày 2026-10-16, sau 3 vòng · nguồn: .planboard/fs24-media-hub/plan.json · lý do: DECISIONS.md

## Nguyên tắc
- Làm theo thứ tự; mỗi task xong thì tick và chạy phần "Kiểm tra".
- Cần đi chệch một quyết định đã chốt: dừng lại, hỏi người dùng.
- Chưa code tính năng: code chỉ sau `/plan FS-24` được duyệt, FS-23 đóng, `Tools/gate` xanh.

## Việc cần làm

### 1. Sửa spec FS-24 theo quyết định
- [ ] **1.1 Thay 28 dòng ⚠️ CẦN QUYẾT bằng quyết định đã chốt** — `docs/02-functional-spec/FS-24-media-hub/*.md`
  - Xong khi: không còn "CẦN QUYẾT"; mỗi chỗ ghi "Chốt 2026-10-16 (D#/A#)"
  - Kiểm tra: `grep -rn "CẦN QUYẾT" docs/02-functional-spec/FS-24-media-hub`
- [ ] **1.2 AC mới/sửa:** D2 công tắc Settings › Playback "Movie Audio in Background" (mặc định bật); D7 hộp hỏi Originals (full resolution) / Viewing Copies (2732 px, HEIC) có dung lượng, mỗi lần Keep ảnh Photos; D8 luật Smart Album Source, Kept; D9 ô Statistics không số; D10 iPhone 8 thẻ; D11 Clear Listening History…; D5 hộp xoá hệ thống; D6 Remove from iPhone; A8 Show As — `14*-acceptance-criteria.md`
- [ ] **1.3 Tài liệu kéo theo:** FS-21.01 §2 (A4), DESIGN.md §6/§8/§9/§13 (A1, A3, A7, A12), NF-03 §2c (A16), FS-06.08 (D8), FS-23 chữ Download → Keep on iPhone / Remove from iPhone (D6)

### 2. Vẽ board còn thiếu trên 4 canvas (A11, A14, A6, D2, D5, D7, D8, D10, D11)
- [ ] **2.1 Music:** Now Playing, Up Next, Lyrics, Sleep Timer, trang album / nghệ sĩ / playlist
- [ ] **2.2 Movies:** Review videos + hộp xoá (D5), Watch History, Subtitles, trang TV Show, sheet Convert, sheet Extract Audio, Show As (A8)
- [ ] **2.3 Settings / Keep:** Playback (D2, D11), hộp Keep Originals / Viewing Copies (D7), Kept detail, nhóm Metadata/Drives/Cache iPhone/Duo (A14)
- [ ] **2.4 Khác:** Music Statistics iPhone 8 thẻ (D10), ô Statistics không số (D9), Smart Album editor có Source/Kept (D8), Mac menu Controls (A6)
  - Xong khi: render sáng + tối không lỗi, đã publish, tên board ghi vào FS-24

### 3. Spike trước /plan
- [ ] **3.1 S-M1 tag + ảnh bìa FLAC · S-M2 phát FLAC 24-bit từ NAS · S-M3 Convert/Extract Audio từ MKV** — báo cáo `docs/_intents/`

### 4. Mốc
- [ ] **4.1 Commit riêng intent + spec + design**, rồi `/plan FS-24`

## Ngoài phạm vi
- CarPlay (chỉ xin quyền, D3); OGG / Opus / APE (D4).
