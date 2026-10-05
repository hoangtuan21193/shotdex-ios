# NF-05 — Tương thích thiết bị và hệ điều hành

`NF-05` · `Core/Utils/ActiveDisplay.swift` · mọi view có nhánh `#available(iOS 26.0, *)`
· kiểm bằng agent `ios26-parity` · `device-layout` · `Tools/ui-drive` · cập nhật 2026-10-02

**Một câu:** những kích thước app phải chạy đúng, hai nhánh iOS 26, luật layout theo bề rộng cửa sổ, và luật
**cửa sổ thấp** theo chiều cao.

## 1. Luật

1. **Điện thoại có đủ mọi chức năng của iPad.** Không viết tay danh sách control theo thiết bị — dựng từ
 danh sách đầy đủ, kiểm bằng cách lặp.
2. Màn rộng thì **thêm nội dung, không phóng to nội dung**.
3. Cổng vào layout rộng tính theo **bề rộng cửa sổ** (editor: editor mở bố cục hai cột
   từ 700pt), không theo idiom thiết bị.
4. phép kiểm "máy có tai thỏ" đọc từ safe area (`> 24`), không từ idiom.
5. **Bề rộng chọn số cột và bề rộng; chiều cao chọn khối cao.** Cửa sổ thấp (§4) lấy bản thấp của mọi số đo
   theo chiều cao, kể cả khi bề rộng là regular. Editor: gập panel hai hàng khi khung dựng thấp hơn 800pt.
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

## 4. Cửa sổ thấp

**Cửa sổ thấp** = cửa sổ cao **dưới 720pt** (Z3). Đo chiều cao **cửa sổ**, gồm cả vùng an toàn, không đo màn;
tính một lần ở gốc app, tính lại khi cửa sổ đổi cỡ (xoay iPad, Stage Manager), mọi màn đọc chung một cờ.

| Cửa sổ | Cao (pt) | Thấp? |
|---|---|---|
| Duo trong | **669** | có — cửa sổ thấp nhất app ship |
| Duo ngoài | 678 | có (compact) |
| iPhone tràn viền thấp nhất (mini) · iPhone 402×874 | 812 · 874 | không |
| iPad ngang · dọc | 1032 · 1376 | không |
| iPad Stage Manager | theo cửa sổ | có khi kéo dưới 720 |

- *Vì 720:* trên 678 (cửa sổ thấp cao nhất đã đo) với 42pt dư, dưới 812 (iPhone tràn viền thấp nhất) — chỉ bắt
  Duo và cửa sổ Stage Manager thật sự thấp. Mốc gập panel 800pt của editor đo khung dựng, là luật riêng (§1.5).
- **Regular + thấp**: mọi số đo theo chiều cao (chiều cao hero, cạnh tile, preview ghim, thẻ cao cố định) lấy
  bản thấp ghi ở doc của màn; số cột và bề rộng giữ regular — màn rộng vẫn thêm nội dung theo chiều ngang.
- **Compact + thấp** (Duo ngoài): giữ số đo compact, vốn đã là bản nhỏ; chỉ đổi ở chỗ doc của màn ghi riêng.
- **Ngân sách**: trên cửa sổ thấp, các khối không cuộn (nav bar, tab bar, thanh dính, preview ghim, nút ghim)
  cộng lại ≤ 50% chiều cao cửa sổ — ≤ 334pt ở 669; phần còn lại là vùng cuộn.
- Nút chính của một màn luôn thấy trên cửa sổ thấp mà không cuộn.

| Chỗ đọc cờ | Ở cửa sổ thấp + regular | Doc |
|---|---|---|
| Collections — hero | 0,28 × chiều cao cửa sổ, sàn 180, trần 260 → 187pt ở 669 | FS-06.01 §3 |
| Collections — tile album | cạnh 132pt (số compact) thay 192pt | FS-06.01 |
| Statistics — Insights | các câu xếp một hàng (tối đa 3, cột ≥ 280pt), thẻ ~120pt ở 669, không cắt chữ | FS-07.02 §6 |
| Widget editor | preview cao ≤ 158pt, cỡ Large chọn qua popover; áp cả Duo ngoài (Z4) | EX-02 |
| Sheet dựng điều kiện (Advanced Search, Smart Album editor, Chart editor) | phần ghim theo ngân sách trên; hàng Media Type + Match (S4) áp ở mọi cỡ | FS-01.03 · FS-06.08 · FS-07.01b §4 |
| Compress, Collage Export | hai pane giữ ở regular (Z1); không preview cao cố định, nút chính ghim đáy pane phải | FS-03.07 · FS-11b |

- Chỗ mới chọn số đo theo size class phải đọc cả cờ này; test thuần cho cờ: 669 / 678 / 719,5 → thấp;
  720 / 812 / 874 / 1032 → không.

## 5. Ràng buộc còn treo

- Máy Duo boot ở trạng thái gập và CoreSimulator **không có lệnh gập/mở** — phải mở tay trong Simulator.app.
- Runtime iOS 27.1 **chỉ tạo được máy Duo**; iPad phải kiểm trên iOS 27.0.
