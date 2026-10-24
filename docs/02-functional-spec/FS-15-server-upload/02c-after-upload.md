# FS-15.02c — Sau khi đẩy

`FS-15.02c` · `Features/ServerUpload/UploadedToServerScreen.swift` · `Domain/ServerUpload/UploadDestinations.swift`
· cập nhật 2026-10-02

**Một câu:** ảnh đã lên server tìm lại được theo nơi đến, có dấu trên lưới, và xoá khỏi máy được bất cứ lúc nào bằng
một hàng nói rõ bao nhiêu ảnh, bao nhiêu GB.

## 1. Uploaded to Server

- **Collections → Utilities → On Server → Uploaded from This Device** (màn tên **Uploaded to Server**). Đổi 2026-09-27
  (người dùng: "không được hiện button create video… phải biết ảnh đã upload lên chỗ nào"): màn là **danh sách nơi
  đến** — mỗi hàng một connection + folder (tên connection, dưới là folder, bên phải số ảnh), mới nhất trước; chạm →
  lưới ảnh của nơi đó (không có nút làm video). Ảnh lên hai nơi có ở cả hai. Hàng cuối **All Uploaded Photos** → lưới
  mọi ảnh. Tên lấy theo connection hiện tại (đã đổi tên thì theo tên mới). Hàng chỉ hiện khi có ít nhất một ảnh.
  Màn không có menu ⋯ — việc xoá nằm ở hàng Free Up Space (§2).
- **Dấu trên lưới**: glyph nhỏ ở góc dưới-trái ô, trên mọi lưới — nghĩa là **đang có trên một nguồn server** theo hash,
  không theo lịch sử upload ([FS-19.07 §9](../FS-19-photo-sources/07-on-server-check.md)). Nhãn VoiceOver "On server".
- **Photo Info**: mỗi nơi (server + folder) một dòng: tên server, dưới là folder, bên phải ngày; mới nhất trước.
- Ảnh bị xoá khỏi thư viện → dòng lịch sử **ở lại** (bảng giữ bằng chứng); nó chỉ không còn hiện ở đâu.

## 2. Free Up Space

Board: `PH_UploadedToServer`, `IP_UploadedToServer`, `DI_UploadedToServer`, `DC_UploadedToServer` (H5).

- Hàng **đầu tiên** của màn, section riêng trên "Where They Are": glyph `trash`, chữ đỏ **Free Up Space**, dòng dưới
  `214 photos · ~4.2 GB` (dòng dưới, không bên phải — Duo ngoài 466pt không đủ chỗ cho cả hai).
- N = số tấm qua luật FS-15.02 §7. X = tổng số byte trong lịch sử upload của các file gốc thuộc N tấm, mỗi file tính một lần
  dù lên nhiều nơi. Dấu `~`: Optimize Storage có thể chỉ giữ bản nhỏ trên máy, và chỗ trống chỉ có lại khi Recently
  Deleted được dọn.
- Chạm → hai hộp xác nhận của FS-15.02 §7 (của app, rồi của hệ thống). Huỷ ở hộp nào cũng không mất gì, không có toast.
- Xoá xong: toast "Moved 214 photos to Recently Deleted. About 4.2 GB frees up when it's emptied."; danh sách nơi
  đến và hàng Free Up Space tính lại tại chỗ, không cuộn. Xoá hỏng → hộp "Couldn't Delete Photos" + lý do.

| Hàng mờ khi | Dòng dưới nói |
|---|---|
| đang tính | spinner + "Checking which photos are safe to delete…" |
| 0 tấm xoá được, còn tấm thiếu file | "Nothing to free up yet — 3 photos have files that aren't on a server." |
| đang xoá | spinner + "Deleting…" |
| mọi ảnh đã lên đều không còn trên máy | cả màn thành câu "No uploaded photos are left on this device." |

- Quyền `.limited`: chỉ tính và xoá những ảnh app thấy được; ảnh ngoài phần được chia sẻ không vào N, không vào X.
