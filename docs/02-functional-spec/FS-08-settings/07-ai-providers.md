# FS-08.07 — AI: chọn ai làm việc AI cho ShotDex

`FS-08.07` · tier A · mã: `ShotDex/Features/Settings/AI/`, `ShotDex/Data/AI/`, `ShotDex/Domain/AI/` · board
`PH_SettingsAI`, `PH_SettingsAIProvider` · cập nhật 2026-10-14

**Một câu:** Settings › **AI** liệt kê những AI ShotDex dùng được — trên máy, máy chủ trong nhà, dịch vụ cloud bằng
API key của người dùng (chỉ cho dịch phụ đề) — và chọn cái nào lo **dịch phụ đề** ([FS-23.04](../FS-23-offline-movies/04-ai-translation.md))
và cái nào lo **AI Search** ([FS-01.03 §4](../FS-01-library/03-search.md)).

Nguồn: [intent 2026-10-14-offline-movies](../../_intents/2026-10-14-offline-movies.md) câu 4, 5, 6, 9.

## 1. Chỗ đặt

- Bố cục hẹp: hàng **AI** trong nhóm Library and viewing, sau Playback; dòng giá trị `Claude · Apple Intelligence`
  (dịch phụ đề · AI Search, theo thứ tự hai hàng của trang AI) / `Not set up`.
- Bố cục rộng: mục thứ 10 trong cột mục, sau Playback.
- Mac: cửa sổ Settings không có Playback; tab **AI** đứng sau General (General · AI · Sources · Editing · Servers ·
  Cameras).
- Luật cũ "9 mục vừa 669pt" (01 §3) bỏ: người dùng chốt 2026-10-14 thêm mục 10; trên Duo trong cột mục cuộn
  một hàng. Sửa 01 §3 theo.

## 2. Loại nhà cung cấp

| Loại | Cài | Dùng cho | Hiện khi |
|---|---|---|---|
| Apple Translation | không cần; gói ngôn ngữ tải lúc dùng lần đầu | chỉ dịch phụ đề | iOS 18+, macOS 15+ |
| Apple Intelligence | không cần | dịch phụ đề, AI Search | máy hỗ trợ + Apple Intelligence bật |
| Máy chủ trong nhà | tên · địa chỉ (`http://192.168.1.10:11434`) · model chọn từ danh sách máy chủ trả về · key (tuỳ) | dịch phụ đề, AI Search | luôn |
| Claude · ChatGPT · OpenRouter · Grok · Gemini | API key · model (danh sách của dịch vụ, có mặc định) | **chỉ dịch phụ đề** | luôn |
| Tương thích OpenAI khác | địa chỉ `https://…` · key · model | **chỉ dịch phụ đề** | luôn |

- Máy chủ trong nhà nói chuẩn OpenAI (Ollama cổng 11434, LM Studio cổng 1234); gợi ý sẵn hai cổng đó.
- Một máy có thể cài nhiều nhà cung cấp, kể cả hai cái cùng loại (hai key Claude khác nhau).

## 3. Trang AI

- Hai hàng chọn trên đầu: **Subtitle Translation** và **AI Search**, mỗi hàng một menu các nhà cung cấp hợp loại
  + `Off` (AI Search). Mặc định: Subtitle Translation = `Ask Each Time`; AI Search = Apple Intelligence nếu có, không
  thì Off.
- Nhóm **On This Device**: Apple Translation, Apple Intelligence (hàng chỉ đọc, dòng giá trị nói trạng thái).
- Nhóm **Providers**: các nhà cung cấp đã thêm, dòng giá trị `claude-sonnet-… · Key ends in 7Qx2`; nút **Add Provider…**.
- Thêm/sửa: chọn loại → form → **Test** gửi một yêu cầu một dòng (dịch "Hello" sang ngôn ngữ máy) → `Working ·
  0.8 s` hoặc lỗi đúng câu dịch vụ trả về. Save được cả khi chưa Test; Test lỗi thì hỏi lại trước khi Save.
- Ô key là ô bí mật; lưu xong chỉ hiện 4 ký tự cuối, không có nút hiện lại cả key.
- Xoá nhà cung cấp: vuốt hoặc nút cuối form, alert 2 nút; xoá luôn key trong Keychain. Đang được chọn ở hàng nào
  thì hàng đó về mặc định.
- Dưới nhóm cloud một dòng: "Requests go straight from this device to the service with your key. ShotDex has no
  server in between."

## 4. Dữ liệu

- Bảng **Nhà cung cấp AI** (migration `v36` cùng FS-23): id · loại · tên · địa chỉ · model · ngày thêm. Lựa chọn hai
  hàng ở kho cài đặt mặc định.
- **Key ở Keychain**, chỉ trên máy này (không đồng bộ iCloud Keychain), khoá theo id nhà cung cấp; không bao giờ
  vào database, log, thông báo lỗi, bản sao lưu.

## 5. AI Search

FS-01.03 §4 đổi: model là nhà cung cấp ở hàng **AI Search**, không cố định Apple Intelligence. Mọi luật khác giữ
(chỉ chạy khi bộ phân tích không hiểu hết, lớp chặn, chạy một lần lúc áp, Off thì giao diện không đổi gì).

- Hạn: 2 s trên máy; 8 s cho máy chủ trong nhà. Quá hạn hay lỗi → dùng kết quả bộ phân tích như hôm nay, không
  hộp lỗi.
- **Không dùng cloud** (người dùng chốt 2026-10-14): lời dặn model kèm vốn từ thật của thư viện, gồm tên địa
  điểm — gửi lên cloud là gửi nơi người dùng đã đến. Menu AI Search chỉ có Apple Intelligence, máy chủ trong nhà, Off.

## 6. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | iOS 26.5 sim (không Apple Intelligence), chưa thêm gì | mở Settings › AI | 2 hàng chọn: Subtitle Translation `Ask Each Time`, AI Search `Off`; On This Device chỉ có Apple Translation | ✅ iOS 18.6 `build/ui-drive/settings-ai-18` (Subtitle Translation `Ask Each Time`, AI Search `Off`, On This Device chỉ Apple Translation) + `AIProviderClientTests.choices`; sim 26.5 có Apple Intelligence `Ready` nên AI Search mặc định là nó (`scripts/settings-ai.json` 01) |
| AC-2 | form Claude, key `sk-ant-test…7Qx2` | Save | key nằm trong Keychain dưới id nhà cung cấp; bảng không có cột/giá trị nào chứa key; hàng hiện `Key ends in 7Qx2` | ✅ `AIProviderStoreTests.keyOnlyInKeychain` + `scripts/settings-ai.json` 05 (form, ô key bí mật, hàng `gpt-test · Key ends in 7Qx2`; chụp bằng nhà cung cấp tương thích OpenAI trỏ về máy chủ giả trên máy để không gửi key giả ra dịch vụ thật) |
| AC-3 | máy chủ giả chuẩn OpenAI ở 127.0.0.1:11434 trả 2 model | chọn Home Server, nhập địa chỉ | menu model có đúng 2 model; Test → `Working` | ✅ `AIProviderClientTests.listsModelsFromLocalServer` + `scripts/settings-ai.json` 02 (máy chủ giả 127.0.0.1:11434 trả 2 model, menu Model, Test `Working`) |
| AC-4 | máy chủ giả trả 401 | Test | `The service rejected the API key.`; Save hỏi lại trước khi lưu | ✅ `AIProviderClientTests.rejectedKeySaysSo` + `scripts/settings-ai.json` 03–04 (401 → `The service rejected the API key.`; Save hỏi `The test didn't work. Save anyway?`) |
| AC-5 | 1 nhà cung cấp Claude đang được chọn cho Subtitle Translation | xoá nó | Keychain không còn key; hàng Subtitle Translation về `Ask Each Time` | ✅ `AIProviderStoreTests.deleteRemovesKey` + `AIProviderClientTests.choices` (lựa chọn trỏ tới nhà cung cấp đã xoá về mặc định) + `scripts/settings-ai.json` 06 (xoá từ form, hai hàng biến mất) |
| AC-6 | AI Search = máy chủ giả trả lời sau 9 s, câu `ảnh hoàng hôn 85mm` | áp tìm | sau 8 s dùng kết quả bộ phân tích, không hộp lỗi | ⚠️ chưa có (`SearchServiceTests.networkModelTimesOutToParser`) |
| AC-7 | đã cài 1 Claude + 1 máy chủ trong nhà | mở menu AI Search | chỉ có Apple Intelligence (nếu máy có), máy chủ trong nhà, Off — không có Claude | 🟡 logic ✅ `AIProviderClientTests.choices` (menu AI Search chỉ Apple Intelligence, máy chủ trong nhà, Off); ảnh menu chờ task 27 |
| AC-8 | Duo trong 951×669, bố cục rộng | mở Settings | đủ 10 mục; cuộn cột mục tới Support và chạm được | ⚠️ chưa có |
| AC-9 | iPhone 17 + iOS 18.6 sim | mở Settings › AI | cả hai nhánh iOS cùng hàng, cùng nút | ✅ cùng hàng, cùng nút trên 26.5 (`settings-ai.json` 01) và 18.6 (`settings-ai-18` 01); khác duy nhất là hàng Apple Intelligence chỉ có ở máy hỗ trợ |
