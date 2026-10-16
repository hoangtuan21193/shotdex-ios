# FS-08.07 — AI: chọn ai giúp AI Search

`FS-08.07` · tier A · mã: `ShotDex/Features/Settings/AI/`, `ShotDex/Data/AI/`, `ShotDex/Domain/AI/` · board
`PH_SettingsAI`, `PH_SettingsAIProvider` · cập nhật 2026-10-16

**Một câu:** Settings › **AI** liệt kê những AI ShotDex dùng được — Apple Intelligence trên máy và máy chủ trong nhà
(Ollama, LM Studio) — và chọn cái nào lo **AI Search** ([FS-01.03 §4](../FS-01-library/03-search.md)).

Nguồn: [intent 2026-10-14-offline-movies](../../_intents/2026-10-14-offline-movies.md) câu 4, 5, 6, 9. Dịch phụ đề
và các dịch vụ cloud bằng API key đi cùng Movies sang app Movik (repo `movik-ios`) ngày 2026-10-16; ShotDex chỉ còn ảnh.

## 1. Chỗ đặt

- Bố cục hẹp: hàng **AI** trong nhóm Library and viewing, sau Playback; dòng giá trị là AI Search đang dùng
  (`Apple Intelligence`, `Mac Studio`) / `Not set up` khi Off.
- Bố cục rộng: mục thứ 10 trong cột mục, sau Playback.
- Mac: cửa sổ Settings không có Playback; tab **AI** đứng sau General (General · AI · Sources · Editing · Servers ·
  Cameras).
- Luật cũ "9 mục vừa 669pt" (01 §3) bỏ: người dùng chốt 2026-10-14 thêm mục 10; trên Duo trong cột mục cuộn
  một hàng. Sửa 01 §3 theo.

## 2. Loại nhà cung cấp

| Loại | Cài | Dùng cho | Hiện khi |
|---|---|---|---|
| Apple Intelligence | không cần | AI Search | máy hỗ trợ + Apple Intelligence bật |
| Máy chủ trong nhà | tên · địa chỉ (`http://192.168.1.10:11434`) · model chọn từ danh sách máy chủ trả về · key (tuỳ) | AI Search | luôn |

- Máy chủ trong nhà nói chuẩn OpenAI (Ollama cổng 11434, LM Studio cổng 1234); gợi ý sẵn hai cổng đó.
- Một máy có thể cài nhiều máy chủ.
- Dòng cloud (Claude, ChatGPT…) một database cũ còn giữ vẫn hiện ở Providers để xoá; không thêm mới được, và AI
  Search không bao giờ dùng chúng (§5).

## 3. Trang AI

- Một hàng chọn trên đầu: **AI Search**, menu Apple Intelligence (nếu máy có) · các máy chủ trong nhà · `Off`. Mặc
  định Apple Intelligence nếu có, không thì Off.
- Nhóm **On This Device**: Apple Intelligence (hàng chỉ đọc, dòng giá trị nói trạng thái); máy không hỗ trợ thì không
  có nhóm.
- Nhóm **Providers**: các máy chủ đã thêm, dòng giá trị `qwen3:14b · 192.168.1.10:11434`; nút **Add Provider…** mở
  thẳng form Home Server.
- Form → **Test** gửi một yêu cầu một dòng → `Working · 0.8 s` hoặc lỗi đúng câu máy chủ trả về. Save được cả khi
  chưa Test; Test lỗi thì hỏi lại trước khi Save.
- Ô key là ô bí mật; lưu xong chỉ hiện 4 ký tự cuối, không có nút hiện lại cả key.
- Xoá: vuốt hoặc nút cuối form, alert 2 nút; xoá luôn key trong Keychain. Đang được chọn cho AI Search thì hàng về
  mặc định.
- Dưới Providers một dòng: "Ollama or LM Studio on a computer at home. Searches go straight from this device to it;
  ShotDex has no server in between."

## 4. Dữ liệu

- Bảng **Nhà cung cấp AI** (tạo ở migration `v36`; các bảng phim cùng migration đó đã bị `v39-dropMovies` xoá): id · loại · tên · địa chỉ · model · ngày thêm. Lựa chọn AI
  Search ở kho cài đặt mặc định.
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
| AC-1 | sim chưa thêm gì | mở Settings › AI | 1 hàng chọn AI Search: `Off` trên máy không Apple Intelligence, `Apple Intelligence` trên máy có | ✅ `AIProviderClientTests.choices` + ảnh iPhone 17 26.5 ngày 2026-10-16 (AI Search `Apple Intelligence`, On This Device `Ready`) |
| AC-2 | form Home Server có key `sk-test…7Qx2` | Save | key nằm trong Keychain dưới id nhà cung cấp; bảng không có cột/giá trị nào chứa key; hàng hiện `Key ends in 7Qx2` | ✅ `AIProviderStoreTests.keyOnlyInKeychain` |
| AC-3 | máy chủ giả chuẩn OpenAI ở 127.0.0.1:11434 trả 2 model | Add Provider…, nhập địa chỉ | menu model có đúng 2 model; Test → `Working` | ✅ `AIProviderClientTests.listsModelsFromLocalServer` + `scripts/settings-ai.json` 02 |
| AC-4 | máy chủ giả trả 401 | Test | `The service rejected the API key.`; Save hỏi lại trước khi lưu | ✅ `AIProviderClientTests.rejectedKeySaysSo` |
| AC-5 | 1 máy chủ đang được chọn cho AI Search | xoá nó | Keychain không còn key; AI Search về mặc định | ✅ `AIProviderStoreTests.deleteRemovesKey` + `AIProviderClientTests.choices` + `scripts/settings-ai.json` 04 |
| AC-6 | AI Search = máy chủ giả trả lời sau 9 s, câu `ảnh hoàng hôn 85mm` | áp tìm | sau 8 s dùng kết quả bộ phân tích, không hộp lỗi | ✅ `SearchServiceTests.networkModelTimesOutToParser` |
| AC-7 | database còn 1 dòng Claude + 1 máy chủ trong nhà | mở menu AI Search | chỉ có Apple Intelligence (nếu máy có), máy chủ trong nhà, Off — không có Claude | ✅ `SearchServiceTests.cloudProviderNeverUsed` + `AIProviderClientTests.choices` |
| AC-8 | Duo trong 951×669, bố cục rộng | mở Settings | đủ 10 mục; cuộn cột mục tới Support và chạm được | ⚠️ chưa có |
| AC-9 | iPhone 17 + iOS 18.6 sim | mở Settings › AI | cả hai nhánh iOS cùng hàng, cùng nút | ⚠️ chưa chụp lại sau 2026-10-16 (trước đó ✅ `settings-ai-18`) |
