# FS-03.14 — Trao đổi preset Lightroom và chia sẻ look

`FS-03.14` · tier D · `ShotDex/Domain/Editing/LookPresetStore.swift` · `ShotDex/Features/Editing/`
· extension "Add to ShotDex" (target mới) · `ShotDexTests/LookExchange*Tests.swift` · cập nhật 2026-09-28

**Một câu:** người chụp mang thư viện preset Lightroom sang ShotDex, biết rõ từng preset sang được bao nhiêu,
và gửi / nhận từng look của mình qua AirDrop, Files, Messages như gửi một tấm ảnh.

Nguồn: intent [lightroom-preset-exchange](../../_intents/2026-09-27-lightroom-preset-exchange.md) (accepted) ·
trả lời câu treo số 2 của [editor-lightroom-feature-parity](../../_intents/2026-09-22-editor-lightroom-feature-parity.md).
Canvas hàng "Presets" PR1–PR9: <https://claude.ai/artifact/T4tEUQrJtxBbi48HokiL9F>.

## Các phần

| # | Phần | Trả lời |
|---|---|---|
| 14 | tài liệu này | phạm vi, luật chung, dữ liệu, ràng buộc, các quyết định đã chốt, câu treo |
| 14a | [Nhập và báo cáo](14a-import-and-report.md) | nhận định dạng nào, giới hạn đọc, báo cáo ✓/≈/✕, nhãn "Imported", trùng tên |
| 14b | [Quy đổi Lightroom → ShotDex](14b-lightroom-mapping.md) | bảng thẻ `crs:`, camera profile → film look, creative profile → LUT |
| 14c | [Xuất, chia sẻ, nhận, menu giữ lâu](14c-export-share-receive.md) | Export As ba định dạng, Share một look, AirDrop/Files/Messages, extension "Add to ShotDex", kho look |

Chỗ đặt nút (ô Import XMP Preset, menu giữ lâu) thuộc [FS-03.13](13-iphone-editor-layout.md) — tài liệu này
không đặc tả bố cục. Thông số mà preset đổ vào: [FS-03.15](15-lightroom-parameter-parity.md);
ba mức sửa ống kính: [FS-03.16](16-lens-correction-sources.md).

## 1. Người dùng cần gì

Thợ ảnh đổi app mang theo vài chục tới vài trăm preset tích luỹ nhiều năm. Không mang được là không đổi app.
Look tự làm trong ShotDex phải gửi được cho máy thứ hai hay cho đồng nghiệp.

## 2. Phạm vi

**Có:**
- Nhập `.xmp`, `.lrtemplate`, DNG có preset, `.shotdexlook`, `.cube` (chuyển sang tab LUTs); chọn nhiều file.
- Báo cáo từng preset sau khi nhập; nhãn "Imported" cho look đến từ preset Lightroom.
- Export As `.shotdexlook` · `.xmp` · `.cube`; Share **một** look mỗi lần, thành một file `.shotdexlook`.
- Giữ lâu bất kỳ ô nào ở Presets / My Looks / LUTs → **Rename · Share · Export As · Delete** (14c §3).
- Nhận qua AirDrop, Files, Messages/Mail ("Open in ShotDex") và extension mới "Add to ShotDex".

**Cố ý không có:**
- Duplicate look — Save Current trên ảnh đã áp look làm được việc đó, thêm một hàng menu không đáng.
- Màn quản lý look, chọn nhiều, kéo sắp xếp; chia sẻ nhiều look một lượt — menu giữ lâu từng ô là đủ.
- Nhận file zip — Files tự giải nén khi chạm, người dùng chọn nhiều file.
- Ảnh xem trước nhúng trong file look — máy nhận tự render từ ảnh của chính họ.
- Crop, mask (kể cả preset "adaptive"), markup, heal trong look — lát cắt của [FS-03.10](10-copy-paste-edits.md).
- Nhập camera profile (DCP) và `.lcp` — định dạng độc quyền của Adobe; chỉ map **theo tên** (14b §3).
- Đồng bộ look qua đám mây, thư viện look trực tuyến — ShotDex là local-only ([NF-03](../../04-non-functional-design/NF-03-privacy-and-security.md)).
- HDR (chế độ sửa HDR của Lightroom) — ngoài phạm vi FS-03.15, nên ở đây là ✕ có lý do.

## 3. Luật chung

- **File từ ngoài là dữ liệu không tin được**: đọc có trần kích thước, có schema version, một preset hỏng
  chỉ mất chính nó — cùng tinh thần decode khoan dung của recipe.
- **Không lặng lẽ mất gì**: mỗi thẻ Lightroom không sang nguyên vẹn đều có một dòng ≈ hoặc ✕ kèm lý do.
- **✓ nghĩa là "cùng slider, trong dải, quy đổi theo bảng"**, không phải "màu giống hệt Lightroom" — độ giống
  màu đo bằng ΔE ở thử nghiệm (§8), không hứa trong giao diện.
- **Save Current giữ nguyên hành vi hôm nay**: đặt tên, lưu tone · màu · curve · film look/LUT.
- **Không cần mạng**, không gửi byte nào ra khỏi máy ngoài file người dùng tự chia sẻ.
- **FS-03.14 ship trước FS-03.15**: thông số ShotDex chưa có thành dòng ✕ "not in ShotDex yet" (14b §5).

## 4. Dữ liệu

| | |
|---|---|
| Đọc từ | file người dùng chọn/nhận; kho My Looks; kho LUT đã nhập |
| Ghi vào | kho My Looks — file JSON trong Application Support ([14c §6](14c-export-share-receive.md#6-kho-look)); kho LUT (creative profile, `.cube`); hộp thư chờ trong App Group (extension "Add to ShotDex") |
| Người dùng tự nhập? | có — look là dữ liệu người dùng: **không bao giờ** vào `photo_metadata` ([BD-02 §1](../../01-basic-design/BD-02-database-design.md)) |

## 5. Ràng buộc

| Mặt | Ràng buộc |
|---|---|
| Bộ nhớ | extension "Add to ShotDex" dưới trần extension ([NF-02 §3](../../04-non-functional-design/NF-02-memory-and-resources.md)); không phân tích, không render trong extension |
| Kit | bộ đọc preset và bộ đọc look nằm trong app, **không** vào `ShotDexKit` — extension chỉ chép byte ([EX-01](../../03-extensions-and-integrations/EX-01-shotdexkit-and-edit-extension.md)) |
| Thiết bị | iPhone 402×874 · iPad 1376×1032 · Duo trong 951×669 · Duo ngoài 466×678 — cùng luồng, bố cục theo FS-03.13 |
| iOS 26 vs trước | không có nhánh `#available` riêng; file importer, share sheet, banner giống nhau |
| Thiết kế | banner nhận look dùng lại toast có Undo sẵn có, đậu **trên** panel ([DESIGN.md](../../../DESIGN.md) mục editor) — không bịa token |
| Truy cập | báo cáo đọc được bằng VoiceOver theo từng dòng; ✓/≈/✕ có nhãn chữ, không chỉ ký hiệu |

## 6. Đã chốt 2026-09-28

Lý do từng điểm: [DECISIONS.md](../../../.planboard/editor-specs-decisions/DECISIONS.md).

1. **Kho look** — file JSON trong Application Support + thư mục ảnh (D34). → [14c §6](14c-export-share-receive.md#6-kho-look)
2. **Giữ file preset Lightroom gốc** cạnh mỗi look đã nhập, để bản sau quy đổi lại (D35). → [14b §5](14b-lightroom-mapping.md#5-thẻ-chưa-có-chỗ-đặt)
3. **Ship trước FS-03.15**; thẻ chưa có chỗ đặt → ✕ "not in ShotDex yet" (D36). → [14b §5](14b-lightroom-mapping.md#5-thẻ-chưa-có-chỗ-đặt)
4. **Bỏ mọi mask** trong preset, kể cả preset "adaptive" (D37). → [14b §4](14b-lightroom-mapping.md#4-creative-profile-và-nhóm-bị-bỏ-qua)
5. **Nhãn "Import XMP Preset" / "Export XMP Preset"** kèm một câu giải thích; không có cổng pháp lý (D38). → [§7](#7-tên-thương-hiệu)
6. **Nhãn nguồn "Imported"**, không "(LR)" (D39). → [14a §4](14a-import-and-report.md#4-tên-nhãn-trùng-tên)
7. **Sheet xuất `.xmp` thêm một dòng** không liên quan / không được Adobe bảo trợ (D40). → [§7](#7-tên-thương-hiệu)
8. **Không ảnh xem trước nhúng** trong file look; máy nhận tự render (D41). → [14c §2](14c-export-share-receive.md#2-share)
9. **Extension mới "Add to ShotDex"** chỉ cho look, có App Group (D42). → [14c §4](14c-export-share-receive.md#4-nhận)
10. **Extension chỉ kiểm cỡ + chép byte** vào hộp thư chờ (D43). → [14c §4](14c-export-share-receive.md#4-nhận)
11. **File từ AirDrop/Files chép vào app**, xoá sau khi nhập (D44). → [14c §5](14c-export-share-receive.md#5-khai-báo-loại-file)
12. **Chia sẻ mỗi lần một look**; chỉ một loại file `.shotdexlook` (D45). → [14c §2](14c-export-share-receive.md#2-share)
13. **Định danh nhập riêng** `com.hoangtuan.shotdex.imported.*` cho `.xmp`/`.lrtemplate`/`.cube` (D46). → [14c §5](14c-export-share-receive.md#5-khai-báo-loại-file)
14. **`.shotdexlook` nhúng bảng LUT đã nhập** mà look dùng (D47). → [14c §1](14c-export-share-receive.md#1-export-as)
15. **Không nhận zip** ở v1 (D48). → [14a §1](14a-import-and-report.md#1-nhận-định-dạng-nào)
16. **Bảng trần kích thước** chốt như đề xuất, không có dòng zip (D49). → [14a §2](14a-import-and-report.md#2-giới-hạn-đọc)
17. **Trùng tên** → thêm hậu tố; trùng cả nội dung → bỏ qua (D50). → [14a §4](14a-import-and-report.md#4-tên-nhãn-trùng-tên)
18. **Không có màn Manage Looks**; giữ lâu mở menu bốn mục, Delete ẩn với preset có sẵn (D20). → [14c §3](14c-export-share-receive.md#3-menu-giữ-lâu)

## 7. Tên thương hiệu

- Không code, SDK, preset, profile, DCP hay `.lcp` nào của Adobe trong app hay trong bundle; bộ đọc/ghi tự
  viết theo XMP (ISO 16684-1) và đặc tả DNG công khai.
- Nhãn **"Import XMP Preset"** / **"Export XMP Preset"**, không logo, kèm câu giải thích "Import presets in XMP
  format from Adobe Lightroom." / "Export presets in XMP format for use with Adobe Lightroom."
- Sheet xuất `.xmp` có thêm một dòng: "ShotDex is not affiliated with or endorsed by Adobe."
- Chữ "Adobe"/"Lightroom" chỉ ở ba chỗ: câu giải thích, dòng từ chối bảo trợ, lý do trong báo cáo.
- Điều khoản sử dụng thêm một dòng: *chỉ chia sẻ look bạn có quyền chia sẻ*.
- Không có bước rà soát pháp lý chặn bản phát hành.

## 8. Câu hỏi còn treo

1. **Độ giống màu** `.xmp` → ShotDex: xử lý cùng bộ ảnh ở hai app, đo ΔE2000 trung bình và tệ nhất theo từng
   slider; kết quả thay hệ số quy đổi tạm ở 14b. Dùng chung với FS-03.15. → thử nghiệm.
2. **RGBTable** của creative profile có giải mã thành LUT 3D được không, cỡ bảng bao nhiêu. → thử nghiệm với
   vài profile bên thứ ba (không dùng profile của Adobe làm dữ liệu kiểm thử được commit).
3. **Danh sách thẻ `crs:`** của Lightroom 13–15 và cách nó ghi preset hiện nay (thẻ Look, nhóm mask,
   thứ tự Process Version) — bảng 14b là bản nháp. → agent `lightroom-parity` kiểm trước `/plan`.

## 9. Tiêu chí nghiệm thu chung

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-0.1 | máy ở chế độ máy bay, không Wi-Fi | nhập một `.xmp` 3 KB rồi Export As `.shotdexlook` | cả hai xong, không có lời gọi mạng nào (0 request trong log mạng của phiên) | `LookExchangeOfflineTests.importAndExportNeedNoNetwork` (test chặn mọi kết nối mạng) |

**Chưa chứng minh được:** mọi AC của FS-03.14 (chưa có code). Tổng: 1 ở đây + 12 ở 14a + 8 ở 14b + 12 ở 14c = **33**.

## 10. Tài liệu phải sửa theo khi làm

- [FS-03.02 §9](02-film-simulation-and-presets.md#9-my-looks): giữ lâu mở menu bốn mục thay vì chỉ Delete
  (Delete ẩn với preset có sẵn); kho look là file JSON trong Application Support; thứ tự vẫn mới nhất trước.
- [EX-03](../../03-extensions-and-integrations/EX-03-share-extension.md) và
  [NF-03](../../04-non-functional-design/NF-03-privacy-and-security.md) §1, §4: thêm extension "Add to ShotDex"
  có App Group; "Save to ShotDex" giữ nguyên quyền tối thiểu.
- Dòng điều khoản "chỉ chia sẻ look bạn có quyền chia sẻ" vào nơi điều khoản sử dụng đang sống.
- [FS-03.13 13d §1](13d-presets-batch-devices.md#1-presets): bỏ Manage Looks; dòng `.xmp` của Export As là "Export XMP Preset".
