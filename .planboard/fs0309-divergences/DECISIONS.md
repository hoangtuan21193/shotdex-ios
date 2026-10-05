# FS-03.09 — chốt các chỗ code lệch spec + ba điểm của luồng server — các quyết định

| ID | Quyết định | Kết quả | Lựa chọn |
|---|---|---|---|
| D1 | AC-1: 7 thẻ hay 5 | OK | Sửa AC thành 7, test đọc danh sách thật |
| D2 | AC-5: thẻ cuối không lên được đầu | OK | Đệm dưới động |
| D3 | AC-11: curve nuốt cú cuộn | OK | Chỉ điểm điều khiển nhận kéo |
| D4 | AC-9: cụm lệnh 361pt | OK | Sửa AC |
| D5 | AC-20: canvas 832 < 842 | OK | Hạ mốc AC xuống 832 (khác đề xuất) |
| D6 | AC-13: rời Crop áp khung | OK | Rời Crop là áp (sửa AC) |
| D7 | AC-28/29: ↺ trùng, không hỏi | OK | Một ↺, hỏi khi ≥ 2 layer |
| D8 | AC-30: palette PencilKit đè ảnh | OK | EditorDrawRows trong panel |
| D9 | AC-15: lỗi nạp .limited | OK | Làm ngay |
| D10 | iPad: nút dài 1000pt | OK | Đưa hành động lên toolbar như Files (khác đề xuất) |
| D11 | Chữ "Server" cho folder cloud | Không OK | — |
| D12 | Photo Info ghi "/" | OK | Hiện vị trí connection |

## D1 — AC-1: panel có 7 thẻ
- **Chốt:** Sửa AC thành 7 thẻ; test đọc `PhotoEditorScreen.sidebarParameterGroups`.
- **Vì sao:** test cũ đọc một danh sách màn hình không dùng nên xanh mà không chứng minh gì.
- **Đã cân nhắc:** gộp về 5 — thêm tầng tab trong Effects/Color, đổi chỗ công cụ.
- **Lịch sử:** vòng 1 — OK.

## D2 — AC-5: đệm dưới động
- **Chốt:** đệm dưới đủ để thẻ cuối cuộn lên đầu.
- **Vì sao:** thẻ cuối dừng ở chỗ bất kỳ, khác mọi thẻ khác.
- **Đã cân nhắc:** sửa AC — hai hành vi cho một cú chạm.
- **Lịch sử:** vòng 1 — OK.

## D3 — AC-11: chỉ điểm điều khiển nhận kéo
- **Chốt:** mỗi điểm một vùng chạm 44pt nhận kéo; nền đồ chỉ nhận chạm để thêm điểm, vuốt thì danh sách cuộn.
- **Vì sao:** đồ 280×280 chiếm gần hết panel; lướt qua thẻ Light là kẹt.
- **Đã cân nhắc:** nhấn giữ 0,2 s rồi kéo — chậm và khó khám phá; chấp nhận — panel không cuộn được.
- **Lịch sử:** vòng 1 — OK.

## D4 — AC-9
- **Chốt:** AC ghi "trong bề rộng panel + 8pt"; 361pt đạt.
- **Lịch sử:** vòng 1 — OK.

## D5 — AC-20: hạ mốc canvas xuống 832
- **Chốt:** mốc 832pt (người dùng chọn thay cho đề xuất cho tay nắm đè lên panel).
- **Vì sao:** test xanh vì không trừ tay nắm 10pt; test phải đo đúng canvas thật.
- **Đã cân nhắc:** tay nắm đè mép panel (đề xuất cũ); panel hẹp 10pt.
- **Lịch sử:** vòng 1 — OK với lựa chọn "relax".

## D6 — AC-13: rời Crop là áp khung
- **Chốt:** giữ cách hiện tại (như Lightroom/Photos), sửa AC; 7 slider; chip 4:5, 9:16 xuống hàng.
- **Vì sao:** chạm nhầm mode là cắt, nhưng Undo lấy lại; bỏ khung thì mất công dựng.
- **Đã cân nhắc:** rời Crop là bỏ khung + nút Apply riêng.
- **Lịch sử:** vòng 1 — OK.

## D7 — AC-28/29
- **Chốt:** một ↺ trên hàng tiêu đề Layers, hỏi khi ≥ 2 layer; AC-28 ghi "Layers" là hàng tiêu đề.
- **Đã cân nhắc:** không hỏi (Undo là đủ) — lệch AC-29.
- **Lịch sử:** vòng 1 — OK.

## D8 — AC-30
- **Chốt:** màn rộng ẩn palette PencilKit, dùng EditorDrawRows trong panel; màn hẹp giữ palette nổi.
- **Đã cân nhắc:** giữ palette, dời lên trên chân panel — vẫn đè ảnh.
- **Lịch sử:** vòng 1 — OK.

## D9 — AC-15
- **Chốt:** làm ngay: lỗi do quyền nói lý do + Open Settings; chứng minh bằng unit test.
- **Đã cân nhắc:** dời — AC-15 đỏ mãi.
- **Lịch sử:** vòng 1 — OK.

## D10 — iPad: hành động lên toolbar
- **Chốt:** ở regular width, Import N to Library / Delete / Choose "…" / Connect thành nút toolbar như app Files; compact giữ thanh dưới (người dùng chọn thay cho đề xuất giới hạn 420pt).
- **Vì sao:** DESIGN.md §10.1c — một hàng trải 1032pt là layout điện thoại phóng to.
- **Đã cân nhắc:** giới hạn 420pt căn giữa.
- **Lịch sử:** vòng 1 — OK với lựa chọn "toolbar".

## D11 — chữ "Server" cho folder cloud
- **Kết quả:** Không OK — giữ nguyên "Upload to Server", "verified on a server", "Uploaded to Server".

## D12 — Photo Info
- **Chốt:** folder rỗng thì hiện vị trí connection (vd "On My iPhone › CloudTest") thay "/".
- **Lịch sử:** vòng 1 — OK.
