# FS-12.08 — Model dữ liệu, nhạc và giới hạn v1

`FS-12.08` · `Domain/Video/VideoProjectModels.swift` · `ImportedMusicStore` · cập nhật 2026-09-22

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
| **Project** | clip · chuyển cảnh · nhiều bản nhạc · âm lượng video · filter + cường độ · adjustments · overlay · số lần xoay · preset xuất · tỉ lệ khung · master volume · màu nền · tầng màu (de-log, node chain, mask, LUT) |
| **Clip** | id · asset · loại (ảnh / video / freeze) · thời lượng ảnh · trim hai đầu · mute · hiệu ứng · tốc độ · mốc freeze · thời lượng nguồn |
| **Overlay theo thời gian** | overlay (chữ hoặc ảnh) · mốc bắt đầu · thời lượng · animation vào/ra + thời lượng từng chiều |
| **Bản nhạc** | id · nguồn · mốc bắt đầu · trim hai đầu · thời lượng nguồn · âm lượng · fade in/out |

- Tư thế của animation overlay (độ mờ, dịch, phóng) tính bằng **một hàm dùng chung cho cả export lẫn
  preview** — nếu không, hai bên sẽ trôi khỏi nhau.
- Overlay rasterize **theo từng cái**, cache theo id, rồi ghép theo thứ tự lớp.
- Thời lượng hiệu dụng của một bản nhạc = cửa sổ trim (tối thiểu **0,1s**).

## 3. Nhạc

- **Add music luôn mở chooser** (sheet nửa/toàn màn). Multi-track nên **không còn hàng "None"** — xoá một
  bản là việc của timeline.
- Chooser: nút **"Add Music from Files…"** (accent) ở **đầu** danh sách, rồi section **"My Music"** (nhạc
  đã import; rỗng thì hiện empty state gợi ý Add).
- Mỗi hàng có **nút nghe thử** (loop, một bài một lúc, dừng khi đóng sheet), **waveform mini** (decode lười
  theo hàng, có cache) và **nút xoá**.
- **Import lưu bền**: copy vào thư mục riêng của app kèm một manifest tên, nên dùng lại được ở mọi phiên sau.
- Chooser nhạc, sticker picker và media picker là **picker chọn nguồn**, không phải sheet-panel có tiêu đề
  và nút ✓.

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
