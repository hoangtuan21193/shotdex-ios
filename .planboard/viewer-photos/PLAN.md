# Viewer và tải ảnh giống Photos — plan thực thi

> Chốt 2026-11-13, 1 vòng · spec FS-02 §8, AC-1…16

- [ ] 1. Intent + spec + board PH/IP/DI/DC_Viewer (tweak `chrome` hidden, nền sáng/tối)
- [ ] 2. A1 sửa cache gốc, A2 giải mã sẵn, A3 giữ sau huỷ, A4 dọn khi thiếu bộ nhớ — PhotoLibraryService.swift (AC-11, 13, 14)
- [ ] 3. D6 preheat ±2 — PhotoDetailScreen.swift (AC-12)
- [ ] 4. D1–D4 chromeHidden: ảnh + video, nền, status bar, giữ khi vuốt — PhotoDetailScreen.swift, ZoomableImageView.swift (AC-1…7)
- [ ] 5. D5 phóng từ ô / thu về ô + cuộn tới ảnh — PhotoGridCollectionView.swift, LibraryScreen.swift + các màn lưới (AC-8…10)
- [ ] 6. A5 preheat lưới theo hướng cuộn (AC-15); A6 Esc + Caption & Keywords (AC-16)
- [ ] 7. Build, test lớp liên quan, sim iPad 26.5 (+ iPhone/18.6 nếu có quyền ảnh), commit từng phần
