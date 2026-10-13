# FS-23.04 — Dịch phụ đề bằng AI

`FS-23.04` · tier A (sheet) · board `PH_MovieTranslate` (5/5) — chưa vẽ · cập nhật 2026-10-14

**Một câu:** từ một phụ đề chữ đã có, tạo phụ đề thứ hai bằng ngôn ngữ khác với AI người dùng chọn, giữ nguyên
từng mốc giờ, làm xong trước khi lên máy bay và giữ lại để xem offline.

## 1. Sheet Translate

Mở từ nút **Translate…** của bảng phụ đề (03 §2).

| Ô | Mặc định | Ghi chú |
|---|---|---|
| From | phụ đề Primary | chỉ phụ đề chữ (03 §3) |
| To | ngôn ngữ đầu tiên trong Subtitle Languages khác From | danh sách ngôn ngữ của nhà cung cấp đang chọn |
| Using | nhà cung cấp dùng lần trước | các nhà cung cấp đã cài ở [FS-08.07](../FS-08-settings/07-ai-providers.md) |

- **Using** liệt kê theo thứ tự: trên máy (Apple Translation, Apple Intelligence) → máy chủ nhà → cloud. Mục nào
  máy không có thì không hiện (Apple Translation dưới iOS 18; Apple Intelligence ngoài máy hỗ trợ).
- Chưa có nhà cung cấp nào dùng được → sheet chỉ có `Set Up AI` · "Choose how ShotDex translates: on this device,
  a model on your home computer, or a service you have an API key for." · nút **Open AI Settings** (mở Settings › AI).
- Chọn nhà cung cấp cloud → dòng dưới: "1,380 lines of subtitle text will be sent to Anthropic." Máy chủ nhà →
  "Sent to Mac Studio on your network." Trên máy → "Stays on this device."
- Nút **Translate** (accent duy nhất của sheet).

## 2. Chạy

- Tiến độ trong sheet và trên hàng phim: `Translating 412 of 1,380 lines` + **Cancel**. Đóng sheet không dừng việc.
- Chia theo cue, không theo câu: mỗi lượt gửi một khối cue có đánh số + 5 cue trước làm ngữ cảnh (không dịch lại).
  Khối: 40 cue cho máy chủ nhà và cloud; 30 cue cho Apple Intelligence (cửa sổ 4.096 token, mỗi khối một phiên mới);
  Apple Translation dịch theo lô.
- Lời dặn model: tên phim, hai ngôn ngữ, giữ số cue, giữ xuống dòng, không gộp, không thêm chú thích; cue kiểu
  `[music]` cũng dịch.
- **Mốc giờ không bao giờ do AI viết**: bản dịch lấy đúng giờ bắt đầu/kết thúc của cue gốc. Khối trả về sai số
  cue → thử lại khối đó một lần, vẫn sai thì dịch từng cue của khối.
- Cancel hoặc app bị dừng → giữ các khối đã xong; mở lại Translate cùng From/To/Using → `Continue (412 of 1,380)`.
- Rời app: iOS 26 xin tác vụ xử lý tiếp tục; trước 26 dừng khi hệ thống dừng app, mở lại thì tiếp.

## 3. Kết quả

- Xong → phụ đề mới `Tiếng Việt · Translated (Claude)` lưu cạnh phim; Secondary đang Off thì tự bật bằng nó.
- Dịch lại cùng From → To bằng nhà cung cấp khác tạo phụ đề riêng, không đè bản cũ.
- Bản dịch chỉ nằm trên máy, không gửi lại cho ai.

## 4. Lỗi

| Lỗi | Hiển thị |
|---|---|
| không mạng (cloud, máy chủ nhà) | `Can't Reach Anthropic` · "Check your connection, or translate on this device." · Retry |
| key sai (401/403) | `Anthropic Rejected the API Key` · "Update it in Settings › AI." · Open AI Settings |
| giới hạn tốc độ (429) | tự chờ và thử lại tối đa 3 lần (2, 8, 30 s); vẫn lỗi → dừng, giữ phần xong, Retry |
| hết tiền / hết hạn mức tài khoản | đúng câu nhà cung cấp trả về, một dòng, + Retry |
| Apple Translation chưa có gói ngôn ngữ | hộp tải gói của hệ thống (cần mạng); từ chối → không chạy, không lỗi đỏ |
| Apple Intelligence không hỗ trợ ngôn ngữ đích | ngôn ngữ đó không có trong ô To khi chọn Apple Intelligence |

- Mọi lỗi giữ phần đã dịch; không lỗi nào xoá phụ đề gốc.

## 5. Ràng buộc

- Apple Translation **không chạy trên Simulator** → AC của nó chứng minh trên máy thật.
- Không gửi gì ngoài chữ của phụ đề From + tên phim + tên hai ngôn ngữ. Không gửi tên file, mã băm, đường dẫn.
- API key đọc từ Keychain lúc gọi, không ghi vào log, không vào thông báo lỗi.
