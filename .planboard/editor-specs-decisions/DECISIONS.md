# Các điểm cần quyết — FS-03.13…16 — các quyết định

> Chốt 2026-09-28 sau 1 vòng · nguồn: .planboard/editor-specs-decisions/plan.json

| ID | Quyết định | Kết quả | Lựa chọn |
|---|---|---|---|
| D1 | [13·Q1] Panel có được đổi chiều cao theo ảnh (344 / 264 / 315) thay vì cố định 264 không? | OK | 344 / 264 / 315 theo phần đen của ảnh |
| D2 | [13·Q2] Khi sửa nhiều ảnh cùng lúc, chiều cao panel tính theo ảnh nào? | OK | Theo ảnh đang mở |
| D3 | [13·Q3] Cụm nút băng trên cách mép màn 10pt (như canvas) hay 20pt (như luật cũ)? | OK | Chờ số đo đảo thật rồi quyết (khác đề xuất) |
| D4 | [13·Q6] Thanh 6 công cụ có thay hẳn bánh xe nhóm ở mọi layout không sidebar, kể cả Duo màn ngoài? | OK | Bỏ hẳn bánh xe |
| D5 | [13·Q4] Mục “gọi lại bản đã lưu / đổi nguồn” của ⋯ hôm nay sẽ đi đâu? | OK | Thêm vào cuối ⋯ khi có |
| D6 | [13·Q5] Giữ lâu trên ảnh để xem ảnh gốc có dùng được ở Presets không, hay chỉ ở Edit? | OK | Edit và Presets |
| D7 | [13·Q7a] Chạm ✕ trong một công cụ có hỏi xác nhận không, và có Undo lại được không? | OK | Hỏi khi có ≥1 thay đổi |
| D8 | [13·Q7b] Trong một công cụ, Undo dừng ở lúc vào công cụ hay lùi tiếp vào các bước trước đó? | OK | Dừng ở lúc vào |
| D9 | [13·Q8a] Trên iPhone, Edit giữ 9 nhóm phẳng hay gom về 5 nhóm như sidebar iPad? | OK | Hai mô hình: phone 9, sidebar 5 |
| D10 | [13·Q8b] Nhóm chỉnh màu theo vùng tối/trung/sáng tên là “Grading” hay “Grade”? | OK | Grading |
| D11 | [13·Q9] Curve chuyển hẳn vào panel ở mọi layout, hay vẫn giữ kiểu vẽ đè lên ảnh như một tuỳ chọn? | OK | Curve luôn trong panel |
| D12 | [13·Q10] Sáu chip Upright (Off · Auto · Level · Vertical · Full · Guided) xếp thế nào khi không được cuộn ngang? | OK | Hai hàng 3 + 3 (khác đề xuất) |
| D13 | [13·Q11] Straighten Tool: kéo một đường gần dọc (cột nhà, thân cây) thì dựng nó đứng thẳng hay bỏ qua? | OK | Dựng đứng, như Lightroom |
| D14 | [13·Q12 Transform] Trước khi FS-03.15 xong, các hàng Transform chưa làm được (Upright Auto, Guided, Aspect, Constrain Crop) hiện ra sao? | OK | Không hiện, giữ chỗ trong thứ tự |
| D15 | [13·Q13] Phủ đỏ của mask theo luật mới (hiện khi vẽ, mờ dần khi nhấc tay, chip Mask Overlay ghim lại) áp cho mọi layout hay chỉ iPhone? | OK | Luật mới cho mọi layout |
| D16 | [13·Q14] Thêm/trừ vùng vào một mask được chọn mọi loại vùng, hay chỉ 8 loại như canvas vẽ? | OK | Mọi loại, dựng từ danh sách |
| D17 | [13·Q12 Heal] Trước khi FS-03.15 xong, Heal theo bố cục mới hiện các hàng chưa có (Remove, Opacity, New Source, Visualize Spots, Spot Pins, Clear All) ra sao? | OK | Không hiện, giữ chỗ trong thứ tự |
| D18 | [13·Q15a] Bảy loại mực của bút Markup (Pen, Marker, Pencil, Fountain, Monoline, Watercolor, Crayon) chọn ở đâu khi không còn dải cuộn ngang? | OK | Chấm màu mở trang con (lưới mực + bảng màu) |
| D19 | [13·Q15b] Loại lớp khung thoại gọi là “Speech bubble” hay “Bubble”? | OK | đề xuất |
| D20 | [13·Q16] Lối mở Manage Looks (chọn nhiều, sắp xếp, xoá look) đặt ở đâu? | Không OK | — (theo ghi chú) |
| D21 | [13·Q17a] Filmstrip khi sửa nhiều ảnh có thu từ 124pt (ô 96, viền accent) về 56pt (ô 44, viền trắng) không? | OK | 56 / 44, viền trắng |
| D22 | [13·Q17b] Ô filmstrip bo góc 6 (như canvas) hay 8? | Không OK | — (theo ghi chú) |
| D23 | [13·Q18] Sync (áp chỉnh sửa sang các ảnh khác) có ở cả ⋯ lẫn cuối filmstrip, hay chỉ filmstrip? | OK | Chỉ cuối filmstrip (khác đề xuất) |
| D24 | [13·Q19] Mở xoay ngang cho cả app, chỉ editor, hay các màn tầng D (editor, Collage, Video Studio)? | Không OK | — (theo ghi chú) |
| D25 | [13·Q20a] Điều kiện nào đưa iPhone ngang vào bố cục cột phải: theo kích thước cửa sổ hay theo loại máy? | Không OK | — (theo ghi chú) |
| D26 | [13·Q20b] Cột phải khi iPhone ngang rộng 330 (canvas) hay 320 (mặc định sidebar có sẵn)? | Không OK | — (theo ghi chú) |
| D27 | [13·Q20c] Ở iPhone ngang, histogram và filmstrip đặt ở đâu? | Không OK | — (theo ghi chú) |
| D28 | [13·Q21] Trên iPhone Pro Max xoay ngang, giữ lâu trên ảnh là xem gốc hay mở menu ngữ cảnh? | Không OK | — (theo ghi chú) |
| D29 | [13·Q22.1] Trên Duo màn ngoài (326pt), hàng “Mask 1 ▼ · Mask Overlay · + · ⋯” giữ nguyên hay rút chip thành “Overlay”? | OK | Giữ “Mask Overlay”, đo trước |
| D30 | [13·Q22.2] Nhãn ô trong cột công cụ Duo cỡ 9,5pt (canvas) hay 10,5pt (token nhãn tab có sẵn)? | OK | 10,5 (token nhãn tab) |
| D31 | [13·Q22.3] Danh sách slider trên Duo màn ngoài cố định 300pt hay đổi theo phần đen của ảnh như iPhone? | OK | Cố định 300 |
| D32 | [13·Q22.4] Trên Duo màn ngoài, đang trong một công cụ thì chạm vào 5 ô công cụ còn lại của cột làm gì? | Không OK | — (theo ghi chú) |
| D33 | [13·Q22.5] Băng trên của Duo màn ngoài có thêm histogram không? | OK | Thêm histogram vào băng |
| D34 | [14·1] Kho My Looks lưu ở đâu khi cần thêm thứ tự, nguồn, mã lượt nhận và có thể cả ảnh xem trước? | OK | File JSON trong Application Support + thư mục ảnh |
| D35 | [14·5b] Có giữ file preset Lightroom gốc cạnh mỗi look đã nhập, để sau này quy đổi lại không? | OK | Giữ file gốc |
| D36 | [14·5a] Ship tính năng nhập preset trước FS-03.15 hay chờ FS-03.15 xong? | OK | Ship trước |
| D37 | [14·11] Preset có mask (kể cả preset “adaptive” Sky/Subject của Lightroom): bỏ mask, hay map các mask tự sinh theo nội dung? | OK | Bỏ hết mask |
| D38 | [14·6a] Rà soát pháp lý (chữ “Lightroom”, nhãn “(LR)”, dòng điều khoản) chặn bản phát hành nào? | Không OK | — (theo ghi chú) |
| D39 | [14·6b] Look nhập từ Lightroom mang nhãn “(LR)” hay “Imported”? | OK | Imported (khác đề xuất) |
| D40 | [14·6c] Sheet xuất .xmp có thêm câu “không liên quan / không được Adobe bảo trợ” không? | OK | Thêm một dòng (khác đề xuất) |
| D41 | [14·12] Ảnh xem trước nhúng trong file look khi chia sẻ: mặc định tắt, bật, hay bỏ hẳn? | OK | Bỏ hẳn, máy nhận tự render (khác đề xuất) |
| D42 | [14·2] Đường “Add to ShotDex” từ Messages/Mail có cần một share extension có vùng chia sẻ với app (App Group) không? | OK | Extension mới “Add to ShotDex” chỉ cho look |
| D43 | [14·3] Share extension làm gì với file look nhận được? | OK | Chỉ kiểm cỡ + chép byte |
| D44 | [14·4c] File look mở từ AirDrop/Files được chép vào app rồi xoá, hay mở tại chỗ? | OK | Chép vào, xoá sau khi nhập |
| D45 | [14·4a] Gói nhiều look dùng cùng loại file .shotdexlook, hay một loại riêng .shotdexlooks? | Không OK | — (theo ghi chú) |
| D46 | [14·4b] Loại file nhập .xmp, .lrtemplate, .cube khai theo định danh của chủ định dạng, hay định danh riêng của ShotDex? | OK | Định danh riêng com.hoangtuan.shotdex.imported.* |
| D47 | [14·10] Xuất .shotdexlook cho một look dùng LUT đã nhập: nhúng bảng LUT vào file hay bỏ? | OK | Nhúng bảng .cube |
| D48 | [14·7] Có nhận file zip preset không, và nếu có thì giải nén bằng gì? | OK | V1 không nhận zip |
| D49 | [14·8] Có chốt nguyên bảng trần kích thước khi đọc preset (5 MB/file, DNG 200 MB, zip 50/500/250 MB, 500 preset/lượt, XML 64 tầng, Lua 32 tầng) không? | OK | đề xuất |
| D50 | [14·9] Nhập một preset trùng tên với look đã có thì làm gì? | OK | Thêm hậu tố; trùng cả nội dung thì bỏ qua |
| D51 | [15a·6] Curve vùng (Shadows · Darks · Lights · Highlights) nướng chung bảng tra với curve điểm, hay là một pass riêng trước Light? | OK | Chung bảng tra với curve điểm |
| D52 | [15a·5] Chuyển ảnh sang đen trắng (B&W) chạy đầu chuỗi như hôm nay, hay dời vào chặng Color sau cân bằng trắng và Light? | OK | Dời vào chặng Color |
| D53 | [15a·4] Calibration (dời ba màu cơ bản) chạy ngay sau Lens Blur, trước Light, hay chung chặng Color sau Light? | OK | Sau Lens Blur, trước Light |
| D54 | [15b·7] Tối góc ống kính chỉnh tay chạy trong không gian tuyến tính ngay sau Lens Blur, hay trong lượt Optics sau curve? | OK | Tuyến tính, sau Lens Blur |
| D55 | [15b·8] Vignette (Effects) và Grain dời ra sau crop và mask, hay giữ chạy trước crop như hôm nay? | OK | Dời ra sau crop và mask |
| D56 | [15·1] Chế độ nắn thẳng Upright (Auto/Level/Vertical/Full) có đi theo look khi Copy Edits, Sync, My Looks không? | OK | Đi theo, tính lại trên ảnh đích |
| D57 | [15b·10] Upright lưu thành “chế độ + phép nắn đã giải” riêng, hay tiếp tục ghi thẳng vào ba slider Geometry? | OK | Lưu chế độ + phép nắn riêng |
| D58 | [15d·18] Vùng chọn tự sinh (matte của Subject, People, Object… và bản đồ lấp của Remove) tính lại mỗi lần mở, hay lưu vào kho riêng? | OK | Lưu file matte trong kho riêng |
| D59 | [15e·20] Có kèm model ước lượng độ sâu Depth Anything (~50 MB) để Lens Blur chạy cả trên ảnh không có bản đồ độ sâu không? | OK | Kèm vào app (khác đề xuất) |
| D60 | [15·2] Các pass render mới có phải vừa trần bộ nhớ extension (ảnh 12MP ≤ 120 MB) ngay từ bây giờ không? | OK | Hoãn ràng buộc, ghi ở EX-01 |
| D61 | [15·3] Lưu ảnh 100MP (Lens Blur + 3 vết Remove + 3 mask) được dùng tối đa bao nhiêu bộ nhớ? | OK | ≤ 1,5 GB |
| D62 | [15e·19] Lens Blur chạy đầu chuỗi nên mọi slider đều phải trả giá của nó — giữ mượt bằng cách nào? | OK | Dựng sẵn 8 mức mờ, chỉ trộn khi kéo Amount (khác đề xuất) |
| D63 | [15c·13] Vết Remove được giải ở cỡ preview 2400px — khi lưu ảnh đầy đủ thì phóng bản đồ lên, hay giải lại ở độ phân giải đầy đủ? | OK | Phóng bản đồ, tra pixel đầy đủ, vá mép |
| D64 | [15b·9] Upright Auto dò đường thẳng trong ảnh bằng cách nào? | OK | Vision tìm chân trời cho Level + bộ tự viết cho dọc (khác đề xuất) |
| D65 | [15b·11] Constrain Crop tắt thì phần góc trống sau khi nắn phối cảnh xử lý thế nào? | OK | Tắt thì kéo giãn mép như hôm nay |
| D66 | [15c·12] Remove (tô lên vật để xoá) lấp vùng bằng thuật toán nào? | Không OK | — (theo ghi chú) |
| D67 | [15d·16] Mask Subject có đổi nghĩa thành “mọi đối tượng, không cần chạm”, để Object lo phần chạm chọn từng vật không? | OK | Subject = mọi đối tượng; Object = chạm từng vật |
| D68 | [15d·17] Lưới chọn loại mask 4×3 đã đầy — thêm Object và People bằng cách dời Face Skin/Eyes/Lips vào People, hay mở lưới 4×4? | OK | Lưới 4×4, giữ ba ô khuôn mặt ngoài (khác đề xuất) |
| D69 | [15c·14] Sửa mắt đỏ: người dùng chạm vào từng mắt, hay có nút tự dò mọi con ngươi đỏ? | OK | Cả hai (khác đề xuất) |
| D70 | [15c·15] Red Eye đặt ở đâu trong giao diện? | OK | Ô thứ tư trong hàng chế độ Heal |
| D71 | [16·1] Các trường sửa ống kính (ba mức độ mạnh, công tắc, nguồn đã giải) nằm ở đâu trong recipe? | OK | Như A, bỏ thang RAW cũ, một công tắc |
| D72 | [16a·2] Dữ liệu sửa ống kính do hãng ghi trong file RAW: v1 đọc những hãng nào? | OK | Cả năm định dạng (khác đề xuất) |
| D73 | [16a·4] Sửa quang sai màu (viền đỏ/lam ở rìa ảnh) theo hồ sơ bằng một kernel mới, hay ba lượt warp? | OK | Kernel mới, gộp với méo một pass |
| D74 | [16b·7] Bảng dữ liệu ống kính (Lensfun, thêm tối góc và quang sai màu) được phép lớn tới đâu trong app? | OK | JSON thô, trần 4 MB |
| D75 | [16a·3] JPEG từ máy ảnh đã được máy sửa ống kính sẵn — ShotDex xử lý thế nào để không sửa hai lần? | OK | Đọc thẻ trạng thái; đã sửa thì không tự khớp và nói rõ |
| D76 | [16a·5] Chip “Remove CA” hôm nay (khử viền màu nhẹ, không theo hồ sơ ống) giữ, bỏ, hay ẩn khi ảnh đã có dữ liệu CA theo hồ sơ? | OK | Giữ |
| D77 | [16b·6] RAW có dữ liệu ống kính nhúng, nhưng người dùng bấm Change chọn một ống khác — bên nào thắng? | OK | Như A, thêm lối quay về dữ liệu trong ảnh |

## D1 — [13·Q1] Panel có được đổi chiều cao theo ảnh (344 / 264 / 315) thay vì cố định 264 không?
- **Chốt:** Nhận 344 / 264 / 315: panel 344 chỉ khi 80pt thêm lấy trọn từ phần đen (ảnh không nhỏ đi), Curve với ảnh dọc tạm cao 315; viết lại bốn chỗ đang ghi 264 cố định.
- **Vì sao:** Đây là luật nền của cả bố cục iPhone: mọi AC về khung ảnh, số hàng slider và Curve đều tính từ nó. Giữ 264 thì ảnh ngang (3:2, 16:9) bỏ phí 80pt đen và chỉ thấy 4 hàng slider thay vì 6. Vì sao phải hỏi: FS-03.12 §3, FS-03.01 §1, FS-03.03 §1 và DESIGN.md §10.3 đều ghi “264 cố định, không đổi chiều cao”.
- **Đã cân nhắc:** Giữ 264 mọi lúc
- **Lịch sử:** vòng 1 — OK

## D2 — [13·Q2] Khi sửa nhiều ảnh cùng lúc, chiều cao panel tính theo ảnh nào?
- **Chốt:** Tính theo ảnh đang mở — cùng luật với sửa một ảnh và khớp AC-42 đang viết (ảnh 3:4 trong phiên nhiều ảnh được panel 264). Spec chưa chọn; đây là phương án phần AC đã theo.
- **Vì sao:** Một phiên nhiều ảnh trộn ảnh ngang và dọc. Tính theo ảnh đang mở thì panel nhảy 80pt khi lướt filmstrip; cố định thì có ảnh chịu thiệt chỗ. Vì sao phải hỏi: intent chỉ nói “cố định trong một phiên sửa”, không nói tới phiên nhiều ảnh.
- **Đã cân nhắc:** Theo ảnh đầu phiên; 344 chỉ khi mọi ảnh trong phiên đều được 344
- **Lịch sử:** vòng 1 — OK

## D3 — [13·Q3] Cụm nút băng trên cách mép màn 10pt (như canvas) hay 20pt (như luật cũ)?
- **Chốt:** Chọn “Chờ số đo đảo thật rồi quyết” thay cho đề xuất.
- **Vì sao:** Sát mép quá thì góc bo của màn cắt mất nút; lùi vào 20pt thì cụm 120pt chạm Dynamic Island. Vì sao phải hỏi: FS-03.01 §3 đặt 20pt “để góc bo màn không cắt”, canvas đặt 10pt.
- **Đã cân nhắc:** 10pt, kiểm trên khung có mask; 20pt, nút 34 cách 4 (cụm 110)
- **Lịch sử:** vòng 1 — OK

## D4 — [13·Q6] Thanh 6 công cụ có thay hẳn bánh xe nhóm ở mọi layout không sidebar, kể cả Duo màn ngoài?
- **Chốt:** Bỏ hẳn bánh xe ở mọi layout không sidebar (iPhone dọc, iPhone ngang, Duo màn ngoài), viết lại ba tài liệu.
- **Vì sao:** Giữ bánh xe ở đâu đó là giữ hai cách tới cùng một công cụ, hai bộ test, và cú vuốt ngang sát cạnh vuốt-chuyển-app mà intent muốn bỏ. Vì sao phải hỏi: FS-03.01 §5, FS-03.12 §6 và DESIGN.md §10.3 đang mô tả bánh xe là “tầng cuộn ngang duy nhất”.
- **Đã cân nhắc:** Giữ bánh xe riêng cho Duo màn ngoài
- **Lịch sử:** vòng 1 — OK

## D5 — [13·Q4] Mục “gọi lại bản đã lưu / đổi nguồn” của ⋯ hôm nay sẽ đi đâu?
- **Chốt:** Thêm vào cuối ⋯, chỉ hiện khi ảnh có bản đã lưu / nguồn khác. Spec chưa chọn giữa (a) và (b); (c) trái luật.
- **Vì sao:** Danh sách ⋯ mới của intent không có mục này; bỏ quên là mất một chức năng đang có. Vì sao phải hỏi: FS-03.01 §3 đang liệt kê nó trong ⋯, còn FS-03.13 §3 cấm mất chức năng.
- **Đã cân nhắc:** Chuyển vào sheet lưu; Bỏ
- **Lịch sử:** vòng 1 — OK

## D6 — [13·Q5] Giữ lâu trên ảnh để xem ảnh gốc có dùng được ở Presets không, hay chỉ ở Edit?
- **Chốt:** Cho cả Edit và Presets: Presets không có cử chỉ nào khác trên ảnh nên không tranh chấp. Intent ghi “chỉ Edit”; phần lý lẽ của spec nghiêng về (b).
- **Vì sao:** Nút compare đã bỏ, nên giữ lâu là đường so sánh duy nhất. Chỉ ở Edit thì lúc thử look ở Presets — lúc hay so với gốc nhất — phải sang Edit mới so được.
- **Đã cân nhắc:** Chỉ Edit (như intent)
- **Lịch sử:** vòng 1 — OK

## D7 — [13·Q7a] Chạm ✕ trong một công cụ có hỏi xác nhận không, và có Undo lại được không?
- **Chốt:** Hỏi xác nhận chỉ khi phiên công cụ có ít nhất một thay đổi; ✕ vẫn trả recipe và độ sâu lịch sử về lúc vào (giữ AC-8). Spec chưa chọn; đây là gợi ý vì không mất việc mà vẫn khớp AC.
- **Vì sao:** ✕ bỏ mọi nét, vết, lớp vừa làm trong công cụ. Không hỏi và không Undo được thì một chạm nhầm mất 10 phút tô mask; hỏi mọi lần thì phiền người hay thử rồi huỷ.
- **Đã cân nhắc:** Chạy ngay, không hỏi, không Redo; ✕ là một bước Undo được
- **Lịch sử:** vòng 1 — OK

## D8 — [13·Q7b] Trong một công cụ, Undo dừng ở lúc vào công cụ hay lùi tiếp vào các bước trước đó?
- **Chốt:** Dừng ở lúc vào (nút Undo mờ), để ✕ và Undo cùng một mốc. Spec chưa chọn; đây là phương án giữ nghĩa của ✕ mà spec đã viết.
- **Vì sao:** Lùi tiếp thì người dùng có thể Undo xuyên qua lúc vào, và ✕ không còn nghĩa “về lúc vào”; dừng lại thì muốn sửa bước trước phải ✓ hoặc ✕ trước.
- **Đã cân nhắc:** Lùi tiếp qua lúc vào
- **Lịch sử:** vòng 1 — OK

## D9 — [13·Q8a] Trên iPhone, Edit giữ 9 nhóm phẳng hay gom về 5 nhóm như sidebar iPad?
- **Chốt:** Nhận hai mô hình: phone 9 nhóm phẳng (danh sách đằng nào cũng dài, mục lục 9 dòng ngắn hơn 5 thẻ lồng), sidebar giữ 5 nhóm.
- **Vì sao:** Hai mô hình nghĩa là cùng một thông số nằm ở nhóm khác nhau trên iPhone và iPad; một mô hình thì một bên phải chịu bố cục không hợp. Vì sao phải hỏi: FS-03.01 §5 và FS-03.09 §10 đang treo đúng câu này.
- **Đã cân nhắc:** Phone theo 5 nhóm, mục con thành nhãn phụ
- **Lịch sử:** vòng 1 — OK

## D10 — [13·Q8b] Nhóm chỉnh màu theo vùng tối/trung/sáng tên là “Grading” hay “Grade”?
- **Chốt:** Dùng “Grading” như canvas ở nhãn nhóm, mục lục và chip; chip hôm nay đổi theo. Spec chưa chọn, đây là gợi ý.
- **Vì sao:** 
- **Đã cân nhắc:** Grade
- **Lịch sử:** vòng 1 — OK

## D11 — [13·Q9] Curve chuyển hẳn vào panel ở mọi layout, hay vẫn giữ kiểu vẽ đè lên ảnh như một tuỳ chọn?
- **Chốt:** Curve luôn nằm trong panel ở mọi layout; viết lại FS-04.02.
- **Vì sao:** Giữ hai kiểu là hai thứ phải học và hai bộ test; bỏ hẳn lớp đè thì iPad/sidebar cũng phải đổi. Vì sao phải hỏi: FS-04.02 §1, §4 ghi “curve đè lên ảnh, không phải một màn riêng”.
- **Đã cân nhắc:** Giữ lớp đè ảnh như tuỳ chọn trong ⋯
- **Lịch sử:** vòng 1 — OK

## D12 — [13·Q10] Sáu chip Upright (Off · Auto · Level · Vertical · Full · Guided) xếp thế nào khi không được cuộn ngang?
- **Chốt:** Chọn “Hai hàng 3 + 3” thay cho đề xuất.
- **Vì sao:** Trên 402pt mỗi chip chỉ ~56pt mà “Vertical” cần ~66pt; xếp sai là chữ bị cắt hoặc lại phải cuộn ngang. Vì sao phải hỏi: FS-03.12 §4 cho dải >5 mục cuộn ngang, luật mới cấm.
- **Đã cân nhắc:** Một hàng, chữ co tối đa 0,85; Off tách riêng + 5 chip
- **Lịch sử:** vòng 1 — OK

## D13 — [13·Q11] Straighten Tool: kéo một đường gần dọc (cột nhà, thân cây) thì dựng nó đứng thẳng hay bỏ qua?
- **Chốt:** Dựng đường gần dọc đứng thẳng như Lightroom, cùng luật với Guided ở FS-03.15b (gần dọc thành dọc). Spec chưa chọn; intent chỉ nói “theo chân trời”.
- **Vì sao:** Bỏ qua thì ảnh kiến trúc, nội thất — nơi đường dọc rõ hơn chân trời — không dùng được công cụ; nhận thì một đường kéo chéo gần 45° có thể xoay ảnh ngược ý.
- **Đã cân nhắc:** Chỉ nhận đường gần ngang
- **Lịch sử:** vòng 1 — OK

## D14 — [13·Q12 Transform] Trước khi FS-03.15 xong, các hàng Transform chưa làm được (Upright Auto, Guided, Aspect, Constrain Crop) hiện ra sao?
- **Chốt:** Hàng chưa có thì không hiện, thứ tự giữ chỗ; hiện ra khi FS-03.15 land. Spec chưa chọn; đây là gợi ý vì không có nút chết và Transform land được ngay.
- **Vì sao:** Hiện nút không làm gì là một thao tác chết im lặng; chặn cả Transform thì Crop huỷ được và Straighten Tool mới phải chờ FS-03.15. Vì sao phải hỏi: 13b §3 dựa vào thông số FS-03.15 chưa có trong recipe.
- **Đã cân nhắc:** Hiện mờ 0,35 kèm lý do; Chặn phần Transform tới khi FS-03.15 xong
- **Lịch sử:** vòng 1 — OK

## D15 — [13·Q13] Phủ đỏ của mask theo luật mới (hiện khi vẽ, mờ dần khi nhấc tay, chip Mask Overlay ghim lại) áp cho mọi layout hay chỉ iPhone?
- **Chốt:** Nhận luật mới cho mọi layout, viết lại FS-03.05 §6–7, thêm thời gian mờ dần 1,5s vào DESIGN.md.
- **Vì sao:** Hai luật cho một nút cùng tên trên iPhone và iPad là một hành vi phải học hai lần và hai bộ test; áp mọi nơi thì iPad cũng đổi. Vì sao phải hỏi: FS-03.05 §6 ghi phủ đỏ “bật và giữ” và “slider luôn thắng, không ngoại lệ”; canvas đổi cả hai vế. Số 1,5s chưa có trong DESIGN.md.
- **Đã cân nhắc:** Luật mới chỉ trên phone
- **Lịch sử:** vòng 1 — OK

## D16 — [13·Q14] Thêm/trừ vùng vào một mask được chọn mọi loại vùng, hay chỉ 8 loại như canvas vẽ?
- **Chốt:** Mọi loại, lưới dựng từ danh sách đầy đủ — đúng luật không mất chức năng.
- **Vì sao:** Chỉ 8 loại là mất Background, Color, Luminance, Depth khi cộng/trừ — đúng những loại hay dùng để trừ (vd bỏ trời theo độ sáng). Vì sao phải hỏi: canvas bảng L3 vẽ lưới 8 ô, FS-03.05 §4 cho mọi loại.
- **Đã cân nhắc:** 8 loại như canvas
- **Lịch sử:** vòng 1 — OK

## D17 — [13·Q12 Heal] Trước khi FS-03.15 xong, Heal theo bố cục mới hiện các hàng chưa có (Remove, Opacity, New Source, Visualize Spots, Spot Pins, Clear All) ra sao?
- **Chốt:** Hàng chưa có thì không hiện, thứ tự giữ chỗ — cùng luật với Transform (thẻ 13·Q12 Transform). Spec chưa chọn, đây là gợi ý.
- **Vì sao:** Sáu trên tám control của panel Heal mới thuộc FS-03.15. Ẩn thì panel còn thưa như hôm nay; hiện mờ thì nhiều nút chết; chờ thì Heal chưa có ✕ để huỷ.
- **Đã cân nhắc:** Hiện mờ kèm lý do; Heal mới chỉ land cùng FS-03.15
- **Lịch sử:** vòng 1 — OK

## D18 — [13·Q15a] Bảy loại mực của bút Markup (Pen, Marker, Pencil, Fountain, Monoline, Watercolor, Crayon) chọn ở đâu khi không còn dải cuộn ngang?
- **Chốt:** Chạm chấm màu mở trang con trong panel gồm lưới mực + bảng màu, như trang bảng màu custom của FS-05.02. Spec chưa chọn; đây là phương án theo hướng canvas.
- **Vì sao:** Canvas nói “mực ở chấm màu” nhưng không vẽ bề mặt mở ra; chọn sai là giấu 6 loại mực sau một chạm không ai đoán ra, hoặc tốn thêm một hàng panel. Vì sao phải hỏi: FS-05.01 §4 đặt 7 loại mực trên dải chip cuộn ngang, nay cấm.
- **Đã cân nhắc:** Thêm một hàng 7 ô mực chia đều
- **Lịch sử:** vòng 1 — OK

## D19 — [13·Q15b] Loại lớp khung thoại gọi là “Speech bubble” hay “Bubble”?
- **Chốt:** Giữ “Speech bubble” như FS-05.01 — “Bubble” đã là tên một hình bokeh của Lens Blur (FS-03.15e), trùng tên dễ nhầm.
- **Vì sao:** 
- **Lịch sử:** vòng 1 — OK

## D20 — [13·Q16] Lối mở Manage Looks (chọn nhiều, sắp xếp, xoá look) đặt ở đâu?
- **Chốt:** Không OK — hướng thay thế theo ghi chú: “không cần màn hình Manage Looks nên không cần cho vào ⋯  ở màn hình presets, My looks hay LUT, hold vào bất kỳ cái nào cũng sẽ hiện option rename, share, export as và delete. Option delete k hiện ở những preset có sẵn trong app.”
- **Vì sao:** Đặt chỗ khó thấy thì tính năng sắp xếp look coi như không có; thêm nút vào dải nguồn thì ba chip Presets · My Looks · LUTs hẹp lại. Vì sao phải hỏi: intent chỉ ghi “⋯ tab → Manage Looks”, không rõ ⋯ nào.
- **Đã cân nhắc:** Nút ⋯ 30×30 cuối dải nguồn khi ở My Looks
- **Lịch sử:** vòng 1 — Không OK: “không cần màn hình Manage Looks nên không cần cho vào ⋯  ở màn hình presets, My looks hay LUT, hold vào bất kỳ cái nào cũng sẽ hiện option rename, share, export as và delete. Option delete k hiện ở những preset có sẵn trong app.”

## D21 — [13·Q17a] Filmstrip khi sửa nhiều ảnh có thu từ 124pt (ô 96, viền accent) về 56pt (ô 44, viền trắng) không?
- **Chốt:** Nhận 56 / 44, viền trắng; viết lại FS-03.09b §2 và DESIGN.md §10.3.
- **Vì sao:** Filmstrip 124 ăn thẳng vào chiều cao ảnh; viền accent phạm luật “accent chỉ trên Save”. Vì sao phải hỏi: FS-03.09b §2 và DESIGN.md §10.3 ghi 124 / 96 và “viền accent = đang sửa”.
- **Đã cân nhắc:** Giữ 124 / 96
- **Lịch sử:** vòng 1 — OK

## D22 — [13·Q17b] Ô filmstrip bo góc 6 (như canvas) hay 8?
- **Chốt:** Không OK — hướng thay thế theo ghi chú: “bo góc 6”
- **Vì sao:** 
- **Lịch sử:** vòng 1 — Không OK: “bo góc 6”

## D23 — [13·Q18] Sync (áp chỉnh sửa sang các ảnh khác) có ở cả ⋯ lẫn cuối filmstrip, hay chỉ filmstrip?
- **Chốt:** Chọn “Chỉ cuối filmstrip” thay cho đề xuất.
- **Vì sao:** Chỉ filmstrip thì khi tràn viền (filmstrip ẩn) và với VoiceOver không có đường tới Sync; hai chỗ thì trái “một hành động — một chỗ”.
- **Đã cân nhắc:** Cả hai
- **Lịch sử:** vòng 1 — OK

## D24 — [13·Q19] Mở xoay ngang cho cả app, chỉ editor, hay các màn tầng D (editor, Collage, Video Studio)?
- **Chốt:** Không OK — hướng thay thế theo ghi chú: “khoá iPhone chỉ dọc, editor cũng k xoay, chỉ dọc thôi”
- **Vì sao:** Mở cả app là lộ Library, Statistics, Settings ở bố cục ngang chưa ai thiết kế; chỉ editor thì xoay máy giữa app không có gì xảy ra cho tới khi vào editor. Vì sao phải hỏi: project hôm nay khoá iPhone chỉ dọc.
- **Đã cân nhắc:** Cả app; Chỉ màn tầng D
- **Lịch sử:** vòng 1 — Không OK: “khoá iPhone chỉ dọc, editor cũng k xoay, chỉ dọc thôi”

## D25 — [13·Q20a] Điều kiện nào đưa iPhone ngang vào bố cục cột phải: theo kích thước cửa sổ hay theo loại máy?
- **Chốt:** Không OK — hướng thay thế theo ghi chú: “khoá iPhone chỉ dọc, editor cũng k xoay, chỉ dọc thôi”
- **Vì sao:** iPhone ngang cao 402 < 600 nên hôm nay rơi về slab dọc — ảnh bị ép còn một dải. Luật theo loại máy lệch nguyên tắc “hỏi kích thước, đừng hỏi idiom” và bỏ sót cửa sổ Stage Manager thấp trên iPad. Vì sao phải hỏi: cổng sidebar của DESIGN.md §10.3 đòi cao ≥600.
- **Đã cân nhắc:** Theo loại máy: phone + ngang
- **Lịch sử:** vòng 1 — Không OK: “khoá iPhone chỉ dọc, editor cũng k xoay, chỉ dọc thôi”

## D26 — [13·Q20b] Cột phải khi iPhone ngang rộng 330 (canvas) hay 320 (mặc định sidebar có sẵn)?
- **Chốt:** Không OK — hướng thay thế theo ghi chú: “khoá iPhone chỉ dọc, editor cũng k xoay, chỉ dọc thôi”
- **Vì sao:** 
- **Đã cân nhắc:** 330, thêm vào DESIGN.md
- **Lịch sử:** vòng 1 — Không OK: “khoá iPhone chỉ dọc, editor cũng k xoay, chỉ dọc thôi”

## D27 — [13·Q20c] Ở iPhone ngang, histogram và filmstrip đặt ở đâu?
- **Chốt:** Không OK — hướng thay thế theo ghi chú: “khoá iPhone chỉ dọc, editor cũng k xoay, chỉ dọc thôi”
- **Vì sao:** Canvas không vẽ hai thứ này ở bố cục ngang; thiếu là mất chức năng so với dọc (trái luật không mất chức năng). Cột có đè vùng an toàn khi đảo nằm bên phải hay không cũng chưa đo.
- **Lịch sử:** vòng 1 — Không OK: “khoá iPhone chỉ dọc, editor cũng k xoay, chỉ dọc thôi”

## D28 — [13·Q21] Trên iPhone Pro Max xoay ngang, giữ lâu trên ảnh là xem gốc hay mở menu ngữ cảnh?
- **Chốt:** Không OK — hướng thay thế theo ghi chú: “khoá iPhone chỉ dọc, editor cũng k xoay, chỉ dọc thôi”
- **Vì sao:** Pro Max ngang là size class regular nên luật hiện tại sẽ dựng menu ngữ cảnh — cướp cú giữ-xem-gốc, lặp lại bug “kẹt bản gốc” đã ghi ở DESIGN.md §10.3.
- **Đã cân nhắc:** iPhone ngang dùng menu ngữ cảnh
- **Lịch sử:** vòng 1 — Không OK: “khoá iPhone chỉ dọc, editor cũng k xoay, chỉ dọc thôi”

## D29 — [13·Q22.1] Trên Duo màn ngoài (326pt), hàng “Mask 1 ▼ · Mask Overlay · + · ⋯” giữ nguyên hay rút chip thành “Overlay”?
- **Chốt:** Giữ nguyên chữ, đo trước; chỉ rút thành “Overlay” trên Duo ngoài nếu đo thấy cắt (AC-31 fail). Spec để câu này cho số đo.
- **Vì sao:** Không vừa thì tên mask thành “…” hoặc + / ⋯ bị đẩy ra ngoài khung (cột cuối của hàng ngang bị đẩy đi). Rút chữ thì một nút có hai tên trên hai màn.
- **Đã cân nhắc:** Rút thành “Overlay” trên Duo ngoài
- **Lịch sử:** vòng 1 — OK

## D30 — [13·Q22.2] Nhãn ô trong cột công cụ Duo cỡ 9,5pt (canvas) hay 10,5pt (token nhãn tab có sẵn)?
- **Chốt:** Dùng 10,5 có sẵn, đo “Transform” trong ô 52pt; chỉ thêm token 9,5 nếu đo thấy cắt. Spec chưa chọn, đây là gợi ý theo luật không bịa token.
- **Vì sao:** 9,5 là cỡ chữ mới không có trong DESIGN.md; 10,5 có thể làm “Transform” bị cắt trong ô 52pt.
- **Đã cân nhắc:** 9,5, thêm vào DESIGN.md
- **Lịch sử:** vòng 1 — OK

## D31 — [13·Q22.3] Danh sách slider trên Duo màn ngoài cố định 300pt hay đổi theo phần đen của ảnh như iPhone?
- **Chốt:** Cố định 300pt — 13a §2 đã ghi Duo màn ngoài không dùng luật 344/264. Spec chưa chọn; đây là phương án khớp phần thân spec.
- **Vì sao:** Cố định thì ảnh ngang trên Duo ngoài để trống phần đen; đổi theo ảnh thì thêm một luật chiều cao nữa cho một màn hiếm dùng.
- **Đã cân nhắc:** Theo phần đen như iPhone
- **Lịch sử:** vòng 1 — OK

## D32 — [13·Q22.4] Trên Duo màn ngoài, đang trong một công cụ thì chạm vào 5 ô công cụ còn lại của cột làm gì?
- **Chốt:** Không OK — hướng thay thế theo ghi chú: “✓ và ✕ button phải hiện ở chỗ thanh công cụ chiều dọc ở Duo, nên sẽ k có ô chết”
- **Vì sao:** Chạm để đổi thì khác iPhone (nơi phải ✓ hoặc ✕ trước) — một thói quen hai hành vi, và áp công cụ ngầm; mờ thì cột 56pt có 5 ô chết.
- **Đã cân nhắc:** Chạm = ✓ rồi đổi công cụ
- **Lịch sử:** vòng 1 — Không OK: “✓ và ✕ button phải hiện ở chỗ thanh công cụ chiều dọc ở Duo, nên sẽ k có ô chết”

## D33 — [13·Q22.5] Băng trên của Duo màn ngoài có thêm histogram không?
- **Chốt:** Thêm histogram 40×28 vào băng trước ⋯ — băng 326pt còn chỗ. Spec chỉ ghi nhận thiếu, đây là gợi ý.
- **Vì sao:** Canvas bỏ histogram ở Duo ngoài; không có là mất một chức năng iPhone có (luật “không mất chức năng”, dựng từ danh sách đầy đủ).
- **Đã cân nhắc:** Chấp nhận không có
- **Lịch sử:** vòng 1 — OK

## D34 — [14·1] Kho My Looks lưu ở đâu khi cần thêm thứ tự, nguồn, mã lượt nhận và có thể cả ảnh xem trước?
- **Chốt:** File JSON trong Application Support cộng một thư mục ảnh, cùng khuôn với kho LUT đã nhập.
- **Vì sao:** Đây là chỗ lưu dữ liệu người dùng: đổi chỗ sau khi có người dùng là phải chuyển dữ liệu. Kho cài đặt hôm nay là một mảng JSON nạp mỗi lần mở app — 300 preset ~1 MB và không chứa được ảnh. Vì sao phải hỏi: look là dữ liệu người dùng, không được vào photo_metadata (BD-02); kit và extension không được đụng GRDB.
- **Đã cân nhắc:** Giữ kho cài đặt, thứ tự = thứ tự mảng; Bảng GRDB riêng
- **Lịch sử:** vòng 1 — OK

## D35 — [14·5b] Có giữ file preset Lightroom gốc cạnh mỗi look đã nhập, để sau này quy đổi lại không?
- **Chốt:** Giữ file gốc cạnh look (phần “giữ file gốc” của phương án (c) trong 14b §5), để bản sau có nút quy đổi lại.
- **Vì sao:** Không giữ thì khi FS-03.15 thêm Calibration, B&W mixer, curve vùng…, preset đã nhập vẫn thiếu mãi — người dùng phải tìm lại file gốc để nhập lại. Giữ thì thêm một trường vào kho look (khó thêm lại sau khi đã nhập).
- **Đã cân nhắc:** Không giữ
- **Lịch sử:** vòng 1 — OK

## D36 — [14·5a] Ship tính năng nhập preset trước FS-03.15 hay chờ FS-03.15 xong?
- **Chốt:** Ship FS-03.14 trước (cùng với giữ file gốc ở thẻ 14·5b — tức phương án (c) của spec).
- **Vì sao:** Ship trước thì báo cáo nhập đầy dòng ✕ “not in ShotDex yet” cho Calibration, curve vùng, B&W mixer, Upright; chờ thì rào cản đổi app từ Lightroom còn nguyên lâu hơn.
- **Đã cân nhắc:** Chờ FS-03.15
- **Lịch sử:** vòng 1 — OK

## D37 — [14·11] Preset có mask (kể cả preset “adaptive” Sky/Subject của Lightroom): bỏ mask, hay map các mask tự sinh theo nội dung?
- **Chốt:** V1 bỏ hết mask, báo ✕ “Masks stay with each photo” — đúng lát cắt look của FS-03.10.
- **Vì sao:** Bỏ hết thì preset adaptive mất phần chính của nó; map thì phải đổi luật chung “look không mang mask” của FS-03 README và Copy/Sync.
- **Đã cân nhắc:** Map mask tự sinh (Subject, Sky, People), bỏ mask vẽ tay
- **Lịch sử:** vòng 1 — OK

## D38 — [14·6a] Rà soát pháp lý (chữ “Lightroom”, nhãn “(LR)”, dòng điều khoản) chặn bản phát hành nào?
- **Chốt:** Không OK — hướng thay thế theo ghi chú: “dùng Import XMP Preset Export XMP Preset rồi có câu giải thích ngắn kiểu: "Export presets in XMP format for use with Adobe Lightroom."”
- **Vì sao:** Dùng tên thương hiệu Adobe sai cách có thể bị App Store từ chối hoặc nhận khiếu nại sau khi phát hành — sửa lúc đó đắt hơn nhiều. Chặn cả TestFlight thì tính năng không có người thử thật trong lúc chờ.
- **Đã cân nhắc:** Chặn mọi phát hành tới khi xem xong
- **Lịch sử:** vòng 1 — Không OK: “dùng Import XMP Preset Export XMP Preset rồi có câu giải thích ngắn kiểu: "Export presets in XMP format for use with Adobe Lightroom."”

## D39 — [14·6b] Look nhập từ Lightroom mang nhãn “(LR)” hay “Imported”?
- **Chốt:** Chọn “Imported” thay cho đề xuất.
- **Vì sao:** “(LR)” nói rõ look đến từ đâu nhưng dùng tên viết tắt sản phẩm Adobe; “Imported” an toàn hơn nhưng không phân biệt preset Lightroom với look nhận từ đồng nghiệp.
- **Đã cân nhắc:** (LR)
- **Lịch sử:** vòng 1 — OK

## D40 — [14·6c] Sheet xuất .xmp có thêm câu “không liên quan / không được Adobe bảo trợ” không?
- **Chốt:** Chọn “Thêm một dòng” thay cho đề xuất.
- **Vì sao:** 
- **Đã cân nhắc:** Không thêm, trừ khi luật sư yêu cầu
- **Lịch sử:** vòng 1 — OK

## D41 — [14·12] Ảnh xem trước nhúng trong file look khi chia sẻ: mặc định tắt, bật, hay bỏ hẳn?
- **Chốt:** Chọn “Bỏ hẳn, máy nhận tự render” thay cho đề xuất.
- **Vì sao:** Ảnh xem trước là một tấm ảnh của người dùng rời máy; bật mặc định là gửi ảnh riêng đi mà người dùng có thể không để ý.
- **Đã cân nhắc:** Mặc định tắt, bật từng lần; Mặc định bật, nhớ lựa chọn cuối
- **Lịch sử:** vòng 1 — OK

## D42 — [14·2] Đường “Add to ShotDex” từ Messages/Mail có cần một share extension có vùng chia sẻ với app (App Group) không?
- **Chốt:** Extension mới “Add to ShotDex” chỉ cho look, có App Group; extension ảnh giữ quyền tối thiểu. Spec để ngỏ (b) hoặc (c) — AC-c9 viết theo (b); (c) là lùi an toàn nếu không muốn thêm target.
- **Vì sao:** Mở vùng chia sẻ cho extension ảnh là nới quyền của một extension cố ý giữ tối thiểu; thêm extension mới là thêm target, bản khai riêng tư và mục release-check; bỏ thì Messages/Mail chỉ còn “Open in ShotDex”. Vì sao phải hỏi: EX-03 §1 và NF-03 §1 ghi extension cố ý không có vùng chia sẻ với app.
- **Đã cân nhắc:** Mở rộng extension “Save to ShotDex” hiện có; Bỏ đường extension
- **Lịch sử:** vòng 1 — OK

## D43 — [14·3] Share extension làm gì với file look nhận được?
- **Chốt:** Chỉ kiểm cỡ và chép byte vào hộp thư chờ, báo “Added. Open ShotDex to use it.”; trần hộp thư 50 file / 50 MB.
- **Vì sao:** Extension có trần bộ nhớ thấp (NF-02 §3); đọc và giải mã trong extension là kéo bộ đọc look/preset vào ShotDexKit và mở công khai. Chỉ chép byte thì người dùng không thấy tên look cho tới khi mở app. Chỉ cần quyết nếu giữ đường extension (thẻ 14·2).
- **Đã cân nhắc:** Đọc .shotdexlook để hiện tên và ảnh xem trước; Đọc mọi định dạng, kể cả XMP
- **Lịch sử:** vòng 1 — OK

## D44 — [14·4c] File look mở từ AirDrop/Files được chép vào app rồi xoá, hay mở tại chỗ?
- **Chốt:** Chép vào hộp thư của app rồi xoá sau khi nhập — look được chép vào kho, không cần giữ file gốc.
- **Vì sao:** Mở tại chỗ cần quyền truy cập có phạm vi và giữ đường dẫn tới file người khác sở hữu (file bị xoá/di chuyển là hỏng); chép vào thì tốn một bản chép tạm.
- **Đã cân nhắc:** Mở tại chỗ
- **Lịch sử:** vòng 1 — OK

## D45 — [14·4a] Gói nhiều look dùng cùng loại file .shotdexlook, hay một loại riêng .shotdexlooks?
- **Chốt:** Không OK — hướng thay thế theo ghi chú: “không cho phép share nhiều Look cùng một lúc nữa, nên chỉ cần .shotdexlook”
- **Vì sao:** Đuôi file là thứ người dùng thấy và gửi cho nhau; đổi sau khi file đã lưu hành là file cũ không mở được. Hai loại là hai khai báo, hai biểu tượng, hai đường nhập.
- **Đã cân nhắc:** Loại riêng .shotdexlooks
- **Lịch sử:** vòng 1 — Không OK: “không cho phép share nhiều Look cùng một lúc nữa, nên chỉ cần .shotdexlook”

## D46 — [14·4b] Loại file nhập .xmp, .lrtemplate, .cube khai theo định danh của chủ định dạng, hay định danh riêng của ShotDex?
- **Chốt:** Định danh riêng dưới com.hoangtuan.shotdex.imported.*, khớp theo đuôi file. Spec chưa chọn — đây là gợi ý vì không đụng khai báo của ai.
- **Vì sao:** Khai sai thì ShotDex không hiện trong “Open in…” cho file đó, hoặc đụng khai báo của app khác và hành vi mở khó đoán. Hôm nay .cube chỉ khớp theo đuôi, không khai loại.
- **Đã cân nhắc:** Định danh kiểu chủ sở hữu định dạng
- **Lịch sử:** vòng 1 — OK

## D47 — [14·10] Xuất .shotdexlook cho một look dùng LUT đã nhập: nhúng bảng LUT vào file hay bỏ?
- **Chốt:** Nhúng bảng .cube vào file; máy nhận thêm LUT vào My LUTs, và Undo của lần nhận gỡ cả LUT.
- **Vì sao:** Không nhúng thì máy nhận render look như LUT đã bị xoá — look sai mà trông như lỗi. Nhúng thì file từ vài KB thành ~1 MB.
- **Đã cân nhắc:** Không nhúng, ghi dòng “LUT isn't included”
- **Lịch sử:** vòng 1 — OK

## D48 — [14·7] Có nhận file zip preset không, và nếu có thì giải nén bằng gì?
- **Chốt:** V1 không nhận zip: Files tự giải nén khi chạm, người dùng chọn nhiều file; tự viết bộ đọc (a) để bản sau. Spec ghi (c) là rẻ nhất, chưa chốt.
- **Vì sao:** Preset Lightroom hay được phát hành dạng zip, nhưng iOS không có API giải nén zip công khai. Thêm thư viện là lệch luật “phụ thuộc ngoài duy nhất là GRDB” (CLAUDE.md); tự viết là thêm bề mặt tấn công (zip bomb).
- **Đã cân nhắc:** Tự viết bộ đọc zip (lưu thẳng + deflate) bằng Compression; Thêm một thư viện SPM giải nén
- **Lịch sử:** vòng 1 — OK: “không nhận, chỉ cho phép share 1 lần 1 look”

## D49 — [14·8] Có chốt nguyên bảng trần kích thước khi đọc preset (5 MB/file, DNG 200 MB, zip 50/500/250 MB, 500 preset/lượt, XML 64 tầng, Lua 32 tầng) không?
- **Chốt:** Chốt nguyên bảng ở 14a §2 cho v1; đo lại trên một bộ preset thật trước /verify và chỉnh dòng nào lệch.
- **Vì sao:** Trần thấp quá thì preset thật (có RGBTable, DNG của bản di động) bị từ chối; cao quá thì một file độc hại làm app hết bộ nhớ. Các số là đề xuất, chưa đo trên preset thật.
- **Lịch sử:** vòng 1 — OK

## D50 — [14·9] Nhập một preset trùng tên với look đã có thì làm gì?
- **Chốt:** Thêm hậu tố (“Golden 2”); trùng cả tên lẫn nội dung thì ✕ “Already in My Looks” — nhập không bao giờ xoá look của người dùng.
- **Vì sao:** Ghi đè là xoá look người dùng tự làm mà không hỏi; từ chối thì preset hợp lệ không vào được. Vì sao phải hỏi: Save Current hôm nay ghi đè khi trùng tên (FS-03.02 §9).
- **Đã cân nhắc:** Ghi đè như Save Current; Từ chối, báo “already exists”
- **Lịch sử:** vòng 1 — OK

## D51 — [15a·6] Curve vùng (Shadows · Darks · Lights · Highlights) nướng chung bảng tra với curve điểm, hay là một pass riêng trước Light?
- **Chốt:** Nướng vùng rồi điểm vào cùng bảng tra 256 mức của curve RGB đang có — một lượt, đúng thứ tự Lightroom, không thêm pass.
- **Vì sao:** Thứ tự render là nền của mọi golden test; đổi sau là chụp lại golden. Pass riêng thêm chi phí mỗi khung và khác thứ tự Lightroom; nướng chung thì phải chứng minh bảng “vùng rồi điểm” khớp tính tay (AC-8).
- **Đã cân nhắc:** Pass riêng trước Light
- **Lịch sử:** vòng 1 — OK

## D52 — [15a·5] Chuyển ảnh sang đen trắng (B&W) chạy đầu chuỗi như hôm nay, hay dời vào chặng Color sau cân bằng trắng và Light?
- **Chốt:** Dời chuyển xám vào chặng Color, sau WB và Light — Temp đổi tông xám như Lightroom.
- **Vì sao:** Đầu chuỗi thì Temp/Tint không làm gì với ảnh xám — preset B&W Lightroom dùng Temp để đổi tông xám sẽ ra sai. Dời thì mọi ảnh B&W đã sửa ra khác (được phép vì app chưa phát hành) và golden toàn pipeline chụp lại.
- **Đã cân nhắc:** Giữ đầu chuỗi, mixer đọc màu gốc
- **Lịch sử:** vòng 1 — OK

## D53 — [15a·4] Calibration (dời ba màu cơ bản) chạy ngay sau Lens Blur, trước Light, hay chung chặng Color sau Light?
- **Chốt:** Ngay sau Lens Blur, trước Light, trong không gian tuyến tính — gần Lightroom nhất vì Calibration là một phần hồ sơ màu máy ảnh.
- **Vì sao:** Sau Light thì Exposure đã đẩy màu sang vùng khác trước khi calibrate — preset có Calibration (rất hay gặp trong preset giả phim) ra lệch. Trước Light thì thêm một pass màu riêng.
- **Đã cân nhắc:** Chung chặng Color, sau Light
- **Lịch sử:** vòng 1 — OK

## D54 — [15b·7] Tối góc ống kính chỉnh tay chạy trong không gian tuyến tính ngay sau Lens Blur, hay trong lượt Optics sau curve?
- **Chốt:** Không gian tuyến tính, ngay sau Lens Blur — như Lightroom và cùng chỗ với bù tối góc theo hồ sơ.
- **Vì sao:** Sau curve thì độ sáng đã bị uốn cong, bù tối góc sẽ sai (góc loang hoặc sáng quá). Vị trí này cũng phải khớp chỗ bù tối góc theo hồ sơ của FS-03.16.
- **Đã cân nhắc:** Trong lượt Optics sau curve
- **Lịch sử:** vòng 1 — OK

## D55 — [15b·8] Vignette (Effects) và Grain dời ra sau crop và mask, hay giữ chạy trước crop như hôm nay?
- **Chốt:** Dời vignette rồi grain ra sau mask, trước bước hạ cỡ preview.
- **Vì sao:** Trước crop thì cắt lệch một bên là vignette lệch tâm — sai nghĩa “post-crop vignette” mà preset Lightroom mang. Dời thì ảnh có vignette đã sửa ra khác và golden chụp lại.
- **Đã cân nhắc:** Giữ trước crop
- **Lịch sử:** vòng 1 — OK

## D56 — [15·1] Chế độ nắn thẳng Upright (Auto/Level/Vertical/Full) có đi theo look khi Copy Edits, Sync, My Looks không?
- **Chốt:** Chế độ Auto/Level/Vertical/Full đi theo và tính lại trên ảnh đích như preset Lightroom; Guided (đường guide vẽ tay) luôn ở lại ảnh gốc.
- **Vì sao:** Quyết định lát cắt look — thứ Copy/Sync/My Looks chép. Không đi theo thì preset Lightroom có Upright Auto mất phần đó; đi theo thì dán sang ảnh khác phải tính lại Upright trên ảnh đích.
- **Đã cân nhắc:** Không Upright nào đi theo
- **Lịch sử:** vòng 1 — OK

## D57 — [15b·10] Upright lưu thành “chế độ + phép nắn đã giải” riêng, hay tiếp tục ghi thẳng vào ba slider Geometry?
- **Chốt:** Lưu chế độ + phép nắn đã giải riêng, slider tay cộng lên trên; phép nắn giải một lần lúc bấm, không giải lại mỗi lượt render.
- **Vì sao:** Đây là bố cục recipe. Ghi vào slider thì recipe không biết ảnh đang ở “Auto” — preset không mang được Upright, và slider tay bị ghi đè. Lưu riêng là thêm một khối vào recipe.
- **Đã cân nhắc:** Giữ ghi vào slider
- **Lịch sử:** vòng 1 — OK

## D58 — [15d·18] Vùng chọn tự sinh (matte của Subject, People, Object… và bản đồ lấp của Remove) tính lại mỗi lần mở, hay lưu vào kho riêng?
- **Chốt:** Lưu file matte 8-bit ¼ độ phân giải trong kho riêng của app, khoá theo ảnh + vùng + nguồn; mất thì tính lại. Dùng chung cho bản đồ Remove.
- **Vì sao:** Vision có thể trả kết quả khác giữa hai bản iOS: tính lại thì mở một bản sửa sau khi cập nhật hệ điều hành có thể ra mask khác. Lưu thì tốn 100–400 KB mỗi mask và thêm một kho dữ liệu.
- **Đã cân nhắc:** Tính lại mỗi lần mở; Nhúng vào recipe
- **Lịch sử:** vòng 1 — OK

## D59 — [15e·20] Có kèm model ước lượng độ sâu Depth Anything (~50 MB) để Lens Blur chạy cả trên ảnh không có bản đồ độ sâu không?
- **Chốt:** Chọn “Kèm vào app” thay cho đề xuất.
- **Vì sao:** Kèm vào app là thêm ~50 MB tải về cho mọi người (cạnh model bầu trời 41 MB); tải theo yêu cầu thì cần mạng lần đầu — trái tinh thần “không cần mạng”; không kèm thì Lens Blur chỉ cho ảnh Portrait.
- **Đã cân nhắc:** Tải theo yêu cầu từ App Store; Không kèm — chỉ ảnh có độ sâu
- **Lịch sử:** vòng 1 — OK

## D60 — [15·2] Các pass render mới có phải vừa trần bộ nhớ extension (ảnh 12MP ≤ 120 MB) ngay từ bây giờ không?
- **Chốt:** Bỏ ràng buộc cho tới khi có extension render, ghi lại ở EX-01; đối chiếu lại FS-03.16 AC-6 cho khớp.
- **Vì sao:** Giữ ràng buộc là thêm test đo bộ nhớ cho mọi pass trong khi hôm nay không extension nào link renderer; bỏ thì ngày thêm extension render phải đo lại và có thể sửa pass. Vì sao phải hỏi: FS-16 §5 (grep 2026-09-25) nói widget/share/edit không link renderer, còn intent đòi pass mới vừa trần extension. Lưu ý FS-03.16 §6 và AC-6 lại giả định extension chia sẻ render có sửa ống kính.
- **Đã cân nhắc:** Giữ: mỗi pass có test bộ nhớ 12MP ≤ 120 MB
- **Lịch sử:** vòng 1 — OK

## D61 — [15·3] Lưu ảnh 100MP (Lens Blur + 3 vết Remove + 3 mask) được dùng tối đa bao nhiêu bộ nhớ?
- **Chốt:** Đỉnh ≤ 1,5 GB (vừa máy 6 GB); vượt trần thì giữ phiên và báo lỗi, không tạo ảnh rỗng.
- **Vì sao:** Trần cao quá thì máy 6 GB bị hệ thống giết app lúc lưu (mất phiên); thấp quá thì phải render theo ô, chậm và phức tạp hơn.
- **Đã cân nhắc:** ≤ 2 GB
- **Lịch sử:** vòng 1 — OK

## D62 — [15e·19] Lens Blur chạy đầu chuỗi nên mọi slider đều phải trả giá của nó — giữ mượt bằng cách nào?
- **Chốt:** Chọn “Dựng sẵn 8 mức mờ, chỉ trộn khi kéo Amount” thay cho đề xuất.
- **Vì sao:** Không xử lý thì kéo Exposure trên ảnh Portrait cũng chạy lại blur 8 lớp mỗi khung — giật. Hạ độ phân giải khi kéo bị FS-03.04 cấm (spec đã loại phương án đó).
- **Đã cân nhắc:** Nướng vào nền tương tác
- **Lịch sử:** vòng 1 — OK

## D63 — [15c·13] Vết Remove được giải ở cỡ preview 2400px — khi lưu ảnh đầy đủ thì phóng bản đồ lên, hay giải lại ở độ phân giải đầy đủ?
- **Chốt:** Phóng bản đồ lên rồi tra pixel ở độ phân giải đầy đủ, vá mép bằng phép sửa màu của Heal.
- **Vì sao:** Giải lại tốn hàng giây mỗi vết và bộ nhớ lớn (đụng trần 100MP); phóng bản đồ thì vùng lấp có thể mờ nếu vá mép không tốt. Vì sao phải hỏi: luật không hạ độ phân giải của FS-03.04.
- **Đã cân nhắc:** Giải lại ở độ phân giải đầy đủ
- **Lịch sử:** vòng 1 — OK

## D64 — [15b·9] Upright Auto dò đường thẳng trong ảnh bằng cách nào?
- **Chốt:** Chọn “Vision tìm chân trời cho Level + bộ tự viết cho dọc” thay cho đề xuất.
- **Vì sao:** Bộ dò yếu thì Auto nắn sai toà nhà; bộ dò nặng thì chạm Auto phải chờ. Guided không cần dò.
- **Đã cân nhắc:** Bộ tự viết có sẵn + ước lượng điểm tụ; Bộ tìm đoạn thẳng mới trên GPU ở 1024px
- **Lịch sử:** vòng 1 — OK

## D65 — [15b·11] Constrain Crop tắt thì phần góc trống sau khi nắn phối cảnh xử lý thế nào?
- **Chốt:** Bật = tự cắt về hình chữ nhật lớn nhất nằm trong ảnh sau nắn, giữ tỉ lệ đang khoá; tắt = kéo giãn mép như hôm nay.
- **Vì sao:** Để góc trống trong suốt như Lightroom là có thể lọt pixel trống vào ảnh lưu — JPEG/HEIC không có trong suốt nên thành viền đen hoặc trắng.
- **Đã cân nhắc:** Tắt thì góc trống trong suốt như Lightroom
- **Lịch sử:** vòng 1 — OK

## D66 — [15c·12] Remove (tô lên vật để xoá) lấp vùng bằng thuật toán nào?
- **Chốt:** Không OK — hướng thay thế theo ghi chú: “tạm bỏ nếu apple chưa hỗ trờ model nào”
- **Vì sao:** Lấp kém trên cỏ/tường là tính năng thành đồ chơi; model vá ảnh thì Apple chưa công bố — trái ràng buộc “chỉ model Apple công bố”. Bị chặn bởi thử nghiệm 1 (chất lượng, thời gian trên iPhone 12).
- **Đã cân nhắc:** Model vá ảnh Core ML; Chỉ nội suy màu như Heal
- **Lịch sử:** vòng 1 — Không OK: “tạm bỏ nếu apple chưa hỗ trờ model nào”

## D67 — [15d·16] Mask Subject có đổi nghĩa thành “mọi đối tượng, không cần chạm”, để Object lo phần chạm chọn từng vật không?
- **Chốt:** Subject = luôn mọi đối tượng, không cần chạm; Object = chạm chọn từng vật — đúng tên Lightroom.
- **Vì sao:** Giữ Subject như cũ (chạm vật nào lấy vật đó, chạm nền lấy tất cả) thì Object chỉ là tên thứ hai cho cùng việc; đổi thì người quen chạm Subject thấy khác, nhưng preset Lightroom map đúng hơn.
- **Đã cân nhắc:** Giữ Subject, Object là tên khác
- **Lịch sử:** vòng 1 — OK

## D68 — [15d·17] Lưới chọn loại mask 4×3 đã đầy — thêm Object và People bằng cách dời Face Skin/Eyes/Lips vào People, hay mở lưới 4×4?
- **Chốt:** Chọn “Lưới 4×4, giữ ba ô khuôn mặt ngoài” thay cho đề xuất.
- **Vì sao:** 4×4 thì ảnh dọc (panel 264) phải cuộn tới hàng 3 và 4; dời thì chỉnh da mặt, mắt, môi sâu thêm một chạm.
- **Đã cân nhắc:** Dời ba ô khuôn mặt vào People
- **Lịch sử:** vòng 1 — OK

## D69 — [15c·14] Sửa mắt đỏ: người dùng chạm vào từng mắt, hay có nút tự dò mọi con ngươi đỏ?
- **Chốt:** Chọn “Cả hai” thay cho đề xuất.
- **Vì sao:** Tự dò trên mắt không đỏ (mắt nâu tối) là làm tối oan; chỉ chạm thì ảnh đông người phải chạm từng mắt.
- **Đã cân nhắc:** Chạm + Vision căn tâm; Nút “Fix Red Eye” tự dò
- **Lịch sử:** vòng 1 — OK

## D70 — [15c·15] Red Eye đặt ở đâu trong giao diện?
- **Chốt:** Ô thứ tư trong hàng chế độ Heal: Remove · Heal · Clone · Red Eye.
- **Vì sao:** Thanh 6 công cụ của FS-03.13 không còn chỗ; giấu trong ⋯ thì khó tìm; thêm ô vào hàng chế độ Heal thì hàng chật hơn trên máy nhỏ.
- **Đã cân nhắc:** Mục trong ⋯ của Heal; Công cụ riêng
- **Lịch sử:** vòng 1 — OK

## D71 — [16·1] Các trường sửa ống kính (ba mức độ mạnh, công tắc, nguồn đã giải) nằm ở đâu trong recipe?
- **Chốt:** Ba mức + công tắc vào bộ thông số chỉnh, lựa chọn hồ sơ thêm loại nguồn, và bỏ hẳn thang RAW cũ — một công tắc cho mọi nguồn.
- **Vì sao:** Chỗ đặt quyết định Copy Edits/Sync có tự chép đúng hay không: ba mức phải đi theo look, nguồn đã giải thì không. Hôm nay có hai chỗ (thang RAW trong bộ thông số, lựa chọn hồ sơ riêng) — giữ cả hai là hai khái niệm cho một việc.
- **Đã cân nhắc:** Vào bộ thông số chỉnh; hồ sơ thêm loại nguồn; Một khối “sửa ống kính” riêng
- **Lịch sử:** vòng 1 — OK

## D72 — [16a·2] Dữ liệu sửa ống kính do hãng ghi trong file RAW: v1 đọc những hãng nào?
- **Chốt:** Chọn “Cả năm định dạng” thay cho đề xuất.
- **Vì sao:** Nhận nhiều hãng mà định dạng chưa rõ thì cả đợt trễ; ít quá thì người chụp Sony/Fuji — nhóm đông nhất có dữ liệu nhúng — chưa được gì. Cổng: spike với RAW thật của từng hãng.
- **Đã cân nhắc:** DNG + Sony + Fujifilm; Chỉ DNG trước
- **Lịch sử:** vòng 1 — OK

## D73 — [16a·4] Sửa quang sai màu (viền đỏ/lam ở rìa ảnh) theo hồ sơ bằng một kernel mới, hay ba lượt warp?
- **Chốt:** Kernel lấy mẫu mới đọc R, G, B ở ba bán kính, gộp với sửa méo trong một pass.
- **Vì sao:** Kernel warp của Core Image trả một toạ độ cho cả ba kênh nên không tách được đỏ/lam; ba lượt warp tốn ~3× thời gian mỗi khung (đích ≤ 8 ms, chưa đo).
- **Đã cân nhắc:** Ba lượt warp rồi ghép kênh
- **Lịch sử:** vòng 1 — OK

## D74 — [16b·7] Bảng dữ liệu ống kính (Lensfun, thêm tối góc và quang sai màu) được phép lớn tới đâu trong app?
- **Chốt:** JSON thô, trần 4 MB; vượt trần thì chuyển sang nén trong bundle.
- **Vì sao:** Bảng hôm nay 823 KB, thêm tối góc + CA ước 1–2 MB (chưa đo). Không đặt trần thì mỗi lần làm mới dữ liệu app phình dần; nén thì lần mở đầu chậm hơn; cắt bớt thì mất ống.
- **Đã cân nhắc:** Nén trong bundle, giải nén lần đầu dùng; Bỏ ống ngoài phạm vi (GoPro, drone, medium format)
- **Lịch sử:** vòng 1 — OK

## D75 — [16a·3] JPEG từ máy ảnh đã được máy sửa ống kính sẵn — ShotDex xử lý thế nào để không sửa hai lần?
- **Chốt:** Đọc thẻ trạng thái sửa trong maker notes của JPEG (Sony, Panasonic, OM; Fujifilm xác nhận ở spike): đã sửa thì không tự khớp và nói rõ lý do; câu chữ cần chốt thêm.
- **Vì sao:** Bật sửa lên ảnh máy đã nắn là méo ngược, tối góc thành sáng góc — người dùng khó nhận ra vì sao.
- **Đã cân nhắc:** Giữ bật tay như hôm nay; Bật mặc định cho JPEG, dựa vào B để tránh ảnh đã sửa
- **Lịch sử:** vòng 1 — OK

## D76 — [16a·5] Chip “Remove CA” hôm nay (khử viền màu nhẹ, không theo hồ sơ ống) giữ, bỏ, hay ẩn khi ảnh đã có dữ liệu CA theo hồ sơ?
- **Chốt:** Giữ, là “sửa CA không cần hồ sơ” — Lightroom cũng tách ô này khỏi phần Profile.
- **Vì sao:** Hai control cùng chữ “CA” dễ rối; bỏ thì ảnh không có hồ sơ ống mất đường sửa CA duy nhất, và thẻ AutoLateralCA của preset Lightroom (14b) mất chỗ đặt.
- **Đã cân nhắc:** Bỏ, nhường Defringe tím/lục của FS-03.15; Ẩn khi ảnh có dữ liệu CA theo hồ sơ
- **Lịch sử:** vòng 1 — OK

## D77 — [16b·6] RAW có dữ liệu ống kính nhúng, nhưng người dùng bấm Change chọn một ống khác — bên nào thắng?
- **Chốt:** Người dùng thắng (nguồn thành “Chosen by you”), và đầu danh sách chọn có một dòng quay về dữ liệu trong ảnh (câu chữ cần chốt).
- **Vì sao:** Dữ liệu nhúng luôn thắng thì người dùng không sửa được khi hãng ghi sai; người dùng thắng mà không có lối quay lại thì bấm nhầm là mất dữ liệu chuẩn của ảnh.
- **Đã cân nhắc:** Người dùng thắng; Dữ liệu nhúng luôn thắng, không có Change
- **Lịch sử:** vòng 1 — OK
