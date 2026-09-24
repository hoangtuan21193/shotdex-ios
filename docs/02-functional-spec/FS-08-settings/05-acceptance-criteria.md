# FS-08.05 — Tiêu chí nghiệm thu

`FS-08.05` · cập nhật 2026-09-22

**Một câu:** 19 tiêu chí cho **bố cục theo bề rộng và tìm kiếm**; các mục khác của FS-08 chưa có AC.

## 1. Bảng

| # | Cho | Khi | Thì | Chứng minh |
|---|---|---|---|---|
| AC-1 | bề rộng hệ thống báo là **rộng** | gọi hàm quyết định bố cục | chọn hai cột | ✅ test bố cục: bề rộng rộng → hai cột |
| AC-2 | **hẹp** và **chưa xác định** | gọi hàm quyết định bố cục | chọn một cột cho cả hai — chưa xác định thì không đoán | ✅ test bố cục: hẹp và chưa xác định → một cột |
| AC-3 | iPad 13" ngang 1376×1032, Settings đóng | chạm gear | sidebar trái + detail "Photo Library" phải; hàng detail rộng **≤ 860pt** | ✅ kịch bản `ipad-settings-split` — sidebar `x=26 w=288`, detail từ `x=350`, hàng `x=453 w=800`; [ảnh](../assets/2026-09-22-settings-split-ipad13-landscape.png) |
| AC-3b | iPad 11" **dọc** 834×1210, iOS 18.6 | mở Settings | vẫn split view, không rơi về một cột | ✅ [ảnh](../assets/2026-09-22-settings-split-ipad11-portrait.png) — sidebar 320pt, đủ 9 mục |
| AC-4 | iPhone 402×874 | mở Settings | đúng **12 section** theo thứ tự Photo Library → Privacy, không sidebar | ⚠️ một nửa — thứ tự khoá bằng test; ảnh iPhone 17 Pro 402×874 cho thấy **một cột, không sidebar**, mở đúng ở Photo Library. **Chưa chụp** đủ 12 section (phải cuộn nhiều màn) |
| AC-4b | iPad 13", Settings ở Slide Over (compact) | chụp màn | một cột, không sidebar | ⚠️ chưa có — `Tools/ui-drive` không dựng được Slide Over |
| AC-5 | danh sách mục đầy đủ | dựng danh sách cho cả hai bố cục | hai danh sách **cùng một tập**, không mục nào chỉ có một bên | ✅ test: hai bố cục phủ cùng một tập mục |
| AC-6 | Duo màn trong 951×669, mục Photo Library | chụp màn | sidebar hiện **cả 9 mục không phải cuộn** (mép dưới của Support ≤ 669 − safe area) | ⚠️ chưa có — `Tools/sim-shot` + một kịch bản cho Duo |
| AC-7 | iPad 13" ngang | chọn Support rồi mở một thread | thread hiện **trong detail pane** (mép trái ≥ bề rộng sidebar), Back về danh sách Support chứ không về Photo Library | ⚠️ chưa có |
| AC-8 | iPad 13" ngang, Widgets → một design | kéo dòng giờ trên preview 40pt | anchor **đúng dòng đó** đổi, ảnh nền dịch **0pt**, preview vẫn trong pane | ⚠️ chưa có |
| AC-9 | iPad 13" dọc, đang ở Camera Database | xoay sang ngang | vẫn split và **vẫn ở Camera Database** | ⚠️ chưa có |
| AC-10 | Stage Manager ~1200pt, đang ở Display | thu cửa sổ về cỡ compact | rơi về một cột và **Display là màn đang hiện**; Back về danh sách 12 section | ⚠️ chưa có — driver không đổi được cỡ cửa sổ |
| AC-11 | quyền `.limited`, iPad 13" ngang | mở Settings | detail hiện Access = "Limited Access" + nút Manage, không hàng nào tràn bề rộng detail | ⚠️ chưa có |
| AC-12 | iPad 13" ngang, Settings mở ở mục bất kỳ | bấm **Done** ở toolbar sidebar | toàn bộ Settings đóng, về tab trước đó | ✅ kịch bản `ipad-settings-split` — dump sau Done còn 8 cell, không còn phần tử nào của cột mục |
| AC-13 | iPad 13" ngang, cỡ chữ `.accessibility1` | mở Settings | không nhãn sidebar nào bị cắt, mọi hàng cao ≥ 44pt | ⚠️ chưa có |
| AC-14 | VoiceOver bật, iPad 13" ngang | quét qua sidebar | mỗi mục đọc ra tên + trạng thái "đang chọn" cho mục đang chọn; detail có heading đúng tên mục | ⚠️ chưa có — không có đường tự động |
| AC-15 | Settings mở | gõ `hdr` | kết quả có hàng **"View Full HDR"** kèm dòng phụ "Playback"; `HDR` và `hdr` cho cùng kết quả | ✅ test tìm kiếm không phân biệt hoa thường + test kết quả mang tên mục ở dòng phụ + [ảnh](../assets/2026-09-22-settings-search-iphone16.png) |
| AC-16 | iPhone 402×874, Settings mở | gõ một từ rồi chạm kết quả | cuộn tới đúng hàng, ô tìm kiếm đóng, hàng nháy nền 1,2s | ⚠️ hai phần ba — ảnh iPhone 17 Pro: gõ `hdr` ra hàng "View Full HDR / Playback", chạm vào thì **cuộn tới đúng hàng** trong section Playback và **ô tìm kiếm đóng**. Cái nháy nền 1,2 s vẫn chưa bắt được trên ảnh |
| AC-17 | chỉ mục tìm kiếm của Settings và các section thật | đếm nhãn hàng ở hai nơi | mỗi section có số mục index **bằng** số hàng nó dựng | ✅ test mọi mục đều có chỉ mục + test mỗi mục khai đủ hàng nó vẽ (38 hàng) + test mỗi nhãn hàng cho đúng một mục chỉ mục |
| AC-18 | Settings mở, bố cục bất kỳ | gõ `zzzz` | màn rỗng chuẩn của hệ thống, không phải danh sách rỗng | ✅ ảnh iPhone 17 Pro: gõ `zzzz` cho màn rỗng chuẩn của hệ thống — kính lúp, "No Results for “zzzz”", "Check the spelling or try a new search." |
| AC-19 | iPad 13" ngang | chụp sidebar | 9 mục có đúng ký hiệu, mỗi hàng ≥ 44pt | ✅ kịch bản `ipad-settings-split` (hàng cao **53pt**) + test mỗi mục có biểu tượng riêng |

## 2. Chưa chứng minh được

- **Đầy đủ:** AC-1, AC-2, AC-3, AC-3b, AC-5, AC-12, AC-15, AC-17, AC-19.
- **Một phần:** AC-4, AC-16.
- **Chưa chạm:** AC-6, AC-7, AC-8, AC-9, AC-11, AC-13, AC-18.
- **Không có đường tự động:** AC-4b (Slide Over), AC-10 (Stage Manager), AC-14 (VoiceOver) — chứng minh
  bằng hàm thuần cộng một ảnh chụp tay.
- Các mục khác của FS-08 (index, notifications, widget, playback…) **chưa có AC nào** — xem
  [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).

## 3. Hai chỗ chứng minh còn hở

1. **Dump baseline của AC-4 không có.** Ba lượt `Tools/ui-drive` đầu chết: một lượt mất kết nối khi `dump`
   đi qua cả cây, hai lượt sau bị giết vì hai lượt driver chạy chồng nhau xoá
   file kịch bản dùng chung của nhau. Luật rút ra: **một lượt driver chỉ chạy một lần một**, và script iPad
   **không được mở đầu bằng bước xoay máy** (bước đó treo hơn 9 phút — đặt máy sẵn hướng cần chụp).
2. **Cú nháy 1,2s chưa bắt được trên ảnh.** Mọi đường chụp ở đây mất hơn một giây để trả về nên khung hình
   luôn rơi sau khi nháy đã tắt. Muốn ảnh thì phải quay lệnh quay màn hình của trình giả lập rồi cắt khung — máy này
   chưa có công cụ cắt video.
