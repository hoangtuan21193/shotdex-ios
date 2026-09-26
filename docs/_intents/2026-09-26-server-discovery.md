# Intent: Tự tìm server trong mạng nội bộ, không bắt gõ địa chỉ

| Trường | Giá trị |
|---|---|
| Tác giả | hat.tuan@karabiner.tech |
| Ngày | 2026-09-26 |
| Trạng thái | accepted — người dùng duyệt 2026-09-26 |
| Tiến độ | **gần xong** (2026-09-26) — 3/3 task, 6/7 AC có bằng chứng; AC-27 (hộp Local Network) chỉ chứng minh được trên máy thật |
| Nguồn | phản hồi người dùng (2026-09-26, sau khi dùng FS-15) |
| Spec sinh ra từ đây | [FS-15.04](../02-functional-spec/FS-15-server-upload/04-find-servers.md) — AC-24…AC-30 |

## Problem — vấn đề

Muốn thêm connection, người chụp phải biết và gõ tay **host, cổng, tên share** của NAS hoặc Mac. Phần lớn
không biết IP của NAS nhà mình, không biết share tên gì, và gõ trên bàn phím điện thoại dễ sai
(`FileServerFormScreen` hiện chỉ có ô nhập tay — [FileServerFormScreen.swift](../../ShotDex/Features/ServerUpload/FileServerFormScreen.swift)).
Trong khi đó Finder và Files trên cùng mạng đã thấy sẵn những máy này.

Thêm nữa: hộp xin quyền **Local Network** của hệ thống hiện chỉ bật ở lần nối đầu (Test Connection hoặc Upload,
FS-15.01 §5) — giữa một thao tác, không ai giải thích trước.

## Proposed outcome — kết quả mong muốn

- Mở **Add Connection** → hệ thống hỏi quyền Local Network ngay lúc đó (app nói trước vì sao cần).
- Form có mục **Servers Found on This Network**: các Mac, NAS đang chia sẻ file trên cùng mạng, mỗi hàng có
  icon loại máy, tên máy, các giao thức nó mở. Người dùng hiểu ngay đây là máy **trong mạng nội bộ** app vừa tìm
  thấy, không phải danh sách có sẵn.
- Chạm một máy → Name, Protocol, Host, Port điền sẵn. Chỉ còn gõ username và password.
- Với SMB: đăng nhập xong thì chọn **share** từ danh sách có trên máy, không gõ tên share. Folder chọn bằng màn
  duyệt đã có.
- Không tìm thấy gì (Wi-Fi khách, router chặn mDNS, máy Windows) → nhập tay như hôm nay, vẫn đủ.

## Affected users and systems — phạm vi ảnh hưởng

- Settings → File Servers → Add Connection; sheet upload → Add Connection….
- iPhone · iPad · Duo trong · Duo ngoài.
- Data: một bộ tìm máy qua Bonjour (Network framework), liệt kê share SMB. Domain: đổi loại dịch vụ Bonjour ra
  giao thức và cổng (thuần, test được). Features: form.
- Info.plist: khai `NSBonjourServices` (`_smb._tcp`, `_sftp-ssh._tcp`, `_ssh._tcp`, `_device-info._tcp`, và các
  loại của giao thức mới — xem intent [more-file-protocols](2026-09-26-more-file-protocols.md)).
- Không đụng dữ liệu đã lưu.

## Constraints — ràng buộc

- Không thêm thư viện: Bonjour có sẵn trong Network framework; SMBClient đã có `listShares()`.
- Chỉ tìm khi form đang mở; đóng form là dừng. Không quét nền, không gửi gì ra ngoài mạng nội bộ (NF-03).
- Lưu host dạng tên `.local` chứ không lưu IP (DHCP đổi IP).
- Không đọc tên Wi-Fi — trên iOS cần quyền vị trí (người dùng chọn tiêu đề không có tên Wi-Fi).
- Nhập tay vẫn là đường chính cho server qua internet và máy Windows.

## Open questions — câu hỏi còn treo

- ~~Tên mục~~ → **Servers Found on This Network** (người dùng chốt 2026-09-26).
- ~~Lúc hỏi quyền~~ → khi mở Add Connection (người dùng chốt 2026-09-26).
- Người dùng từ chối quyền Local Network: form hiện gì — một dòng giải thích + nút mở Settings? (đề xuất: có;
  `/spec` chốt câu chữ).
- Synology/QNAP có quảng bá `_sftp-ssh._tcp` không, hay chỉ `_smb._tcp`? — đo trên máy thật, không chặn Design.
