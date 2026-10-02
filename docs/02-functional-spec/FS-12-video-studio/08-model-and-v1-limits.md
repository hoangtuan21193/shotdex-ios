# FS-12.08 — Model dữ liệu, nhạc và giới hạn v1

`FS-12.08` · `Domain/Video/VideoProjectModels.swift` · `ImportedMusicStore` · cập nhật 2026-10-03

**Một câu:** project là một công thức thuần dữ liệu, nhạc chỉ đến từ file người dùng có quyền, và những gì
cố ý chưa làm được ghi ra.

## 1. Quy tắc

- **Không bundle nhạc sẵn.** Nhạc chỉ đến từ **Files-import của người dùng**.
- **Không tải nhạc từ YouTube hay stream** — vi phạm điều khoản dịch vụ, vi phạm bản quyền, và bị App Store
  từ chối. Chỉ Files-import (nhạc người dùng có quyền) hoặc một kho CC0/có giấy phép mới hợp pháp.
- Toán quyết định (timeline, split, hiệu ứng, animation overlay, xếp lane) nằm ở Domain và **có test**.
- Một thay đổi trên project là **một bước undo**; kéo slider gom thành một nhóm.

## 2. Model

| Kiểu | Giữ gì |
|---|---|
| **Project** | clip · chuyển cảnh · nhiều bản nhạc · **Video sound** (âm gốc mọi clip — mức âm duy nhất của project, **không có Master**, [04 §2](04-tools-and-inspector.md)) · **một ô look** cả video (preset · My Look · LUT, kèm Amount — [06c](06c-photo-looks.md)) · adjustments · overlay · lane phụ đề C1 tuỳ chọn ([14 §7](14-captions.md)) · số lần xoay · **Video Settings** (tỉ lệ · Fit/Fill · nền: loại, màu, độ mờ, id ảnh · độ phân giải · fps · codec — [10 §6](10-video-settings-and-export.md)) · **đích xuất** (id preset hoặc Custom + Fit/Fill khi chênh tỉ lệ — [16 §6](16-export-presets.md)) · In–Out tuỳ chọn ([17b §5](17b-keyboard-and-pointer.md)) · tầng màu (de-log, node chain, mask) |
| **Clip** | id · asset · loại (ảnh / video / freeze) · thời lượng ảnh · trim hai đầu · mute · hiệu ứng · tốc độ · mốc freeze · thời lượng nguồn · ô look tuỳ chọn (thay look cả video) |
| **Overlay theo thời gian** | overlay (chữ hoặc ảnh; sticker giữ id asset nguồn — [09 §6](09-media-panel.md)) · mốc bắt đầu · thời lượng · animation vào/ra + thời lượng từng chiều |
| **Bản nhạc** | id · nguồn · mốc bắt đầu · trim hai đầu · thời lượng nguồn · âm lượng · fade in/out · bắt nhịp (bật · Every Beat/Bar · Offset — [12 §7](12-beats.md)) · ducking (bật · Amount · Duck in · Recover · nguồn — [13 §5](13-audio-ducking.md)) |
| **Lane phụ đề** | ngôn ngữ · kiểu · cỡ · vị trí · Burn into video · tiến độ nhận dạng; mỗi khối: id · clip · giờ đầu/cuối **trong nguồn** · chữ · mốc từng từ · cờ đã sửa tay ([14 §7](14-captions.md)) |

- **Không lưu trong project:** BPM và vị trí nhịp, đoạn có giọng — dữ liệu suy ra, cache theo file trong Caches;
  tập clip đang chọn, chế độ so sánh, trạng thái thu panel — trạng thái màn hình. Cài đặt PRECISION / PENCIL theo máy.
- Khoá cũ (Master, preset 1080p/4K) bị bỏ qua hoặc chuyển khi đọc; app chưa phát hành nên không migration.

- Tư thế của animation overlay (độ mờ, dịch, phóng) tính bằng **một hàm dùng chung cho cả export lẫn
  preview** — nếu không, hai bên sẽ trôi khỏi nhau.
- Overlay rasterize **theo từng cái**, cache theo id, rồi ghép theo thứ tự lớp.
- Thời lượng hiệu dụng của một bản nhạc = cửa sổ trim (tối thiểu **0,1s**).

## 3. Nhạc

- **Công cụ Music mở panel Music** ([04 §3](04-tools-and-inspector.md)), không mở sheet. Multi-track nên **không có
  hàng "None"** — xoá một bản là việc của timeline.
- Panel: dòng **Video sound**, nút **"Add Music from Files…"**, rồi section **"My Music"** (nhạc đã import; rỗng thì
  hiện empty state gợi ý Add). Accent chỉ ở Export.
- Mỗi hàng có **nút nghe thử** (loop, một bài một lúc, dừng khi đóng sheet), **waveform mini** (decode lười
  theo hàng, có cache) và **nút xoá**.
- **Import lưu bền**: copy vào thư mục riêng của app kèm một manifest tên, nên dùng lại được ở mọi phiên sau.
- Trình chọn sticker là **picker chọn nguồn**, không phải panel có tiêu đề và nút ✓. Media là panel thư viện
  ([09](09-media-panel.md)), không phải trình chọn của hệ thống.

## 4. Hai lối vào song song

Nút thêm trên lane và toolbar tới **cùng** hành động. Undo/redo giữ ảnh chụp recipe, trần **40** bước.

## 5. Project mở lại được

Recipe lưu vào bảng riêng và hiện ở **Video Projects** trong tab Collections — mở lại là sửa tiếp
([FS-06.01b](../FS-06-collections/01b-album-management-and-creations.md)).

## 6. Giới hạn v1 (cố ý)

- HDR / Dolby Vision bị tone-map về SDR.
- **Âm thanh đổi cao độ khi đổi tốc độ** — chưa có time-stretch giữ pitch.
- Không có tiến độ tải iCloud theo từng clip.
- Chưa có hiệu ứng glitch / VHS.

Chữ thì đã đủ: kéo/scale/xoay trên preview, màu, căn lề, viền, bóng, animation vào/ra.

## 7. Tiêu chí nghiệm thu

Xem [README](README.md).
