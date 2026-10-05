# Vòng 1 — FS-03.09 — chốt các chỗ code lệch spec (verify 2026-09-29) + ba điểm của luồng server

Không còn gì cần sửa: có thể chốt plan.

## Không OK (bỏ, không cần sửa) (1)

- **D11** Chữ 'Server' khi đích là folder cloud — trang server

## OK (11)

- **D1** AC-1: panel có 7 thẻ, AC ghi 5 — trang panel
  - Lựa chọn: Sửa AC thành 7, test đọc danh sách thật (seven)
- **D2** AC-5: chạm header thẻ cuối thì thẻ không lên được đầu — trang panel
  - Lựa chọn: Đệm dưới động (pad)
- **D3** AC-11: đồ thị curve nuốt cú cuộn danh sách — trang panel
  - Lựa chọn: Chỉ điểm điều khiển nhận kéo (points)
- **D4** AC-9: cụm lệnh rộng 361pt, AC ghi 340 — trang chrome
- **D5** AC-20: canvas iPad 11" chỉ rộng 832pt, dưới mốc 842 — trang chrome
  - Lựa chọn: Hạ mốc AC xuống 832 (relax) — KHÁC với đề xuất
- **D6** AC-13: đổi mode trên rail thì áp khung cắt — trang chrome
  - Lựa chọn: Rời Crop là áp (sửa AC) (commit)
- **D7** AC-28 và AC-29: 'Layers' là hàng tiêu đề, ↺ không hỏi xác nhận, có hai ↺ — trang markup
  - Lựa chọn: Một ↺, hỏi khi ≥ 2 layer (one-confirm)
- **D8** AC-30: palette PencilKit nổi đè ảnh và che chân panel — trang markup
  - Lựa chọn: EditorDrawRows trong panel (rows)
- **D9** AC-15: ảnh ngoài tập .limited — chưa có code — trang markup
  - Lựa chọn: Làm ngay (build)
- **D10** iPad: nút 'Import N to Library' và 'Choose …' dài gần 1000pt — trang server
  - Lựa chọn: Đưa hành động lên toolbar như Files (toolbar) — KHÁC với đề xuất
- **D12** Photo Info ghi folder '/' cho folder cloud — trang server
