# FS-03.17b — Editor iPhone Duo màn trong (ngang và dọc)

`FS-03.17b` · tier D · `Features/Editing/` · cập nhật 2026-10-01

**Một câu:** mở Duo ra, editor ngang 951×669 là bản iPad thu nhỏ (cột 260, đĩa băng 40); xoay máy dọc 669×951 thì
editor thành bản iPhone phóng to (panel dưới 400). Luật chung: [17](17-wide-design.md) §3.

## 1. Xoay — chỉ editor, chỉ màn trong (D5)

- iPhone thường và Duo màn ngoài vẫn khoá dọc. Trên Duo màn trong, mọi màn ngoài editor vẫn như hôm nay
  (cảnh ngang 951×669). Chỉ khi editor đang mở trên màn trong thì xoay được 951×669 ↔ 669×951.
- Rời editor khi đang dọc: app quay về hướng của màn trước đó. Gập máy khi đang trong editor dọc: editor sang màn
  ngoài theo [17c](17c-duo-cover.md), không mất chỉnh sửa.
- 669×951 rộng dưới 700 nên đi đường bố cục iPhone; mọi số bên dưới là của bảng, không phải của iPhone 402.

⚠️ CẦN QUYẾT: **nhận biết "màn trong của Duo"** lúc chạy. Không có API hệ thống. Đề xuất: model máy là Duo **và** cảnh
dài nhất ≥ 900pt. Sai thì iPhone khác có thể xoay nhầm — có test đơn vị cho hàm nhận biết.

## 2. Ngang 951×669 (bảng `DI*`)

| Vùng | Số |
|---|---|
| Vùng ảnh | x0–691, cao hết 669 |
| Cột | x691–951, **260**, viền trái 1pt trắng 7% |
| Băng | y12, đĩa **40**: Back x16 · Undo 68 · Redo 113 · … · History 396 · Reset All 441 · Revert 486 · Recall 531 · Compare 583 · Save 635 (kết thúc 16pt trước cột) |
| Histogram | góc trên cột 236×80, đầu cột cao 103 |
| Danh sách | y103–596 (493) mọi chế độ |
| Dải công cụ | y596–657, 6 ô 43×54; trong công cụ thành ✕ · tên · ✓ |
| Thanh nổi Mask/Heal | bản gọn mép trái ảnh, rộng 58; Size là nút 46×40, kéo ngang để đổi |
| Filmstrip | 72 dưới vùng ảnh |
| Sheet Save | 480 × 580 giữa màn |

- Hàng chữ trong cột 260: căn lề là một nút xoay vòng, Size rộng 92.
- Transform cao ~730 trong khung 493: danh sách cuộn; vào Transform cuộn về CROP.

⚠️ CẦN QUYẾT: **mép màn**. Bảng đặt băng ở y12, histogram y8, dải công cụ tới y657 — nằm trong vùng 24pt trên/dưới đã đo
khi còn status bar, và góc bo ~66pt cắt góc histogram và ô Markup. Đề xuất: đo lại inset khi editor ẩn status bar
(`Tools/sim-shot … inner` có mask) **trước** khi code; nếu cắt thì lùi phần bị cắt vào trong đúng số pt đo được và
sửa bảng `DI*` theo.

## 3. Dọc 669×951 (bảng `DIP*`)

| Vùng | Số |
|---|---|
| Băng | dải 52 trên cùng, đĩa 34 ở y9, cách mép 10: Back · Undo · Redo · … · History · Reset All · Revert · Recall · histogram 46×28 · Save |
| Vùng ảnh | y52–551 (669×499), ảnh fit có 8pt trên dưới |
| Panel | **400** cố định từ y551, bo trên 22: vùng thông số 323 · dải 6 công cụ 56 (ô 111×50) · 21 cho home |
| Trong công cụ | ✕ thay Back, ✓ đĩa trắng thay Save trên băng; dải công cụ vẫn hiện, mờ 22%, không chạm được |
| Thanh nổi Mask/Heal | mép trái vùng ảnh |
| Lưới | Presets, Mask mới, lớp mới: **5 cột** |
| Filmstrip | 64 giữa ảnh và panel, ô 48 bo 8, Sync ở cuối dải |
| Curve | trong danh sách Edit: Point \| Region, đồ thị 200 cạnh cột kênh |
| Sheet Save | 520 giữa màn |

- Không có Compare trên băng dọc (bảng không vẽ, dù note liệt kê) — giữ lâu trên ảnh để so.

## 4. Tiêu chí nghiệm thu

Thiết bị: iPhone Duo iOS 27. **Người dùng mở gập simulator bằng tay** trước mỗi lượt chụp (simctl không có lệnh
mở). Chụp bằng `Tools/sim-shot <udid> out.png inner`, không dùng MCP simulator trên Duo. Script:
`ShotDexUITests/scripts/fs0317-duo-inner.json` (⚠️ chưa có) — không mở đầu bằng bước `orientation`.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-33 | Duo mở, ngang | lặp các bước AC-18…AC-28 của 17a | `design-parity` PASS `DI1`…`DI12` (12 bảng) | ⚠️ chưa có |
| AC-34 | Duo mở, ngang, Edit | xoay sang dọc | cảnh 669×951, PASS `DIP1_Edit`; chỉnh sửa còn nguyên | ⚠️ chưa có |
| AC-35 | Duo mở, dọc | lặp các bước AC-18…AC-28 | PASS `DIP1`…`DIP12` (12 bảng) | ⚠️ chưa có |
| AC-36 | Duo mở, dọc, trong Mask | xoay sang ngang | vẫn trong Mask, mask còn nguyên, PASS `DI4_Mask` | ⚠️ chưa có |
| AC-37 | Duo mở, dọc, trong editor | chạm Back | thư viện hiện ở cảnh ngang 951×669 như trước khi vào | ⚠️ chưa có |
| AC-38 | Duo mở, thư viện | xoay máy | thư viện không xoay | ⚠️ chưa có |
| AC-39 | iPhone 17 | mở editor, xoay máy | editor không xoay | `EditorOrientationPolicyTests` ⚠️ chưa có |
| AC-40 | Duo mở, dọc, Edit | chạm một ô công cụ khác khi đang trong Transform | không đổi công cụ; ô mờ 22% | ⚠️ chưa có |
| AC-41 | Duo mở, ngang, ảnh 2:3 | vào Mask, vẽ một nét ở giữa ảnh | nét vẽ được; thanh cọ và băng vẫn chạm được dù nằm trên ảnh | ⚠️ chưa có |
| AC-42 | Duo mở, ngang, mọi bảng | ảnh `sim-shot … inner` có mask | không nút, nhãn nào bị góc bo hay mép cắt | ⚠️ chưa có |

**Chưa chứng minh được:** AC-33…AC-42 — chưa có code; AC-33…AC-38, AC-40…AC-42 còn cần người mở gập simulator.
