# NF-05 — Tương thích thiết bị và hệ điều hành

`NF-05` · `Core/Utils/ActiveDisplay.swift` · mọi view có nhánh `#available(iOS 26.0, *)`
· kiểm bằng agent `ios26-parity` · `device-layout` · `Tools/ui-drive` · cập nhật 2026-09-22

**Một câu:** những kích thước app phải chạy đúng, hai nhánh iOS 26, và luật layout theo bề rộng cửa sổ.

## 1. Luật

1. **Điện thoại có đủ mọi chức năng của iPad.** Không viết tay danh sách control theo thiết bị — dựng từ
 danh sách đầy đủ, kiểm bằng cách lặp.
2. Màn rộng thì **thêm nội dung, không phóng to nội dung**.
3. Cổng vào layout rộng tính theo **bề rộng cửa sổ** (editor: editor mở bố cục hai cột
   từ 700pt), không theo idiom thiết bị.
4. phép kiểm "máy có tai thỏ" đọc từ safe area (`> 24`), không từ idiom.
5. Màn thấp (Duo trong, iPad Split View ngang) phải có nhánh gập panel — editor gập panel hai hàng khi
   khung dựng thấp hơn 800pt.
6. **Cả hai nhánh nhánh riêng cho iOS 26 phải làm được cùng một việc** — không nhánh nào thiếu action.
   Kiểm bằng element dump hai bên.

## 2. Phiên bản

| iOS | Trạng thái |
|---|---|
| 17 | tối thiểu — Swift Charts, Observation, bảng trượt nhiều nấc |
| 26 | nhánh UI riêng: Liquid Glass hệ thống, tab tìm kiếm của hệ thống |
| 27 | đổi cách vẽ tab search; kéo về bằng một dòng thiết lập của hệ thống, không rẽ nhánh code |

## 3. Kích thước phải chạy đúng

| Thiết bị | Scene (pt) | Ghi chú |
|---|---|---|
| iPhone (compact) | 402 × 874 | một tay, thumb zone, Dynamic Island |
| iPad | 1376 × 1032 và 1032 × 1376 | regular; rộng dư, cao thì không |
| iPhone Duo — màn trong | **951 × 669** | regular width nhưng **màn thấp nhất app ship** |
| iPhone Duo — màn ngoài | **466 × 678** | scene 382 × 644, `.compact`, safe area **phải 84pt** |
| Split View / Stage Manager | thay đổi liên tục | đo **cửa sổ**, không đo màn |

- Duo: hai màn tích hợp — ngoài `1398×2034 @3x`, trong `2007×2853 @3x`. Trên màn ngoài iOS đặt status bar
  **dọc** cùng tab bar thành dải đứng bên phải (insets `top 0, left 0, bottom 34, right 84`).
- Vì dải đó, view toàn màn dùng chỉ tràn qua vùng an toàn **trên và dưới**, **không** cả bốn cạnh.
- Màn trong: lưới `bounds = 867×669pt`. hệ số siết **0,7** cho density 3 ra **9 cột** ở ~94pt
  (giữ nguyên kích thước ô sẽ ra 7 cột 123.9pt — quá thưa). Cấp độ ngày theo **density đã lưu**, không
  theo số cột đã vẽ. Kiểm bằng test mật độ lưới ở đúng 867pt.
- Góc bo màn: Duo ~66pt (ăn 17pt ở độ sâu 14pt), iPad ~36pt → screenshot kiểm tra phải có mask, dùng
  `Tools/sim-shot`.
- iPad tham chiếu: lưới Library 9 cột ở 11" dọc; dashboard Statistics **2 cột** ở 11" dọc, **3 cột** ở 13" dọc.

## 4. Ràng buộc còn treo

- Máy Duo boot ở trạng thái gập và CoreSimulator **không có lệnh gập/mở** — phải mở tay trong Simulator.app.
- Runtime iOS 27.1 **chỉ tạo được máy Duo**; iPad phải kiểm trên iOS 27.0.
