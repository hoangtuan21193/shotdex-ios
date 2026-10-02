# Review UI/UX ShotDex — chọn việc cần làm (2/10) — các quyết định

Chốt 2026-10-02 sau 1 vòng. Nguồn: review/merged.md (88 mục) và challenge.md trong scratchpad của phiên; plan.json ở thư mục này.

| ID | Quyết định | Kết quả | Lựa chọn |
|---|---|---|---|
| Q1 | M-14 · Photo Info và Burst có nút Done | OK | — |
| Q2 | M-10 · Lỗi Favorite/Delete ở Viewer và Compare phải hiện ra | OK | — |
| Q3 | M-26 · Dòng gợi ý 'Try:' đang là tiếng Việt cứng trong UI tiếng Anh | OK | — |
| Q4 | M-58 · Số trong Statistics có dấu phân cách hàng nghìn | OK | — |
| Q5 | M-59 · Thêm chart Top Lens vào bộ mặc định | OK | — |
| Q6 | M-07 · Xoá kết nối server dùng .alert thay confirmationDialog | OK | — |
| Q7 | M-16 · Đóng Viewer thì lưới cuộn tới ảnh vừa xem | OK | — |
| Q8 | Nhóm nhỏ còn lại (M-09, M-56, M-75, M-78, M-87) | OK | — |
| D1 | M-01 · Merge All Groups ghi vào thư viện trước khi xác nhận | OK | Merge chỉ ở Exact + alert + bỏ try? |
| D2 | M-03 · Dấu xoá ở Duplicates mất khi đổi tab/Back; đánh dấu được cả nhóm | OK | Giữ trong bộ nhớ của phiên |
| D3 | M-04 · Ô ảnh trùng cho thấy bản nào đáng giữ | OK | — |
| D4 | M-02 · Resize với Delete Originals bật sẵn | OK | Giữ bật, nói rõ ở nút + toast |
| D5 | M-08 · Hide nói tìm lại ở đâu | OK | — |
| V1 | M-13 · Compare zoom 5× không soi được độ nét | OK | Bản phân giải cao theo vùng, chặn ~3000px |
| V2 | M-15 · Compare: xoá một tấm không thoát cả màn | OK | — |
| V3 | M-17 · Photo Info trên iPad | OK | Cột inspector bên phải ở regular width (khác đề xuất ban đầu) |
| V4 | M-18, M-19 · Thứ tự Photo Info và chạm-để-ẩn chrome | OK | — |
| V5 | M-20 · Duo cover: thùng rác gần ngón cái nhất | OK | — |
| S1 | M-21 · Lọc theo Camera/Lens từ menu Filter | OK | Submenu Camera ▸ / Lens ▸ |
| S2 | M-22 · Từ không hiểu ('night') bị đổi thành tìm theo tên file | OK | Thêm trường timeOfDay (night, golden hour) (khác đề xuất ban đầu) |
| S3 | M-23 · Capsule '85mm' nói rõ tiêu cự thật hay tương đương | Không OK | — |
| S4 | M-25 · Rule builder gọn hơn trên màn thấp | OK | — |
| S5 | M-27 · Lọc ảnh thiếu dữ liệu (không vị trí, không lens, không ngày) | OK | — |
| F1 | M-31 · Onboarding báo trước hộp quyền | OK | — |
| F2 | M-32 · Trạng thái 'đang index' ở Statistics, Duplicates, Search | OK | — |
| F3 | Bỏ sót · Board cho Limited Access, bị từ chối, iCloud offline | OK | — |
| H1 | M-37 · Resize xong thì Share được ngay | OK | — |
| H2 | M-36 · Tên mức Share đọc ngược trong một ca | OK | — |
| H3 | M-40 · Upload dừng khi app ra nền | OK | Làm BGContinuedProcessingTask luôn (khác đề xuất ban đầu) |
| H4 | M-06, M-41, M-42 · Sửa vặt màn server | OK | — |
| H5 | M-43 · Uploaded to Server: Free Up Space có con số | OK | — |
| Z1 | M-45 · Nút chính của Compress và Collage Export | OK | Hai pane ở regular width (khác đề xuất ban đầu) |
| Z2 | M-46…49 · Lưới thay cho thẻ full-width trên iPad | OK | — |
| Z3 | M-52 · Màn thấp: 669pt nhận metrics của iPad | OK | Một environment isShortWindow + 8 điểm gọi (khác đề xuất ban đầu) |
| Z4 | M-53 · Widget editor trên Duo | OK | — |
| Z5 | M-50 · Bàn phím iPad trong Viewer | OK | — |
| C1 | M-72 · Vuốt nhầm làm mất form đang nhập | OK | — |
| C2 | M-61 · Chart editor: Save xám dù tên gợi ý đã hiện | OK | — |
| C3 | M-62 · Màu chart: indigo hay amber | OK | Giữ indigo, sửa DESIGN (khác đề xuất ban đầu) |
| C4 | M-60 · Bar chart vẽ hai lần cùng dữ liệu | OK | — |
| C5 | M-67 · Collections: 'My Albums ›' mở lưới đầy đủ | OK | — |
| C6 | M-68, M-69, M-76 · Từ ngữ và glyph | OK | — |
| P1 | Bỏ sót · Review dark mode và accessibility | OK | — |
| P2 | Bỏ sót · Chấm sao / Pick / Reject chưa có board | OK | — |
| P3 | Bỏ sót · Chạy vòng lõi trên thư viện thật | OK | — |
| P4 | 15 mục challenger loại | OK | — |
| P5 | Cách đi vào code | OK | Một /intent 'UI review 2/10' cho tất cả (khác đề xuất ban đầu) |

## Q1 — M-14 · Photo Info và Burst có nút Done
- **Chốt:** Thêm toolbar Done cho MetadataPanel và sheet Burst. Ghi luật mới vào DESIGN.md §10.4: mọi .sheet có nút đóng nhìn thấy được.
- **Vì sao:** Trên Duo inner sheet thành toàn màn (UIKit bỏ detent ở compact height) mà không có nút đóng; người không biết vuốt xuống là kẹt. Tốn 0pt.
- **Lịch sử:** vòng 1 — OK.

## Q2 — M-10 · Lỗi Favorite/Delete ở Viewer và Compare phải hiện ra
- **Chốt:** Đưa favorite/delete của Viewer và Compare qua AssetActionsCoordinator (đã có alert sẵn); tách 'người dùng huỷ' khỏi 'lỗi'.
- **Vì sao:** catch {} rỗng: bấm tim hay xoá thất bại (iCloud, quyền) thì không có gì xảy ra, người dùng tưởng đã xong.
- **Lịch sử:** vòng 1 — OK.

## Q3 — M-26 · Dòng gợi ý 'Try:' đang là tiếng Việt cứng trong UI tiếng Anh
- **Chốt:** Đổi thành 'Try: Fukuoka · f > 1.2 · ISO over 3200 · before 2020' qua String Catalog.
- **Lịch sử:** vòng 1 — OK.

## Q4 — M-58 · Số trong Statistics có dấu phân cách hàng nghìn
- **Chốt:** Dùng .formatted() cho đếm và phần trăm theo locale ('22,640' cạnh trục '25,000').
- **Lịch sử:** vòng 1 — OK.

## Q5 — M-59 · Thêm chart Top Lens vào bộ mặc định
- **Chốt:** Seed thêm Top Lens, tăng currentSeedGeneration (app chưa release, không migration).
- **Vì sao:** 'Ống kính nào tôi dùng nhiều nhất' là câu hỏi đầu tiên của người chụp (persona Linh, review Lightroom); bộ mặc định hiện chỉ có Body + Lens.
- **Lịch sử:** vòng 1 — OK.

## Q6 — M-07 · Xoá kết nối server dùng .alert thay confirmationDialog
- **Chốt:** Đổi 3 chỗ sang .alert 2 nút (Delete đỏ + Cancel) và sửa DESIGN §11 cho khớp §10.5.
- **Vì sao:** Trên iOS 26 confirmationDialog ẩn nút Cancel, chỉ còn nút đỏ — đúng ở thao tác xoá kết nối có mật khẩu. DESIGN §10.5 cấm, §11 lại bắt dùng: tài liệu tự mâu thuẫn.
- **Lịch sử:** vòng 1 — OK.

## Q7 — M-16 · Đóng Viewer thì lưới cuộn tới ảnh vừa xem
- **Chốt:** onDismiss của fullScreenCover đẩy một token cuộn tới asset cuối cùng (như jumpToNewestToken); chưa làm zoom-transition.
- **Vì sao:** Thao tác dùng nhiều nhất app: lướt 40 ảnh trong viewer rồi đóng, lưới vẫn đứng chỗ cũ, phải tự tìm lại.
- **Lịch sử:** vòng 1 — OK.

## Q8 — Nhóm nhỏ còn lại (M-09, M-56, M-75, M-78, M-87)
- **Chốt:** Cancel quét Duplicates bỏ role destructive; OnThisDay date picker detents [.height(440), .large]; vùng chạm 44pt cho nút xoá điều kiện và ⋯ của chart card; accessibilityLabel cho slider Quality; thêm một dòng kiểm vào /release-check.
- **Lịch sử:** vòng 1 — OK.

## D1 — M-01 · Merge All Groups ghi vào thư viện trước khi xác nhận
- **Chốt:** Chỉ cho Merge ở chế độ Exact (ẩn ở Similar/Series); một .alert ghi số nhóm và 'Nothing is deleted until you tap Delete'; bỏ try?, lỗi hiện qua alert.
- **Vì sao:** mergeAll ghi favorite, vị trí, ngày chụp vào Photos ngay, nuốt lỗi bằng try?, và chạy cả ở Similar/Series (ở đó dời ngày là sai thật). Huỷ xoá thì thay đổi vẫn ở lại trong thư viện thật — ba reviewer độc lập cùng chỉ ra.
- **Đã cân nhắc:** Dời việc chép metadata vào cùng giao dịch xoá (Phải giữ danh sách chờ chép qua đổi tab/huỷ, Đảo FS-06.06 §8); Giữ hành vi, chỉ thêm alert (Similar/Series vẫn dời ngày sai)
- **Lịch sử:** vòng 1 — OK.

## D2 — M-03 · Dấu xoá ở Duplicates mất khi đổi tab/Back; đánh dấu được cả nhóm
- **Chốt:** Giữ dấu trong bộ nhớ qua đổi chế độ/tab, chỉ lọc theo ảnh còn sống lúc xoá; chặn (hoặc cảnh báo) khi mọi bản trong một nhóm bị đánh dấu.
- **Vì sao:** Đúng review 'mất 4 giờ đánh dấu' của Gemini. Đánh dấu hết cả nhóm là xoá mất mọi bản.
- **Đã cân nhắc:** Lưu xuống DB/UserDefaults (Thêm một bảng trạng thái nháp, chưa ai đòi, Phải dọn khi ảnh đổi)
- **Lịch sử:** vòng 1 — OK.

## D3 — M-04 · Ô ảnh trùng cho thấy bản nào đáng giữ
- **Chốt:** Hàng glyph 12pt (favorite, đã chỉnh, RAW, Live) trên mỗi ô; thứ tự giữ ưu tiên đã chỉnh > favorite > lớn nhất. Chưa làm 'nằm trong album nào' (M, đảo FS-06.06 §8).
- **Vì sao:** Không biết bản nào đã chỉnh, là favorite, là RAW; bản được giữ là file lớn nhất nên bản gốc chưa chỉnh thắng bản đã chỉnh.
- **Lịch sử:** vòng 1 — OK.

## D4 — M-02 · Resize với Delete Originals bật sẵn
- **Chốt:** Giữ mặc định bật. Nút đổi chữ 'Resize 8 Photos and Delete Originals' khi bật; xong thì toast 3s 'N saved · X MB freed · originals in Recently Deleted'. Cùng lúc sửa chữ trắng trên amber thành đen (M-79, 2.4:1).
- **Vì sao:** Bật sẵn là có chủ ý (FS-03.07 §2) nhưng nút chính không nói sẽ xoá bản gốc, và chạy xong màn đóng im lặng — Minh không biết ảnh gốc đã vào Recently Deleted.
- **Đã cân nhắc:** Mặc định tắt (Thư viện dư bản trùng sau mỗi lần nén, Đảo FS-03.07 §2)
- **Lịch sử:** vòng 1 — OK.

## D5 — M-08 · Hide nói tìm lại ở đâu
- **Chốt:** Toast 4s '12 photos hidden · Find them in Photos > Hidden'. Không làm Undo (cần giữ PHAsset, chưa thử trên máy).
- **Lịch sử:** vòng 1 — OK.

## V1 — M-13 · Compare zoom 5× không soi được độ nét
- **Chốt:** Khi zoom > 1.5× thì xin bản độ phân giải cao cho vùng đang xem, cạnh dài tối đa ~3000px, chỉ pane đang chạm, allowNetwork theo Optimize Storage. Nhờ perf-profiler + memory-leak kiểm.
- **Vì sao:** Mỗi pane chỉ xin ảnh cỡ màn hình rồi phóng 5×: hai tấm gần giống nhau nhoè như nhau, nên không chọn được tấm nét hơn — đúng lý do màn tồn tại (persona Linh, blocker).
- **Đã cân nhắc:** Giải mã ảnh gốc cho pane đang zoom (4 pane × ảnh 45MP vượt bộ nhớ, Chậm với ảnh iCloud); Giữ như FS-01.08 §6 (Màn không làm được việc chính)
- **Lịch sử:** vòng 1 — OK.

## V2 — M-15 · Compare: xoá một tấm không thoát cả màn
- **Chốt:** Còn ≥ 2 thẻ thì ở lại màn; thêm hint 'Touch and hold to keep only this one'. Giữ hành vi 'chạm = đánh dấu' và nút xoá ở trên (khung tầng D §10.3).
- **Vì sao:** Xoá 1 trong 4 tấm thì màn đóng luôn, phải chọn lại từ đầu để so tiếp 3 tấm còn lại.
- **Lịch sử:** vòng 1 — OK.

## V3 — M-17 · Photo Info trên iPad
- **Chốt:** Ở regular width (iPad, Duo inner), Photo Info là cột inspector bên phải cạnh ảnh thay vì sheet; compact giữ sheet có Done (Q1).
- **Vì sao:** Sheet 700pt che đúng tấm ảnh đang đọc EXIF; thanh thông tin là một nút rộng 1280pt cho một dòng chữ.
- **Đã cân nhắc:** Done + maxWidth 520 (Sheet vẫn che ảnh)
- **Lịch sử:** vòng 1 — OK.

## V4 — M-18, M-19 · Thứ tự Photo Info và chạm-để-ẩn chrome
- **Chốt:** Camera & Lens lên trước bản đồ trong Photo Info (0pt). Chạm-để-ẩn chrome cho ảnh tĩnh để sau (thêm trễ 0.25s cho single tap).
- **Lịch sử:** vòng 1 — OK.

## V5 — M-20 · Duo cover: thùng rác gần ngón cái nhất
- **Chốt:** Không đổi (challenger): đảo Delete/Share riêng cho Duo trái quy ước Photos, thêm nhánh layout cho một thiết bị, và thùng rác đã có hộp xác nhận hệ thống.
- **Lịch sử:** vòng 1 — OK.

## S1 — M-21 · Lọc theo Camera/Lens từ menu Filter
- **Chốt:** Thêm 'Camera ▸' và 'Lens ▸' (top theo số ảnh) vào phần Filter của menu, chọn xong thành token trong thanh lọc.
- **Vì sao:** Menu Filter của Library không có Camera/Lens; người không biết cú pháp search phải đi qua Advanced Search. Thread Adobe từ 2018 vẫn có người xin đúng điều này.
- **Đã cân nhắc:** Thêm cột lọc 320pt cạnh lưới trên iPad (Ăn 3 cột lưới, iPhone vẫn cần submenu (luật iPad ↔ phone))
- **Lịch sử:** vòng 1 — OK.

## S2 — M-22 · Từ không hiểu ('night') bị đổi thành tìm theo tên file
- **Chốt:** Thêm trường timeOfDay (night, golden hour, blue hour…) tính lúc index từ giờ chụp + vị trí; SearchParser hiểu "night"; chip vẫn nói rõ từ nào không hiểu.
- **Vì sao:** Linh gõ '85mm night' ra 0 ảnh mà không hiểu vì sao: 'night' lặng lẽ thành điều kiện Filename contains.
- **Đã cân nhắc:** Nói rõ trên chip (Vẫn không tìm được ảnh đêm)
- **Lịch sử:** vòng 1 — OK.

## S3 — M-23 · Capsule '85mm' nói rõ tiêu cự thật hay tương đương
- **Chốt:** Bỏ.
- **Lịch sử:** vòng 1 — Không OK.

## S4 — M-25 · Rule builder gọn hơn trên màn thấp
- **Chốt:** Gộp Media Type + Match vào một hàng (lấy lại ~200pt); đưa 'Matches N photos' lên gần nút Search. Áp cho Advanced Search, Smart Album editor, Chart editor.
- **Vì sao:** Trên Duo inner và iPhone, Media Type và Match chiếm 2 hàng riêng; số ảnh khớp nằm ở footer cuối danh sách, không thấy khi đang sửa.
- **Lịch sử:** vòng 1 — OK.

## S5 — M-27 · Lọc ảnh thiếu dữ liệu (không vị trí, không lens, không ngày)
- **Chốt:** Toán tử isMissing cho mọi trường; Location có 'Has / No Location'. Thanh 'Unknown' trong chart chạm vào mở lưới với điều kiện đó. Làm sau lô đầu.
- **Vì sao:** Câu hỏi dọn thư viện thật; app đã có Adjust Date/Location để sửa nhưng không tìm được ảnh cần sửa. Một người dùng 78k ảnh bỏ app khác vì thiếu điều này.
- **Lịch sử:** vòng 1 — OK.

## F1 — M-31 · Onboarding báo trước hộp quyền
- **Chốt:** Một footnote trên nút Continue: 'Next, iOS asks for access — choose Allow Full Access so ShotDex can read every photo's camera info.' Nút Continue maxWidth 480 ở regular (đang 1320pt trên iPad).
- **Vì sao:** Linh suýt chọn Limited theo thói quen. Chọn Limited thì Search, Statistics, Duplicates trả thiếu mà chỉ có một banner ở Library.
- **Lịch sử:** vòng 1 — OK.

## F2 — M-32 · Trạng thái 'đang index' ở Statistics, Duplicates, Search
- **Chốt:** Nhãn 'Still reading photo info · N%' ở đầu Statistics/Duplicates/Search khi isIndexing; làm mới Statistics khi index xong. Không gắn nhãn 'Partial' lên từng chart.
- **Vì sao:** Lần đầu mở, Duplicates bảo 'index thư viện thủ công' (không có nút đó), Statistics đứng số cũ tới khi mở lại.
- **Lịch sử:** vòng 1 — OK.

## F3 — Bỏ sót · Board cho Limited Access, bị từ chối, iCloud offline
- **Chốt:** Vẽ 3 trạng thái (Limited, Denied, đang chờ iCloud) cho Library + Statistics trên cả 4 thiết bị, rồi chạy ux-reviewer trên đó.
- **Vì sao:** Challenger: không board nào vẽ các trạng thái này, nên không ai review được người dùng Limited thấy gì ở Statistics/Duplicates/Search.
- **Lịch sử:** vòng 1 — OK.

## H1 — M-37 · Resize xong thì Share được ngay
- **Chốt:** Sau khi lưu, nút 'Share 8 Photos' dùng createdAssetIDs; Collage Export thêm 'Share…'. Làm cùng D4.
- **Vì sao:** Người chụp resize để gửi đi; hiện xong là 'saved to Photos', phải chọn lại đúng các bản copy trong lưới.
- **Lịch sử:** vòng 1 — OK.

## H2 — M-36 · Tên mức Share đọc ngược trong một ca
- **Chốt:** Giữ ba tên mức đã chốt (FS-08.06 §4). Chỉ sửa header/phụ đề cho ca đó, ví dụ 'Sharing: No Metadata' và phụ đề hàng 'Adds camera & lens info, no location'.
- **Vì sao:** Khi mặc định là No Metadata, header 'Metadata removed' đứng cạnh hàng 'Share Without Location' (hàng này thêm lại thông tin máy) — Minh đọc ba lần vẫn không chắc.
- **Lịch sử:** vòng 1 — OK.

## H3 — M-40 · Upload dừng khi app ra nền
- **Chốt:** Làm upload nền thật bằng BGContinuedProcessingTask trên iOS 26 (pre-26 giữ màn hình sáng như cũ); sửa FS-15 README:41.
- **Vì sao:** Ngày cưới 40–60 GB: phải để iPad sáng màn hàng giờ. Review PhotoSync/Remo/Gemini đều than đúng điều này. Nhưng FS-15 đã chốt 'không chạy nền'.
- **Đã cân nhắc:** Banner Resume ngay + /intent chạy nền (Chưa chạy nền thật); Giữ nguyên FS-15 (Mất người dùng chụp sự kiện)
- **Lịch sử:** vòng 1 — OK.

## H4 — M-06, M-41, M-42 · Sửa vặt màn server
- **Chốt:** Công tắc 'Apply to Remaining Conflicts' lên trên ba nút Replace/Skip/Keep Both; 'Add Connection…' ra khỏi giữa section Connection; Server Browser đưa Select ra toolbar và đổi glyph 'In Library' cho khỏi giống dấu đã chọn.
- **Lịch sử:** vòng 1 — OK.

## H5 — M-43 · Uploaded to Server: Free Up Space có con số
- **Chốt:** Hàng đầu 'Free Up Space — 214 photos · ~4.2 GB'; tắt thì ghi lý do; toast sau khi xoá.
- **Lịch sử:** vòng 1 — OK.

## Z1 — M-45 · Nút chính của Compress và Collage Export
- **Chốt:** Compress và Collage Export có hai pane ở regular width: preview trái, tuỳ chọn + nút chính phải; compact ghim nút chính vào safeAreaInset.
- **Vì sao:** Trên Duo inner nút Resize nằm 130–230pt dưới đáy; trên iPhone nó bắt đầu dưới home indicator.
- **Đã cân nhắc:** Ghim nút, đo lại (iPad vẫn cột 700pt giữa màn)
- **Lịch sử:** vòng 1 — OK.

## Z2 — M-46…49 · Lưới thay cho thẻ full-width trên iPad
- **Chốt:** Trips adaptive(320…440); Duplicates LazyVGrid adaptive(420) + nút Delete tối đa 360pt; Search Recents adaptive + thumbnail theo cạnh thật; Collage Layout inspector thành lưới 4 cột ở regular.
- **Vì sao:** Trips là thẻ 1344×160 (8.4:1), Duplicates là card 1344pt rỗng 80%, Search Recents phóng thumbnail ~2.7× — màn điện thoại kéo giãn, trái §10.1c.
- **Lịch sử:** vòng 1 — OK.

## Z3 — M-52 · Màn thấp: 669pt nhận metrics của iPad
- **Chốt:** Một environment isShortWindow (chiều cao cửa sổ < ngưỡng) đặt ở RootTabView, mọi chỗ đang chọn metrics theo size class đọc thêm cờ này.
- **Vì sao:** Cả app chỉ hỏi horizontalSizeClass (verticalSizeClass xuất hiện 0 lần): Duo inner nhận hero 260, tile 192 trên chiều cao 669, còn chỗ cho đúng một hàng album.
- **Đã cân nhắc:** Công thức theo chiều cao ở từng chỗ (Mỗi chỗ tự nhớ làm)
- **Lịch sử:** vòng 1 — OK.

## Z4 — M-53 · Widget editor trên Duo
- **Chốt:** Preview tối đa 158pt cao trên màn thấp; chọn cỡ Large qua popover. Hạ từ blocker xuống: màn dùng một lần lúc cài.
- **Lịch sử:** vòng 1 — OK.

## Z5 — M-50 · Bàn phím iPad trong Viewer
- **Chốt:** Esc đóng, ←/→ chuyển ảnh trong Viewer, Compare, Compress, Trim. Không làm ⌘A/⌘F.
- **Lịch sử:** vòng 1 — OK.

## C1 — M-72 · Vuốt nhầm làm mất form đang nhập
- **Chốt:** isDirty + interactiveDismissDisabled + alert Discard / Keep Editing cho 4 sheet đó.
- **Vì sao:** Smart Album editor, Chart editor, form kết nối (có mật khẩu), Advanced Search vuốt xuống là mất; editor ảnh/Video Studio/Collage thì đã chặn.
- **Lịch sử:** vòng 1 — OK.

## C2 — M-61 · Chart editor: Save xám dù tên gợi ý đã hiện
- **Chốt:** canSave bỏ điều kiện tên; tên rỗng thì dùng tên gợi ý. Không ghim preview lượt này.
- **Lịch sử:** vòng 1 — OK.

## C3 — M-62 · Màu chart: indigo hay amber
- **Chốt:** Giữ chart indigo, sửa DESIGN.md (bỏ "charts" khỏi danh sách dùng accent ở §10.6 và AppAccentTheme).
- **Vì sao:** DESIGN nói chart dùng accent amber, code ChartPalette dùng indigo. Một bên phải sửa, nếu không reviewer nào cũng sẽ báo lại.
- **Đã cân nhắc:** Series đầu là amber (Phải kiểm tương phản amber trên nền sáng)
- **Lịch sử:** vòng 1 — OK.

## C4 — M-60 · Bar chart vẽ hai lần cùng dữ liệu
- **Chốt:** Khi topN ≤ 5 ghi tên lên thanh và bỏ danh sách nhãn bên dưới; giữ Swift Charts.
- **Lịch sử:** vòng 1 — OK.

## C5 — M-67 · Collections: 'My Albums ›' mở lưới đầy đủ
- **Chốt:** Tiêu đề section 'My Albums ›' push tới lưới dọc (2 cột iPhone, adaptive iPad) có sort; bổ sung 'See All' vào DESIGN §10.1d.
- **Vì sao:** Người có 80 album không thấy hết trong một hàng cuộn ngang; tiêu đề section không chạm được.
- **Lịch sử:** vòng 1 — OK.

## C6 — M-68, M-69, M-76 · Từ ngữ và glyph
- **Chốt:** Một tên cho album người dùng (My Albums) ở mọi chỗ; 'Cloud' bỏ icon iCloud (đó là Dropbox/Drive); nút ⇅ của Statistics vào menu 'Add Chart / Reorder'.
- **Lịch sử:** vòng 1 — OK.

## P1 — Bỏ sót · Review dark mode và accessibility
- **Chốt:** Chạy design-reviewer trên bản tối (đã render sẵn ở build/design/app/render-dark/) và a11y-voiceover trên code các màn tầng A/B.
- **Vì sao:** Mọi reviewer chỉ xem bản sáng; không ai chạy VoiceOver/Dynamic Type. Người dùng app ảnh thường để chế độ tối; control tự vẽ (chip lọc, bar chart, vote) chưa có trạng thái đọc được.
- **Lịch sử:** vòng 1 — OK.

## P2 — Bỏ sót · Chấm sao / Pick / Reject chưa có board
- **Chốt:** Vẽ board lưới có sao/cờ, viewer có hàng chấm, lượt Cull trên 4 thiết bị, chạy ux-reviewer, trước khi plan đó vào code.
- **Vì sao:** FS-01.12 và plan cull được viết hôm nay nhưng canvas chưa có màn nào; luật design ↔ code bắt phải có board trước khi code màn mới.
- **Lịch sử:** vòng 1 — OK.

## P3 — Bỏ sót · Chạy vòng lõi trên thư viện thật
- **Chốt:** Một kịch bản Tools/ui-drive Statistics → drill-down → Library → Share trên máy có thư viện lớn, ghi số chạm và thời gian.
- **Vì sao:** Review chấm từng màn; chưa ai đo 'ống kính nào tôi dùng nhiều nhất năm ngoái → xem các khung đó → xuất' bằng số chạm và giây trên 55k ảnh.
- **Lịch sử:** vòng 1 — OK.

## P4 — 15 mục challenger loại
- **Chốt:** Bỏ: M-20 (đảo nút Duo cover), M-28 (gán lại lens cơ), M-29 (capsule thành token), M-38 (strip metadata video), M-44 (test ngầm khi Save), M-55, M-63 (round-robin Statistics), M-64, M-65 (dời Compare/Edit xuống đáy), M-70, M-73 (sheet chồng sheet thành push), M-77, M-80, M-81 (refactor nút/capsule), M-85 (nit spacing). Lý do từng mục trong challenge.md; chọn Sửa để giữ lại mục nào.
- **Lịch sử:** vòng 1 — OK.

## P5 — Cách đi vào code
- **Chốt:** Một /intent "UI review 2/10" cho cả 46 mục, rồi /spec với AC từng mục, /plan, mỗi AC một commit, /verify; mọi màn đổi thì sửa board cùng lượt.
- **Vì sao:** CLAUDE.md bắt tính năng mới đi /intent → /spec → /plan; phần lớn mục trên là sửa lỗi/hành vi nhỏ. Đi sai đường thì hoặc tốn ba tài liệu cho một dòng chữ, hoặc đổi hành vi mà docs không theo.
- **Đã cân nhắc:** Lô đầu qua /review-sweep, việc lớn qua /intent (Nhiều commit nhỏ)
- **Lịch sử:** vòng 1 — OK.
